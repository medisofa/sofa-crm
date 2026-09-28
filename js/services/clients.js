/** SOFA · Clientes PSS: listado, ficha 360°, prestadores y códigos ARS */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();

export async function listClients({ q = '', status = '', page = 0, size = 25 } = {}) {
  let query = sb().from('v_client_360')
    .select('organization_id, legal_name, status, started_on, submissions, submitted, radicado, pagado, glosado, saldo, tasa_pago, tasa_glosa, vencidas, codigos_pendientes', { count: 'exact' });
  const t = clean(q);
  if (t) query = query.ilike('legal_name', `%${t}%`);
  if (status) query = query.eq('status', status);
  const { data, error, count } = await query.order('legal_name').range(page * size, page * size + size - 1);
  if (error) throw error;
  return { data, count };
}
export async function getClient(id) {
  const [org, stats] = await Promise.all([
    sb().from('organizations').select('*').eq('id', id).maybeSingle(),
    sb().from('v_client_360').select('*').eq('organization_id', id).maybeSingle()
  ]);
  if (org.error) throw org.error;
  return { org: org.data, stats: stats.error ? null : stats.data };
}
/** Alta en una transacción (organización + reglas de honorario + prestador) */
export async function createClient(v) {
  return must(await sb().rpc('create_client', {
    p_legal_name: v.legal_name, p_tax_id: v.tax_id || null, p_org_type: v.org_type, p_specialty: v.specialty || null,
    p_phone: v.phone || null, p_whatsapp: v.whatsapp || null, p_email: v.email || null, p_city: v.city || null,
    p_started_on: v.started_on || null, p_monthly_fee: Number(v.monthly_fee || 0), p_success_pct: Number(v.success_pct || 0),
    p_provider_name: v.provider_name || null, p_exequatur: v.exequatur || null }));
}
export async function updateClient(id, v) {
  const row = { legal_name: v.legal_name.trim(), trade_name: v.trade_name || null, tax_id: v.tax_id ? v.tax_id.replace(/\D/g, '') : null,
    org_type: v.org_type, specialty: v.specialty || null, phone: v.phone || null, whatsapp: v.whatsapp ? v.whatsapp.replace(/\D/g, '') : null,
    email: v.email ? v.email.trim().toLowerCase() : null, address: v.address || null, city: v.city || null, status: v.status, notes: v.notes || null };
  const { error } = await sb().from('organizations').update(row).eq('id', id); // sin RETURNING: RLS de SELECT se evalúa aparte
  if (error) throw error;
}
export async function listProviders(orgId) {
  return must(await sb().from('providers').select('id, full_name, provider_type, tax_id, exequatur, specialty, is_active').eq('organization_id', orgId).order('full_name'));
}
export async function saveProvider(orgId, v, id = null) {
  const row = { full_name: v.full_name.trim(), provider_type: v.provider_type, tax_id: v.tax_id ? v.tax_id.replace(/\D/g, '') : null,
    exequatur: v.exequatur || null, specialty: v.specialty || null, is_active: v.is_active !== false };
  if (id) return must(await sb().from('providers').update(row).eq('id', id).select('id').single());
  return must(await sb().from('providers').insert({ ...row, organization_id: orgId }).select('id').single());
}
export async function listCodes(orgId) {
  return must(await sb().from('provider_ars_codes').select('id, provider_id, ars_id, code, status, requested_on, granted_on, notes, providers(full_name), ars(name)').eq('organization_id', orgId));
}
export async function saveCode(orgId, v, id = null) {
  const row = { status: v.status, code: v.code?.trim() || null, requested_on: v.requested_on || null, granted_on: v.granted_on || null, notes: v.notes || null };
  if (id) return must(await sb().from('provider_ars_codes').update(row).eq('id', id).select('id').single());
  return must(await sb().from('provider_ars_codes').insert({ ...row, organization_id: orgId, provider_id: v.provider_id, ars_id: v.ars_id }).select('id').single());
}
