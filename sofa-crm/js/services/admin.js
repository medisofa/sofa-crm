/** SOFA · Administración: usuarios, parámetros, perfil y plan de 90 días */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };

export async function listMemberships() {
  return must(await sb().from('organization_users')
    .select('organization_id, user_id, role_code, is_active, created_at, profiles(full_name, phone, is_active), organizations(legal_name, kind), roles(name, sort_order)')
    .order('created_at'));
}
export async function setUserActive(userId, active) {
  return must(await sb().rpc('set_user_active', { p_user: userId, p_active: active }));
}
export async function getSettings() {
  return must(await sb().from('app_settings').select('*').limit(1).maybeSingle());
}
export async function updateSettings(operatorId, values) {
  return must(await sb().from('app_settings').update(values).eq('operator_id', operatorId).select().single());
}
export async function getProfile(userId) {
  return must(await sb().from('profiles').select('id, full_name, phone, is_active, created_at').eq('id', userId).single());
}
export async function updateProfile(userId, values) {
  return must(await sb().from('profiles').update(values).eq('id', userId).select('id, full_name, phone').single());
}
export async function listMilestones() {
  return must(await sb().from('plan_milestones').select('id, week_no, title, due_on, done_on').order('week_no').order('title'));
}
export async function setMilestoneDone(id, done) {
  return must(await sb().from('plan_milestones').update({ done_on: done ? new Date().toISOString().slice(0, 10) : null }).eq('id', id).select('id, done_on').single());
}

/** Revisión de accesos: correo, estado y último ingreso (Admin, Super Admin y Auditor) */
export async function usersOverview() { return must(await sb().rpc('users_overview')); }

/**
 * Llama a la Edge Function "admin-users" (invitar, reenviar, cambiar rol).
 * La clave de servicio vive en Supabase; aquí solo viaja la sesión del usuario.
 */
export async function adminUsers(payload) {
  const { data, error } = await sb().functions.invoke('admin-users', { body: payload });
  if (error) {
    let msg = error.message || 'Error';
    try { const body = await error.context?.json?.(); if (body?.message) msg = body.message; } catch { /* sin cuerpo */ }
    if (error.context?.status === 404 || /Failed to send a request|not found/i.test(msg)) msg = 'La función admin-users no está publicada en Supabase (Iteración 10, paso 3 de la guía).';
    throw Object.assign(new Error(msg), { code: 'SOFA' });
  }
  if (data && data.ok === false) throw Object.assign(new Error(data.message || 'No se pudo completar'), { code: 'SOFA' });
  return data;
}
