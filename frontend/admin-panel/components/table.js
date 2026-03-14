import { escapeHtml } from '../models/serializers.js';

function sortRows(rows, sortKey, sortDir) {
  if (!sortKey) return [...rows];
  const dir = sortDir === 'desc' ? -1 : 1;
  return [...rows].sort((a, b) => {
    const av = a?.[sortKey];
    const bv = b?.[sortKey];
    if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
    return String(av ?? '').localeCompare(String(bv ?? '')) * dir;
  });
}

export function renderTable({
  container,
  columns,
  rows,
  state,
  onSortChange,
  emptyText = 'No data',
}) {
  const sorted = sortRows(rows, state.sortKey, state.sortDir);
  const head = columns
    .map((col) => {
      const isActive = state.sortKey === col.key;
      const arrow = !col.sortable ? '' : isActive ? (state.sortDir === 'asc' ? ' ▲' : ' ▼') : '';
      const label = `${escapeHtml(col.label)}${arrow}`;
      return `<th>${col.sortable ? `<button class="table-sort" data-sort="${col.key}">${label}</button>` : label}</th>`;
    })
    .join('');

  const body = sorted.length
    ? sorted
        .map((row) => {
          const cells = columns
            .map((col) => {
              if (col.render) return `<td>${col.render(row)}</td>`;
              return `<td>${escapeHtml(row?.[col.key] ?? '')}</td>`;
            })
            .join('');
          return `<tr>${cells}</tr>`;
        })
        .join('')
    : `<tr><td colspan="${columns.length}" class="table-empty">${escapeHtml(emptyText)}</td></tr>`;

  container.innerHTML = `
    <div class="table-wrap">
      <table class="admin-table">
        <thead><tr>${head}</tr></thead>
        <tbody>${body}</tbody>
      </table>
    </div>
  `;

  container.querySelectorAll('.table-sort').forEach((button) => {
    button.addEventListener('click', () => {
      const nextKey = button.dataset.sort;
      if (!nextKey) return;
      if (state.sortKey === nextKey) {
        onSortChange(nextKey, state.sortDir === 'asc' ? 'desc' : 'asc');
      } else {
        onSortChange(nextKey, 'asc');
      }
    });
  });
}
