import { api } from '../services/api.js';
import { formatDate, formatMoney, escapeHtml } from '../models/serializers.js';
import { statusBadge } from '../components/badge.js';
import { renderTable } from '../components/table.js';
import {
  renderDefinitionList,
  renderMetricGrid,
  renderPageHeader,
  renderSectionCard,
  tr,
} from '../components/page-shell.js';

const ORDER_STATUSES = ['pending', 'accepted', 'preparing', 'on_the_way', 'delivered', 'cancelled', 'completed'];
const PAYMENT_STATUSES = ['pending', 'unpaid', 'paid', 'refunded'];
const ADMIN_FETCH_LIMIT = 200;

export async function renderOrders(ctx) {
  const { container, token, openDrawer, showToast, uiLang = 'en', t = (key) => key } = ctx;
  const state = {
    search: '',
    status: '',
    paymentStatus: '',
    sortKey: 'id',
    sortDir: 'desc',
    rows: [],
  };

  const openOrderDetails = async (row) => {
    if (!row) return;
    const content = `
      ${renderDefinitionList([
        { label: tr(uiLang, 'Order', 'Заказ', 'Buyurtma'), value: `#${row.id}` },
        { label: tr(uiLang, 'Poster order', 'Заказ Poster', 'Poster buyurtmasi'), value: row.poster_order_id || '-' },
        { label: t('customer'), value: row.user_name || '-' },
        { label: t('phone'), value: row.user_phone || '-' },
        { label: t('status_label'), value: labelForOrderStatus(row.status) },
        { label: t('payment_status'), value: labelForPaymentStatus(row.payment_status) },
        { label: tr(uiLang, 'Payment method', 'Способ оплаты', 'To‘lov usuli'), value: row.payment_method || '-' },
        { label: tr(uiLang, 'Delivery type', 'Тип доставки', 'Yetkazib berish turi'), value: row.delivery_type || '-' },
        { label: tr(uiLang, 'Address', 'Адрес', 'Manzil'), value: row.address || '-' },
        { label: tr(uiLang, 'Notes', 'Заметки', 'Izohlar'), value: row.notes || '-' },
        { label: t('created'), value: formatDate(row.created_at) },
      ])}
    `;
    await openDrawer({
      title: `${tr(uiLang, 'Order details', 'Детали заказа', 'Buyurtma tafsilotlari')} #${row.id}`,
      subtitle: tr(
        uiLang,
        'Monitoring view only. Poster remains the source of truth for lifecycle handling.',
        'Только мониторинг. Poster остается источником истины для жизненного цикла заказа.',
        'Faqat monitoring. Buyurtma hayotiy sikli uchun Poster asosiy manba bo‘lib qoladi.',
      ),
      content,
      closeText: t('close') === 'close' ? tr(uiLang, 'Close', 'Закрыть', 'Yopish') : t('close'),
    });
  };

  const labelForOrderStatus = (status) => {
    const key = `status_${String(status || '').toLowerCase()}`;
    const translated = t(key);
    return translated === key ? status : translated;
  };

  const labelForPaymentStatus = (status) => {
    const key = `payment_${String(status || '').toLowerCase()}`;
    const translated = t(key);
    return translated === key ? status : translated;
  };

  container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_orders'))}</div>`;

  const load = async () => {
    try {
      const res = await api.listOrders(token, {
        search: state.search,
        status: state.status,
        paymentStatus: state.paymentStatus,
        limit: ADMIN_FETCH_LIMIT,
      });
      state.rows = res.results || [];
    } catch (error) {
      container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_orders'))}: ${escapeHtml(error.message)}</div>`;
      return;
    }

    const rows = state.rows;
    const todayDate = new Date().toDateString();
    const todayRows = rows.filter((row) => {
      const created = new Date(row.created_at);
      return !Number.isNaN(created.getTime()) && created.toDateString() === todayDate;
    });
    const newToday = todayRows.filter((row) => String(row.status || '').toLowerCase().includes('pend')).length;
    const deliveredToday = todayRows.filter((row) => {
      const value = String(row.status || '').toLowerCase();
      return value.includes('deliver') || value.includes('complete');
    }).length;
    const unpaidCount = rows.filter((row) => String(row.payment_status || '').toLowerCase().includes('unpaid')).length;
    const syncedCount = rows.filter((row) => Boolean(String(row.poster_order_id || '').trim())).length;

    container.innerHTML = `
      ${renderPageHeader({
        eyebrow: tr(uiLang, 'Poster order monitor', 'Монитор заказов Poster', 'Poster buyurtma monitori'),
        title: tr(uiLang, 'Orders observability', 'Наблюдение за заказами', 'Buyurtmalar kuzatuvi'),
        description: tr(
          uiLang,
          'Track Poster-synced orders, inspect payment state, search by customer details, and refresh the feed without forcing admin-side lifecycle actions.',
          'Отслеживайте заказы, синхронизированные с Poster, проверяйте состояние оплаты, ищите по данным клиента и обновляйте поток без навязывания действий по жизненному циклу из админки.',
          'Poster bilan sinxronlangan buyurtmalarni kuzating, to‘lov holatini tekshiring, mijoz ma’lumotlari bo‘yicha qidiring va admin paneldan soxta hayotiy sikl amallarini bermasdan oqimni yangilang.',
        ),
        actions: `<button class="btn btn-primary" id="order-refresh">${escapeHtml(tr(uiLang, 'Refresh Poster feed', 'Обновить поток Poster', 'Poster oqimini yangilash'))}</button>`,
        meta: [
          { label: tr(uiLang, 'Mode', 'Режим', 'Rejim'), value: tr(uiLang, 'Read-only operations monitoring', 'Мониторинг без управления', 'Faqat monitoring'), tone: 'accent' },
          { label: tr(uiLang, 'Search scope', 'Область поиска', 'Qidiruv sohasi'), value: tr(uiLang, 'ID, customer, phone', 'ID, клиент, телефон', 'ID, mijoz, telefon') },
        ],
      })}
      ${renderMetricGrid([
        { label: tr(uiLang, 'Today total', 'Сегодня всего', 'Bugun jami'), value: String(todayRows.length), tone: 'accent', helper: tr(uiLang, 'Orders created today', 'Заказы за сегодня', 'Bugun yaratilgan buyurtmalar') },
        { label: tr(uiLang, 'New today', 'Новые сегодня', 'Bugun yangi'), value: String(newToday), tone: 'warning', helper: tr(uiLang, 'Pending / fresh intake', 'Ожидают обработки', 'Yangi / kutilmoqda') },
        { label: tr(uiLang, 'Delivered today', 'Доставлено сегодня', 'Bugun yetkazilgan'), value: String(deliveredToday), tone: 'success', helper: tr(uiLang, 'Delivered or completed', 'Доставленные или завершенные', 'Yetkazilgan yoki yakunlangan') },
        { label: tr(uiLang, 'Unpaid', 'Не оплачено', 'To‘lanmagan'), value: String(unpaidCount), tone: 'warning', helper: tr(uiLang, 'Current unpaid orders in view', 'Неоплаченные в текущем списке', 'Joriy ro‘yxatdagi to‘lanmaganlar') },
        { label: tr(uiLang, 'Poster-linked', 'Связано с Poster', 'Poster bilan bog‘langan'), value: `${syncedCount}/${rows.length}`, tone: 'success', helper: tr(uiLang, 'Rows with Poster order id', 'Строки с id заказа Poster', 'Poster buyurtma ID si bor satrlar') },
      ])}
      ${renderSectionCard({
        title: t('orders_management'),
        description: tr(uiLang, 'Search, filter, and inspect order records without introducing fake admin-side flow control.', 'Ищите, фильтруйте и просматривайте заказы без ложного управления потоком из админки.', 'Soxta admin boshqaruvini qo‘shmasdan buyurtmalarni qidiring, filtrlang va ko‘ring.'),
        body: `
          <div class="toolbar">
            <input id="order-search" placeholder="${escapeHtml(t('search_order_placeholder'))}" value="${escapeHtml(state.search)}" />
            <select id="order-status-filter">
              <option value="">${escapeHtml(t('all_statuses'))}</option>
              ${ORDER_STATUSES.map((s) => `<option value="${s}" ${s === state.status ? 'selected' : ''}>${escapeHtml(labelForOrderStatus(s))}</option>`).join('')}
            </select>
            <select id="order-payment-filter">
              <option value="">${escapeHtml(t('all_payments'))}</option>
              ${PAYMENT_STATUSES.map((s) => `<option value="${s}" ${s === state.paymentStatus ? 'selected' : ''}>${escapeHtml(labelForPaymentStatus(s))}</option>`).join('')}
            </select>
          </div>
          <div id="orders-table"></div>
        `,
      })}
    `;

    const tableNode = container.querySelector('#orders-table');

    const columns = [
      { key: 'id', label: t('order_number'), sortable: true },
      { key: 'user_name', label: t('customer'), sortable: true, render: (row) => escapeHtml(row.user_name || row.user_phone || '-') },
      { key: 'user_phone', label: t('phone'), sortable: true },
      {
        key: 'status',
        label: t('status_label'),
        sortable: true,
        render: (row) => `
          <div class="definition-list">
            <div class="definition-item">
              <dt>${escapeHtml(tr(uiLang, 'App status', 'Статус в приложении', 'Ilovadagi holat'))}</dt>
              <dd>${statusBadge(row.status, labelForOrderStatus(row.status))}</dd>
            </div>
            <div class="definition-item">
              <dt>${escapeHtml(tr(uiLang, 'Poster link', 'Связь с Poster', 'Poster havolasi'))}</dt>
              <dd>${row.poster_order_id ? statusBadge('active', `Poster #${row.poster_order_id}`) : statusBadge('inactive', tr(uiLang, 'Pending sync id', 'Без Poster id', 'Poster ID yo‘q'))}</dd>
            </div>
          </div>
        `,
      },
      {
        key: 'payment_status',
        label: t('payment'),
        sortable: true,
        render: (row) => `
          <div class="definition-list">
            <div class="definition-item">
              <dt>${escapeHtml(t('payment_status'))}</dt>
              <dd>${statusBadge(row.payment_status, labelForPaymentStatus(row.payment_status))}</dd>
            </div>
            <div class="definition-item">
              <dt>${escapeHtml(tr(uiLang, 'Method', 'Метод', 'Usul'))}</dt>
              <dd>${escapeHtml(row.payment_method || '-')}</dd>
            </div>
          </div>
        `,
      },
      { key: 'total', label: t('total'), sortable: true, render: (row) => formatMoney(row.total) },
      {
        key: 'created_at',
        label: t('created'),
        sortable: true,
        render: (row) => `
          <div class="definition-list">
            <div class="definition-item">
              <dt>${escapeHtml(t('created'))}</dt>
              <dd>${escapeHtml(formatDate(row.created_at))}</dd>
            </div>
            <div class="definition-item">
              <dt>${escapeHtml(tr(uiLang, 'Delivery', 'Доставка', 'Yetkazish'))}</dt>
              <dd>${escapeHtml(row.delivery_type || '-')}</dd>
            </div>
          </div>
        `,
      },
      {
        key: 'actions',
        label: t('actions'),
        sortable: false,
        render: (row) => `
          <div class="table-actions">
            <button class="btn btn-sm btn-muted" data-action="view-order" data-id="${row.id}">${escapeHtml(t('view'))}</button>
          </div>
        `,
      },
    ];

    const drawTable = () => {
      renderTable({
        container: tableNode,
        columns,
        rows: state.rows,
        state,
        onSortChange: (sortKey, sortDir) => {
          state.sortKey = sortKey;
          state.sortDir = sortDir;
          drawTable();
        },
        emptyText: t('no_data'),
        minWidth: '1120px',
      });

      tableNode.querySelectorAll('[data-action="view-order"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const orderId = Number(btn.dataset.id);
          const item = state.rows.find((row) => row.id === orderId);
          await openOrderDetails(item);
        });
      });
    };

    drawTable();

    container.querySelector('#order-search').addEventListener('input', (event) => {
      state.search = event.target.value;
    });
    container.querySelector('#order-status-filter').addEventListener('change', (event) => {
      state.status = event.target.value;
      load();
    });
    container.querySelector('#order-payment-filter').addEventListener('change', (event) => {
      state.paymentStatus = event.target.value;
      load();
    });
    container.querySelector('#order-refresh').addEventListener('click', load);
    container.querySelector('#order-search').addEventListener('keydown', (event) => {
      if (event.key === 'Enter') load();
    });
  };

  await load();
}
