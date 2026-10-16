/** SOFA · 4.7.0 · Dos pasos al entrar (SEG-05, parte de pantalla). Falla cerrado: si no se puede comprobar, no se entra.
 *  1) Si la cuenta tiene un factor TOTP verificado y esta sesión todavía es aal1, se pide el código (aal2) antes de cargar nada.
 *  2) Si el personal de SOFA no tiene factor y el Super Admin encendió «exigir dos pasos» (app_settings.require_staff_mfa),
 *     se le guía para inscribirlo antes de entrar.
 *  Se usa desde js/app.js: ambas funciones devuelven true cuando ya dibujaron una pantalla y el arranque debe detenerse. */
import { supabase, h, note } from '../services/iter18.js';
import { mfaState, verifyStep, render as seguridad } from './seguridad.js';
import { isStaff } from '../utils/permissions.js';

const card = (...kids) => h('div', { class: 'auth-wrap' }, h('div', { class: 'auth-card', role: 'region', 'aria-label': 'Verificación en dos pasos' }, ...kids));
const botones = (onSalir, extra) => h('div', { class: 'i18-actions' }, extra || null, h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: onSalir }, 'Cerrar sesión'));

function bloqueo(app, titulo, texto, { onRetry, onSalir }) {
  app.replaceChildren(card(h('h1', {}, titulo), note(texto, 'error'),
    botones(onSalir, h('button', { class: 'i18-btn', type: 'button', onclick: onRetry }, 'Reintentar'))));
}

/** Paso 1 · antes de cargar el perfil: pedir el código si la cuenta tiene factor verificado. */
export async function pedirCodigo(app, { onSalir }) {
  let st;
  try { st = await mfaState(); }
  catch (_) {
    bloqueo(app, 'No se pudo comprobar la verificación en dos pasos', 'Por seguridad no se abre el sistema sin comprobarla. Revise su conexión y pulse «Reintentar»; si sigue igual, avise al Administrador.', { onRetry: () => location.reload(), onSalir });
    return true;
  }
  if (!st.factor || st.current === 'aal2') return false;
  const caja = h('div');
  app.replaceChildren(card(h('h1', {}, 'Verificación en dos pasos'),
    note('Escriba el código de 6 dígitos que muestra su app autenticadora para entrar a SOFA.'), caja, botones(onSalir)));
  verifyStep(caja, st.factor.id, () => setTimeout(() => location.reload(), 400));
  return true;
}

/** Paso 2 · ya con el rol: el personal sin factor debe inscribirlo cuando el servidor lo exige. */
export async function exigirInscripcion(app, role, { onSalir }) {
  if (!isStaff(role)) return false;
  let exige;
  try {
    const { data, error } = await supabase.from('app_settings').select('require_staff_mfa').limit(1).maybeSingle();
    if (error) throw error;
    exige = !!(data && data.require_staff_mfa);
  } catch (_) {
    bloqueo(app, 'No se pudo leer la política de seguridad', 'Por seguridad no se abre el sistema sin comprobarla. Pulse «Reintentar»; si sigue igual, avise al Administrador.', { onRetry: () => location.reload(), onSalir });
    return true;
  }
  if (!exige) return false;
  let st;
  try { st = await mfaState(); }
  catch (_) { bloqueo(app, 'No se pudo comprobar la verificación en dos pasos', 'Pulse «Reintentar»; si sigue igual, avise al Administrador.', { onRetry: () => location.reload(), onSalir }); return true; }
  if (st.factor) return st.current !== 'aal2' ? pedirCodigo(app, { onSalir }) : false;
  const caja = h('div');
  const seguir = h('button', { class: 'i18-btn', type: 'button' }, 'Ya la activé, continuar');
  const msg = h('div', { 'aria-live': 'polite' });
  seguir.addEventListener('click', async () => {
    try { const s = await mfaState(); if (s.factor && s.current === 'aal2') location.reload(); else msg.replaceChildren(note('Todavía falta verificar el código en la sección de arriba. Termine los pasos y vuelva a pulsar «Continuar».', 'error')); }
    catch (e) { msg.replaceChildren(note('No se pudo comprobar. Recargue la página e intente de nuevo.', 'error')); }
  });
  app.replaceChildren(card(h('h1', {}, 'Active la verificación en dos pasos'),
    note('SOFA exige la verificación en dos pasos al personal. Instale una app autenticadora (Google Authenticator, Microsoft Authenticator o Authy), escanee el código QR y escriba el código de 6 dígitos. Solo se hace una vez.'),
    caja, msg, botones(onSalir, seguir)));
  seguridad(caja);
  return true;
}
