const ADMIN_KEY = 'sushixl_admin_profile';
let memoryToken = '';

export function getToken() {
  return memoryToken;
}

export function setToken(token) {
  memoryToken = String(token || '').trim();
}

export function getAdminProfile() {
  const raw = sessionStorage.getItem(ADMIN_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    sessionStorage.removeItem(ADMIN_KEY);
    return null;
  }
}

export function setAdminProfile(profile) {
  if (!profile) {
    sessionStorage.removeItem(ADMIN_KEY);
    return;
  }
  sessionStorage.setItem(ADMIN_KEY, JSON.stringify(profile));
}

export function clearAuth() {
  memoryToken = '';
  sessionStorage.removeItem(ADMIN_KEY);
}
