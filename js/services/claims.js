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
