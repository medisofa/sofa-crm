/** SOFA · 4.2 · Iteración 52 · Verificación del día siguiente.
 *  Citas ARS de mañana sin elegibilidad verificada o sin autorización: se resuelven hoy para evitar glosas. */
import { rpc, h, note, guarded, kpi } from '../services/iter18.js';

const SRC = { portal_ars: 'Portal de la ARS', sisalril: 'SISALRIL', senasa: 'SeNaSa', telefono: 'Teléfono', otro: 'Otro' };
const NEED = { elegibilidad: 'Elegibilidad', autorizacion: 'Autorización', nss: 'NSS' };

export async function render(root) {
  root.replaceChildren();
  const day = h('input', { type: 'date', id: 'vf-day' });
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Verificación del día siguiente'),
    h('p', { class: 'i18-sub' }, 'Las citas con ARS de mañana: verifique que el afiliado esté vigente y que tenga autorización. Evita las glosas por «afiliado no vigente» y «falta de autorización».'),
    h('div', { class: 'i18-bar' }, h('label', { for: 'vf-day' }, 'Fecha', day)), box));

  async function load() {
    const d = await guarded(box, () => rpc('next_day_checklist', { p_date: day.value || null, p_provider: null }));
    if (!d) return;
    if (!day.value) day.value = d.date;
    const k = d.kpi_30d || {};
    box.replaceChildren(h('div', { class: 'i18-kpis' }, kpi('Sin verificar', String(d.pending)), kpi('Sin autorización', String(d.no_authorization)), kpi('No elegibles', String(d.not_eligible)),
      kpi('Atendidas con elegibilidad verificada (30 días)', k.pct == null ? '—' : `${k.pct} %`, `${k.verified || 0} de ${k.attended || 0}`)),
      d.items.length ? h('div', { class: 'i18-list' }, d.items.map(card)) : note('No hay citas con ARS para esa fecha.'));
  }

  function card(a) {
    const out = h('div', { 'aria-live': 'polite' });
    const head = [h('strong', {}, `${a.time || '—'} · ${a.patient}`), h('div', { class: 'i18-sub' }, `${a.ars || ''} · ${a.provider}${a.member ? ` · NSS ${a.member}` : ''}${a.phone ? ` · ${a.phone}` : ''}`),
      a.needs.length ? h('div', {}, 'Falta: ', a.needs.map((n) => h('span', { class: 'pa-sev bloquea', style: 'margin-right:4px' }, NEED[n] || n))) : h('div', { class: 'ok' }, 'Listo para atender.'),
      a.eligibility === 'no_elegible' ? note('No elegible: avise al paciente (puede atenderse como privado).', 'error') : null];
    if (!a.can_edit) return h('div', { class: 'i18-card' }, ...head);
    const kids = [];
    if (a.needs.includes('elegibilidad')) {
      const src = h('select', { 'aria-label': 'Dónde se verificó' }, Object.entries(SRC).map(([v, t]) => h('option', { value: v }, t)));
      const ref = h('input', { type: 'text', maxlength: '60', placeholder: 'Número de confirmación', 'aria-label': 'Referencia' });
      const ok = h('button', { class: 'i18-btn', type: 'button' }, 'Vigente');
      const no = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'No elegible');
      const set = (st) => async () => { try { await rpc('set_eligibility', { p_appointment: a.id, p_status: st, p_source: src.value, p_reference: ref.value, p_authorization_date: null }); load(); } catch (e) { out.replaceChildren(note(e.message, 'error')); } };
      ok.addEventListener('click', set('verificada')); no.addEventListener('click', set('no_elegible'));
      kids.push(h('div', { class: 'i18-bar' }, src, ref, ok, no));
    }
    if (a.needs.includes('autorizacion')) {
      const num = h('input', { type: 'text', maxlength: '40', placeholder: 'Número de autorización', 'aria-label': 'Número de autorización' });
      const sv = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Guardar autorización');
      sv.addEventListener('click', async () => { try { await rpc('set_appointment_authorization', { p_appointment: a.id, p_number: num.value, p_date: null }); load(); } catch (e) { out.replaceChildren(note(e.message, 'error')); } });
      kids.push(h('div', { class: 'i18-bar' }, num, sv));
    }
    return h('div', { class: 'i18-card' }, ...head, ...kids, out);
  }

  day.addEventListener('change', load);
  await load();
}
export default render;
