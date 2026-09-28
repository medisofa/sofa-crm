/** SOFA · Catálogos: ARS, procedimientos, códigos y tarifas */
import { sb } from '../supabase.js';

const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();
const must = ({ data, error }) => { if (error) throw error; return data; };
const mustCount = ({ data, error, count }) => { if (error) throw error; return { data, count: count ?? data.length }; };

export async function listArs() {
  return must(await sb().from('ars').select('id, code, name, regime_default, submission_channel, notes, is_active').order('name'));
}
export async function tariffCountsByArs() {
  const rows = must(await sb().from('tariffs').select('ars_id').limit(10000));
  return rows.reduce((m, r) => { m[r.ars_id] = (m[r.ars_id] || 0) + 1; return m; }, {});
}
export async function codedProcedureIds() {
  const rows = must(await sb().from('procedure_codes').select('procedure_id').limit(10000));
  return [...new Set(rows.map((r) => r.procedure_id))];
}
/** Búsqueda por descripción o código, con filtros y paginación en servidor */
export async function searchProcedures({ q = '', family = '', onlyUncoded = false, page = 0, size = 25 } = {}) {
  const term = clean(q);
  let byCode = null;
  if (term) {
    const rows = must(await sb().from('procedure_codes').select('procedure_id').ilike('code', `%${term}%`).limit(200));
    byCode = [...new Set(rows.map((r) => r.procedure_id))];
  }
  let query = sb().from('procedures').select('id, internal_code, description, family, service_type_code, source_note', { count: 'exact' }).eq('is_active', true);
  if (family) query = query.eq('family', family);
  if (term) {
    query = byCode.length ? query.or(`description.ilike.%${term}%,internal_code.ilike.%${term}%,id.in.(${byCode.join(',')})`)
                          : query.or(`description.ilike.%${term}%,internal_code.ilike.%${term}%`);
  }
  if (onlyUncoded) {
    const coded = await codedProcedureIds();
    if (coded.length) query = query.not('id', 'in', `(${coded.join(',')})`);
  }
  query = query.order('internal_code').range(page * size, page * size + size - 1);
  return mustCount(await query);
}
export async function codesFor(ids) {
  if (!ids.length) return [];
  return must(await sb().from('procedure_codes').select('procedure_id, code_system, code, ars_id').in('procedure_id', ids));
}
export async function tariffsFor(ids) {
  if (!ids.length) return [];
  return must(await sb().from('tariffs').select('procedure_id, ars_id, amount, valid_during, provider_id').in('procedure_id', ids).is('provider_id', null));
}
