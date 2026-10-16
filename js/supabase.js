/**
 * SOFA · Cliente de Supabase (supabase-js 2.117.2, copia local en /vendor). 4.7.0: sesión en sessionStorage (SEG-22).
 * La librería se sirve desde el propio repositorio: no depende de un CDN
 * externo y la versión queda fija.
 */
import { APP_VERSION } from './version.js';
import { CONFIG } from './config.js';

/**
 * Normaliza la URL del proyecto: quita espacios, barras finales y rutas como
 * /rest/v1 que a veces se copian junto con la URL.
 */
export function projectUrl() {
  let u = String(CONFIG.SUPABASE_URL || '').trim().replace(/^['"]|['"]$/g, '');
  u = u.replace(/\/(rest|auth|storage|realtime)\/v1.*$/i, '').replace(/\/+$/, '');
  return u.toLowerCase();
}
const publishableKey = () => String(CONFIG.SUPABASE_PUBLISHABLE_KEY || '').trim();
const shown = (v) => (v ? `«${v}»` : '(vacío)');

/** Devuelve un texto con el problema de configuración, o null si está bien. */
export function configProblem() {
  const url = projectUrl();
  const key = publishableKey();
  const dash = /supabase\.com\/dashboard\/project\/([a-z0-9]+)/i.exec(url);
  if (dash) return `En js/config.js se pegó la dirección del panel de Supabase ${shown(url)}. La Project URL de tu proyecto es https://${dash[1].toLowerCase()}.supabase.co`;
  if (!url || url.includes('tu-proyecto')) return `Falta la URL del proyecto de Supabase en js/config.js. Valor leído: ${shown(url)}.`;
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url)) return `La URL de js/config.js no tiene el formato https://xxxx.supabase.co. Valor leído: ${shown(url)}.`;
  if (!key || key.includes('REEMPLAZAR')) return 'Falta la clave publicable de Supabase en js/config.js.';
  if (key.startsWith('sb_secret_')) return 'PELIGRO: js/config.js contiene una Secret key. Bórrala de inmediato, rótala en Supabase y usa la clave publicable (sb_publishable_...).';
  const parts = key.split('.');
  if (parts.length === 3) {
    try {
      const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
      if (payload.role === 'service_role') return 'PELIGRO: js/config.js contiene la clave service_role. Bórrala de inmediato, rótala en Supabase y usa la clave publicable.';
    } catch { /* no es un JWT legible */ }
  } else if (!key.startsWith('sb_publishable_')) {
    return `La clave de js/config.js no parece una clave publicable de Supabase (debe empezar con sb_publishable_). Empieza con ${shown(key.slice(0, 15))}.`;
  }
  return null;
}

/**
 * 4.7.0 (SEG-22) · La sesión vive en sessionStorage: se borra al cerrar la pestaña o el navegador (antes quedaba en localStorage).
 * Transición: si la pantalla de ingreso (login.html) todavía la guardó en localStorage, aquí se mueve a sessionStorage una sola vez
 * y se borra de localStorage. Si el navegador no deja usar sessionStorage, la sesión queda en memoria (se pierde al recargar).
 */
const AUTH_KEY = 'sofa-auth';
const memoria = new Map();
export const sesionStorage = {
  getItem(k) {
    try {
      const v = window.sessionStorage.getItem(k);
      if (v != null) return v;
      if (k === AUTH_KEY || k.startsWith(AUTH_KEY + '-')) {   // sesión que dejó el ingreso en localStorage
        const viejo = window.localStorage.getItem(k);
        if (viejo != null) { window.sessionStorage.setItem(k, viejo); window.localStorage.removeItem(k); return viejo; }
      }
      return null;
    } catch (_) { return memoria.has(k) ? memoria.get(k) : null; }
  },
  setItem(k, v) {
    try { window.sessionStorage.setItem(k, v); try { window.localStorage.removeItem(k); } catch (_) { /* sin efecto */ } }
    catch (_) { memoria.set(k, v); }
  },
  removeItem(k) {
    memoria.delete(k);
    try { window.sessionStorage.removeItem(k); } catch (_) { /* sin efecto */ }
    try { window.localStorage.removeItem(k); } catch (_) { /* sin efecto */ }
  }
};

let client = null;
/** Cliente único de Supabase (null si la configuración no es válida). */
export function sb() {
  if (client) return client;
  if (configProblem()) return null;
  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    throw new Error('No se cargó la librería de Supabase (vendor/supabase-js).');
  }
  client = window.supabase.createClient(projectUrl(), publishableKey(), {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: AUTH_KEY, storage: sesionStorage },
    global: { headers: { 'x-sofa-client': `web/${APP_VERSION}` } }
  });
  return client;
}
