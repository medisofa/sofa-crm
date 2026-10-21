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
  const load = () => loadInto(box, async () => {
    try { return await listCommercialDocs(org.id); } catch { return []; }
  }, (list) => html`
    <div class="note warn" style="margin-bottom:10px">
      <b>Documentos A–E en preparación.</b><br>
      Las plantillas todavía no están aprobadas para uso operativo. La generación, descarga, cambio de estado y carga de firmas permanecen deshabilitados hasta completar la revisión documental y legal.
    </div>
    <div class="list">
      ${Object.entries(COMMERCIAL_DOCS).map(([code, title]) => {
        const latest = list.find((d) => d.template_code === code);
        return html`<div class="li">
          <div class="b">
            <div class="t1"><b>${code}</b> · ${title}</div>
            <div class="t2">${latest ? `Existe un borrador histórico generado ${dateTime(latest.created_at)}; no debe utilizarse.` : 'Plantilla pendiente de validación.'}</div>
          </div>
          <span class="pill warn">No disponible</span>
          <button class="btn sm" disabled title="Pendiente de aprobación documental y legal">Usar documento</button>
        </div>`;
      })}
    </div>
    <p class="small muted">Cuando cada plantilla sea aprobada, se habilitará individualmente con versión, fecha de vigencia y responsable de aprobación. Los documentos ya generados antes de esta corrección se consideran borradores históricos.</p>
  `, { isEmpty: () => false });
  load();
  return { reload: load };
}

