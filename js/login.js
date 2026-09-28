/**
 * SOFA · Pantalla de acceso (login.html)
 * Modos: iniciar sesión · recuperar contraseña · definir nueva contraseña.
 */
import { CONFIG } from './config.js';
import { sb, configProblem } from './supabase.js';
import { html, render, $ } from './utils/dom.js';
import { friendlyError, busy, fieldError } from './utils/ui.js';
import { isEmail, passwordProblem } from './utils/validation.js';

// Se lee ANTES de iniciar Supabase, que limpia el hash del enlace de recuperación
const HASH = new URLSearchParams(location.hash.replace(/^#/, ''));
const IS_RECOVERY = HASH.get('type') === 'recovery';
const LINK_ERROR = HASH.get('error_description');
const REASON = new URLSearchParams(location.search).get('motivo');
const REASONS = {
  inactividad: ['info', 'Tu sesión se cerró por inactividad. Vuelve a entrar para continuar.'],
  sesion: ['info', 'Tu sesión terminó. Inicia sesión de nuevo.'],
  salida: ['ok', 'Cerraste sesión correctamente.'],
  'sin-acceso': ['warn', 'Tu usuario no tiene acceso activo a SOFA.']
};

const card = document.getElementById('card');
const shell = (body) => html`<div class="logo"><img src="assets/icons/icon-192.png" alt=""><div><b>SOFA</b><span>Soluciones de Facturación Médica</span></div></div>${body}<p class="auth-foot">v${CONFIG.APP_VERSION} · Acceso exclusivo para personal y clientes autorizados</p>`;
const note = (kind, text) => html`<div class="note ${kind}" role="status">${text}</div>`;
const pwField = (id, label, auto) => html`<div class="field"><label for="${id}">${label}</label><div class="pw-wrap"><input id="${id}" type="password" autocomplete="${auto}" required minlength="10"><button type="button" data-toggle="${id}" aria-label="Mostrar contraseña">Ver</button></div></div>`;

function bindToggles() {
  card.querySelectorAll('[data-toggle]').forEach((b) => b.addEventListener('click', () => {
    const i = document.getElementById(b.dataset.toggle); const show = i.type === 'password';
    i.type = show ? 'text' : 'password'; b.textContent = show ? 'Ocultar' : 'Ver'; b.setAttribute('aria-label', show ? 'Ocultar contraseña' : 'Mostrar contraseña');
  }));
}

function loginView(message) {
  render(card, shell(html`
    <h1>Iniciar sesión</h1><p class="lead">Entra con el correo y la contraseña que te asignó SOFA.</p>
    ${message || ''}
    <form id="f" novalidate>
      <div class="field"><label for="email">Correo electrónico</label><input id="email" type="email" autocomplete="username" inputmode="email" required></div>
      ${pwField('password', 'Contraseña', 'current-password')}
      <div id="msg" aria-live="assertive"></div>
      <button class="btn primary block" type="submit">Entrar</button>
    </form>
    <p style="text-align:center;margin:14px 0 0"><button class="btn link" id="forgot" type="button">¿Olvidaste tu contraseña?</button></p>`));
  bindToggles();
  $('#email').focus();
  $('#forgot').onclick = () => forgotView($('#email').value);
  $('#f').onsubmit = async (e) => {
    e.preventDefault();
    const email = $('#email'), pw = $('#password');
    fieldError(email, isEmail(email.value) ? null : 'Escribe un correo válido.');
    fieldError(pw, pw.value ? null : 'Escribe tu contraseña.');
    if (!isEmail(email.value) || !pw.value) return;
    await busy(e.submitter || $('#f button[type=submit]'), async () => {
      const { error } = await sb().auth.signInWithPassword({ email: email.value.trim(), password: pw.value });
      if (error) { render($('#msg'), note('bad', friendlyError(error))); pw.select(); return; }
      location.replace('index.html');
    });
  };
}

function forgotView(prefill = '') {
  render(card, shell(html`
    <h1>Recuperar contraseña</h1><p class="lead">Te enviaremos un enlace para crear una contraseña nueva.</p>
    <form id="f" novalidate>
      <div class="field"><label for="email">Correo electrónico</label><input id="email" type="email" autocomplete="username" required value="${prefill}"></div>
      <div id="msg" aria-live="assertive"></div>
      <button class="btn primary block" type="submit">Enviar enlace</button>
    </form>
    <p style="text-align:center;margin:14px 0 0"><button class="btn link" id="back" type="button">Volver a iniciar sesión</button></p>`));
  $('#email').focus();
  $('#back').onclick = () => loginView();
  $('#f').onsubmit = async (e) => {
    e.preventDefault();
    const email = $('#email');
    if (!isEmail(email.value)) { fieldError(email, 'Escribe un correo válido.'); return; }
    fieldError(email, null);
    await busy(e.submitter || $('#f button[type=submit]'), async () => {
      const redirectTo = new URL('login.html', location.href).href.split('#')[0].split('?')[0];
      const { error } = await sb().auth.resetPasswordForEmail(email.value.trim(), { redirectTo });
      // Mismo mensaje exista o no el correo (evita revelar quién tiene cuenta)
      if (error && !/rate|too many/i.test(error.message)) console.warn(error);
      render($('#msg'), error && /rate|too many/i.test(error.message)
        ? note('warn', friendlyError(error))
        : note('ok', 'Si el correo está registrado, recibirás un enlace en unos minutos. Revisa también la carpeta de spam.'));
    });
  };
}

function resetView() {
  render(card, shell(html`
    <h1>Crear contraseña nueva</h1><p class="lead">Usa al menos 10 caracteres, combinando letras y números.</p>
    <form id="f" novalidate>
      ${pwField('p1', 'Contraseña nueva', 'new-password')}
      ${pwField('p2', 'Repite la contraseña', 'new-password')}
      <div id="msg" aria-live="assertive"></div>
      <button class="btn primary block" type="submit">Guardar contraseña</button>
    </form>`));
  bindToggles();
  $('#p1').focus();
  $('#f').onsubmit = async (e) => {
    e.preventDefault();
    const p1 = $('#p1'), p2 = $('#p2');
    const prob = passwordProblem(p1.value);
    fieldError(p1, prob); fieldError(p2, !prob && p1.value !== p2.value ? 'Las contraseñas no coinciden.' : null);
    if (prob || p1.value !== p2.value) return;
    await busy(e.submitter || $('#f button[type=submit]'), async () => {
      const { error } = await sb().auth.updateUser({ password: p1.value });
      if (error) { render($('#msg'), note('bad', friendlyError(error))); return; }
      history.replaceState(null, '', 'login.html');
      render($('#msg'), note('ok', 'Contraseña actualizada. Entrando…'));
      setTimeout(() => location.replace('index.html'), 900);
    });
  };
}

async function start() {
  const problem = configProblem();
  if (problem) { render(card, shell(html`<h1>Configuración pendiente</h1>${note('warn', problem)}`)); return; }
  if (LINK_ERROR) { loginView(note('warn', /expired|invalid/i.test(LINK_ERROR) ? 'El enlace expiró o ya se usó. Solicita uno nuevo con "¿Olvidaste tu contraseña?".' : LINK_ERROR)); return; }
  const client = sb();
  if (IS_RECOVERY) {
    render(card, shell(html`<p class="lead">Validando el enlace…</p>`));
    let done = false;
    client.auth.onAuthStateChange((event) => { if (event === 'PASSWORD_RECOVERY' && !done) { done = true; resetView(); } });
    const { data } = await client.auth.getSession();
    if (data.session && !done) { done = true; resetView(); }
    setTimeout(() => { if (!done) loginView(note('warn', 'No se pudo validar el enlace. Solicita uno nuevo.')); }, 6000);
    return;
  }
  const { data } = await client.auth.getSession();
  if (data.session) { location.replace('index.html'); return; }
  const r = REASONS[REASON];
  loginView(r ? note(r[0], r[1]) : '');
}
start().catch((e) => render(card, shell(html`<h1>No se pudo iniciar</h1>${note('bad', friendlyError(e))}`)));
