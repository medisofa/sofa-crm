/** SOFA · Paleta de comandos (salto rápido de menús).
 *  Abre con Ctrl/⌘+K desde cualquier parte. Busca entre todas las rutas que el rol puede abrir
 *  (por nombre y por familia), se mueve con el teclado y navega con Enter. Muestra «Recientes».
 *
 *  Es infraestructura de interfaz, no una pantalla de ruta. Se inicializa una vez en el arranque
 *  (js/app.js). Los recientes se guardan en localStorage por usuario/rol (estado por visor, igual
 *  que el menú plegado y los favoritos; nunca es dato compartido ni sale del navegador). */
import { html, render, raw } from '../utils/dom.js';

const RECENTS_KEY = 'sofa.palette.recientes';
const MAX_RECENTS = 6;
const norm = (t) => String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/** ¿Es `q` subsecuencia de `t`? (coincidencia difusa: "hcl" ≈ "historia clínica") */
function subseq(q, t) {
  let i = 0;
  for (let n = 0; n < t.length && i < q.length; n++) if (t[n] === q[i]) i++;
  return i === q.length;
}
function score(q, label, group) {
  if (!q) return 0;
  const L = norm(label), G = norm(group);
  if (L.startsWith(q)) return 0;
  const li = L.indexOf(q);
  if (li >= 0) return 1 + li / 1000;
  if (G.includes(q)) return 2;
  if (subseq(q, L)) return 3;
  return Infinity;
}

const STYLE = `
.cmdp-back{position:fixed;inset:0;z-index:10000;background:rgba(15,23,32,.45);display:flex;align-items:flex-start;justify-content:center;padding:10vh 16px 16px}
.cmdp-dialog{width:100%;max-width:560px;background:var(--surface,#fff);color:var(--ink,#1c2733);border:1px solid var(--line,#c9d3dc);border-radius:14px;box-shadow:0 20px 60px rgba(15,23,32,.35);overflow:hidden;display:flex;flex-direction:column;max-height:70vh}
.cmdp-in{border:0;border-bottom:1px solid var(--line,#c9d3dc);padding:15px 16px;font:16px/1.3 inherit;background:transparent;color:inherit;outline:none}
.cmdp-list{list-style:none;margin:0;padding:6px;overflow:auto}
.cmdp-opt{display:flex;gap:10px;align-items:baseline;padding:9px 11px;border-radius:9px;cursor:pointer}
.cmdp-opt[aria-selected=true]{background:var(--az-bg,#eaf2fb)}
.cmdp-opt .lb{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cmdp-opt .fm{font-size:12px;color:var(--ink-2,#5b6b7a);flex:none}
.cmdp-head{font-size:11px;letter-spacing:.04em;text-transform:uppercase;color:var(--ink-2,#5b6b7a);padding:8px 12px 2px}
.cmdp-empty{padding:16px;color:var(--ink-2,#5b6b7a)}
.cmdp-foot{border-top:1px solid var(--line,#c9d3dc);padding:7px 12px;font-size:12px;color:var(--ink-2,#5b6b7a);display:flex;gap:14px;flex-wrap:wrap}
.cmdp-foot kbd{font:inherit;background:var(--surface-2,#eef3f8);border:1px solid var(--line,#c9d3dc);border-radius:5px;padding:0 5px}
@media (prefers-color-scheme:dark){.cmdp-opt[aria-selected=true]{background:rgba(120,170,230,.18)}}
`;

export function initCommandPalette({ items, scopeKey, currentRoute, onNavigate } = {}) {
  if (typeof items !== 'function') throw new Error('initCommandPalette: falta items()');
  const key = typeof scopeKey === 'function' ? scopeKey : (k) => k;
  const goTo = typeof onNavigate === 'function' ? onNavigate : (route) => { location.hash = `#/${route}`; };

  let back = null, input = null, listEl = null;
  let all = [], view = [], active = 0, lastFocus = null, open = false;

  if (!document.getElementById('cmdp-style')) {
    const s = document.createElement('style'); s.id = 'cmdp-style'; s.textContent = STYLE; document.head.appendChild(s);
  }

  const readRecents = () => { try { return JSON.parse(localStorage.getItem(key(RECENTS_KEY)) || '[]'); } catch (_) { return []; } };
  const recordVisit = (route) => {
    if (!route) return;
    try {
      const next = [route, ...readRecents().filter((r) => r !== route)].slice(0, MAX_RECENTS);
      localStorage.setItem(key(RECENTS_KEY), JSON.stringify(next));
    } catch (_) { /* sin almacenamiento: no se recuerdan recientes */ }
  };

  function build() {
    back = document.createElement('div');
    back.className = 'cmdp-back';
    render(back, html`<div class="cmdp-dialog" role="dialog" aria-modal="true" aria-label="Ir a un módulo">
      <input id="cmdpInput" class="cmdp-in" type="text" role="combobox" aria-expanded="true" aria-controls="cmdpList"
        aria-autocomplete="list" autocomplete="off" spellcheck="false" placeholder="Ir a un módulo… escribe su nombre">
      <ul id="cmdpList" class="cmdp-list" role="listbox" aria-label="Módulos"></ul>
      <div class="cmdp-foot"><span><kbd>↑</kbd><kbd>↓</kbd> moverse</span><span><kbd>Enter</kbd> abrir</span><span><kbd>Esc</kbd> cerrar</span></div>
    </div>`);
    input = back.querySelector('#cmdpInput');
    listEl = back.querySelector('#cmdpList');
    back.addEventListener('mousedown', (e) => { if (e.target === back) close(); });
    input.addEventListener('input', () => { active = 0; refresh(); });
    input.addEventListener('keydown', onKey);
    listEl.addEventListener('mousedown', (e) => {
      const li = e.target.closest('[data-i]'); if (!li) return;
      e.preventDefault(); active = Number(li.dataset.i); choose();
    });
    document.body.appendChild(back);
  }

  function compute() {
    const q = norm(input.value).trim();
    if (!q) {
      const byRoute = new Map(all.map((it) => [it.route, it]));
      const rec = readRecents().map((r) => byRoute.get(r)).filter(Boolean).filter((it) => it.route !== currentRoute?.());
      view = rec.length ? rec : all.slice(0, 8);
      return { heading: rec.length ? 'Recientes' : 'Sugerencias' };
    }
    view = all.map((it) => ({ it, s: score(q, it.label, it.group) }))
      .filter((x) => x.s !== Infinity)
      .sort((a, b) => a.s - b.s || a.it.label.length - b.it.label.length)
      .slice(0, 50).map((x) => x.it);
    return { heading: '' };
  }

  function refresh() {
    const { heading } = compute();
    if (active >= view.length) active = Math.max(0, view.length - 1);
    if (!view.length) {
      render(listEl, html`<li class="cmdp-empty" role="option" aria-selected="false">Ningún módulo coincide. Prueba con otra palabra.</li>`);
      input.removeAttribute('aria-activedescendant');
      return;
    }
    render(listEl, html`${heading ? html`<li class="cmdp-head" role="presentation">${heading}</li>` : ''}
      ${view.map((it, i) => html`<li id="cmdp-opt-${i}" class="cmdp-opt" role="option" data-i="${i}" aria-selected="${String(i === active)}">
        <span class="lb">${it.label}</span><span class="fm">${it.group}</span></li>`)}`);
    syncActive();
  }

  function syncActive() {
    const opts = listEl.querySelectorAll('.cmdp-opt');
    opts.forEach((o, i) => o.setAttribute('aria-selected', String(i === active)));
    const cur = listEl.querySelector('#cmdp-opt-' + active);
    if (cur) { input.setAttribute('aria-activedescendant', cur.id); cur.scrollIntoView({ block: 'nearest' }); }
    else input.removeAttribute('aria-activedescendant');
  }

  function move(d) {
    if (!view.length) return;
    active = (active + d + view.length) % view.length;
    syncActive();
  }

  function choose() {
    const it = view[active]; if (!it) return;
    close();
    goTo(it.route);
  }

  function onKey(e) {
    if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
    else if (e.key === 'Enter') { e.preventDefault(); choose(); }
    else if (e.key === 'Escape') { e.preventDefault(); close(); }
    else if (e.key === 'Tab') { e.preventDefault(); } // trampa de foco: se queda en el input
  }

  function show() {
    if (open) return;
    all = (items() || []).filter((it) => it && it.route && it.label);
    if (!back) build();
    lastFocus = document.activeElement;
    open = true;
    back.style.display = 'flex';
    input.value = ''; active = 0; refresh();
    input.focus();
  }
  function close() {
    if (!open) return;
    open = false;
    if (back) back.style.display = 'none';
    if (lastFocus && typeof lastFocus.focus === 'function') lastFocus.focus();
  }
  function toggle() { open ? close() : show(); }

  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && !e.altKey && (e.key === 'k' || e.key === 'K')) { e.preventDefault(); toggle(); }
  });

  return { open: show, close, toggle, recordVisit };
}

export default initCommandPalette;
