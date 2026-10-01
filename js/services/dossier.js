/** SOFA · Expediente por reclamación, reglas documentales, pre-radicación y envío a la ARS (Iteración 13 · 028_expediente.sql) */
import { sb } from '../supabase.js';

const must = ({ data, error }) => { if (error) throw error; return data; };

// ---------------------------------------------------------------- expediente
/** Documentos que exige la regla más específica para un servicio, ARS y modalidad */
export async function requiredDocsPreview(procedureId, arsId = null, careMode = null) {
  return must(await sb().rpc('required_docs_preview', { p_procedure: procedureId, p_ars: arsId, p_care_mode: careMode || null }));
}
/** { items:[{code,name,mandatory,checked,files,present}], missing:[], complete, exception, ok, care_mode } */
export async function claimDossier(lineId) {
  return must(await sb().rpc('claim_dossier', { p_line: lineId }));
}
/** Estado del expediente de varias reclamaciones (para listados) */
export async function dossierStatus(lineIds) {
  if (!lineIds.length) return {};
  const rows = must(await sb().from('v_claim_dossier').select('service_line_id, missing, complete, excepted, ok').in('service_line_id', lineIds));
  return Object.fromEntries(rows.map((r) => [r.service_line_id, r]));
}
/** Ids de reclamaciones con expediente incompleto y sin excepción (filtro del listado) */
export async function incompleteDossierIds(limit = 1000) {
  return must(await sb().from('v_claim_dossier').select('service_line_id').eq('ok', false).limit(limit)).map((r) => r.service_line_id);
}
export async function claimFiles(lineId) {
  return must(await sb().from('documents').select('id, organization_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes, uploaded_at, uploaded_by')
    .eq('service_line_id', lineId).order('uploaded_at', { ascending: false }));
}
/** Marca o desmarca un documento como recibido en físico (sin archivo) */
export async function setPhysicalCheck(line, docType, present) {
  if (present) {
    return must(await sb().from('line_document_checks').upsert({ service_line_id: line.id, organization_id: line.organization_id, document_type_code: docType, present: true },
      { onConflict: 'service_line_id,document_type_code' }).select('service_line_id').single());
  }
  const { error } = await sb().from('line_document_checks').delete().eq('service_line_id', line.id).eq('document_type_code', docType);
  if (error) throw error;
  return null;
}
export async function authorizeDossierException(lineIds, reason) {
  return must(await sb().rpc('authorize_dossier_exception', { p_lines: lineIds, p_reason: reason }));
}
export async function revokeDossierException(lineId, reason) {
  return must(await sb().rpc('revoke_dossier_exception', { p_line: lineId, p_reason: reason }));
}

// ---------------------------------------------------------------- reglas documentales
export async function documentTypes() {
  return must(await sb().from('document_types').select('code, name, sort_order').order('sort_order'));
}
export async function serviceTypes() {
  return must(await sb().from('service_types').select('code, name, sort_order').order('sort_order'));
}
export async function listRules({ docType = '', serviceType = '', arsId = '', careMode = '', q = '', onlyActive = true } = {}) {
  let r = sb().from('document_rules').select('id, service_type_code, procedure_id, ars_id, care_mode, document_type_code, requirement, notes, is_active, source, updated_at, procedures(internal_code, description), ars(name), document_types(name), service_types(name)');
  if (docType) r = r.eq('document_type_code', docType);
  if (serviceType) r = r.eq('service_type_code', serviceType);
  if (arsId) r = r.eq('ars_id', arsId);
  if (careMode) r = r.eq('care_mode', careMode);
  if (onlyActive) r = r.eq('is_active', true);
  let rows = must(await r.order('document_type_code').limit(1000));
  if (q) { const t = q.toLowerCase(); rows = rows.filter((x) => [x.procedures?.description, x.procedures?.internal_code, x.ars?.name, x.document_types?.name, x.notes].some((v) => (v || '').toLowerCase().includes(t))); }
  return rows;
}
export async function saveRule(rule) {
  const row = { service_type_code: rule.serviceType || null, procedure_id: rule.procedure || null, ars_id: rule.ars || null, care_mode: rule.careMode || null,
    document_type_code: rule.docType, requirement: rule.requirement, notes: rule.notes || null, is_active: rule.active !== false };
  if (rule.id) return must(await sb().from('document_rules').update(row).eq('id', rule.id).select('id').single());
  return must(await sb().from('document_rules').insert(row).select('id').single());
}

// ---------------------------------------------------------------- pre-radicación y envío
export async function preradBatches({ providerId = '', arsId = '', readyOnly = false } = {}) {
  let q = sb().from('v_prerad_batches').select('*');
  if (providerId) q = q.eq('provider_id', providerId);
  if (arsId) q = q.eq('ars_id', arsId);
  if (readyOnly) q = q.eq('claims_ready', true).eq('fiscal_ok', true);
  return must(await q.order('period', { ascending: false }).order('provider_name').limit(500));
}
export async function getDelivery(submissionId) {
  return must(await sb().from('submissions').select('id, status, sent_on, sent_by, sent_via, sent_tracking, sent_evidence_id').eq('id', submissionId).maybeSingle());
}
export async function markSubmissionSent(submissionId, { sentOn, via, tracking = null, evidence = null }) {
  return must(await sb().rpc('mark_submission_sent', { p_submission: submissionId, p_sent_on: sentOn, p_via: via, p_tracking: tracking || null, p_evidence: evidence || null }));
}
