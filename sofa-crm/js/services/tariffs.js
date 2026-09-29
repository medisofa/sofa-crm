/** SOFA · Tarifarios y codificación: conceptos, códigos, tarifas con vigencia e importación */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
const withCount = ({ data, error, count }) => { if (error) throw error; return { data, count: count ?? data.length }; };
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();

export async function listCurrentTariffs({ arsId = '', scope = '', orgId = '', q = '', page = 0, size = 50 } = {}) {
  let query = sb().from('v_tariffs_current').select('*', { count: 'exact' });
  if (arsId) query = query.eq('ars_id', arsId);
  if (scope) query = query.eq('scope', scope);
  if (orgId) query = query.eq('organization_id', orgId);
  const t = clean(q); if (t) query = query.or(`description.ilike.%${t}%,internal_code.ilike.%${t}%,provider_name.ilike.%${t}%`);
  return withCount(await query.order('description').order('ars_name').range(page * size, page * size + size - 1));
}
export async function tariffHistory(procedureId) {
  return must(await sb().from('tariffs').select('id, ars_id, plan_id, provider_id, amount, valid_during, source, created_at, ars(name), providers(full_name), ars_plans(name)')
    .eq('procedure_id', procedureId).order('valid_during', { ascending: false }).limit(500));
}
export async function tariffGaps({ onlyDiff = true } = {}) {
  let q = sb().from('v_tariff_gaps').select('*');
  if (onlyDiff) q = q.gt('gap_pct', 0);
  return must(await q.order('gap_pct', { ascending: false }).limit(1000));
}
export async function createTariff({ procedure, ars, amount, validFrom, provider = null, plan = null, source = null }) {
  return must(await sb().rpc('create_tariff', { p_procedure: procedure, p_ars: ars, p_amount: amount, p_valid_from: validFrom, p_provider: provider, p_plan: plan, p_source: source }));
}
export async function importTariffs({ ars, validFrom, rows, provider = null, plan = null, source = null }) {
  return must(await sb().rpc('import_tariffs', { p_ars: ars, p_valid_from: validFrom, p_rows: rows, p_provider: provider, p_plan: plan, p_source: source }));
}
export async function getProcedure(id) {
  return must(await sb().from('procedures').select('*, procedure_codes(id, code_system, code, ars_id), service_types(name)').eq('id', id).maybeSingle());
}
export async function createProcedure(v) {
  return must(await sb().from('procedures').insert({ description: v.description, service_type_code: v.service_type_code, family: v.family }).select('id').single());
}
export async function updateProcedure(id, v) { return must(await sb().from('procedures').update(v).eq('id', id).select('id').single()); }
export async function addCode(procedureId, system, code, arsId = null) {
  return must(await sb().from('procedure_codes').insert({ procedure_id: procedureId, code_system: system, code: code.trim(), ars_id: system === 'ARS' ? arsId : null }).select('id').single());
}
export async function deleteCode(id) { const { error } = await sb().from('procedure_codes').delete().eq('id', id); if (error) throw error; }
export async function serviceTypes() { return must(await sb().from('service_types').select('code, name').order('sort_order')); }
export async function plansFor(arsId) { return must(await sb().from('ars_plans').select('id, name').eq('ars_id', arsId).order('name')); }
export async function procedureList() {
  return must(await sb().from('procedures').select('id, internal_code, description').eq('is_active', true).order('description').limit(3000));
}
