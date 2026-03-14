import { escapeHtml } from '../models/serializers.js';
import { t } from '../services/i18n.js';

const NAV_ITEMS = [
  ['dashboard', 'dashboard'],
  ['orders', 'orders'],
  ['products', 'products'],
  ['categories', 'categories'],
  ['discounts', 'discounts'],
  ['users', 'users'],
  ['notifications', 'notifications'],
  ['banners', 'banners'],
  ['faq', 'faq'],
  ['settings', 'settings'],
  ['profile', 'profile'],
];

export function renderMainLayout({ activeRoute, adminName, uiLang }) {
  const nav = NAV_ITEMS.map(([route, labelKey]) => {
    const active = activeRoute === route ? 'active' : '';
    return `<a href="#/${route}" class="side-link ${active}">${escapeHtml(t(labelKey, uiLang))}</a>`;
  }).join('');

  const pageTitleKey = NAV_ITEMS.find(([route]) => route === activeRoute)?.[1] || 'dashboard';

  return `
    <div class="admin-shell">
      <aside class="sidebar">
        <div class="brand">
          <div class="brand-mark brand-logo-wrap">
            <img src="./assets/app-logo.png" alt="Sushi XL logo" class="brand-logo-img" />
          </div>
          <div>
            <div class="brand-title">Sushi XL</div>
            <div class="brand-sub">Admin Suite</div>
          </div>
        </div>
        <nav class="side-nav">${nav}</nav>
      </aside>
      <div class="main-column">
        <header class="topbar">
          <div>
            <h1>${escapeHtml(t(pageTitleKey, uiLang))}</h1>
            <p>${escapeHtml(t('operational_dashboard', uiLang))}</p>
          </div>
          <div class="topbar-actions">
            <label class="field compact-field topbar-language-field">
              <select id="ui-language-switcher" aria-label="${escapeHtml(t('language', uiLang))}">
                <option value="en" ${uiLang === 'en' ? 'selected' : ''}>ENG</option>
                <option value="ru" ${uiLang === 'ru' ? 'selected' : ''}>RUS</option>
                <option value="uz" ${uiLang === 'uz' ? 'selected' : ''}>UZB</option>
              </select>
            </label>
            <div class="admin-chip">${escapeHtml(adminName || 'Admin')}</div>
            <button id="logout-btn" class="btn btn-muted">${escapeHtml(t('logout', uiLang))}</button>
          </div>
        </header>
        <main id="page-root" class="page-root"></main>
      </div>
    </div>
  `;
}
