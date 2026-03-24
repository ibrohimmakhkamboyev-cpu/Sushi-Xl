import { api } from '../services/api.js';
import { formatCompactMoney, formatDate, formatMoney } from '../models/serializers.js';
import { statusBadge } from '../components/badge.js';
import { renderTable } from '../components/table.js';
import { renderMetricGrid, renderPageHeader, renderSectionCard, tr } from '../components/page-shell.js';

export async function renderDashboard(ctx) {
  const { container, token, uiLang = 'en', t = (key) => key } = ctx;
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
    const unpaid = orders.filter((row) => String(row.payment_status || '').toLowerCase().includes('unpaid')).length;
    const posterLinked = orders.filter((row) => row.poster_order_id).length;

    container.innerHTML = `
      ${renderPageHeader({
        eyebrow: tr(uiLang, 'Executive overview', 'Исполнительный обзор', 'Ijrochi ko‘rinish'),
        title: tr(uiLang, 'Sushi XL command center', 'Командный центр Sushi XL', 'Sushi XL boshqaruv markazi'),
        description: tr(
          uiLang,
          'A live summary of revenue, demand, catalog size, and the most recent Poster-synced order activity across the admin suite.',
          'Живой обзор выручки, спроса, размера каталога и последних заказов, синхронизированных с Poster.',
          'Daromad, talab, katalog hajmi va Poster bilan sinxronlangan so‘nggi buyurtmalar bo‘yicha jonli ko‘rinish.',
        ),
        meta: [
          { label: tr(uiLang, 'Orders role', 'Роль заказов', 'Buyurtma roli'), value: tr(uiLang, 'Monitoring and visibility', 'Мониторинг и видимость', 'Monitoring va ko‘rinish'), tone: 'accent' },
          { label: tr(uiLang, 'Poster link', 'Связь с Poster', 'Poster ulanishi'), value: `${posterLinked}/${orders.length}` },
        ],
      })}
      ${renderMetricGrid([
        {
          label: t('revenue'),
          value: formatCompactMoney(stats.revenue || 0, 'UZS', uiLang),
          caption: formatMoney(stats.revenue || 0, 'UZS', uiLang),
          tone: 'accent',
          valueClassName: 'metric-value--currency',
          helper: tr(uiLang, 'Recorded revenue snapshot', 'Снимок выручки', 'Daromad ko‘rinishi'),
        },
        { label: t('total_orders'), value: String(stats.totalOrders || 0), helper: tr(uiLang, 'All recorded orders', 'Все записанные заказы', 'Barcha qayd etilgan buyurtmalar') },
        { label: t('pending_orders'), value: String(stats.pendingOrders || 0), tone: 'warning', helper: tr(uiLang, 'Orders still in progress', 'Заказы в работе', 'Jarayondagi buyurtmalar') },
        { label: t('users'), value: String(stats.users || 0), helper: tr(uiLang, 'Customer accounts', 'Клиентские аккаунты', 'Mijoz akkauntlari') },
        { label: t('products'), value: String(stats.products || 0), helper: tr(uiLang, 'Live catalog entries', 'Активные позиции каталога', 'Faol katalog elementlari') },
        { label: tr(uiLang, 'Recent unpaid', 'Недавние неоплаченные', 'So‘nggi to‘lanmagan'), value: String(unpaid), tone: 'warning', helper: tr(uiLang, 'Within latest order snapshot', 'В текущем срезе заказов', 'Joriy buyurtma kesimida') },
      ])}
      ${renderSectionCard({
        title: t('recent_orders'),
        description: tr(uiLang, 'A quick operational feed for the latest incoming orders. Open the Orders page for deeper monitoring and filtering.', 'Быстрый операционный поток последних заказов. Для глубокого мониторинга и фильтров откройте страницу заказов.', 'So‘nggi buyurtmalar uchun tezkor operatsion oqim. Batafsil monitoring va filtrlar uchun Buyurtmalar sahifasini oching.'),
        body: '<div id="dashboard-orders-table"></div>',
      })}
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
        minWidth: '820px',
      });

    draw();
  } catch (error) {
    container.innerHTML = `<div class="page-state error">${t('failed_load_dashboard')}: ${error.message}</div>`;
  }
}
