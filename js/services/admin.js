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
/** 4.7.0 (SEG-29) · La fila completa (meta de ingresos, costo por hora, datos bancarios…) solo la entrega app_settings_staff() al personal.
 *  Si la migración 176 todavía no está aplicada (función inexistente), se lee como antes. */
export async function getSettings() {
  const r = await sb().rpc('app_settings_staff');
  if (!r.error) return (r.data || [])[0] || null;
  if (r.error.code === 'PGRST202' || r.error.code === '42883') return must(await sb().from('app_settings').select('*').limit(1).maybeSingle());
  throw r.error;
}
/** Solo lo que necesita cualquier usuario (plazos y texto de la normativa de glosas). */
export async function getPublicSettings() {
  const r = await sb().rpc('app_settings_public');
  if (!r.error) return r.data || null;
  if (r.error.code === 'PGRST202' || r.error.code === '42883') return must(await sb().from('app_settings').select('glosa_norm_reference, payment_term_days, alert_days').limit(1).maybeSingle());
  throw r.error;
}
export async function updateSettings(operatorId, values) {
  must(await sb().from('app_settings').update(values).eq('operator_id', operatorId));   // sin .select(): las columnas sensibles no se devuelven por la API
  return getSettings();
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

// ---- Reinicio de datos (Super Admin) y validación de usuarios y roles
export async function dataResetPreview(scopes) { return must(await sb().rpc('data_reset_preview', { p_scopes: scopes })); }
export async function dataReset(scopes, reason, confirm, resetFolios) {
  return must(await sb().rpc('data_reset', { p_scopes: scopes, p_reason: reason, p_confirm: confirm, p_reset_folios: !!resetFolios }));
}
/** Borra de Storage los archivos de los documentos eliminados (por bucket, en lotes de 100). Devuelve cuántos se borraron y los que fallaron. */
export async function removeStorageFiles(files) {
  const byBucket = {}; for (const f of files || []) (byBucket[f.bucket] = byBucket[f.bucket] || []).push(f.path);
  let removed = 0; const failed = [];
  for (const [bucket, paths] of Object.entries(byBucket)) {
    for (let i = 0; i < paths.length; i += 100) {
      const chunk = paths.slice(i, i + 100);
      const { error } = await sb().storage.from(bucket).remove(chunk);
      if (error) failed.push(...chunk.map((p) => `${bucket}/${p}`)); else removed += chunk.length;
    }
  }
  return { removed, failed };
}
export async function usersRolesReport() { return must(await sb().rpc('users_roles_report')); }

/** 2.? · "Ver como" (modo soporte, solo lectura): auditoría solo interna de SOFA */
export async function supportViewStart(orgId, targetUserId = null) { return must(await sb().rpc('support_view_start', { p_org: orgId, p_target_user: targetUserId })); }
export async function supportViewEnd(sessionId) { return must(await sb().rpc('support_view_end', { p_session: sessionId })); }
/** 31/10/2026 · Si quedó una sesión de "Ver como" sin cerrar (pestaña cerrada sin pulsar «Salir»),
 *  esto permite que la pantalla la detecte al entrar de nuevo —en cualquier dispositivo— y avise,
 *  en vez de dejar a la cuenta viendo un solo consultorio sin ninguna explicación en pantalla. */
export async function supportViewActive() {
  const { data, error } = await sb().rpc('support_view_active');
  if (error) return null;
  return data?.[0] || null;
}
