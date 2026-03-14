import { api } from '../services/api.js';
import { formatDate, formatMoney, escapeHtml } from '../models/serializers.js';
import { statusBadge } from '../components/badge.js';
import { renderTable } from '../components/table.js';

const ORDER_STATUSES = ['pending', 'accepted', 'preparing', 'on_the_way', 'delivered', 'cancelled', 'completed'];
const PAYMENT_STATUSES = ['pending', 'unpaid', 'paid', 'refunded'];
const ADMIN_FETCH_LIMIT = 200;

export async function renderOrders(ctx) {
  const { container, token, openFormModal, showToast, t = (key) => key } = ctx;
  const state = {
    search: '',
    status: '',
    paymentStatus: '',
    sortKey: 'id',
    sortDir: 'desc',
    rows: [],
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
    container.innerHTML = `
      <section class="panel">
        <div class="panel-head split">
          <h2>${escapeHtml(t('orders_management'))}</h2>
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
            <button class="btn btn-muted" id="order-refresh">${escapeHtml(t('refresh'))}</button>
          </div>
        </div>
        <div id="orders-table"></div>
      </section>
    `;

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

    const tableNode = container.querySelector('#orders-table');

    const columns = [
      { key: 'id', label: t('order_number'), sortable: true },
      { key: 'user_name', label: t('customer'), sortable: true, render: (row) => escapeHtml(row.user_name || row.user_phone || '-') },
      { key: 'user_phone', label: t('phone'), sortable: true },
      {
        key: 'status',
        label: t('status_label'),
        sortable: true,
        render: (row) => statusBadge(row.status, labelForOrderStatus(row.status)),
      },
      {
        key: 'payment_status',
        label: t('payment'),
        sortable: true,
        render: (row) => statusBadge(row.payment_status, labelForPaymentStatus(row.payment_status)),
      },
      { key: 'total', label: t('total'), sortable: true, render: (row) => formatMoney(row.total) },
      { key: 'created_at', label: t('created'), sortable: true, render: (row) => formatDate(row.created_at) },
      {
        key: 'actions',
        label: t('actions'),
        sortable: false,
        render: (row) => `
          <div class="table-actions">
            <button class="btn btn-sm btn-muted" data-action="set-preparing" data-id="${row.id}">${escapeHtml(t('preparing'))}</button>
            <button class="btn btn-sm btn-muted" data-action="set-delivered" data-id="${row.id}">${escapeHtml(t('delivered'))}</button>
            <button class="btn btn-sm btn-muted" data-action="edit-order" data-id="${row.id}">${escapeHtml(t('edit'))}</button>
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
      });

      tableNode.querySelectorAll('[data-action="set-preparing"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const orderId = Number(btn.dataset.id);
          const item = state.rows.find((row) => row.id === orderId);
          if (!item) return;
          try {
            await api.updateOrder(token, orderId, {
              status: 'preparing',
              paymentStatus: item.payment_status,
            });
            showToast(t('order_set_preparing'), 'success');
            await load();
          } catch (error) {
            showToast(`${t('update_failed')}: ${error.message}`, 'error');
          }
        });
      });

      tableNode.querySelectorAll('[data-action="set-delivered"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const orderId = Number(btn.dataset.id);
          const item = state.rows.find((row) => row.id === orderId);
          if (!item) return;
          try {
            await api.updateOrder(token, orderId, {
              status: 'delivered',
              paymentStatus: item.payment_status === 'paid' ? 'paid' : item.payment_status,
            });
            showToast(t('order_set_delivered'), 'success');
            await load();
          } catch (error) {
            showToast(`${t('update_failed')}: ${error.message}`, 'error');
          }
        });
      });

      tableNode.querySelectorAll('[data-action="edit-order"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const orderId = Number(btn.dataset.id);
          const item = state.rows.find((row) => row.id === orderId);
          if (!item) return;

          const form = await openFormModal({
            title: `${t('update_order')} #${orderId}`,
            submitText: t('save'),
            cancelText: t('cancel'),
            initial: {
              status: item.status,
              paymentStatus: item.payment_status,
            },
            fields: [
              {
                name: 'status',
                label: t('order_status'),
                type: 'select',
                required: true,
                options: ORDER_STATUSES.map((status) => ({ label: labelForOrderStatus(status), value: status })),
              },
              {
                name: 'paymentStatus',
                label: t('payment_status'),
                type: 'select',
                required: true,
                options: PAYMENT_STATUSES.map((status) => ({ label: labelForPaymentStatus(status), value: status })),
              },
            ],
          });

          if (!form) return;
          try {
            await api.updateOrder(token, orderId, form);
            showToast(t('order_updated'), 'success');
            await load();
          } catch (error) {
            showToast(`${t('update_failed')}: ${error.message}`, 'error');
          }
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
