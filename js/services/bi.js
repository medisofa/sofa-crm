/** SOFA · Consultas de inteligencia de negocio (todas respetan RLS) */
import { sb } from '../supabase.js';
import { todayISO, addMonths } from '../utils/formatters.js';
const must = ({ data, error }) => { if (error) throw error; return data; };

export const BUCKETS = ['0-30', '31-60', '61-90', '91-120', '120+'];
const first = (ym) => `${ym}-01`;
const last = (ym) => { const [y, m] = ym.split('-').map(Number); return `${ym}-${String(new Date(y, m, 0).getDate()).padStart(2, '0')}`; };
export const monthKey = (iso) => String(iso).slice(0, 7);
export function monthsBetween(from, to) {
  const out = []; let [y, m] = from.split('-').map(Number); const [ty, tm] = to.split('-').map(Number);
  while (y < ty || (y === ty && m <= tm)) { out.push(`${y}-${String(m).padStart(2, '0')}`); m += 1; if (m > 12) { m = 1; y += 1; } if (out.length > 36) break; }
  return out;
}
export function defaultRange(months = 6) {
  const to = todayISO().slice(0, 7);
  return { from: addMonths(to, -(months - 1)), to };
}
let realIdsCache = null;
async function realClientIds() {
  if (realIdsCache) return realIdsCache;
  realIdsCache = must(await sb().from('sofa_real_client_organizations').select('id')).map((r) => r.id);
  return realIdsCache;
}
const scope = (q, { orgId, arsId }) => { if (orgId) q = q.eq('organization_id', orgId); if (arsId) q = q.eq('ars_id', arsId); return q; };
function applyScoped(q, f = {}, ids = []) {
  q = scope(q, f);
  if (f.realOnly) q = ids.length ? q.in('organization_id', ids) : q.eq('organization_id', '00000000-0000-0000-0000-000000000000');
  return q;
}
async function scopeIds(f = {}) { return f.realOnly ? realClientIds() : []; }

export async function financialEvents(f) {
  const q = applyScoped(sb().from('v_financial_events').select('organization_id, ars_id, provider_id, submission_id, event_date, kind, amount'), f, await scopeIds(f));
  return must(await q.gte('event_date', first(f.from)).lte('event_date', last(f.to)).limit(20000));
}
export async function collectionDays(f) {
  const q = applyScoped(sb().from('v_collection_days').select('submission_id, ars_id, organization_id, days, fully_paid, last_paid_on'), f, await scopeIds(f));
  return must(await q.eq('fully_paid', true).gte('last_paid_on', first(f.from)).lte('last_paid_on', last(f.to)).limit(20000));
}
export async function serviceMix(f) {
  const q = applyScoped(sb().from('v_service_mix').select('*'), f, await scopeIds(f));
  return must(await q.gte('period', first(f.from)).lte('period', first(f.to)).limit(20000));
}
export async function openBalances(f = {}) {
  const q = applyScoped(sb().from('v_submissions').select('id, folio, organization_id, client_name, provider_name, ars_id, ars_name, period, submitted_on, claimed, paid, glosa_accepted, glosa_in_dispute, balance, payment_deadline, age_days, aging_bucket'), f, await scopeIds(f));
  return must(await q.not('submitted_on', 'is', null).gt('balance', 0).not('status', 'in', '(cerrada,rechazada)').order('age_days', { ascending: false }).limit(20000));
}
export async function submissionsInRange(f) {
  const q = applyScoped(sb().from('v_submissions').select('id, folio, organization_id, client_name, provider_name, ars_name, period, status, display_status, lines, claimed, paid, glosado, glosa_accepted, balance, submitted_on, docs_pct'), f, await scopeIds(f));
  return must(await q.gte('period', first(f.from)).lte('period', first(f.to)).order('period', { ascending: false }).limit(5000));
}
export async function feesInRange(f) {
  let q = sb().from('sofa_fees').select('organization_id, period, amount, source_type');
  q = applyScoped(q, { ...f, arsId: '' }, await scopeIds({ ...f, arsId: '' }));
  return must(await q.gte('period', first(f.from)).lte('period', first(f.to)).limit(20000));
}
export async function clientOptions() { return must(await sb().from('sofa_real_client_organizations').select('id, legal_name').order('legal_name').limit(2000)); }
export async function workQueue({ realOnly = false } = {}) {
  const rows = must(await sb().rpc('work_queue'));
  if (!realOnly) return rows;
  const ids = new Set(await realClientIds());
  return rows.filter((r) => !r.organization_id || ids.has(r.organization_id));
}
export async function growthMonthly({ realOnly = false } = {}) { return must(await sb().from(realOnly ? 'v_growth_monthly_real' : 'v_growth_monthly').select('*').order('month')); }
export async function mrr({ realOnly = false } = {}) { return must(await sb().from(realOnly ? 'v_mrr_real' : 'v_mrr').select('*').limit(1).maybeSingle()); }
export async function pipelineTotals() { return must(await sb().from('v_pipeline_real').select('stage, opportunities, monthly_value, weighted_value')); }
export async function growthTargets() { return must(await sb().from('growth_targets').select('*').order('ends_on')); }
export async function settings() { const { getSettings } = await import('./admin.js'); return getSettings(); }   // 4.7.0 (SEG-29): por app_settings_staff()
export async function glosaPareto(f = {}) { const q = applyScoped(sb().from('v_glosa_pareto').select('*'), f, await scopeIds(f)); return must(await q.limit(5000)); }
export async function feeSummaryAll({ realOnly = false } = {}) { let q = sb().from('v_fee_summary').select('*'); if (realOnly) { const ids = await realClientIds(); q = ids.length ? q.in('organization_id', ids) : q.eq('organization_id', '00000000-0000-0000-0000-000000000000'); } return must(await q.order('client_name')); }
