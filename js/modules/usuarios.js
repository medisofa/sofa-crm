/** SOFA · Alta de usuarios: correo + vínculo + rol. La clave temporal la genera el servidor y se muestra una vez.
 *  2.1 · Al crear se vincula a un CLIENTE (Médico o Secretaria), a un PROSPECTO (rol Prospecto: solo ve su incorporación
 *  y pasa a Médico cuando se convierte en cliente) o al EQUIPO SOFA. */
import { supabase, invoke, rpc, h, note, guarded } from '../services/iter18.js';
import { can } from '../utils/permissions.js';

export async function render(root, ctx = {}) {
  root.replaceChildren();
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
    ['cliente', 'Un cliente (Médico o Secretaria)', true],
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

  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Crear usuario'),
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
