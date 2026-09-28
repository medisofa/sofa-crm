/** SOFA · Estados de interfaz: carga, vacío, error, reintento, avisos y confirmaciones */
import { html, render, raw } from './dom.js';

export function toast(message, kind = '') {
  let host = document.querySelector('.toasts');
  if (!host) { host = document.createElement('div'); host.className = 'toasts'; host.setAttribute('aria-live', 'polite'); document.body.appendChild(host); }
  const el = document.createElement('div');
  el.className = `toast ${kind}`; el.textContent = message;
  host.appendChild(el);
  setTimeout(() => el.remove(), kind === 'bad' ? 6500 : 4000);
}

/** Traduce errores de Supabase/PostgREST/red a mensajes comprensibles */
export function friendlyError(err) {
  const e = err || {};
  const msg = String(e.message || e.error_description || e.msg || e || '');
  const code = String(e.code || e.status || '');
  if (!navigator.onLine || /Failed to fetch|NetworkError|Load failed/i.test(msg)) return 'Sin conexión a internet. Revisa tu conexión y vuelve a intentar.';
  if (/invalid login credentials|invalid_credentials/i.test(msg)) return 'Correo o contraseña incorrectos.';
  if (/email not confirmed/i.test(msg)) return 'Tu correo aún no está confirmado. Pide al administrador que lo confirme.';
  if (/rate limit|too many/i.test(msg) || code === '429') return 'Demasiados intentos. Espera unos minutos y vuelve a intentar.';
  if (code === 'PGRST301' || /jwt expired|invalid jwt|session.*(missing|expired)/i.test(msg)) return 'Tu sesión expiró. Inicia sesión de nuevo.';
  if (code === '42501' || /permission denied|row-level security/i.test(msg)) return 'No tienes permiso para esta acción.';
  if (code === '23505') return 'Ya existe un registro con esos datos.';
  if (code === '23514' || code === '22023' || code === 'P0002') return msg; // mensajes de negocio escritos en español en la base de datos
  if (/same.*password|different from the old/i.test(msg)) return 'La nueva contraseña debe ser distinta de la anterior.';
  if (/password/i.test(msg) && /weak|short|at least/i.test(msg)) return 'La contraseña es muy débil. Usa al menos 10 caracteres con letras y números.';
  return msg ? `Ocurrió un error: ${msg}` : 'Ocurrió un error inesperado.';
}

export const loadingView = (rows = 4) => html`<div aria-busy="true" aria-label="Cargando">${raw('<div class="skeleton"></div>'.repeat(rows))}</div>`;
export const emptyView = (title, text = '', action = '') => html`<div class="state"><div class="ico" aria-hidden="true">○</div><h3>${title}</h3>${text ? html`<p>${text}</p>` : ''}${action}</div>`;
export const errorView = (err, retryId) => html`<div class="state" role="alert"><div class="ico" aria-hidden="true">!</div><h3>No se pudo cargar</h3><p>${friendlyError(err)}</p>${retryId ? html`<button class="btn" data-retry="${retryId}">Reintentar</button>` : ''}</div>`;

let seq = 0;
/**
 * Carga datos en un contenedor manejando loading / vacío / error / reintento.
 * fetcher: async () => datos ; view: (datos) => html`` ; isEmpty opcional.
 */
export async function loadInto(el, fetcher, view, { isEmpty = (d) => Array.isArray(d) && d.length === 0, empty = () => emptyView('Sin registros', 'No hay información para mostrar.') } = {}) {
  const id = `r${++seq}`;
  render(el, loadingView());
  try {
    const data = await fetcher();
    render(el, isEmpty(data) ? empty() : view(data));
    return data;
  } catch (err) {
    console.error(err);
    render(el, errorView(err, id));
    el.querySelector(`[data-retry="${id}"]`)?.addEventListener('click', () => loadInto(el, fetcher, view, { isEmpty, empty }));
    return null;
  }
}

/** Ejecuta una acción con el botón en estado ocupado */
export async function busy(btn, fn) {
  if (!btn || btn.getAttribute('aria-busy') === 'true') return;
  const label = btn.innerHTML;
  btn.setAttribute('aria-busy', 'true'); btn.disabled = true;
  btn.innerHTML = '<span class="spinner" aria-hidden="true"></span> Procesando…';
  try { return await fn(); } finally { btn.removeAttribute('aria-busy'); btn.disabled = false; btn.innerHTML = label; }
}

/** Confirmación accesible con <dialog>. Devuelve true/false. */
export function confirmDialog(title, text, okLabel = 'Confirmar', danger = false) {
  return new Promise((resolve) => {
    const d = document.createElement('dialog');
    d.className = 'dlg'; d.setAttribute('aria-labelledby', 'dlgT');
    render(d, html`<div class="dh" id="dlgT">${title}</div><div class="db">${text}</div><div class="df"><button class="btn" value="no">Cancelar</button><button class="btn ${danger ? 'danger' : 'primary'}" value="ok">${okLabel}</button></div>`);
    document.body.appendChild(d);
    d.addEventListener('click', (e) => { const v = e.target.closest('button')?.value; if (v) { d.close(v); } });
    d.addEventListener('close', () => { resolve(d.returnValue === 'ok'); d.remove(); });
    d.showModal();
    d.querySelector('button[value="no"]').focus();
  });
}

/** Muestra u oculta el error de un campo de formulario */
export function fieldError(input, message) {
  const field = input.closest('.field'); if (!field) return;
  let e = field.querySelector('.err');
  if (!message) { e?.remove(); input.removeAttribute('aria-invalid'); return; }
  if (!e) { e = document.createElement('div'); e.className = 'err'; e.id = `${input.id}-err`; field.appendChild(e); }
  e.textContent = message; input.setAttribute('aria-invalid', 'true'); input.setAttribute('aria-describedby', e.id);
}
