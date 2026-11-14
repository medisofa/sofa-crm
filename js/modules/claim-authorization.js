/** Corrección acotada e historial administrativo del número de autorización. */
import { html, render as paint } from '../utils/dom.js';
import { formDialog, confirmDialog, fieldError, toast, friendlyError, busy, loadingView } from '../utils/ui.js';
import { dateTime } from '../utils/formatters.js';
import { viewAsState } from '../utils/view-as-state.js';
import { adminSetClaimAuthorization, listClaimAuthorizationHistory } from '../services/claim-authorization.js';

const ADMIN_ROLES = ['super_admin', 'admin'];
function requireAdmin({ role, viewAs } = {}) {
  if (!ADMIN_ROLES.includes(role) || viewAs || viewAsState.active) throw new Error('Esta gestión corresponde a Administración o Super Admin, fuera del modo soporte.');
}
function ensureStyles() {
  if (document.getElementById('claim-authorization-styles')) return;
  const link = document.createElement('link');
  link.id = 'claim-authorization-styles'; link.rel = 'stylesheet';
  link.href = new URL('../../css/claim-authorization.css', import.meta.url).href;
  document.head.appendChild(link);
}
const numberLabel = (number) => number == null || number === '' ? 'Sin registrar' : number;

/** No expone el editor general de importes ni cambia el estado de la reclamación. */
export async function editClaimAuthorization(claim, options = {}) {
  requireAdmin(options); ensureStyles();
  const before = numberLabel(claim.authorization_number);
  const result = await formDialog({
    title: claim.authorization_number ? 'Corregir autorización' : 'Registrar autorización', submitLabel: 'Revisar cambio', wide: true,
    body: html`<div class="ca-edit"><p class="ca-context"><b>${claim.folio}</b><span>${claim.patient_name}</span></p>
      <div class="note">Solo se corrige el número de autorización. Los importes, pagos y estado de la reclamación se conservan.</div>
      <div class="field"><label for="ca-number">Número de autorización *</label><input id="ca-number" name="number" maxlength="100" autocomplete="off" required value="${claim.authorization_number || ''}" placeholder="Número informado por la ARS"><span class="hint">Se conservan los ceros iniciales.</span></div>
      <section class="ca-comparison" aria-label="Comparación de la corrección"><div><span>Antes</span><b class="mono">${before}</b></div><div><span>Después</span><b id="ca-after" class="mono">${before}</b></div></section>
      <div class="field"><label for="ca-reason">Motivo de la corrección *</label><textarea id="ca-reason" name="reason" rows="3" maxlength="1000" required placeholder="Ej.: autorización recibida después de la carga. Mínimo 10 caracteres."></textarea></div>
      <p class="small muted">La bitácora registra el usuario, la fecha, el valor anterior y el nuevo. El cambio no concilia pagos automáticamente.</p></div>`,
    onOpen: (form, dialog) => {
      dialog.classList.add('ca-dialog');
      form.elements.number.addEventListener('input', () => {
        form.querySelector('#ca-after').textContent = numberLabel(form.elements.number.value.trim());
        fieldError(form.elements.number, null);
      });
      form.elements.reason.addEventListener('input', () => fieldError(form.elements.reason, null));
    },
    onSubmit: async (data, form) => {
      const number = String(data.number || '').trim(); const reason = String(data.reason || '').trim();
      if (!number || number.length > 100 || /[\u0000-\u001f\u007f]/.test(number)) { fieldError(form.elements.number, 'Indica un número válido de hasta 100 caracteres.'); return false; }
      if (reason.length < 10) { fieldError(form.elements.reason, 'Escribe un motivo de al menos 10 caracteres.'); return false; }
      if (!(await confirmDialog('Confirmar cambio de autorización', `${claim.folio}. Antes: ${before}. Después: ${number}. Motivo: ${reason}. Se conservarán importes, pagos y estado.`, 'Guardar autorización'))) return false;
      requireAdmin(options);
      try {
        return await adminSetClaimAuthorization({ lineId: claim.id, number, reason, expectedNumber: claim.authorization_number ?? null });
      } catch (error) {
        if (String(error?.code) === '40001' || /autorización cambió/i.test(error?.message || '')) {
          throw new Error('La autorización cambió desde que abriste la ficha. Tu número y motivo permanecen en este formulario. Cierra y actualiza la ficha para comparar con el valor vigente antes de guardar.');
        }
        throw error;
      }
    }
  });
  if (result) toast(result.changed === false ? 'La autorización ya tiene ese número.' : 'Autorización actualizada y registrada en la bitácora.', 'ok');
  return result;
}

/** Consulta solo administrativa. No se carga historial para roles sin acceso ni en soporte. */
export async function showClaimAuthorizationHistory(claim, options = {}) {
  requireAdmin(options); ensureStyles();
  const opener = document.activeElement;
  const dialog = document.createElement('dialog'); dialog.className = 'dlg ca-dialog ca-history-dialog';
  const titleId = `ca-history-${crypto.randomUUID()}`;
  dialog.setAttribute('aria-labelledby', titleId);
  paint(dialog, html`<div class="dh" id="${titleId}">Historial de autorización</div><div class="db ca-history-body"><p class="ca-context"><b>${claim.folio}</b><span>Correcciones administrativas del número de autorización</span></p><div id="ca-history-rows" aria-live="polite"></div></div><div class="df"><button type="button" class="btn" data-ca-history-reload>Actualizar historial</button><button type="button" class="btn primary" data-ca-history-close>Cerrar</button></div>`);
  document.body.appendChild(dialog);
  let request = 0;
  const load = async () => {
    const mine = ++request; const rows = dialog.querySelector('#ca-history-rows');
    paint(rows, loadingView(2));
    try {
      requireAdmin(options);
      const history = await listClaimAuthorizationHistory(claim.id);
      if (!dialog.isConnected || mine !== request) return;
      paint(rows, history.length ? html`<ol class="ca-history-list">${history.map((entry) => html`<li class="ca-history-entry"><div class="ca-history-meta"><b>${entry.actor_name || 'Usuario registrado'}</b><time>${dateTime(entry.changed_at)}</time></div><dl class="ca-comparison"><div><dt>Antes</dt><dd class="mono">${numberLabel(entry.old_number)}</dd></div><div><dt>Después</dt><dd class="mono">${numberLabel(entry.new_number)}</dd></div></dl><p class="ca-history-reason"><b>Motivo:</b> ${entry.reason || 'Sin motivo disponible'}</p></li>`)}</ol>` : html`<div class="note">Sin correcciones administrativas de autorización registradas para esta reclamación.</div>`);
    } catch (error) {
      if (dialog.isConnected && mine === request) paint(rows, html`<div class="note bad" role="alert">No se pudo consultar el historial. ${friendlyError(error)} Usa «Actualizar historial» para reintentar.</div>`);
    }
  };
  dialog.querySelector('[data-ca-history-reload]').addEventListener('click', (event) => busy(event.currentTarget, load));
  dialog.querySelector('[data-ca-history-close]').addEventListener('click', () => dialog.close());
  const closed = new Promise((resolve) => dialog.addEventListener('close', () => { request += 1; dialog.remove(); if (opener?.isConnected) opener.focus(); resolve(); }, { once: true }));
  dialog.showModal(); dialog.querySelector('[data-ca-history-close]').focus();
  await load(); return closed;
}
