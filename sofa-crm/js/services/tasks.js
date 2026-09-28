/** SOFA · Tareas */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
export async function listTasks({ bucket = '', assignee = '', entityType = '', entityId = '' } = {}) {
  let q = sb().from('v_tasks').select('*');
  if (bucket) q = q.eq('bucket', bucket);
  if (assignee) q = q.eq('assignee_id', assignee);
  if (entityType) q = q.eq('entity_type', entityType).eq('entity_id', entityId);
  return must(await q.order('due_date', { ascending: bucket !== 'completadas' }).limit(300));
}
export async function taskCounts(assignee = '') {
  let q = sb().from('v_tasks').select('bucket');
  if (assignee) q = q.eq('assignee_id', assignee);
  const rows = must(await q.limit(2000));
  return rows.reduce((m, r) => { m[r.bucket] = (m[r.bucket] || 0) + 1; return m; }, { hoy: 0, vencidas: 0, proximas: 0, completadas: 0 });
}
export async function createTask(operatorId, v, entity = null) {
  return must(await sb().from('tasks').insert({ operator_id: operatorId, title: v.title.trim(), priority: v.priority || 'media', due_date: v.due_date,
    assignee_id: v.assignee_id || null, notes: v.notes || null, entity_type: entity?.type || null, entity_id: entity?.id || null,
    organization_id: entity?.organizationId || null }).select('id').single());
}
export async function updateTask(id, values) { return must(await sb().from('tasks').update(values).eq('id', id).select('id, status, due_date').single()); }
