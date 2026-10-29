/** SOFA · Mis asistentes: el médico decide, por cada asistente de consulta, si puede mover el
 *  flujo de pacientes y si puede leer y escribir la historia clínica. Calcado de mis-secretarias.js. */
import { rpc, providerOptions, h, note, guarded } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const msg = h('div', { 'aria-live': 'polite' });
  const out = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Mis asistentes'),
    h('p', {}, 'Marque lo que cada asistente de consulta puede hacer en su consultorio. Los cambios aplican de inmediato.'), top, msg, out);
  const provs = await guarded(top, providerOptions);
  if (!provs) return;
  if (!provs.length) { top.replaceChildren(note('No tiene médicos asignados. Pida al Administrador que le asigne su consultorio.')); return; }
  const sel = h('select', { id: 'ma-prov' }, provs.map((p) => h('option', { value: p.id }, p.full_name)));
  top.replaceChildren(h('div', { class: 'i18-form' }, h('label', { for: 'ma-prov' }, 'Médico'), sel));

  async function save(row, flow, hc) {
    msg.replaceChildren();
    try {
      await rpc('set_consult_assistant_permissions', { p_user: row.user_id, p_provider: sel.value, p_can_flow: flow.checked, p_can_hc: hc.checked });
      msg.replaceChildren(note(`Permisos de ${row.name} guardados.`));
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); await load(); }
  }
  async function load() {
    const rows = await guarded(out, () => rpc('list_consult_assistants', { p_provider: sel.value }));
    if (!rows) return;
    if (!rows.length) { out.replaceChildren(note('Este médico no tiene asistentes de consulta asignados. Pida al Administrador que lo asigne en «Usuarios y roles».')); return; }
    out.replaceChildren(h('div', { class: 'i18-list' }, rows.map((r) => {
      const flow = h('input', { type: 'checkbox', checked: r.can_flow });
      const hc = h('input', { type: 'checkbox', checked: r.can_hc });
      flow.addEventListener('change', () => save(r, flow, hc));
      hc.addEventListener('change', () => save(r, flow, hc));
      return h('section', { class: 'i18-card' }, h('h3', {}, r.name + (r.active === false ? ' (inactivo)' : '')),
        h('label', { class: 'i18-chk' }, flow, ' Puede mover el flujo de pacientes (llamar a consulta, devolver a espera)'),
        h('label', { class: 'i18-chk' }, hc, ' Puede leer y escribir la historia clínica'));
    })));
  }
  sel.addEventListener('change', load);
  await load();
}
