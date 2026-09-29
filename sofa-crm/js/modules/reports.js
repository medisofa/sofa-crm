/** SOFA · Reportes con filtros, totales, exportación a CSV e impresión */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, errorView, emptyView, opt } from '../utils/ui.js';
import { financialEvents, collectionDays, serviceMix, submissionsInRange, openBalances, glosaPareto, feeSummaryAll, monthsBetween, monthKey } from '../services/bi.js';
import { filterBar, downloadCsv } from '../utils/filters.js';
import { money, num, period, date } from '../utils/formatters.js';
import { subStatus } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';

const pct = (a, b) => (Number(b) > 0 ? Math.round((1000 * Number(a)) / Number(b)) / 10 : null);
const sumBy = (rows, key, val = 'amount') => rows.reduce((m, r) => { const k = key(r); m[k] = (m[k] || 0) + Number(r[val] || 0); return m; }, {});

/** Cada reporte: { title, about, roles?, build(f) → { cols:[{label, key, type}], rows, totals? } } */
const REPORTS = {
  mensual: { title: 'Radicado, cobrado y glosado por mes', about: 'Montos por la fecha real de cada evento.',
    async build(f) {
      const ev = await financialEvents(f); const months = monthsBetween(f.from, f.to);
      const g = (kind, m) => ev.filter((e) => e.kind === kind && monthKey(e.event_date) === m).reduce((t, e) => t + Number(e.amount), 0);
      const rows = months.map((m) => { const r = { mes: period(`${m}-01`), radicado: g('radicado', m), cobrado: g('cobrado', m), glosado: g('glosado', m), recuperado: g('recuperado', m) }; r.tasa = pct(r.glosado, r.radicado); return r; });
      return { cols: [{ label: 'Mes', key: 'mes' }, { label: 'Radicado', key: 'radicado', type: 'money' }, { label: 'Cobrado', key: 'cobrado', type: 'money' }, { label: 'Glosado', key: 'glosado', type: 'money' }, { label: '% glosa', key: 'tasa', type: 'pct' }, { label: 'Recuperado', key: 'recuperado', type: 'money' }], rows, totals: true };
    } },
  ars: { title: 'Desempeño por ARS', about: 'Radicado, cobrado y glosas del período, y días promedio de cobro por ARS.',
    async build(f) {
      const [ev, cd, open] = await Promise.all([financialEvents(f), collectionDays(f), openBalances(f)]);
      const names = {}; open.forEach((r) => { names[r.ars_id] = r.ars_name; });
      const { listArs } = await import('../services/catalog.js'); (await listArs()).forEach((a) => { names[a.id] = a.name; });
      const ids = [...new Set([...ev.map((e) => e.ars_id), ...open.map((r) => r.ars_id)])];
      const rows = ids.map((id) => {
        const e = ev.filter((x) => x.ars_id === id); const s = (k) => e.filter((x) => x.kind === k).reduce((t, x) => t + Number(x.amount), 0);
        const d = cd.filter((x) => x.ars_id === id);
        return { ars: names[id] || id, radicado: s('radicado'), cobrado: s('cobrado'), glosado: s('glosado'), tasa: pct(s('glosado'), s('radicado')),
          dias: d.length ? Math.round(d.reduce((t, x) => t + Number(x.days), 0) / d.length) : null, saldo: open.filter((r) => r.ars_id === id).reduce((t, r) => t + Number(r.balance), 0) };
      }).sort((a, b) => b.radicado - a.radicado);
      return { cols: [{ label: 'ARS', key: 'ars' }, { label: 'Radicado', key: 'radicado', type: 'money' }, { label: 'Cobrado', key: 'cobrado', type: 'money' }, { label: 'Glosado', key: 'glosado', type: 'money' }, { label: '% glosa', key: 'tasa', type: 'pct' }, { label: 'Días de cobro', key: 'dias', type: 'num' }, { label: 'Saldo hoy', key: 'saldo', type: 'money' }], rows, totals: true };
    } },
  cartera: { title: 'Cartera por cliente', about: 'Saldo pendiente hoy por cliente, con lo vencido a más de 90 días.', staff: true,
    async build(f) {
      const open = await openBalances(f); const by = {};
      open.forEach((r) => { const k = r.client_name; by[k] = by[k] || { cliente: k, radicaciones: 0, radicado: 0, pagado: 0, disputa: 0, saldo: 0, vencido: 0 };
        const x = by[k]; x.radicaciones += 1; x.radicado += Number(r.claimed); x.pagado += Number(r.paid); x.disputa += Number(r.glosa_in_dispute); x.saldo += Number(r.balance); if (r.age_days > 90) x.vencido += Number(r.balance); });
      return { cols: [{ label: 'Cliente', key: 'cliente' }, { label: 'Radicaciones', key: 'radicaciones', type: 'num' }, { label: 'Radicado', key: 'radicado', type: 'money' }, { label: 'Pagado', key: 'pagado', type: 'money' }, { label: 'Glosa en disputa', key: 'disputa', type: 'money' }, { label: 'Saldo', key: 'saldo', type: 'money' }, { label: 'Vencido > 90 días', key: 'vencido', type: 'money' }], rows: Object.values(by).sort((a, b) => b.saldo - a.saldo), totals: true };
    } },
  glosas: { title: 'Glosas por motivo', about: 'Pareto de motivos: glosado, aceptado y recuperado (todas las fechas).',
    async build(f) {
      const p = await glosaPareto(f); const by = {};
      p.forEach((r) => { const k = r.reason_name; by[k] = by[k] || { motivo: k, categoria: r.category, servicios: 0, glosado: 0, aceptado: 0, recuperado: 0 }; const x = by[k]; x.servicios += Number(r.items); x.glosado += Number(r.amount); x.aceptado += Number(r.accepted); x.recuperado += Number(r.recovered); });
      const rows = Object.values(by).sort((a, b) => b.glosado - a.glosado); const tot = rows.reduce((t, r) => t + r.glosado, 0); let acc = 0;
      rows.forEach((r) => { acc += r.glosado; r.acumulado = pct(acc, tot); });
      return { cols: [{ label: 'Motivo', key: 'motivo' }, { label: 'Categoría', key: 'categoria' }, { label: 'Servicios', key: 'servicios', type: 'num' }, { label: 'Glosado', key: 'glosado', type: 'money' }, { label: 'Aceptado', key: 'aceptado', type: 'money' }, { label: 'Recuperado', key: 'recuperado', type: 'money' }, { label: '% acumulado', key: 'acumulado', type: 'pct' }], rows, totals: true };
    } },
  servicios: { title: 'Servicios por concepto', about: 'Servicios de los períodos seleccionados (mes de la radicación).',
    async build(f) {
      const mix = await serviceMix(f); const by = {};
      mix.forEach((r) => { const k = r.internal_code; by[k] = by[k] || { codigo: k, concepto: r.description, servicios: 0, cantidad: 0, monto: 0 }; by[k].servicios += Number(r.lines); by[k].cantidad += Number(r.quantity); by[k].monto += Number(r.amount); });
      return { cols: [{ label: 'Código', key: 'codigo' }, { label: 'Concepto', key: 'concepto' }, { label: 'Servicios', key: 'servicios', type: 'num' }, { label: 'Cantidad', key: 'cantidad', type: 'num' }, { label: 'Monto', key: 'monto', type: 'money' }], rows: Object.values(by).sort((a, b) => b.monto - a.monto), totals: true };
    } },
  radicaciones: { title: 'Detalle de radicaciones', about: 'Todas las radicaciones de los períodos seleccionados con su estado y saldo.',
    async build(f) {
      const s = await submissionsInRange(f);
      return { cols: [{ label: 'Folio', key: 'folio' }, { label: 'Cliente', key: 'client_name', staff: true }, { label: 'Prestador', key: 'provider_name' }, { label: 'ARS', key: 'ars_name' }, { label: 'Período', key: 'periodo' }, { label: 'Estado', key: 'estado' }, { label: 'Servicios', key: 'lines', type: 'num' }, { label: 'Reclamado', key: 'claimed', type: 'money' }, { label: 'Pagado', key: 'paid', type: 'money' }, { label: 'Glosado', key: 'glosado', type: 'money' }, { label: 'Saldo', key: 'balance', type: 'money' }],
        rows: s.map((r) => ({ ...r, periodo: period(r.period), estado: subStatus(r.display_status)[0] })), totals: true };
    } },
  honorarios: { title: 'Honorarios por cliente', about: 'Devengado, facturado y cobrado por SOFA a cada cliente (acumulado).', fees: true,
    async build() {
      const r = await feeSummaryAll();
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
  let f = await filterBar($('#fb', main), ctx, (nf) => { f = nf; run(); });
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
  $('#print', main).addEventListener('click', () => window.print());
  $('#csv', main).addEventListener('click', () => { if (data?.rows?.length) downloadCsv(`sofa-${key}.csv`, data.cols.map((c) => c.label), data.rows.map((r) => data.cols.map((c) => r[c.key] ?? ''))); });
  run();
}
