import { api } from '../services/api.js';
import { escapeHtml, formatMoney, normalizeString } from '../models/serializers.js';
import { renderTable } from '../components/table.js';
import { statusBadge } from '../components/badge.js';
import { renderMetricGrid, renderPageHeader, renderSectionCard, tr } from '../components/page-shell.js';

const ADMIN_FETCH_LIMIT = 200;

function sortRows(rows, sortKey, sortDir) {
  if (!sortKey) return [...rows];
  const dir = sortDir === 'desc' ? -1 : 1;
  return [...rows].sort((a, b) => {
    const av = a?.[sortKey];
    const bv = b?.[sortKey];
    if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
    return String(av ?? '').localeCompare(String(bv ?? '')) * dir;
  });
}

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

function normalizeOptionalPositiveNumber(value) {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return parsed;
}

function toPayload(form, current = null, uiLang = 'en') {
  const fallbackTitle = firstText(
    form.title,
    current?.title,
    pickFormLocalized(form, 'title', uiLang),
  );
  const fallbackDescription = firstText(
    form.description,
    current?.description,
    pickFormLocalized(form, 'description', uiLang),
  ) || null;
  const titleEn = firstText(form.titleEn, current?.titleEn, fallbackTitle);
  const titleRu = firstText(form.titleRu, current?.titleRu, fallbackTitle);
  const titleUz = firstText(form.titleUz, current?.titleUz, fallbackTitle);
  const descriptionEn = firstText(
    form.descriptionEn,
    current?.descriptionEn,
    fallbackDescription,
  ) || null;
  const descriptionRu = firstText(
    form.descriptionRu,
    current?.descriptionRu,
    fallbackDescription,
  ) || null;
  const descriptionUz = firstText(
    form.descriptionUz,
    current?.descriptionUz,
    fallbackDescription,
  ) || null;
  const resolvedIsActive =
    form.isActive === undefined ? (current?.isActive ?? true) : Boolean(form.isActive);
  const resolvedIsDrink =
    form.isDrink === undefined ? (current?.isDrink ?? false) : Boolean(form.isDrink);
  const resolvedIsRecommended =
    form.isRecommended === undefined
      ? (current?.isRecommended ?? false)
      : Boolean(form.isRecommended);
  const resolvedIsPopular =
    form.isPopular === undefined ? (current?.isPopular ?? false) : Boolean(form.isPopular);
  const resolvedIsNew =
    form.isNew === undefined ? (current?.isNew ?? false) : Boolean(form.isNew);
  return {
    title: fallbackTitle,
    description: fallbackDescription,
    titleEn,
    titleRu,
    titleUz,
    descriptionEn,
    descriptionRu,
    descriptionUz,
    imageUrl: current?.imageUrl || null,
    categoryId: Number(form.categoryId),
    price: Number(form.price),
    oldPrice: normalizeOptionalPositiveNumber(form.oldPrice),
    discountStartAt: (form.discountStartAt || '').trim() || null,
    discountEndAt: (form.discountEndAt || '').trim() || null,
    sortOrder: Number(form.sortOrder || 0),
    isActive: resolvedIsActive,
    isDrink: resolvedIsDrink,
    isRecommended: resolvedIsRecommended,
    isPopular: resolvedIsPopular,
    isNew: resolvedIsNew,
  };
}

export async function renderProducts(ctx) {
  const { container, token, openFormModal, openConfirmModal, showToast, uiLang = 'en', t = (key) => key } = ctx;
  const state = {
    search: '',
    categoryId: '',
    sortKey: 'sortOrder',
    sortDir: 'asc',
    products: [],
    categories: [],
    source: 'database',
    readOnly: false,
    loaded: false,
  };

  container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_products'))}</div>`;

  const fetchData = async () => {
    const menuLang = uiLang === 'uz' ? 'uz' : uiLang === 'en' ? 'en' : 'ru';
    const menuRes = await api.getMenu(menuLang);
    const menuCategories = (menuRes?.categories || []).map((cat, idx) => ({
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
    const menuProducts = [];
    for (const cat of menuRes?.categories || []) {
      for (const product of cat.products || []) {
        menuProducts.push({
          id: Number(product.id),
          title: product.title || product.name || '',
          titleEn: product.title || product.name || '',
          titleRu: product.title || product.name || '',
          titleUz: product.title || product.name || '',
          description: product.description || null,
          descriptionEn: product.description || null,
          descriptionRu: product.description || null,
          descriptionUz: product.description || null,
          imageUrl: product.imageUrl || product.image_url || null,
          categoryId: Number(cat.id),
          categoryName: cat.name || '',
          categoryNameEn: cat.name || '',
          categoryNameRu: cat.name || '',
          categoryNameUz: cat.name || '',
          price: Number(product.price || 0),
          oldPrice: product.oldPrice ?? product.old_price ?? null,
          isActive: true,
          isDrink: false,
          isRecommended: false,
          isPopular: false,
          isNew: false,
          sortOrder: 0,
        });
      }
    }

    // Default to the same menu source used by the mobile app (/menu endpoint).
    state.products = menuProducts;
    state.categories = menuCategories;
    state.source = 'menu';
    state.readOnly = true;

    // If backend is in database mode and returns editable admin data, use it.
    try {
      const [productsRes, categoriesRes] = await Promise.all([
        api.listProducts(token, { limit: ADMIN_FETCH_LIMIT }),
        api.listCategories(token),
      ]);
      const adminSource = String(productsRes.source || categoriesRes.source || '').toLowerCase();
      const adminReadOnly = Boolean(productsRes.readOnly || categoriesRes.readOnly);
      if (adminSource === 'database' || adminSource === 'poster') {
        state.products = productsRes.results || [];
        state.categories = categoriesRes.results || [];
        state.source = adminSource;
        state.readOnly = adminReadOnly;
      }
    } catch (_) {
      // Keep menu-derived read-only data if admin endpoints are unavailable.
    }
  };

  const buildProductForm = (initial = {}) => {
    const categoryOptions = state.categories.map((item) => ({
      label: pickLocalized(item, 'name', uiLang),
      value: String(item.id),
    }));
    return openFormModal({
      title: initial.id ? t('edit') : t('add_product'),
      submitText: initial.id ? t('update') : t('create'),
      cancelText: t('cancel'),
      initial: {
        title: initial.title || initial.name || '',
        titleEn: initial.titleEn || initial.title || initial.name || '',
        titleRu: initial.titleRu || initial.title || initial.name || '',
        titleUz: initial.titleUz || initial.title || initial.name || '',
        description: initial.description || '',
        descriptionEn: initial.descriptionEn || initial.description || '',
        descriptionRu: initial.descriptionRu || initial.description || '',
        descriptionUz: initial.descriptionUz || initial.description || '',
        imageUrl: initial.imageUrl || '',
        imageFile: null,
        clearImage: false,
        categoryId: initial.categoryId ? String(initial.categoryId) : (categoryOptions[0]?.value || ''),
        price: initial.price ?? 0,
        oldPrice: initial.oldPrice ?? null,
        discountStartAt: initial.discountStartAt || '',
        discountEndAt: initial.discountEndAt || '',
        sortOrder: initial.sortOrder ?? 0,
        isActive: initial.isActive ?? true,
        isDrink: initial.isDrink ?? false,
        isRecommended: initial.isRecommended ?? false,
        isPopular: initial.isPopular ?? false,
        isNew: initial.isNew ?? false,
      },
      fields: [
        { name: 'title', label: t('title_fallback'), required: true },
        { name: 'titleEn', label: t('title_en'), required: true },
        { name: 'titleRu', label: t('title_ru'), required: true },
        { name: 'titleUz', label: t('title_uz'), required: true },
        { name: 'description', label: t('description_fallback'), type: 'textarea' },
        { name: 'descriptionEn', label: t('description_en'), type: 'textarea' },
        { name: 'descriptionRu', label: t('description_ru'), type: 'textarea' },
        { name: 'descriptionUz', label: t('description_uz'), type: 'textarea' },
        { name: 'imageUrl', label: t('image_url_optional') },
        { name: 'imageFile', label: t('upload_image'), type: 'file', accept: 'image/*' },
        { name: 'clearImage', label: t('remove_image'), type: 'checkbox' },
        { name: 'categoryId', label: t('category'), type: 'select', required: true, options: categoryOptions },
        { name: 'price', label: t('price'), type: 'number', required: true },
        { name: 'oldPrice', label: t('old_price_optional'), type: 'number' },
        { name: 'discountStartAt', label: t('discount_starts_at'), type: 'datetime-local' },
        { name: 'discountEndAt', label: t('discount_ends_at'), type: 'datetime-local' },
        { name: 'sortOrder', label: t('sort_order'), type: 'number' },
      ],
    });
  };

  const moveProduct = async (id, direction) => {
    const current = state.products.find((item) => Number(item.id) === Number(id));
    if (!current) return;
    const currentCategoryId = Number(current.categoryId || 0);
    const categoryRows = state.products.filter((item) => Number(item.categoryId || 0) === currentCategoryId);
    const categoryIdx = categoryRows.findIndex((item) => Number(item.id) === Number(id));
    if (categoryIdx < 0) return;
    const swapIdx = direction < 0 ? categoryIdx - 1 : categoryIdx + 1;
    if (swapIdx < 0 || swapIdx >= categoryRows.length) return;
    const nextIds = categoryRows.map((item) => Number(item.id));
    const tmp = nextIds[categoryIdx];
    nextIds[categoryIdx] = nextIds[swapIdx];
    nextIds[swapIdx] = tmp;
    try {
      const response = await api.reorderProducts(
        token,
        nextIds,
      );
      state.products = response.results?.length
        ? response.results
        : nextIds
            .map((nextId) => state.products.find((item) => Number(item.id) === Number(nextId)))
            .filter(Boolean);
      showToast(`${t('products')} ${t('updated')}`, 'success');
    } catch (error) {
      showToast(`${t('reorder_failed')}: ${error.message}`, 'error');
    }
  };

  const render = async (forceReload = false) => {
    if (!state.loaded || forceReload) {
      container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_products'))}</div>`;
      try {
        await fetchData();
        state.loaded = true;
      } catch (error) {
        container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_products'))}: ${escapeHtml(error.message)}</div>`;
        return;
      }
    }

    container.innerHTML = `
      <section class="panel">
        <div class="panel-head split">
          <h2>${escapeHtml(t('products_management'))}</h2>
          ${state.readOnly ? `<span style="color:#64748b;font-size:13px">${escapeHtml(t('source_read_only').replace('{source}', state.source))}</span>` : ''}
          <div class="toolbar">
            <input id="products-search" placeholder="${escapeHtml(t('search_products'))}" value="${escapeHtml(state.search)}" />
            <select id="products-category-filter">
              <option value="">${escapeHtml(t('all_categories'))}</option>
              ${state.categories.map((cat) => `<option value="${cat.id}" ${String(cat.id) === String(state.categoryId) ? 'selected' : ''}>${escapeHtml(pickLocalized(cat, 'name', uiLang))}</option>`).join('')}
            </select>
            ${state.readOnly ? '' : `<button class="btn btn-primary" id="add-product">${escapeHtml(t('add_product'))}</button>`}
          </div>
        </div>
        <div id="products-table"></div>
      </section>
    `;

    const filtered = state.products.filter((item) => {
      const searchSource = [
        item.title,
        item.titleEn,
        item.titleRu,
        item.titleUz,
        item.description,
        item.descriptionEn,
        item.descriptionRu,
        item.descriptionUz,
      ]
        .map((v) => String(v || ''))
        .join(' ')
        .toLowerCase();
      const searchOk = !state.search || searchSource.includes(normalizeString(state.search));
      const categoryOk = !state.categoryId || String(item.categoryId) === String(state.categoryId);
      return searchOk && categoryOk;
    });

    const activeCount = state.products.filter((item) => item.isActive).length;
    const discountedCount = state.products.filter((item) => Number(item.oldPrice || 0) > Number(item.price || 0)).length;
    const featuredCount = state.products.filter((item) => item.isRecommended || item.isPopular || item.isNew).length;

    container.innerHTML = `
      ${renderPageHeader({
        eyebrow: tr(uiLang, 'Catalog management', 'Управление каталогом', 'Katalog boshqaruvi'),
        title: tr(uiLang, 'Products and availability', 'Товары и доступность', 'Mahsulotlar va mavjudlik'),
        description: tr(uiLang, 'Manage the Sushi XL product catalog, pricing, category assignment, discount timing, and product imagery from one premium control surface.', 'Управляйте каталогом Sushi XL, ценами, привязкой к категориям, временем скидок и изображениями из одной панели.', 'Sushi XL katalogi, narxlar, kategoriyaga biriktirish, chegirma vaqt oralig‘i va rasmlarni bitta boshqaruv yuzasidan boshqaring.'),
        meta: [
          { label: tr(uiLang, 'Source', 'Источник', 'Manba'), value: state.source || 'database' },
          { label: tr(uiLang, 'Write access', 'Доступ на запись', 'Yozish huquqi'), value: state.readOnly ? tr(uiLang, 'Read only', 'Только чтение', 'Faqat o‘qish') : tr(uiLang, 'Writable', 'Доступно', 'Yozish mumkin') },
        ],
      })}
      ${renderMetricGrid([
        { label: t('products'), value: String(state.products.length), tone: 'accent', helper: tr(uiLang, 'Products in current source', 'Товары в текущем источнике', 'Joriy manbadagi mahsulotlar') },
        { label: t('active'), value: String(activeCount), tone: 'success', helper: tr(uiLang, 'Available to customers', 'Доступно клиентам', 'Mijozlar uchun ochiq') },
        { label: t('discounts'), value: String(discountedCount), tone: 'warning', helper: tr(uiLang, 'Items with price drops', 'Позиции со скидкой', 'Narxi tushirilganlar') },
        { label: t('flags'), value: String(featuredCount), helper: tr(uiLang, 'Recommended, popular, or new', 'Рекомендуемые, популярные или новые', 'Tavsiya etilgan, ommabop yoki yangi') },
      ])}
      ${renderSectionCard({
        title: t('products_management'),
        description: tr(uiLang, 'Search, filter, reorder, and maintain media-rich menu items while preserving current backend write rules.', 'Ищите, фильтруйте, сортируйте и поддерживайте товары с медиа, сохраняя текущие правила записи бэкенда.', 'Qidiring, filtrlang, qayta tartiblang va media boy menyu elementlarini joriy backend yozish qoidalarini saqlagan holda boshqaring.'),
        actions: state.readOnly
          ? statusBadge('warning', t('source_read_only').replace('{source}', state.source))
          : `<button class="btn btn-primary" id="add-product">${escapeHtml(t('add_product'))}</button>`,
        body: `
          <div class="toolbar">
            <input id="products-search" placeholder="${escapeHtml(t('search_products'))}" value="${escapeHtml(state.search)}" />
            <select id="products-category-filter">
              <option value="">${escapeHtml(t('all_categories'))}</option>
              ${state.categories.map((cat) => `<option value="${cat.id}" ${String(cat.id) === String(state.categoryId) ? 'selected' : ''}>${escapeHtml(pickLocalized(cat, 'name', uiLang))}</option>`).join('')}
            </select>
          </div>
          <div id="products-table"></div>
        `,
      })}
    `;

    const tableNode = container.querySelector('#products-table');
    const columns = [
      { key: 'id', label: t('id'), sortable: true },
      {
        key: 'imageUrl',
        label: t('image'),
        sortable: false,
        render: (row) => {
          const imageUrl = (row.imageUrl || '').trim();
          if (!imageUrl) return '-';
          return `<img src="${escapeHtml(imageUrl)}" alt="product" style="width:52px;height:52px;border-radius:16px;object-fit:cover" />`;
        },
      },
      { key: 'title', label: t('title'), sortable: true, render: (row) => escapeHtml(pickLocalized(row, 'title', uiLang)) },
      {
        key: 'categoryName',
        label: t('categories'),
        sortable: true,
        render: (row) => escapeHtml(pickLocalized(row, 'categoryName', uiLang)),
      },
      { key: 'sortOrder', label: t('sort'), sortable: true },
      { key: 'price', label: t('new_price'), sortable: true, render: (row) => formatMoney(row.price) },
      { key: 'oldPrice', label: t('old_price'), sortable: true, render: (row) => (row.oldPrice ? formatMoney(row.oldPrice) : '-') },
      { key: 'isActive', label: t('active'), sortable: true, render: (row) => statusBadge(row.isActive ? 'active' : 'inactive') },
      {
        key: 'isDrink',
        label: t('type'),
        sortable: true,
        render: (row) => statusBadge(row.isDrink ? 'drink' : 'food', row.isDrink ? t('drink') : t('food')),
      },
      {
        key: 'flags',
        label: t('flags'),
        sortable: false,
        render: (row) =>
          [row.isRecommended ? t('recommended') : '', row.isPopular ? t('popular') : '', row.isNew ? t('new_badge') : '']
            .filter(Boolean)
            .map((flag) => statusBadge('flag', flag))
            .join(' '),
      },
    ];
    if (!state.readOnly) {
      columns.push({
        key: 'actions',
        label: t('actions'),
        sortable: false,
        render: (row) => `
          <div class="table-actions">
            <button class="btn btn-sm btn-muted" data-action="up" data-id="${row.id}">${escapeHtml(t('up'))}</button>
            <button class="btn btn-sm btn-muted" data-action="down" data-id="${row.id}">${escapeHtml(t('down'))}</button>
            <button class="btn btn-sm btn-muted" data-action="toggle" data-id="${row.id}">${escapeHtml(row.isActive ? t('disable') : t('enable'))}</button>
            <button class="btn btn-sm btn-muted" data-action="edit" data-id="${row.id}">${escapeHtml(t('edit'))}</button>
            <button class="btn btn-sm btn-danger" data-action="delete" data-id="${row.id}">${escapeHtml(t('delete'))}</button>
          </div>
        `,
      });
    }

    const drawTable = () => {
      renderTable({
        container: tableNode,
        columns,
        rows: filtered,
        state,
        onSortChange: (sortKey, sortDir) => {
          state.sortKey = sortKey;
          state.sortDir = sortDir;
          drawTable();
        },
        emptyText: t('no_data'),
        minWidth: '1180px',
      });

      if (state.readOnly) return;

      tableNode.querySelectorAll('[data-action="up"]').forEach((button) => {
        button.addEventListener('click', async () => {
          await moveProduct(Number(button.dataset.id), -1);
          await render(false);
        });
      });
      tableNode.querySelectorAll('[data-action="down"]').forEach((button) => {
        button.addEventListener('click', async () => {
          await moveProduct(Number(button.dataset.id), 1);
          await render(false);
        });
      });

      tableNode.querySelectorAll('[data-action="toggle"]').forEach((button) => {
        button.addEventListener('click', async () => {
          const id = Number(button.dataset.id);
          const current = state.products.find((item) => item.id === id);
          if (!current) return;
          try {
            const payload = toPayload(current, current, uiLang);
            payload.isActive = !current.isActive;
            const updated = await api.updateProduct(token, id, payload);
            state.products = state.products.map((item) => (
              item.id === id
                ? { ...item, ...updated, isActive: payload.isActive }
                : item
            ));
            showToast(`${t('products')} ${t('updated')}`, 'success');
            await render(true);
          } catch (error) {
            showToast(`${t('toggle_failed')}: ${error.message}`, 'error');
          }
        });
      });

      tableNode.querySelectorAll('[data-action="edit"]').forEach((button) => {
        button.addEventListener('click', async () => {
          const id = Number(button.dataset.id);
          const current = state.products.find((item) => item.id === id);
          if (!current) return;
          const form = await buildProductForm(current);
          if (!form) return;
          try {
            const payload = toPayload(form, current, uiLang);
            let imageUrl = (form.imageUrl || '').trim() || (current.imageUrl || null);
            if (form.imageFile) {
              const uploaded = await api.uploadImage(token, form.imageFile);
              imageUrl = (uploaded.imageUrl || uploaded.path || '').trim() || imageUrl;
            }
            if (form.clearImage) imageUrl = null;
            payload.imageUrl = imageUrl || null;
            await api.updateProduct(token, id, payload);
            showToast(`${t('products')} ${t('updated')}`, 'success');
            await render(true);
          } catch (error) {
            showToast(`${t('update_failed')}: ${error.message}`, 'error');
          }
        });
      });

      tableNode.querySelectorAll('[data-action="delete"]').forEach((button) => {
        button.addEventListener('click', async () => {
          const id = Number(button.dataset.id);
          const ok = await openConfirmModal({
            title: `${t('delete')} ${t('products')}`,
            message: t('this_action_cannot_be_undone'),
            confirmText: t('confirm_delete'),
            cancelText: t('cancel'),
          });
          if (!ok) return;
          try {
            await api.deleteProduct(token, id);
            showToast(`${t('products')} ${t('delete')}`, 'success');
            await render(true);
          } catch (error) {
            showToast(`${t('delete_failed')}: ${error.message}`, 'error');
          }
        });
      });
    };

    drawTable();

    container.querySelector('#products-search').addEventListener('input', (event) => {
      state.search = event.target.value;
      render(false);
    });
    container.querySelector('#products-category-filter').addEventListener('change', (event) => {
      state.categoryId = event.target.value;
      render(false);
    });
    if (state.readOnly) return;

    container.querySelector('#add-product').addEventListener('click', async () => {
      const form = await buildProductForm();
      if (!form) return;
      try {
        const payload = toPayload(form, null, uiLang);
        let imageUrl = (form.imageUrl || '').trim() || null;
        if (form.imageFile) {
          const uploaded = await api.uploadImage(token, form.imageFile);
          imageUrl = (uploaded.imageUrl || uploaded.path || '').trim() || imageUrl;
        }
        payload.imageUrl = form.clearImage ? null : imageUrl;
        await api.createProduct(token, payload);
        showToast(`${t('products')} ${t('create')}`, 'success');
        await render(true);
      } catch (error) {
        showToast(`${t('create_failed')}: ${error.message}`, 'error');
      }
    });
  };

  await render();
}
