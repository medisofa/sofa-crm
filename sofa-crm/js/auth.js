/**
 * SOFA · Autenticación con Supabase Auth.
 * Flujo: sesión → my_context() (perfil, organizaciones y roles desde la base
 * de datos) → membresía activa → permisos de pantalla.
 * Nunca se guardan contraseñas ni roles en el navegador: el rol se lee de
 * PostgreSQL en cada carga y RLS lo vuelve a verificar en cada consulta.
 */
import { sb } from './supabase.js';
import { CONFIG } from './config.js';
import { toast } from './utils/ui.js';

export async function getSession() {
  const { data, error } = await sb().auth.getSession();
  if (error) throw error;
  return data.session;
}

export async function loadContext() {
  const { data, error } = await sb().rpc('my_context');
  if (error) throw error;
  return data; // { user_id, full_name, is_active, memberships:[{organization_id, organization, kind, role, role_name}] }
}

const ORG_KEY = 'sofa-org-activa'; // preferencia de interfaz (no es un control de seguridad)
export function pickMembership(ctx) {
  const ms = (ctx?.memberships || []).filter((m) => m && m.role);
  if (!ms.length) return null;
  let pref = null;
  try { pref = sessionStorage.getItem(ORG_KEY); } catch { /* sin almacenamiento */ }
  return ms.find((m) => m.organization_id === pref) || ms.find((m) => m.kind === 'operator') || ms[0];
}
export function rememberMembership(orgId) { try { sessionStorage.setItem(ORG_KEY, orgId); } catch { /* sin almacenamiento */ } }

let leaving = false;
/** Cierra sesión y vuelve al login. scope: 'local' | 'global' (todos los dispositivos) */
export async function signOut(reason = 'salida', scope = 'local') {
  if (leaving) return; leaving = true;
  try { await sb()?.auth.signOut({ scope }); } catch (e) { console.warn('signOut', e); }
  try { sessionStorage.removeItem(ORG_KEY); } catch { /* sin almacenamiento */ }
  location.replace(`login.html?motivo=${encodeURIComponent(reason)}`);
}

/** Si la sesión termina en otra pestaña o expira, vuelve al login */
export function watchAuth() {
  sb().auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT' || (event === 'TOKEN_REFRESHED' && !session)) {
      if (!leaving) { leaving = true; location.replace('login.html?motivo=sesion'); }
    }
  });
}

/** Cierre de sesión por inactividad, con aviso un minuto antes */
export function startInactivityTimer() {
  const limit = Math.max(5, CONFIG.INACTIVITY_MINUTES) * 60 * 1000;
  let warnT, outT;
  const reset = () => {
    clearTimeout(warnT); clearTimeout(outT);
    warnT = setTimeout(() => toast('Por seguridad, tu sesión se cerrará en 1 minuto por inactividad.'), limit - 60000);
    outT = setTimeout(() => signOut('inactividad'), limit);
  };
  let last = 0;
  const onAct = () => { const now = Date.now(); if (now - last > 5000) { last = now; reset(); } };
  ['pointerdown', 'keydown', 'scroll', 'touchstart'].forEach((ev) => window.addEventListener(ev, onAct, { passive: true }));
  document.addEventListener('visibilitychange', () => { if (!document.hidden) onAct(); });
  reset();
}
