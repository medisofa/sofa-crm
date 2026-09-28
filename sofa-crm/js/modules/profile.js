/** SOFA · Mi perfil: datos, contraseña y sesiones */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, busy, fieldError, loadInto } from '../utils/ui.js';
import { getProfile, updateProfile } from '../services/admin.js';
import { passwordProblem, isPhone } from '../utils/validation.js';
import { signOut } from '../auth.js';
import { dateTime } from '../utils/formatters.js';

export async function render(main, ctx) {
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Mi perfil</h2><p>${ctx.session.user.email}</p></div></div>
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
