/**
 * SOFA · Arranque de la aplicación (index.html)
 * Login → Supabase Auth → perfil → organización → permisos → aplicación.
 */
import { APP_VERSION } from './version.js';
import { CONFIG } from './config.js';
import { sb, configProblem } from './supabase.js';
import { getSession, loadContext, pickMembership, rememberMembership, signOut, watchAuth, startInactivityTimer } from './auth.js';
import { resolve, parseHash, DEFAULT_ROUTE } from './router.js';
import { visibleNav, ROLES, homeRoute } from './utils/permissions.js';
import { html, render, raw, $, $$ } from './utils/dom.js';
import { toast, friendlyError, errorView, emptyView } from './utils/ui.js';
import { initials } from './utils/formatters.js';

const app = document.getElementById('app');
const state = { session: null, profile: null, memberships: [], membership: null, role: null, operatorId: null };

function fatal(title, text, actions = '') {
  render(app, html`<div class="auth-wrap"><div class="auth-card" role="alert">
    <div class="logo"><img class="logo-full" src="assets/brand/sofa-logo.png" alt="SOFA · Soluciones de Facturación Médica" width="942" height="321"></div>
    <h1>${title}</h1><p class="lead">${text}</p>${actions}</div></div>`);
}

/**
 * 1.9 · Primer acceso: si el usuario entró con la clave temporal (creada con «Crear usuario»),
 * debe cambiarla antes de usar el sistema. Se carga aparte: si falla, la aplicación sigue arrancando.
 */
async function passwordGate() {
  try {
    const cc = await import('./modules/cambio-clave.js');
    if (!(await cc.needsPasswordChange())) return false;
    render(app, html`<div class="auth-wrap"><div class="auth-card" id="cambioClave"></div></div>`);
    await cc.render($('#cambioClave'), { onDone: () => setTimeout(() => location.reload(), 800) });
    return true;
  } catch (e) { console.warn('cambio-clave', e); return false; }
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
  if (await passwordGate()) return;   // 1.9 · cambio de clave obligatorio en el primer acceso
  // Organización operadora (SOFA) para crear registros del CRM; null para usuarios de clientes
  state.operatorId = (state.memberships.find((m) => m.kind === 'operator') || {}).organization_id || null;
  layout();
  watchAuth();
  startInactivityTimer();
  window.addEventListener('hashchange', route);
  if (!location.hash || (location.hash.replace(/^#\/?/, '') === DEFAULT_ROUTE && homeRoute(state.role) !== DEFAULT_ROUTE)) history.replaceState(null, '', `#/${homeRoute(state.role)}`);
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
      <div class="brand"><img class="logo-full" src="assets/brand/sofa-logo-white.png" alt="SOFA · Soluciones de Facturación Médica" width="942" height="321"></div>
      <div class="nav-search"><label class="sr-only" for="navSearch">Buscar en el menú</label><input id="navSearch" type="search" placeholder="Buscar módulo…" autocomplete="off"></div>
      <nav class="nav nav-v2" id="nav"></nav>
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
  renderNav(); bindNav();
  $('#menuBtn').onclick = () => toggleMenu(true);
  $('#scrim').onclick = () => toggleMenu(false);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { toggleMenu(false); closeUserMenu(); } });
  $('#userBtn').onclick = (e) => { e.stopPropagation(); openUserMenu(); };
  $('#orgSel')?.addEventListener('change', (e) => { rememberMembership(e.target.value); location.reload(); });
  const net = () => { $('#offline').hidden = navigator.onLine; };
  window.addEventListener('online', net); window.addEventListener('offline', net); net();
}

/** 2.0 · Grupos plegables (se recuerdan en este navegador) y búsqueda en el menú. */
const NAV_KEY = 'sofa.nav.cerrados';
const closedGroups = () => { try { return new Set(JSON.parse(localStorage.getItem(NAV_KEY) || '[]')); } catch (_) { return new Set(); } };
const saveClosed = (set) => { try { localStorage.setItem(NAV_KEY, JSON.stringify([...set])); } catch (_) { /* sin almacenamiento: no se recuerda */ } };
const norm = (t) => String(t || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
function renderNav() {
  const nav = $('#nav'); if (!nav) return;
  const { route } = parseHash();
  const q = norm($('#navSearch')?.value).trim();
  const closed = closedGroups();
  const link = (i) => html`<a href="#/${i.route}" ${i.route === route ? raw('aria-current="page"') : ''}>${i.label}${i.ready ? '' : html`<span class="soon" title="Llega en la Iteración ${i.iteration}">It. ${i.iteration}</span>`}</a>`;
  const groups = visibleNav(state.role);
  if (q) {
    const hits = groups.flatMap((g) => g.items.filter((i) => norm(i.label).includes(q) || norm(g.group).includes(q)));
    render(nav, hits.length ? html`<div class="nav-hits">${hits.map(link)}</div>` : html`<p class="nav-empty">No hay módulos con «${$('#navSearch').value}». Borre la búsqueda para ver todo el menú.</p>`);
    return;
  }
  render(nav, html`${groups.map((g) => {
    const active = g.items.some((i) => i.route === route);
    const open = active || !closed.has(g.group);
    return html`<div class="nav-group ${open ? 'open' : ''}">
      <button type="button" class="nav-group-btn" data-group="${g.group}" aria-expanded="${open ? 'true' : 'false'}">${g.group}<span class="nav-count">${g.items.length}</span></button>
      <div class="nav-items" ${open ? '' : raw('hidden')}>${g.items.map(link)}</div></div>`;
  })}`);
}
function bindNav() {
  $('#nav').addEventListener('click', (e) => {
    const b = e.target.closest('.nav-group-btn'); if (!b) return;
    const set = closedGroups(); const g = b.dataset.group;
    if (b.getAttribute('aria-expanded') === 'true') set.add(g); else set.delete(g);
    saveClosed(set); renderNav();
  });
  const s = $('#navSearch');
  s.addEventListener('input', renderNav);
  s.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { const a = $('#nav a'); if (a) { location.hash = a.getAttribute('href'); s.value = ''; } }
    if (e.key === 'Escape') { s.value = ''; renderNav(); }
  });
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
    <a role="menuitem" href="#/perfil">Mi perfil</a><a role="menuitem" href="#/cambio-clave">Cambiar contraseña</a><a role="menuitem" href="#/seguridad">Seguridad (dos pasos)</a><a role="menuitem" href="#/diagnostico">Diagnóstico</a>
    <button role="menuitem" data-out="local">Cerrar sesión</button><button role="menuitem" data-out="global">Cerrar sesión en todos los dispositivos</button>`);
  document.body.appendChild(pop); $('#userBtn').setAttribute('aria-expanded', 'true');
  pop.addEventListener('click', (e) => { const b = e.target.closest('[data-out]'); if (b) signOut('salida', b.dataset.out); else closeUserMenu(); });
  setTimeout(() => document.addEventListener('click', function h(ev) { if (!pop.contains(ev.target)) { closeUserMenu(); document.removeEventListener('click', h); } }), 0);
  pop.querySelector('a').focus();
}

let routeSeq = 0;
async function route() {
  const my = ++routeSeq;
  toggleMenu(false); closeUserMenu(); if ($('#navSearch')) $('#navSearch').value = ''; renderNav();
  const main = $('#main'); const title = $('#pageTitle');
  let r;
  try { r = await resolve(state.role); }
  catch (e) { render(main, errorView(e)); return; }
  if (my !== routeSeq) return;
  const setTitle = (t) => { title.textContent = t; document.title = `${t} · SOFA`; };
  const home = homeRoute(state.role);
  if (r.kind === 'forbidden' && r.def.route === DEFAULT_ROUTE && home !== DEFAULT_ROUTE) { location.replace(`#/${home}`); return; }
  if (r.kind === 'notfound') { setTitle('No encontrado'); render(main, emptyView('Página no encontrada', 'La dirección no existe.', html`<a class="btn primary" href="#/${home}">Ir al inicio</a>`)); return; }
  if (r.kind === 'forbidden') { setTitle(r.def.label); render(main, emptyView('Sin acceso a este módulo', `Tu rol (${ROLES[state.role]?.name}) no incluye "${r.def.label}". Si lo necesitas, pide al Super Admin que revise tus permisos.`, html`<a class="btn" href="#/${home}">Volver al inicio</a>`)); return; }
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
