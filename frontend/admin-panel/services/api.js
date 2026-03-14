const isLocalhostRuntime =
  typeof window !== 'undefined' &&
  (window.location.hostname === '127.0.0.1' || window.location.hostname === 'localhost');
export const DEFAULT_API_BASE = isLocalhostRuntime
  ? 'http://127.0.0.1:8010/api/v1'
  : '/api/v1';
const DEFAULT_LIST_LIMIT = 20;
const MAX_LIST_LIMIT = 200;
const MAX_TEXT_QUERY_LENGTH = 200;
const API_BASE_KEY = 'sushixl_admin_api_base';

export function getApiBase() {
  const fromStorage = localStorage.getItem(API_BASE_KEY);
  if (fromStorage && fromStorage.trim()) return fromStorage.trim();
  if (window.__ADMIN_API_BASE__ && String(window.__ADMIN_API_BASE__).trim()) {
    return String(window.__ADMIN_API_BASE__).trim();
  }
  return DEFAULT_API_BASE;
}

export function setApiBase(value) {
  if (!value || !String(value).trim()) {
    localStorage.removeItem(API_BASE_KEY);
    return;
  }
  localStorage.setItem(API_BASE_KEY, String(value).trim());
}

function buildQuery(query = {}) {
  const params = new URLSearchParams();
  const limitKeys = new Set(['limit', 'pageSize', 'page_size', 'take', 'per_page']);
  const offsetKeys = new Set(['offset', 'skip']);
  const textKeys = new Set(['search', 'query', 'title', 'name', 'filter']);

  const normalizeQueryValue = (key, value) => {
    if (value === undefined || value === null || value === '') return undefined;

    if (limitKeys.has(key)) {
      const parsed = Number.parseInt(String(value), 10);
      if (!Number.isFinite(parsed)) return DEFAULT_LIST_LIMIT;
      return Math.max(1, Math.min(MAX_LIST_LIMIT, parsed));
    }

    if (offsetKeys.has(key)) {
      const parsed = Number.parseInt(String(value), 10);
      if (!Number.isFinite(parsed)) return 0;
      return Math.max(0, parsed);
    }

    if (textKeys.has(key)) {
      const text = String(value).trim();
      if (!text) return undefined;
      return text.slice(0, MAX_TEXT_QUERY_LENGTH);
    }

    return value;
  };

  Object.entries(query).forEach(([key, value]) => {
    const normalized = normalizeQueryValue(key, value);
    if (normalized === undefined || normalized === null || normalized === '') return;
    params.set(key, String(normalized));
  });
  const raw = params.toString();
  return raw ? `?${raw}` : '';
}

function detailToMessage(detail, fallback = 'Request failed') {
  if (detail === undefined || detail === null) return fallback;
  if (typeof detail === 'string') return detail || fallback;
  if (typeof detail === 'number' || typeof detail === 'boolean') return String(detail);
  if (detail instanceof Error) {
    const errMessage = String(detail.message || '').trim();
    return errMessage || fallback;
  }
  if (Array.isArray(detail)) {
    const parts = detail
      .map((item) => detailToMessage(item, ''))
      .map((v) => String(v || '').trim())
      .filter(Boolean);
    return parts.length ? parts.join('; ') : fallback;
  }
  if (typeof detail === 'object') {
    if (detail?.detail !== undefined) return detailToMessage(detail.detail, fallback);
    if (typeof detail.message === 'string' && detail.message.trim()) return detail.message.trim();
    if (detail.message !== undefined) {
      const nested = detailToMessage(detail.message, '');
      if (nested) return nested;
    }
    if (typeof detail.msg === 'string' && detail.msg.trim()) return detail.msg.trim();
    if (detail.error !== undefined) {
      const nested = detailToMessage(detail.error, '');
      if (nested) return nested;
    }
    if (detail.reason !== undefined) {
      const nested = detailToMessage(detail.reason, '');
      if (nested) return nested;
    }
    const entries = Object.entries(detail)
      .map(([key, value]) => `${key}: ${detailToMessage(value, '')}`)
      .map((line) => line.trim())
      .filter(Boolean);
    if (entries.length) return entries.join('; ');
    try {
      const json = JSON.stringify(detail);
      if (json && json !== '{}') return json;
    } catch {}
  }
  return fallback;
}

function createHttpError(response, payload, fallback = 'Request failed') {
  const detail = payload?.detail ?? payload?.error ?? payload ?? response.statusText ?? fallback;
  const message = detailToMessage(detail, fallback);
  const error = new Error(message);
  error.status = response.status;
  error.payload = payload;
  return error;
}

function normalizeError(error, fallback = 'Request failed') {
  if (error instanceof Error && typeof error.message === 'string' && error.message.trim()) {
    return error;
  }
  const normalized = new Error(
    detailToMessage(error?.message ?? error?.detail ?? error ?? fallback, fallback),
  );
  if (error && typeof error === 'object' && Number.isFinite(Number(error.status))) {
    normalized.status = Number(error.status);
  }
  if (error && typeof error === 'object' && 'payload' in error) {
    normalized.payload = error.payload;
  }
  return normalized;
}

async function executeJson(base, path, { method = 'GET', token = '', body, query } = {}) {
  const url = `${base}${path}${buildQuery(query)}`;
  const response = await fetch(url, {
    method,
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const hasJson = response.headers.get('content-type')?.includes('application/json');
  const payload = hasJson ? await response.json() : null;

  if (!response.ok) {
    throw createHttpError(response, payload, 'Request failed');
  }

  return payload;
}

function shouldRetryWithDefault(error, currentBase, method = 'GET') {
  if (currentBase === DEFAULT_API_BASE) return false;
  if (!error || typeof error !== 'object') return true;
  if (!('status' in error)) return true;
  const status = Number(error.status);
  if (!Number.isFinite(status)) return true;
  if ([401, 403, 422].includes(status)) return false;
  if (status >= 500) return true;
  if ([404, 405, 408, 429].includes(status)) return true;
  if (status === 400 && ['GET', 'HEAD'].includes(String(method || 'GET').toUpperCase())) return true;
  return false;
}

function dispatchAuthExpired(error) {
  const status = Number(error?.status);
  const message = String(error?.message || '').toLowerCase();
  const isExpiredMessage =
    message.includes('expired access token') ||
    message.includes('session expired') ||
    message.includes('unauthorized');
  if (![401, 403, 419].includes(status) && !isExpiredMessage) return;
  window.dispatchEvent(
    new CustomEvent('admin-auth-expired', {
      detail: { status, message: String(error?.message || 'Unauthorized') },
    }),
  );
}

async function request(path, { method = 'GET', token = '', body, query } = {}) {
  const currentBase = getApiBase();
  try {
    return await executeJson(currentBase, path, { method, token, body, query });
  } catch (error) {
    if (shouldRetryWithDefault(error, currentBase, method)) {
      try {
        const payload = await executeJson(DEFAULT_API_BASE, path, { method, token, body, query });
        setApiBase('');
        return payload;
      } catch (fallbackError) {
        const normalized = normalizeError(fallbackError);
        dispatchAuthExpired(normalized);
        throw normalized;
      }
    }
    const normalized = normalizeError(error);
    dispatchAuthExpired(normalized);
    throw normalized;
  }
}

async function executeUpload(base, path, { token = '', file } = {}) {
  const url = `${base}${path}`;
  const form = new FormData();
  form.append('file', file);
  const response = await fetch(url, {
    method: 'POST',
    credentials: 'include',
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: form,
  });
  const hasJson = response.headers.get('content-type')?.includes('application/json');
  const payload = hasJson ? await response.json() : null;
  if (!response.ok) {
    throw createHttpError(response, payload, 'Upload failed');
  }
  return payload;
}

async function upload(path, { token = '', file } = {}) {
  const currentBase = getApiBase();
  try {
    return await executeUpload(currentBase, path, { token, file });
  } catch (error) {
    if (shouldRetryWithDefault(error, currentBase, 'POST')) {
      try {
        const payload = await executeUpload(DEFAULT_API_BASE, path, { token, file });
        setApiBase('');
        return payload;
      } catch (fallbackError) {
        const normalized = normalizeError(fallbackError, 'Upload failed');
        dispatchAuthExpired(normalized);
        throw normalized;
      }
    }
    const normalized = normalizeError(error, 'Upload failed');
    dispatchAuthExpired(normalized);
    throw normalized;
  }
}

export const api = {
  login: (email, password) => request('/auth/login', { method: 'POST', body: { email, password } }),
  logout: () => request('/auth/logout', { method: 'POST' }),
  getMenu: (lang = 'ru') => request('/menu', { query: { lang } }),

  dashboardStats: (token) => request('/admin/dashboard/stats', { token }),

  listOrders: (token, query) => request('/admin/orders', { token, query }),
  updateOrder: (token, orderId, body) =>
    request(`/admin/orders/${orderId}`, { method: 'PATCH', token, body }),

  listUsers: (token, query) => request('/admin/users', { token, query }),
  createUser: (token, body) => request('/admin/users', { method: 'POST', token, body }),
  updateUser: (token, userId, body) =>
    request(`/admin/users/${userId}`, { method: 'PUT', token, body }),
  deleteUser: (token, userId) =>
    request(`/admin/users/${userId}`, { method: 'DELETE', token }),

  listProducts: (token, query) => request('/admin/products', { token, query }),
  createProduct: (token, body) => request('/admin/products', { method: 'POST', token, body }),
  updateProduct: (token, id, body) =>
    request(`/admin/products/${id}`, { method: 'PUT', token, body }),
  deleteProduct: (token, id) => request(`/admin/products/${id}`, { method: 'DELETE', token }),
  reorderProducts: (token, ids) =>
    request('/admin/products/reorder', { method: 'POST', token, body: { ids } }),

  listCategories: (token) => request('/admin/categories', { token }),
  createCategory: (token, body) => request('/admin/categories', { method: 'POST', token, body }),
  updateCategory: (token, id, body) =>
    request(`/admin/categories/${id}`, { method: 'PUT', token, body }),
  deleteCategory: (token, id) => request(`/admin/categories/${id}`, { method: 'DELETE', token }),
  reorderCategories: (token, ids) =>
    request('/admin/categories/reorder', { method: 'POST', token, body: { ids } }),

  listBanners: (token) => request('/admin/banners', { token }),
  createBanner: (token, body) => request('/admin/banners', { method: 'POST', token, body }),
  updateBanner: (token, id, body) =>
    request(`/admin/banners/${id}`, { method: 'PUT', token, body }),
  deleteBanner: (token, id) => request(`/admin/banners/${id}`, { method: 'DELETE', token }),

  listNotifications: (token) => request('/admin/notifications', { token }),
  createNotification: (token, body) =>
    request('/admin/notifications', { method: 'POST', token, body }),
  updateNotification: (token, id, body) =>
    request(`/admin/notifications/${id}`, { method: 'PUT', token, body }),
  deleteNotification: (token, id) =>
    request(`/admin/notifications/${id}`, { method: 'DELETE', token }),

  listFaqs: (token) => request('/admin/faqs', { token }),
  createFaq: (token, body) => request('/admin/faqs', { method: 'POST', token, body }),
  updateFaq: (token, id, body) => request(`/admin/faqs/${id}`, { method: 'PUT', token, body }),
  deleteFaq: (token, id) => request(`/admin/faqs/${id}`, { method: 'DELETE', token }),

  getSettings: (token) => request('/admin/settings', { token }),
  createSettings: (token, body) => request('/admin/settings', { method: 'POST', token, body }),
  updateSettings: (token, body) => request('/admin/settings', { method: 'PUT', token, body }),
  resetSettings: (token) => request('/admin/settings', { method: 'DELETE', token }),

  getProfile: (token) => request('/admin/profile', { token }),
  updateProfile: (token, body) => request('/admin/profile', { method: 'PUT', token, body }),

  uploadImage: (token, file) => upload('/admin/uploads/image', { token, file }),
};
