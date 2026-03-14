import { api } from '../services/api.js';
import { escapeHtml } from '../models/serializers.js';
import { setAdminProfile, getAdminProfile } from '../services/auth.js';

export async function renderProfile(ctx) {
  const { container, token, showToast, refreshApp, t = (key) => key } = ctx;
  container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_profile'))}</div>`;

  try {
    const profile = await api.getProfile(token);
    container.innerHTML = `
      <section class="panel form-panel">
        <div class="panel-head">
          <h2>${escapeHtml(t('profile_title'))}</h2>
        </div>
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
      </section>
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
