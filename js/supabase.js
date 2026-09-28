/**
 * SOFA · Cliente de Supabase (supabase-js 2.117.2, copia local en /vendor).
 * La librería se sirve desde el propio repositorio: no depende de un CDN
 * externo y la versión queda fija.
 */
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

let client = null;
/** Cliente único de Supabase (null si la configuración no es válida). */
export function sb() {
  if (client) return client;
  if (configProblem()) return null;
  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    throw new Error('No se cargó la librería de Supabase (vendor/supabase-js).');
  }
  client = window.supabase.createClient(projectUrl(), publishableKey(), {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: 'sofa-auth' },
    global: { headers: { 'x-sofa-client': `web/${CONFIG.APP_VERSION}` } }
  });
  return client;
}
