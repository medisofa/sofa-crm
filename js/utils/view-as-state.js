/**
 * SOFA · Bandera compartida de "Ver como" (modo soporte, solo lectura).
 * app.js la actualiza al entrar/salir; cualquier utilidad puede importarla
 * para bloquear exportar/imprimir sin tener que importar app.js (evita
 * dependencias circulares, ya que app.js importa muchos módulos).
 *
 * pii(val) — envuelve un valor en <span class="pii"> cuando el modo soporte
 * está activo, para que CSS pueda difuminarlo sin tocar la lógica de negocio.
 * Devuelve siempre un nodo DOM; úsalo donde ya se usa h() o como hijo de html``.
 *
 * Ejemplo con sistema antiguo (h):
 *   { label: 'Cédula', get: (r) => pii(r.cedula || '—') }
 * Ejemplo con sistema nuevo (html``):
 *   html`<td>${pii(r.name)}</td>`
 */
export const viewAsState = { active: false };

/**
 * Devuelve un <span class="pii"> con el texto cuando el modo soporte está activo,
 * o un TextNode con el valor en caso contrario, para no añadir nodos innecesarios.
 * @param {string|number|null|undefined} val
 * @returns {HTMLSpanElement|Text}
 */
export function pii(val) {
  const text = val == null || val === '' ? '—' : String(val);
  if (!viewAsState.active) return document.createTextNode(text);
  const s = document.createElement('span');
  s.className = 'pii';
  s.textContent = text;
  return s;
}
