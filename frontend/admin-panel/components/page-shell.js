import { escapeHtml } from '../models/serializers.js';

export function tr(uiLang = 'en', en, ru, uz) {
  if (uiLang === 'ru') return ru;
  if (uiLang === 'uz') return uz;
  return en;
}

function renderMeta(meta = []) {
  if (!Array.isArray(meta) || !meta.length) return '';
  return `
    <div class="page-meta-list">
      ${meta
        .filter((item) => item && (item.label || item.value))
        .map(
          (item) => `
            <div class="page-meta-item ${item.tone ? `is-${escapeHtml(item.tone)}` : ''}">
              <span class="page-meta-label">${escapeHtml(item.label || '')}</span>
              <strong class="page-meta-value">${escapeHtml(item.value || '')}</strong>
            </div>
          `,
        )
        .join('')}
    </div>
  `;
}

export function renderPageHeader({
  eyebrow = '',
  title = '',
  description = '',
  actions = '',
  meta = [],
}) {
  return `
    <section class="page-hero">
      <div class="page-hero-copy">
        ${eyebrow ? `<span class="page-eyebrow">${escapeHtml(eyebrow)}</span>` : ''}
        <h2 class="page-title">${escapeHtml(title)}</h2>
        ${description ? `<p class="page-description">${escapeHtml(description)}</p>` : ''}
        ${renderMeta(meta)}
      </div>
      ${actions ? `<div class="page-hero-actions">${actions}</div>` : ''}
    </section>
  `;
}

export function renderMetricGrid(cards = []) {
  if (!Array.isArray(cards) || !cards.length) return '';
  return `
    <section class="metric-grid">
      ${cards
        .filter((card) => card && (card.label || card.value))
        .map(
          (card) => `
            <article class="metric-card ${card.tone ? `is-${escapeHtml(card.tone)}` : ''} ${card.className ? escapeHtml(card.className) : ''}">
              <div class="metric-card-top">
                <span class="metric-label">${escapeHtml(card.label || '')}</span>
                ${card.caption ? `<span class="metric-caption">${escapeHtml(card.caption)}</span>` : ''}
              </div>
              <strong class="metric-value ${card.valueClassName ? escapeHtml(card.valueClassName) : ''}">${escapeHtml(card.value || '0')}</strong>
              ${card.helper ? `<p class="metric-helper">${escapeHtml(card.helper)}</p>` : ''}
            </article>
          `,
        )
        .join('')}
    </section>
  `;
}

export function renderSectionCard({
  title = '',
  description = '',
  actions = '',
  body = '',
  className = '',
}) {
  return `
    <section class="surface-card ${className}">
      <div class="surface-head">
        <div class="surface-head-copy">
          <h3>${escapeHtml(title)}</h3>
          ${description ? `<p>${escapeHtml(description)}</p>` : ''}
        </div>
        ${actions ? `<div class="surface-head-actions">${actions}</div>` : ''}
      </div>
      ${body}
    </section>
  `;
}

export function renderInlineList(items = []) {
  if (!Array.isArray(items) || !items.length) return '';
  return `
    <div class="inline-stat-list">
      ${items
        .filter((item) => item && (item.label || item.value))
        .map(
          (item) => `
            <div class="inline-stat-item">
              <span>${escapeHtml(item.label || '')}</span>
              <strong>${escapeHtml(item.value || '')}</strong>
            </div>
          `,
        )
        .join('')}
    </div>
  `;
}

export function renderEmptyState({ title = '', description = '' }) {
  return `
    <div class="empty-state-card">
      <div class="empty-state-mark"></div>
      <h3>${escapeHtml(title)}</h3>
      ${description ? `<p>${escapeHtml(description)}</p>` : ''}
    </div>
  `;
}

export function renderDefinitionList(items = []) {
  if (!Array.isArray(items) || !items.length) return '';
  return `
    <dl class="definition-list">
      ${items
        .filter((item) => item && item.label)
        .map(
          (item) => `
            <div class="definition-item">
              <dt>${escapeHtml(item.label)}</dt>
              <dd>${escapeHtml(item.value || '-')}</dd>
            </div>
          `,
        )
        .join('')}
    </dl>
  `;
}
