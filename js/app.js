/**
 * SOFA · Arranque de la aplicación (index.html)
 * Login → Supabase Auth → perfil → organización → permisos → aplicación.
 */
import { APP_VERSION } from './version.js';
import { CONFIG } from './config.js';
import { sb, configProblem } from './supabase.js';
import { getSession, loadContext, pickMembership, rememberMembership, signOut, watchAuth, startInactivityTimer } from './auth.js';
import { resolve, parseHash, DEFAULT_ROUTE } from './router.js';
import { visibleNav, ROLES } from './utils/permissions.js';
import { html, render, raw, $, $$ } from './utils/dom.js';
import { toast, friendlyError, errorView, emptyView } from './utils/ui.js';
import { initials } from './utils/formatters.js';

const app = document.getElementById('app');
const state = { session: null, profile: null, memberships: [], membership: null, role: null, operatorId: null };

function fatal(title, text, actions = '') {
  render(app, html`<div class="auth-wrap"><div class="auth-card" role="alert">
    <div class="logo"><img src="assets/icons/icon-192.png" alt=""><div><b>SOFA</b><span>Soluciones de Facturación Médica</span></div></div>
    <h1>${title}</h1><p class="lead">${text}</p>${actions}</div></div>`);
}

async function boot() {
  const problem = configProblem();
  if (problem) { fatal('Configuración pendiente', problem, html`<p class="small muted">Edita <b>js/config.js</b> en el repositorio con la Project URL y la Publishable key (paso 7 de la Iteración 2).</p>`); return; }

  try { state.session = await getSession(); }
  catch (e) { fatal('No se pudo iniciar', friendlyError(e), html`<button class="btn primary" id="rt">Reintentar</button>`); $('#rt').onclick = () => location.reload(); return; }
  if (!state.session) { location.replace('login.html'); return; }

  let ctx;
  try { ctx = await loadContext(); }
  catch (e) {
    if (/expired|jwt/i.test(String(e?.message)) || e?.code === 'PGRST301') { signOut('sesion'); return; }
    fatal('No se pudo cargar tu perfil', friendlyError(e), html`<button class="btn primary" id="rt">Reintentar</button> <button class="btn" id="out">Cerrar sesión</button>`);
    $('#rt').onclick = () => location.reload(); $('#out').onclick = () => signOut('salida'); return;
  }
  if (!ctx || ctx.is_active === false) {
    fatal('Usuario desactivado', 'Tu usuario está desactivado. Si crees que es un error, contacta al administrador de SOFA.', html`<button class="btn primary" id="out">Cerrar sesión</button>`);
    $('#out').onclick = () => signOut('sin-acceso'); return;
  }
  state.profile = ctx; state.memberships = ctx.memberships || [];
  state.membership = pickMembership(ctx);
  if (!state.membership) {
    fatal('Aún no tienes un rol asignado', `Tu usuario (${state.session.user.email}) existe, pero todavía no tiene organización ni rol. Pide al Super Admin que te lo asigne.`, html`<button class="btn primary" id="out">Cerrar sesión</button>`);
    $('#out').onclick = () => signOut('sin-acceso'); return;
  }
  state.role = state.membership.role;
  // Organización operadora (SOFA) para crear registros del CRM; null para usuarios de clientes
  state.operatorId = (state.memberships.find((m) => m.kind === 'operator') || {}).organization_id || null;
  layout();
  watchAuth();
  startInactivityTimer();
  window.addEventListener('hashchange', route);
  if (!location.hash) history.replaceState(null, '', `#/${DEFAULT_ROUTE}`);
  route();
  registerSW();
}

function layout() {
  const name = state.profile.full_name || state.session.user.email;
  const multi = state.memberships.length > 1;
  render(app, html`
  <a class="skip" href="#main">Saltar al contenido</a>
  <div class="app">
    <aside class="sidebar" id="sidebar" aria-label="Menú principal">
      <div class="brand"><img src="assets/icons/icon-192.png" alt=""><div><b>SOFA</b><small>Soluciones de Facturación Médica</small></div></div>
      <nav class="nav" id="nav"></nav>
      <div class="side-foot">v${APP_VERSION} · ${ROLES[state.role]?.name || state.role}</div>
    </aside>
    <div class="scrim" id="scrim"></div>
    <div style="min-width:0;display:flex;flex-direction:column">
      <header class="topbar">
        <button class="menu-btn" id="menuBtn" aria-label="Abrir menú" aria-controls="sidebar" aria-expanded="false">☰</button>
        <h1 id="pageTitle">SOFA</h1>
        ${multi ? html`<label class="sr-only" for="orgSel">Organización activa</label><select class="org-select" id="orgSel">${state.memberships.map((m) => html`<option value="${m.organization_id}" ${m.organization_id === state.membership.organization_id ? raw('selected') : ''}>${m.organization} · ${m.role_name}</option>`)}</select>`
                : html`<span class="org-chip" title="${state.membership.organization}">${state.membership.organization}</span>`}
        <button class="user-btn" id="userBtn" aria-haspopup="menu" aria-expanded="false"><span class="avatar" aria-hidden="true">${initials(name)}</span><span class="nm">${name}</span></button>
      </header>
      <div class="banner offline" id="offline" hidden role="status">Sin conexión. Los cambios no se guardarán hasta que vuelva internet.</div>
      <main class="page" id="main" tabindex="-1"></main>
    </div>
  </div>`);
  renderNav();
  $('#menuBtn').onclick = () => toggleMenu(true);
  $('#scrim').onclick = () => toggleMenu(false);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { toggleMenu(false); closeUserMenu(); } });
  $('#userBtn').onclick = (e) => { e.stopPropagation(); openUserMenu(); };
  $('#orgSel')?.addEventListener('change', (e) => { rememberMembership(e.target.value); location.reload(); });
  const net = () => { $('#offline').hidden = navigator.onLine; };
  window.addEventListener('online', net); window.addEventListener('offline', net); net();
}

function renderNav() {
  const { route } = parseHash();
  render($('#nav'), html`${visibleNav(state.role).map((g) => html`<h6>${g.group}</h6>${g.items.map((i) => html`
    <a href="#/${i.route}" ${i.route === route ? raw('aria-current="page"') : ''}>${i.label}${i.ready ? '' : html`<span class="soon" title="Llega en la Iteración ${i.iteration}">It. ${i.iteration}</span>`}</a>`)}`)}`);
}
function toggleMenu(open) {
  $('#sidebar')?.classList.toggle('open', open); $('#scrim')?.classList.toggle('show', open);
  $('#menuBtn')?.setAttribute('aria-expanded', String(open));
}
function closeUserMenu() { $('.menu-pop')?.remove(); $('#userBtn')?.setAttribute('aria-expanded', 'false'); }
function openUserMenu() {
  if ($('.menu-pop')) { closeUserMenu(); return; }
  const pop = document.createElement('div');
  pop.className = 'menu-pop'; pop.setAttribute('role', 'menu');
  render(pop, html`<div class="who"><b>${state.profile.full_name || '—'}</b><span>${state.session.user.email}</span><br><span>${state.membership.role_name} · ${state.membership.organization}</span></div>
    <a role="menuitem" href="#/perfil">Mi perfil</a><a role="menuitem" href="#/diagnostico">Diagnóstico</a>
    <button role="menuitem" data-out="local">Cerrar sesión</button><button role="menuitem" data-out="global">Cerrar sesión en todos los dispositivos</button>`);
  document.body.appendChild(pop); $('#userBtn').setAttribute('aria-expanded', 'true');
  pop.addEventListener('click', (e) => { const b = e.target.closest('[data-out]'); if (b) signOut('salida', b.dataset.out); else closeUserMenu(); });
  setTimeout(() => document.addEventListener('click', function h(ev) { if (!pop.contains(ev.target)) { closeUserMenu(); document.removeEventListener('click', h); } }), 0);
  pop.querySelector('a').focus();
}

let routeSeq = 0;
async function route() {
  const my = ++routeSeq;
  toggleMenu(false); closeUserMenu(); renderNav();
  const main = $('#main'); const title = $('#pageTitle');
  let r;
  try { r = await resolve(state.role); }
  catch (e) { render(main, errorView(e)); return; }
  if (my !== routeSeq) return;
  const setTitle = (t) => { title.textContent = t; document.title = `${t} · SOFA`; };
  if (r.kind === 'notfound') { setTitle('No encontrado'); render(main, emptyView('Página no encontrada', 'La dirección no existe.', html`<a class="btn primary" href="#/${DEFAULT_ROUTE}">Ir al inicio</a>`)); return; }
  if (r.kind === 'forbidden') { setTitle(r.def.label); render(main, emptyView('Sin acceso a este módulo', `Tu rol (${ROLES[state.role]?.name}) no incluye "${r.def.label}". Si lo necesitas, pide al Super Admin que revise tus permisos.`, html`<a class="btn" href="#/${DEFAULT_ROUTE}">Volver al inicio</a>`)); return; }
  setTitle(r.def.label);
  const ctx = { ...state, def: r.def, arg: r.arg, setTitle, sb: sb() };
  try { await r.mod.render(main, ctx); }
  catch (e) { console.error(e); render(main, errorView(e)); }
  if (my === routeSeq) main.focus({ preventScroll: true });
}

function registerSW() {
  if (!('serviceWorker' in navigator) || location.protocol !== 'https:') return;
  navigator.serviceWorker.register('sw.js').then((reg) => {
    reg.addEventListener('updatefound', () => {
      const w = reg.installing;
      w?.addEventListener('statechange', () => { if (w.state === 'installed' && navigator.serviceWorker.controller) toast('Hay una versión nueva de SOFA. Recarga la página para usarla.'); });
    });
  }).catch((e) => console.warn('SW', e));
}

boot();
