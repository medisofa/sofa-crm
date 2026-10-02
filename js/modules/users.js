/** SOFA · Usuarios y roles: invitaciones, cambio de rol, activación y revisión periódica de accesos */
import { html, render as paint, $ } from '../utils/dom.js';
import { emptyView, toast, friendlyError, confirmDialog, busy, formDialog, opt, requireFields, fieldError } from '../utils/ui.js';
import { listMemberships, setUserActive, usersOverview, adminUsers } from '../services/admin.js';
import { clientOptions } from '../services/bi.js';
import { downloadCsv } from '../utils/filters.js';
import { can, ROLES } from '../utils/permissions.js';
import { date, dateTime, todayISO } from '../utils/formatters.js';
import { isEmail } from '../utils/validation.js';
import { capturerScopes, providersOfOrg, setCapturerScope } from '../services/claims.js';

const ORG_ROLES = ['client', 'capturer'];   // roles de la organización del cliente (no SOFA)

const STATUS = { activo: ['Activo', 'ok'], 'invitación pendiente': ['Invitación pendiente', 'warn'], 'sin ingreso en 90 días': ['Sin ingreso en 90 días', 'warn'], desactivado: ['Desactivado', ''] };
const f = (name, label, input, hint = '') => html`<div class="field"><label for="f_${name}">${label}</label>${input}${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`;

const SOFA_ROLES = ['super_admin', 'admin', 'operations', 'billing', 'glosas', 'assistant', 'auditor'];
const roleOpts = (ctx, sel) => html`<optgroup label="Equipo SOFA">${SOFA_ROLES.filter((k) => ctx.role === 'super_admin' || k !== 'super_admin').map((k) => opt(k, ROLES[k].name, sel))}</optgroup>
  <optgroup label="Consultorio del cliente">${ORG_ROLES.map((k) => opt(k, ROLES[k].name, sel))}</optgroup>`;

/**
 * Invitar o cambiar el rol. Médico y Secretaria pertenecen a la organización del cliente;
 * a la Secretaria se le marcan aquí mismo los médicos que atiende (mínimo privilegio).
 */
async function roleDialog(ctx, preset = {}) {
  const clients = await clientOptions().catch(() => []);
  const invite = !preset.email;
  let provs = [];
  return formDialog({
    title: invite ? (preset.role === 'client' ? 'Invitar médico' : preset.role === 'capturer' ? 'Invitar secretaria' : 'Invitar usuario') : `Cambiar rol · ${preset.email}`,
    submitLabel: invite ? 'Enviar invitación' : 'Guardar rol', wide: true,
    body: html`<div class="form-grid">
      ${invite ? html`${f('email', 'Correo *', html`<input id="f_email" name="email" type="email" required autocomplete="off">`)}
        ${f('full_name', 'Nombre completo *', html`<input id="f_full_name" name="full_name" required maxlength="120">`)}` : ''}
      ${f('role', 'Rol *', html`<select id="f_role" name="role">${roleOpts(ctx, preset.role || 'billing')}</select>`)}
      ${f('org', 'Consultorio o clínica (cliente) *', html`<select id="f_org" name="org"><option value="">Seleccione…</option>${clients.map((c) => opt(c.id, c.legal_name, preset.orgId))}</select>`)}
      </div>
      <p class="small" id="f_rdesc" aria-live="polite"></p>
      <fieldset id="f_provs" style="border:0;padding:0;display:none"><legend class="small" style="font-weight:600">Médicos que atiende esta secretaria *</legend><div id="f_plist" class="list"></div></fieldset>
      ${invite ? html`<p class="small muted">La persona recibe un correo para crear su contraseña. Si el correo ya tiene usuario, solo se le asigna el rol.</p>` : ''}`,
    onOpen: (form) => {
      const sync = async () => {
        const r = form.elements.role.value; const orgRole = ORG_ROLES.includes(r);
        form.elements.org.disabled = !orgRole; form.elements.org.closest('.field').style.display = orgRole ? '' : 'none';   // [hidden] no basta: .field fija display
        form.querySelector('#f_rdesc').textContent = ROLES[r]?.desc || '';
        const box = form.querySelector('#f_provs'); box.style.display = r === 'capturer' ? '' : 'none';
        if (r === 'capturer' && form.elements.org.value) {
          provs = await providersOfOrg(form.elements.org.value).catch(() => []);
          const current = preset.userId ? await capturerScopes(preset.userId).catch(() => []) : [];
          paint(form.querySelector('#f_plist'), provs.length ? html`${provs.map((p) => html`<label class="li" style="cursor:pointer"><input type="checkbox" name="pv_${p.id}" ${current.includes(p.id) || provs.length === 1 ? 'checked' : ''}><div class="b"><div class="t1">${p.full_name}</div></div></label>`)}`
            : html`<p class="small muted">Este cliente todavía no tiene médicos registrados. Agrégalos en su ficha antes de invitar a la secretaria.</p>`);
        } else if (r === 'capturer') paint(form.querySelector('#f_plist'), html`<p class="small muted">Elige primero el consultorio.</p>`);
      };
      form.elements.role.addEventListener('change', sync); form.elements.org.addEventListener('change', sync); sync();
    },
    onSubmit: async (d, form) => {
      if (invite) {
        if (!requireFields(form, ['email', 'full_name'])) return false;
        if (!isEmail(d.email)) { fieldError(form.elements.email, 'Correo inválido.'); return false; }
      }
      if (ORG_ROLES.includes(d.role) && !form.elements.org.value) { fieldError(form.elements.org, 'Elige el consultorio o clínica.'); return false; }
      const chosen = d.role === 'capturer' ? provs.filter((p) => d[`pv_${p.id}`]).map((p) => p.id) : [];
      if (d.role === 'capturer' && !chosen.length) { toast('Marca al menos un médico para la secretaria', 'bad'); return false; }
      const r = await adminUsers({ action: invite ? 'invite' : 'grant', email: invite ? d.email.trim() : preset.email, full_name: d.full_name || '', role: d.role, organization_id: ORG_ROLES.includes(d.role) ? form.elements.org.value : null });
      if (d.role === 'capturer' && r?.user_id) await setCapturerScope(r.user_id, chosen);
      return r;
    }
  });
}

export async function render(main, ctx) {
  const manage = can('users.invite', ctx.role); const canToggle = can('users.toggle', ctx.role);
  let rows = []; let filter = '';
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Usuarios y roles</h2><p>Quién tiene acceso, con qué rol y cuándo entró por última vez. Revísalo cada trimestre y desactiva lo que ya no se usa.</p></div>
      <div class="toolbar" style="margin:0">${manage ? html`<button class="btn primary" id="invite">+ Invitar usuario</button><button class="btn" id="inviteMed">+ Médico</button><button class="btn" id="inviteSec">+ Secretaria</button>` : ''}<button class="btn" id="csv">Exportar revisión de accesos</button></div></div>
    <div class="tabs" id="kinds" role="group" aria-label="Tipo de usuario" style="margin-bottom:6px"></div>
    <div class="tabs" id="tabs" role="group" aria-label="Estado"></div><div id="l"></div>`);
  let kind = '';
  const KINDS = [['', 'Todos'], ['sofa', 'Equipo SOFA'], ['client', 'Médicos'], ['capturer', 'Secretarias']];
  const ofKind = (r) => (!kind ? true : kind === 'sofa' ? !ORG_ROLES.includes(r.role_code) : r.role_code === kind);
  const drawKinds = () => paint($('#kinds', main), html`${KINDS.map(([k, l]) => html`<button data-k="${k}" aria-pressed="${kind === k}">${l}${k ? ` · ${rows.filter((r) => (k === 'sofa' ? !ORG_ROLES.includes(r.role_code) : r.role_code === k)).length}` : ''}</button>`)}`);
  const tabs = [['', 'Todos'], ['activo', 'Activos'], ['invitación pendiente', 'Invitación pendiente'], ['sin ingreso en 90 días', 'Sin ingreso en 90 días'], ['desactivado', 'Desactivados']];
  const drawTabs = () => paint($('#tabs', main), html`${tabs.map(([k, l]) => html`<button data-s="${k}" aria-pressed="${filter === k}">${l}${k ? ` · ${rows.filter((r) => r.status === k).length}` : ''}</button>`)}`);
  const box = $('#l', main);
  const draw = () => {
    const list = (filter ? rows.filter((r) => r.status === filter) : rows).filter(ofKind);
    if (!list.length) { paint(box, emptyView('Sin usuarios en este filtro')); return; }
    paint(box, html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Usuario</th><th>Rol</th><th>Organización</th><th>Estado</th><th>Último ingreso</th>${manage || canToggle ? html`<th></th>` : ''}</tr></thead>
      <tbody>${list.map((u) => {
        const self = u.user_id === ctx.session.user.id; const [sl, sc] = STATUS[u.status] || [u.status, ''];
        const protectedRow = u.role_code === 'super_admin' && ctx.role !== 'super_admin';
        return html`<tr>
          <td data-l="Usuario"><b>${u.full_name || '—'}</b>${self ? html` <span class="pill info">Tú</span>` : ''}<div class="small muted">${u.email}</div></td>
          <td data-l="Rol">${u.role_name}</td><td data-l="Organización">${u.organization}</td>
          <td data-l="Estado"><span class="pill ${sc}">${sl}</span><div class="small muted">Invitado ${date(u.invited_at)}</div></td>
          <td data-l="Último ingreso">${u.last_sign_in_at ? dateTime(u.last_sign_in_at) : '—'}</td>
          ${manage || canToggle ? html`<td data-l="">${self || protectedRow ? '' : html`
            ${manage && u.email ? html`<button class="btn sm" data-act="grant" data-email="${u.email}" data-role="${u.role_code}" data-user="${u.user_id}" data-org="${u.kind === 'client' ? u.organization_id : ''}">Cambiar rol</button>
              ${u.role_code === 'capturer' && can('capturers.assign', ctx.role) ? html`<button class="btn sm" data-act="scope" data-user="${u.user_id}" data-org="${u.organization_id}" data-name="${u.full_name || u.email}">Médicos asignados</button>` : ''}
              <button class="btn sm" data-act="resend" data-email="${u.email}">${u.status === 'invitación pendiente' ? 'Reenviar invitación' : 'Enviar acceso'}</button>` : ''}
            ${canToggle ? html`<button class="btn sm ${u.is_active ? 'danger' : ''}" data-act="toggle" data-user="${u.user_id}" data-active="${u.is_active ? '0' : '1'}" data-name="${u.full_name || u.email}">${u.is_active ? 'Desactivar' : 'Activar'}</button>` : ''}`}</td>` : ''}</tr>`;
      })}</tbody></table></div>`);
  };
  const load = async () => {
    try { rows = await usersOverview(); }
    catch (err) {
      // Sin el script 022: lista básica, sin correos ni último ingreso
      const basic = await listMemberships().catch(() => []);
      rows = basic.map((m) => ({ user_id: m.user_id, email: '', full_name: m.profiles?.full_name, role_code: m.role_code, role_name: m.roles?.name, organization_id: m.organization_id, organization: m.organizations?.legal_name, kind: m.organizations?.kind, is_active: m.is_active && m.profiles?.is_active !== false, invited_at: m.created_at, last_sign_in_at: null, status: m.is_active ? 'activo' : 'desactivado' }));
      toast(`Revisión de accesos no disponible: ${friendlyError(err)}`);
    }
    drawKinds(); drawTabs(); draw();
  };
  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-s]'); if (b) { filter = b.dataset.s; drawTabs(); draw(); } });
  $('#kinds', main).addEventListener('click', (e) => { const b = e.target.closest('[data-k]'); if (b) { kind = b.dataset.k; drawKinds(); draw(); } });
  const invitePreset = async (role) => { try { const r = await roleDialog(ctx, { role }); if (r) { toast(r.message, 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } };
  $('#inviteMed', main)?.addEventListener('click', () => invitePreset('client'));
  $('#inviteSec', main)?.addEventListener('click', () => invitePreset('capturer'));
  $('#invite', main)?.addEventListener('click', async () => { try { const r = await roleDialog(ctx); if (r) { toast(r.message, 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
  $('#csv', main).addEventListener('click', () => downloadCsv(`sofa-revision-accesos-${todayISO()}.csv`, ['Nombre', 'Correo', 'Rol', 'Organización', 'Estado', 'Invitado', 'Último ingreso'],
    rows.map((u) => [u.full_name, u.email, u.role_name, u.organization, u.status, String(u.invited_at || '').slice(0, 10), String(u.last_sign_in_at || '').slice(0, 16).replace('T', ' ')])));
  box.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-act]'); if (!b) return;
    try {
      if (b.dataset.act === 'grant') { const r = await roleDialog(ctx, { email: b.dataset.email, role: b.dataset.role, orgId: b.dataset.org, userId: b.dataset.user }); if (r) { toast(r.message, 'ok'); load(); } return; }
      if (b.dataset.act === 'scope') { if (await scopeDialog(b.dataset.user, b.dataset.org, b.dataset.name)) { toast('Médicos asignados actualizados', 'ok'); load(); } return; }
      if (b.dataset.act === 'resend') { await busy(b, async () => { const r = await adminUsers({ action: 'resend', email: b.dataset.email }); toast(r.message, 'ok'); }); return; }
      const activate = b.dataset.active === '1';
      if (!(await confirmDialog(activate ? 'Activar usuario' : 'Desactivar usuario', activate ? `${b.dataset.name} podrá volver a entrar a SOFA.` : `${b.dataset.name} no podrá ver ni modificar datos desde este momento. Sus registros y su historial se conservan.`, activate ? 'Activar' : 'Desactivar', !activate))) return;
      await setUserActive(b.dataset.user, activate); toast(activate ? 'Usuario activado' : 'Usuario desactivado', 'ok'); load();
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
}

/** D3 · Capturador: solo ve y registra reclamaciones de los médicos asignados aquí (mínimo privilegio, aplicado también por RLS) */
async function scopeDialog(userId, orgId, name) {
  const [provs, current] = await Promise.all([providersOfOrg(orgId), capturerScopes(userId)]);
  return formDialog({
    title: `Médicos asignados · ${name}`, submitLabel: 'Guardar asignación',
    body: provs.length ? html`<p class="small">La secretaria solo podrá registrar y consultar reclamaciones de los médicos marcados. Nunca verá pagos, honorarios ni información de otros médicos.</p>
      <div class="list">${provs.map((p) => html`<label class="li" style="cursor:pointer"><input type="checkbox" name="p_${p.id}" ${current.includes(p.id) ? 'checked' : ''}><div class="b"><div class="t1">${p.full_name}</div></div></label>`)}</div>`
      : emptyView('Sin médicos', 'Este cliente no tiene médicos activos registrados.'),
    onSubmit: async (d) => { const ids = provs.filter((p) => d[`p_${p.id}`]).map((p) => p.id); await setCapturerScope(userId, ids); return true; }
  });
}

/** Invitar Médico o Secretaria desde la ficha del cliente (consultorio ya elegido) */
export async function inviteToClient(ctx, role, orgId) { return roleDialog(ctx, { role, orgId }); }
