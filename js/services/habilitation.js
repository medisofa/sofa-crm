/** SOFA · Habilitación ante MISPAS: casos, checklist con semáforo y checklist maestro */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
const withCount = ({ data, error, count }) => { if (error) throw error; return { data, count: count ?? data.length }; };
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();

export const STAGES = ['diagnostico', 'correccion', 'ensamblaje', 'depositado', 'inspeccion', 'habilitado'];
export const STAGE_LABEL = { diagnostico: 'Diagnóstico de brechas', correccion: 'Corrección', ensamblaje: 'Ensamblaje del expediente', depositado: 'Depositado en DGHA', inspeccion: 'Inspección', habilitado: 'Habilitado', cancelado: 'Cancelado' };
export const ITEM_STATUS = { pendiente: ['Sin evaluar', ''], verde: ['Verde · listo', 'ok'], amarillo: ['Amarillo · < 15 días', 'warn'], rojo: ['Rojo · obra o inversión', 'bad'], no_aplica: ['No aplica', ''] };
export const EST_TYPES = ['Consultorio', 'Centro médico', 'Clínica', 'Laboratorio', 'Centro diagnóstico', 'Otro'];
export const CASE_KIND = { apertura: 'Apertura', renovacion: 'Renovación', actualizacion: 'Actualización' };

export async function listCases({ group = 'activos', q = '', orgId = '', page = 0, size = 25 } = {}) {
  let query = sb().from('v_habilitation_cases').select('*', { count: 'exact' });
  if (group === 'activos') query = query.not('stage', 'in', '(habilitado,cancelado)');
  if (group === 'habilitados') query = query.eq('stage', 'habilitado');
  if (group === 'cancelados') query = query.eq('stage', 'cancelado');
  if (orgId) query = query.eq('organization_id', orgId);
  const t = clean(q); if (t) query = query.or(`establishment_name.ilike.%${t}%,folio.ilike.%${t}%,client_name.ilike.%${t}%,lead_company.ilike.%${t}%`);
  return withCount(await query.order('target_date', { ascending: true, nullsFirst: false }).order('created_at', { ascending: false }).range(page * size, page * size + size - 1));
}
export async function caseSummary() { return must(await sb().from('v_habilitation_cases').select('stage, license_days_left, days_to_target, critical_open').limit(5000)); }
export async function getCase(id) { return must(await sb().from('v_habilitation_cases').select('*').eq('id', id).maybeSingle()); }
export async function caseItems(id) {
  return must(await sb().from('habilitation_items').select('id, area, requirement, is_critical, status, notes, due_on, document_id, sort_order, requirement_id, habilitation_requirements(code, evidence_hint)').eq('case_id', id).order('sort_order'));
}
export async function updateItem(id, values) { return must(await sb().from('habilitation_items').update(values).eq('id', id).select('id, status').single()); }
export async function updateCase(id, values) { return must(await sb().from('habilitation_cases').update(values).eq('id', id).select('id').single()); }
export async function createCase({ name, type, orgId = null, leadId = null, kind = 'apertura', fee = 0, target = null, notes = null }) {
  return must(await sb().rpc('create_habilitation_case', { p_name: name, p_type: type, p_org: orgId, p_lead: leadId, p_kind: kind, p_fee: fee, p_target: target, p_notes: notes }));
}
export async function moveCase(id, stage, comment = null, override = null) {
  return must(await sb().rpc('move_habilitation_case', { p_case: id, p_stage: stage, p_comment: comment, p_override: override }));
}
export async function caseActivity(id) {
  return must(await sb().from('activities').select('id, activity_type, body, occurred_at, created_by').eq('entity_type', 'habilitation').eq('entity_id', id).order('occurred_at', { ascending: false }).limit(100));
}
export async function requirementsCatalog() { return must(await sb().from('habilitation_requirements').select('*').order('sort_order')); }
export async function saveRequirement(v, id = null) {
  if (id) return must(await sb().from('habilitation_requirements').update(v).eq('id', id).select('id').single());
  return must(await sb().from('habilitation_requirements').insert(v).select('id').single());
}
export async function leadOptions() { return must(await sb().from('leads').select('id, company, whatsapp').is('converted_org_id', null).order('company').limit(1000)); }
export async function leadContact(id) { return must(await sb().from('leads').select('id, company, whatsapp').eq('id', id).maybeSingle()); }
