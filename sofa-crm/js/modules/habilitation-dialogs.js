/** SOFA · Diálogos de habilitación */
import { html, raw } from '../utils/dom.js';
import { formDialog, opt, requireFields, fieldError } from '../utils/ui.js';
import { addMonths, todayISO } from '../utils/formatters.js';
import { clientOptions } from '../services/bi.js';
import { createCase, leadOptions, saveRequirement, EST_TYPES, CASE_KIND } from '../services/habilitation.js';

const f = (name, label, input, hint = '') => html`<div class="field"><label for="f_${name}">${label}</label>${input}${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`;
const text = (name, value = '', attrs = '') => html`<input id="f_${name}" name="${name}" value="${value ?? ''}" ${raw(attrs)}>`;
const plusDays = (n) => { const [y, m, d] = todayISO().split('-').map(Number); const x = new Date(y, m - 1, d + n); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; };

/** preset: { orgId, name, type, kind } */
export async function caseDialog(preset = {}) {
  const [clients, leads] = await Promise.all([clientOptions().catch(() => []), leadOptions().catch(() => [])]);
  return formDialog({
    title: preset.kind === 'renovacion' ? 'Renovación de habilitación' : 'Nuevo caso de habilitación', submitLabel: 'Abrir caso', wide: true,
    body: html`<div class="form-grid">
      ${f('name', 'Nombre del establecimiento *', text('name', preset.name || '', 'required maxlength="150"'))}
      ${f('type', 'Tipo de establecimiento *', html`<select id="f_type" name="type">${EST_TYPES.map((t) => opt(t, t, preset.type || 'Consultorio'))}</select>`, 'Define el checklist de requisitos.')}
      ${f('kind', 'Trámite', html`<select id="f_kind" name="kind">${Object.entries(CASE_KIND).map(([k, l]) => opt(k, l, preset.kind || 'apertura'))}</select>`)}
      ${f('org', 'Cliente', html`<select id="f_org" name="org"><option value="">— Ninguno (prospecto o nuevo) —</option>${clients.map((c) => opt(c.id, c.legal_name, preset.orgId))}</select>`, 'Si es cliente, verá su checklist en SOFA.')}
      ${f('lead', 'Prospecto', html`<select id="f_lead" name="lead"><option value="">— Ninguno —</option>${leads.map((l) => opt(l.id, l.company))}</select>`)}
      ${f('fee', 'Honorario del servicio (RD$)', text('fee', preset.fee || '', 'type="number" min="0" step="0.01"'))}
      ${f('target', 'Fecha objetivo de apertura', text('target', preset.target || plusDays(60), `type="date" min="${todayISO()}"`))}
      ${f('notes', 'Notas', text('notes', '', 'maxlength="300"'))}</div>`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['name', 'type'])) return false;
      if (d.name.trim().length < 3) { fieldError(form.elements.name, 'Muy corto.'); return false; }
      return createCase({ name: d.name.trim(), type: d.type, orgId: d.org || null, leadId: d.lead || null, kind: d.kind, fee: Number(d.fee || 0), target: d.target || null, notes: d.notes || null });
    }
  });
}

export function overrideDialog(problem) {
  return formDialog({
    title: 'Continuar con excepción', submitLabel: 'Continuar',
    body: html`<div class="note warn">${problem}</div>${f('reason', 'Motivo de la excepción (queda en el historial) *', html`<textarea id="f_reason" name="reason" rows="3" class="input"></textarea>`)}`,
    onSubmit: async (d, form) => { if (!d.reason || d.reason.trim().length < 10) { fieldError(form.elements.reason, 'Mínimo 10 caracteres.'); return false; } return d.reason.trim(); }
  });
}
export function commentDialog(title, required) {
  return formDialog({
    title, submitLabel: 'Confirmar',
    body: html`${f('comment', required ? 'Motivo *' : 'Comentario (opcional)', html`<textarea id="f_comment" name="comment" rows="3" class="input"></textarea>`)}`,
    onSubmit: async (d, form) => { if (required && (!d.comment || d.comment.trim().length < 5)) { fieldError(form.elements.comment, 'Escribe el motivo.'); return false; } return { comment: (d.comment || '').trim() || null }; }
  });
}

export function requirementDialog(areas) {
  return formDialog({
    title: 'Nuevo requisito del checklist maestro', submitLabel: 'Agregar', wide: true,
    body: html`<div class="form-grid">
      ${f('area', 'Área *', html`<select id="f_area" name="area">${areas.map((a) => opt(a, a))}</select>`)}
      ${f('code', 'Código *', text('code', '', 'required maxlength="20" placeholder="HAB-DL-09"'))}</div>
      ${f('requirement', 'Requisito *', text('requirement', '', 'required maxlength="250"'))}
      ${f('hint', 'Evidencia esperada', text('hint', '', 'maxlength="200"'))}
      <fieldset class="field" style="border:0;padding:0"><legend class="small" style="font-weight:600;color:var(--ink-2)">Aplica a</legend>
        <div style="display:flex;gap:10px;flex-wrap:wrap">${EST_TYPES.map((t) => html`<label class="check small"><input type="checkbox" name="types" value="${t}" checked> ${t}</label>`)}</div></fieldset>
      <label class="check small"><input type="checkbox" name="critical"> Crítico (bloquea el ensamblaje del expediente si no está en verde)</label>`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['code', 'requirement'])) return false;
      const types = [...form.querySelectorAll('[name=types]:checked')].map((x) => x.value);
      if (!types.length) throw new Error('Marca al menos un tipo de establecimiento.');
      return saveRequirement({ code: d.code.trim().toUpperCase(), area: d.area, requirement: d.requirement.trim(), evidence_hint: d.hint || null, applies_to: types, is_critical: form.elements.critical.checked, sort_order: 900 });
    }
  });
}
export { addMonths };
