/** SOFA · Mis secretarias: el médico decide, por cada secretaria, si puede dar citas y si ve los mensajes de WhatsApp. */
import { rpc, providerOptions, h, note, guarded } from '../services/iter18.js';
import { myAgendaScopes, setAssistantCenter } from '../services/consultorio.js';

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

  async function save(row, book, wa, pay) {
    msg.replaceChildren();
    try {
      await rpc('set_assistant_permissions', { p_user: row.user_id, p_provider: sel.value, p_can_book: book.checked, p_can_whatsapp: wa.checked, p_can_payments: pay.checked });
      msg.replaceChildren(note(`Permisos de ${row.name} guardados.`));
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); await load(); }
  }
  // 244 · Centro de cada secretaria: «Todos los centros» o uno solo (opción B).
  let centersByProvider = {};
  try { centersByProvider = (await myAgendaScopes()).centers_by_provider || {}; } catch { centersByProvider = {}; }
  async function saveCenter(row, centerSel) {
    msg.replaceChildren();
    try {
      await setAssistantCenter(row.user_id, sel.value, centerSel.value || null);
      msg.replaceChildren(note(`${row.name} ahora maneja la agenda en: ${centerSel.selectedOptions[0].textContent}.`));
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); await load(); }
  }
  async function load() {
    const rows = await guarded(out, () => rpc('list_assistants', { p_provider: sel.value }));
    if (!rows) return;
    if (!rows.length) { out.replaceChildren(note('Este médico no tiene secretarias asignadas. Pida al Administrador que la asigne en «Usuarios y roles».')); return; }
    out.replaceChildren(h('div', { class: 'i18-list' }, rows.map((r) => {
      const book = h('input', { type: 'checkbox', checked: r.can_book });
      const wa = h('input', { type: 'checkbox', checked: r.can_whatsapp });
      const pay = h('input', { type: 'checkbox', checked: r.can_payments });
      book.addEventListener('change', () => save(r, book, wa, pay));
      wa.addEventListener('change', () => save(r, book, wa, pay));
      pay.addEventListener('change', () => save(r, book, wa, pay));
      const centers = centersByProvider[sel.value] || [];
      const cid = `ms-c-${r.user_id}`;
      const centerSel = h('select', { id: cid }, [h('option', { value: '' }, 'Todos los centros del médico'),
        ...centers.map((c) => h('option', { value: c.id, selected: c.id === r.center_id }, c.name))]);
      centerSel.addEventListener('change', () => saveCenter(r, centerSel));
      return h('section', { class: 'i18-card' }, h('h3', {}, r.name + (r.active === false ? ' (inactiva)' : '')),
        h('label', { class: 'i18-chk' }, book, ' Puede dar y cambiar citas'),
        h('label', { class: 'i18-chk' }, wa, ' Puede ver y enviar los mensajes de WhatsApp'),
        h('label', { class: 'i18-chk' }, pay, ' Puede registrar pagos de pacientes'),
        centers.length > 1 ? h('div', { class: 'i18-form' }, h('label', { for: cid }, 'Maneja la agenda en'), centerSel,
          h('small', {}, 'Con un solo centro, la secretaria no ve las citas de los otros centros; solo ve esas horas como «No disponible».')) : null);
    })));
  }
  sel.addEventListener('change', load);
  await load();
}
export default render;
