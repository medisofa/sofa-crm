/** SOFA · 5.35.3 · Servicio del módulo #/mercadeo. Solo llamadas a Supabase/RPC. */
import { rpc } from './iter18.js';

/** Resumen (KPIs + actividades recientes + backlog) en un solo round-trip. */
export const overview = (from = null, to = null) => rpc('marketing_overview', { p_from: from, p_to: to });

/** Registrar o actualizar una actividad. Devuelve el id. */
export const saveActivity = (v) => rpc('marketing_activity_save', {
  p_id: v.id ?? null,
  p_activity_date: v.activity_date || null,
  p_channel: v.channel || 'otro',
  p_kind: v.kind || 'otro',
  p_lead: v.lead_id || null,
  p_org: v.organization_id || null,
  p_subject: v.subject,
  p_outcome: v.outcome || 'pendiente',
  p_notes: v.notes || null,
});

/** Registrar o actualizar un material. */
export const saveMaterial = (v) => rpc('marketing_material_save', {
  p_id: v.id ?? null,
  p_title: v.title,
  p_channel: v.channel || 'otro',
  p_status: v.status || 'idea',
  p_due_date: v.due_date || null,
  p_published_on: v.published_on || null,
  p_notes: v.notes || null,
  p_owner: v.owner_id || null,
});
