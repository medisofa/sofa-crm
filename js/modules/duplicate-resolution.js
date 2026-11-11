/** Gestión de una coincidencia: corregir datos o solicitar exclusión, sin modificar reclamaciones. */
import { html, render as paint, raw } from '../utils/dom.js';
import { formDialog, confirmDialog, fieldError, toast, busy, friendlyError } from '../utils/ui.js';
import { dateTime } from '../utils/formatters.js';
import { viewAsState } from '../utils/view-as-state.js';
import { requestClaimDuplicateExclusion, listClaimDuplicateResolutionRequests } from '../services/claims.js';

const REQUEST_ROLES = ['super_admin', 'admin', 'billing', 'operations'];
const pairKey = (a, b) => [a, b].sort().join(':');

/**
 * @param {object} d Candidato de claimDuplicateCandidates; sus flags son la fuente del bloqueo.
 * @param {{onRefresh?:Function,role:string,viewAs?:object}} options
 * @returns {Promise<object|null>} Solicitud pendiente o navegación de corrección; nunca una resolución automática.
 */
export async function resolveDuplicateDialog(d, { onRefresh, role, viewAs } = {}) {
  if (!d?.line_id || !d?.other_line_id) throw new Error('No se pudo identificar el par de reclamaciones.');
  const readOnly = !!viewAs || !!viewAsState.active;
  const canRequest = REQUEST_ROLES.includes(role) && !readOnly;
  const confirmedBlock = d.review_decision === 'duplicado_confirmado' && !!d.blocks_radicacion;
  const requests = await listClaimDuplicateResolutionRequests(d.line_id, d.other_line_id);
  const pending = (requests || []).filter((r) => r.status === 'pendiente' && pairKey(r.line_a, r.line_b) === pairKey(d.line_id, d.other_line_id));
  const claims = [
    { id: d.line_id, folio: d.folio || d.line_id, service: d.service_name, authorization: d.authorization_number },
    { id: d.other_line_id, folio: d.other_folio || d.other_line_id, service: d.other_service_name, authorization: d.other_authorization_number }
  ];
  const label = (id) => claims.find((c) => c.id === id)?.folio || 'Reclamación del par';
  const result = await formDialog({
    title: d.review_decision === 'duplicado_confirmado' ? 'Gestionar duplicado confirmado' : 'Gestionar coincidencia', submitLabel: 'Continuar', wide: true,
    body: html`<div class="duplicate-resolution">
      <div class="note ${d.blocks_radicacion ? 'bad' : 'warn'}"><b>${d.blocks_radicacion ? 'La radicación continúa bloqueada' : 'Comprueba el estado actual antes de continuar'}</b><p>La revisión registra una decisión. Solicitar una exclusión no elimina reclamaciones ni levanta el bloqueo; un responsable debe gestionar las acciones autorizadas y volver a comprobar el resultado.</p></div>
      <div class="dup-comparison">${claims.map((c) => html`<section class="dup-claim"><h3>${c.folio}</h3><p>${c.service || 'Servicio no indicado'}</p><p class="small muted">Autorización: ${c.authorization || 'Sin indicar'}</p><a href="#/reclamaciones/${c.id}">Abrir reclamación</a></section>`)}</div>
      <section class="dr-requests" aria-label="Solicitudes de exclusión"><h3>Solicitudes registradas</h3>${pending.length ? pending.map((r) => html`<article class="dr-request"><span class="pill warn">Pendiente de gestión</span><p><b>Conservar:</b> ${label(r.keep_line)}<br><b>Exclusión solicitada:</b> ${label(r.exclude_line)}</p><p class="small muted">Registrada: ${dateTime(r.created_at)}</p><p class="small">${r.reason}</p>${r.submission_id ? html`<a class="btn sm" href="#/radicaciones/${r.submission_id}">Abrir lote para gestionar</a>` : ''}<p class="small muted">Solicitud registrada; todavía no equivale a una exclusión realizada.</p></article>`) : html`<p class="small muted">No hay solicitudes pendientes registradas para este par.</p>`}</section>
      ${!canRequest ? html`<p class="note">${readOnly ? 'Modo soporte: solo lectura.' : 'Tu perfil puede consultar el par. La solicitud de exclusión corresponde al personal autorizado.'}</p>` : ''}
      <div class="field"><label for="dr-action">¿Qué necesitas hacer? *</label><select id="dr-action" name="action"><option value="">Selecciona una acción…</option><option value="corregir">Revisar y corregir datos en la ficha</option><option value="excluir" ${!canRequest || !confirmedBlock || pending.length ? raw('disabled') : ''}>Solicitar exclusión de una reclamación</option></select></div>
      ${!confirmedBlock ? html`<p class="small muted">Para solicitar exclusión, primero debe existir una decisión de duplicado confirmado y un bloqueo vigente.</p>` : ''}
      ${pending.length ? html`<p class="small muted">Ya hay una solicitud pendiente. Consulta su lote o coordina con el responsable antes de registrar otra.</p>` : ''}
      <div id="dr-correction" hidden><p>Abre la ficha correspondiente y utiliza las opciones permitidas para corregir datos. Después vuelve a comprobar la coincidencia. No cambies una decisión a «Dato corregido» antes de realizar y verificar la corrección.</p><div class="dr-links">${claims.map((c) => html`<a class="btn" href="#/reclamaciones/${c.id}">Abrir ${c.folio}</a>`)}</div></div>
      <div id="dr-exclusion" hidden><div class="field"><label for="dr-keep">Reclamación que debe conservarse *</label><select id="dr-keep" name="keepLine"><option value="">Selecciona la reclamación correcta…</option>${claims.map((c) => html`<option value="${c.id}">${c.folio}</option>`)}</select></div>
        <p id="dr-target" class="dr-target" role="status">La otra reclamación quedará identificada en la solicitud. No se modificará automáticamente.</p>
        <div class="field"><label for="dr-reason">Motivo de la solicitud *</label><textarea id="dr-reason" name="reason" rows="3" maxlength="1000" placeholder="Explica cuál reclamación debe conservarse y por qué (mínimo 10 caracteres)."></textarea></div>
        <p class="note">«Marcar retirada» significa retiro físico de documentos; no excluye una reclamación duplicada.</p>
      </div>
      <div id="dr-message" aria-live="polite"></div><button type="button" class="btn" id="dr-recheck">Volver a comprobar coincidencia</button>
    </div>`,
    onOpen: (form, dialog) => {
      dialog.classList.add('duplicate-resolution-dialog');
      const action = form.elements.action;
      const update = () => {
        form.querySelector('#dr-exclusion').hidden = action.value !== 'excluir';
        form.querySelector('#dr-correction').hidden = action.value !== 'corregir';
        form.querySelector('[type=submit]').textContent = action.value === 'excluir' ? 'Solicitar exclusión' : action.value === 'corregir' ? 'Cerrar opciones de corrección' : 'Continuar';
      };
      action.addEventListener('change', update);
      form.elements.keepLine.addEventListener('change', () => {
        const keep = form.elements.keepLine.value;
        const other = claims.find((c) => c.id !== keep);
        form.querySelector('#dr-target').textContent = keep && other ? `Conservar: ${label(keep)}. Solicitar exclusión: ${other.folio}.` : 'Selecciona la reclamación correcta; ninguna está preseleccionada.';
      });
      form.addEventListener('click', (event) => { if (event.target.closest('a[href]')) dialog.close(); });
      form.querySelector('#dr-recheck').addEventListener('click', (event) => busy(event.currentTarget, async () => {
        try { if (onRefresh) await onRefresh(); dialog.close(); toast('Comprobación actualizada. Revisa el estado del par en el listado.', ''); }
        catch (err) { paint(form.querySelector('#dr-message'), html`<div class="note bad">${friendlyError(err)}</div>`); }
      }));
      update();
    },
    onSubmit: async (data, form) => {
      if (!['corregir', 'excluir'].includes(data.action)) { fieldError(form.elements.action, 'Selecciona una acción.'); return false; }
      if (data.action === 'corregir') return { action: 'corregir' };
      if (!canRequest || !confirmedBlock || pending.length) { paint(form.querySelector('#dr-message'), html`<div class="note bad">No se puede registrar una nueva solicitud desde este contexto.</div>`); return false; }
      if (!claims.some((c) => c.id === data.keepLine)) { fieldError(form.elements.keepLine, 'Selecciona la reclamación que debe conservarse.'); return false; }
      const reason = String(data.reason || '').trim();
      if (reason.length < 10) { fieldError(form.elements.reason, 'Escribe un motivo de al menos 10 caracteres.'); return false; }
      const other = claims.find((c) => c.id !== data.keepLine);
      const confirmed = await confirmDialog('Confirmar solicitud de exclusión', `Conservar: ${label(data.keepLine)}. Solicitar exclusión: ${other.folio}. Motivo: ${reason}. Esta solicitud no elimina datos ni levanta el bloqueo.`, 'Registrar solicitud');
      if (!confirmed) return false;
      return requestClaimDuplicateExclusion({ lineA: d.line_id, lineB: d.other_line_id, keepLine: data.keepLine, reason });
    }
  });
  if (result?.status === 'pendiente') {
    toast('Solicitud registrada, pendiente de gestión. El bloqueo no se ha levantado.', 'warn');
    if (onRefresh) await onRefresh();
  }
  return result;
}
