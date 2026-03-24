import { escapeHtml } from '../models/serializers.js';

function closeModal(root) {
  root.classList.add('modal-exit');
  setTimeout(() => root.remove(), 150);
}

export function openConfirmModal({ title = 'Confirm', message = '', confirmText = 'Confirm', cancelText = 'Cancel' }) {
  return new Promise((resolve) => {
    const root = document.createElement('div');
    root.className = 'modal-backdrop';
    root.innerHTML = `
      <div class="modal-card">
        <h3>${escapeHtml(title)}</h3>
        <p>${escapeHtml(message)}</p>
        <div class="modal-actions">
          <button class="btn btn-muted" data-action="cancel">${escapeHtml(cancelText)}</button>
          <button class="btn btn-danger" data-action="confirm">${escapeHtml(confirmText)}</button>
        </div>
      </div>
    `;
    root.addEventListener('click', (event) => {
      if (event.target === root) {
        closeModal(root);
        resolve(false);
      }
    });
    root.querySelector('[data-action="cancel"]').addEventListener('click', () => {
      closeModal(root);
      resolve(false);
    });
    root.querySelector('[data-action="confirm"]').addEventListener('click', () => {
      closeModal(root);
      resolve(true);
    });
    document.body.appendChild(root);
  });
}

export function openDrawer({
  title = '',
  subtitle = '',
  content = '',
  closeText = 'Close',
}) {
  return new Promise((resolve) => {
    const root = document.createElement('div');
    root.className = 'drawer-backdrop';
    root.innerHTML = `
      <aside class="drawer-panel" role="dialog" aria-modal="true" aria-label="${escapeHtml(title)}">
        <div class="drawer-head">
          <div>
            <h3>${escapeHtml(title)}</h3>
            ${subtitle ? `<p>${escapeHtml(subtitle)}</p>` : ''}
          </div>
          <button type="button" class="drawer-close" aria-label="${escapeHtml(closeText)}">&times;</button>
        </div>
        <div class="drawer-body">${content}</div>
      </aside>
    `;

    const dismiss = () => {
      closeModal(root);
      resolve();
    };

    root.addEventListener('click', (event) => {
      if (event.target === root) dismiss();
    });
    root.querySelector('.drawer-close')?.addEventListener('click', dismiss);
    document.addEventListener(
      'keydown',
      function onKeyDown(event) {
        if (event.key === 'Escape') {
          document.removeEventListener('keydown', onKeyDown);
          dismiss();
        }
      },
      { once: true },
    );
    document.body.appendChild(root);
  });
}

export function openFormModal({ title, fields, initial = {}, submitText = 'Save', cancelText = 'Cancel' }) {
  return new Promise((resolve) => {
    const root = document.createElement('div');
    root.className = 'modal-backdrop';

    const fieldsHtml = fields
      .map((field) => {
        const value = initial[field.name] ?? field.defaultValue ?? '';
        if (field.type === 'textarea') {
          return `
            <label class="field">
              <span>${escapeHtml(field.label)}</span>
              <textarea name="${field.name}" ${field.required ? 'required' : ''}>${escapeHtml(value)}</textarea>
            </label>
          `;
        }
        if (field.type === 'checkbox') {
          const checked = value ? 'checked' : '';
          return `
            <label class="field field-checkbox">
              <input type="checkbox" name="${field.name}" ${checked} />
              <span>${escapeHtml(field.label)}</span>
            </label>
          `;
        }
        if (field.type === 'select') {
          const options = (field.options || [])
            .map((opt) => {
              const selected = String(opt.value) === String(value) ? 'selected' : '';
              return `<option value="${escapeHtml(opt.value)}" ${selected}>${escapeHtml(opt.label)}</option>`;
            })
            .join('');
          return `
            <label class="field">
              <span>${escapeHtml(field.label)}</span>
              <select name="${field.name}" ${field.required ? 'required' : ''}>${options}</select>
            </label>
          `;
        }
        if (field.type === 'file') {
          return `
            <label class="field">
              <span>${escapeHtml(field.label)}</span>
              <input type="file" name="${field.name}" accept="${escapeHtml(field.accept || 'image/*')}" ${field.required ? 'required' : ''} />
            </label>
          `;
        }
        if (field.type === 'multiselect') {
          const selectedValues = new Set((Array.isArray(value) ? value : []).map(String));
          const options = (field.options || [])
            .map((opt) => {
              const checked = selectedValues.has(String(opt.value)) ? 'checked' : '';
              const label = String(opt.label ?? opt.value ?? '').trim();
              const tagLabel = String(opt.tagLabel ?? label).trim();
              const searchText = `${label} ${opt.value ?? ''}`.trim().toLowerCase();
              return `
                <label class="multi-select-row ${checked ? 'is-selected' : ''}" data-multi-row data-search="${escapeHtml(searchText)}">
                  <input type="checkbox" name="${field.name}" value="${escapeHtml(opt.value)}" data-multi-checkbox ${checked} />
                  <span class="multi-select-label">${escapeHtml(label)}</span>
                  <span class="multi-select-tag-label" hidden>${escapeHtml(tagLabel)}</span>
                </label>
              `;
            })
            .join('');
          return `
            <fieldset class="field">
              <legend>${escapeHtml(field.label)}</legend>
              <div class="multi-select" data-multi-select="${field.name}">
                <div class="multi-select-header">
                  <span class="multi-select-title">${escapeHtml(field.selectedLabel || `Selected ${field.label}`)}</span>
                  <div class="multi-select-tags" data-multi-tags></div>
                </div>
                <label class="multi-select-search-wrap">
                  <input
                    type="search"
                    class="multi-select-search"
                    data-multi-search
                    placeholder="${escapeHtml(field.searchPlaceholder || 'Search by name or ID')}"
                  />
                </label>
                <div class="multi-select-list" data-multi-list>
                  ${options}
                </div>
                <div class="multi-select-no-results" data-multi-empty hidden>
                  ${escapeHtml(field.noResultsLabel || 'No matching products')}
                </div>
              </div>
            </fieldset>
          `;
        }
        const type = field.type || 'text';
        return `
          <label class="field">
            <span>${escapeHtml(field.label)}</span>
            <input type="${escapeHtml(type)}" name="${field.name}" value="${escapeHtml(value)}" ${field.required ? 'required' : ''} />
          </label>
        `;
      })
      .join('');

    root.innerHTML = `
      <div class="modal-card modal-form-card">
        <h3>${escapeHtml(title)}</h3>
        <form class="modal-form">
          <div class="modal-form-fields">${fieldsHtml}</div>
          <div class="modal-actions">
            <button type="button" class="btn btn-muted" data-action="cancel">${escapeHtml(cancelText)}</button>
            <button type="submit" class="btn btn-primary">${escapeHtml(submitText)}</button>
          </div>
        </form>
      </div>
    `;

    const form = root.querySelector('form');

    fields
      .filter((field) => field.type === 'multiselect')
      .forEach((field) => {
        const wrapper = form.querySelector(`[data-multi-select="${field.name}"]`);
        if (!wrapper) return;
        const searchInput = wrapper.querySelector('[data-multi-search]');
        const tagRoot = wrapper.querySelector('[data-multi-tags]');
        const rows = [...wrapper.querySelectorAll('[data-multi-row]')];
        const checkboxes = [...wrapper.querySelectorAll('[data-multi-checkbox]')];
        const emptyState = wrapper.querySelector('[data-multi-empty]');

        const syncTags = () => {
          rows.forEach((row) => {
            const checked = Boolean(row.querySelector('[data-multi-checkbox]')?.checked);
            row.classList.toggle('is-selected', checked);
          });

          const selected = checkboxes
            .filter((node) => node.checked)
            .map((node) => {
              const row = node.closest('[data-multi-row]');
              const tagLabel = row?.querySelector('.multi-select-tag-label')?.textContent?.trim()
                || row?.querySelector('.multi-select-label')?.textContent?.trim()
                || node.value;
              return { value: node.value, label: tagLabel };
            });

          if (!selected.length) {
            tagRoot.innerHTML = `<span class="multi-select-empty">${escapeHtml(field.emptyLabel || 'No products selected')}</span>`;
            return;
          }

          tagRoot.innerHTML = selected
            .map((item) => `
              <button type="button" class="multi-select-tag" data-remove-value="${escapeHtml(item.value)}">
                <span>${escapeHtml(item.label)}</span>
                <span class="multi-select-tag-x">&times;</span>
              </button>
            `)
            .join('');

          tagRoot.querySelectorAll('[data-remove-value]').forEach((button) => {
            button.addEventListener('click', () => {
              const target = checkboxes.find((node) => String(node.value) === String(button.dataset.removeValue));
              if (!target) return;
              target.checked = false;
              syncTags();
            });
          });
        };

        const syncFilter = () => {
          const query = String(searchInput?.value || '').trim().toLowerCase();
          let visibleCount = 0;
          rows.forEach((row) => {
            const haystack = String(row.dataset.search || '').toLowerCase();
            const isVisible = query ? haystack.includes(query) : true;
            row.hidden = !isVisible;
            if (isVisible) visibleCount += 1;
          });
          if (emptyState) {
            emptyState.hidden = visibleCount > 0;
          }
        };

        checkboxes.forEach((node) => {
          node.addEventListener('change', syncTags);
        });
        searchInput?.addEventListener('input', syncFilter);

        syncTags();
        syncFilter();
      });

    form.addEventListener('submit', (event) => {
      event.preventDefault();
      const values = {};
      fields.forEach((field) => {
        if (field.type === 'checkbox') {
          values[field.name] = Boolean(form.elements[field.name]?.checked);
          return;
        }
        if (field.type === 'number') {
          const raw = form.elements[field.name]?.value ?? '';
          values[field.name] = raw === '' ? null : Number(raw);
          return;
        }
        if (field.type === 'file') {
          const node = form.elements[field.name];
          values[field.name] = node?.files?.[0] || null;
          return;
        }
        if (field.type === 'multiselect') {
          const checks = form.querySelectorAll(`input[name="${field.name}"]:checked`);
          values[field.name] = [...checks].map((node) => Number(node.value));
          return;
        }
        values[field.name] = String(form.elements[field.name]?.value ?? '').trim();
      });
      closeModal(root);
      resolve(values);
    });

    root.querySelector('[data-action="cancel"]').addEventListener('click', () => {
      closeModal(root);
      resolve(null);
    });

    root.addEventListener('click', (event) => {
      if (event.target === root) {
        closeModal(root);
        resolve(null);
      }
    });

    document.body.appendChild(root);
  });
}
