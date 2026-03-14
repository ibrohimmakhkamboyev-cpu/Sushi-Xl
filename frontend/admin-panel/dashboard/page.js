import { api } from '../services/api.js';
import { formatDate, formatMoney } from '../models/serializers.js';
import { statusBadge } from '../components/badge.js';
import { renderTable } from '../components/table.js';

export async function renderDashboard(ctx) {
  const { container, token, t = (key) => key } = ctx;
  container.innerHTML = `<div class="page-state loading">${t('loading_dashboard')}</div>`;
  const localizeStatus = (status) => {
    const key = `status_${String(status || '').toLowerCase()}`;
    const translated = t(key);
    return translated === key ? status : translated;
  };

  try {
    const [stats, ordersRes] = await Promise.all([
      api.dashboardStats(token),
      api.listOrders(token, { limit: 8 }),
    ]);
    const orders = ordersRes.results || [];

    container.innerHTML = `
      <section class="stats-grid">
        <article class="stat-card"><h3>${t('revenue')}</h3><p>${formatMoney(stats.revenue || 0)}</p></article>
        <article class="stat-card"><h3>${t('total_orders')}</h3><p>${stats.totalOrders || 0}</p></article>
        <article class="stat-card"><h3>${t('pending_orders')}</h3><p>${stats.pendingOrders || 0}</p></article>
        <article class="stat-card"><h3>${t('users')}</h3><p>${stats.users || 0}</p></article>
        <article class="stat-card"><h3>${t('products')}</h3><p>${stats.products || 0}</p></article>
        <article class="stat-card"><h3>${t('active_banners')}</h3><p>${stats.activeBanners || 0}</p></article>
      </section>
      <section class="panel">
        <div class="panel-head">
          <h2>${t('recent_orders')}</h2>
        </div>
        <div id="dashboard-orders-table"></div>
      </section>
    `;

    const tableRoot = container.querySelector('#dashboard-orders-table');
    const state = { sortKey: 'id', sortDir: 'desc' };
    const columns = [
      { key: 'id', label: t('order_number'), sortable: true },
      { key: 'user_name', label: t('customer'), sortable: true },
      {
        key: 'status',
        label: t('status_label'),
        sortable: true,
        render: (row) => statusBadge(row.status, localizeStatus(row.status)),
      },
      {
        key: 'total',
        label: t('total'),
        sortable: true,
        render: (row) => formatMoney(row.total),
      },
      {
        key: 'created_at',
        label: t('created'),
        sortable: true,
        render: (row) => formatDate(row.created_at),
      },
    ];

    const draw = () =>
      renderTable({
        container: tableRoot,
        columns,
        rows: orders,
        state,
        onSortChange: (sortKey, sortDir) => {
          state.sortKey = sortKey;
          state.sortDir = sortDir;
          draw();
        },
        emptyText: t('no_orders'),
      });

    draw();
  } catch (error) {
    container.innerHTML = `<div class="page-state error">${t('failed_load_dashboard')}: ${error.message}</div>`;
  }
}
