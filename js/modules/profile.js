/** SOFA · Mi perfil: datos, contraseña y sesiones */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, busy, fieldError, loadInto } from '../utils/ui.js';
import { getProfile, updateProfile, myRecentProfileChanges, ackProfileChanges } from '../services/admin.js';
import { passwordProblem, isPhone } from '../utils/validation.js';
import { signOut } from '../auth.js';
import { dateTime } from '../utils/formatters.js';

const FIELD_LABEL = { full_name: 'Nombre completo', phone: 'Teléfono' };
const dash = (v) => (v == null || v === '' ? '—' : String(v));

export async function render(main, ctx) {
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Mi perfil</h2><p>${ctx.session.user.email}</p></div></div>
    <div id="pf-aviso"></div>
    <div class="grid two">
      <div class="card"><h2>Datos personales</h2><p class="sub">Tu nombre aparece en el historial y en la auditoría.</p><div id="pf"></div></div>
      <div class="card"><h2>Cambiar contraseña</h2><p class="sub">Al menos 10 caracteres, con letras y números.</p>
        <form id="fp" novalidate>
          <div class="field"><label for="np1">Contraseña nueva</label><input id="np1" type="password" autocomplete="new-password"></div>
          <div class="field"><label for="np2">Repite la contraseña</label><input id="np2" type="password" autocomplete="new-password"></div>
          <button class="btn primary" type="submit">Actualizar contraseña</button>
        </form></div>
      <div class="card"><h2>Accesos</h2><p class="sub">Organizaciones y roles asignados por el Super Admin.</p>
        <div class="list">${ctx.memberships.map((m) => html`<div class="li"><div class="b"><div class="t1">${m.organization}</div><div class="t2">${m.role_name}</div></div>${m.organization_id === ctx.membership.organization_id ? html`<span class="pill ok">Activa</span>` : ''}</div>`)}</div></div>
      <div class="card"><h2>Sesiones</h2><p class="sub">Sesión actual iniciada ${dateTime(ctx.session.user.last_sign_in_at)}.</p>
        <button class="btn danger" id="outAll">Cerrar sesión en todos los dispositivos</button></div>
    </div>`);

  // 5.35.10 · Aviso cuando otra persona (Super Admin) editó tu perfil desde la última vez que lo marcaste como visto.
  (async () => {
    try {
      const data = await myRecentProfileChanges();
      if (!data || !data.pending) return;
      drawAviso($('#pf-aviso', main), data);
    } catch (_) { /* silencioso: el aviso es un extra */ }
  })();

  const pf = $('#pf', main);
  const p = await loadInto(pf, () => getProfile(ctx.session.user.id), (p) => html`<form id="fd" novalidate>
      <div class="field"><label for="fn">Nombre completo</label><input id="fn" value="${p.full_name || ''}" autocomplete="name" maxlength="120"></div>
      <div class="field"><label for="ph">Teléfono</label><input id="ph" value="${p.phone || ''}" autocomplete="tel" inputmode="tel" placeholder="8095551234"></div>
      <button class="btn primary" type="submit">Guardar</button></form>`, { isEmpty: (d) => !d });
  if (p) $('#fd', main).addEventListener('submit', async (e) => {
    e.preventDefault();
    const fn = $('#fn', main), ph = $('#ph', main);
    fieldError(fn, fn.value.trim().length < 3 ? 'Escribe tu nombre completo.' : null);
    fieldError(ph, isPhone(ph.value) ? null : 'Solo números, 10 a 15 dígitos.');
    if (fn.value.trim().length < 3 || !isPhone(ph.value)) return;
    await busy(e.submitter, async () => {
      try { await updateProfile(ctx.session.user.id, { full_name: fn.value.trim(), phone: ph.value.replace(/[\s()-]/g, '') || null }); toast('Datos guardados', 'ok'); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });

  $('#fp', main).addEventListener('submit', async (e) => {
    e.preventDefault();
    const a = $('#np1', main), b = $('#np2', main);
    const prob = passwordProblem(a.value);
    fieldError(a, prob); fieldError(b, !prob && a.value !== b.value ? 'Las contraseñas no coinciden.' : null);
    if (prob || a.value !== b.value) return;
    await busy(e.submitter, async () => {
      const { error } = await ctx.sb.auth.updateUser({ password: a.value });
      if (error) { toast(friendlyError(error), 'bad'); return; }
      a.value = ''; b.value = ''; toast('Contraseña actualizada', 'ok');
    });
  });
  $('#outAll', main).addEventListener('click', () => signOut('salida', 'global'));
}

/** 5.35.10 · Renderiza el aviso de cambios en el perfil hechos por otro usuario.
 *  Un solo botón «Entendido» marca todo como visto (acknowledge). */
function drawAviso(container, data) {
  if (!container || !data || !data.pending) return;
  const entries = data.entries || [];
  const first = entries[0];
  const whoAll = [...new Set(entries.map((e) => e.by_name || 'el equipo de SOFA'))].join(', ');
  paint(container, html`
    <div class="card" style="border-left:4px solid var(--warn,#b8860b);margin-bottom:14px">
      <h3 style="margin-top:0">Un administrador editó tu perfil</h3>
      <p class="sub"><b>${whoAll}</b> cambió tus datos el ${dateTime(first.at)}${entries.length > 1 ? ` (y ${entries.length - 1} cambio${entries.length > 2 ? 's' : ''} más antes)` : ''}.</p>
      <div class="list">${entries.map((e) => html`<div class="li"><div class="b">
        <div class="t2">${dateTime(e.at)} · ${e.by_name || '—'}</div>
        <ul class="small" style="margin:4px 0 0 18px">${Object.entries(e.changes || {}).map(([k, v]) => html`<li>
          <b>${FIELD_LABEL[k] || k}</b>: ${dash(v.from)} → ${dash(v.to)}</li>`)}</ul>
      </div></div>`)}</div>
      <div class="toolbar" style="margin:10px 0 0"><button class="btn" id="pf-aviso-ok" type="button">Entendido</button></div>
    </div>`);
  container.querySelector('#pf-aviso-ok')?.addEventListener('click', async () => {
    try { await ackProfileChanges(); paint(container, html``); }
    catch (err) { toast(friendlyError(err), 'bad'); }
  });
}
