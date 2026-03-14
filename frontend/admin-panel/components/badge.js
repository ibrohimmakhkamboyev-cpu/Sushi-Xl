import { escapeHtml } from '../models/serializers.js';

export function statusBadge(value, label = null) {
  const text = String(value || 'unknown');
  const normalized = text.toLowerCase();
  let cls = 'badge-neutral';
  if (normalized.includes('pend')) cls = 'badge-warning';
  else if (normalized.includes('deliver') || normalized.includes('done') || normalized.includes('complete')) cls = 'badge-success';
  else if (normalized.includes('cancel') || normalized.includes('fail')) cls = 'badge-danger';
  else if (normalized.includes('process') || normalized.includes('prep')) cls = 'badge-info';
  const shown = String(label ?? text);
  return `<span class="status-badge ${cls}">${escapeHtml(shown)}</span>`;
}
