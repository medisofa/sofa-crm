/** SOFA · Registro de diagnóstico, de alcance global y permanente en todas las pantallas.
 *  Guarda en la base de datos (tabla app_diagnostics_log) quién estaba, con qué rol, con qué
 *  nivel de verificación (aal1/aal2) y en qué pantalla, cuando algo falló o se vio raro — así el
 *  Súper Admin puede ver qué pasó en el dispositivo de un cliente sin pedirle capturas de pantalla.
 *  Nunca bloquea la interfaz: si el guardado falla (sin red, sin sesión), se ignora en silencio.
 *  Solo el propio Súper Admin puede LEER este registro (ver migración app_diagnostics_log: RLS). */
import { sb } from '../supabase.js';

let ctx = { userId: null, email: null, role: null, orgId: null, aal: null, route: '' };

export function setDiagContext({ userId, email, role, orgId, aal }) {
  ctx = { ...ctx, userId, email, role, orgId, aal };
}
export function setDiagRoute(route) { ctx.route = route; }

/** event_type: 'info' | 'error' | 'rls_empty' (una pantalla devolvió menos de lo esperado) */
export function logDiag(eventType, tableName, message, details) {
  if (!ctx.userId) return;
  try {
    sb().from('app_diagnostics_log').insert({
      user_id: ctx.userId, email: ctx.email, role_code: ctx.role, organization_id: ctx.orgId, aal: ctx.aal,
      route: ctx.route, event_type: eventType, table_name: tableName || null,
      message: String(message || '').slice(0, 500), details: details ?? null
    }).then(() => {}, () => {});
  } catch (_) { /* nunca debe romper la pantalla que lo llama */ }
}
