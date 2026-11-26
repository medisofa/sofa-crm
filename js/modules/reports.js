/** SOFA · Reportes con filtros, totales, exportación a CSV e impresión */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, errorView, emptyView, opt, toast } from '../utils/ui.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';
import { eventsByMonthKind, eventsByArsKind, collectionDaysByArs, openBalanceByArs, openBalanceByClient,
  serviceMixAgg, glosaPareto, submissionsInRange, feeSummaryAll, monthsBetween } from '../services/bi.js';
import { filterBar, downloadCsv } from '../utils/filters.js';
import { money, num, period, date } from '../utils/formatters.js';
import { subStatus } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';

const pct = (a, b) => (Number(b) > 0 ? Math.round((1000 * Number(a)) / Number(b)) / 10 : null);

/** Cada reporte: { title, about, roles?, build(f) → { cols:[{label, key, type}], rows, totals? } } */
const REPORTS = {
  mensual: { title: 'Radicado, cobrado y glosado por mes', about: 'Montos por la fecha real de cada evento.',
    async build(f) {
      const ev = await eventsByMonthKind(f); const months = monthsBetween(f.from, f.to);
      const g = (kind, m) => { const r = ev.find((x) => x.kind === kind && x.month === m); return r ? Number(r.total) : 0; };
      const rows = months.map((m) => { const r = { mes: period(`${m}-01`), radicado: g('radicado', m), cobrado: g('cobrado', m), glosado: g('glosado', m), recuperado: g('recuperado', m) }; r.tasa = pct(r.glosado, r.radicado); return r; });
      return { cols: [{ label: 'Mes', key: 'mes' }, { label: 'Radicado', key: 'radicado', type: 'money' }, { label: 'Cobrado', key: 'cobrado', type: 'money' }, { label: 'Glosado', key: 'glosado', type: 'money' }, { label: '% glosa', key: 'tasa', type: 'pct' }, { label: 'Recuperado', key: 'recuperado', type: 'money' }], rows, totals: true };
    } },
  ars: { title: 'Desempeño por ARS', about: 'Radicado, cobrado y glosas del período, y días promedio de cobro por ARS.',
    async build(f) {
      const [evArs, cdArs, balArs] = await Promise.all([eventsByArsKind(f), collectionDaysByArs(f), openBalanceByArs(f)]);
      const { listArs } = await import('../services/catalog.js'); const allArs = await listArs();
      const names = {}; allArs.forEach((a) => { names[a.id] = a.name; }); balArs.forEach((r) => { names[r.ars_id] = r.ars_name; });
      const ids = [...new Set([...evArs.map((e) => e.ars_id), ...balArs.map((r) => r.ars_id)])];
      const rows = ids.map((id) => {
        const s = (k) => { const r = evArs.find((x) => x.ars_id === id && x.kind === k); return r ? Number(r.total) : 0; };
        const d = cdArs.find((x) => x.ars_id === id);
        const b = balArs.find((x) => x.ars_id === id);
        return { ars: names[id] || id, radicado: s('radicado'), cobrado: s('cobrado'), glosado: s('glosado'), tasa: pct(s('glosado'), s('radicado')),
          dias: d ? Math.round(Number(d.sum_days) / Number(d.cnt)) : null, saldo: b ? Number(b.total_balance) : 0 };
      }).sort((a, b) => b.radicado - a.radicado);
      return { cols: [{ label: 'ARS', key: 'ars' }, { label: 'Radicado', key: 'radicado', type: 'money' }, { label: 'Cobrado', key: 'cobrado', type: 'money' }, { label: 'Glosado', key: 'glosado', type: 'money' }, { label: '% glosa', key: 'tasa', type: 'pct' }, { label: 'Días de cobro', key: 'dias', type: 'num' }, { label: 'Saldo hoy', key: 'saldo', type: 'money' }], rows, totals: true };
    } },
  cartera: { title: 'Cartera por cliente', about: 'Saldo pendiente hoy por cliente, con lo vencido a más de 90 días.', staff: true,
    async build(f) {
      const rows = (await openBalanceByClient(f)).map((r) => ({
        cliente: r.cliente, radicaciones: Number(r.radicaciones), radicado: Number(r.radicado), pagado: Number(r.pagado),
        disputa: Number(r.disputa), saldo: Number(r.saldo), vencido: Number(r.vencido),
      }));
      return { cols: [{ label: 'Cliente', key: 'cliente' }, { label: 'Radicaciones', key: 'radicaciones', type: 'num' }, { label: 'Radicado', key: 'radicado', type: 'money' }, { label: 'Pagado', key: 'pagado', type: 'money' }, { label: 'Glosa en disputa', key: 'disputa', type: 'money' }, { label: 'Saldo', key: 'saldo', type: 'money' }, { label: 'Vencido > 90 días', key: 'vencido', type: 'money' }], rows, totals: true };
    } },
  glosas: { title: 'Glosas por motivo', about: 'Pareto de motivos: glosado, aceptado y recuperado (todas las fechas).',
    async build(f) {
      const rows = (await glosaPareto(f)).map((r) => ({
        motivo: r.reason_name, categoria: r.category, servicios: Number(r.servicios),
        glosado: Number(r.glosado), aceptado: Number(r.aceptado), recuperado: Number(r.recuperado),
      }));
      const tot = rows.reduce((t, r) => t + r.glosado, 0); let acc = 0;
      rows.forEach((r) => { acc += r.glosado; r.acumulado = pct(acc, tot); });
      return { cols: [{ label: 'Motivo', key: 'motivo' }, { label: 'Categoría', key: 'categoria' }, { label: 'Servicios', key: 'servicios', type: 'num' }, { label: 'Glosado', key: 'glosado', type: 'money' }, { label: 'Aceptado', key: 'aceptado', type: 'money' }, { label: 'Recuperado', key: 'recuperado', type: 'money' }, { label: '% acumulado', key: 'acumulado', type: 'pct' }], rows, totals: true };
    } },
  servicios: { title: 'Servicios por concepto', about: 'Servicios de los períodos seleccionados (mes de la radicación).',
    async build(f) {
      const rows = (await serviceMixAgg(f)).map((r) => ({
        codigo: r.internal_code, concepto: r.description, servicios: Number(r.total_lines),
        cantidad: Number(r.total_quantity), monto: Number(r.total_amount),
      }));
      return { cols: [{ label: 'Código', key: 'codigo' }, { label: 'Concepto', key: 'concepto' }, { label: 'Servicios', key: 'servicios', type: 'num' }, { label: 'Cantidad', key: 'cantidad', type: 'num' }, { label: 'Monto', key: 'monto', type: 'money' }], rows, totals: true };
    } },
  radicaciones: { title: 'Detalle de radicaciones', about: 'Todas las radicaciones de los períodos seleccionados con su estado y saldo.',
    async build(f) {
      const s = await submissionsInRange(f);
      return { cols: [{ label: 'Folio', key: 'folio' }, { label: 'Cliente', key: 'client_name', staff: true }, { label: 'Prestador', key: 'provider_name' }, { label: 'ARS', key: 'ars_name' }, { label: 'Período', key: 'periodo' }, { label: 'Estado', key: 'estado' }, { label: 'Servicios', key: 'lines', type: 'num' }, { label: 'Reclamado', key: 'claimed', type: 'money' }, { label: 'Pagado', key: 'paid', type: 'money' }, { label: 'Glosado', key: 'glosado', type: 'money' }, { label: 'Saldo', key: 'balance', type: 'money' }],
        rows: s.map((r) => ({ ...r, periodo: period(r.period), estado: subStatus(r.display_status)[0] })), totals: true };
    } },
  honorarios: { title: 'Honorarios por cliente', about: 'Devengado, facturado y cobrado por SOFA a cada cliente (acumulado).', fees: true,
    async build() {
      const r = await feeSummaryAll({ realOnly: true });
      return { cols: [{ label: 'Cliente', key: 'client_name' }, { label: 'Reglas vigentes', key: 'rules' }, { label: 'Devengado', key: 'accrued', type: 'money' }, { label: 'Por facturar', key: 'uninvoiced', type: 'money' }, { label: 'Facturado', key: 'invoiced', type: 'money' }, { label: 'Cobrado', key: 'collected', type: 'money' }], rows: r, totals: true };
    } }
};
const fmt = (v, type) => (type === 'money' ? money(v) : type === 'pct' ? (v == null ? '—' : `${v}%`) : type === 'num' ? (v == null ? '—' : num(v)) : (v ?? '—'));

export async function render(main, ctx) {
  const staff = isStaff(ctx.role);
  const avail = Object.entries(REPORTS).filter(([, r]) => (!r.staff || staff) && (!r.fees || can('fees.view', ctx.role)));
  let key = avail[0][0]; let data = null;
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Reportes</h2><p>Elige un reporte, ajusta los filtros y exporta a CSV (Excel) o imprime.</p></div>
      <div class="toolbar no-print" style="margin:0"><button class="btn" id="csv">Exportar CSV</button><button class="btn" id="print">Imprimir</button></div></div>
    <div class="toolbar no-print"><label class="sr-only" for="rep">Reporte</label><select class="input" id="rep" style="width:auto;min-width:280px">${avail.map(([k, r]) => opt(k, r.title, key))}</select></div>
    <div id="fb"></div><div id="out">${loadingView(6)}</div>`);
  let f = await filterBar($('#fb', main), ctx, (nf) => { f = { ...nf, realOnly: staff }; run(); });
  f.realOnly = staff;
  const run = async () => {
    const rep = REPORTS[key]; const out = $('#out', main); paint(out, loadingView(6));
    try {
      data = await rep.build(f);
      const cols = data.cols.filter((c) => !c.staff || staff);
      if (!data.rows.length) { paint(out, emptyView('Sin datos', 'No hay información para estos filtros.')); return; }
      const totals = data.totals ? Object.fromEntries(cols.map((c) => [c.key, c.type === 'money' || (c.type === 'num' && !['dias'].includes(c.key)) ? data.rows.reduce((t, r) => t + Number(r[c.key] || 0), 0) : null])) : null;
      paint(out, html`<div class="card"><h2>${rep.title}</h2><p class="sub">${rep.about}${rep.fees || key === 'cartera' || key === 'glosas' ? '' : ` Período: ${period(`${f.from}-01`)} a ${period(`${f.to}-01`)}.`}</p>
        <div class="table-wrap"><table class="t cards"><thead><tr>${cols.map((c) => html`<th class="${c.type ? 'n' : ''}">${c.label}</th>`)}</tr></thead>
        <tbody>${data.rows.map((r) => html`<tr>${cols.map((c) => html`<td data-l="${c.label}" class="${c.type ? 'n' : ''}">${fmt(r[c.key], c.type)}</td>`)}</tr>`)}
        ${totals ? html`<tr>${cols.map((c, i) => html`<td data-l="${c.label}" class="${c.type ? 'n' : ''}"><b>${i === 0 ? 'Total' : totals[c.key] == null ? '' : fmt(totals[c.key], c.type)}</b></td>`)}</tr>` : ''}</tbody></table></div>
        <p class="small muted">${num(data.rows.length)} filas · generado ${new Date().toLocaleString('es-DO')}</p></div>`);
      data.cols = cols;
    } catch (err) { console.error(err); paint(out, errorView(err)); }
  };
  $('#rep', main).addEventListener('change', (e) => { key = e.target.value; run(); });
  $('#print', main).addEventListener('click', () => {
    if (!data?.rows?.length) { toast('Cargue un reporte antes de imprimir', 'bad'); return; }
    const w = openPrint();
    const rep = REPORTS[key];
    const sub = (rep.fees || key === 'cartera' || key === 'glosas')
      ? `${num(data.rows.length)} filas`
      : `Período: ${period(`${f.from}-01`)} a ${period(`${f.to}-01`)} · ${num(data.rows.length)} filas`;
    const right = data.cols.map((c) => c.type === 'money' || c.type === 'pct' || c.type === 'num');
    const tableRows = data.rows.map((r) => data.cols.map((c) => fmt(r[c.key], c.type)));
    if (data.totals) {
      tableRows.push(data.cols.map((c, i) => {
        if (i === 0) return 'Total';
        if (c.type === 'money' || c.type === 'num') return fmt(data.rows.reduce((t, r) => t + Number(r[c.key] || 0), 0), c.type);
        return '';
      }));
    }
    fillPrint(w, rep.title, sub, [{ table: { head: data.cols.map((c) => c.label), rows: tableRows, right } }]);
  });
  $('#csv', main).addEventListener('click', () => { if (data?.rows?.length) downloadCsv(`sofa-${key}.csv`, data.cols.map((c) => c.label), data.rows.map((r) => data.cols.map((c) => r[c.key] ?? ''))); });
  run();
}
