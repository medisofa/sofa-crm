/** SOFA · 24 · Atender una cita de ARS y crear su reclamación en un paso.
 *  Uso desde la Agenda / Trabajo de hoy: render(contenedor, { appointment, onDone }).
 *  appointment necesita: id, provider_id, ars_id, patient_name, reason. */
import { rpc, h, money, note, careModesFor } from '../services/iter18.js';

export async function render(root, { appointment: a, onDone } = {}) {
  root.replaceChildren();
  const msg = h('div', { 'aria-live': 'polite' });
  if (!a || !a.id) { root.append(note('Elija una cita de la agenda.', 'error')); return; }
  root.append(h('h3', {}, `Atender: ${a.patient_name}`), msg);
  let reasons = [], modes = [], centers = [];
  try {
    [reasons, modes, centers] = await Promise.all([
      a.ars_id ? rpc('appointment_reasons', { p_provider: a.provider_id, p_ars: a.ars_id }) : [],
      careModesFor(a.provider_id),
      rpc('provider_centers_of', { p_provider: a.provider_id }).catch(() => [])]);
  } catch (e) { msg.replaceChildren(note(e.message, 'error')); return; }
  const services = (reasons || []).filter((r) => r.kind === 'servicio');
  const match = services.find((s) => (s.label || '').trim().toLowerCase() === (a.reason || '').trim().toLowerCase());
  const svc = h('select', { id: 'at-svc' }, h('option', { value: '' }, '— Elija el servicio —'),
    services.map((s) => h('option', { value: s.procedure_id, selected: match && s.procedure_id === match.procedure_id }, `${s.label} · ${money(s.amount)}`)));
  const mode = h('select', { id: 'at-mode' }, (modes || []).map((m) => h('option', { value: m.code, selected: m.code === 'consultorio' }, m.label)));
  const center = h('select', { id: 'at-center' }, h('option', { value: '' }, '— Sin indicar —'),
    (centers || []).map((c) => h('option', { value: c.id, selected: !!c.primary }, c.name)));
  const amount = h('input', { id: 'at-amount', type: 'number', min: '0', step: '0.01', placeholder: 'Vacío = tarifa del contrato' });
  const reason = h('input', { id: 'at-disc', placeholder: 'Solo si el monto es distinto a la tarifa' });
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Atender y crear reclamación');
  root.append(h('div', { class: 'i18-form' },
    h('label', { for: 'at-svc' }, 'Servicio realizado *'), svc,
    h('label', { for: 'at-mode' }, 'Modalidad'), mode,
    h('label', { for: 'at-center' }, 'Centro de salud'), center,
    h('label', { for: 'at-amount' }, 'Monto (opcional)'), amount,
    h('label', { for: 'at-disc' }, 'Motivo de la diferencia'), reason, go));
  if (!services.length) msg.replaceChildren(note('Este médico no tiene servicios contratados vigentes con esta ARS. Pida a SOFA que registre el contrato.', 'error'));

  go.addEventListener('click', async () => {
    go.disabled = true; msg.replaceChildren();
    try {
      const r = await rpc('attend_appointment', { p_appointment: a.id, p_procedure: svc.value || null,
        p_amount: amount.value === '' ? null : Number(amount.value), p_care_mode: mode.value || 'consultorio',
        p_center: center.value || null, p_discrepancy_reason: reason.value.trim() || null, p_notes: null });
      msg.replaceChildren(note(`Listo: reclamación ${r.folio} por ${money(r.amount)} en el lote ${r.submission_folio}.`));
      if (typeof onDone === 'function') onDone(r);
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); go.disabled = false; }
  });
}
