/** SOFA · 3.9 · Registro de horas del equipo SOFA por cliente (opcional). Sirve para medir horas por cliente y margen. */
import { rpc, h, fmtDate, note, guarded, clientOptions, clientName } from '../services/iter18.js';

const ACT = { facturacion: 'Facturación', glosas: 'Glosas', codificacion: 'Codificación', habilitacion: 'Habilitación', renegociacion: 'Renegociación',
  auditoria: 'Auditoría', comercial: 'Comercial', administrativa: 'Administrativa', otro: 'Otro' };

export async function render(root) {
  root.replaceChildren();
  const org = h('select', { id: 'mh-h-org' }, h('option', { value: '' }, 'Elija un cliente'));
  const act = h('select', { id: 'mh-h-act' }, Object.entries(ACT).map(([k, v]) => h('option', { value: k }, v)));
  const hrs = h('input', { type: 'number', id: 'mh-h-hrs', min: '0.25', max: '16', step: '0.25', value: '1', inputmode: 'decimal' });
  const day = h('input', { type: 'date', id: 'mh-h-day', value: new Date().toISOString().slice(0, 10) });
  const nt = h('input', { type: 'text', id: 'mh-h-note', maxlength: '300' });
  const save = h('button', { class: 'i18-btn', type: 'button' }, 'Registrar');
  const out = h('div', { 'aria-live': 'polite' });
  const list = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Mis horas'),
    h('p', { class: 'i18-sub' }, 'Registro opcional del tiempo dedicado a cada cliente (en cuartos de hora). Con él, Dirección ve horas por cliente y margen.'),
    h('div', { class: 'i18-form' }, h('label', { for: 'mh-h-org' }, 'Cliente'), org, h('label', { for: 'mh-h-act' }, 'Actividad'), act,
      h('label', { for: 'mh-h-hrs' }, 'Horas'), hrs, h('label', { for: 'mh-h-day' }, 'Fecha'), day, h('label', { for: 'mh-h-note' }, 'Nota (opcional)'), nt, h('div', {}, save), out), list));
  try { (await clientOptions()).forEach((c) => org.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { out.replaceChildren(note(e.message, 'error')); }

  async function load() {
    const d = await guarded(list, () => rpc('staff_time_mine', { p_days: 14 }));
    if (!d) return;
    const total = d.reduce((a, x) => a + Number(x.hours), 0);
    list.replaceChildren(h('h3', {}, `Últimos 14 días: ${total} hora(s)`), d.length ? h('ul', {}, d.map((x) => {
      const del = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': 'Borrar registro' }, 'Borrar');
      del.addEventListener('click', async () => { try { await rpc('staff_time_delete', { p_id: x.id }); load(); } catch (e) { out.replaceChildren(note(e.message, 'error')); } });
      return h('li', {}, `${fmtDate(x.work_date)} · ${x.client} · ${ACT[x.activity] || x.activity} · ${x.hours} h${x.note ? ` · ${x.note}` : ''} `, del);
    })) : note('Sin registros.'));
  }
  save.addEventListener('click', async () => {
    save.disabled = true; out.replaceChildren();
    try { await rpc('staff_time_add', { p_org: org.value || null, p_hours: Number(hrs.value), p_activity: act.value, p_date: day.value || null, p_note: nt.value || null }); nt.value = ''; out.replaceChildren(note('Registrado.')); await load(); }
    catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { save.disabled = false; }
  });
  await load();
}
export default render;
