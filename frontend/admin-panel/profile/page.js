import { api } from '../services/api.js';
import { escapeHtml } from '../models/serializers.js';
import { setAdminProfile, getAdminProfile } from '../services/auth.js';
import { renderPageHeader, renderSectionCard, tr } from '../components/page-shell.js';

export async function renderProfile(ctx) {
  const { container, token, showToast, refreshApp, uiLang = 'en', t = (key) => key } = ctx;
  container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_profile'))}</div>`;

  try {
    const profile = await api.getProfile(token);
    container.innerHTML = `
      ${renderPageHeader({
        eyebrow: tr(uiLang, 'Administrator account', 'Аккаунт администратора', 'Administrator hisobi'),
        title: tr(uiLang, 'Profile and access', 'Профиль и доступ', 'Profil va kirish'),
        description: tr(uiLang, 'Update the administrator identity shown across the suite and rotate the password without changing the underlying auth flow.', 'Обновляйте личность администратора, видимую по всей системе, и меняйте пароль без изменения базового auth-потока.', 'Butun panel bo‘ylab ko‘rinadigan administrator ma’lumotlarini yangilang va asosiy autentifikatsiya oqimini o‘zgartirmasdan parolni almashtiring.') })}
      ${renderSectionCard({
        title: t('profile_title'),
        description: tr(uiLang, 'Security-sensitive fields are kept minimal and aligned with the existing backend profile endpoint.', 'Чувствительные поля сведены к минимуму и соответствуют существующему profile endpoint бэкенда.', 'Xavfsizlikka sezgir maydonlar minimal holatda bo‘lib, mavjud backend profile endpointiga mos keladi.'),
        body: `
        <form id="profile-form" class="inline-form-grid">
          <label class="field">
            <span>${escapeHtml(t('email'))}</span>
            <input value="${escapeHtml(profile.email)}" disabled />
          </label>
          <label class="field">
            <span>${escapeHtml(t('full_name'))}</span>
            <input name="fullName" value="${escapeHtml(profile.fullName || '')}" required />
          </label>
          <label class="field">
            <span>${escapeHtml(t('new_password'))}</span>
            <input name="password" type="password" minlength="8" placeholder="${escapeHtml(t('password_hint'))}" />
          </label>
          <div class="form-actions-row">
            <button type="submit" class="btn btn-primary">${escapeHtml(t('save_profile'))}</button>
          </div>
        </form>
        `,
      })}
    `;

    container.querySelector('#profile-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      const form = event.target;
      const payload = {
        fullName: form.fullName.value.trim(),
      };
      if (form.password.value.trim()) {
        payload.password = form.password.value.trim();
      }
      try {
        const updated = await api.updateProfile(token, payload);
        const current = getAdminProfile() || {};
        setAdminProfile({ ...current, ...updated, fullName: updated.fullName });
        showToast(t('profile_updated'), 'success');
        refreshApp();
      } catch (error) {
        showToast(`${t('update_failed')}: ${error.message}`, 'error');
      }
    });
  } catch (error) {
    container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_profile'))}: ${escapeHtml(error.message)}</div>`;
  }
}
