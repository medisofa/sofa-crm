/** SOFA · 4.3 · Iteración 53 · Informe estratégico trimestral para el cliente.
 *  Qué ARS priorizar, cuáles renegociar o escalar, qué procedimientos sostienen el ingreso y qué causa de glosa atacar. */
import { rpc, h, money, fmtDate, note, guarded, kpi, clientOptions, clientName } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';

const KIND = { priorizar: 'Priorizar', glosa: 'Bajar la glosa', escalar: 'Escalar el cobro', renegociar: 'Renegociar', causa: 'Atacar la causa' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const client = ctx.role === 'client';
  const sel = h('select', { id: 'qt-org' }, h('option', { value: '' }, 'Elija un cliente'));
  const q = h('select', { id: 'qt-q' }, quarters().map((x, i) => h('option', { value: x.start, selected: i === 1 }, x.label)));
  const save = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Guardar e imprimir');
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Informe estratégico trimestral'),
    h('p', { class: 'i18-sub' }, 'Para la reunión trimestral: dónde está el dinero y qué hacer el próximo trimestre.'),
    h('div', { class: 'i18-bar' }, client ? null : h('label', { for: 'qt-org' }, 'Cliente', sel), h('label', { for: 'qt-q' }, 'Trimestre', q), save), box));
  if (!client) { try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { box.replaceChildren(note(e.message, 'error')); } }
  const org = () => (client ? ctx.membership?.organization_id : sel.value);
  let last = null;

  async function load() {
    if (!org()) { box.replaceChildren(note('Elija un cliente.')); return; }
    const d = await guarded(box, () => rpc('quarterly_report', { p_org: org(), p_quarter_start: q.value, p_save: false }));
    if (!d) return;
    last = d;
    const t = d.totals; const p = d.prev_totals;
    const delta = (a, b) => (Number(b) ? `${Number(a) >= Number(b) ? '+' : ''}${Math.round((100 * (Number(a) - Number(b))) / Number(b))} % vs. trimestre anterior` : '');
    box.replaceChildren(h('div', { class: 'i18-kpis' }, kpi('Radicado', money(t.claimed), delta(t.claimed, p.claimed)), kpi('Cobrado', money(t.paid), delta(t.paid, p.paid)),
      kpi('Glosado', money(t.glosado), delta(t.glosado, p.glosado)), kpi('Pendiente', money(t.balance))),
      h('h3', {}, 'Recomendaciones'),
      d.recommendations.length ? h('ol', { class: 'qt-recs' }, d.recommendations.map((r) => h('li', {}, h('span', { class: `pa-sev ${r.kind === 'priorizar' ? 'advierte' : 'bloquea'}` }, KIND[r.kind] || r.kind), ' ', r.text))) : note('Sin recomendaciones: el trimestre no tiene datos suficientes o todo está en orden.'),
      h('h3', {}, 'Por ARS'),
      d.by_ars.length ? table(['ARS', 'Lotes', 'Radicado', 'Cobrado', '% cobrado', '% glosa', 'Días de pago', 'Pendiente'],
        d.by_ars.map((a) => [a.ars, String(a.lots), money(a.claimed), money(a.paid), pct(a.net_rate), pct(a.glosa_pct), a.dso == null ? '—' : String(a.dso), money(a.balance)]), [1, 2, 3, 4, 5, 6, 7]) : note('Sin lotes radicados en el trimestre.'),
      h('h3', {}, 'Procedimientos que sostienen el ingreso'),
      d.by_procedure.length ? table(['Procedimiento', 'Cantidad', 'Cobrado', 'Cobro por unidad', '% del volumen', '% del ingreso'],
        d.by_procedure.map((x) => [`${x.code ? x.code + ' · ' : ''}${x.procedure}`, String(x.qty), money(x.paid), money(x.net_per_unit), pct(x.share_volume), pct(x.share_income)]), [1, 2, 3, 4, 5]) : note('Sin procedimientos en el trimestre.'),
      d.subsidize.length ? h('p', { class: 'i18-sub' }, 'Desbalance (pesan distinto en volumen que en ingreso): ' + d.subsidize.map((x) => `${x.procedure} (${x.share_volume} % del volumen, ${x.share_income} % del ingreso)`).join('; ')) : null,
      h('p', { class: 'i18-sub' }, d.note));
  }

  save.addEventListener('click', async () => {
    if (!org()) return;
    const w = openPrint();
    try {
      const d = await rpc('quarterly_report', { p_org: org(), p_quarter_start: q.value, p_save: true });
      fillPrint(w, `Informe trimestral · ${d.client} · ${d.label}`, `Del ${fmtDate(d.quarter_start)} al ${fmtDate(d.quarter_end)} · generado el ${fmtDate(d.generated_on)}`, [
        { big: `Cobrado: ${money(d.totals.paid)} de ${money(d.totals.claimed)} radicado` },
        { h: 'Recomendaciones' }, ...(d.recommendations.length ? d.recommendations.map((r) => ({ p: `• ${KIND[r.kind] || r.kind}: ${r.text}` })) : [{ p: 'Sin recomendaciones.' }]),
        { h: 'Por ARS' }, { table: { head: ['ARS', 'Radicado', 'Cobrado', '% cobrado', '% glosa', 'Días'], right: [1, 2, 3, 4, 5], rows: d.by_ars.map((a) => [a.ars, money(a.claimed), money(a.paid), pct(a.net_rate), pct(a.glosa_pct), a.dso == null ? '—' : String(a.dso)]) } },
        { h: 'Procedimientos' }, { table: { head: ['Procedimiento', 'Cant.', 'Cobrado', 'Por unidad'], right: [1, 2, 3], rows: d.by_procedure.map((x) => [x.procedure, String(x.qty), money(x.paid), money(x.net_per_unit)]) } },
        { p: d.note }]);
      last = d;
    } catch (e) { if (w) w.close(); box.prepend(note(e.message, 'error')); }
  });

  const pct = (v) => (v == null ? '—' : `${v} %`);
  const table = (head, rows, right = []) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x, i) => h('th', { class: right.includes(i) ? 'i18-r' : null }, x)))),
    h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x, i) => h('td', { class: right.includes(i) ? 'i18-r' : null }, x)))))));

  sel.addEventListener('change', load); q.addEventListener('change', load);
  await load();
}

function quarters() {
  const out = []; const d = new Date(); let y = d.getFullYear(); let qn = Math.floor(d.getMonth() / 3);
  for (let i = 0; i < 6; i++) { out.push({ start: `${y}-${String(qn * 3 + 1).padStart(2, '0')}-01`, label: `${y} · T${qn + 1}${i === 0 ? ' (en curso)' : ''}` }); qn -= 1; if (qn < 0) { qn = 3; y -= 1; } }
  return out;
}
export default render;
