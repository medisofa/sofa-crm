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
