/** SOFA · Radicaciones (desglose de servicios del período por prestador y ARS) */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();

export const GROUPS = {
  todas: { label: 'Todas' },
  preparacion: { label: 'En preparación', statuses: ['borrador', 'recibida', 'pendiente_documentos', 'en_depuracion'] },
  listas: { label: 'Listas para radicar', statuses: ['lista_para_radicar'] },
  radicadas: { label: 'Radicadas por cobrar', statuses: ['radicada', 'en_auditoria_ars'] },
  cerradas: { label: 'Cerradas y rechazadas', statuses: ['cerrada', 'rechazada'] }
};

export async function listSubmissions({ group = 'todas', orgId = '', arsId = '', period = '', q = '', page = 0, size = 25 } = {}) {
  let query = sb().from('v_submissions').select('*', { count: 'exact' });
  const g = GROUPS[group];
  if (g?.statuses) query = query.in('status', g.statuses);
  if (group === 'radicadas') query = query.gt('balance', 0);
  if (orgId) query = query.eq('organization_id', orgId);
  if (arsId) query = query.eq('ars_id', arsId);
  if (period) query = query.eq('period', `${period}-01`);
  const t = clean(q);
  if (t) query = query.or(`folio.ilike.%${t}%,provider_name.ilike.%${t}%,client_name.ilike.%${t}%`);
  const { data, error, count } = await query.order('period', { ascending: false }).order('created_at', { ascending: false }).range(page * size, page * size + size - 1);
  if (error) throw error;
  return { data, count: count ?? data.length };
}
/** Cifras para las tarjetas del listado (solo columnas livianas) */
export async function submissionSummary() {
  return must(await sb().from('v_submissions').select('status, display_status, claimed, balance, payment_deadline, submitted_on').limit(5000));
}
export async function getSubmission(id) { return must(await sb().from('v_submissions').select('*').eq('id', id).maybeSingle()); }
export async function newSubmission({ provider, ars, period, plan = null, notes = null }) {
  return must(await sb().rpc('new_submission', { p_provider: provider, p_ars: ars, p_period: period, p_plan: plan, p_notes: notes }));
}
export async function updateSubmission(id, values) { return must(await sb().from('submissions').update(values).eq('id', id).select('id').single()); }
export async function deleteSubmission(id) { const { error } = await sb().from('submissions').delete().eq('id', id); if (error) throw error; }
export async function changeStatus(id, to, { comment = null, override = null, submittedOn = null, receipt = null } = {}) {
  return must(await sb().rpc('change_submission_status', { p_submission: id, p_to: to, p_comment: comment, p_override_reason: override, p_submitted_on: submittedOn, p_ars_receipt: receipt }));
}
export async function validateSubmission(id, save = false) { return must(await sb().rpc('validate_submission', { p_submission: id, p_save: save })); }
export async function transitionsFrom(status) {
  return must(await sb().from('submission_transitions').select('to_code, allowed_roles, requires_validation').eq('from_code', status));
}
export async function statusHistory(id) {
  return must(await sb().from('submission_status_history').select('from_status, to_status, changed_by, changed_at, comment, is_override').eq('submission_id', id).order('changed_at', { ascending: false }).limit(100));
}
export async function profileNames(ids) {
  const u = [...new Set(ids.filter(Boolean))]; if (!u.length) return {};
  const rows = must(await sb().from('profiles').select('id, full_name').in('id', u));
  return Object.fromEntries(rows.map((r) => [r.id, r.full_name]));
}

// ---- Servicios (líneas)
export async function listLines(submissionId) {
  return must(await sb().from('service_lines').select('*, procedures(internal_code, description, service_type_code)').eq('submission_id', submissionId).order('service_date').order('created_at'));
}
export async function lineChecklist(submissionId) {
  return must(await sb().from('v_line_checklist').select('service_line_id, required, present, pct, complete').eq('submission_id', submissionId));
}
const lineRow = (v) => ({
  service_date: v.service_date, patient_name: v.patient_name.trim(),
  patient_doc: v.patient_doc ? v.patient_doc.replace(/\D/g, '') : null,
  member_number: v.member_number ? v.member_number.trim() : null,
  authorization_number: v.authorization_number ? v.authorization_number.trim() : null,
  procedure_id: v.procedure_id, quantity: Number(v.quantity || 1), unit_amount: Number(v.unit_amount),
  notes: v.notes ? v.notes.trim() : null
});
export async function addLine(sub, v) {
  return must(await sb().from('service_lines').insert({ ...lineRow(v), submission_id: sub.id, organization_id: sub.organization_id }).select('id').single());
}
export async function updateLine(id, v) { return must(await sb().from('service_lines').update(lineRow(v)).eq('id', id).select('id').single()); }
export async function deleteLine(id) { const { error } = await sb().from('service_lines').delete().eq('id', id); if (error) throw error; }
export async function lookupTariff(procedure, ars, date, provider = null, plan = null) {
  const rows = must(await sb().rpc('lookup_tariff', { p_procedure: procedure, p_ars: ars, p_date: date, p_provider: provider, p_plan: plan }));
  return rows?.[0] || null;
}
export async function checkDuplicate(org, ars, member, date, procedure, authorization = null) {
  return must(await sb().rpc('check_duplicate_line', { p_org: org, p_ars: ars, p_member: member || null, p_date: date, p_procedure: procedure, p_authorization: authorization || null }));
}
export async function importLines(submissionId, rows, skipDuplicates = true) {
  return must(await sb().rpc('import_service_lines', { p_submission: submissionId, p_rows: rows, p_skip_duplicates: skipDuplicates }));
}

// ---- Checklist documental
export async function requirements() {
  return must(await sb().from('document_requirements').select('service_type_code, document_type_code, is_mandatory, document_types(name, sort_order)').eq('is_mandatory', true));
}
export async function documentTypes() { return must(await sb().from('document_types').select('code, name, sort_order').order('sort_order')); }
export async function lineChecks(lineIds) {
  if (!lineIds.length) return [];
  return must(await sb().from('line_document_checks').select('service_line_id, document_type_code, present').in('service_line_id', lineIds));
}
export async function setLineCheck(line, docType, present) {
  if (present) {
    return must(await sb().from('line_document_checks').upsert({ service_line_id: line.id, organization_id: line.organization_id, document_type_code: docType, present: true }, { onConflict: 'service_line_id,document_type_code' }).select('service_line_id').single());
  }
  const { error } = await sb().from('line_document_checks').delete().eq('service_line_id', line.id).eq('document_type_code', docType);
  if (error) throw error; return null;
}

// ---- Catálogos para capturar servicios
export async function activeProviders(orgId = '') {
  let q = sb().from('providers').select('id, full_name, provider_type, organization_id, organizations(legal_name)').eq('is_active', true);
  if (orgId) q = q.eq('organization_id', orgId);
  return must(await q.order('full_name').limit(1000));
}
export async function providerCodes(providerId) {
  return must(await sb().from('provider_ars_codes').select('ars_id, status, code').eq('provider_id', providerId));
}
export async function procedureOptions(arsId) {
  const [procs, tariffs] = await Promise.all([
    must(await sb().from('procedures').select('id, internal_code, description, service_type_code, procedure_codes(code_system, code, ars_id)').eq('is_active', true).order('description').limit(2000)),
    must(await sb().from('tariffs').select('procedure_id, amount, valid_during').eq('ars_id', arsId).is('provider_id', null).limit(5000))
  ]);
  return { procs, tariffs };
}
export async function organizationContact(orgId) {
  return must(await sb().from('organizations').select('id, legal_name, whatsapp, phone').eq('id', orgId).maybeSingle());
}
