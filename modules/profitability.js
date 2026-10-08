/** SOFA · 18-D · Rentabilidad (desempeño de cobro) por ARS y procedimiento + reporte mensual para el contador. */
import { rpc, clientOptions, h, money, pct, num, fmtDate, monthNow, monthToDate, monthsAgoIso, todayIso, clientName, kpi, table, note, guarded, downloadCsv } from '../services/iter18.js';

const GROUPS = { ars: 'Por ARS', procedimiento: 'Por procedimiento', ars_procedimiento: 'ARS y procedimiento' };

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' }), acc = h('div');
  const cli = h('select', { id: 'i18-pf-client' });
  const grp = h('select', { id: 'i18-pf-group' }, ...Object.entries(GROUPS).map(([v, t]) => h('option', { value: v }, t)));
  const from = h('input', { type: 'date', value: monthsAgoIso(2) }), to = h('input', { type: 'date', value: todayIso() });
  const month = h('input', { type: 'month', value: monthNow(), max: monthNow() });
  const csv = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: true }, 'Exportar CSV');
  const acBtn = h('button', { class: 'i18-btn', type: 'button' }, 'Reporte del contador (CSV)');
  let data = null;

  async function load() {
    csv.disabled = true; data = null;
    if (!cli.value) return;
    data = await guarded(out, () => rpc('profitability', { p_org: cli.value, p_from: from.value, p_to: to.value, p_group: grp.value }));
    if (!data) return;
    out.replaceChildren(view(data)); csv.disabled = false;
  }
  csv.addEventListener('click', () => downloadCsv(`rentabilidad_${grp.value}_${from.value}_${to.value}.csv`, [
    ['ARS', 'Procedimiento', 'Reclamaciones', 'Reclamado', 'Cobrado', 'Glosado', 'Glosa aceptada', 'Pendiente', '% cobrado', '% glosa', 'Ticket promedio', 'Días de cobro'],
    ...data.rows.map((r) => [r.ars || '', r.procedure || '', r.lines, r.claimed, r.paid, r.glosado, r.glosa_accepted, r.pending, r.collected_pct ?? '', r.glosa_rate_pct ?? '', r.avg_ticket, r.avg_days_to_pay ?? ''])]));
  acBtn.addEventListener('click', async () => {
    acc.replaceChildren(); acBtn.disabled = true;
    try {
      const d = await rpc('accountant_report', { p_org: cli.value, p_period: monthToDate(month.value) });
      const rows = [['Reporte para el contador', d.organization.legal_name, d.organization.tax_id || '', d.period], [], ['Sección', 'Fecha', 'Concepto', 'Detalle', 'Monto']];
      d.ars_payments.forEach((p) => rows.push(['Pago de ARS', p.paid_on, p.ars, [p.method, p.reference, p.folio].filter(Boolean).join(' · '), p.amount]));
      d.private_by_method.forEach((p) => rows.push(['Cobro privado', '', p.method, '', p.amount]));
      d.copays_by_method.forEach((p) => rows.push(['Copago / diferencia', '', p.method, '', p.amount]));
      d.glosas_accepted.forEach((g) => rows.push(['Glosa aceptada', '', g.ars, '', g.accepted]));
      d.sofa_invoices.forEach((i) => rows.push(['Factura de honorarios SOFA', i.issued_on, i.folio, i.ncf || 'NCF pendiente', i.total]));
      const s = d.summary;
      rows.push([], ['Total ingresos', '', '', '', s.income_total], ['  ARS', '', '', '', s.income_ars], ['  Privados', '', '', '', s.income_private], ['  Copagos', '', '', '', s.income_copays],
        ['Glosas aceptadas', '', '', '', s.glosas_accepted], ['Honorarios SOFA facturados', '', '', '', s.sofa_fees_invoiced], [], [d.note]);
      downloadCsv(`reporte_contador_${d.period.slice(0, 7)}.csv`, rows);
      acc.replaceChildren(note(`Reporte de ${fmtDate(d.period)} generado: ingresos ${money(s.income_total)}.`));
    } catch (e) { acc.replaceChildren(note(e.message, 'error')); } finally { acBtn.disabled = false; }
  });
  [cli, grp, from, to].forEach((el) => el.addEventListener('change', load));

  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Rentabilidad por ARS y procedimiento'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Cliente', cli), h('label', {}, 'Agrupar', grp), h('label', {}, 'Desde', from), h('label', {}, 'Hasta', to), csv),
    out, h('h3', {}, 'Reporte mensual para el contador'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Mes', month), acBtn), acc));
  try { (await clientOptions()).forEach((c) => cli.append(h('option', { value: c.id }, clientName(c)))); await load(); }
  catch (e) { out.replaceChildren(note(e.message, 'error')); }
}
export default render;
export const mount = render;

function view(d) {
  const t = d.totals;
  return h('div', { class: 'i18-wrap' },
    h('div', { class: 'i18-kpis' }, kpi('Reclamado', money(t.claimed), `${num(t.lines)} reclamaciones`), kpi('Cobrado', money(t.paid), t.collected_pct != null ? `${pct(t.collected_pct)} de lo reconocido` : ''),
      kpi('Glosado', money(t.glosado), `${pct(t.glosa_rate_pct)} de lo reclamado`), kpi('Pendiente', money(t.pending))),
    note(d.note),
    table([{ label: 'ARS', get: (r) => r.ars || '—' }, { label: 'Procedimiento', get: (r) => r.procedure || '—' }, { label: 'Reclam.', right: true, get: (r) => num(r.lines) },
           { label: 'Reclamado', right: true, get: (r) => money(r.claimed) }, { label: 'Cobrado', right: true, get: (r) => money(r.paid) }, { label: '% cobrado', right: true, get: (r) => pct(r.collected_pct) },
           { label: '% glosa', right: true, get: (r) => pct(r.glosa_rate_pct) }, { label: 'Días de cobro', right: true, get: (r) => num(r.avg_days_to_pay) }, { label: 'Pendiente', right: true, get: (r) => money(r.pending) }]
      .filter((c) => d.group !== 'ars' || c.label !== 'Procedimiento').filter((c) => d.group === 'procedimiento' ? c.label !== 'ARS' : true), d.rows));
}
