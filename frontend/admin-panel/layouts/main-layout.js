import { escapeHtml } from '../models/serializers.js';
import { t } from '../services/i18n.js';
import { tr } from '../components/page-shell.js';

const NAV_ITEMS = [
  ['dashboard', 'dashboard', '01', ['Executive overview', 'Обзор показателей', 'Umumiy ko‘rinish']],
  ['orders', 'orders', '02', ['Poster monitor', 'Монитор Poster', 'Poster nazorati']],
  ['products', 'products', '03', ['Menu catalog', 'Каталог меню', 'Menyu katalogi']],
  ['categories', 'categories', '04', ['Menu structure', 'Структура меню', 'Menyu tuzilmasi']],
  ['discounts', 'discounts', '05', ['Campaigns', 'Кампании', 'Kampaniyalar']],
  ['users', 'users', '06', ['Customer base', 'Клиентская база', 'Mijozlar bazasi']],
  ['notifications', 'notifications', '07', ['Push center', 'Центр уведомлений', 'Bildirishnoma markazi']],
  ['banners', 'banners', '08', ['Hero placements', 'Баннеры', 'Banner joylashuvi']],
  ['faq', 'faq', '09', ['Support content', 'Поддержка', 'Yordam mazmuni']],
  ['settings', 'settings', '10', ['System rules', 'Системные правила', 'Tizim qoidalari']],
  ['profile', 'profile', '11', ['Admin account', 'Аккаунт администратора', 'Admin hisobi']],
];

export function renderMainLayout({ activeRoute, adminName, uiLang, sidebarCollapsed = false }) {
  const adminSuiteLabel = tr(uiLang, 'Admin Suite', 'Админ-панель', 'Admin paneli');
  const fullSuiteLabel = `Sushi XL ${adminSuiteLabel}`;
  const nav = NAV_ITEMS.map(([route, labelKey, indexLabel, hintCopy]) => {
    const active = activeRoute === route ? 'active' : '';
    return `
      <a href="#/${route}" class="side-link ${active}">
        <span class="side-link-index">${escapeHtml(indexLabel)}</span>
        <span class="side-link-copy">
          <strong>${escapeHtml(t(labelKey, uiLang))}</strong>
          <small>${escapeHtml(tr(uiLang, ...hintCopy))}</small>
        </span>
      </a>
    `;
  }).join('');

  const pageTitleKey = NAV_ITEMS.find(([route]) => route === activeRoute)?.[1] || 'dashboard';

  return `
    <div class="admin-shell ${sidebarCollapsed ? 'is-collapsed' : ''}">
      <button type="button" class="sidebar-scrim" id="sidebar-scrim" aria-label="${escapeHtml(tr(uiLang, 'Close navigation', 'Закрыть навигацию', 'Navigatsiyani yopish'))}"></button>
      <aside class="sidebar">
        <div class="sidebar-brand">
          <div class="brand brand--sidebar">
            <div class="brand-mark brand-logo-wrap">
              <img src="./assets/app-logo.png" alt="Sushi XL logo" class="brand-logo-img" />
            </div>
            <div>
              <div class="brand-title">Sushi XL</div>
              <div class="brand-sub">${escapeHtml(adminSuiteLabel)}</div>
            </div>
          </div>
          <div class="sidebar-brand-card">
            <p>${escapeHtml(tr(uiLang, 'Poster-connected operations', 'Операции с интеграцией Poster', 'Poster bilan bog‘langan operatsiyalar'))}</p>
            <strong>${escapeHtml(tr(uiLang, 'Orders are monitored here. Core intake stays in Poster.', 'Заказы отслеживаются здесь. Основной прием остается в Poster.', 'Buyurtmalar shu yerda kuzatiladi. Asosiy qabul Poster ichida qoladi.'))}</strong>
          </div>
        </div>
        <nav class="side-nav">${nav}</nav>
        <div class="sidebar-footer">
          <div class="sidebar-footer-card">
            <span>${escapeHtml(tr(uiLang, 'Current operator', 'Текущий оператор', 'Joriy operator'))}</span>
            <strong>${escapeHtml(adminName || 'Admin')}</strong>
          </div>
        </div>
      </aside>
      <div class="main-column">
        <header class="topbar">
          <div class="topbar-main">
            <div class="topbar-leading">
              <button type="button" id="sidebar-toggle" class="icon-btn" aria-label="${escapeHtml(tr(uiLang, 'Toggle navigation', 'Переключить навигацию', 'Navigatsiyani almashtirish'))}">
                &#9776;
              </button>
              <div>
                <span class="topbar-eyebrow">${escapeHtml(fullSuiteLabel)}</span>
                <h1>${escapeHtml(t(pageTitleKey, uiLang))}</h1>
              </div>
            </div>
            <p class="topbar-context">${escapeHtml(tr(uiLang, 'Premium restaurant operations workspace', 'Премиальное рабочее пространство для ресторанных операций', 'Restoran operatsiyalari uchun premium ish maydoni'))}</p>
          </div>
          <div class="topbar-actions">
            <label class="field compact-field topbar-language-field">
              <span>${escapeHtml(t('language', uiLang))}</span>
              <select id="ui-language-switcher" aria-label="${escapeHtml(t('language', uiLang))}">
                <option value="en" ${uiLang === 'en' ? 'selected' : ''}>ENG</option>
                <option value="ru" ${uiLang === 'ru' ? 'selected' : ''}>RUS</option>
                <option value="uz" ${uiLang === 'uz' ? 'selected' : ''}>UZB</option>
              </select>
            </label>
            <div class="admin-chip">
              <span>${escapeHtml(tr(uiLang, 'Signed in as', 'В системе как', 'Tizimdagi foydalanuvchi'))}</span>
              <strong>${escapeHtml(adminName || 'Admin')}</strong>
            </div>
            <button id="logout-btn" class="btn btn-muted">${escapeHtml(t('logout', uiLang))}</button>
          </div>
        </header>
        <main id="page-root" class="page-root"></main>
      </div>
    </div>
  `;
}
