import { api, DEFAULT_API_BASE, getApiBase, setApiBase } from './services/api.js';
import { clearAuth, getAdminProfile, getToken, setAdminProfile, setToken } from './services/auth.js';
import { showToast } from './components/toast.js';
import { openConfirmModal, openFormModal } from './components/modal.js';
import { renderMainLayout } from './layouts/main-layout.js';
import { escapeHtml } from './models/serializers.js';
import { getUiLang, setUiLang, t } from './services/i18n.js';

import { renderDashboard } from './dashboard/page.js';
import { renderOrders } from './orders/page.js';
import { renderProducts } from './products/page.js';
import { renderCategories } from './categories/page.js';
import { renderDiscounts } from './discounts/page.js';
import { renderUsers } from './users/page.js';
import { renderNotifications } from './notifications/page.js';
import { renderBanners } from './banners/page.js';
import { renderFaq } from './faq/page.js';
import { renderSettings } from './settings/page.js';
import { renderProfile } from './profile/page.js';

const routes = {
  dashboard: renderDashboard,
  orders: renderOrders,
  products: renderProducts,
  categories: renderCategories,
  discounts: renderDiscounts,
  users: renderUsers,
  notifications: renderNotifications,
  banners: renderBanners,
  faq: renderFaq,
  settings: renderSettings,
  profile: renderProfile,
};

const appRoot = document.getElementById('app');
let authExpiryHandlerBound = false;

function shouldSuppressLoginError(message) {
  const normalized = String(message || '').trim().toLowerCase();
  if (!normalized) return true;
  return (
    normalized.includes('session expired') ||
    normalized.includes('invalid or expired access token') ||
    normalized.includes('сессия истекла') ||
    normalized.includes('sessiya tugadi')
  );
}

function isAuthFailure(error) {
  const status = Number(error?.status);
  const text = String(error?.message || '').toLowerCase();
  if ([401, 403, 419].includes(status)) return true;
  return (
    text.includes('unauthorized') ||
    text.includes('forbidden') ||
    text.includes('expired access token') ||
    text.includes('session expired')
  );
}

function currentRoute() {
  const raw = location.hash.replace('#/', '').trim();
  if (!raw || !routes[raw]) return 'dashboard';
  return raw;
}

function navigate(route) {
  location.hash = `/${route}`;
}

function renderLogin(errorMessage = '') {
  const safeErrorMessage = shouldSuppressLoginError(errorMessage) ? '' : errorMessage;
  const uiLang = getUiLang();
  appRoot.innerHTML = `
    <div class="login-shell">
      <div class="login-card">
        <div class="login-logo-wrap">
          <img src="./assets/app-logo.png" alt="Sushi XL logo" class="login-logo-img" />
        </div>
        <h1>${escapeHtml(t('login_title', uiLang))}</h1>
        <p>${escapeHtml(t('login_subtitle', uiLang))}</p>
        ${safeErrorMessage ? `<div class="inline-error">${escapeHtml(safeErrorMessage)}</div>` : ''}
        <form id="login-form" class="login-form">
          <label class="field"><span>${escapeHtml(t('login_email', uiLang))}</span><input name="email" autocomplete="username" required /></label>
          <label class="field"><span>${escapeHtml(t('login_password', uiLang))}</span><input name="password" type="password" autocomplete="current-password" required minlength="8" /></label>
          <button type="submit" class="btn btn-primary login-btn">${escapeHtml(t('login_submit', uiLang))}</button>
        </form>
      </div>
    </div>
  `;

  const form = appRoot.querySelector('#login-form');
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const email = form.email.value.trim();
    const password = form.password.value;

    try {
      let session;
      try {
        session = await api.login(email, password);
      } catch (error) {
        const message = String(error?.message || '');
        if (
          getApiBase() !== DEFAULT_API_BASE &&
          (message.includes('Failed to fetch') ||
              message.includes('NetworkError') ||
              message.includes('Load failed'))
        ) {
          setApiBase('');
          session = await api.login(email, password);
        } else {
          throw error;
        }
      }
      if (!session?.access_token) {
        setToken('');
      } else {
        setToken(session.access_token);
      }
      setAdminProfile(session.admin || { fullName: email, email });
      showToast(t('signed_in', uiLang), 'success');
      navigate('dashboard');
      await renderApp();
    } catch (error) {
      renderLogin(error.message || t('login_failed', uiLang));
    }
  });
}

async function renderAuthed() {
  const token = getToken();
  try {
    let profile;
    try {
      profile = await api.getProfile(token);
    } catch (error) {
      const message = String(error?.message || '');
      if (
        getApiBase() !== DEFAULT_API_BASE &&
        (message.includes('Failed to fetch') ||
          message.includes('NetworkError') ||
          message.includes('Load failed'))
      ) {
        setApiBase('');
        profile = await api.getProfile(token);
      } else {
        throw error;
      }
    }
    if (profile) {
      setAdminProfile(profile);
    }
  } catch (error) {
    if (isAuthFailure(error)) {
      clearAuth();
      renderLogin();
      return;
    }
    renderLogin(error?.message || t('failed_connect_admin_api'));
    return;
  }

  const route = currentRoute();
  const admin = getAdminProfile() || {};
  const uiLang = getUiLang();
  appRoot.innerHTML = renderMainLayout({
    activeRoute: route,
    adminName: admin.fullName || admin.email || 'Admin',
    uiLang,
  });

  const uiLanguageSwitcher = document.getElementById('ui-language-switcher');
  if (uiLanguageSwitcher) {
    uiLanguageSwitcher.addEventListener('change', async (event) => {
      setUiLang(event.target.value);
      await renderApp();
    });
  }

  const logoutButton = document.getElementById('logout-btn');
  logoutButton.addEventListener('click', async () => {
    const confirmed = await openConfirmModal({
      title: t('logout_title', uiLang),
      message: t('logout_message', uiLang),
      confirmText: t('logout', uiLang),
      cancelText: t('cancel', uiLang),
    });
    if (!confirmed) return;
    try {
      await api.logout();
    } catch (_) {
      // Ignore logout transport errors and clear local auth state anyway.
    }
    clearAuth();
    renderLogin();
  });

  const pageRoot = document.getElementById('page-root');
  const renderPage = routes[route] || routes.dashboard;
  await renderPage({
    container: pageRoot,
    token,
    showToast,
    openFormModal,
    openConfirmModal,
    navigate,
    refreshApp: renderApp,
    uiLang,
    t: (key) => t(key, uiLang),
  });
}

async function renderApp() {
  if (!authExpiryHandlerBound) {
    authExpiryHandlerBound = true;
    window.addEventListener('admin-auth-expired', () => {
      clearAuth();
      renderLogin();
    });
  }
  await renderAuthed();
}

window.addEventListener('hashchange', () => {
  renderApp();
});

renderApp();
