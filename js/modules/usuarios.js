/** SOFA · Alta de usuarios: correo + vínculo + rol. La clave temporal la genera el servidor y se muestra una vez.
 *  2.1 · Al crear se vincula a un CLIENTE (Médico o Secretaria), a un PROSPECTO (rol Prospecto: solo ve su incorporación
 *  y pasa a Médico cuando se convierte en cliente) o al EQUIPO SOFA.
 *  2.6.1: el Médico o el Centro ya no crea usuarios: envía una SOLICITUD que el Super Admin aprueba (la cuenta se crea al aprobar). */
import { supabase, invoke, rpc, h, note, guarded } from '../services/iter18.js';
import { can } from '../utils/permissions.js';

export async function render(root, ctx = {}) {
  root.replaceChildren();
  if (ctx.role === 'client') return renderRequest(root, ctx);
  const pending = h('div', { 'aria-live': 'polite' });
  if (['super_admin', 'admin'].includes(ctx.role)) drawPending(pending, ctx);
  const out = h('div', { 'aria-live': 'polite' });
  const linkSel = h('select', { id: 'i18-us-link', required: true });
  const orgSel = h('select', { id: 'i18-us-org', required: true });
  const leadSel = h('select', { id: 'i18-us-lead' });
  const roleSel = h('select', { id: 'i18-us-role', required: true });
  const email = h('input', { id: 'i18-us-email', type: 'email', required: true, placeholder: 'nombre@dominio.com', autocomplete: 'off' });
  const provBox = h('fieldset', { class: 'i18-fs', hidden: true }, h('legend', {}, 'Médicos que atenderá la secretaria'));
  const book = h('input', { type: 'checkbox', checked: true, id: 'i18-us-book' });
  const wa = h('input', { type: 'checkbox', id: 'i18-us-wa' });
  const permBox = h('div', { hidden: true },
    h('label', {}, book, ' Puede dar y cambiar citas'), h('br'), h('label', {}, wa, ' Puede ver y enviar los mensajes de WhatsApp'));
  const hint = h('p', { class: 'i18-sub', 'aria-live': 'polite' });
  const send = h('button', { class: 'i18-btn', type: 'submit' }, 'Crear usuario');
  const orgLabel = h('label', {}, 'Cliente', orgSel);
  const leadLabel = h('label', { hidden: true }, 'Prospecto', leadSel);
  const roleLabel = h('label', {}, 'Rol', roleSel);
  let orgs = [], roles = [], provs = [], leads = [];

  const LINKS = [
    ['cliente', 'Un cliente (Médico o Secretaria)', ['super_admin', 'admin'].includes(ctx.role)],
    ['prospecto', 'Un prospecto (todavía no es cliente)', can('users.prospect', ctx.role)],
    ['sofa', 'El equipo SOFA (personal interno)', ['super_admin', 'admin'].includes(ctx.role)]
  ].filter((x) => x[2]);
  linkSel.replaceChildren(...LINKS.map(([v, l]) => h('option', { value: v }, l)));

  const link = () => linkSel.value;
  function paintLink() {
    const k = link();
    orgLabel.hidden = k !== 'cliente'; leadLabel.hidden = k !== 'prospecto'; roleLabel.hidden = k === 'prospecto';
    const list = k === 'sofa' ? orgs.filter((o) => o.kind === 'operator') : orgs.filter((o) => o.kind === 'client');
    orgSel.replaceChildren(h('option', { value: '' }, k === 'sofa' ? 'SOFA' : 'Elija el cliente'), ...list.map((x) => h('option', { value: x.id }, x.trade_name || x.legal_name)));
    if (k === 'sofa' && list.length) orgSel.value = list[0].id;
    hint.textContent = k === 'prospecto'
      ? 'El prospecto solo verá el avance de su incorporación (oportunidad y habilitación). Cuando se convierta en cliente, su usuario pasa solo a Médico.'
      : k === 'sofa' ? 'Personal interno de SOFA: elija el rol según su trabajo.' : 'Médico: ve su consultorio completo. Secretaria: solo lo de los médicos que se le asignen.';
    paintRoles();
  }
  function paintRoles() {
    const staff = link() === 'sofa';
    roleSel.replaceChildren(h('option', { value: '' }, 'Elija un rol'),
      ...roles.filter((r) => r.is_staff === staff && r.code !== 'prospect').map((r) => h('option', { value: r.code }, r.name)));
    paintProviders();
  }
  function paintProviders() {
    const isCap = roleSel.value === 'capturer' && link() === 'cliente';
    provBox.hidden = !isCap; permBox.hidden = !isCap;
    provBox.replaceChildren(h('legend', {}, 'Médicos que atenderá la secretaria'),
      ...provs.filter((p) => p.organization_id === orgSel.value).map((p) =>
        h('label', { class: 'i18-chk' }, h('input', { type: 'checkbox', value: p.id, name: 'prov' }), ' ' + p.full_name)));
    if (isCap && !provBox.querySelector('input')) provBox.append(note('Este cliente aún no tiene médicos activos. Registre primero al médico en la ficha del cliente.', 'error'));
  }
  linkSel.addEventListener('change', paintLink);
  orgSel.addEventListener('change', paintProviders);
  roleSel.addEventListener('change', paintProviders);

  const form = h('form', { class: 'i18-form', novalidate: true },
    h('label', {}, 'Vincular a', linkSel), hint, orgLabel, leadLabel, roleLabel, h('label', {}, 'Correo', email), provBox, permBox, send);
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault(); out.replaceChildren();
    const k = link();
    const ids = [...provBox.querySelectorAll('input[name=prov]:checked')].map((i) => i.value);
    if (!email.value.trim()) return out.replaceChildren(note('Escriba el correo del usuario.', 'error'));
    if (k === 'prospecto' && !leadSel.value) return out.replaceChildren(note('Elija el prospecto. Si no aparece, créelo primero en Prospectos.', 'error'));
    if (k !== 'prospecto' && (!orgSel.value || !roleSel.value)) return out.replaceChildren(note(k === 'sofa' ? 'Elija el rol.' : 'Elija el cliente y el rol.', 'error'));
    if (roleSel.value === 'capturer' && k === 'cliente' && !ids.length) return out.replaceChildren(note('Marque al menos un médico para la secretaria.', 'error'));
    send.disabled = true;
    try {
      const body = k === 'prospecto'
        ? { email: email.value.trim(), lead_id: leadSel.value }
        : { email: email.value.trim(), organization_id: orgSel.value, role_code: roleSel.value, provider_ids: ids, can_book: book.checked, can_whatsapp: wa.checked };
      const r = await invoke('crear-usuario', body);
      out.replaceChildren(resultado(r)); email.value = ''; paintLink();
    } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { send.disabled = false; }
  });

  root.append(pending, h('div', { class: 'i18-wrap' }, h('h2', {}, 'Crear usuario'),
    note('Solo necesita el correo, a quién se vincula y el rol. Se genera una clave temporal que usted entrega al usuario; en su primer acceso el sistema le pedirá cambiarla.'),
    form, out));

  await guarded(out, async () => {
    const [o, r, p] = await Promise.all([
      supabase.from('organizations').select('id, kind, legal_name, trade_name').order('legal_name'),
      supabase.from('roles').select('code, name, is_staff, sort_order').order('sort_order'),
      supabase.from('providers').select('id, organization_id, full_name').eq('is_active', true).order('full_name')]);
    for (const x of [o, r, p]) if (x.error) throw new Error(x.error.message);
    orgs = o.data; roles = r.data; provs = p.data;
    if (LINKS.some((x) => x[0] === 'prospecto')) {
      leads = await rpc('prospect_options').catch(() => []);
      leadSel.replaceChildren(h('option', { value: '' }, leads.length ? 'Elija el prospecto' : 'No hay prospectos sin convertir'),
        ...leads.map((l) => h('option', { value: l.id }, [l.company, l.contact].filter(Boolean).join(' · '))));
    }
    paintLink();
    return true;
  });
}
export default render;
export const mount = render;

const ST = { pendiente: ['Pendiente', 'st-req'], aprobada: ['Aprobada', 'st-ok'], rechazada: ['Rechazada', 'st-bad'], cancelada: ['Cancelada', 'st-none'] };
const pill = (st) => h('span', { class: `ac-pill ${(ST[st] || [st, 'st-none'])[1]}` }, (ST[st] || [st])[0]);
const when = (iso) => (iso ? new Date(iso).toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) : '—');

/** Super Admin / Administrador: solicitudes de los consultorios. Solo el Super Admin aprueba o rechaza. */
async function drawPending(box, ctx) {
  const l = await guarded(box, () => rpc('user_requests_list', { p_status: 'pendiente' }));
  if (!l) return;
  if (!l.length) { box.replaceChildren(); return; }
  const canDecide = can('users.approve', ctx.role);
  const out = h('div', { 'aria-live': 'polite' });
  box.replaceChildren(h('section', { class: 'i18-card ur-pending' }, h('h3', { style: 'margin-top:0' }, `Solicitudes de usuario por autorizar (${l.length})`),
    canDecide ? '' : note('Solo el Super Admin aprueba o rechaza. Usted las ve para dar seguimiento.'),
    h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Consultorio', 'Persona', 'Tipo', 'Médicos', 'Pidió', ''].map((x) => h('th', {}, x)))),
      h('tbody', {}, l.map((r) => h('tr', {}, h('td', {}, r.organization), h('td', {}, h('strong', {}, r.name), h('div', { class: 'i18-sub' }, r.email), r.notes ? h('div', { class: 'i18-sub' }, r.notes) : ''),
        h('td', {}, r.role_name || r.role, r.role === 'capturer' ? h('div', { class: 'i18-sub' }, [r.can_book ? 'citas' : null, r.can_whatsapp ? 'WhatsApp' : null].filter(Boolean).join(' · ') || 'sin citas ni WhatsApp') : ''),
        h('td', {}, (r.providers || []).join(', ') || '—'), h('td', {}, r.requested_by || '—', h('div', { class: 'i18-sub' }, when(r.at))),
        h('td', {}, canDecide ? [h('button', { class: 'i18-btn', type: 'button', onclick: (e) => approve(r, e.target) }, 'Aprobar y crear'), ' ',
          h('button', { class: 'i18-link', type: 'button', onclick: () => reject(r) }, 'Rechazar')] : pill(r.status))))))), out));
  async function approve(r, btn) {
    if (!confirm(`Se creará el usuario ${r.email} (${r.role_name || r.role}) para ${r.organization}. ¿Continuar?`)) return;
    btn.disabled = true;
    try { const res = await invoke('crear-usuario', { request_id: r.id }); out.replaceChildren(resultado(res)); await drawPending(box, ctx); box.append(out); }
    catch (e) { out.replaceChildren(note(e.message, 'error')); btn.disabled = false; }
  }
  async function reject(r) {
    const why = prompt(`Motivo del rechazo para ${r.organization} (lo verá el consultorio):`);
    if (why === null) return;
    try { await rpc('reject_user_request', { p_id: r.id, p_reason: why }); await drawPending(box, ctx); box.append(note(`Solicitud de ${r.email} rechazada.`, 'ok')); }
    catch (e) { out.replaceChildren(note(e.message, 'error')); }
  }
}

/** Médico o Centro: pide el usuario; SOFA lo autoriza */
async function renderRequest(root, ctx) {
  const out = h('div', { 'aria-live': 'polite' });
  const mine = h('div', { 'aria-live': 'polite' });
  const orgSel = h('select', { id: 'ur-org' });
  const type = h('select', { id: 'ur-type' }, h('option', { value: 'capturer' }, 'Secretaria (solo lo de los médicos que marque)'), h('option', { value: 'client' }, 'Otro médico del consultorio'));
  const name = h('input', { id: 'ur-name', maxlength: '120', placeholder: 'Nombre y apellido' });
  const email = h('input', { id: 'ur-email', type: 'email', placeholder: 'nombre@dominio.com', autocomplete: 'off' });
  const notes = h('textarea', { id: 'ur-notes', rows: '2', maxlength: '500', placeholder: 'Opcional: horario, sede u otra indicación para SOFA' });
  const provBox = h('fieldset', { class: 'i18-fs' }, h('legend', {}, 'Médicos que atenderá la secretaria'));
  const book = h('input', { type: 'checkbox', checked: true, id: 'ur-book' });
  const wa = h('input', { type: 'checkbox', id: 'ur-wa' });
  const perm = h('div', {}, h('label', { class: 'i18-chk' }, book, ' Puede dar y cambiar citas'), h('br'), h('label', { class: 'i18-chk' }, wa, ' Puede ver y enviar los mensajes de WhatsApp'));
  const send = h('button', { class: 'i18-btn', type: 'submit' }, 'Enviar solicitud a SOFA');
  let provs = [];
  const paint = () => {
    const cap = type.value === 'capturer';
    provBox.hidden = !cap; perm.hidden = !cap;
    provBox.replaceChildren(h('legend', {}, 'Médicos que atenderá la secretaria'),
      ...provs.filter((p) => p.organization_id === orgSel.value).map((p) => h('label', { class: 'i18-chk' }, h('input', { type: 'checkbox', value: p.id, name: 'prov' }), ' ' + p.full_name)));
  };
  type.addEventListener('change', paint); orgSel.addEventListener('change', paint);
  const form = h('form', { class: 'i18-form', novalidate: true },
    h('label', { for: 'ur-org' }, 'Consultorio', orgSel), h('label', { for: 'ur-type' }, 'Tipo de usuario', type),
    h('label', { for: 'ur-name' }, 'Nombre completo', name), h('label', { for: 'ur-email' }, 'Correo', email), provBox, perm,
    h('label', { for: 'ur-notes' }, 'Notas para SOFA', notes), send);
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault(); out.replaceChildren();
    const ids = [...provBox.querySelectorAll('input[name=prov]:checked')].map((i) => i.value);
    send.disabled = true;
    try {
      await rpc('request_user', { p_org: orgSel.value, p_email: email.value, p_full_name: name.value, p_role: type.value,
        p_providers: type.value === 'capturer' ? ids : [], p_can_book: book.checked, p_can_whatsapp: wa.checked, p_notes: notes.value || null });
      out.replaceChildren(note(`Solicitud enviada. SOFA la revisa y le avisa; cuando la apruebe, SOFA le entregará la clave temporal de ${email.value.trim()}.`, 'ok'));
      name.value = ''; email.value = ''; notes.value = ''; await drawMine();
    } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { send.disabled = false; }
  });
  async function drawMine() {
    const l = await guarded(mine, () => rpc('user_requests_list', { p_status: null }));
    if (!l) return;
    mine.replaceChildren(l.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Fecha', 'Persona', 'Tipo', 'Estado', 'Respuesta de SOFA', ''].map((x) => h('th', {}, x)))),
      h('tbody', {}, l.map((r) => h('tr', {}, h('td', {}, when(r.at)), h('td', {}, r.name, h('div', { class: 'i18-sub' }, r.email)), h('td', {}, r.role_name || r.role),
        h('td', {}, pill(r.status)), h('td', {}, r.decision_note || (r.decided_at ? when(r.decided_at) : '—')),
        h('td', {}, r.status === 'pendiente' ? h('button', { class: 'i18-link', type: 'button', onclick: async () => {
          try { await rpc('cancel_user_request', { p_id: r.id }); await drawMine(); } catch (e) { out.replaceChildren(note(e.message, 'error')); } } }, 'Cancelar') : '')))))) : note('Todavía no ha pedido usuarios.'));
  }
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Solicitar usuario'),
    note('Para cuidar quién entra a sus datos, los usuarios los autoriza SOFA. Llene la solicitud: cuando el Super Admin la apruebe se crea la cuenta y SOFA le entrega la clave temporal por un medio privado.'),
    form, out, h('h3', {}, 'Mis solicitudes'), mine));
  await guarded(out, async () => {
    const [o, p] = await Promise.all([
      supabase.from('organizations').select('id, kind, legal_name, trade_name').eq('kind', 'client').order('legal_name'),
      supabase.from('providers').select('id, organization_id, full_name').eq('is_active', true).order('full_name')]);
    for (const x of [o, p]) if (x.error) throw new Error(x.error.message);
    provs = p.data;
    orgSel.replaceChildren(...o.data.map((x) => h('option', { value: x.id }, x.trade_name || x.legal_name)));
    paint();
    return true;
  });
  await drawMine();
}

function resultado(r) {
  const copy = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Copiar clave');
  copy.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(r.temporary_password); copy.textContent = 'Copiada'; } catch (_) { copy.textContent = 'Seleccione y copie con Ctrl+C'; }
  });
  return h('div', { class: 'i18-card', role: 'status' },
    h('strong', {}, `Usuario creado: ${r.email}${r.role === 'prospect' ? ' (Prospecto)' : ''}`),
    h('p', {}, 'Clave temporal (se muestra una sola vez):'),
    h('pre', { class: 'i18-pre' }, r.temporary_password), copy,
    note('Entréguela por un medio privado (en persona o mensaje directo). No la envíe en grupos ni la guarde en correos. El usuario deberá cambiarla al entrar.', 'info'));
}
