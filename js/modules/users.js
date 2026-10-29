/** SOFA · Usuarios y roles: invitaciones, cambio de rol, activación, restablecer contraseña (2.1) y revisión periódica de accesos */
import { html, render as paint, $ } from '../utils/dom.js';
import { emptyView, toast, friendlyError, confirmDialog, busy, formDialog, opt, requireFields, fieldError } from '../utils/ui.js';
import { listMemberships, setUserActive, usersOverview, adminUsers } from '../services/admin.js';
import { clientOptions } from '../services/bi.js';
import { downloadCsv } from '../utils/filters.js';
import { can, canSee, ROLES } from '../utils/permissions.js';
import { date, dateTime, todayISO } from '../utils/formatters.js';
import { isEmail } from '../utils/validation.js';
import { capturerScopes, providersOfOrg, setCapturerScope, assistantScopes, setAssistantScope } from '../services/claims.js';
import { invoke, rpc, supabase } from '../services/iter18.js';
import { groupUserAccounts, matchesAccount, resolveAccountAction, mergeCapturerScope } from '../utils/user-accounts.js';

const ORG_ROLES = ['client', 'capturer', 'asistente'];   // roles de la organización del cliente (no SOFA)
const SCOPED_ROLES = ['capturer', 'asistente'];   // roles que se asignan por médico, no por consultorio completo

const STATUS = { activo: ['Activo', 'ok'], 'invitación pendiente': ['Invitación pendiente', 'warn'], 'sin ingreso en 90 días': ['Sin ingreso en 90 días', 'warn'], desactivado: ['Desactivado', ''] };
const READINESS = { ready: ['Listo para operar', 'ok'], email_pending: ['Correo pendiente', 'warn'], profile_inactive: ['Perfil desactivado', 'bad'], no_membership: ['Sin membresía', 'bad'], membership_inactive: ['Membresía desactivada', 'bad'], invalid_role: ['Rol inválido', 'bad'], role_org_mismatch: ['Rol/organización inconsistente', 'bad'] };
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
  const directActive = invite && preset.directActive === true && ctx.role === 'super_admin';
  let provs = [], providersOrg = null, providersReady = false, syncSequence = 0;
  return formDialog({
    title: directActive ? 'Crear usuario activo' : invite ? (preset.role === 'client' ? 'Invitar médico' : preset.role === 'capturer' ? 'Invitar secretaria' : preset.role === 'asistente' ? 'Invitar asistente de consulta' : 'Invitar usuario') : `Cambiar rol · ${preset.email}`,
    submitLabel: directActive ? 'Crear y activar' : invite ? 'Enviar invitación' : 'Guardar rol', wide: true,
    body: html`<div class="form-grid">
      ${invite ? html`${f('email', 'Correo *', html`<input id="f_email" name="email" type="email" required autocomplete="off">`)}
        ${f('full_name', 'Nombre completo *', html`<input id="f_full_name" name="full_name" required maxlength="120">`)}
        ${directActive ? f('password', 'Contraseña temporal *', html`<input id="f_password" name="password" type="password" required minlength="12" autocomplete="new-password"><button type="button" class="btn" id="generate-temporary-password">Generar contraseña segura</button><button type="button" class="btn" id="show-temporary-password">Mostrar</button>`, 'Mínimo 12 caracteres. No se enviará correo; entrégala al usuario por un canal seguro.') : ''}` : ''}
      ${f('role', 'Rol *', html`<select id="f_role" name="role">${roleOpts(ctx, preset.role || 'billing')}</select>`)}
      ${f('org', 'Consultorio o clínica (cliente) *', html`<select id="f_org" name="org"><option value="">Seleccione…</option>${clients.map((c) => opt(c.id, c.legal_name, preset.orgId))}</select>`)}
      </div>
      <p class="small" id="f_rdesc" aria-live="polite"></p>
      <fieldset id="f_provs" style="border:0;padding:0;display:none"><legend class="small" style="font-weight:600" id="f_provs_legend">Médicos que atiende esta secretaria *</legend><div id="f_plist" class="list"></div></fieldset>
      ${directActive ? html`<p class="small muted"><b>Alta directa por Super Admin:</b> la cuenta se confirma y activa sin enviar correo. El usuario deberá cambiar la contraseña temporal en el primer acceso.</p>` : invite ? html`<p class="small muted">La persona recibe un correo para crear su contraseña. Si el correo ya tiene usuario, solo se le asigna el rol.</p>` : ''}
      <p class="small muted">Una persona no puede ser a la vez personal de SOFA y Médico/Secretaria de un cliente. Si esta cuenta quedó mal asignada por error, use «Corregir asignación» en su fila en vez de cambiar el rol aquí.</p>`,
    onOpen: (form) => {
      form.querySelector('#generate-temporary-password')?.addEventListener('click', () => {
        const bytes = crypto.getRandomValues(new Uint8Array(20));
        form.elements.password.value = 'Aa9!' + Array.from(bytes, x => x.toString(16).padStart(2, '0')).join('');
        form.elements.password.type = 'password';
        form.querySelector('#show-temporary-password').textContent = 'Mostrar';
      });
      form.querySelector('#show-temporary-password')?.addEventListener('click', (event) => {
        const input = form.elements.password;
        input.type = input.type === 'password' ? 'text' : 'password';
        event.currentTarget.textContent = input.type === 'password' ? 'Mostrar' : 'Ocultar';
      });
      const sync = async () => {
        const sequence = ++syncSequence;
        providersReady = false; providersOrg = null; provs = [];
        const r = form.elements.role.value; const orgRole = ORG_ROLES.includes(r);
        form.elements.org.disabled = !orgRole; form.elements.org.closest('.field').style.display = orgRole ? '' : 'none';   // [hidden] no basta: .field fija display
        form.querySelector('#f_rdesc').textContent = ROLES[r]?.desc || '';
        const scoped = SCOPED_ROLES.includes(r);
        const box = form.querySelector('#f_provs'); box.style.display = scoped ? '' : 'none';
        form.querySelector('#f_provs_legend').textContent = r === 'asistente' ? 'Médicos que atiende este asistente *' : 'Médicos que atiende esta secretaria *';
        if (scoped && form.elements.org.value) {
          const org = form.elements.org.value;
          paint(form.querySelector('#f_plist'), html`<p role="status">Cargando médicos y asignaciones…</p>`);
          try {
            const scopesOf = r === 'asistente' ? assistantScopes : capturerScopes;
            const [providers, current] = await Promise.all([providersOfOrg(org), preset.userId ? scopesOf(preset.userId) : Promise.resolve([])]);
            if (sequence !== syncSequence || form.elements.org.value !== org || form.elements.role.value !== r) return;
            provs = providers; providersOrg = org; providersReady = true;
            paint(form.querySelector('#f_plist'), provs.length ? html`${provs.map((p) => html`<label class="li" style="cursor:pointer"><input type="checkbox" name="pv_${p.id}" ${current.includes(p.id) || (invite && provs.length === 1) ? 'checked' : ''}><div class="b"><div class="t1">${p.full_name}</div></div></label>`)}`
              : html`<p class="small muted">Este cliente todavía no tiene médicos registrados. Agrégalos en su ficha antes de invitar.</p>`);
          } catch (error) {
            if (sequence === syncSequence) paint(form.querySelector('#f_plist'), html`<p role="alert">No se pudieron verificar los médicos y asignaciones. ${friendlyError(error)}</p>`);
          }
        } else if (scoped) paint(form.querySelector('#f_plist'), html`<p class="small muted">Elige primero el consultorio.</p>`);
      };
      form.elements.role.addEventListener('change', sync); form.elements.org.addEventListener('change', sync); sync();
    },
    onSubmit: async (d, form) => {
      if (invite) {
        const required = directActive ? ['email', 'full_name', 'password'] : ['email', 'full_name'];
        if (!requireFields(form, required)) return false;
        if (!isEmail(d.email)) { fieldError(form.elements.email, 'Correo inválido.'); return false; }
        if (directActive && String(d.password || '').length < 12) { fieldError(form.elements.password, 'Usa al menos 12 caracteres.'); return false; }
      }
      if (ORG_ROLES.includes(d.role) && !form.elements.org.value) { fieldError(form.elements.org, 'Elige el consultorio o clínica.'); return false; }
      const scoped = SCOPED_ROLES.includes(d.role);
      if (scoped && (!providersReady || providersOrg !== form.elements.org.value)) { fieldError(form.elements.org, 'Espere a que se verifiquen los médicos del consultorio seleccionado.'); return false; }
      const chosen = scoped ? provs.filter((p) => d[`pv_${p.id}`]).map((p) => p.id) : [];
      if (scoped && !chosen.length) { toast(d.role === 'asistente' ? 'Marca al menos un médico para el asistente' : 'Marca al menos un médico para la secretaria', 'bad'); return false; }
      const r = await adminUsers({ action: directActive ? 'create_active' : invite ? 'invite' : 'grant', email: invite ? d.email.trim() : preset.email, full_name: d.full_name || '', password: directActive ? d.password : undefined, role: d.role, organization_id: ORG_ROLES.includes(d.role) ? form.elements.org.value : null });
      if (scoped && r?.user_id) {
        try {
          const scopesOf = d.role === 'asistente' ? assistantScopes : capturerScopes;
          const setScope = d.role === 'asistente' ? setAssistantScope : setCapturerScope;
          const current = await scopesOf(r.user_id);
          await setScope(r.user_id, mergeCapturerScope(current, provs.map((p) => p.id), chosen));
        } catch (error) {
          throw new Error(`El rol se guardó, pero la asignación de médicos requiere revisión. No repita la invitación. ${friendlyError(error)}`);
        }
      }
      return r;
    }
  });
}

export async function render(main, ctx) {
  if (!canSee('usuarios', ctx.role)) {
    paint(main, emptyView('Sin acceso', 'Tu rol no puede consultar ni administrar usuarios.'));
    return;
  }
  const manage = can('users.invite', ctx.role); const canToggle = can('users.toggle', ctx.role);
  let rows = [], accounts = []; let filter = '', search = ''; let repairUnavailable = false;
  paint(main, html`
    <div class="page-head users-page-head"><div class="t"><h2>Usuarios y accesos</h2><p>Una fila por cuenta, con sus roles y organizaciones agrupados. Los filtros seleccionan cuentas; se muestran todos sus accesos.</p></div>
      <div class="toolbar" style="margin:0">${manage ? html`<details class="users-add"><summary class="btn primary">+ Agregar usuario</summary><div class="users-add-options"><button class="btn primary" id="invite">+ Invitar usuario</button>${ctx.role === 'super_admin' ? html`<button class="btn" id="createActive">+ Crear usuario activo</button>` : ''}<button class="btn" id="inviteMed">+ Médico</button><button class="btn" id="inviteSec">+ Secretaria</button><button class="btn" id="inviteAsist">+ Asistente de consulta</button></div></details>` : ''}<button class="btn" id="csv">Exportar revisión de accesos</button></div></div>
    <div class="toolbar users-search"><label for="user-search">Buscar cuenta</label><input class="input grow" id="user-search" type="search" placeholder="Nombre, correo o identificador"><span id="user-count" role="status" aria-live="polite"></span></div>
    <div class="tabs" id="kinds" role="group" aria-label="Tipo de usuario" style="margin-bottom:6px"></div>
    <div class="tabs" id="tabs" role="group" aria-label="Estado del acceso"></div><p class="small muted">Una cuenta puede aparecer en varios filtros cuando tiene accesos distintos.</p><div id="repair-availability" role="status"></div><div id="l"></div>
    ${ctx.role === 'super_admin' ? html`<div class="card" style="margin-top:14px"><h2>Validación de usuarios y roles</h2>
      <p class="sub">Revisa usuarios sin rol, roles cruzados, secretarias sin médicos y otras inconsistencias.</p><button class="btn" id="valRoles">Revisar ahora</button><div id="valBox" style="margin-top:10px"></div></div>` : ''}`);
  let kind = '';
  const KINDS = [['', 'Todos'], ['sofa', 'Equipo SOFA'], ['client', 'Médicos'], ['capturer', 'Secretarias'], ['asistente', 'Asistentes de consulta']];
  const drawKinds = () => paint($('#kinds', main), html`${KINDS.map(([k, l]) => html`<button data-k="${k}" aria-pressed="${kind === k}">${l} · ${accounts.filter((u) => matchesAccount(u, { kind: k, q: search })).length}</button>`)}`);
  const tabs = [['', 'Todos'], ['activo', 'Con acceso activo'], ['invitación pendiente', 'Invitación pendiente'], ['sin ingreso en 90 días', 'Sin ingreso en 90 días'], ['desactivado', 'Con acceso desactivado']];
  const drawTabs = () => paint($('#tabs', main), html`${tabs.map(([k, l]) => html`<button data-s="${k}" aria-pressed="${filter === k}">${l} · ${accounts.filter((u) => matchesAccount(u, { kind, status: k, q: search })).length}</button>`)}`);
  const box = $('#l', main);
  const draw = () => {
    const list = accounts.filter((u) => matchesAccount(u, { kind, status: filter, q: search }));
    $('#user-count', main).textContent = `${list.length} de ${accounts.length} cuentas · ${accounts.reduce((n, u) => n + u.memberships.length, 0)} accesos`;
    if (!list.length) { paint(box, emptyView('Sin usuarios en este filtro')); return; }
    paint(box, html`<div class="table-wrap"><table class="t cards users-accounts"><thead><tr><th>Cuenta</th><th>Roles y organizaciones</th><th>Último ingreso</th>${manage || canToggle ? html`<th>Acciones de la cuenta</th>` : ''}</tr></thead>
      <tbody>${list.map((u) => {
        const self = u.user_id === ctx.session.user.id;
        const protectedRow = u.protectedAdmin && ctx.role !== 'super_admin';
        const editable = !!u.user_id && !self && !protectedRow;
        return html`<tr>
          <td data-l="Cuenta"><button class="btn sm users-view" data-view-account="${u.user_id}">Ver cuenta</button><b>${u.full_name || '—'}</b>${self ? html` <span class="pill info">Tú</span>` : ''}<div class="small muted">${[...u.emails].join(' · ') || 'Correo no disponible'}</div><details class="small"><summary>Identificador de cuenta</summary>${u.user_id || 'No disponible'}</details>
            ${u.sharedEmail ? html`<p class="note warn">Correo asociado a cuentas distintas. Requiere revisión; no se han fusionado.</p>` : ''}${u.emailConflict ? html`<p class="note bad">Correos inconsistentes para esta cuenta.</p>` : ''}</td>
          <td data-l="Roles y organizaciones">${u.memberships.map((m) => {
            const [sl, sc] = STATUS[m.status] || [m.status, ''];
            const [rl, rc] = READINESS[m.access_readiness] || [m.access_readiness, ''];
            return html`<section class="user-membership"><b>${m.role_name || ROLES[m.role_code]?.name || m.role_code || 'Sin rol'}</b><div>${m.organization || 'Sin organización'}</div>
              <span class="pill ${sc}">${sl}</span>${rl ? html` <span class="pill ${rc}">${rl}</span>` : ''}<div class="small muted">Invitado ${date(m.invited_at)}</div>
              ${m.conflict ? html`<p class="note bad">Datos contradictorios para este acceso. Revisa la validación antes de modificarlo.</p>` : ''}
              ${editable && !m.conflict ? html`<div class="user-access-actions">${manage && u.email && !u.sharedEmail ? html`<button class="btn sm" data-act="grant" data-email="${u.email}" data-role="${m.role_code}" data-user="${u.user_id}" data-org="${m.organization_id || ''}">Cambiar este rol</button>` : ''}
                ${manage && SCOPED_ROLES.includes(m.role_code) && can('capturers.assign', ctx.role) ? html`<button class="btn sm" data-act="scope" data-role="${m.role_code}" data-user="${u.user_id}" data-org="${m.organization_id}" data-name="${u.full_name || u.email}">Médicos asignados</button>` : ''}
                ${ctx.role === 'super_admin' && m.role_code === 'capturer' && m.is_active === true ? html`<button class="btn sm" data-act="viewas" data-user="${u.user_id}" data-org="${m.organization_id}" data-orgname="${m.organization || ''}" data-name="${u.full_name || u.email}" title="Ver las pantallas de esta secretaria, en modo soporte y solo lectura">Ver como esta secretaria</button>` : ''}
                ${manage ? html`<button class="btn sm" data-act="validate" data-user="${u.user_id}" data-role="${m.role_code || ''}" data-org="${m.organization_id || ''}">Validar acceso</button>` : ''}
                ${!repairUnavailable && ctx.role === 'super_admin' && ORG_ROLES.includes(m.role_code) && m.is_active === true ? html`<button class="btn sm" data-act="repair" data-user="${u.user_id}" data-role="${m.role_code}" data-org="${m.organization_id}">Corregir asignación</button>` : ''}</div>` : ''}</section>`;
          })}</td>
          <td data-l="Último ingreso">${u.last_sign_in_at ? dateTime(u.last_sign_in_at) : '—'}</td>
          ${manage || canToggle ? html`<td data-l="Acciones de la cuenta">${!editable ? html`<p class="small muted">${self ? 'Tu cuenta: otro Super Admin debe realizar los cambios sensibles.' : protectedRow ? 'Cuenta protegida: requiere Super Admin.' : 'Identificador no disponible: revisa la cuenta.'}</p>` : html`
            ${manage && u.email && !u.sharedEmail ? html`
              ${can('users.reset', ctx.role) ? html`<button class="btn sm" data-act="reset" data-user="${u.user_id}" data-name="${u.full_name || u.email}">Restablecer contraseña</button>` : ''}
              <button class="btn sm" data-act="resend" data-user="${u.user_id}" data-email="${u.email}">Enviar acceso</button>` : ''}
            ${canToggle && u.is_active !== null ? html`<button class="btn sm ${u.is_active ? 'danger' : ''}" data-act="toggle" data-user="${u.user_id}" data-active="${u.is_active ? '0' : '1'}" data-name="${u.full_name || u.email}">${u.is_active ? 'Desactivar cuenta' : 'Activar cuenta'}</button>` : ''}
            ${u.is_active === null ? html`<p class="small muted">Estados de acceso distintos o inconsistentes: valida cada acceso antes de activar la cuenta.</p>` : ''}`}</td>` : ''}</tr>`;
      })}</tbody></table></div>`);
  };
  const load = async () => {
    try {
      rows = await usersOverview();
      if (!Array.isArray(rows) || rows.some((u) => !u || typeof u !== 'object')) throw new Error('Respuesta de usuarios no válida.');
      try {
        const readiness = await rpc('users_access_readiness');
        const map = new Map((Array.isArray(readiness) ? readiness : []).map((x) => [`${x.user_id}:${x.role_code || ''}:${x.organization_id || ''}`, x]));
        rows = rows.map((u) => ({ ...u, access_readiness: map.get(`${u.user_id}:${u.role_code || ''}:${u.organization_id || ''}`)?.readiness || null }));
      } catch (_) { /* compatibilidad si aún no existe el RPC */ }
    }
    catch (err) {
      // Sin el script 022: lista básica, sin correos ni último ingreso
      let basic;
      try { basic = await listMemberships(); if (!Array.isArray(basic) || basic.some((m) => !m || typeof m !== 'object')) throw new Error('Respuesta de accesos no válida.'); }
      catch (fallbackError) {
        rows = []; accounts = []; drawKinds(); drawTabs();
        $('#user-count', main).textContent = 'Listado no disponible';
        paint(box, html`<div class="note bad" role="alert">No se pudo cargar la lista de cuentas. ${friendlyError(fallbackError)}</div><button class="btn" id="retryUsers">Reintentar</button>`);
        $('#retryUsers', box).addEventListener('click', load);
        return;
      }
      rows = basic.map((m) => ({ user_id: m.user_id, email: '', full_name: m.profiles?.full_name, role_code: m.role_code, role_name: m.roles?.name, organization_id: m.organization_id, organization: m.organizations?.legal_name, kind: m.organizations?.kind, is_active: m.is_active && m.profiles?.is_active !== false, invited_at: m.created_at, last_sign_in_at: null, status: m.is_active && m.profiles?.is_active !== false ? 'activo' : 'desactivado' }));
      toast(`Revisión de accesos no disponible: ${friendlyError(err)}`);
    }
    accounts = groupUserAccounts(rows);
    drawKinds(); drawTabs(); draw();
  };
  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-s]'); if (b) { filter = b.dataset.s; drawTabs(); draw(); } });
  $('#valRoles', main)?.addEventListener('click', (e) => busy(e.currentTarget, async () => { try { await runRolesReport($('#valBox', main)); } catch (err) { toast(friendlyError(err), 'bad'); } }));
  $('#kinds', main).addEventListener('click', (e) => { const b = e.target.closest('[data-k]'); if (b) { kind = b.dataset.k; drawKinds(); drawTabs(); draw(); } });
  $('#user-search', main).addEventListener('input', (e) => { search = e.target.value; drawKinds(); drawTabs(); draw(); });
  const invitePreset = async (role) => { try { const r = await roleDialog(ctx, { role }); if (r) { toast(r.message, 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } };
  $('#inviteMed', main)?.addEventListener('click', () => invitePreset('client'));
  $('#inviteSec', main)?.addEventListener('click', () => invitePreset('capturer'));
  $('#inviteAsist', main)?.addEventListener('click', () => invitePreset('asistente'));
  $('#invite', main)?.addEventListener('click', async () => { try { const r = await roleDialog(ctx); if (r) { toast(r.message, 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
  $('#createActive', main)?.addEventListener('click', async () => { try { const r = await roleDialog(ctx, { directActive: true }); if (r) { toast(r.message, 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
  $('#csv', main).addEventListener('click', () => downloadCsv(`sofa-revision-accesos-${todayISO()}.csv`, ['ID de cuenta', 'Nombre', 'Correo', 'Accesos (rol / organización / estado)', 'Último ingreso', 'Revisión'],
    accounts.filter((u) => matchesAccount(u, { kind, status: filter, q: search })).map((u) => [u.user_id, u.full_name, [...u.emails].join(' · '), u.memberships.map((m) => `${m.role_name || m.role_code} / ${m.organization || 'Sin organización'} / ${m.status}${m.conflict ? ' / Datos contradictorios' : ''}`).join(' | '), String(u.last_sign_in_at || '').slice(0, 16).replace('T', ' '), u.sharedEmail || u.emailConflict ? 'Revisar identidad' : ''])));
  box.addEventListener('click', (event) => {
    const trigger = event.target.closest('[data-view-account]');
    if (!trigger) return;
    const account = accounts.find((item) => item.user_id === trigger.dataset.viewAccount);
    if (!account) return;
    const row = trigger.closest('tr');
    const dialog = document.createElement('dialog');
    dialog.className = 'dlg users-detail';
    dialog.setAttribute('aria-labelledby', 'account-detail-title');
    paint(dialog, html`<div class="dh" id="account-detail-title">${account.full_name || 'Cuenta seleccionada'}</div>
      <div class="db"><p>${[...account.emails].join(' · ') || 'Correo no disponible'}</p>
      <div class="tabs" role="group" aria-label="Secciones de la cuenta">
      <button data-pane="access" aria-pressed="true">Accesos</button><button data-pane="security" aria-pressed="false">Seguridad</button><button data-pane="activity" aria-pressed="false">Actividad disponible</button></div>
      <section data-content="access"><h3>Roles y organizaciones</h3><div class="users-detail-access"></div></section>
      <section data-content="security" hidden><h3>Acciones de la cuenta</h3><p>Estas acciones afectan a la cuenta completa. Sus registros se conservan.</p><div class="users-detail-security"></div></section>
      <section data-content="activity" hidden><h3>Último ingreso</h3><p>${account.last_sign_in_at ? dateTime(account.last_sign_in_at) : 'No disponible'}</p><p>No se dispone de un historial administrativo completo en esta vista.</p></section></div>
      <div class="df"><button class="btn" data-close-account>Cerrar</button></div>`);
    const copy = (source, target) => {
      if (!source) return;
      const clone = source.cloneNode(true);
      clone.querySelectorAll('[data-act]').forEach((button) => {
        button.addEventListener('click', () => {
          const original = [...source.querySelectorAll('[data-act]')].find((item) => item.dataset.act === button.dataset.act && item.dataset.role === button.dataset.role && item.dataset.org === button.dataset.org);
          dialog.close();
          original?.click(); // La acción vuelve a pasar por resolveAccountAction.
        });
      });
      dialog.querySelector(target).append(clone);
    };
    copy(row.querySelector('[data-l="Roles y organizaciones"]'), '.users-detail-access');
    copy(row.querySelector('[data-l="Acciones de la cuenta"]'), '.users-detail-security');
    dialog.addEventListener('click', (e) => {
      if (e.target.closest('[data-close-account]')) dialog.close();
      const tab = e.target.closest('[data-pane]');
      if (!tab) return;
      dialog.querySelectorAll('[data-pane]').forEach((item) => item.setAttribute('aria-pressed', String(item === tab)));
      dialog.querySelectorAll('[data-content]').forEach((item) => { item.hidden = item.dataset.content !== tab.dataset.pane; });
    });
    dialog.addEventListener('close', () => { dialog.remove(); if (trigger.isConnected) trigger.focus(); }, {once:true});
    document.body.append(dialog); dialog.showModal(); dialog.querySelector('[data-pane]').focus();
  });
  box.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-act]'); if (!b) return;
    if (b.disabled || b.getAttribute('aria-busy') === 'true') return;
    if (b.dataset.act === 'viewas') {
      const { enterViewAs } = await import('../app.js');
      await enterViewAs({ id: b.dataset.org, legal_name: b.dataset.orgname }, { userId: b.dataset.user, role: 'capturer', name: b.dataset.name });
      return;
    }
    const selection = resolveAccountAction(accounts, { role: ctx.role, userId: ctx.session.user.id }, {
      action: b.dataset.act, userId: b.dataset.user, role: b.dataset.role, orgId: b.dataset.org
    });
    if (!selection) { toast('Acción no disponible para la cuenta o el acceso seleccionado.', 'bad'); return; }
    const { account, membership } = selection;
    try {
      if (b.dataset.act === 'repair') {
        if (repairUnavailable) return;
        try { await busy(b, () => repairAssignment(account, membership, load)); }
        catch (error) {
          if (error.code !== 'REPAIR_NOT_INSTALLED') throw error;
          repairUnavailable = true;
          paint($('#repair-availability', main), html`<div class="note warn"><b>Corrección de asociaciones no habilitada</b><p>La base todavía no tiene instalada la herramienta validada de corrección. No se modificó ninguna cuenta. Un administrador debe completar su validación e instalación; no elimines ni reactives accesos para evitar este bloqueo.</p></div>`);
          draw();
        }
        return;
      }
      if (b.dataset.act === 'grant') { const r = await roleDialog(ctx, { email: account.email, role: membership.role_code, orgId: membership.kind === 'client' ? membership.organization_id : '', userId: account.user_id }); if (r) { toast(r.message, 'ok'); load(); } return; }
      if (b.dataset.act === 'scope') { if (await scopeDialog(account.user_id, membership.organization_id, account.full_name || account.email, b.dataset.role)) { toast('Médicos asignados actualizados', 'ok'); load(); } return; }
      if (b.dataset.act === 'reset') { await resetPassword(account.user_id, account.full_name || account.email); return; }
      if (b.dataset.act === 'resend') { await busy(b, async () => { const r = await adminUsers({ action: 'resend', email: account.email }); toast(r.message, 'ok'); }); return; }
      if (b.dataset.act === 'validate') {
        await validateUser(membership, load, { allowActivation: canToggle && account.memberships.length === 1 && account.is_active === false });
        return;
      }
      await busy(b, async () => {
        const activate = !account.is_active;
        if (!(await confirmDialog(activate ? 'Activar usuario' : 'Desactivar usuario', activate ? `${account.full_name || account.email} podrá volver a entrar a SOFA.` : `${account.full_name || account.email} no podrá ver ni modificar datos desde este momento. Sus registros y su historial se conservan.`, activate ? 'Activar' : 'Desactivar', !activate))) return;
        await setUserActive(account.user_id, activate); toast(activate ? 'Usuario activado' : 'Usuario desactivado', 'ok'); await load();
      });
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
}

/** Corrección explícita y auditada, no eliminación de la identidad. */
async function repairAssignment(account, membership, reload) {
  let preview;
  try {
    const result = await supabase.rpc('admin_user_repair_preview', { p_user: account.user_id, p_org: membership.organization_id });
    if (result.error) {
      const error = new Error(result.error.message || 'No se pudo verificar la asociación.');
      error.code = result.error.code;
      throw error;
    }
    preview = result.data;
  }
  catch (error) {
    if (['PGRST202', '42883'].includes(error?.code) ||
        /(?:could not find the function|function .* does not exist).*admin_user_repair_preview|admin_user_repair_preview.*does not exist/i.test(String(error?.message))) {
      const missing = new Error('La herramienta de corrección todavía no está habilitada en esta base. No se modificó la cuenta.');
      missing.code = 'REPAIR_NOT_INSTALLED'; throw missing;
    }
    throw error;
  }
  if (!preview || preview.user_id !== account.user_id || preview.client_org_id !== membership.organization_id ||
      preview.target_role !== 'admin' || !Array.isArray(preview.blockers) || !preview.expected) throw new Error('No se pudo verificar la vista previa. No se modificó la cuenta.');
  const allowed = preview.can_repair === true && preview.blockers.length === 0;
  let saved = false;
  await formDialog({
    title: 'Corregir asociación de cuenta', submitLabel: allowed ? 'Desactivar asociación errónea' : 'Cerrar', wide: true,
    body: html`<p><b>${account.full_name || 'Cuenta seleccionada'}</b><br>${preview.email}</p>
      <details><summary>Identificador de cuenta</summary>${preview.user_id}</details>
      <dl class="kv"><dt>Asociación actual</dt><dd>${ROLES[membership.role_code]?.name || membership.role_code} · ${membership.organization}</dd>
      <dt>Cambio por defecto</dt><dd>Solo desactivar esa asociación errónea. No se otorga ningún otro acceso.</dd>
      <dt>Cuenta e historial</dt><dd>Se conservan el identificador, correo, documentos y registros anteriores. No se elimina al usuario.</dd>
      <dt>Activación</dt><dd>${preview.profile_active === true ? 'La cuenta conservará su estado activo.' : 'La cuenta permanecerá inactiva; esta corrección no la reactiva.'}</dd></dl>
      ${allowed ? html`<div class="field"><label for="repair-reason">Motivo de la corrección *</label><textarea id="repair-reason" name="reason" rows="3" maxlength="1000" required placeholder="Describe por qué esta cuenta fue asociada por error al cliente"></textarea><span class="hint">Al menos 12 caracteres. El motivo y los accesos anteriores quedan registrados.</span></div>
        <div class="field"><label for="repair-email">Escribe el correo para confirmar *</label><input id="repair-email" name="email" type="email" autocomplete="off" required></div>
        <div class="field"><label class="check" for="repair-promote"><input id="repair-promote" type="checkbox" name="promote_admin"> Esta cuenta en realidad es personal de SOFA: además de desactivar la asociación, asignarle Administrador en su operador.</label><span class="hint">Déjalo sin marcar para el caso normal: solo se resetea la asociación errónea de este usuario (ej. un médico o secretaria mal asociado), sin darle ningún rol nuevo.</span></div>
        <div id="repair-promote-extra" hidden><div class="field"><label class="check" for="repair-confirmed"><input id="repair-confirmed" type="checkbox" name="confirmed"> Confirmo que esta cuenta debe ser Administrador SOFA y que su asociación al cliente es un error.</label><span role="status" class="sr-only" id="repair-confirmation-status"></span></div></div>` : html`<div class="note bad" role="alert"><b>No se puede corregir automáticamente</b><ul>${preview.blockers.map((message) => html`<li>${message}</li>`)}</ul></div>`}`,
    onOpen: (form, d) => {
      if (!allowed) return;
      const promote = form.elements.promote_admin;
      const extra = form.querySelector('#repair-promote-extra');
      const submitBtn = d.querySelector('[type=submit]');
      promote?.addEventListener('change', () => {
        extra.hidden = !promote.checked;
        if (!promote.checked) form.elements.confirmed.checked = false;
        submitBtn.textContent = promote.checked ? 'Corregir y asignar Administrador' : 'Desactivar asociación errónea';
      });
    },
    onSubmit: async (d, form) => {
      if (!allowed) return true;
      if ((d.reason || '').trim().length < 12) { fieldError(form.elements.reason, 'Describe el motivo con al menos 12 caracteres.'); return false; }
      if ((d.email || '').trim().toLowerCase() !== String(preview.email || '').toLowerCase()) { fieldError(form.elements.email, 'El correo no coincide con la cuenta mostrada.'); return false; }
      if (d.promote_admin === true && d.confirmed !== true) { fieldError(form.elements.confirmed, 'Confirma el cambio solicitado.'); form.querySelector('#repair-confirmation-status').textContent = 'Confirma el cambio solicitado.'; form.elements.confirmed.focus(); return false; }
      const result = await rpc('admin_repair_user_access', { p_user: preview.user_id, p_org: preview.client_org_id,
        p_reason: d.reason.trim(), p_confirm_email: d.email.trim(), p_expected: preview.expected, p_promote_admin: d.promote_admin === true });
      if (result?.ok !== true || !result.audit_id) throw new Error('No se confirmó la corrección. Revisa la cuenta antes de reintentar.');
      saved = true;
      toast(result.promoted_admin ? `Administrador SOFA asignado. Registro de auditoría: ${result.audit_id}.` : `Asociación errónea desactivada. Registro de auditoría: ${result.audit_id}.`, 'ok');
      return true;
    }
  });
  if (saved) await reload();
}

/** Validación individual de usuario y activación segura. */
async function validateUser(u, reload, { allowActivation = false } = {}) {
  const staff = SOFA_ROLES.includes(u.role_code);
  let readiness = null;
  try {
    const all = await rpc('users_access_readiness');
    readiness = (Array.isArray(all) ? all : []).find((x) => x.user_id === u.user_id && x.role_code === u.role_code && x.organization_id === u.organization_id) || null;
  } catch (_) { /* compatibilidad mientras se despliega la migración RBAC */ }
  const checks = [
    { label: 'Validación de acceso en servidor', ok: !!readiness, detail: readiness ? 'Respuesta disponible para este rol y organización' : 'No disponible: no se habilita activación desde esta validación' },
    ...(readiness ? [
      { label: 'Correo confirmado', ok: readiness.email_confirmed, detail: readiness.email_confirmed ? 'Confirmado' : 'Pendiente de confirmación' },
      { label: 'Perfil activo', ok: readiness.profile_active, detail: readiness.profile_active ? 'Activo' : 'Desactivado' },
      { label: 'Membresía activa', ok: readiness.membership_active, detail: readiness.membership_active ? 'Activa' : 'Desactivada' }
    ] : []),
    { label: 'Correo registrado', ok: !!u.email, detail: u.email || 'Sin correo disponible' },
    { label: 'Rol reconocido', ok: !!ROLES[u.role_code], detail: ROLES[u.role_code]?.name || u.role_code || 'Sin rol' },
    { label: 'Organización asignada', ok: !!u.organization_id && !!u.organization, detail: u.organization || 'Sin organización' },
    { label: 'Rol y tipo de organización', ok: staff ? u.kind === 'operator' : u.kind === 'client', detail: staff ? 'Debe pertenecer a SOFA' : 'Debe pertenecer a un cliente' }
  ];

  if (u.role_code === 'capturer' || u.role_code === 'asistente') {
    try {
      const scopes = await (u.role_code === 'asistente' ? assistantScopes : capturerScopes)(u.user_id);
      checks.push({ label: 'Médicos asignados', ok: scopes.length > 0, detail: scopes.length ? `${scopes.length} médico(s) asignado(s)` : 'Sin médicos asignados' });
    } catch (err) {
      checks.push({ label: 'Médicos asignados', ok: false, detail: friendlyError(err) });
    }
  }

  let findings = [], reportComplete = false;
  try {
    const { usersRolesReport } = await import('../services/admin.js');
    const report = await usersRolesReport();
    if (!Array.isArray(report)) throw new Error('Reporte no válido');
    const email = String(u.email || '').toLowerCase();
    findings = report.filter((r) => (r.users || []).some((x) => x.user_id ? x.user_id === u.user_id : email && String(x.email || '').toLowerCase() === email));
    reportComplete = true;
  } catch (_) { /* La validación básica sigue disponible si el reporte global no responde. */ }

  const hardFail = !reportComplete || checks.some((x) => !x.ok) || findings.some((x) => x.severity === 'alta');
  const canActivateNow = allowActivation && !u.is_active && !hardFail;
  const SEV = { alta: ['Corregir', 'bad'], media: ['Revisar', 'warn'], info: ['Info', 'info'], ok: ['Bien', 'ok'] };

  await formDialog({
    title: `Validar usuario · ${u.full_name || u.email || 'Usuario'}`,
    submitLabel: canActivateNow ? 'Activar usuario' : 'Cerrar',
    body: html`<p class="small">SOFA revisa identidad básica, rol, organización, alcance y hallazgos de gobierno antes de permitir la activación.</p>
      <div class="list">${checks.map((x) => html`<div class="li"><span class="pill ${x.ok ? 'ok' : 'bad'}">${x.ok ? 'Correcto' : 'Revisar'}</span><div class="b"><div class="t1">${x.label}</div><div class="t2">${x.detail}</div></div></div>`)}</div>
      ${findings.length ? html`<h3 style="margin-top:14px">Hallazgos relacionados</h3><div class="list">${findings.map((r) => { const [l, cls] = SEV[r.severity] || [r.severity, '']; return html`<div class="li"><span class="pill ${cls}">${l}</span><div class="b"><div class="t1">${r.title}</div><div class="t2">${r.detail}</div></div></div>`; })}</div>` : html`<p class="small muted" style="margin-top:12px">${reportComplete ? 'Sin hallazgos adicionales asociados a este usuario.' : 'Reporte de roles no disponible: validación incompleta.'}</p>`}
      <p class="small" style="margin-top:12px"><b>Estado actual:</b> ${u.is_active ? 'Activo' : 'Desactivado'} · <b>Resultado:</b> ${hardFail ? 'requiere corrección antes de activar' : 'validación satisfactoria'}.</p>`,
    onSubmit: async () => {
      if (!canActivateNow) return true;
      if (!(await confirmDialog('Activar usuario', `${u.full_name || u.email} superó la validación y podrá volver a entrar a SOFA.`, 'Activar'))) return false;
      await setUserActive(u.user_id, true);
      toast('Usuario validado y activado', 'ok');
      await reload();
      return true;
    }
  });
}

/** D3 · Capturador: solo ve y registra reclamaciones de los médicos asignados aquí (mínimo privilegio, aplicado también por RLS) */
async function scopeDialog(userId, orgId, name, role = 'capturer') {
  const scopesOf = role === 'asistente' ? assistantScopes : capturerScopes;
  const setScope = role === 'asistente' ? setAssistantScope : setCapturerScope;
  const [provs, current] = await Promise.all([providersOfOrg(orgId), scopesOf(userId)]);
  return formDialog({
    title: `Médicos asignados · ${name}`, submitLabel: 'Guardar asignación',
    body: provs.length ? html`<p class="small">${role === 'asistente' ? 'El asistente solo podrá mover el flujo de pacientes y, si el médico lo autoriza, leer/escribir la historia clínica de los médicos marcados. Nunca verá a otros médicos.' : 'La secretaria solo podrá registrar y consultar reclamaciones de los médicos marcados. Nunca verá pagos, honorarios ni información de otros médicos.'}</p>
      <div class="list">${provs.map((p) => html`<label class="li" style="cursor:pointer"><input type="checkbox" name="p_${p.id}" ${current.includes(p.id) ? 'checked' : ''}><div class="b"><div class="t1">${p.full_name}</div></div></label>`)}</div>`
      : emptyView('Sin médicos', 'Este cliente no tiene médicos activos registrados.'),
    onSubmit: async (d) => {
      const chosen = provs.filter((p) => d[`p_${p.id}`]).map((p) => p.id);
      const freshScope = await scopesOf(userId);
      await setScope(userId, mergeCapturerScope(freshScope, provs.map((p) => p.id), chosen));
      return true;
    }
  });
}

/** Invitar Médico o Secretaria desde la ficha del cliente (consultorio ya elegido) */
export async function inviteToClient(ctx, role, orgId) { return roleDialog(ctx, { role, orgId }); }

/** Validación de usuarios y roles (solo Super Admin) */
async function runRolesReport(box) {
  const { usersRolesReport } = await import('../services/admin.js');
  const SEV = { alta: ['Corregir', 'bad'], media: ['Revisar', 'warn'], info: ['Informativo', 'info'], ok: ['Bien', 'ok'] };
  const rows = await usersRolesReport();
  const bad = rows.filter((r) => r.severity === 'alta').length; const warn = rows.filter((r) => r.severity === 'media').length;
  paint(box, html`<p><b>${bad ? `${bad} punto(s) a corregir` : 'Sin puntos críticos'}</b>${warn ? ` · ${warn} a revisar` : ''} · ${rows.length} reglas revisadas</p>
    <div class="list">${rows.map((r) => { const [l, c] = SEV[r.severity] || [r.severity, '']; return html`<div class="li" style="align-items:flex-start">
      <span class="pill ${c}" style="min-width:86px;text-align:center">${l}</span><div class="b"><div class="t1">${r.title}${r.check_code === 'super_admin' || r.n ? ` · ${r.n}` : ''}</div><div class="t2">${r.detail}</div>
      ${r.n && (r.severity !== 'ok' || r.check_code === 'super_admin') ? html`<div class="t2">${r.users.slice(0, 12).map((u) => [u.name, u.email, u.role, u.roles, u.org, u.medico, u.estado].filter(Boolean).join(' · ')).join(' | ')}${r.users.length > 12 ? ` y ${r.users.length - 12} más` : ''}</div>` : ''}</div></div>`; })}</div>`);
}

/** 4.7.0 (SEG-21) · Médico con historia clínica activa: no se muestra ninguna clave temporal (con ella se podría entrar como él).
 *  Se pide el motivo, queda en la bitácora de usuarios y Supabase envía el enlace de recuperación al correo del propio médico. */
async function recoveryLink(userId, name, email) {
  await formDialog({
    title: `Enlace de recuperación · ${name}`, submitLabel: 'Registrar y enviar enlace',
    body: html`<p><b>${name}</b> tiene historia clínica activa. Por seguridad SOFA no genera una clave temporal para este usuario: se envía un enlace de recuperación a su correo (<b>${email}</b>) y solo él elige su contraseña nueva.</p>
      <div class="field"><label for="f_reason">Motivo del restablecimiento *</label><textarea id="f_reason" name="reason" rows="3" maxlength="300" required placeholder="Ej.: el médico olvidó su clave y pidió ayuda por teléfono"></textarea><span class="hint">Mínimo 10 caracteres. Queda en la bitácora de usuarios.</span></div>`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['reason'])) return false;
      const reason = String(d.reason || '').trim();
      if (reason.length < 10) { fieldError(form.elements.reason, 'Escriba el motivo con al menos 10 caracteres.'); return false; }
      // Primero pedir el correo: nunca auditar un envío que Supabase rechazó.
      const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: `${location.origin}/login.html` });
      if (error) {
        const limited = error.status === 429 || /rate.limit|too many requests|demasiados intentos/i.test(String(error.message || ''));
        throw new Error(limited
          ? 'Supabase limitó temporalmente los correos (429). No se envió un enlace nuevo. Espere antes de reintentar.'
          : `No se pudo solicitar el correo de recuperación: ${error.message}. No se registró como enviado.`);
      }
      // El éxito de API indica solicitud aceptada, NO entrega al buzón.
      try {
        await rpc('record_recovery_link', { p_user: userId, p_reason: reason });
        toast(`Supabase aceptó la solicitud de recuperación para ${email}. Compruebe la bandeja y spam.`, 'ok');
      } catch (auditError) {
        console.error('SOFA: solicitud de recuperación aceptada; falló registro de auditoría', auditError);
        toast('Supabase aceptó la solicitud, pero falló el registro en bitácora. No vuelva a enviar; contacte soporte.', 'bad');
      }
      return true;
    }
  });
}

/** 2.1 · Restablecer contraseña (solo Super Admin): clave temporal que se muestra una sola vez; el usuario la cambia al entrar */
async function resetPassword(userId, name) {
  // 4.7.0 (SEG-21): si es un médico con historia clínica activa, enlace al correo en vez de clave temporal.
  // Si la migración 176 todavía no está aplicada, se sigue con la clave temporal pero con la advertencia.
  let info = null;
  try { info = await rpc('password_reset_info', { p_user: userId }); }
  catch (err) { if (!/password_reset_info|schema cache|does not exist/i.test(String(err?.message))) { toast(friendlyError(err), 'bad'); return; } }
  if (info?.clinical) { try { await recoveryLink(userId, name, info.email); } catch (err) { toast(friendlyError(err), 'bad'); } return; }
  if (!(await confirmDialog('Restablecer contraseña', `Se generará una clave temporal para ${name}. Su contraseña actual dejará de funcionar y deberá cambiar la temporal al entrar.`, 'Restablecer'))) return;
  let r;
  try { r = await invoke('restablecer-clave', { user_id: userId }); } catch (err) { toast(friendlyError(err), 'bad'); return; }
  await formDialog({
    title: `Clave temporal · ${name}`, submitLabel: 'Listo, ya la entregué',
    body: html`<p>Entregue esta clave por un medio privado (en persona o mensaje directo). <b>Se muestra una sola vez.</b></p>
      <p class="mono" style="font-size:1.3rem;letter-spacing:.06em;padding:10px 12px;border:1px solid var(--line);border-radius:var(--r);user-select:all" id="tmpPass">${r.temporary_password}</p>
      <button type="button" class="btn sm" id="cpPass">Copiar clave</button>
      <p class="small muted">Al entrar con ella, SOFA le pedirá una contraseña nueva. Quedó registrado en la bitácora de usuarios.</p>
      <p class="small"><b>Advertencia:</b> quien conozca esta clave puede entrar como ${name}. No la use con un médico que maneja historia clínica; para ellos use el enlace de recuperación al correo.</p>`,
    onOpen: (form) => form.querySelector('#cpPass').addEventListener('click', async (e) => {
      try { await navigator.clipboard.writeText(r.temporary_password); e.currentTarget.textContent = 'Copiada'; } catch (_) { e.currentTarget.textContent = 'Seleccione y copie con Ctrl+C'; }
    }),
    onSubmit: async () => true
  });
}
