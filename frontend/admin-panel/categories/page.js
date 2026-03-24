import { api } from '../services/api.js';
import { escapeHtml } from '../models/serializers.js';
import { renderTable } from '../components/table.js';
import { statusBadge } from '../components/badge.js';
import { renderMetricGrid, renderPageHeader, renderSectionCard, tr } from '../components/page-shell.js';

function pickLocalized(row, base, uiLang = 'en') {
  if (uiLang === 'ru') return row?.[`${base}Ru`] || row?.[base] || '';
  if (uiLang === 'uz') return row?.[`${base}Uz`] || row?.[base] || '';
  return row?.[`${base}En`] || row?.[base] || '';
}

function pickFormLocalized(form, base, uiLang = 'en') {
  const suffix = uiLang === 'ru' ? 'Ru' : uiLang === 'uz' ? 'Uz' : 'En';
  const keys = [`${base}${suffix}`, base, `${base}Ru`, `${base}En`, `${base}Uz`];
  for (const key of keys) {
    const value = String(form?.[key] ?? '').trim();
    if (value) return value;
  }
  return '';
}

function firstText(...values) {
  for (const value of values) {
    const text = String(value ?? '').trim();
    if (text) return text;
  }
  return '';
}

function categoryPayload(form, uiLang = 'en', current = null) {
  const canonicalName = firstText(form.name, current?.name, pickFormLocalized(form, 'name', uiLang));
  const canonicalDescription = firstText(
    form.description,
    current?.description,
    pickFormLocalized(form, 'description', uiLang),
  );
  const nameEn = firstText(form.nameEn, current?.nameEn, canonicalName);
  const nameRu = firstText(form.nameRu, current?.nameRu, canonicalName);
  const nameUz = firstText(form.nameUz, current?.nameUz, canonicalName);
  const descriptionEn = firstText(
    form.descriptionEn,
    current?.descriptionEn,
    canonicalDescription,
  ) || null;
  const descriptionRu = firstText(
    form.descriptionRu,
    current?.descriptionRu,
    canonicalDescription,
  ) || null;
  const descriptionUz = firstText(
    form.descriptionUz,
    current?.descriptionUz,
    canonicalDescription,
  ) || null;
  return {
    name: canonicalName,
    nameEn,
    nameRu,
    nameUz,
    description: canonicalDescription || null,
    descriptionEn,
    descriptionRu,
    descriptionUz,
    sortOrder: Number(form.sortOrder || 0),
    isActive: Boolean(form.isActive),
  };
}

export async function renderCategories(ctx) {
  const { container, token, openFormModal, openConfirmModal, showToast, uiLang = 'en', t = (key) => key } = ctx;
  const state = { sortKey: 'sortOrder', sortDir: 'asc', rows: [], source: 'database', readOnly: false };

  const loadRows = async () => {
    const menuLang = uiLang === 'uz' ? 'uz' : uiLang === 'en' ? 'en' : 'ru';
    const menuRes = await api.getMenu(menuLang);
    state.rows = (menuRes?.categories || []).map((cat, idx) => ({
      id: Number(cat.id),
      name: cat.name || '',
      nameEn: cat.name || '',
      nameRu: cat.name || '',
      nameUz: cat.name || '',
      description: cat.description || null,
      descriptionEn: cat.description || null,
      descriptionRu: cat.description || null,
      descriptionUz: cat.description || null,
      sortOrder: idx,
      isActive: true,
    }));
    state.source = 'menu';
    state.readOnly = true;

    try {
      const res = await api.listCategories(token);
      const adminSource = String(res.source || '').toLowerCase();
      const adminReadOnly = Boolean(res.readOnly);
      if (adminSource === 'database' || adminSource === 'poster') {
        state.rows = res.results || [];
        state.source = adminSource;
        state.readOnly = adminReadOnly;
      }
    } catch (_) {
      // Keep menu-derived read-only data.
    }
  };

  const categoryForm = (initial = {}) =>
    openFormModal({
      title: initial.id ? t('edit') : t('add_category'),
      submitText: initial.id ? t('update') : t('create'),
      cancelText: t('cancel'),
      initial: {
        name: initial.name || '',
        nameEn: initial.nameEn || initial.name || '',
        nameRu: initial.nameRu || initial.name || '',
        nameUz: initial.nameUz || initial.name || '',
        description: initial.description || '',
        descriptionEn: initial.descriptionEn || initial.description || '',
        descriptionRu: initial.descriptionRu || initial.description || '',
        descriptionUz: initial.descriptionUz || initial.description || '',
        isActive: initial.isActive ?? true,
        sortOrder: initial.sortOrder ?? 0,
      },
      fields: [
        { name: 'name', label: t('name_fallback'), required: true },
        { name: 'nameEn', label: t('name_en'), required: true },
        { name: 'nameRu', label: t('name_ru'), required: true },
        { name: 'nameUz', label: t('name_uz'), required: true },
        { name: 'description', label: t('description_fallback'), type: 'textarea' },
        { name: 'descriptionEn', label: t('description_en'), type: 'textarea' },
        { name: 'descriptionRu', label: t('description_ru'), type: 'textarea' },
        { name: 'descriptionUz', label: t('description_uz'), type: 'textarea' },
        { name: 'sortOrder', label: t('sort_order'), type: 'number' },
        { name: 'isActive', label: t('active'), type: 'checkbox' },
      ],
    });

  const render = async () => {
    container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_categories'))}</div>`;
    try {
      await loadRows();
    } catch (error) {
      container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_categories'))}: ${escapeHtml(error.message)}</div>`;
      return;
    }

    container.innerHTML = `
      ${renderPageHeader({
        eyebrow: tr(uiLang, 'Menu structure', 'Структура меню', 'Menyu tuzilmasi'),
        title: tr(uiLang, 'Category management', 'Управление категориями', 'Kategoriyalar boshqaruvi'),
        description: tr(uiLang, 'Organize the storefront hierarchy, multilingual naming, and category order with a cleaner operations-first layout.', 'Управляйте иерархией витрины, многоязычными названиями и порядком категорий в более чистом интерфейсе.', 'Vitirinaning ierarxiyasi, ko‘p tilli nomlar va kategoriya tartibini yanada toza boshqaruv interfeysida boshqaring.'),
        meta: [
          { label: tr(uiLang, 'Source', 'Источник', 'Manba'), value: state.source || 'database' },
          { label: tr(uiLang, 'Write access', 'Доступ на запись', 'Yozish huquqi'), value: state.readOnly ? tr(uiLang, 'Read only', 'Только чтение', 'Faqat o‘qish') : tr(uiLang, 'Writable', 'Доступно', 'Yozish mumkin') },
        ],
      })}
      ${renderMetricGrid([
        { label: t('categories'), value: String(state.rows.length), tone: 'accent', helper: tr(uiLang, 'Visible category groups', 'Группы категорий', 'Ko‘rinadigan kategoriya guruhlari') },
        { label: t('active'), value: String(state.rows.filter((row) => row.isActive).length), tone: 'success', helper: tr(uiLang, 'Currently active', 'Сейчас активны', 'Hozir faol') },
      ])}
      ${renderSectionCard({
        title: t('categories_management'),
        description: tr(uiLang, 'Maintain a clear category tree and presentation order for the customer-facing menu.', 'Поддерживайте понятное дерево категорий и порядок отображения для клиентского меню.', 'Mijozlar ko‘radigan menyu uchun aniq kategoriya daraxti va ko‘rsatish tartibini saqlang.'),
        actions: state.readOnly
          ? statusBadge('warning', t('source_read_only').replace('{source}', state.source))
          : `<button type="button" class="btn btn-primary" id="add-category">${escapeHtml(t('add_category'))}</button>`,
        body: '<div id="categories-table"></div>',
      })}
    `;

    const tableRoot = container.querySelector('#categories-table');
    const orderedRows = [...state.rows].sort((a, b) => {
      const left = Number(a.sortOrder || 0);
      const right = Number(b.sortOrder || 0);
      if (left !== right) return left - right;
      return String(a.name || '').localeCompare(String(b.name || ''));
    });
    const columns = [
      { key: 'id', label: t('id'), sortable: true },
      { key: 'name', label: t('name'), sortable: true, render: (row) => escapeHtml(pickLocalized(row, 'name', uiLang)) },
      {
        key: 'description',
        label: t('description'),
        sortable: true,
        render: (row) => escapeHtml(pickLocalized(row, 'description', uiLang) || '-'),
      },
      { key: 'sortOrder', label: t('sort'), sortable: true },
      { key: 'isActive', label: t('status_label'), sortable: true, render: (row) => statusBadge(row.isActive ? 'active' : 'inactive') },
    ];
    if (!state.readOnly) {
      columns.push({
        key: 'actions',
        label: t('actions'),
        sortable: false,
        render: (row) => `
          <div class="table-actions">
            <button type="button" class="btn btn-sm btn-muted" data-action="up" data-id="${row.id}">${escapeHtml(t('up'))}</button>
            <button type="button" class="btn btn-sm btn-muted" data-action="down" data-id="${row.id}">${escapeHtml(t('down'))}</button>
            <button type="button" class="btn btn-sm btn-muted" data-action="edit" data-id="${row.id}">${escapeHtml(t('edit'))}</button>
            <button type="button" class="btn btn-sm btn-danger" data-action="delete" data-id="${row.id}">${escapeHtml(t('delete'))}</button>
          </div>
        `,
      });
    }

    const drawTable = () => {
      renderTable({
        container: tableRoot,
        columns,
        rows: orderedRows,
        state,
        onSortChange: (sortKey, sortDir) => {
          state.sortKey = sortKey;
          state.sortDir = sortDir;
          drawTable();
        },
        emptyText: t('no_data'),
        minWidth: '940px',
      });

      if (state.readOnly) return;

      const moveCategory = async (id, direction) => {
        const idx = orderedRows.findIndex((item) => Number(item.id) === Number(id));
        if (idx < 0) return;
        const swapIdx = direction < 0 ? idx - 1 : idx + 1;
        if (swapIdx < 0 || swapIdx >= orderedRows.length) return;
        const next = [...orderedRows];
        const tmp = next[idx];
        next[idx] = next[swapIdx];
        next[swapIdx] = tmp;
        try {
          await api.reorderCategories(
            token,
            next.map((item) => Number(item.id)),
          );
          showToast(`${t('categories')} ${t('updated')}`, 'success');
          await render();
        } catch (error) {
          showToast(`${t('reorder_failed')}: ${error.message}`, 'error');
        }
      };

      tableRoot.querySelectorAll('[data-action="up"]').forEach((btn) => {
        btn.addEventListener('click', () => moveCategory(Number(btn.dataset.id), -1));
      });

      tableRoot.querySelectorAll('[data-action="down"]').forEach((btn) => {
        btn.addEventListener('click', () => moveCategory(Number(btn.dataset.id), 1));
      });

      tableRoot.querySelectorAll('[data-action="edit"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const id = Number(btn.dataset.id);
          const current = state.rows.find((row) => row.id === id);
          if (!current) return;
          const form = await categoryForm(current);
          if (!form) return;
          try {
            await api.updateCategory(token, id, categoryPayload(form, uiLang, current));
            showToast(`${t('categories')} ${t('updated')}`, 'success');
            await render();
          } catch (error) {
            showToast(`${t('update_failed')}: ${error.message}`, 'error');
          }
        });
      });

      tableRoot.querySelectorAll('[data-action="delete"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const id = Number(btn.dataset.id);
          const confirmed = await openConfirmModal({
            title: `${t('delete')} ${t('categories')}`,
            message: t('category_must_have_no_products'),
            confirmText: t('confirm_delete'),
            cancelText: t('cancel'),
          });
          if (!confirmed) return;
          try {
            await api.deleteCategory(token, id);
            showToast(`${t('categories')} ${t('delete')}`, 'success');
            await render();
          } catch (error) {
            showToast(`${t('delete_failed')}: ${error.message}`, 'error');
          }
        });
      });
    };

    drawTable();

    if (state.readOnly) return;

    container.querySelector('#add-category').addEventListener('click', async () => {
      const form = await categoryForm();
      if (!form) return;
      try {
        await api.createCategory(token, categoryPayload(form, uiLang));
        showToast(`${t('categories')} ${t('create')}`, 'success');
        await render();
      } catch (error) {
        showToast(`${t('create_failed')}: ${error.message}`, 'error');
      }
    });
  };

  await render();
}
