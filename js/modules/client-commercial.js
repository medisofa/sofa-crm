/**
 * SOFA · Ficha del cliente, Iteración 15: implementación (onboarding de 9 pasos con activación)
 * y documentos A–E (generar, PDF con membrete, estado, copia firmada).
 */
import { html } from '../utils/dom.js';
import { loadInto, toast, friendlyError, opt, formDialog, fieldError } from '../utils/ui.js';
import { dateTime } from '../utils/formatters.js';
import { COMMERCIAL_DOCS, COMMERCIAL_DOC_STATUS, COMMERCIAL_DOC_TYPE } from '../utils/constants.js';
import { can } from '../utils/permissions.js';
import { onboardingStatus, setOnboardingStep, activateClient, listCommercialDocs, getCommercialDoc, generateCommercialDoc, setCommercialDocStatus } from '../services/crm.js';
import { uploadDocument } from '../services/documents.js';
import { listArs } from '../services/catalog.js';

const SRC = { automatico: ['Automático', 'ok'], manual: ['Marcado a mano', 'info'], pendiente: ['Pendiente', 'warn'] };

/** Implementación: barra de avance, 9 pasos y "Activar cliente" */
export function renderOnboarding(box, org, ctx, onChange = () => {}) {
  const manage = can('onboarding.manage', ctx.role); const admin = can('onboarding.override', ctx.role);
  const load = () => loadInto(box, () => onboardingStatus(org.id), (steps) => {
    const done = steps.filter((s) => s.done).length; const pct = Math.round((100 * done) / (steps.length || 9));
    return html`<div style="display:flex;justify-content:space-between;gap:10px;align-items:center;flex-wrap:wrap">
        <div><b style="font-size:20px">${pct}%</b> <span class="small muted">${done} de ${steps.length} pasos</span></div>
        ${org.status === 'activo' ? html`<span class="pill ok">Cliente activo</span>` : manage ? html`<button class="btn primary" id="activate">Activar cliente</button>` : ''}</div>
      <div style="height:10px;background:var(--surface-2);border-radius:6px;overflow:hidden;margin:8px 0 12px" role="progressbar" aria-valuenow="${pct}" aria-valuemin="0" aria-valuemax="100" aria-label="Avance del onboarding">
        <div style="height:100%;width:${pct}%;background:${pct === 100 ? 'var(--ok)' : 'var(--navy)'}"></div></div>
      ${org.activation_override ? html`<div class="note warn small">${org.activation_override}</div>` : ''}
      <div class="list">${steps.map((s) => { const [l, c] = SRC[s.source] || [s.source, '']; return html`<div class="li">
        <span aria-hidden="true" style="font-weight:700;width:18px;color:${s.done ? 'var(--ok)' : 'var(--ink-3)'}">${s.done ? '✓' : s.step}</span>
        <div class="b"><div class="t1">${s.label}</div><div class="t2">${s.detail}${s.done_at ? ` · ${dateTime(s.done_at)}` : ''}</div></div>
        <span class="pill ${c}">${l}</span>
        ${manage && s.source === 'pendiente' ? html`<button class="btn sm" data-mark="${s.code}" data-label="${s.label}">Marcar</button>` : ''}
        ${manage && s.source === 'manual' ? html`<button class="btn sm" data-unmark="${s.code}">Desmarcar</button>` : ''}</div>`; })}</div>
      <p class="small muted">Los pasos con documento o con datos del sistema se cumplen solos. Márcalo a mano solo si se cumplió fuera del sistema, indicando cómo.</p>`;
  });
  box.addEventListener('click', async (e) => {
    const m = e.target.closest('[data-mark]'); const u = e.target.closest('[data-unmark]');
    try {
      if (m) {
        const ok = await formDialog({ title: `Marcar: ${m.dataset.label}`, submitLabel: 'Marcar como cumplido',
          body: html`<div class="field"><label for="ob_n">¿Cómo se cumplió? *</label><textarea id="ob_n" name="notes" rows="2" class="input" maxlength="300"></textarea></div>`,
          onSubmit: async (d, f) => { if ((d.notes || '').trim().length < 5) { fieldError(f.elements.notes, 'Mínimo 5 caracteres'); return false; } await setOnboardingStep(org.id, m.dataset.mark, true, d.notes.trim()); return true; } });
        if (ok) { toast('Paso marcado', 'ok'); load(); onChange(); }
      } else if (u) { await setOnboardingStep(org.id, u.dataset.unmark, false); toast('Paso desmarcado'); load(); onChange(); }
      else if (e.target.closest('#activate')) {
        const steps = await onboardingStatus(org.id); const pct = Math.round((100 * steps.filter((s) => s.done).length) / steps.length);
        if (pct < 100 && !admin) { toast(`El onboarding va en ${pct} %. Complétalo o pide a un administrador que active por excepción.`, 'bad'); return; }
        const r = await formDialog({ title: pct < 100 ? `Activar por excepción (onboarding en ${pct} %)` : 'Activar cliente', submitLabel: 'Activar',
          body: pct < 100 ? html`<div class="note warn">Faltan pasos del onboarding. La activación quedará registrada como EXCEPCIÓN con tu usuario y el motivo.</div>
            <div class="field"><label for="ac_r">Motivo (mínimo 10 caracteres) *</label><textarea id="ac_r" name="reason" rows="2" class="input"></textarea></div>`
            : html`<p>El onboarding está completo. El cliente pasa a <b>Activo</b> y la oportunidad se cierra como ganada.</p>`,
          onSubmit: async (d, f) => { if (pct < 100 && (d.reason || '').trim().length < 10) { fieldError(f.elements.reason, 'Mínimo 10 caracteres'); return false; } await activateClient(org.id, pct < 100 ? d.reason.trim() : null); return true; } });
        if (r) { toast('Cliente activado', 'ok'); onChange(true); }
      }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
  return { reload: load };
}

/** Documentos A–E: generar, PDF con membrete, estado y copia firmada */
export function renderCommercialDocs(box, org, ctx, providers = []) {
  const manage = can('onboarding.manage', ctx.role);
  let rows = [];
  const load = () => loadInto(box, async () => { rows = await listCommercialDocs(org.id); return rows; }, (list) => html`
    ${manage ? html`<div class="toolbar" style="margin:0 0 8px">${Object.entries(COMMERCIAL_DOCS).map(([k, l]) => html`<button class="btn sm" data-gen="${k}" title="${l}">+ ${k} · ${l}</button>`)}</div>` : ''}
    ${list.length ? html`<div class="list">${list.map((d) => { const [l, c] = COMMERCIAL_DOC_STATUS[d.status] || [d.status, '']; return html`<div class="li">
      <div class="b"><div class="t1"><b>${d.template_code}</b> · ${COMMERCIAL_DOCS[d.template_code]}${d.ars?.name ? ` · ${d.ars.name}` : ''}${d.providers?.full_name ? ` · ${d.providers.full_name}` : ''}</div>
        <div class="t2">Generado ${dateTime(d.created_at)} · plantilla v${d.template_version}${d.status !== 'generado' ? ` · ${l.toLowerCase()} ${dateTime(d.status_changed_at)}` : ''}</div></div>
      <span class="pill ${c}">${l}</span>
      <button class="btn sm" data-pdf="${d.id}">PDF</button>
      ${manage && d.status !== 'anulado' && d.status !== 'firmado' ? html`<select class="input" data-st="${d.id}" style="width:auto;min-height:32px" aria-label="Cambiar estado">
        <option value="">Estado…</option>${['enviado', 'entregado', 'anulado'].map((s) => opt(s, COMMERCIAL_DOC_STATUS[s][0]))}</select>
        <label class="btn sm" style="cursor:pointer">Subir firmada<input type="file" data-sign="${d.id}" accept="application/pdf,image/jpeg,image/png" hidden></label>` : ''}</div>`; })}</div>`
      : html`<p class="small muted">Aún no se han generado documentos para este cliente.</p>`}
    <p class="small muted">Los textos de A (contrato) y B (autorización) deben estar revisados por un abogado. SOFA los llena con los datos del cliente, pero no sustituye esa revisión.</p>`, { isEmpty: () => false });   // sin documentos todavía: igual se muestran los botones para generarlos
  box.addEventListener('click', async (e) => {
    const g = e.target.closest('[data-gen]'); const p = e.target.closest('[data-pdf]');
    try {
      if (g) {
        const code = g.dataset.gen; const ars = code === 'D' ? await listArs().catch(() => []) : [];
        const r = await formDialog({ title: `Generar ${code} · ${COMMERCIAL_DOCS[code]}`, submitLabel: 'Generar',
          body: html`${providers.length > 1 ? html`<div class="field"><label for="cg_p">Médico</label><select id="cg_p" name="provider">${providers.map((x) => opt(x.id, x.full_name))}</select></div>` : ''}
            ${code === 'D' ? html`<div class="field"><label for="cg_a">ARS *</label><select id="cg_a" name="ars"><option value="">Seleccione…</option>${ars.map((a) => opt(a.id, a.name))}</select><span class="hint">Se genera una carta por ARS.</span></div>` : ''}
            <p class="small">El documento se llena con los datos actuales del cliente. Lo que falte queda como "______" para completarlo a mano.</p>`,
          onSubmit: async (d, f) => { if (code === 'D' && !d.ars) { fieldError(f.elements.ars, 'Seleccione la ARS'); return false; } return generateCommercialDoc(org.id, code, d.provider || null, d.ars || null); } });
        if (r) { toast('Documento generado', 'ok'); load(); }
      } else if (p) {
        p.disabled = true; const { downloadLetterPdf } = await import('../utils/pdf-invoice.js');
        toast(`Descargado ${await downloadLetterPdf(await getCommercialDoc(p.dataset.pdf))}`, 'ok'); p.disabled = false;
      }
    } catch (err) { toast(friendlyError(err), 'bad'); if (p) p.disabled = false; }
  });
  box.addEventListener('change', async (e) => {
    const s = e.target.closest('[data-st]'); const f = e.target.closest('[data-sign]');
    try {
      if (s && s.value) { await setCommercialDocStatus(s.dataset.st, s.value); toast(`Marcado como ${COMMERCIAL_DOC_STATUS[s.value][0].toLowerCase()}`, 'ok'); load(); }
      if (f && f.files[0]) {
        const d = rows.find((x) => x.id === f.dataset.sign);
        toast('Subiendo copia firmada…');
        const up = await uploadDocument({ orgId: org.id, file: f.files[0], entityType: 'organization', entityId: org.id, docType: COMMERCIAL_DOC_TYPE[d.template_code], bucket: 'contracts' });
        await setCommercialDocStatus(d.id, 'firmado', up.id); toast('Documento firmado guardado en el expediente', 'ok'); load();
      }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
  return { reload: load };
}

