import { api } from '../services/api.js';
import { escapeHtml, formatDate } from '../models/serializers.js';
import { renderTable } from '../components/table.js';
import { statusBadge } from '../components/badge.js';

const TYPE_OPTIONS = ['info', 'success', 'warning', 'error'];
const DELIVERY_OPTIONS = ['push', 'in_app', 'mailing'];
const LANGS = ['en', 'ru', 'uz'];

function pickLocalized(row, base, uiLang = 'en') {
  if (uiLang === 'ru') return row?.[`${base}Ru`] || row?.[`${base}En`] || row?.[base] || '';
  if (uiLang === 'uz') return row?.[`${base}Uz`] || row?.[`${base}En`] || row?.[base] || '';
  return row?.[`${base}En`] || row?.[base] || '';
}

function tr(uiLang, en, ru, uz) {
  if (uiLang === 'ru') return ru;
  if (uiLang === 'uz') return uz;
  return en;
}

function deliveryLabel(type, uiLang) {
  if (type === 'push') {
    return tr(uiLang, 'Push notification', 'Push-уведомление', 'Push bildirishnoma');
  }
  if (type === 'in_app') {
    return tr(uiLang, 'In-app notification', 'В приложении', 'Ilova ichida');
  }
  return tr(uiLang, 'Mailing / broadcast', 'Рассылка / broadcast', 'Tarqatma / broadcast');
}

function emptyForm() {
  return {
    titleEn: '',
    titleRu: '',
    titleUz: '',
    messageEn: '',
    messageRu: '',
    messageUz: '',
    imageUrl: '',
    type: 'info',
    isActive: true,
    deliveryTypes: ['in_app'],
  };
}

function formFromRow(row) {
  return {
    titleEn: row.titleEn || row.title || '',
    titleRu: row.titleRu || row.title || '',
    titleUz: row.titleUz || row.title || '',
    messageEn: row.messageEn || row.message || '',
    messageRu: row.messageRu || row.message || '',
    messageUz: row.messageUz || row.message || '',
    imageUrl: row.imageUrl || '',
    type: row.type || 'info',
    isActive: row.isActive ?? true,
    deliveryTypes: Array.isArray(row.deliveryTypes) && row.deliveryTypes.length > 0
      ? row.deliveryTypes
      : ['in_app'],
  };
}

function firstNonEmpty(values) {
  for (const value of values) {
    const next = String(value || '').trim();
    if (next) return next;
  }
  return '';
}

function collectForm(formNode) {
  const checked = formNode.querySelectorAll('input[name="deliveryTypes"]:checked');
  return {
    titleEn: String(formNode.titleEn?.value || '').trim(),
    titleRu: String(formNode.titleRu?.value || '').trim(),
    titleUz: String(formNode.titleUz?.value || '').trim(),
    messageEn: String(formNode.messageEn?.value || '').trim(),
    messageRu: String(formNode.messageRu?.value || '').trim(),
    messageUz: String(formNode.messageUz?.value || '').trim(),
    imageUrl: String(formNode.imageUrl?.value || '').trim(),
    imageFile: formNode.imageFile?.files?.[0] || null,
    type: String(formNode.type?.value || 'info').trim() || 'info',
    isActive: Boolean(formNode.isActive?.checked),
    deliveryTypes: [...checked].map((item) => String(item.value).trim()),
  };
}

function validateFormData(data, uiLang) {
  if (!Array.isArray(data.deliveryTypes) || data.deliveryTypes.length === 0) {
    return tr(
      uiLang,
      'Select at least one delivery type.',
      'Выберите хотя бы один тип доставки.',
      'Kamida bitta yuborish turini tanlang.',
    );
  }
  const hasTitle = Boolean(firstNonEmpty([data.titleEn, data.titleRu, data.titleUz]));
  const hasMessage = Boolean(firstNonEmpty([data.messageEn, data.messageRu, data.messageUz]));
  if (!hasTitle || !hasMessage) {
    return tr(
      uiLang,
      'Fill at least one language title and message.',
      'Заполните заголовок и сообщение хотя бы на одном языке.',
      'Kamida bitta tilda sarlavha va xabarni to‘ldiring.',
    );
  }
  return '';
}

function normalizePayload(data, current = null) {
  const title = firstNonEmpty([
    data.titleEn,
    data.titleRu,
    data.titleUz,
    current?.titleEn,
    current?.titleRu,
    current?.titleUz,
    current?.title,
  ]);
  const message = firstNonEmpty([
    data.messageEn,
    data.messageRu,
    data.messageUz,
    current?.messageEn,
    current?.messageRu,
    current?.messageUz,
    current?.message,
  ]);
  return {
    title,
    message,
    titleEn: data.titleEn || current?.titleEn || title,
    titleRu: data.titleRu || current?.titleRu || title,
    titleUz: data.titleUz || current?.titleUz || title,
    messageEn: data.messageEn || current?.messageEn || message,
    messageRu: data.messageRu || current?.messageRu || message,
    messageUz: data.messageUz || current?.messageUz || message,
    deliveryTypes: data.deliveryTypes,
    imageUrl: data.imageUrl || '',
    type: data.type || 'info',
    isActive: Boolean(data.isActive),
  };
}

function drawPreview(previewRoot, data, lang, uiLang) {
  const title = firstNonEmpty([
    lang === 'en' ? data.titleEn : '',
    lang === 'ru' ? data.titleRu : '',
    lang === 'uz' ? data.titleUz : '',
    data.titleEn,
    data.titleRu,
    data.titleUz,
  ]);
  const message = firstNonEmpty([
    lang === 'en' ? data.messageEn : '',
    lang === 'ru' ? data.messageRu : '',
    lang === 'uz' ? data.messageUz : '',
    data.messageEn,
    data.messageRu,
    data.messageUz,
  ]);
  const image = String(data.imageUrl || '').trim();
  previewRoot.innerHTML = `
    <div class="notification-preview-card">
      <div class="notification-preview-top">
        ${image
          ? `<img src="${escapeHtml(image)}" alt="preview" class="notification-preview-image" />`
          : `<div class="notification-preview-placeholder">${escapeHtml(tr(uiLang, 'No image', 'Нет изображения', 'Rasm yo‘q'))}</div>`}
      </div>
      <div class="notification-preview-body">
        <h4>${escapeHtml(title || tr(uiLang, 'Untitled notification', 'Уведомление без заголовка', 'Sarlavhasiz bildirishnoma'))}</h4>
        <p>${escapeHtml(message || tr(uiLang, 'No message yet', 'Сообщение не заполнено', 'Xabar kiritilmagan'))}</p>
      </div>
    </div>
  `;
}

function summarizeDeliveryLogs(logs = []) {
  const failed = logs
    .filter((row) => String(row?.status || '').toLowerCase() === 'failed')
    .map((row) => String(row?.message || '').trim())
    .filter(Boolean);
  return failed.join(' | ');
}

export async function renderNotifications(ctx) {
  const {
    container,
    token,
    openConfirmModal,
    showToast,
    uiLang = 'en',
    t = (key) => key,
  } = ctx;
  const state = {
    rows: [],
    sortKey: 'id',
    sortDir: 'desc',
    editingId: null,
    formLang: 'en',
  };

  async function loadRows() {
    const res = await api.listNotifications(token);
    state.rows = (res.results || []).map((row) => ({
      ...row,
      deliveryTypes: Array.isArray(row.deliveryTypes) && row.deliveryTypes.length
        ? row.deliveryTypes
        : ['in_app'],
    }));
  }

  async function renderPage(activeForm = null) {
    container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_notifications'))}</div>`;
    try {
      await loadRows();
    } catch (error) {
      container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_notifications'))}: ${escapeHtml(error.message)}</div>`;
      return;
    }

    const editing = state.editingId != null;
    const currentForm = activeForm || (editing
      ? formFromRow(state.rows.find((row) => row.id === state.editingId) || {})
      : emptyForm());

    const deliveryChecks = DELIVERY_OPTIONS.map((item) => {
      const checked = currentForm.deliveryTypes.includes(item) ? 'checked' : '';
      return `
        <label class="delivery-option">
          <input type="checkbox" name="deliveryTypes" value="${escapeHtml(item)}" ${checked} />
          <span>${escapeHtml(deliveryLabel(item, uiLang))}</span>
        </label>
      `;
    }).join('');

    const langButtons = LANGS.map((lang) => {
      const activeClass = state.formLang === lang ? 'active' : '';
      return `<button type="button" class="lang-tab ${activeClass}" data-lang-tab="${lang}">${lang.toUpperCase()}</button>`;
    }).join('');

    container.innerHTML = `
      <div class="notifications-page-grid">
        <section class="panel notifications-table-panel">
          <div class="panel-head split">
            <h2>${escapeHtml(t('notifications'))}</h2>
            <button type="button" class="btn btn-muted" id="notification-refresh">${escapeHtml(t('refresh'))}</button>
          </div>
          <div id="notifications-table"></div>
        </section>

        <section class="panel form-panel notifications-form-panel">
          <div class="panel-head split">
            <h2>${escapeHtml(editing ? tr(uiLang, 'Edit notification', 'Изменить уведомление', 'Bildirishnomani tahrirlash') : tr(uiLang, 'Create notification', 'Создать уведомление', 'Bildirishnoma yaratish'))}</h2>
            <div class="toolbar">
              ${editing ? `<button type="button" class="btn btn-muted" id="notification-cancel-edit">${escapeHtml(tr(uiLang, 'Cancel edit', 'Отмена', 'Bekor qilish'))}</button>` : ''}
              <button type="button" class="btn btn-muted" id="notification-reset">${escapeHtml(tr(uiLang, 'Reset form', 'Очистить форму', 'Formani tozalash'))}</button>
            </div>
          </div>
          <form id="notification-form" class="inline-form-grid">
            <label class="field">
              <span>${escapeHtml(tr(uiLang, 'Notification type', 'Тип уведомления', 'Bildirishnoma turi'))}</span>
              <select name="type">
                ${TYPE_OPTIONS.map((item) => {
                  const selected = currentForm.type === item ? 'selected' : '';
                  return `<option value="${escapeHtml(item)}" ${selected}>${escapeHtml(item)}</option>`;
                }).join('')}
              </select>
            </label>
            <fieldset class="field">
              <legend>${escapeHtml(tr(uiLang, 'Notification delivery type', 'Тип доставки уведомления', 'Bildirishnoma yuborish turi'))}</legend>
              <div class="delivery-grid">${deliveryChecks}</div>
            </fieldset>
            <div class="lang-tabs">${langButtons}</div>
            <div class="lang-pane ${state.formLang === 'en' ? 'active' : ''}" data-lang-pane="en">
              <label class="field">
                <span>${escapeHtml(tr(uiLang, 'Title (EN)', 'Заголовок (EN)', 'Sarlavha (EN)'))}</span>
                <input name="titleEn" value="${escapeHtml(currentForm.titleEn)}" />
              </label>
              <label class="field">
                <span>${escapeHtml(tr(uiLang, 'Message (EN)', 'Сообщение (EN)', 'Xabar (EN)'))}</span>
                <textarea name="messageEn" rows="4">${escapeHtml(currentForm.messageEn)}</textarea>
              </label>
            </div>
            <div class="lang-pane ${state.formLang === 'ru' ? 'active' : ''}" data-lang-pane="ru">
              <label class="field">
                <span>${escapeHtml(tr(uiLang, 'Title (RU)', 'Заголовок (RU)', 'Sarlavha (RU)'))}</span>
                <input name="titleRu" value="${escapeHtml(currentForm.titleRu)}" />
              </label>
              <label class="field">
                <span>${escapeHtml(tr(uiLang, 'Message (RU)', 'Сообщение (RU)', 'Xabar (RU)'))}</span>
                <textarea name="messageRu" rows="4">${escapeHtml(currentForm.messageRu)}</textarea>
              </label>
            </div>
            <div class="lang-pane ${state.formLang === 'uz' ? 'active' : ''}" data-lang-pane="uz">
              <label class="field">
                <span>${escapeHtml(tr(uiLang, 'Title (UZ)', 'Заголовок (UZ)', 'Sarlavha (UZ)'))}</span>
                <input name="titleUz" value="${escapeHtml(currentForm.titleUz)}" />
              </label>
              <label class="field">
                <span>${escapeHtml(tr(uiLang, 'Message (UZ)', 'Сообщение (UZ)', 'Xabar (UZ)'))}</span>
                <textarea name="messageUz" rows="4">${escapeHtml(currentForm.messageUz)}</textarea>
              </label>
            </div>
            <label class="field">
              <span>${escapeHtml(tr(uiLang, 'Image URL (optional)', 'URL изображения (опционально)', 'Rasm URL (ixtiyoriy)'))}</span>
              <input name="imageUrl" value="${escapeHtml(currentForm.imageUrl)}" />
            </label>
            <label class="field">
              <span>${escapeHtml(tr(uiLang, 'Upload image', 'Загрузить изображение', 'Rasm yuklash'))}</span>
              <input type="file" name="imageFile" accept="image/*" />
            </label>
            <label class="field field-checkbox">
              <input type="checkbox" name="isActive" ${currentForm.isActive ? 'checked' : ''} />
              <span>${escapeHtml(t('active'))}</span>
            </label>
            <div>
              <p class="notification-preview-title">${escapeHtml(tr(uiLang, 'Preview', 'Предпросмотр', 'Ko‘rinish'))}</p>
              <div id="notification-preview"></div>
            </div>
            <div class="form-actions-row">
              <button type="submit" class="btn btn-primary">${escapeHtml(editing ? t('update') : tr(uiLang, 'Send notification', 'Отправить уведомление', 'Bildirishnoma yuborish'))}</button>
            </div>
          </form>
        </section>
      </div>
    `;

    const formNode = container.querySelector('#notification-form');
    const previewRoot = container.querySelector('#notification-preview');
    const tableRoot = container.querySelector('#notifications-table');

    const drawFormPreview = () => {
      const formData = collectForm(formNode);
      drawPreview(previewRoot, formData, state.formLang, uiLang);
    };
    drawFormPreview();

    formNode.querySelectorAll('input,textarea,select').forEach((node) => {
      node.addEventListener('input', drawFormPreview);
      node.addEventListener('change', drawFormPreview);
    });
    formNode.querySelectorAll('[data-lang-tab]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.formLang = btn.dataset.langTab;
        const snapshot = collectForm(formNode);
        renderPage(snapshot);
      });
    });

    formNode.addEventListener('submit', async (event) => {
      event.preventDefault();
      const formData = collectForm(formNode);
      const validationError = validateFormData(formData, uiLang);
      if (validationError) {
        showToast(validationError, 'error');
        return;
      }
      let imageUrl = formData.imageUrl;
      if (formData.imageFile) {
        try {
          const uploaded = await api.uploadImage(token, formData.imageFile);
          imageUrl = (uploaded.imageUrl || uploaded.path || '').trim() || imageUrl;
        } catch (error) {
          showToast(`${tr(uiLang, 'Image upload failed', 'Ошибка загрузки изображения', 'Rasm yuklash xatosi')}: ${error.message}`, 'error');
          return;
        }
      }
      const currentRow = editing
        ? state.rows.find((row) => row.id === state.editingId) || null
        : null;
      const payload = normalizePayload({ ...formData, imageUrl }, currentRow);
      try {
        let response;
        if (editing) {
          response = await api.updateNotification(token, state.editingId, payload);
        } else {
          response = await api.createNotification(token, payload);
        }
        const deliveryError = summarizeDeliveryLogs(response?.deliveryLogs || []);
        if (deliveryError) {
          showToast(`${tr(uiLang, 'Notification saved, but push delivery failed', 'Уведомление сохранено, но push не доставлен', 'Bildirishnoma saqlandi, lekin push yuborilmadi')}: ${deliveryError}`, 'error');
        } else {
          showToast(editing ? t('notification_updated') : t('notification_created'), 'success');
        }
        state.editingId = null;
        await renderPage();
      } catch (error) {
        const action = editing ? t('update_failed') : t('create_failed');
        showToast(`${action}: ${error.message}`, 'error');
      }
    });

    const resetButton = container.querySelector('#notification-reset');
    if (resetButton) {
      resetButton.addEventListener('click', async () => {
        state.editingId = null;
        await renderPage();
      });
    }
    const cancelEditButton = container.querySelector('#notification-cancel-edit');
    if (cancelEditButton) {
      cancelEditButton.addEventListener('click', async () => {
        state.editingId = null;
        await renderPage();
      });
    }

    const columns = [
      { key: 'id', label: t('id'), sortable: true },
      {
        key: 'title',
        label: t('title'),
        sortable: true,
        render: (row) => escapeHtml(pickLocalized(row, 'title', uiLang)),
      },
      {
        key: 'message',
        label: t('message'),
        sortable: false,
        render: (row) => escapeHtml(pickLocalized(row, 'message', uiLang)).slice(0, 120),
      },
      {
        key: 'deliveryTypes',
        label: tr(uiLang, 'Delivery', 'Доставка', 'Yuborish'),
        sortable: false,
        render: (row) => escapeHtml((row.deliveryTypes || []).map((item) => deliveryLabel(item, uiLang)).join(', ')),
      },
      { key: 'type', label: t('type'), sortable: true, render: (row) => statusBadge(row.type || 'info') },
      {
        key: 'isActive',
        label: t('active'),
        sortable: true,
        render: (row) => statusBadge(row.isActive ? 'active' : 'inactive'),
      },
      {
        key: 'imageUrl',
        label: t('image'),
        sortable: false,
        render: (row) => {
          const image = String(row.imageUrl || '').trim();
          if (!image) return '-';
          return `<a href="${escapeHtml(image)}" target="_blank" rel="noreferrer">${escapeHtml(t('view'))}</a>`;
        },
      },
      { key: 'createdAt', label: t('created'), sortable: true, render: (row) => formatDate(row.createdAt) },
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

    renderTable({
      container: tableRoot,
      columns,
      rows: state.rows,
      state,
      onSortChange: (sortKey, sortDir) => {
        state.sortKey = sortKey;
        state.sortDir = sortDir;
        renderPage(collectForm(formNode));
      },
      emptyText: tr(uiLang, 'No data', 'Нет данных', 'Maʼlumot yoʻq'),
    });

    tableRoot.querySelectorAll('[data-action="edit"]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const id = Number(btn.dataset.id);
        const current = state.rows.find((row) => row.id === id);
        if (!current) return;
        state.editingId = id;
        state.formLang = 'en';
        await renderPage(formFromRow(current));
      });
    });
    tableRoot.querySelectorAll('[data-action="delete"]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const id = Number(btn.dataset.id);
        let ok = false;
        try {
          ok = await openConfirmModal({
            title: t('delete_notification_title'),
            message: t('delete_notification_message'),
            confirmText: t('confirm_delete'),
            cancelText: t('cancel'),
          });
        } catch (_) {
          ok = window.confirm(t('delete_notification_message'));
        }
        if (!ok) return;
        try {
          await api.deleteNotification(token, id);
          if (state.editingId === id) state.editingId = null;
          showToast(t('notification_deleted'), 'success');
          await renderPage();
        } catch (error) {
          showToast(`${t('delete_failed')}: ${error.message}`, 'error');
        }
      });
    });

    const refreshButton = container.querySelector('#notification-refresh');
    refreshButton?.addEventListener('click', async () => {
      await renderPage(collectForm(formNode));
    });
  }

  await renderPage();
}
