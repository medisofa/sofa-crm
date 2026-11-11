import { html } from '../utils/dom.js';
import { formDialog, fieldError, toast } from '../utils/ui.js';
import { viewAsState } from '../utils/view-as-state.js';
import { adminSetClaimAuthorization } from '../services/claim-authorization.js';

/** No expone el editor general de importes ni cambia el estado de la reclamación. */
export async function editClaimAuthorization(claim, { role, viewAs } = {}) {
  if (!['super_admin', 'admin'].includes(role) || viewAs || viewAsState.active) throw new Error('Esta corrección corresponde a Administración o Super Admin, fuera del modo soporte.');
  const result = await formDialog({
    title: claim.authorization_number ? 'Corregir autorización' : 'Registrar autorización', submitLabel: 'Guardar autorización',
    body: html`<p><b>${claim.folio}</b> · ${claim.patient_name}</p>
      <div class="note">Registra la autorización indicada por la ARS. La corrección queda en la bitácora y conserva los importes, pagos y estado de la reclamación.</div>
      <div class="field"><label>Autorización actual</label><p class="mono">${claim.authorization_number || 'Sin registrar'}</p></div>
      <div class="field"><label for="ca-number">Número de autorización *</label><input id="ca-number" name="number" maxlength="100" autocomplete="off" required value="${claim.authorization_number || ''}" placeholder="Número informado por la ARS"><span class="hint">Se conservan los ceros iniciales.</span></div>
      <div class="field"><label for="ca-reason">Motivo de la corrección *</label><textarea id="ca-reason" name="reason" rows="3" maxlength="1000" required placeholder="Ej.: autorización recibida después de la carga. Mínimo 10 caracteres."></textarea></div>
      <p class="small muted">El cambio no concilia pagos automáticamente. Vuelve a comprobar la reclamación y la referencia del pago con el nuevo número.</p>`,
    onSubmit: async (data, form) => {
      const number = String(data.number || '').trim(); const reason = String(data.reason || '').trim();
      if (!number || number.length > 100 || /[\u0000-\u001f\u007f]/.test(number)) { fieldError(form.elements.number, 'Indica un número válido de hasta 100 caracteres.'); return false; }
      if (reason.length < 10) { fieldError(form.elements.reason, 'Escribe un motivo de al menos 10 caracteres.'); return false; }
      return adminSetClaimAuthorization({ lineId: claim.id, number, reason, expectedNumber: claim.authorization_number ?? null });
    }
  });
  if (result) toast(result.changed === false ? 'La autorización ya tiene ese número.' : 'Autorización actualizada y registrada en la bitácora.', 'ok');
  return result;
}
