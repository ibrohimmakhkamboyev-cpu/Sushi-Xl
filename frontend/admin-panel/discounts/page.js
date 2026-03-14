import { api } from '../services/api.js';
import { escapeHtml, formatMoney } from '../models/serializers.js';
import { renderTable } from '../components/table.js';

const ADMIN_FETCH_LIMIT = 200;

export async function renderDiscounts(ctx) {
  const { container, token, openFormModal, openConfirmModal, showToast, t = (key) => key } = ctx;
  const state = { rows: [], products: [], banners: [], sortKey: 'oldPrice', sortDir: 'desc' };

  const load = async () => {
    const [productsRes, bannersRes] = await Promise.all([
      api.listProducts(token, { limit: ADMIN_FETCH_LIMIT }),
      api.listBanners(token),
    ]);
    state.products = productsRes.results || [];
    state.banners = bannersRes.results || [];

    const discountedRows = state.products.filter((item) => {
      const hasPriceDiscount = Number(item.oldPrice || 0) > Number(item.price || 0);
      const hasSchedule = Boolean((item.discountStartAt || '').trim() || (item.discountEndAt || '').trim());
      return hasPriceDiscount || hasSchedule;
    });

    const byId = new Map(discountedRows.map((item) => [Number(item.id), item]));
    const activeBanners = state.banners.filter((banner) => Boolean(banner?.isActive));

    for (const banner of activeBanners) {
      const productIds = Array.isArray(banner?.productIds) ? banner.productIds : [];
      for (const rawId of productIds) {
        const id = Number(rawId);
        if (!Number.isFinite(id) || id <= 0) continue;
        if (byId.has(id)) continue;
        const product = state.products.find((item) => Number(item.id) === id);
        if (!product) continue;
        byId.set(id, {
          ...product,
          promoSource: 'banner',
          promoBannerTitle: banner.title || '',
        });
      }
    }

    state.rows = Array.from(byId.values());
  };

  const buildDiscountForm = async (current) => {
    const products = state.products;

    return openFormModal({
      title: current ? t('edit_discount') : t('create_discount_title'),
      submitText: current ? t('update') : t('create'),
      cancelText: t('cancel'),
      initial: {
        productId: current ? String(current.id) : '',
        oldPrice: current?.oldPrice ?? current?.price ?? null,
        price: current?.price ?? null,
        discountStartAt: current?.discountStartAt || '',
        discountEndAt: current?.discountEndAt || '',
      },
      fields: [
        {
          name: 'productId',
          label: t('product'),
          type: 'select',
          required: true,
          options: products.map((item) => ({ label: `${item.title} (#${item.id})`, value: String(item.id) })),
        },
        { name: 'oldPrice', label: t('original_price'), type: 'number', required: true },
        { name: 'price', label: t('discounted_price'), type: 'number', required: true },
        { name: 'discountStartAt', label: t('start_datetime_optional'), type: 'datetime-local' },
        { name: 'discountEndAt', label: t('end_datetime_optional'), type: 'datetime-local' },
      ],
    });
  };

  const render = async () => {
    container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_discounts'))}</div>`;
    try {
      await load();
    } catch (error) {
      container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_discounts'))}: ${escapeHtml(error.message)}</div>`;
      return;
    }

    container.innerHTML = `
      <section class="panel">
        <div class="panel-head split">
          <h2>${escapeHtml(t('discounts_promotions'))}</h2>
          <button class="btn btn-primary" id="create-discount">${escapeHtml(t('add_discount'))}</button>
        </div>
        <div id="discounts-table"></div>
      </section>
    `;

    const tableNode = container.querySelector('#discounts-table');
    const columns = [
      { key: 'id', label: t('id'), sortable: true },
      { key: 'title', label: t('product'), sortable: true, render: (row) => escapeHtml(row.title || row.name) },
      { key: 'oldPrice', label: t('old_price'), sortable: true, render: (row) => formatMoney(row.oldPrice) },
      { key: 'price', label: t('new_price'), sortable: true, render: (row) => formatMoney(row.price) },
      {
        key: 'discountStartAt',
        label: t('start'),
        sortable: true,
        render: (row) => escapeHtml(row.discountStartAt || '-'),
      },
      {
        key: 'discountEndAt',
        label: t('end'),
        sortable: true,
        render: (row) => escapeHtml(row.discountEndAt || '-'),
      },
      {
        key: 'discount',
        label: t('discount'),
        sortable: false,
        render: (row) => {
          const old = Number(row.oldPrice || 0);
          const next = Number(row.price || 0);
          if (old > 0 && next > 0) {
            const pct = Math.round(((old - next) / old) * 100);
            return `<strong>${pct}%</strong>`;
          }
          if (row.promoSource === 'banner') {
            const bannerTitle = String(row.promoBannerTitle || '').trim();
            return bannerTitle
              ? `<span title="${escapeHtml(bannerTitle)}">${escapeHtml(t('banner_promo'))}</span>`
              : `<span>${escapeHtml(t('banner_promo'))}</span>`;
          }
          return '<span>-</span>';
        },
      },
      {
        key: 'actions',
        label: t('actions'),
        sortable: false,
        render: (row) => `
          <div class="table-actions">
            <button class="btn btn-sm btn-muted" data-action="edit" data-id="${row.id}">${escapeHtml(t('edit'))}</button>
            <button class="btn btn-sm btn-danger" data-action="remove" data-id="${row.id}">${escapeHtml(t('remove'))}</button>
          </div>
        `,
      },
    ];

    const draw = () => {
      renderTable({
        container: tableNode,
        columns,
        rows: state.rows,
        state,
        onSortChange: (sortKey, sortDir) => {
          state.sortKey = sortKey;
          state.sortDir = sortDir;
          draw();
        },
        emptyText: t('no_data'),
      });

      tableNode.querySelectorAll('[data-action="edit"]').forEach((button) => {
        button.addEventListener('click', async () => {
          const id = Number(button.dataset.id);
          const current = state.rows.find((item) => item.id === id);
          if (!current) return;
          const form = await buildDiscountForm(current);
          if (!form) return;

          try {
            await api.updateProduct(token, Number(form.productId), {
              title: current.title,
              description: current.description,
              titleEn: current.titleEn || current.title,
              titleRu: current.titleRu || current.title,
              titleUz: current.titleUz || current.title,
              descriptionEn: current.descriptionEn || current.description,
              descriptionRu: current.descriptionRu || current.description,
              descriptionUz: current.descriptionUz || current.description,
              imageUrl: current.imageUrl,
              categoryId: current.categoryId,
              price: Number(form.price),
              oldPrice: Number(form.oldPrice),
              discountStartAt: (form.discountStartAt || '').trim() || null,
              discountEndAt: (form.discountEndAt || '').trim() || null,
              sortOrder: Number(current.sortOrder || 0),
              isActive: current.isActive,
              isDrink: current.isDrink,
              isRecommended: current.isRecommended || false,
              isPopular: current.isPopular || false,
              isNew: current.isNew || false,
            });
            showToast(t('discount_updated'), 'success');
            await render();
          } catch (error) {
            showToast(`${t('update_failed')}: ${error.message}`, 'error');
          }
        });
      });

      tableNode.querySelectorAll('[data-action="remove"]').forEach((button) => {
        button.addEventListener('click', async () => {
          const id = Number(button.dataset.id);
          const current = state.rows.find((item) => item.id === id);
          if (!current) return;
          const confirmed = await openConfirmModal({
            title: t('remove_discount_title'),
            message: t('remove_discount_message'),
            confirmText: t('confirm_remove'),
            cancelText: t('cancel'),
          });
          if (!confirmed) return;
          try {
            await api.updateProduct(token, id, {
              title: current.title,
              description: current.description,
              titleEn: current.titleEn || current.title,
              titleRu: current.titleRu || current.title,
              titleUz: current.titleUz || current.title,
              descriptionEn: current.descriptionEn || current.description,
              descriptionRu: current.descriptionRu || current.description,
              descriptionUz: current.descriptionUz || current.description,
              imageUrl: current.imageUrl,
              categoryId: current.categoryId,
              price: current.price,
              oldPrice: null,
              discountStartAt: null,
              discountEndAt: null,
              sortOrder: Number(current.sortOrder || 0),
              isActive: current.isActive,
              isDrink: current.isDrink,
              isRecommended: current.isRecommended || false,
              isPopular: current.isPopular || false,
              isNew: current.isNew || false,
            });
            showToast(t('discount_removed'), 'success');
            await render();
          } catch (error) {
            showToast(`${t('remove_failed')}: ${error.message}`, 'error');
          }
        });
      });
    };

    draw();

    container.querySelector('#create-discount').addEventListener('click', async () => {
      const form = await buildDiscountForm();
      if (!form) return;
      const product = state.products.find((item) => item.id === Number(form.productId));
      if (!product) {
        showToast(t('product_not_found'), 'error');
        return;
      }
      try {
        await api.updateProduct(token, product.id, {
          title: product.title,
          description: product.description,
          titleEn: product.titleEn || product.title,
          titleRu: product.titleRu || product.title,
          titleUz: product.titleUz || product.title,
          descriptionEn: product.descriptionEn || product.description,
          descriptionRu: product.descriptionRu || product.description,
          descriptionUz: product.descriptionUz || product.description,
          imageUrl: product.imageUrl,
          categoryId: product.categoryId,
          price: Number(form.price),
          oldPrice: Number(form.oldPrice),
          discountStartAt: (form.discountStartAt || '').trim() || null,
          discountEndAt: (form.discountEndAt || '').trim() || null,
          sortOrder: Number(product.sortOrder || 0),
          isActive: product.isActive,
          isDrink: product.isDrink,
          isRecommended: product.isRecommended || false,
          isPopular: product.isPopular || false,
          isNew: product.isNew || false,
        });
        showToast(t('discount_created'), 'success');
        await render();
      } catch (error) {
        showToast(`${t('create_failed')}: ${error.message}`, 'error');
      }
    });
  };

  await render();
}
