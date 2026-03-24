import { api, DEFAULT_API_BASE, getApiBase, setApiBase } from './services/api.js?v=20260324c';
import { clearAuth, getAdminProfile, getToken, setAdminProfile, setToken } from './services/auth.js?v=20260324c';
import { showToast } from './components/toast.js?v=20260324c';
import { openConfirmModal, openDrawer, openFormModal } from './components/modal.js?v=20260324c';
import { renderMainLayout } from './layouts/main-layout.js?v=20260324c';
import { escapeHtml } from './models/serializers.js?v=20260324c';
import { getUiLang, setUiLang, t } from './services/i18n.js?v=20260324c';
import { tr } from './components/page-shell.js?v=20260324c';

import { renderDashboard } from './dashboard/page.js?v=20260324c';
import { renderOrders } from './orders/page.js?v=20260324c';
import { renderProducts } from './products/page.js?v=20260324c';
import { renderCategories } from './categories/page.js?v=20260324c';
import { renderDiscounts } from './discounts/page.js?v=20260324c';
import { renderUsers } from './users/page.js?v=20260324c';
import { renderNotifications } from './notifications/page.js?v=20260324c';
import { renderBanners } from './banners/page.js?v=20260324c';
import { renderFaq } from './faq/page.js?v=20260324c';
import { renderSettings } from './settings/page.js?v=20260324c';
import { renderProfile } from './profile/page.js?v=20260324c';

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
const SIDEBAR_COLLAPSED_KEY = 'sushixl_admin_sidebar_collapsed';
const AUTH_UI_VERSION_KEY = 'sushixl_admin_ui_auth_version';
const AUTH_UI_VERSION = '20260324c';

function renderBootFailure(error) {
  const uiLang = getUiLang();
  const message = String(error?.message || error || 'Unknown startup error');
  console.error('Admin panel boot failed:', error);
  appRoot.innerHTML = `
    <div class="login-shell">
      <section class="login-stage">
        <div class="login-panel login-card" style="max-width:720px;margin:auto;">
          <div class="login-copy-block">
            <h2>${escapeHtml(tr(uiLang, 'Admin failed to load', 'Админ-панель не загрузилась', 'Admin panel yuklanmadi'))}</h2>
            <p>${escapeHtml(tr(uiLang, 'The admin frontend hit a runtime error. Reload the page after the new bundle is served.', 'Фронтенд админ-панели столкнулся с runtime-ошибкой. Перезагрузите страницу после получения нового бандла.', 'Admin frontend runtime xatoga uchradi. Yangi bundle yuklangandan keyin sahifani qayta oching.'))}</p>
          </div>
          <div class="inline-error" aria-live="polite">${escapeHtml(message)}</div>
        </div>
      </section>
    </div>
  `;
}

async function bootApp() {
  try {
    await renderApp();
  } catch (error) {
    renderBootFailure(error);
  }
}

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

function getSidebarCollapsed() {
  return localStorage.getItem(SIDEBAR_COLLAPSED_KEY) === '1';
}

function setSidebarCollapsed(value) {
  localStorage.setItem(SIDEBAR_COLLAPSED_KEY, value ? '1' : '0');
}

function renderLogin(errorMessage = '', remembered = {}) {
  const safeErrorMessage = shouldSuppressLoginError(errorMessage) ? '' : errorMessage;
  const uiLang = getUiLang();
  const adminSuiteLabel = tr(uiLang, 'Admin Suite', 'Админ-панель', 'Admin paneli');
  appRoot.innerHTML = `
    <div class="login-shell">
      <section class="login-stage">
        <div class="login-panel login-brand-panel">
          <div class="login-brand-top">
            <div class="login-logo-wrap">
              <img src="./assets/app-logo.png" alt="Sushi XL logo" class="login-logo-img" />
            </div>
            <div>
              <span class="login-eyebrow">Sushi XL</span>
              <h1>${escapeHtml(adminSuiteLabel)}</h1>
            </div>
          </div>
          <p class="login-brand-copy">${escapeHtml(tr(uiLang, 'Poster-connected control center for catalog, campaigns, staff operations, and brand management.', 'Poster-подключенный центр управления каталогом, кампаниями, персоналом и брендом.', 'Katalog, kampaniyalar, xodimlar operatsiyalari va brend boshqaruvi uchun Poster bilan bog‘langan markaz.'))}</p>
          <div class="login-feature-list">
            <article class="login-feature-card">
              <span>${escapeHtml(tr(uiLang, 'Order visibility', 'Видимость заказов', 'Buyurtma ko‘rinishi'))}</span>
              <strong>${escapeHtml(tr(uiLang, 'Monitor Poster-synced order flow without introducing fake admin actions.', 'Отслеживайте поток заказов из Poster без ложных действий администратора.', 'Poster orqali sinxronlangan buyurtmalar oqimini soxta admin amallarisiz kuzating.'))}</strong>
            </article>
            <article class="login-feature-card">
              <span>${escapeHtml(tr(uiLang, 'Menu command', 'Управление меню', 'Menyu boshqaruvi'))}</span>
              <strong>${escapeHtml(tr(uiLang, 'Manage products, categories, discounts, banners, notifications, and support content from one suite.', 'Управляйте товарами, категориями, скидками, баннерами, уведомлениями и контентом поддержки из одного интерфейса.', 'Mahsulotlar, kategoriyalar, chegirmalar, bannerlar, bildirishnomalar va yordam kontentini bitta interfeysdan boshqaring.'))}</strong>
            </article>
          </div>
        </div>

        <div class="login-panel login-card">
          <div class="login-card-topbar">
            <span class="login-panel-label">${escapeHtml(tr(uiLang, 'Secure entry', 'Безопасный вход', 'Xavfsiz kirish'))}</span>
            <label class="field compact-field auth-language-switcher">
              <span>${escapeHtml(t('language', uiLang))}</span>
              <select id="login-language-switcher" aria-label="${escapeHtml(t('language', uiLang))}">
                <option value="en" ${uiLang === 'en' ? 'selected' : ''}>ENG</option>
                <option value="ru" ${uiLang === 'ru' ? 'selected' : ''}>RUS</option>
                <option value="uz" ${uiLang === 'uz' ? 'selected' : ''}>UZB</option>
              </select>
            </label>
          </div>
          <div class="login-copy-block">
            <h2>${escapeHtml(t('login_title', uiLang))}</h2>
            <p>${escapeHtml(t('login_subtitle', uiLang))}</p>
          </div>
          <div class="login-status-note">${escapeHtml(tr(uiLang, 'Use your existing administrator credentials. No extra auth steps are shown unless the backend supports them.', 'Используйте существующие учетные данные администратора. Дополнительные шаги авторизации не показываются без поддержки бэкенда.', 'Mavjud administrator ma’lumotlari bilan kiring. Backend qo‘llab-quvvatlamasa, qo‘shimcha autentifikatsiya bosqichlari ko‘rsatilmaydi.'))}</div>
          ${safeErrorMessage ? `<div class="inline-error" aria-live="polite">${escapeHtml(safeErrorMessage)}</div>` : '<div class="login-feedback" aria-live="polite"></div>'}
          <form id="login-form" class="login-form">
            <label class="field">
              <span>${escapeHtml(t('login_email', uiLang))}</span>
              <input name="email" autocomplete="username" required value="${escapeHtml(remembered.email || '')}" />
            </label>
            <label class="field">
              <span>${escapeHtml(t('login_password', uiLang))}</span>
              <div class="password-field">
                <input name="password" type="password" autocomplete="current-password" required minlength="8" />
                <button type="button" class="input-action" id="toggle-password">${escapeHtml(tr(uiLang, 'Show', 'Показать', 'Ko‘rsatish'))}</button>
              </div>
            </label>
            <button type="submit" class="btn btn-primary login-btn" id="login-submit">${escapeHtml(t('login_submit', uiLang))}</button>
          </form>
        </div>
      </section>
    </div>
  `;

  const form = appRoot.querySelector('#login-form');
  const submitButton = appRoot.querySelector('#login-submit');
  const passwordInput = form.password;
  const togglePasswordButton = appRoot.querySelector('#toggle-password');
  const languageSwitcher = appRoot.querySelector('#login-language-switcher');

  languageSwitcher?.addEventListener('change', (event) => {
    setUiLang(event.target.value);
    renderLogin(safeErrorMessage, { email: form.email.value.trim() });
  });

  togglePasswordButton?.addEventListener('click', () => {
    const nextVisible = passwordInput.type === 'password';
    passwordInput.type = nextVisible ? 'text' : 'password';
    togglePasswordButton.textContent = nextVisible
      ? tr(uiLang, 'Hide', 'Скрыть', 'Yashirish')
      : tr(uiLang, 'Show', 'Показать', 'Ko‘rsatish');
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const email = form.email.value.trim();
    const password = form.password.value;
    submitButton.disabled = true;
    form.querySelectorAll('input, button, select').forEach((node) => {
      node.disabled = true;
    });
    submitButton.textContent = tr(uiLang, 'Signing in...', 'Вход...', 'Kirilmoqda...');

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
      renderLogin(error.message || t('login_failed', uiLang), { email });
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
    sidebarCollapsed: getSidebarCollapsed(),
  });

  const shell = appRoot.querySelector('.admin-shell');
  const sidebarToggle = document.getElementById('sidebar-toggle');
  const sidebarScrim = document.getElementById('sidebar-scrim');
  const closeSidebar = () => shell?.classList.remove('is-sidebar-open');
  const isCompactViewport = () => window.matchMedia('(max-width: 1080px)').matches;

  sidebarToggle?.addEventListener('click', () => {
    if (isCompactViewport()) {
      shell?.classList.toggle('is-sidebar-open');
      return;
    }
    const next = !shell?.classList.contains('is-collapsed');
    shell?.classList.toggle('is-collapsed', next);
    setSidebarCollapsed(next);
  });
  sidebarScrim?.addEventListener('click', closeSidebar);
  appRoot.querySelectorAll('.side-link').forEach((link) => {
    link.addEventListener('click', closeSidebar);
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
    openDrawer,
    navigate,
    refreshApp: renderApp,
    uiLang,
    t: (key) => t(key, uiLang),
  });
}

async function renderApp() {
  const storedAuthUiVersion = sessionStorage.getItem(AUTH_UI_VERSION_KEY);
  if (storedAuthUiVersion !== AUTH_UI_VERSION) {
    clearAuth();
    sessionStorage.setItem(AUTH_UI_VERSION_KEY, AUTH_UI_VERSION);
  }

  if (!authExpiryHandlerBound) {
    authExpiryHandlerBound = true;
    window.addEventListener('admin-auth-expired', () => {
      clearAuth();
      renderLogin();
    });
  }

  if (!getAdminProfile() && !getToken()) {
    renderLogin();
    return;
  }

  await renderAuthed();
}

window.addEventListener('error', (event) => {
  renderBootFailure(event.error || event.message || 'Unknown window error');
});

window.addEventListener('unhandledrejection', (event) => {
  renderBootFailure(event.reason || 'Unhandled promise rejection');
});

window.addEventListener('hashchange', () => {
  bootApp();
});

bootApp();
