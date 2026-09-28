/**
 * SOFA · Utilidades de DOM seguras.
 * html`` escapa TODO valor interpolado (defensa contra XSS). Para insertar
 * HTML ya construido y confiable se usa raw() o se anida otro html``.
 */
const MAP = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
export const esc = (v) => (v == null ? '' : String(v).replace(/[&<>"']/g, (c) => MAP[c]));

class SafeHTML { constructor(s) { this.s = s; } toString() { return this.s; } }
export const raw = (s) => new SafeHTML(String(s ?? ''));
const fmt = (v) => {
  if (v instanceof SafeHTML) return v.s;
  if (Array.isArray(v)) return v.map(fmt).join('');
  if (v == null || v === false) return '';
  return esc(v);
};
export function html(strings, ...values) {
  let out = '';
  strings.forEach((s, i) => { out += s + (i < values.length ? fmt(values[i]) : ''); });
  return new SafeHTML(out);
}
/** Inserta una plantilla html`` en un elemento. */
export function render(el, tpl) {
  if (!(tpl instanceof SafeHTML)) throw new Error('render() solo acepta plantillas html``');
  el.innerHTML = tpl.s;
}
export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
