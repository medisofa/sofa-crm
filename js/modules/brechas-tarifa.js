/** SOFA · 3.5 · Iteración 45 · Brechas de tarifa entre las ARS del mismo médico.
 *  Solo con sus propios tarifarios vigentes (nunca datos de otros clientes). Base de la carpeta de negociación. */
import { rpc, h, money, note, guarded, kpi, clientOptions, clientName } from '../services/iter18.js';

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const client = ctx.role === 'client';
  const sel = h('select', { id: 'bt-org' }, h('option', { value: '' }, 'Elija un cliente'));
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Brechas de tarifa entre ARS'),
    h('p', { class: 'i18-sub' }, 'Cuánto deja de ganar el médico cuando una ARS le paga menos que otra por el mismo procedimiento, con su volumen de los últimos 12 meses.'),
    client ? null : h('div', { class: 'i18-bar' }, h('label', { for: 'bt-org' }, 'Cliente', sel)), box));
  if (!client) { try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { box.replaceChildren(note(e.message, 'error')); } }

  async function load() {
    const org = client ? ctx.membership?.organization_id : sel.value;
    if (!org) { box.replaceChildren(note('Elija un cliente para ver sus brechas.')); return; }
    const d = await guarded(box, () => rpc('tariff_gaps', { p_org: org, p_provider: null }));
    if (!d) return;
    box.replaceChildren(...(d.providers.length ? d.providers.map(provider) : [note('El cliente no tiene médicos activos.')]), h('p', { class: 'i18-sub' }, d.note));
  }

  function provider(p) {
    return h('section', { class: 'i18-card' }, h('h3', {}, p.name),
      h('div', { class: 'i18-kpis' }, kpi('Brecha anual estimada', money(p.annual_total)), kpi('Procedimientos con brecha', String(p.gaps.length)), kpi('Por contratar', String(p.not_contracted.length))),
      p.gaps.length ? table(['Procedimiento', 'ARS', 'Le paga', 'Mejor ARS', 'Mejor tarifa', 'Brecha', 'Cant. 12 meses', 'Brecha anual'],
        p.gaps.map((g) => [`${g.code ? g.code + ' · ' : ''}${g.procedure}`, g.ars, money(g.amount), g.best_ars, money(g.best), `${money(g.gap)} (${g.gap_pct} %)`, String(g.qty12), money(g.annual)]), [2, 4, 5, 6, 7])
        : note('Sin brechas: el médico no tiene el mismo procedimiento con tarifas distintas entre sus ARS.'),
      p.not_contracted.length ? [h('h4', {}, 'Procedimientos sin tarifa con ARS donde ya está codificado'),
        table(['Procedimiento', 'ARS', 'Referencia (su mejor tarifa)'], p.not_contracted.map((n) => [`${n.code ? n.code + ' · ' : ''}${n.procedure}`, n.ars, n.reference ? money(n.reference) : '—']), [2])] : null,
      p.volume.length ? [h('h4', {}, 'Volumen y tasa de glosa por ARS (12 meses)'),
        table(['ARS', 'Reclamaciones', 'Radicado', 'Glosado', 'Tasa de glosa'], p.volume.map((v) => [v.ars, String(v.claims), money(v.claimed), money(v.glosado), v.glosa_pct == null ? '—' : `${v.glosa_pct} %`]), [1, 2, 3, 4])] : null);
  }

  const table = (head, rows, right = []) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x, i) => h('th', { class: right.includes(i) ? 'i18-r' : null }, x)))),
    h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x, i) => h('td', { class: right.includes(i) ? 'i18-r' : null }, x)))))));

  sel.addEventListener('change', load);
  await load();
}
export default render;
