import { escapeHtml } from '../models/serializers.js';

export function statusBadge(value, label = null) {
  const text = String(value || 'unknown');
  const normalized = text.toLowerCase();
  let cls = 'badge-neutral';
  if (
    normalized.includes('paid')
    || normalized.includes('deliver')
    || normalized.includes('done')
    || normalized.includes('complete')
    || normalized.includes('active')
    || normalized.includes('success')
  ) {
    cls = 'badge-success';
  } else if (
    normalized.includes('cancel')
    || normalized.includes('fail')
    || normalized.includes('refund')
    || normalized.includes('inactive')
  ) {
    cls = 'badge-danger';
  } else if (
    normalized.includes('process')
    || normalized.includes('prep')
    || normalized.includes('way')
    || normalized.includes('info')
    || normalized.includes('drink')
  ) {
    cls = 'badge-info';
  } else if (
    normalized.includes('pend')
    || normalized.includes('new')
    || normalized.includes('warn')
    || normalized.includes('unpaid')
  ) {
    cls = 'badge-warning';
  }
  const shown = String(label ?? text);
  return `<span class="status-badge ${cls}"><span class="status-badge-dot"></span>${escapeHtml(shown)}</span>`;
}
