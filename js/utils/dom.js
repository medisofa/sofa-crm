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
  // 1.5: si el destino ya no existe (el usuario cambió de pantalla antes de que terminara una carga), no hay nada que pintar
  if (!el) return;
  el.innerHTML = tpl.s;
}
export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

/** Badges de pendientes en el sidebar: {route: count}. Se re-aplican tras cada renderNav. */
const _badges = {};
export function updateSidebarBadges(counts) {
  Object.assign(_badges, counts);
  applySidebarBadges();
}
export function applySidebarBadges() {
  document.querySelectorAll('.nav a[href]').forEach((a) => {
    const route = a.getAttribute('href').replace(/^#\//, '');
    const existing = a.querySelector('.nav-badge');
    const n = _badges[route];
    if (n > 0) {
      if (existing) { existing.textContent = n > 99 ? '99+' : n; existing.hidden = false; }
      else { const b = document.createElement('span'); b.className = 'nav-badge'; b.textContent = n > 99 ? '99+' : n; a.appendChild(b); }
    } else if (existing) { existing.hidden = true; }
  });
}

/** Conecta un input de búsqueda con debounce a un state + load. */
export function debounceSearch(el, st, load, { key = 'q', resetPage = true, delay = 350 } = {}) {
  let t;
  el.addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st[key] = e.target.value; if (resetPage && 'page' in st) st.page = 0; load(); }, delay); });
}
