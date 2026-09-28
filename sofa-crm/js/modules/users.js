/** SOFA · Usuarios y roles (la asignación se hace desde SQL hasta el módulo de invitaciones) */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, confirmDialog, busy } from '../utils/ui.js';
import { listMemberships, setUserActive } from '../services/admin.js';
import { can } from '../utils/permissions.js';
import { date } from '../utils/formatters.js';

export async function render(main, ctx) {
  const canToggle = can('users.toggle', ctx.role);
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Usuarios y roles</h2><p>Quién tiene acceso, a qué organización y con qué rol.</p></div></div>
    <div class="note">Para agregar un usuario: créalo en Supabase (<b>Authentication › Users › Add user</b>, con Auto Confirm) y asígnale el rol en el SQL Editor con <code>select app.grant_role('correo', 'rol');</code>. La invitación desde esta pantalla llega en una iteración posterior, porque requiere una Edge Function con clave privada en el servidor.</div>
    <div id="l"></div>`);
  const box = $('#l', main);
  const load = () => loadInto(box, listMemberships, (rows) => html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Usuario</th><th>Organización</th><th>Rol</th><th>Desde</th><th>Estado</th>${canToggle ? html`<th></th>` : ''}</tr></thead>
    <tbody>${rows.sort((a, b) => (a.roles?.sort_order || 9) - (b.roles?.sort_order || 9)).map((m) => {
      const active = m.is_active && m.profiles?.is_active !== false;
      const self = m.user_id === ctx.session.user.id;
      return html`<tr>
        <td data-l="Usuario"><b>${m.profiles?.full_name || '—'}</b>${self ? html` <span class="pill info">Tú</span>` : ''}<div class="small muted">${m.profiles?.phone || ''}</div></td>
        <td data-l="Organización">${m.organizations?.legal_name || '—'}</td>
        <td data-l="Rol">${m.roles?.name || m.role_code}</td>
        <td data-l="Desde">${date(m.created_at)}</td>
        <td data-l="Estado">${active ? html`<span class="pill ok">Activo</span>` : html`<span class="pill">Inactivo</span>`}</td>
        ${canToggle ? html`<td data-l="">${self ? '' : html`<button class="btn sm ${active ? 'danger' : ''}" data-user="${m.user_id}" data-active="${active ? '0' : '1'}" data-name="${m.profiles?.full_name || ''}">${active ? 'Desactivar' : 'Activar'}</button>`}</td>` : ''}</tr>`;
    })}</tbody></table></div>`, { empty: () => emptyView('Sin usuarios visibles') });
  box.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-user]'); if (!b) return;
    const activate = b.dataset.active === '1';
    const ok = await confirmDialog(activate ? 'Activar usuario' : 'Desactivar usuario',
      activate ? `${b.dataset.name} podrá volver a entrar a SOFA.` : `${b.dataset.name} no podrá ver ni modificar datos desde este momento. Sus registros y su historial se conservan.`,
      activate ? 'Activar' : 'Desactivar', !activate);
    if (!ok) return;
    await busy(b, async () => {
      try { await setUserActive(b.dataset.user, activate); toast(activate ? 'Usuario activado' : 'Usuario desactivado', 'ok'); load(); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });
  load();
}
