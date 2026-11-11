/**
 * SOFA · Iteración 12 — Reclamaciones individuales, captura rápida, retiros físicos,
 * tarifario contractual (Médico × ARS × Servicio × vigencia), factura fiscal y reparto de pagos.
 * Toda regla de negocio vive en PostgreSQL (026_reclamaciones.sql); aquí solo se llaman las funciones.
 */
import { sb } from '../supabase.js';
import { CLAIM_GROUPS } from '../utils/constants.js';

const must = ({ data, error }) => { if (error) throw error; return data; };
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();
let realOrgIdsCache = null;
async function realOrgIds() {
  if (realOrgIdsCache) return realOrgIdsCache;
  realOrgIdsCache = must(await sb().from('sofa_real_client_organizations').select('id')).map((r) => r.id);
  return realOrgIdsCache;
}
function applyRealScope(query, ids) {
  return ids.length ? query.in('organization_id', ids) : query.eq('organization_id', '00000000-0000-0000-0000-000000000000');
}

// ---------------------------------------------------------------- Captura rápida
/** Médicos visibles para el usuario (el Capturador solo ve los que tiene asignados, por RLS) */
export async function captureProviders({ realOnly = false } = {}) {
  let q = sb().from('providers').select('id, full_name, organization_id, organizations(legal_name)').eq('is_active', true);
  if (realOnly) q = applyRealScope(q, await realOrgIds());
  return must(await q.order('full_name').limit(1000));
}
export async function activeArs() { return must(await sb().from('ars').select('id, code, name, portal_url').eq('is_active', true).order('name')); }
/** Servicios contratados para Médico + ARS vigentes en la fecha del servicio (con SIMON, CUPS y tarifa) */
export async function contractedServices(provider, ars, date) {
  return must(await sb().rpc('contracted_services', { p_provider: provider, p_ars: ars, p_date: date }));
}

export async function searchCatalog(q, ars) {
  if (!q || q.length < 2) return [];
  let query = sb().from('procedures')
    .select('id, name, simon, cups, internal_code, ars_service_code')
    .or(`name.ilike.%${clean(q)}%,simon.ilike.%${clean(q)}%,cups.ilike.%${clean(q)}%`)
    .eq('is_active', true)
    .order('name').limit(30);
  if (ars) query = query.eq('ars_id', ars);
  return must(await query);
}

export async function patientLookup(q, orgId) {
  if (!q || q.length < 2) return [];
  const c = clean(q);
  const isNss = /^\d{9,}$/.test(c.replace(/\s/g, ''));
  let query = sb().from('org_patients')
    .select('id, patient_name, member_number, patient_doc')
    .eq('organization_id', orgId)
    .order('patient_name').limit(20);
  if (isNss) {
    query = query.ilike('member_number', `%${c}%`);
  } else {
    query = query.ilike('patient_name', `%${c}%`);
  }
  return must(await query);
}

export async function captureClaim(payload) {
  return must(await sb().rpc('capture_claim', payload));
}

export async function myRecentClaims(limit = 15) {
  return must(await sb().rpc('my_recent_claims', { p_limit: limit }));
}

// ---------------------------------------------------------------- Búsqueda y listado
const CLAIM_LIST_COLS = 'id, folio, claim_status, discrepancy_status, patient_name, provider_name, ars_name, service_name, claimed, created_at, organization_id';

export async function listClaims({ page = 1, pageSize = 50, search = '', status = '', ars = '', provider = '', dateFrom = '', dateTo = '', realOnly = false } = {}) {
  let q = sb().from('claims_view').select(CLAIM_LIST_COLS, { count: 'exact' });
  if (search) {
    const c = clean(search);
    q = q.or(`folio.ilike.%${c}%,patient_name.ilike.%${c}%,service_name.ilike.%${c}%`);
  }
  if (status) q = q.eq('claim_status', status);
  if (ars)    q = q.eq('ars_id', ars);
  if (provider) q = q.eq('provider_id', provider);
  if (dateFrom) q = q.gte('service_date', dateFrom);
  if (dateTo)   q = q.lte('service_date', dateTo);
  if (realOnly) q = applyRealScope(q, await realOrgIds());
  q = q.order('created_at', { ascending: false }).range((page - 1) * pageSize, page * pageSize - 1);
  const { data, error, count } = await q;
  if (error) throw error;
  return { data, count };
}

export async function getClaim(id) {
  return must(await sb().from('claims_view').select('*').eq('id', id).single());
}

export async function getClaimAttachments(claimId) {
  return must(await sb().from('claim_attachments').select('id, file_name, file_size, storage_path, created_at').eq('claim_id', claimId).order('created_at'));
}

export async function listPayments(claimId) {
  return must(await sb().from('claim_payments').select('id, paid_at, amount, payer, notes, created_at').eq('claim_id', claimId).order('paid_at'));
}

// ---------------------------------------------------------------- Edición
export async function editClaimField(id, field, value) {
  return must(await sb().rpc('edit_claim_field', { p_id: id, p_field: field, p_value: String(value ?? '') }));
}

export async function requestReview(id) {
  return must(await sb().rpc('request_claim_review', { p_id: id }));
}

export async function resolveDiscrepancy(id, resolution, notes) {
  return must(await sb().rpc('resolve_claim_discrepancy', { p_id: id, p_resolution: resolution, p_notes: notes || null }));
}

// ---------------------------------------------------------------- Remesa
export async function listRemesas({ page = 1, pageSize = 25, search = '', status = '', ars = '', realOnly = false } = {}) {
  let q = sb().from('remesas_view').select('id, folio, status, ars_name, claim_count, total_claimed, created_at, organization_id', { count: 'exact' });
  if (search) q = q.ilike('folio', `%${clean(search)}%`);
  if (status) q = q.eq('status', status);
  if (ars)    q = q.eq('ars_id', ars);
  if (realOnly) q = applyRealScope(q, await realOrgIds());
  q = q.order('created_at', { ascending: false }).range((page - 1) * pageSize, page * pageSize - 1);
  const { data, error, count } = await q;
  if (error) throw error;
  return { data, count };
}

export async function getRemesa(id) {
  return must(await sb().from('remesas_view').select('*').eq('id', id).single());
}

export async function getRemesaClaims(remesaId) {
  return must(await sb().from('remesa_claims_view').select(CLAIM_LIST_COLS).eq('remesa_id', remesaId).order('folio'));
}

export async function listGroups(claimGroup) {
  const g = CLAIM_GROUPS[claimGroup];
  if (!g) return [];
  let q = sb().from('claims_view').select(CLAIM_LIST_COLS).eq('claim_status', g.status);
  if (g.ars) q = q.eq('ars_id', g.ars);
  return must(await q.order('service_date').limit(500));
}

// ---------------------------------------------------------------- ARS y proveedores para filtros
export async function listArsForFilter() {
  return must(await sb().from('ars').select('id, name').eq('is_active', true).order('name'));
}

export async function listProvidersForFilter() {
  return must(await sb().from('providers').select('id, full_name').eq('is_active', true).order('full_name').limit(500));
}

// ---------------------------------------------------------------- Global patient match
export async function globalPatientMatch(doc, nss, orgId) {
  if (!doc && !nss) return null;
  return must(await sb().rpc('global_patient_match', { p_doc: doc || null, p_nss: nss || null, p_org: orgId }));
}
