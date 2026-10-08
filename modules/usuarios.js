/** SOFA · Alta de usuarios: solo correo + rol. La clave temporal la genera el servidor y se muestra una vez. */
import { supabase, invoke, h, note, guarded } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const orgSel = h('select', { id: 'i18-us-org', required: true });
  const roleSel = h('select', { id: 'i18-us-role', required: true });
  const email = h('input', { id: 'i18-us-email', type: 'email', required: true, placeholder: 'nombre@dominio.com', autocomplete: 'off' });
  const provBox = h('fieldset', { class: 'i18-fs', hidden: true }, h('legend', {}, 'Médicos que atenderá la secretaria'));
  const book = h('input', { type: 'checkbox', checked: true, id: 'i18-us-book' });
  const wa = h('input', { type: 'checkbox', id: 'i18-us-wa' });
  const permBox = h('div', { hidden: true },
    h('label', {}, book, ' Puede dar y cambiar citas'), h('br'), h('label', {}, wa, ' Puede ver y enviar los mensajes de WhatsApp'));
  const send = h('button', { class: 'i18-btn', type: 'submit' }, 'Crear usuario');
  let orgs = [], roles = [], provs = [];

  const orgKind = () => (orgs.find((o) => o.id === orgSel.value) || {}).kind;
  function paintRoles() {
    const staff = orgKind() === 'operator';
    roleSel.replaceChildren(h('option', { value: '' }, 'Elija un rol'),
      ...roles.filter((r) => r.is_staff === staff).map((r) => h('option', { value: r.code }, r.name)));
    paintProviders();
  }
  function paintProviders() {
    const isCap = roleSel.value === 'capturer';
    provBox.hidden = !isCap; permBox.hidden = !isCap;
    provBox.replaceChildren(h('legend', {}, 'Médicos que atenderá la secretaria'),
      ...provs.filter((p) => p.organization_id === orgSel.value).map((p) =>
        h('label', { class: 'i18-chk' }, h('input', { type: 'checkbox', value: p.id, name: 'prov' }), ' ' + p.full_name)));
    if (isCap && !provBox.querySelector('input')) provBox.append(note('Este cliente aún no tiene médicos activos. Registre primero al médico.', 'error'));
  }
  orgSel.addEventListener('change', paintRoles);
  roleSel.addEventListener('change', paintProviders);

  const form = h('form', { class: 'i18-form', novalidate: true },
    h('label', {}, 'Organización', orgSel), h('label', {}, 'Rol', roleSel), h('label', {}, 'Correo', email), provBox, permBox, send);
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault(); out.replaceChildren();
    const ids = [...provBox.querySelectorAll('input[name=prov]:checked')].map((i) => i.value);
    if (!orgSel.value || !roleSel.value || !email.value.trim()) return out.replaceChildren(note('Complete la organización, el rol y el correo.', 'error'));
    if (roleSel.value === 'capturer' && !ids.length) return out.replaceChildren(note('Marque al menos un médico para la secretaria.', 'error'));
    send.disabled = true;
    try {
      const r = await invoke('crear-usuario', { email: email.value.trim(), organization_id: orgSel.value, role_code: roleSel.value, provider_ids: ids, can_book: book.checked, can_whatsapp: wa.checked });
      out.replaceChildren(resultado(r)); form.reset(); paintRoles();
    } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { send.disabled = false; }
  });

  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Crear usuario'),
    note('Solo necesita el correo y el rol. Se genera una clave temporal que usted entrega al usuario; en su primer acceso el sistema le pedirá cambiarla.'),
    form, out));

  await guarded(out, async () => {
    const [o, r, p] = await Promise.all([
      supabase.from('organizations').select('id, kind, legal_name, trade_name').order('legal_name'),
      supabase.from('roles').select('code, name, is_staff, sort_order').order('sort_order'),
      supabase.from('providers').select('id, organization_id, full_name').eq('is_active', true).order('full_name')]);
    for (const x of [o, r, p]) if (x.error) throw new Error(x.error.message);
    orgs = o.data; roles = r.data; provs = p.data;
    orgSel.replaceChildren(h('option', { value: '' }, 'Elija la organización'),
      ...orgs.map((x) => h('option', { value: x.id }, (x.kind === 'operator' ? 'SOFA (personal interno) · ' : '') + (x.trade_name || x.legal_name))));
    paintRoles();
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
    h('strong', {}, `Usuario creado: ${r.email}`),
    h('p', {}, 'Clave temporal (se muestra una sola vez):'),
    h('pre', { class: 'i18-pre' }, r.temporary_password), copy,
    note('Entréguela por un medio privado (en persona o mensaje directo). No la envíe en grupos ni la guarde en correos. El usuario deberá cambiarla al entrar.', 'info'));
}
