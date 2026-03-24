import { api } from '../services/api.js';
import { escapeHtml } from '../models/serializers.js';
import { renderTable } from '../components/table.js';
import { statusBadge } from '../components/badge.js';
import { renderMetricGrid, renderPageHeader, renderSectionCard, tr } from '../components/page-shell.js';

function pickLocalized(row, base, uiLang = 'en') {
  if (uiLang === 'ru') return row?.[`${base}Ru`] || row?.[`${base}En`] || row?.[base] || '';
  if (uiLang === 'uz') return row?.[`${base}Uz`] || row?.[`${base}En`] || row?.[base] || '';
  return row?.[`${base}En`] || row?.[base] || '';
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const text = String(value || '').trim();
    if (text) return text;
  }
  return '';
}

function firstOptional(...values) {
  for (const value of values) {
    if (value === null || value === undefined) continue;
    const text = String(value).trim();
    if (text) return text;
  }
  return '';
}

function actionLabel(actionType, t) {
  const map = {
    none: t('none'),
    open_product: t('open_product'),
    open_products: t('open_products'),
    open_category: t('open_category'),
    open_discounts: t('open_discounts'),
    open_url: t('open_url'),
  };
  return map[actionType] || actionType;
}

function describeBannerTarget(row, state, uiLang, t) {
  const actionType = String(row?.actionType || 'none').trim().toLowerCase();
  if (actionType === 'open_product') {
    const productId = Number(row?.productId || 0);
    const product = state.products.find((item) => Number(item.id) === productId);
    if (!productId) {
      return tr(uiLang, 'No product linked', 'Товар не привязан', 'Mahsulot bog‘lanmagan');
    }
    const title = product ? pickLocalized(product, 'title', uiLang) : `#${productId}`;
    return `${actionLabel(actionType, t)}: ${title}`;
  }
  if (actionType === 'open_products') {
    const linked = Array.isArray(row?.linkedProductIds) ? row.linkedProductIds : row?.productIds || [];
    const count = linked.filter((item) => Number(item) > 0).length;
    return count > 0
      ? `${actionLabel(actionType, t)}: ${count}`
      : tr(uiLang, 'No products linked', 'Товары не привязаны', 'Mahsulotlar bog‘lanmagan');
  }
  if (actionType === 'open_category') {
    const categoryId = Number(row?.categoryId || 0);
    const category = state.categories.find((item) => Number(item.id) === categoryId);
    if (!categoryId) {
      return tr(uiLang, 'No category linked', 'Категория не привязана', 'Kategoriya bog‘lanmagan');
    }
    return `${actionLabel(actionType, t)}: ${category ? pickLocalized(category, 'name', uiLang) : `#${categoryId}`}`;
  }
  if (actionType === 'open_discounts') {
    return tr(uiLang, 'Opens discounts screen', 'Открывает экран скидок', 'Chegirmalar ekranini ochadi');
  }
  if (actionType === 'open_url') {
    return String(row?.targetUrl || '').trim() || tr(uiLang, 'No URL set', 'URL не задан', 'URL kiritilmagan');
  }
  return tr(uiLang, 'Does not open anything', 'Ничего не открывает', 'Hech narsa ochmaydi');
}

function normalizeBannerPayload(form, current = null) {
  const title = firstNonEmpty(
    form.title,
    current?.title,
    form.titleRu,
    form.titleEn,
    form.titleUz,
  );
  const subtitle = firstOptional(
    form.subtitle,
    current?.subtitle,
    form.subtitleRu,
    form.subtitleEn,
    form.subtitleUz,
  ) || null;
  const actionType = String(form.actionType || 'none').trim().toLowerCase();
  const titleEn = firstNonEmpty(form.titleEn, current?.titleEn, title);
  const titleRu = firstNonEmpty(form.titleRu, current?.titleRu, title);
  const titleUz = firstNonEmpty(form.titleUz, current?.titleUz, title);
  const subtitleEn = firstOptional(form.subtitleEn, current?.subtitleEn, subtitle) || null;
  const subtitleRu = firstOptional(form.subtitleRu, current?.subtitleRu, subtitle) || null;
  const subtitleUz = firstOptional(form.subtitleUz, current?.subtitleUz, subtitle) || null;
  const payload = {
    title,
    titleEn,
    titleRu,
    titleUz,
    subtitle,
    subtitleEn,
    subtitleRu,
    subtitleUz,
    imageUrl: String(form.imageUrl || '').trim(),
    actionType,
    isActive: Boolean(form.isActive),
    sortOrder: Number(form.sortOrder || 0),
  };

  if (actionType === 'open_product') {
    payload.productId = Number(form.productId) || null;
  } else if (actionType === 'open_products') {
    payload.linkedProductIds = (Array.isArray(form.linkedProductIds) ? form.linkedProductIds : [])
      .map((v) => Number(v))
      .filter((v) => Number.isFinite(v) && v > 0);
  } else if (actionType === 'open_category') {
    payload.categoryId = Number(form.categoryId) || null;
  } else if (actionType === 'open_url') {
    payload.targetUrl = String(form.targetUrl || '').trim();
  }
  return payload;
}

export async function renderBanners(ctx) {
  const { container, token, openFormModal, openConfirmModal, showToast, uiLang = 'en', t = (key) => key } = ctx;
  const state = {
    rows: [],
    products: [],
    categories: [],
    sortKey: 'sortOrder',
    sortDir: 'asc',
  };

  const load = async () => {
    const [bannersRes, productsRes, categoriesRes] = await Promise.all([
      api.listBanners(token),
      api.listProducts(token, { limit: 200 }),
      api.listCategories(token),
    ]);
    state.rows = bannersRes.results || [];
    state.products = productsRes.results || [];
    state.categories = categoriesRes.results || [];
  };

  const bannerForm = (initial = {}) =>
    openFormModal({
      title: initial.id ? t('edit_banner') : t('create_banner'),
      submitText: initial.id ? t('update') : t('create'),
      cancelText: t('cancel'),
      initial: {
        title: initial.title || '',
        titleEn: initial.titleEn || initial.title || '',
        titleRu: initial.titleRu || initial.title || '',
        titleUz: initial.titleUz || initial.title || '',
        subtitle: initial.subtitle || '',
        subtitleEn: initial.subtitleEn || initial.subtitle || '',
        subtitleRu: initial.subtitleRu || initial.subtitle || '',
        subtitleUz: initial.subtitleUz || initial.subtitle || '',
        imageUrl: initial.imageUrl || '',
        imageFile: null,
        actionType: initial.actionType || 'none',
        productId: initial.productId ? String(initial.productId) : '',
        categoryId: initial.categoryId ? String(initial.categoryId) : '',
        linkedProductIds: initial.linkedProductIds || initial.productIds || [],
        targetUrl: initial.targetUrl || '',
        isActive: initial.isActive ?? true,
        sortOrder: initial.sortOrder ?? 0,
      },
      fields: [
        { name: 'title', label: t('title_fallback'), required: true },
        { name: 'titleEn', label: t('title_en'), required: true },
        { name: 'titleRu', label: t('title_ru'), required: true },
        { name: 'titleUz', label: t('title_uz'), required: true },
        { name: 'subtitle', label: t('subtitle') },
        { name: 'subtitleEn', label: t('subtitle_en') },
        { name: 'subtitleRu', label: t('subtitle_ru') },
        { name: 'subtitleUz', label: t('subtitle_uz') },
        { name: 'imageUrl', label: t('image_url') },
        { name: 'imageFile', label: t('upload_image'), type: 'file', accept: 'image/*' },
        {
          name: 'actionType',
          label: t('action_type'),
          type: 'select',
          required: true,
          options: [
            { label: actionLabel('none', t), value: 'none' },
            { label: actionLabel('open_product', t), value: 'open_product' },
            { label: actionLabel('open_products', t), value: 'open_products' },
            { label: actionLabel('open_category', t), value: 'open_category' },
            { label: actionLabel('open_discounts', t), value: 'open_discounts' },
            { label: actionLabel('open_url', t), value: 'open_url' },
          ],
        },
        {
          name: 'productId',
          label: t('product'),
          type: 'select',
          options: [
            { label: '-', value: '' },
            ...state.products.map((row) => ({ label: `${pickLocalized(row, 'title', uiLang)} (#${row.id})`, value: String(row.id) })),
          ],
        },
        {
          name: 'categoryId',
          label: t('category'),
          type: 'select',
          options: [
            { label: '-', value: '' },
            ...state.categories.map((row) => ({ label: pickLocalized(row, 'name', uiLang), value: String(row.id) })),
          ],
        },
        {
          name: 'linkedProductIds',
          label: t('linked_products_label'),
          type: 'multiselect',
          selectedLabel: t('selected_products'),
          searchPlaceholder: t('search_products_by_name_or_id'),
          emptyLabel: t('no_products_selected'),
          noResultsLabel: t('no_products_found'),
          options: state.products.map((row) => ({
            label: `${pickLocalized(row, 'title', uiLang)} (#${row.id})`,
            value: String(row.id),
            tagLabel: pickLocalized(row, 'title', uiLang),
          })),
        },
        { name: 'targetUrl', label: t('target_url') },
        { name: 'sortOrder', label: t('sort_order'), type: 'number' },
        { name: 'isActive', label: t('active'), type: 'checkbox' },
      ],
    });

  const render = async () => {
    container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_banners'))}</div>`;
    try {
      await load();
    } catch (error) {
      container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_banners'))}: ${escapeHtml(error.message)}</div>`;
      return;
    }

    const activeCount = state.rows.filter((row) => row.isActive).length;

    container.innerHTML = `
      ${renderPageHeader({
        eyebrow: tr(uiLang, 'Media placements', 'Медиа-размещения', 'Media joylashuvi'),
        title: tr(uiLang, 'Banner control center', 'Центр управления баннерами', 'Banner boshqaruv markazi'),
        description: tr(uiLang, 'Handle homepage storytelling, linked products, and category-driven banner destinations with stronger media presentation.', 'Управляйте визуальными акцентами главной страницы, связанными товарами и переходами по категориям с более сильной подачей медиа.', 'Bosh sahifa hikoyasi, bog‘langan mahsulotlar va kategoriyaga yo‘naltirilgan banner manzillarini kuchliroq media ko‘rinishi bilan boshqaring.'),
      })}
      ${renderMetricGrid([
        { label: t('banners'), value: String(state.rows.length), tone: 'accent', helper: tr(uiLang, 'Total creative placements', 'Всего креативных размещений', 'Jami kreativ joylashuvlar') },
        { label: t('active'), value: String(activeCount), tone: 'success', helper: tr(uiLang, 'Currently visible', 'Сейчас видимы', 'Hozir ko‘rinadigan') },
      ])}
      ${renderSectionCard({
        title: t('banners_management'),
        description: tr(uiLang, 'Upload, target, reorder, and activate storefront banners without losing the existing linking behavior.', 'Загружайте, нацеливайте, сортируйте и активируйте баннеры витрины без потери текущей логики привязки.', 'Joriy bog‘lash xatti-harakatini yo‘qotmasdan bannerlarni yuklang, yo‘naltiring, tartiblang va faollashtiring.'),
        actions: `<button type="button" class="btn btn-primary" id="add-banner">${escapeHtml(t('add_banner'))}</button>`,
        body: '<div id="banners-table"></div>',
      })}
    `;

    const tableRoot = container.querySelector('#banners-table');
    const columns = [
      { key: 'id', label: t('id'), sortable: true },
      {
        key: 'imageUrl',
        label: t('image'),
        sortable: false,
        render: (row) => {
          const image = String(row.imageUrl || '').trim();
          if (!image) return '-';
          return `<img src="${escapeHtml(image)}" alt="banner" style="width:68px;height:42px;border-radius:8px;object-fit:cover" />`;
        },
      },
      { key: 'title', label: t('title'), sortable: true, render: (row) => escapeHtml(pickLocalized(row, 'title', uiLang)) },
      { key: 'subtitle', label: t('subtitle'), sortable: true, render: (row) => escapeHtml(pickLocalized(row, 'subtitle', uiLang) || '-') },
      {
        key: 'actionType',
        label: t('action_type'),
        sortable: true,
        render: (row) => statusBadge(row.actionType || 'none', actionLabel(row.actionType || 'none', t)),
      },
      {
        key: 'destination',
        label: tr(uiLang, 'Destination', 'Назначение', 'Yo‘nalish'),
        sortable: false,
        render: (row) => escapeHtml(describeBannerTarget(row, state, uiLang, t)),
      },
      { key: 'sortOrder', label: t('sort'), sortable: true },
      { key: 'isActive', label: t('active'), sortable: true, render: (row) => statusBadge(row.isActive ? 'active' : 'inactive') },
      {
        key: 'actions',
        label: t('actions'),
        sortable: false,
        render: (row) => `
          <div class="table-actions">
            <button type="button" class="btn btn-sm btn-muted" data-action="edit" data-id="${row.id}">${escapeHtml(t('edit'))}</button>
            <button type="button" class="btn btn-sm btn-danger" data-action="delete" data-id="${row.id}">${escapeHtml(t('delete'))}</button>
          </div>
        `,
      },
    ];

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
        minWidth: '1080px',
      });

      tableRoot.querySelectorAll('[data-action="edit"]').forEach((button) => {
        button.addEventListener('click', async () => {
          const id = Number(button.dataset.id);
          const current = state.rows.find((row) => row.id === id);
          if (!current) return;
          const form = await bannerForm(current);
          if (!form) return;
          try {
            const payload = normalizeBannerPayload(form, current);
            if (!payload.imageUrl && !form.imageFile) {
              showToast(t('banner_image_required'), 'error');
              return;
            }
            if (form.imageFile) {
              const uploaded = await api.uploadImage(token, form.imageFile);
              payload.imageUrl = (uploaded.imageUrl || uploaded.path || '').trim() || payload.imageUrl;
            }
            await api.updateBanner(token, id, payload);
            showToast(t('banner_updated'), 'success');
            await render();
          } catch (error) {
            showToast(`${t('update_failed')}: ${error.message}`, 'error');
          }
        });
      });

      tableRoot.querySelectorAll('[data-action="delete"]').forEach((button) => {
        button.addEventListener('click', async () => {
          const id = Number(button.dataset.id);
          const ok = await openConfirmModal({
            title: t('delete_banner_title'),
            message: t('delete_banner_message'),
            confirmText: t('confirm_delete'),
            cancelText: t('cancel'),
          });
          if (!ok) return;
          try {
            await api.deleteBanner(token, id);
            showToast(t('banner_deleted'), 'success');
            await render();
          } catch (error) {
            showToast(`${t('delete_failed')}: ${error.message}`, 'error');
          }
        });
      });
    };

    draw();

    container.querySelector('#add-banner').addEventListener('click', async () => {
      const form = await bannerForm();
      if (!form) return;
      try {
        const payload = normalizeBannerPayload(form);
        if (!payload.imageUrl && !form.imageFile) {
          showToast(t('banner_image_required'), 'error');
          return;
        }
        if (form.imageFile) {
          const uploaded = await api.uploadImage(token, form.imageFile);
          payload.imageUrl = (uploaded.imageUrl || uploaded.path || '').trim() || payload.imageUrl;
        }
        await api.createBanner(token, payload);
        showToast(t('banner_created'), 'success');
        await render();
      } catch (error) {
        showToast(`${t('create_failed')}: ${error.message}`, 'error');
      }
    });
  };

  await render();
}
