import { api } from '../services/api.js';
import { escapeHtml, formatDate } from '../models/serializers.js';
import { renderTable } from '../components/table.js';
import { statusBadge } from '../components/badge.js';
import { renderMetricGrid, renderPageHeader, renderSectionCard, tr } from '../components/page-shell.js';

function pickLocalized(row, base, uiLang = 'en') {
  if (uiLang === 'ru') return row?.[`${base}Ru`] || row?.[base] || '';
  if (uiLang === 'uz') return row?.[`${base}Uz`] || row?.[base] || '';
  return row?.[`${base}En`] || row?.[base] || '';
}

export async function renderFaq(ctx) {
  const { container, token, openFormModal, openConfirmModal, showToast, uiLang = 'en', t = (key) => key } = ctx;
  const state = { rows: [], sortKey: 'sortOrder', sortDir: 'asc' };

  const load = async () => {
    const res = await api.listFaqs(token);
    state.rows = res.results || [];
  };

  const formFor = (initial = {}) =>
    openFormModal({
      title: initial.id ? t('edit_faq_item') : t('add_faq_item'),
      submitText: initial.id ? t('update') : t('create'),
      cancelText: t('cancel'),
      initial: {
        question: initial.question || '',
        questionEn: initial.questionEn || initial.question || '',
        questionRu: initial.questionRu || initial.question || '',
        questionUz: initial.questionUz || initial.question || '',
        answer: initial.answer || '',
        answerEn: initial.answerEn || initial.answer || '',
        answerRu: initial.answerRu || initial.answer || '',
        answerUz: initial.answerUz || initial.answer || '',
        sortOrder: initial.sortOrder ?? 0,
        isActive: initial.isActive ?? true,
      },
      fields: [
        { name: 'question', label: t('question_fallback'), required: true },
        { name: 'questionEn', label: t('question_en'), required: true },
        { name: 'questionRu', label: t('question_ru'), required: true },
        { name: 'questionUz', label: t('question_uz'), required: true },
        { name: 'answer', label: t('answer_fallback'), type: 'textarea', required: true },
        { name: 'answerEn', label: t('answer_en'), type: 'textarea', required: true },
        { name: 'answerRu', label: t('answer_ru'), type: 'textarea', required: true },
        { name: 'answerUz', label: t('answer_uz'), type: 'textarea', required: true },
        { name: 'sortOrder', label: t('sort_order'), type: 'number' },
        { name: 'isActive', label: t('active'), type: 'checkbox' },
      ],
    });

  const render = async () => {
    container.innerHTML = `<div class="page-state loading">${escapeHtml(t('loading_faq'))}</div>`;
    try {
      await load();
    } catch (error) {
      container.innerHTML = `<div class="page-state error">${escapeHtml(t('failed_load_faq'))}: ${escapeHtml(error.message)}</div>`;
      return;
    }

    const activeCount = state.rows.filter((row) => row.isActive).length;

    container.innerHTML = `
      ${renderPageHeader({
        eyebrow: tr(uiLang, 'Support content', 'Контент поддержки', 'Yordam kontenti'),
        title: tr(uiLang, 'FAQ knowledge base', 'База знаний FAQ', 'FAQ bilim bazasi'),
        description: tr(uiLang, 'Keep multilingual answers, sort order, and help-center readiness in a clearer editorial structure.', 'Поддерживайте многоязычные ответы, порядок сортировки и готовность help-центра в более ясной редакторской структуре.', 'Ko‘p tilli javoblar, tartib va yordam markazi tayyorgarligini aniqroq muharrir tuzilmasida boshqaring.'),
      })}
      ${renderMetricGrid([
        { label: t('faq'), value: String(state.rows.length), tone: 'accent', helper: tr(uiLang, 'Knowledge entries', 'Элементы базы знаний', 'Bilim bazasi yozuvlari') },
        { label: t('active'), value: String(activeCount), tone: 'success', helper: tr(uiLang, 'Visible answers', 'Видимые ответы', 'Ko‘rinadigan javoblar') },
      ])}
      ${renderSectionCard({
        title: t('faq_support'),
        description: tr(uiLang, 'Create, edit, and retire help content with better readability for operations teams.', 'Создавайте, редактируйте и отключайте help-контент с лучшей читаемостью для операционных команд.', 'Operatsion jamoalar uchun yaxshiroq o‘qiladigan yordam kontentini yarating, tahrirlang va o‘chiring.'),
        actions: `<button class="btn btn-primary" id="add-faq">${escapeHtml(t('add_faq'))}</button>`,
        body: '<div id="faq-table"></div>',
      })}
    `;

    const tableRoot = container.querySelector('#faq-table');
    const columns = [
      { key: 'id', label: t('id'), sortable: true },
      { key: 'question', label: t('question'), sortable: true, render: (row) => escapeHtml(pickLocalized(row, 'question', uiLang)) },
      {
        key: 'answer',
        label: t('answer'),
        sortable: false,
        render: (row) => escapeHtml(pickLocalized(row, 'answer', uiLang)).slice(0, 150),
      },
      { key: 'sortOrder', label: t('sort'), sortable: true },
      { key: 'isActive', label: t('status_label'), sortable: true, render: (row) => statusBadge(row.isActive ? 'active' : 'inactive') },
      { key: 'updatedAt', label: t('updated'), sortable: true, render: (row) => formatDate(row.updatedAt) },
      {
        key: 'actions',
        label: t('actions'),
        sortable: false,
        render: (row) => `
          <div class="table-actions">
            <button class="btn btn-sm btn-muted" data-action="edit" data-id="${row.id}">${escapeHtml(t('edit'))}</button>
            <button class="btn btn-sm btn-danger" data-action="delete" data-id="${row.id}">${escapeHtml(t('delete'))}</button>
          </div>
        `,
      },
    ];

    const draw = () => {
      renderTable({
        container: tableRoot,
        columns,
        rows: state.rows,
        state,
        onSortChange: (sortKey, sortDir) => {
          state.sortKey = sortKey;
          state.sortDir = sortDir;
          draw();
        },
        emptyText: t('no_data'),
        minWidth: '1020px',
      });

      tableRoot.querySelectorAll('[data-action="edit"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const id = Number(btn.dataset.id);
          const current = state.rows.find((row) => row.id === id);
          if (!current) return;
          const form = await formFor(current);
          if (!form) return;
          try {
            await api.updateFaq(token, id, {
              question: form.question,
              questionEn: form.questionEn,
              questionRu: form.questionRu,
              questionUz: form.questionUz,
              answer: form.answer,
              answerEn: form.answerEn,
              answerRu: form.answerRu,
              answerUz: form.answerUz,
              sortOrder: Number(form.sortOrder || 0),
              isActive: Boolean(form.isActive),
            });
            showToast(t('faq_updated'), 'success');
            await render();
          } catch (error) {
            showToast(`${t('update_failed')}: ${error.message}`, 'error');
          }
        });
      });

      tableRoot.querySelectorAll('[data-action="delete"]').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const id = Number(btn.dataset.id);
          const ok = await openConfirmModal({
            title: t('delete_faq_title'),
            message: t('delete_faq_message'),
            confirmText: t('confirm_delete'),
            cancelText: t('cancel'),
          });
          if (!ok) return;
          try {
            await api.deleteFaq(token, id);
            showToast(t('faq_deleted'), 'success');
            await render();
          } catch (error) {
            showToast(`${t('delete_failed')}: ${error.message}`, 'error');
          }
        });
      });
    };

    draw();

    container.querySelector('#add-faq').addEventListener('click', async () => {
      const form = await formFor();
      if (!form) return;
      try {
        await api.createFaq(token, {
          question: form.question,
          questionEn: form.questionEn,
          questionRu: form.questionRu,
          questionUz: form.questionUz,
          answer: form.answer,
          answerEn: form.answerEn,
          answerRu: form.answerRu,
          answerUz: form.answerUz,
          sortOrder: Number(form.sortOrder || 0),
          isActive: Boolean(form.isActive),
        });
        showToast(t('faq_created'), 'success');
        await render();
      } catch (error) {
        showToast(`${t('create_failed')}: ${error.message}`, 'error');
      }
    });
  };

  await render();
}
