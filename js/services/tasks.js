/** SOFA · Tareas */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
let realIdsCache = null;
async function realOrgIds() {
  if (realIdsCache) return realIdsCache;
  realIdsCache = must(await sb().from('sofa_real_client_organizations').select('id')).map((r) => r.id);
  return realIdsCache;
}
function applyTaskScope(q, ids) {
  return ids.length ? q.or(`organization_id.is.null,organization_id.in.(${ids.join(',')})`) : q.is('organization_id', null);
}
const TASK_LIST_COLS = 'id, title, priority, notes, entity_type, entity_id, entity_label, due_date, bucket, assignee_name, assignee_id, status, organization_id';
export async function listTasks({ bucket = '', assignee = '', entityType = '', entityId = '', realOnly = false } = {}) {
  let q = sb().from('v_tasks').select(TASK_LIST_COLS);
  if (realOnly) q = applyTaskScope(q, await realOrgIds());
  if (bucket) q = q.eq('bucket', bucket);
  if (assignee) q = q.eq('assignee_id', assignee);
  if (entityType) q = q.eq('entity_type', entityType).eq('entity_id', entityId);
  return must(await q.order('due_date', { ascending: bucket !== 'completadas' }).limit(300));
}
export async function taskCounts(assignee = '', { realOnly = false } = {}) {
  const rows = must(await sb().rpc('task_bucket_counts', { p_assignee: assignee || null, p_real_only: realOnly }));
  return rows.reduce((m, r) => { m[r.bucket] = Number(r.cnt); return m; }, { hoy: 0, vencidas: 0, proximas: 0, completadas: 0 });
}
export async function createTask(operatorId, v, entity = null) {
  return must(await sb().from('tasks').insert({ operator_id: operatorId, title: v.title.trim(), priority: v.priority || 'media', due_date: v.due_date,
    assignee_id: v.assignee_id || null, notes: v.notes || null, entity_type: entity?.type || null, entity_id: entity?.id || null,
    organization_id: entity?.organizationId || null }).select('id').single());
}
export async function updateTask(id, values) { return must(await sb().from('tasks').update(values).eq('id', id).select('id, status, due_date').single()); }
