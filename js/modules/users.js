/** SOFA · Usuarios y roles: invitaciones, cambio de rol, activación, restablecer contraseña (2.1) y revisión periódica de accesos */
import { html, render as paint, $ } from '../utils/dom.js';
import { emptyView, toast, friendlyError, confirmDialog, busy, formDialog, opt, requireFields, fieldError } from '../utils/ui.js';
import { listMemberships, setUserActive, usersOverview, adminUsers } from '../services/admin.js';
import { clientOptions } from '../services/bi.js';
import { downloadCsv } from '../utils/filters.js';
import { can, ROLES } from '../utils/permissions.js';
import { date, dateTime, todayISO } from '../utils/formatters.js';
import { isEmail } from '../utils/validation.js';
import { capturerScopes, providersOfOrg, setCapturerScope } from '../services/claims.js';
import { invoke, rpc, supabase } from '../services/iter18.js';

const ORG_ROLES = ['client', 'capturer'];   // roles de la organización del cliente (no SOFA)

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
  let provs = [];
  return formDialog({
    title: directActive ? 'Crear usuario activo' : invite ? (preset.role === 'client' ? 'Invitar médico' : preset.role === 'capturer' ? 'Invitar secretaria' : 'Invitar usuario') : `Cambiar rol · ${preset.email}`,
    submitLabel: directActive ? 'Crear y activar' : invite ? 'Enviar invitación' : 'Guardar rol', wide: true,
    body: html`<div class="form-grid">
      ${invite ? html`${f('email', 'Correo *', html`<input id="f_email" name="email" type="email" required autocomplete="off">`)}
        ${f('full_name', 'Nombre completo *', html`<input id="f_full_name" name="full_name" required maxlength="120">`)}
        ${directActive ? f('password', 'Contraseña temporal *', html`<input id="f_password" name="password" type="password" required minlength="12" autocomplete="new-password">`, 'Mínimo 12 caracteres. No se enviará correo; entrégala al usuario por un canal seguro.') : ''}` : ''}
      ${f('role', 'Rol *', html`<select id="f_role" name="role">${roleOpts(ctx, preset.role || 'billing')}</select>`)}
      ${f('org', 'Consultorio o clínica (cliente) *', html`<select id="f_org" name="org"><option value="">Seleccione…</option>${clients.map((c) => opt(c.id, c.legal_name, preset.orgId))}</select>`)}
      </div>
      <p class="small" id="f_rdesc" aria-live="polite"></p>
      <fieldset id="f_provs" style="border:0;padding:0;display:none"><legend class="small" style="font-weight:600">Médicos que atiende esta secretaria *</legend><div id="f_plist" class="list"></div></fieldset>
      ${directActive ? html`<p class="small muted"><b>Alta directa por Super Admin:</b> la cuenta se confirma y activa sin enviar correo. El usuario deberá cambiar la contraseña temporal en el primer acceso.</p>` : invite ? html`<p class="small muted">La persona recibe un correo para crear su contraseña. Si el correo ya tiene usuario, solo se le asigna el rol.</p>` : ''}`,
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
        const required = directActive ? ['email', 'full_name', 'password'] : ['email', 'full_name'];
        if (!requireFields(form, required)) return false;
        if (!isEmail(d.email)) { fieldError(form.elements.email, 'Correo inválido.'); return false; }
        if (directActive && String(d.password || '').length < 12) { fieldError(form.elements.password, 'Usa al menos 12 caracteres.'); return false; }
      }
      if (ORG_ROLES.includes(d.role) && !form.elements.org.value) { fieldError(form.elements.org, 'Elige el consultorio o clínica.'); return false; }
      const chosen = d.role === 'capturer' ? provs.filter((p) => d[`pv_${p.id}`]).map((p) => p.id) : [];
      if (d.role === 'capturer' && !chosen.length) { toast('Marca al menos un médico para la secretaria', 'bad'); return false; }
      const r = await adminUsers({ action: directActive ? 'create_active' : invite ? 'invite' : 'grant', email: invite ? d.email.trim() : preset.email, full_name: d.full_name || '', password: directActive ? d.password : undefined, role: d.role, organization_id: ORG_ROLES.includes(d.role) ? form.elements.org.value : null });
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
      <div class="toolbar" style="margin:0">${manage ? html`<button class="btn primary" id="invite">+ Invitar usuario</button>${ctx.role === 'super_admin' ? html`<button class="btn" id="createActive">+ Crear usuario activo</button>` : ''}<button class="btn" id="inviteMed">+ Médico</button><button class="btn" id="inviteSec">+ Secretaria</button>` : ''}<button class="btn" id="csv">Exportar revisión de accesos</button></div></div>
    <div class="tabs" id="kinds" role="group" aria-label="Tipo de usuario" style="margin-bottom:6px"></div>
    <div class="tabs" id="tabs" role="group" aria-label="Estado"></div><div id="l"></div>
    ${ctx.role === 'super_admin' ? html`<div class="card" style="margin-top:14px"><h2>Validación de usuarios y roles</h2>
      <p class="sub">Revisa usuarios sin rol, roles cruzados, secretarias sin médicos y otras inconsistencias.</p><button class="btn" id="valRoles">Revisar ahora</button><div id="valBox" style="margin-top:10px"></div></div>` : ''}`);
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
          <td data-l="Estado"><span class="pill ${sc}">${sl}</span>${u.access_readiness ? (() => { const [rl, rc] = READINESS[u.access_readiness] || [u.access_readiness, '']; return html` <span class="pill ${rc}">${rl}</span>`; })() : ''}<div class="small muted">Invitado ${date(u.invited_at)}</div></td>
          <td data-l="Último ingreso">${u.last_sign_in_at ? dateTime(u.last_sign_in_at) : '—'}</td>
          ${manage || canToggle ? html`<td data-l="">${self || protectedRow ? '' : html`
            ${manage && u.email ? html`<button class="btn sm" data-act="grant" data-email="${u.email}" data-role="${u.role_code}" data-user="${u.user_id}" data-org="${u.kind === 'client' ? u.organization_id : ''}">Cambiar rol</button>
              ${u.role_code === 'capturer' && can('capturers.assign', ctx.role) ? html`<button class="btn sm" data-act="scope" data-user="${u.user_id}" data-org="${u.organization_id}" data-name="${u.full_name || u.email}">Médicos asignados</button>` : ''}
              ${can('users.reset', ctx.role) ? html`<button class="btn sm" data-act="reset" data-user="${u.user_id}" data-name="${u.full_name || u.email}">Restablecer contraseña</button>` : ''}
              <button class="btn sm" data-act="resend" data-email="${u.email}">${u.status === 'invitación pendiente' ? 'Reenviar invitación' : 'Enviar acceso'}</button>
              <button class="btn sm" data-act="validate" data-user="${u.user_id}">Validar usuario</button>` : ''}
            ${canToggle ? html`<button class="btn sm ${u.is_active ? 'danger' : ''}" data-act="toggle" data-user="${u.user_id}" data-active="${u.is_active ? '0' : '1'}" data-name="${u.full_name || u.email}">${u.is_active ? 'Desactivar' : 'Activar usuario'}</button>` : ''}`}</td>` : ''}</tr>`;
      })}</tbody></table></div>`);
  };
  const load = async () => {
    try {
      rows = await usersOverview();
      try {
        const readiness = await rpc('users_access_readiness');
        const map = new Map((Array.isArray(readiness) ? readiness : []).map((x) => [`${x.user_id}:${x.role_code || ''}:${x.organization_id || ''}`, x]));
        rows = rows.map((u) => ({ ...u, access_readiness: map.get(`${u.user_id}:${u.role_code || ''}:${u.organization_id || ''}`)?.readiness || null }));
      } catch (_) { /* compatibilidad si aún no existe el RPC */ }
    }
    catch (err) {
      // Sin el script 022: lista básica, sin correos ni último ingreso
      const basic = await listMemberships().catch(() => []);
      rows = basic.map((m) => ({ user_id: m.user_id, email: '', full_name: m.profiles?.full_name, role_code: m.role_code, role_name: m.roles?.name, organization_id: m.organization_id, organization: m.organizations?.legal_name, kind: m.organizations?.kind, is_active: m.is_active && m.profiles?.is_active !== false, invited_at: m.created_at, last_sign_in_at: null, status: m.is_active ? 'activo' : 'desactivado' }));
      toast(`Revisión de accesos no disponible: ${friendlyError(err)}`);
    }
    drawKinds(); drawTabs(); draw();
  };
  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-s]'); if (b) { filter = b.dataset.s; drawTabs(); draw(); } });
  $('#valRoles', main)?.addEventListener('click', (e) => busy(e.currentTarget, async () => { try { await runRolesReport($('#valBox', main)); } catch (err) { toast(friendlyError(err), 'bad'); } }));
  $('#kinds', main).addEventListener('click', (e) => { const b = e.target.closest('[data-k]'); if (b) { kind = b.dataset.k; drawKinds(); draw(); } });
  const invitePreset = async (role) => { try { const r = await roleDialog(ctx, { role }); if (r) { toast(r.message, 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } };
  $('#inviteMed', main)?.addEventListener('click', () => invitePreset('client'));
  $('#inviteSec', main)?.addEventListener('click', () => invitePreset('capturer'));
  $('#invite', main)?.addEventListener('click', async () => { try { const r = await roleDialog(ctx); if (r) { toast(r.message, 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
  $('#createActive', main)?.addEventListener('click', async () => { try { const r = await roleDialog(ctx, { directActive: true }); if (r) { toast(r.message, 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
  $('#csv', main).addEventListener('click', () => downloadCsv(`sofa-revision-accesos-${todayISO()}.csv`, ['Nombre', 'Correo', 'Rol', 'Organización', 'Estado', 'Invitado', 'Último ingreso'],
    rows.map((u) => [u.full_name, u.email, u.role_name, u.organization, u.status, String(u.invited_at || '').slice(0, 10), String(u.last_sign_in_at || '').slice(0, 16).replace('T', ' ')])));
  box.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-act]'); if (!b) return;
    try {
      if (b.dataset.act === 'grant') { const r = await roleDialog(ctx, { email: b.dataset.email, role: b.dataset.role, orgId: b.dataset.org, userId: b.dataset.user }); if (r) { toast(r.message, 'ok'); load(); } return; }
      if (b.dataset.act === 'scope') { if (await scopeDialog(b.dataset.user, b.dataset.org, b.dataset.name)) { toast('Médicos asignados actualizados', 'ok'); load(); } return; }
      if (b.dataset.act === 'reset') { await resetPassword(b.dataset.user, b.dataset.name); return; }
      if (b.dataset.act === 'resend') { await busy(b, async () => { const r = await adminUsers({ action: 'resend', email: b.dataset.email }); toast(r.message, 'ok'); }); return; }
      if (b.dataset.act === 'validate') { const u = rows.find((x) => x.user_id === b.dataset.user); if (u) await validateUser(u, load); return; }
      const activate = b.dataset.active === '1';
      if (!(await confirmDialog(activate ? 'Activar usuario' : 'Desactivar usuario', activate ? `${b.dataset.name} podrá volver a entrar a SOFA.` : `${b.dataset.name} no podrá ver ni modificar datos desde este momento. Sus registros y su historial se conservan.`, activate ? 'Activar' : 'Desactivar', !activate))) return;
      await setUserActive(b.dataset.user, activate); toast(activate ? 'Usuario activado' : 'Usuario desactivado', 'ok'); load();
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
}

/** Validación individual de usuario y activación segura. */
async function validateUser(u, reload) {
  const staff = SOFA_ROLES.includes(u.role_code);
  let readiness = null;
  try {
    const all = await rpc('users_access_readiness');
    readiness = (Array.isArray(all) ? all : []).find((x) => x.user_id === u.user_id && x.role_code === u.role_code) || null;
  } catch (_) { /* compatibilidad mientras se despliega la migración RBAC */ }
  const checks = [
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

  if (u.role_code === 'capturer') {
    try {
      const scopes = await capturerScopes(u.user_id);
      checks.push({ label: 'Médicos asignados', ok: scopes.length > 0, detail: scopes.length ? `${scopes.length} médico(s) asignado(s)` : 'Sin médicos asignados' });
    } catch (err) {
      checks.push({ label: 'Médicos asignados', ok: false, detail: friendlyError(err) });
    }
  }

  let findings = [];
  try {
    const { usersRolesReport } = await import('../services/admin.js');
    const report = await usersRolesReport();
    const email = String(u.email || '').toLowerCase();
    findings = report.filter((r) => (r.users || []).some((x) => String(x.email || '').toLowerCase() === email));
  } catch (_) { /* La validación básica sigue disponible si el reporte global no responde. */ }

  const hardFail = checks.some((x) => !x.ok) || findings.some((x) => x.severity === 'alta');
  const canActivateNow = !u.is_active && !hardFail;
  const SEV = { alta: ['Corregir', 'bad'], media: ['Revisar', 'warn'], info: ['Info', 'info'], ok: ['Bien', 'ok'] };

  await formDialog({
    title: `Validar usuario · ${u.full_name || u.email || 'Usuario'}`,
    submitLabel: canActivateNow ? 'Activar usuario' : 'Cerrar',
    body: html`<p class="small">SOFA revisa identidad básica, rol, organización, alcance y hallazgos de gobierno antes de permitir la activación.</p>
      <div class="list">${checks.map((x) => html`<div class="li"><span class="pill ${x.ok ? 'ok' : 'bad'}">${x.ok ? 'Correcto' : 'Revisar'}</span><div class="b"><div class="t1">${x.label}</div><div class="t2">${x.detail}</div></div></div>`)}</div>
      ${findings.length ? html`<h3 style="margin-top:14px">Hallazgos relacionados</h3><div class="list">${findings.map((r) => { const [l, cls] = SEV[r.severity] || [r.severity, '']; return html`<div class="li"><span class="pill ${cls}">${l}</span><div class="b"><div class="t1">${r.title}</div><div class="t2">${r.detail}</div></div></div>`; })}</div>` : html`<p class="small muted" style="margin-top:12px">Sin hallazgos adicionales asociados a este usuario.</p>`}
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
