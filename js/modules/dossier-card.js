/**
 * SOFA · Expediente de una reclamación (Iteración 13).
 * Checklist dinámico (servicio + ARS + modalidad), subir archivo por documento, marcar recibido en físico
 * y excepción de expediente auditada. Las reglas las aplica PostgreSQL (028_expediente.sql).
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, toast, friendlyError, formDialog, fieldError, confirmDialog } from '../utils/ui.js';
import { dateTime } from '../utils/formatters.js';
import { can } from '../utils/permissions.js';
import { uploadDocument, openDocument, deleteDocument, fileProblem, sizeLabel, ALLOWED_TYPES } from '../services/documents.js';
import { claimDossier, claimFiles, setPhysicalCheck, authorizeDossierException, revokeDossierException } from '../services/dossier.js';

const CAPTURE_STATES = ['pendiente_configuracion', 'capturada', 'pendiente_retiro', 'con_inconsistencia', 'devuelta'];
const LOCKED = ['radicada', 'en_proceso_ars', 'pagada', 'pago_parcial', 'glosada', 'cerrada'];
const MODES = { ambulatorio: 'Ambulatorio', emergencia: 'Emergencia', internamiento: 'Internamiento' };

/** Pinta el expediente dentro de `box`. onChange() se llama después de cada cambio (para refrescar la ficha). */
export async function renderDossier(box, claim, role, onChange = null) {
  const done = onChange || (() => renderDossier(box, claim, role));
  paint(box, loadingView(3));
  let d; let files;
  try { [d, files] = await Promise.all([claimDossier(claim.id), claimFiles(claim.id)]); }
  catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); return null; }
  const locked = LOCKED.includes(claim.claim_status);
  const consultorio = ['client', 'capturer'].includes(role);
  const canUpload = !locked && can('dossier.upload', role) && (!consultorio || CAPTURE_STATES.includes(claim.claim_status));
  const canPhysical = !locked && can('dossier.physical', role) && (!consultorio || CAPTURE_STATES.includes(claim.claim_status));
  const canExcept = !locked && can('dossier.exception', role);
  const byType = {};
  files.forEach((f) => { (byType[f.document_type_code || 'otro'] ||= []).push(f); });
  const pill = d.complete ? html`<span class="pill ok">COMPLETO</span>` : d.exception ? html`<span class="pill warn">INCOMPLETO · con excepción</span>` : html`<span class="pill bad">INCOMPLETO</span>`;

  paint(box, html`<h2>Expediente · ${pill}</h2>
    <p class="small muted">Requisitos para <b>${MODES[d.care_mode] || d.care_mode}</b> según el servicio y la ARS. Sin expediente completo (o excepción autorizada) la reclamación no pasa a "Lista para radicar".</p>
    ${d.items.length ? html`<div class="list">${d.items.map((i) => html`<div class="li" style="align-items:flex-start">
      <span aria-hidden="true" style="font-weight:700;color:${i.present ? 'var(--ok)' : i.mandatory ? 'var(--bad)' : 'var(--muted)'}">${i.present ? '✓' : i.mandatory ? '✕' : '○'}</span>
      <div class="b">
        <div class="t1">${i.name} ${i.mandatory ? '' : html`<span class="pill">opcional</span>`}<span class="sr-only">${i.present ? 'Presente' : 'Falta'}</span></div>
        ${(byType[i.code] || []).map((f) => html`<div class="t2"><a href="#" data-open="${f.id}">📎 ${f.file_name}</a> · ${sizeLabel(f.size_bytes)} · ${dateTime(f.uploaded_at)}
          ${can('dossier.delete', role) || (consultorio && CAPTURE_STATES.includes(claim.claim_status)) ? html` · <a href="#" data-del="${f.id}" style="color:var(--bad)">quitar</a>` : ''}</div>`)}
        ${i.checked && !i.files ? html`<div class="t2">Recibido en físico (sin archivo digital)</div>` : ''}
        <div class="toolbar" style="margin:6px 0 0;gap:6px">
          ${canUpload ? html`<label class="btn sm" style="cursor:pointer">Subir archivo<input type="file" data-up="${i.code}" accept="${ALLOWED_TYPES.join(',')}" hidden></label>` : ''}
          ${canPhysical && !i.files ? html`<label class="check small"><input type="checkbox" data-phys="${i.code}" ${i.checked ? 'checked' : ''}> Recibido en físico</label>` : ''}
        </div></div></div>`)}</div>`
      : html`<p class="small muted">Este servicio no tiene documentos requeridos.</p>`}
    ${d.exception ? html`<div class="note warn" style="margin-top:10px"><b>Excepción de expediente</b> · ${dateTime(d.exception.at)}<br>${d.exception.reason}<div class="small">Faltaba: ${(d.exception.missing || []).join(', ')}</div>
        ${canExcept ? html`<button class="btn sm" id="dxRevoke" style="margin-top:6px">Revocar excepción</button>` : ''}</div>`
      : !d.complete && canExcept ? html`<div style="margin-top:10px"><button class="btn" id="dxExcept">Autorizar excepción de expediente…</button></div>` : ''}
    ${canUpload ? html`<p class="small muted" style="margin-top:8px">PDF o imagen, máximo 10 MB. Las fotos se comprimen antes de subir.</p>` : ''}`);

  box.querySelectorAll('[data-up]').forEach((inp) => inp.addEventListener('change', async () => {
    const file = inp.files[0]; if (!file) return;
    const prob = fileProblem(file); if (prob) { toast(prob, 'bad'); inp.value = ''; return; }
    const lbl = inp.closest('label'); lbl.classList.add('busy'); lbl.firstChild.textContent = 'Subiendo…';
    try {
      await uploadDocument({ orgId: claim.organization_id, submissionId: claim.submission_id, lineId: claim.id, docType: inp.dataset.up, file });
      toast('Documento agregado al expediente', 'ok'); await done();
    } catch (err) { toast(friendlyError(err), 'bad'); lbl.classList.remove('busy'); lbl.firstChild.textContent = 'Subir archivo'; inp.value = ''; }
  }));
  box.querySelectorAll('[data-phys]').forEach((c) => c.addEventListener('change', async () => {
    c.disabled = true;
    try { await setPhysicalCheck(claim, c.dataset.phys, c.checked); await done(); }
    catch (err) { toast(friendlyError(err), 'bad'); c.checked = !c.checked; c.disabled = false; }
  }));
  box.querySelectorAll('[data-open]').forEach((a) => a.addEventListener('click', async (e) => {
    e.preventDefault();
    try { const url = await openDocument(files.find((f) => f.id === a.dataset.open)); if (url) toast('El navegador bloqueó la ventana: permite ventanas emergentes para SOFA', 'bad'); }
    catch (err) { toast(friendlyError(err), 'bad'); }
  }));
  box.querySelectorAll('[data-del]').forEach((a) => a.addEventListener('click', async (e) => {
    e.preventDefault();
    const f = files.find((x) => x.id === a.dataset.del);
    if (!(await confirmDialog('Quitar documento', `Se eliminará "${f.file_name}" del expediente.`, 'Quitar'))) return;
    try { await deleteDocument(f); toast('Documento quitado', 'ok'); await done(); }
    catch (err) { toast(friendlyError(err), 'bad'); }
  }));
  $('#dxExcept', box)?.addEventListener('click', async () => {
    try { if (await exceptionDialog([claim.id], d.missing)) { toast('Excepción de expediente autorizada y registrada', 'ok'); await done(); } }
    catch (err) { toast(friendlyError(err), 'bad'); }
  });
  $('#dxRevoke', box)?.addEventListener('click', async () => {
    const r = await formDialog({ title: 'Revocar excepción de expediente', submitLabel: 'Revocar',
      body: html`<div class="field"><label for="rv">Motivo (mín. 5 caracteres) *</label><textarea id="rv" name="reason" rows="2" class="input"></textarea></div>`,
      onSubmit: async (v, f) => { if ((v.reason || '').trim().length < 5) { fieldError(f.elements.reason, 'Mínimo 5 caracteres'); return false; } await revokeDossierException(claim.id, v.reason.trim()); return true; } })
      .catch((err) => { toast(friendlyError(err), 'bad'); });
    if (r) { toast('Excepción revocada', 'ok'); await done(); }
  });
  return d;
}

/** Excepción de expediente (Auditor o administrador): motivo obligatorio; queda en el historial de cada reclamación */
export function exceptionDialog(lineIds, missing = []) {
  return formDialog({
    title: `Excepción de expediente · ${lineIds.length} reclamación${lineIds.length === 1 ? '' : 'es'}`, submitLabel: 'Autorizar excepción',
    body: html`${missing.length ? html`<div class="note warn">Faltan: ${missing.join(', ')}</div>` : ''}
      <p class="small">Permite pasar a "Lista para radicar" sin esos documentos. Úsela solo cuando la ARS los acepte después o no los exija en este caso. Queda registrada con su usuario, fecha y los documentos faltantes.</p>
      <div class="field"><label for="ex_r">Motivo (mín. 10 caracteres) *</label><textarea id="ex_r" name="reason" rows="3" class="input"></textarea></div>`,
    onSubmit: async (v, f) => {
      if ((v.reason || '').trim().length < 10) { fieldError(f.elements.reason, 'Mínimo 10 caracteres'); return false; }
      return authorizeDossierException(lineIds, v.reason.trim());
    }
  });
}
export const dossierPill = (s) => (!s ? '' : s.complete ? html`<span class="pill ok">Completo</span>` : s.excepted ? html`<span class="pill warn">Con excepción</span>`
  : html`<span class="pill bad" title="Falta: ${(s.missing || []).join(', ')}">Incompleto · ${(s.missing || []).length}</span>`);
