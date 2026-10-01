/**
 * SOFA · Iteración 12 — Reclamaciones individuales, captura rápida, retiros físicos,
 * tarifario contractual (Médico × ARS × Servicio × vigencia), factura fiscal y reparto de pagos.
 * Toda regla de negocio vive en PostgreSQL (026_reclamaciones.sql); aquí solo se llaman las funciones.
 */
import { sb } from '../supabase.js';
import { CLAIM_GROUPS } from '../utils/constants.js';

const must = ({ data, error }) => { if (error) throw error; return data; };
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();

// ---------------------------------------------------------------- Captura rápida
/** Médicos visibles para el usuario (el Capturador solo ve los que tiene asignados, por RLS) */
export async function captureProviders() {
  return must(await sb().from('providers').select('id, full_name, organization_id, organizations(legal_name)').eq('is_active', true).order('full_name').limit(1000));
}
export async function activeArs() { return must(await sb().from('ars').select('id, code, name').eq('is_active', true).order('name')); }
/** Servicios contratados para Médico + ARS vigentes en la fecha del servicio (con SIMON, CUPS y tarifa) */
export async function contractedServices(provider, ars, date) {
  return must(await sb().rpc('contracted_services', { p_provider: provider, p_ars: ars, p_date: date }));
}
/** Catálogo maestro (para detectar servicios existentes pero no contratados) */
export async function searchCatalog(q, limit = 12) {
  const t = clean(q);
  let query = sb().from('v_service_catalog').select('id, internal_code, name, category, specialty, service_type_code, simon, cups, is_active').eq('is_active', true);
  if (t) query = query.or(`name.ilike.%${t}%,internal_code.ilike.%${t}%,simon.ilike.%${t}%,cups.ilike.%${t}%,specialty.ilike.%${t}%,category.ilike.%${t}%`);
  return must(await query.order('name').limit(limit));
}
export async function patientLookup(provider, q) {
  if (String(q || '').trim().length < 2) return [];
  return must(await sb().rpc('patient_lookup', { p_provider: provider, p_q: q }));
}
/**
 * Registra una reclamación. Opciones del flujo:
 *  - amount: solo si difiere de la tarifa (exige discrepancyReason) o si no hay contrato
 *  - notContracted: 'bloquear' (defecto) | 'pendiente' | 'excepcion' (admin, exceptionReason ≥ 10)
 */
export async function captureClaim(v) {
  return must(await sb().rpc('capture_claim', {
    p_provider: v.provider, p_ars: v.ars, p_procedure: v.procedure, p_service_date: v.serviceDate,
    p_patient_name: v.patientName, p_member: v.member, p_authorization: v.authorization || null, p_patient_doc: v.patientDoc || null,
    p_amount: v.amount ?? null, p_quantity: v.quantity || 1, p_care_mode: v.careMode || null, p_clinic: v.clinic || null, p_notes: v.notes || null,
    p_discrepancy_reason: v.discrepancyReason || null, p_not_contracted: v.notContracted || 'bloquear', p_exception_reason: v.exceptionReason || null,
    p_allow_duplicate: !!v.allowDuplicate
  }));
}
/** Reclamaciones del día del usuario en la captura (para la lista lateral) */
export async function myRecentClaims(limit = 15) {
  const since = new Date(Date.now() - 18 * 3600 * 1000).toISOString();
  return must(await sb().from('v_claims').select('id, folio, patient_name, service_name, claimed, tariff_amount, claim_status, provider_name, ars_name, discrepancy_status, created_at')
    .gte('created_at', since).order('created_at', { ascending: false }).limit(limit));
}

// ---------------------------------------------------------------- Reclamaciones
const LIST_COLS = 'id, folio, organization_id, client_name, provider_id, provider_name, ars_id, ars_name, submission_id, submission_folio, service_date, patient_name, member_number, authorization_number, service_name, simon, cups, claimed, tariff_amount, contracted, claim_status, status_name, location_code, location_name, custodian_name, discrepancy_status, paid, glosado, balance, next_step, last_action_at, status_changed_at, dossier_ok, dossier_missing';
export async function listClaims({ group = 'todas', status = '', location = '', providerId = '', arsId = '', q = '', from = '', to = '', dossier = '', page = 0, size = 25 } = {}) {
  let query = sb().from('v_claims').select(LIST_COLS, { count: 'exact' });
  const g = CLAIM_GROUPS[group];
  if (status) query = query.eq('claim_status', status); else if (g?.statuses) query = query.in('claim_status', g.statuses);
  if (location) query = query.eq('location_code', location);
  if (dossier === 'incompleto') query = query.eq('dossier_ok', false); else if (dossier === 'completo') query = query.eq('dossier_ok', true);
  if (providerId) query = query.eq('provider_id', providerId);
  if (arsId) query = query.eq('ars_id', arsId);
  if (from) query = query.gte('service_date', from);
  if (to) query = query.lte('service_date', to);
  const t = clean(q);
  if (t) query = query.or(`folio.ilike.%${t}%,patient_name.ilike.%${t}%,member_number.ilike.%${t}%,authorization_number.ilike.%${t}%,submission_folio.ilike.%${t}%`);
  const { data, error, count } = await query.order('service_date', { ascending: false }).order('folio', { ascending: false }).range(page * size, page * size + size - 1);
  if (error) throw error;
  return { data, count: count ?? data.length };
}
export async function claimCounts() { return must(await sb().from('v_claims').select('claim_status').limit(20000)); }
export async function getClaim(id) { return must(await sb().from('v_claims').select('*').eq('id', id).maybeSingle()); }
export async function claimHistory(id) {
  return must(await sb().from('claim_status_history').select('id, from_status, to_status, from_location, to_location, custodian_label, comment, is_override, evidence_document_id, changed_by, changed_at')
    .eq('service_line_id', id).order('changed_at', { ascending: false }).order('id', { ascending: false }));
}
export async function claimAudits(id) {
  return must(await sb().from('claim_audits').select('id, result, observations, errors, missing_documents, corrections, auditor_id, audited_at').eq('service_line_id', id).order('audited_at', { ascending: false }));
}
export async function claimDiscrepancies(id) {
  return must(await sb().from('tariff_discrepancies').select('id, tariff_amount, registered_amount, diff_amount, diff_pct, reason, status, created_by, created_at, decided_by, decided_at, decision_note')
    .eq('service_line_id', id).order('created_at', { ascending: false }));
}
export async function claimChecks(id) { return must(await sb().rpc('claim_checks', { p_line: id })); }
export async function claimLocations() { return must(await sb().from('claim_locations').select('code, name, sort_order').eq('is_active', true).order('sort_order')); }
export async function claimTransitions() { return must(await sb().from('claim_transitions').select('from_code, to_code, allowed_roles, default_location')); }
export async function changeClaimStatus(ids, to, { comment = null, location = null, custodian = null, evidence = null, override = null } = {}) {
  return must(await sb().rpc('change_claim_status', { p_lines: ids, p_to: to, p_comment: comment, p_location: location, p_custodian_label: custodian, p_evidence: evidence, p_override: override }));
}
export async function auditClaims(ids, { result, observations = null, errors = [], missing = [], corrections = null }) {
  return must(await sb().rpc('audit_claims', { p_lines: ids, p_result: result, p_observations: observations, p_errors: errors, p_missing_documents: missing, p_corrections: corrections }));
}
export async function decideDiscrepancy(id, approve, note) { return must(await sb().rpc('decide_discrepancy', { p_id: id, p_approve: approve, p_note: note })); }
export async function recheckContract(id) { return must(await sb().rpc('recheck_claim_contract', { p_line: id })); }
export async function claimPaymentLines(id) {
  return must(await sb().from('payment_line_allocations').select('id, amount, method, reason, superseded_at, created_at, payments(paid_on, reference)').eq('service_line_id', id).order('created_at', { ascending: false }));
}
export async function claimGlosaItems(id) {
  return must(await sb().from('glosa_items').select('id, amount, accepted_amount, recovered_amount, reason_code, glosa_reasons(name), glosa_id, glosas(notified_on, status)').eq('service_line_id', id));
}

// ---------------------------------------------------------------- Retiros físicos
export async function listPickups({ status = '', providerId = '', page = 0, size = 25 } = {}) {
  let q = sb().from('receptions').select('id, folio, organization_id, provider_id, status, expected_count, received_count, delivered_by, received_by_label, differences, notes, received_on, created_at, confirmed_at, providers(full_name), organizations(legal_name)', { count: 'exact' }).like('folio', 'RET-%');
  if (status) q = q.eq('status', status);
  if (providerId) q = q.eq('provider_id', providerId);
  const { data, error, count } = await q.order('created_at', { ascending: false }).range(page * size, page * size + size - 1);
  if (error) throw error;
  return { data, count: count ?? data.length };
}
export async function getPickup(id) {
  return must(await sb().from('receptions').select('*, providers(full_name), organizations(legal_name, phone, whatsapp)').eq('id', id).maybeSingle());
}
export async function pickupItems(id) {
  const items = must(await sb().from('reception_items').select('service_line_id, received, observation').eq('reception_id', id));
  if (!items.length) return [];
  const claims = must(await sb().from('v_claims').select('id, folio, patient_name, member_number, authorization_number, service_date, service_name, ars_name, claimed, claim_status').in('id', items.map((i) => i.service_line_id)));
  const byId = Object.fromEntries(claims.map((c) => [c.id, c]));
  return items.map((i) => ({ ...i, claim: byId[i.service_line_id] || null })).sort((a, b) => String(a.claim?.folio).localeCompare(String(b.claim?.folio)));
}
/** Reclamaciones del médico que esperan retiro (Capturada o Pendiente de retiro) */
export async function pendingPickupClaims(providerId) {
  return must(await sb().from('v_claims').select('id, folio, patient_name, member_number, service_date, service_name, ars_name, claimed, claim_status, status_changed_at')
    .eq('provider_id', providerId).in('claim_status', ['capturada', 'pendiente_retiro']).order('service_date').limit(500));
}
export async function createPickup(provider, lines, notes = null) { return must(await sb().rpc('create_pickup', { p_provider: provider, p_lines: lines, p_notes: notes })); }
export async function confirmPickup(id, { received, deliveredBy, receivedBy = null, differences = null, location = 'oficina_sofa', observations = {} }) {
  return must(await sb().rpc('confirm_pickup', { p_reception: id, p_received: received, p_delivered_by: deliveredBy, p_received_by_label: receivedBy, p_differences: differences, p_location: location, p_observations: observations }));
}
export async function cancelPickup(id, reason) { return must(await sb().rpc('cancel_pickup', { p_reception: id, p_reason: reason })); }

// ---------------------------------------------------------------- Tarifario contractual
export async function listContracts({ providerId = '', arsId = '', q = '', status = '', onlyCurrent = false, page = 0, size = 50 } = {}) {
  let query = sb().from('v_contract_tariffs').select('*', { count: 'exact' });
  if (providerId) query = query.eq('provider_id', providerId);
  if (arsId) query = query.eq('ars_id', arsId);
  if (status) query = query.eq('status', status);
  if (onlyCurrent) query = query.eq('is_current', true);
  const t = clean(q);
  if (t) query = query.or(`service_name.ilike.%${t}%,internal_code.ilike.%${t}%,simon.ilike.%${t}%,cups.ilike.%${t}%,contract_ref.ilike.%${t}%`);
  const { data, error, count } = await query.order('provider_name').order('ars_name').order('service_name').order('valid_from', { ascending: false }).range(page * size, page * size + size - 1);
  if (error) throw error;
  return { data, count: count ?? data.length };
}
/** Historial de vigencias de un mismo Médico + ARS + Servicio */
export async function contractHistory(providerId, arsId, procedureId) {
  return must(await sb().from('v_contract_tariffs').select('id, amount, currency, valid_from, valid_to, status, contract_ref, source, created_at, claims')
    .eq('provider_id', providerId).eq('ars_id', arsId).eq('procedure_id', procedureId).order('valid_from', { ascending: false }));
}
export async function createContractTariff(v) {
  return must(await sb().rpc('create_contract_tariff', {
    p_provider: v.provider, p_ars: v.ars, p_procedure: v.procedure, p_amount: Number(v.amount), p_valid_from: v.validFrom,
    p_valid_to: v.validTo || null, p_contract_ref: v.contractRef || null, p_ars_code: v.arsCode || null, p_notes: v.notes || null, p_currency: v.currency || 'DOP'
  }));
}
/** Solo cambia el estado administrativo (vigente/suspendida/por revisar) y notas: el monto nunca se edita */
export async function setContractStatus(id, status, notes = undefined) {
  const values = { status }; if (notes !== undefined) values.notes = notes;
  return must(await sb().from('tariffs').update(values).eq('id', id).select('id').single());
}
export async function importContracts(rows, commit = false) { return must(await sb().rpc('import_contract_tariffs', { p_rows: rows, p_commit: commit })); }

// ---------------------------------------------------------------- Factura fiscal (D2) y entrega
/** Campos de factura fiscal, excepción y entrega (no están en v_submissions) */
export async function getFiscal(submissionId) {
  return must(await sb().from('submissions').select('id, ncf, fiscal_invoice_number, fiscal_amount, accountant_name, fiscal_requested_on, fiscal_received_on, fiscal_document_id, fiscal_exception_expected, fiscal_exception_amount, fiscal_exception_reason, fiscal_exception_by, fiscal_exception_at, delivery_method, delivery_batch, delivery_evidence_id')
    .eq('id', submissionId).maybeSingle());
}
/** Reclamaciones de la radicación con su estado y folio (para la ficha del lote) */
export async function submissionClaims(submissionId) {
  return must(await sb().from('service_lines').select('id, claim_folio, claim_status, location_code, contracted, amount').eq('submission_id', submissionId));
}
export async function fiscalCheck(submissionId) { return must(await sb().rpc('fiscal_check', { p_submission: submissionId })); }
export async function saveFiscal(submissionId, v) {
  return must(await sb().from('submissions').update({
    fiscal_invoice_number: v.number || null, fiscal_amount: v.amount === '' || v.amount == null ? null : Number(v.amount), accountant_name: v.accountant || null,
    fiscal_requested_on: v.requestedOn || null, fiscal_received_on: v.receivedOn || null, fiscal_document_id: v.documentId || null
  }).eq('id', submissionId).select('id').single());
}
export async function authorizeFiscalDifference(submissionId, reason) { return must(await sb().rpc('authorize_fiscal_difference', { p_submission: submissionId, p_reason: reason })); }

// ---------------------------------------------------------------- Reparto de pagos por reclamación (D4)
export async function submissionLineAllocations(submissionId) {
  return must(await sb().from('payment_line_allocations').select('id, allocation_id, payment_id, service_line_id, amount, method, reason, superseded_at, superseded_by, created_at, created_by, payments(paid_on, reference)')
    .eq('submission_id', submissionId).order('created_at', { ascending: false }));
}
export async function adjustDistribution(allocationId, items, reason) {
  return must(await sb().rpc('adjust_payment_distribution', { p_allocation: allocationId, p_items: items, p_reason: reason }));
}

// ---------------------------------------------------------------- Capturadores (alcance por médico)
export async function capturerScopes(userId) { return must(await sb().from('capturer_scopes').select('provider_id').eq('user_id', userId)).map((r) => r.provider_id); }
export async function providersOfOrg(orgId) { return must(await sb().from('providers').select('id, full_name').eq('organization_id', orgId).eq('is_active', true).order('full_name')); }
export async function setCapturerScope(userId, providerIds) { return must(await sb().rpc('set_capturer_scope', { p_user: userId, p_providers: providerIds })); }


// ---------------------------------------------------------------- Iteración 14 · post-radicación
/** Línea de tiempo de 14 hitos de una reclamación */
export async function claimTimeline(id) { return must(await sb().rpc('claim_timeline', { p_line: id })); }
/** Reenvía reclamaciones devueltas en una radicación complementaria; devuelve el id del lote nuevo */
export async function resubmitClaims(ids, reason) { return must(await sb().rpc('resubmit_claims', { p_lines: ids, p_reason: reason })); }
/** Reenvíos registrados de una reclamación (de qué lote a qué lote) */
export async function claimResubmissions(id) {
  return must(await sb().from('claim_resubmissions').select('id, reason, created_at, created_by, from:from_submission_id(id, folio), to:to_submission_id(id, folio)').eq('service_line_id', id).order('created_at'));
}
/** Tiempos por etapa (días) por ARS y total */
export async function stageTimes() { return must(await sb().from('v_stage_times').select('*')); }
/** Lote original y complementarios de una radicación */
export async function submissionFamily(id) {
  const self = must(await sb().from('submissions').select('id, parent_submission_id, is_complementary, parent:parent_submission_id(id, folio, status)').eq('id', id).maybeSingle());
  const children = must(await sb().from('submissions').select('id, folio, status, created_at').eq('parent_submission_id', id).order('created_at'));
  return { self, children };
}
/** Aprobado vs. pagado por reclamación de un lote */
export async function submissionClaimMoney(id) {
  return must(await sb().from('v_claims').select('id, folio, patient_name, claim_status, claimed, recognized, paid, glosado, balance, last_paid_on').eq('submission_id', id).order('folio'));
}
