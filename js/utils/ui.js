/** SOFA · Estados de interfaz: carga, vacío, error, reintento, avisos y confirmaciones */
import { html, render, raw } from './dom.js';
import { logDiag } from './diag-log.js';

export function toast(message, kind = '') {
  let host = document.querySelector('.toasts');
  if (!host) { host = document.createElement('div'); host.className = 'toasts'; host.setAttribute('aria-live', 'polite'); document.body.appendChild(host); }
  const el = document.createElement('div');
  el.className = `toast ${kind}`; el.textContent = message;
  host.appendChild(el);
  setTimeout(() => el.remove(), kind === 'bad' ? 6500 : 4000);
}

/** Traduce errores de Supabase/PostgREST/red a mensajes comprensibles.
 *  5.35.8 · El mensaje redactado en la base siempre gana sobre el genérico. Antes, un error
 *  42501 lanzado por una RPC con un texto específico («Solo el Super Admin puede editar el
 *  tarifario») se perdía detrás de un genérico «No tienes permiso para esta acción». Ahora,
 *  si la base mandó un mensaje en español ya redactado, se usa tal cual. Si no, se cae al
 *  mensaje genérico por código. */
export function friendlyError(err) {
  const e = err || {};
  const msg = String(e.message || e.error_description || e.msg || e || '').trim();
  const code = String(e.code || e.status || '');
  // Red / infraestructura
  if (/dynamically imported module|error loading dynamically|importing a module script/i.test(msg))
    return 'No se pudo descargar esta pantalla. Recarga la página y vuelve a entrar. Si vuelve a pasar, avísanos: el archivo de esta pantalla no está llegando.';
  if (!navigator.onLine) return 'Sin conexión a internet. Revisa tu conexión y vuelve a intentar.';
  if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) return 'No se pudo conectar con el servidor. Puede ser tu conexión o una caída momentánea. Espera unos segundos y vuelve a intentar.';
  if (/aborted|AbortError/i.test(msg)) return 'Operación cancelada.';
  // Autenticación
  if (/invalid login credentials|invalid_credentials/i.test(msg)) return 'Correo o contraseña incorrectos.';
  if (/email not confirmed/i.test(msg)) return 'Tu correo aún no está confirmado. Pide al administrador que lo confirme.';
  if (/rate limit|too many/i.test(msg) || code === '429') return 'Demasiados intentos. Espera unos minutos y vuelve a intentar.';
  if (code === 'PGRST301' || /jwt expired|invalid jwt|session.*(missing|expired)/i.test(msg)) return 'Tu sesión expiró. Inicia sesión de nuevo.';
  if (/debe iniciar sesión|not authenticated|not_authenticated/i.test(msg)) return 'Debes iniciar sesión para hacer esta acción.';
  // Base de datos — infraestructura
  if (code === '57014' || /statement timeout|canceling statement due to statement timeout/i.test(msg))
    return 'La consulta tomó demasiado tiempo y se canceló. Intenta de nuevo con un filtro más estrecho o avísanos si vuelve a pasar.';
  if (code === '42883' || /function .* does not exist/i.test(msg))
    return 'La acción que intentaste usar todavía no está disponible en esta versión. Avísanos: puede faltar una migración.';
  if (code === '53200' || /out of memory/i.test(msg))
    return 'La operación consumió demasiada memoria. Intenta con un rango más pequeño.';
  // Negocio — si el mensaje viene redactado desde la base, usarlo tal cual (regla de oro)
  const esRedactado = looksLikeBusinessMessage(msg);
  if (code === '42501') {
    if (esRedactado) return msg;
    if (/permission denied|row-level security/i.test(msg)) return 'No tienes permiso para esta acción.';
    return 'No tienes permiso para esta acción.';
  }
  if (code === '23505') { return esRedactado ? msg : 'Ya existe un registro con esos datos.'; }
  if (code === '23503') { return esRedactado ? msg : 'No se puede guardar: hay un dato relacionado que no existe o fue eliminado.'; }
  if (code === '23514' || code === '22023' || code === 'P0002' || code === 'SOFA') return msg;
  // Contraseñas
  if (/same.*password|different from the old/i.test(msg)) return 'La nueva contraseña debe ser distinta de la anterior.';
  if (/password/i.test(msg) && /weak|short|at least/i.test(msg)) return 'La contraseña es muy débil. Usa al menos 10 caracteres con letras y números.';
  // Cualquier otro mensaje redactado en español que venga de la base
  if (esRedactado) return msg;
  return msg ? `Ocurrió un error: ${msg}` : 'Ocurrió un error inesperado.';
}

/** Detección simple de mensaje de negocio en español ya redactado en la base.
 *  Criterios: tiene al menos 10 caracteres, contiene espacio o puntuación (no es un
 *  identificador bare), no parece una traza de código PostgreSQL ni inglés técnico. */
function looksLikeBusinessMessage(msg) {
  if (!msg || msg.length < 10) return false;
  // Técnicos: tablas/columnas/pg_*/context lines
  if (/\b(pg_|CONTEXT|LINE \d+|STATEMENT|HINT|ERROR:|FATAL|column|relation|function)\b/i.test(msg)) return false;
  // Inglés evidente
  if (/\b(permission denied|does not exist|duplicate key|invalid input|null value|violates)\b/i.test(msg)) return false;
  // Español evidente (artículos y verbos comunes)
  return /\b(el|la|los|las|un|una|de|del|al|no|sin|con|para|por|debe|puede|falta|faltan|existe|hay|aún|solo|solo el|ya)\b/i.test(msg);
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
  if (!el.getAttribute('aria-live')) el.setAttribute('aria-live', 'polite');
  render(el, loadingView());
  try {
    const data = await fetcher();
    render(el, isEmpty(data) ? empty() : view(data));
    return data;
  } catch (err) {
    console.error(err);
    logDiag('error', null, friendlyError(err), { code: err?.code || err?.status || null, raw: String(err?.message || err) });
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
    const tid = `dlg-${++seq}`;
    d.className = 'dlg'; d.setAttribute('aria-labelledby', tid);
    render(d, html`<div class="dh" id="${tid}">${title}</div><div class="db">${text}</div><div class="df"><button class="btn" value="no">Cancelar</button><button class="btn ${danger ? 'danger' : 'primary'}" value="ok">${okLabel}</button></div>`);
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

/** Opción de <select> segura */
export const opt = (value, label, selected) => html`<option value="${value}" ${String(value) === String(selected ?? '') ? raw('selected') : ''}>${label ?? value}</option>`;

/**
 * Formulario en un <dialog> accesible. onSubmit(datos, form) puede lanzar un error:
 * se muestra dentro del diálogo sin cerrarlo. Devuelve el valor de onSubmit o null si se cancela.
 */
export function formDialog({ title, body, submitLabel = 'Guardar', wide = false, onSubmit, onOpen }) {
  return new Promise((resolve) => {
    const d = document.createElement('dialog');
    d.className = 'dlg'; if (wide) d.style.width = 'min(720px, 96vw)';
    const tid = `dlg-${++seq}`;
    d.setAttribute('aria-labelledby', tid);
    render(d, html`<form novalidate><div class="dh" id="${tid}">${title}</div><div class="db form-body">${body}<div class="fd-msg" aria-live="assertive"></div></div>
      <div class="df"><button type="button" class="btn" data-cancel>Cancelar</button><button type="submit" class="btn primary">${submitLabel}</button></div></form>`);
    document.body.appendChild(d);
    const form = d.querySelector('form');
    let result = null;
    d.querySelector('[data-cancel]').addEventListener('click', () => d.close());
    d.addEventListener('close', () => { d.remove(); resolve(result); });
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const data = Object.fromEntries(new FormData(form).entries());
      form.querySelectorAll('input[type=checkbox][name]').forEach((c) => { data[c.name] = c.checked; });
      const msg = d.querySelector('.fd-msg');
      await busy(e.submitter || form.querySelector('[type=submit]'), async () => {
        try { result = await onSubmit(data, form); if (result !== undefined && result !== false) d.close(); }
        catch (err) { console.warn(err); render(msg, html`<div class="note bad" role="alert">${friendlyError(err)}</div>`); }
      });
    });
    d.showModal();
    onOpen?.(form, d);
    form.querySelector('input:not([type=hidden]),select,textarea')?.focus();
  });
}

/** Valida campos obligatorios de un formulario de diálogo; devuelve true si todo está bien */
export function requireFields(form, names) {
  let ok = true;
  names.forEach((n) => { const i = form.elements[n]; if (!i) return; const bad = !String(i.value || '').trim(); fieldError(i, bad ? 'Campo obligatorio.' : null); if (bad) ok = false; });
  return ok;
}
