/** SOFA · Servicios del consultorio (Iteración 16): agenda, cobros privados, cuadre del día, tarifas privadas y "Mi práctica". */
import { sb } from '../supabase.js';

const must = ({ data, error }) => { if (error) throw error; return data; };
const rpc = async (fn, args) => must(await sb().rpc(fn, args));

export async function listAppointments(providerId, date) {
  return must(await sb().from('appointments').select('*, ars(name)').eq('provider_id', providerId).eq('appointment_date', date)
    .order('appointment_time', { ascending: true, nullsFirst: false }).order('created_at'));
}
export async function getAppointment(id) { return must(await sb().from('appointments').select('*, ars(name)').eq('id', id).maybeSingle()); }
export async function saveAppointment(v) {
  return rpc('save_appointment', { p_id: v.id || null, p_provider: v.provider, p_date: v.date, p_time: v.time || null, p_patient: v.patient, p_doc: v.doc || null,
    p_member: v.member || null, p_phone: v.phone || null, p_payer: v.payer, p_ars: v.payer === 'ars' ? v.ars : null, p_authorization: v.authorization || null,
    p_reason: v.reason || null, p_notes: v.notes || null });
}
export async function setAppointmentStatus(id, status, note = null) { await rpc('set_appointment_status', { p_id: id, p_status: status, p_note: note }); return true; }
export async function linkAppointmentClaim(appointmentId, lineId) { await rpc('link_appointment_claim', { p_appointment: appointmentId, p_line: lineId }); return true; }

export async function listPrivateCharges(providerId, date) {
  return must(await sb().from('private_charges').select('*').eq('provider_id', providerId).or(`charge_date.eq.${date},collected_on.eq.${date}`).order('created_at'));
}
export async function pendingPrivateCharges(providerId) {
  return must(await sb().from('private_charges').select('*').eq('provider_id', providerId).eq('status', 'pendiente').order('charge_date'));
}
export async function registerPrivateCharge(v) {
  return rpc('register_private_charge', { p_provider: v.provider, p_date: v.date, p_patient: v.patient, p_doc: v.doc || null, p_procedure: v.procedure, p_quantity: v.quantity || 1,
    p_method: v.method, p_reference: v.reference || null, p_discount: Number(v.discount || 0), p_discount_reason: v.discountReason || null, p_appointment: v.appointment || null });
}
export async function collectPrivateCharge(id, method, reference) { await rpc('collect_private_charge', { p_id: id, p_method: method, p_reference: reference || null }); return true; }
export async function voidPrivateCharge(id, reason) { await rpc('void_private_charge', { p_id: id, p_reason: reason }); return true; }

export async function daySummary(providerId, date) { return rpc('day_summary', { p_provider: providerId, p_date: date }); }
export async function closeDay(providerId, date, counted, notes) { return rpc('close_day', { p_provider: providerId, p_date: date, p_counted: counted, p_notes: notes || null }); }
export async function reopenDay(closingId, reason) { await rpc('reopen_day', { p_closing: closingId, p_reason: reason }); return true; }

export async function listPrivateTariffs(providerId) {
  return must(await sb().from('private_tariffs').select('id, provider_id, procedure_id, amount, valid_during, status, notes, created_at, procedures(internal_code, description)')
    .eq('provider_id', providerId).order('created_at', { ascending: false }));
}
export async function createPrivateTariff(v) {
  return rpc('create_private_tariff', { p_provider: v.provider, p_procedure: v.procedure, p_amount: Number(v.amount), p_valid_from: v.from, p_notes: v.notes || null });
}
/** Servicios con tarifa privada vigente hoy (para el cobro) */
export async function privateServices(providerId, date) {
  const rows = must(await sb().from('private_tariffs').select('procedure_id, amount, valid_during, status, procedures(internal_code, description)')
    .eq('provider_id', providerId).eq('status', 'vigente'));
  return rows.filter((t) => inRange(t.valid_during, date)).map((t) => ({ procedure_id: t.procedure_id, amount: Number(t.amount), name: t.procedures?.description || t.procedures?.internal_code }));
}
/** daterange de PostgREST: "[2026-09-01,)" o "[2026-09-01,2026-10-01)" */
export function inRange(range, date) {
  const m = /^[[(]([^,]*),([^\])]*)[\])]$/.exec(range || ''); if (!m) return false;
  return (!m[1] || m[1] <= date) && (!m[2] || date < m[2]);
}
export async function practiceDashboard(providerId) { return rpc('practice_dashboard', { p_provider: providerId }); }

// ---- 1.7 · B1 copagos con comprobante · B2 elegibilidad y fecha de autorización
export async function registerCopay(appointmentId, type, amount, method, reference, note) {
  return rpc('register_copay', { p_appointment: appointmentId, p_type: type, p_amount: Number(amount), p_method: method, p_reference: reference || null, p_note: note || null });
}
export async function receiptDocument(chargeId) { return rpc('receipt_document', { p_charge: chargeId }); }
export async function setEligibility(appointmentId, status, source, reference, authorizationDate) {
  await rpc('set_eligibility', { p_appointment: appointmentId, p_status: status, p_source: source, p_reference: reference, p_authorization_date: authorizationDate || null }); return true;
}
export async function setClaimAuthorizationDate(lineId, date) { await rpc('set_claim_authorization_date', { p_line: lineId, p_date: date }); return true; }
