/**
 * SOFA · Cliente de Supabase (supabase-js 2.117.2, copia local en /vendor).
 * La librería se sirve desde el propio repositorio: no depende de un CDN
 * externo y la versión queda fija.
 */
import { CONFIG } from './config.js';

/** Devuelve un texto con el problema de configuración, o null si está bien. */
export function configProblem() {
  const url = CONFIG.SUPABASE_URL || '';
  const key = CONFIG.SUPABASE_PUBLISHABLE_KEY || '';
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url) || url.includes('TU-PROYECTO')) {
    return 'Falta la URL del proyecto de Supabase en js/config.js.';
  }
  if (!key || key.includes('REEMPLAZAR')) return 'Falta la clave publicable de Supabase en js/config.js.';
  if (key.startsWith('sb_secret_')) return 'PELIGRO: js/config.js contiene una Secret key. Bórrala de inmediato, rótala en Supabase y usa la clave publicable (sb_publishable_...).';
  const parts = key.split('.');
  if (parts.length === 3) {
    try {
      const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
      if (payload.role === 'service_role') return 'PELIGRO: js/config.js contiene la clave service_role. Bórrala de inmediato, rótala en Supabase y usa la clave publicable.';
    } catch { /* no es un JWT legible: se valida abajo */ }
  } else if (!key.startsWith('sb_publishable_')) {
    return 'La clave de js/config.js no parece una clave publicable de Supabase (sb_publishable_...).';
  }
  return null;
}

let client = null;
/** Cliente único de Supabase (null si la configuración no es válida). */
export function sb() {
  if (client) return client;
  if (configProblem()) return null;
  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    throw new Error('No se cargó la librería de Supabase (vendor/supabase-js).');
  }
  client = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: 'sofa-auth' },
    global: { headers: { 'x-sofa-client': `web/${CONFIG.APP_VERSION}` } }
  });
  return client;
}
