function toText(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (value instanceof Error) return String(value.message || value);
  try {
    const json = JSON.stringify(value);
    if (json && json !== '{}') return json;
  } catch {}
  return String(value);
}

function resolveLocale(uiLang = 'en') {
  if (uiLang === 'ru') return 'ru-RU';
  if (uiLang === 'uz') return 'uz-UZ';
  return 'en-US';
}

export function escapeHtml(value) {
  return toText(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function formatMoney(value, currency = 'UZS', uiLang = 'en') {
  const amount = Number(value || 0);
  return new Intl.NumberFormat(resolveLocale(uiLang), {
    style: 'currency',
    currency,
    maximumFractionDigits: 0,
  }).format(amount);
}

export function formatCompactMoney(value, currency = 'UZS', uiLang = 'en') {
  const amount = Number(value || 0);
  const compact = new Intl.NumberFormat(resolveLocale(uiLang), {
    notation: 'compact',
    maximumFractionDigits: 2,
  }).format(amount);
  return `${currency} ${compact}`;
}

export function formatDate(value) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat('en-GB', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
}

export function normalizeString(value) {
  return String(value ?? '').trim().toLowerCase();
}
