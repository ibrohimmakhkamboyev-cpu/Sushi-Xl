import { api, getApiBase, setApiBase } from '../services/api.js';
import { escapeHtml } from '../models/serializers.js';
import { renderPageHeader, renderSectionCard, tr } from '../components/page-shell.js';

export async function renderSettings(ctx) {
  const { container, token, showToast, openConfirmModal, uiLang = 'en', t = (key) => key } = ctx;
  container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_settings'))}</div>`;

  try {
    const settings = await api.getSettings(token);
    const apiBase = getApiBase();

    container.innerHTML = `
      ${renderPageHeader({
        eyebrow: tr(uiLang, 'System controls', 'Системные настройки', 'Tizim boshqaruvi'),
        title: tr(uiLang, 'Admin settings', 'Настройки администратора', 'Admin sozlamalari'),
        description: tr(uiLang, 'Manage support communication labels, chat copy, API routing, timezone, and other shared admin behavior without flattening everything into a plain form.', 'Управляйте подписями поддержки, текстами чата, API-маршрутизацией, часовым поясом и другим общим поведением админки без плоской формы.', 'Qo‘llab-quvvatlash yorliqlari, chat matnlari, API marshruti, vaqt zonasi va umumiy admin xatti-harakatlarini oddiy forma ko‘rinishiga tushirmasdan boshqaring.') })}
      ${renderSectionCard({
        title: t('settings_general'),
        description: tr(uiLang, 'Grouped controls for support, chat copy, localization, and environment routing.', 'Сгруппированные настройки для поддержки, чата, локализации и маршрутизации окружения.', 'Qo‘llab-quvvatlash, chat matni, lokalizatsiya va muhit marshrutlari uchun guruhlangan sozlamalar.'),
        actions: `
          <button type="button" id="settings-create" class="btn btn-muted">${escapeHtml(t('create'))}</button>
          <button type="button" id="settings-reset" class="btn btn-danger">${escapeHtml(t('reset_form'))}</button>
        `,
        body: `
        <form id="settings-form" class="inline-form-grid">
          <label class="field">
            <span>${escapeHtml(t('support_phone'))}</span>
            <input name="supportPhone" value="${escapeHtml(settings.supportPhone || '')}" />
          </label>
          <label class="field">
            <span>${escapeHtml(t('timezone'))}</span>
            <input name="timezone" value="${escapeHtml(settings.timezone || 'Asia/Tashkent')}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('currency_code'))}</span>
            <input name="currencyCode" value="${escapeHtml(settings.currencyCode || 'UZS')}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('api_base_url'))}</span>
            <input name="apiBase" value="${escapeHtml(apiBase)}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('call_label_en'))}</span>
            <input name="callLabelEn" value="${escapeHtml(settings.callLabelEn || '')}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('call_label_ru'))}</span>
            <input name="callLabelRu" value="${escapeHtml(settings.callLabelRu || '')}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('call_label_uz'))}</span>
            <input name="callLabelUz" value="${escapeHtml(settings.callLabelUz || '')}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('chat_label_en'))}</span>
            <input name="chatLabelEn" value="${escapeHtml(settings.chatLabelEn || '')}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('chat_label_ru'))}</span>
            <input name="chatLabelRu" value="${escapeHtml(settings.chatLabelRu || '')}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('chat_label_uz'))}</span>
            <input name="chatLabelUz" value="${escapeHtml(settings.chatLabelUz || '')}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('chat_subtitle_en'))}</span>
            <textarea name="chatSubtitleEn" rows="2" required>${escapeHtml(settings.chatSubtitleEn || '')}</textarea>
          </label>
          <label class="field">
            <span>${escapeHtml(t('chat_subtitle_ru'))}</span>
            <textarea name="chatSubtitleRu" rows="2" required>${escapeHtml(settings.chatSubtitleRu || '')}</textarea>
          </label>
          <label class="field">
            <span>${escapeHtml(t('chat_subtitle_uz'))}</span>
            <textarea name="chatSubtitleUz" rows="2" required>${escapeHtml(settings.chatSubtitleUz || '')}</textarea>
          </label>
          <label class="field">
            <span>${escapeHtml(t('chat_intro_en'))}</span>
            <textarea name="chatIntroEn" rows="3" required>${escapeHtml(settings.chatIntroEn || '')}</textarea>
          </label>
          <label class="field">
            <span>${escapeHtml(t('chat_intro_ru'))}</span>
            <textarea name="chatIntroRu" rows="3" required>${escapeHtml(settings.chatIntroRu || '')}</textarea>
          </label>
          <label class="field">
            <span>${escapeHtml(t('chat_intro_uz'))}</span>
            <textarea name="chatIntroUz" rows="3" required>${escapeHtml(settings.chatIntroUz || '')}</textarea>
          </label>
          <div class="form-actions-row">
            <button type="submit" class="btn btn-primary">${escapeHtml(t('save_settings'))}</button>
          </div>
        </form>
        `,
      })}
    `;

    container.querySelector('#settings-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      const form = event.target;
      const payload = {
        supportPhone: form.supportPhone.value.trim(),
        timezone: form.timezone.value.trim(),
        currencyCode: form.currencyCode.value.trim(),
        callLabelEn: form.callLabelEn.value.trim(),
        callLabelRu: form.callLabelRu.value.trim(),
        callLabelUz: form.callLabelUz.value.trim(),
        chatLabelEn: form.chatLabelEn.value.trim(),
        chatLabelRu: form.chatLabelRu.value.trim(),
        chatLabelUz: form.chatLabelUz.value.trim(),
        chatSubtitleEn: form.chatSubtitleEn.value.trim(),
        chatSubtitleRu: form.chatSubtitleRu.value.trim(),
        chatSubtitleUz: form.chatSubtitleUz.value.trim(),
        chatIntroEn: form.chatIntroEn.value.trim(),
        chatIntroRu: form.chatIntroRu.value.trim(),
        chatIntroUz: form.chatIntroUz.value.trim(),
      };
      const nextApiBase = form.apiBase.value.trim();

      try {
        await api.updateSettings(token, payload);
        setApiBase(nextApiBase);
        showToast(t('settings_saved'), 'success');
      } catch (error) {
        showToast(`${t('save_failed')}: ${error.message}`, 'error');
      }
    });

    container.querySelector('#settings-create').addEventListener('click', async () => {
      const form = container.querySelector('#settings-form');
      const payload = {
        supportPhone: form.supportPhone.value.trim(),
        timezone: form.timezone.value.trim(),
        currencyCode: form.currencyCode.value.trim(),
        callLabelEn: form.callLabelEn.value.trim(),
        callLabelRu: form.callLabelRu.value.trim(),
        callLabelUz: form.callLabelUz.value.trim(),
        chatLabelEn: form.chatLabelEn.value.trim(),
        chatLabelRu: form.chatLabelRu.value.trim(),
        chatLabelUz: form.chatLabelUz.value.trim(),
        chatSubtitleEn: form.chatSubtitleEn.value.trim(),
        chatSubtitleRu: form.chatSubtitleRu.value.trim(),
        chatSubtitleUz: form.chatSubtitleUz.value.trim(),
        chatIntroEn: form.chatIntroEn.value.trim(),
        chatIntroRu: form.chatIntroRu.value.trim(),
        chatIntroUz: form.chatIntroUz.value.trim(),
      };
      try {
        await api.createSettings(token, payload);
        showToast(`${t('settings')} ${t('created')}`, 'success');
      } catch (error) {
        showToast(`${t('create_failed')}: ${error.message}`, 'error');
      }
    });

    container.querySelector('#settings-reset').addEventListener('click', async () => {
      const confirmed = await openConfirmModal({
        title: `${t('reset_form')} ${t('settings')}`,
        message: t('settings_general'),
        confirmText: t('confirm_delete'),
        cancelText: t('cancel'),
      });
      if (!confirmed) return;
      try {
        await api.resetSettings(token);
        setApiBase('');
        showToast(`${t('settings')} ${t('updated')}`, 'success');
        await renderSettings(ctx);
      } catch (error) {
        showToast(`${t('update_failed')}: ${error.message}`, 'error');
      }
    });
  } catch (error) {
    container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_settings'))}: ${escapeHtml(error.message)}</div>`;
  }
}
