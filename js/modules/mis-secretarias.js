/** SOFA · Mis secretarias: el médico decide, por cada secretaria, si puede dar citas y si ve los mensajes de WhatsApp. */
import { rpc, providerOptions, h, note, guarded } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const msg = h('div', { 'aria-live': 'polite' });
  const out = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Mis secretarias'),
    h('p', {}, 'Marque lo que cada secretaria puede hacer en su consultorio. Los cambios aplican de inmediato.'), top, msg, out);
  const provs = await guarded(top, providerOptions);
  if (!provs) return;
  if (!provs.length) { top.replaceChildren(note('No tiene médicos asignados. Pida al Administrador que le asigne su consultorio.')); return; }
  const sel = h('select', { id: 'ms-prov' }, provs.map((p) => h('option', { value: p.id }, p.full_name)));
  top.replaceChildren(h('div', { class: 'i18-form' }, h('label', { for: 'ms-prov' }, 'Médico'), sel));

  async function save(row, book, wa) {
    msg.replaceChildren();
    try {
      await rpc('set_assistant_permissions', { p_user: row.user_id, p_provider: sel.value, p_can_book: book.checked, p_can_whatsapp: wa.checked });
      msg.replaceChildren(note(`Permisos de ${row.name} guardados.`));
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); await load(); }
  }
  async function load() {
    const rows = await guarded(out, () => rpc('list_assistants', { p_provider: sel.value }));
    if (!rows) return;
    if (!rows.length) { out.replaceChildren(note('Este médico no tiene secretarias asignadas. Pida al Administrador que la asigne en «Usuarios y roles».')); return; }
    out.replaceChildren(h('div', { class: 'i18-list' }, rows.map((r) => {
      const book = h('input', { type: 'checkbox', checked: r.can_book });
      const wa = h('input', { type: 'checkbox', checked: r.can_whatsapp });
      book.addEventListener('change', () => save(r, book, wa));
      wa.addEventListener('change', () => save(r, book, wa));
      return h('section', { class: 'i18-card' }, h('h3', {}, r.name + (r.active === false ? ' (inactiva)' : '')),
        h('label', { class: 'i18-chk' }, book, ' Puede dar y cambiar citas'),
        h('label', { class: 'i18-chk' }, wa, ' Puede ver y enviar los mensajes de WhatsApp'));
    })));
  }
  sel.addEventListener('change', load);
  await load();
}
export default render;
