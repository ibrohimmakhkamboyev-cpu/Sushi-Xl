import { api } from '../services/api.js';
import { escapeHtml, formatDate, formatMoney } from '../models/serializers.js';
import { renderTable } from '../components/table.js';
import { renderMetricGrid, renderPageHeader, renderSectionCard, tr } from '../components/page-shell.js';

const ADMIN_FETCH_LIMIT = 200;

function userPayload(form) {
  return {
    phone: String(form.phone || '').trim(),
    fullName: String(form.fullName || '').trim(),
    preferredLang: String(form.preferredLang || 'ru').trim() || 'ru',
  };
}

function userForm(openFormModal, t, initial = null) {
  return openFormModal({
    title: initial ? `${t('edit')} ${t('users')}` : `${t('create')} ${t('users')}`,
    submitText: initial ? t('update') : t('create'),
    cancelText: t('cancel'),
    initial: {
      fullName: initial?.full_name || '',
      phone: initial?.phone || '',
      preferredLang: initial?.preferred_lang || 'ru',
    },
    fields: [
      { name: 'fullName', label: t('full_name'), required: true },
      { name: 'phone', label: t('phone'), required: true },
      {
        name: 'preferredLang',
        label: t('language_label'),
        type: 'select',
        required: true,
        options: [
          { value: 'ru', label: 'RU' },
          { value: 'uz', label: 'UZ' },
          { value: 'en', label: 'EN' },
        ],
      },
    ],
  });
}

export async function renderUsers(ctx) {
  const { container, token, openFormModal, openConfirmModal, showToast, uiLang = 'en', t = (key) => key } = ctx;
  const state = { search: '', rows: [], sortKey: 'id', sortDir: 'desc' };

  const load = async () => {
    const res = await api.listUsers(token, { search: state.search, limit: ADMIN_FETCH_LIMIT });
    state.rows = res.results || [];
  };

  const render = async () => {
    try {
      await load();
    } catch (error) {
      container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_users'))}: ${escapeHtml(error.message)}</div>`;
      return;
    }

    const totalSpent = state.rows.reduce((sum, row) => sum + Number(row.total_spent || 0), 0);

    const columns = [
      { key: 'id', label: t('id'), sortable: true },
      { key: 'full_name', label: t('name'), sortable: true },
      { key: 'phone', label: t('phone'), sortable: true },
      { key: 'preferred_lang', label: t('language_label'), sortable: true },
      { key: 'orders_count', label: t('orders'), sortable: true },
      { key: 'total_spent', label: t('spent'), sortable: true, render: (row) => formatMoney(row.total_spent) },
      { key: 'created_at', label: t('joined'), sortable: true, render: (row) => formatDate(row.created_at) },
      {
        key: 'actions',
        label: t('actions'),
        sortable: false,
        render: (row) => `
          <div class="table-actions">
            <button class="btn btn-sm btn-muted" data-action="edit" data-id="${row.id}">${escapeHtml(t('edit'))}</button>
            <button class="btn btn-sm btn-danger" data-action="delete" data-id="${row.id}">${escapeHtml(t('delete'))}</button>
          </div>
        `,
      },
    ];

    container.innerHTML = `
      ${renderPageHeader({
        eyebrow: tr(uiLang, 'Customer base', 'Клиентская база', 'Mijozlar bazasi'),
        title: tr(uiLang, 'Users and spending overview', 'Пользователи и траты', 'Foydalanuvchilar va sarf ko‘rinishi'),
        description: tr(uiLang, 'Review customer profiles, order activity, preferred language, and total spend while keeping full CRUD controls available.', 'Просматривайте профили клиентов, активность заказов, предпочитаемый язык и общий чек, сохраняя полный CRUD.', 'Mijoz profillari, buyurtma faolligi, afzal til va jami sarfni to‘liq CRUD bilan ko‘rib chiqing.'),
      })}
      ${renderMetricGrid([
        { label: t('users'), value: String(state.rows.length), tone: 'accent', helper: tr(uiLang, 'Matched by current search', 'Найдено по текущему поиску', 'Joriy qidiruv bo‘yicha topildi') },
        { label: t('spent'), value: formatMoney(totalSpent), tone: 'success', helper: tr(uiLang, 'Aggregate spend in view', 'Суммарные траты в текущем списке', 'Joriy ro‘yxatdagi jami sarf') },
      ])}
      ${renderSectionCard({
        title: t('users_customers'),
        description: tr(uiLang, 'Search and maintain customer records with fast access to phone, language, order count, and spend.', 'Ищите и поддерживайте клиентские записи с быстрым доступом к телефону, языку, числу заказов и тратам.', 'Telefon, til, buyurtmalar soni va sarf bo‘yicha tezkor kirish bilan mijoz yozuvlarini qidiring va boshqaring.'),
        actions: `
          <button class="btn btn-primary" id="users-add">${escapeHtml(t('create'))}</button>
          <button class="btn btn-muted" id="users-refresh">${escapeHtml(t('refresh'))}</button>
        `,
        body: `
          <div class="toolbar">
            <input id="users-search" placeholder="${escapeHtml(t('search_users'))}" value="${escapeHtml(state.search)}" />
          </div>
          <div id="users-table"></div>
        `,
      })}
    `;

    const tableRoot = container.querySelector('#users-table');

    const draw = () => {
      renderTable({
        container: tableRoot,
        columns,
        rows: state.rows,
        state,
        onSortChange: (sortKey, sortDir) => {
          state.sortKey = sortKey;
          state.sortDir = sortDir;
          draw();
        },
        emptyText: t('no_data'),
        minWidth: '1040px',
      });

      tableRoot.querySelectorAll('[data-action="edit"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const userId = Number(btn.dataset.id);
          const current = state.rows.find((row) => Number(row.id) === userId);
          if (!current) return;
          const form = await userForm(openFormModal, t, current);
          if (!form) return;
          try {
            await api.updateUser(token, userId, userPayload(form));
            showToast(`${t('users')} ${t('updated')}`, 'success');
            await render();
          } catch (error) {
            showToast(`${t('update_failed')}: ${error.message}`, 'error');
          }
        });
      });

      tableRoot.querySelectorAll('[data-action="delete"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const userId = Number(btn.dataset.id);
          const confirmed = await openConfirmModal({
            title: `${t('delete')} ${t('users')}`,
            message: `${t('users_customers')} #${userId}`,
            confirmText: t('confirm_delete'),
            cancelText: t('cancel'),
          });
          if (!confirmed) return;
          try {
            await api.deleteUser(token, userId);
            showToast(`${t('users')} ${t('delete')}`, 'success');
            await render();
          } catch (error) {
            showToast(`${t('delete_failed')}: ${error.message}`, 'error');
          }
        });
      });
    };

    draw();

    container.querySelector('#users-search').addEventListener('input', (event) => {
      state.search = event.target.value;
    });
    container.querySelector('#users-search').addEventListener('keydown', (event) => {
      if (event.key === 'Enter') render();
    });
    container.querySelector('#users-refresh').addEventListener('click', render);
    container.querySelector('#users-add').addEventListener('click', async () => {
      const form = await userForm(openFormModal, t);
      if (!form) return;
      try {
        await api.createUser(token, userPayload(form));
        showToast(`${t('users')} ${t('created')}`, 'success');
        await render();
      } catch (error) {
        showToast(`${t('create_failed')}: ${error.message}`, 'error');
      }
    });
  };

  await render();
}
