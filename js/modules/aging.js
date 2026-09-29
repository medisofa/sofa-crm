/** SOFA · Aging: antigüedad del saldo por ARS o por cliente en 5 tramos, con detalle y exportación */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, errorView, emptyView } from '../utils/ui.js';
import { openBalances, BUCKETS } from '../services/bi.js';
import { filterBar, downloadCsv } from '../utils/filters.js';
import { money, num, date, period } from '../utils/formatters.js';
import { isStaff } from '../utils/permissions.js';

export async function render(main, ctx) {
  const staff = isStaff(ctx.role);
  let by = 'ars', rows = [], sel = null;
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Aging de cartera</h2><p>Saldo pendiente de cada radicación enviada según los días transcurridos desde la radicación. Plazo de pago de referencia: 90 días.</p></div>
      <div class="toolbar no-print" style="margin:0"><button class="btn" id="csv">Exportar CSV</button><button class="btn" id="print">Imprimir</button></div></div>
    ${staff ? html`<div class="tabs no-print" id="tabs" role="group" aria-label="Agrupar"><button data-b="ars" aria-pressed="true">Por ARS</button><button data-b="cliente" aria-pressed="false">Por cliente</button></div>` : ''}
    <div id="fb"></div><div id="m">${loadingView(5)}</div><div id="d" style="margin-top:14px"></div>`);
  let f = await filterBar($('#fb', main), ctx, (nf) => { f = nf; load(); }, { period: false });
  const key = (r) => (by === 'ars' ? r.ars_name : r.client_name);
  const draw = () => {
    if (!rows.length) { paint($('#m', main), emptyView('Sin saldos pendientes', 'No hay radicaciones enviadas con saldo por cobrar.')); paint($('#d', main), html``); return; }
    const groups = {}; rows.forEach((r) => { const k = key(r); groups[k] = groups[k] || Object.fromEntries(BUCKETS.map((b) => [b, 0])); groups[k][r.aging_bucket] += Number(r.balance); });
    const tot = Object.fromEntries(BUCKETS.map((b) => [b, rows.filter((r) => r.aging_bucket === b).reduce((t, r) => t + Number(r.balance), 0)]));
    const all = Object.values(tot).reduce((a, b) => a + b, 0);
    const order = Object.entries(groups).sort((a, b) => Object.values(b[1]).reduce((x, y) => x + y, 0) - Object.values(a[1]).reduce((x, y) => x + y, 0));
    const cell = (k, b, v) => html`<td data-l="${b} días" class="n">${v > 0 ? html`<button class="btn link" data-k="${k}" data-b="${b}" style="${b === '91-120' || b === '120+' ? 'color:var(--bad);font-weight:700' : ''}">${money(v)}</button>` : '—'}</td>`;
    paint($('#m', main), html`
      <div class="grid kpis">${BUCKETS.map((b) => html`<div class="kpi"><div class="l">${b} días</div><div class="v" style="${(b === '91-120' || b === '120+') && tot[b] ? 'color:var(--bad)' : ''}">${money(tot[b])}</div><div class="h">${all ? Math.round((100 * tot[b]) / all) : 0}% del saldo</div></div>`)}</div>
      <div class="table-wrap" style="margin-top:14px"><table class="t cards"><thead><tr><th>${by === 'ars' ? 'ARS' : 'Cliente'}</th>${BUCKETS.map((b) => html`<th class="n">${b}</th>`)}<th class="n">Total</th></tr></thead>
      <tbody>${order.map(([k, v]) => html`<tr><td data-l="${by === 'ars' ? 'ARS' : 'Cliente'}"><b>${k}</b></td>${BUCKETS.map((b) => cell(k, b, v[b]))}<td data-l="Total" class="n"><b>${money(Object.values(v).reduce((x, y) => x + y, 0))}</b></td></tr>`)}
        <tr><td data-l=""><b>Total</b></td>${BUCKETS.map((b) => html`<td data-l="${b}" class="n"><b>${money(tot[b])}</b></td>`)}<td data-l="Total" class="n"><b>${money(all)}</b></td></tr></tbody></table></div>
      <p class="small muted no-print">Pulsa un monto para ver sus radicaciones.</p>`);
    drawDetail();
  };
  const detailRows = () => (sel ? rows.filter((r) => key(r) === sel.k && r.aging_bucket === sel.b) : rows.filter((r) => r.age_days > 90));
  const drawDetail = () => {
    const d = detailRows();
    paint($('#d', main), html`<div class="card"><h2>${sel ? `${sel.k} · ${sel.b} días` : 'Radicaciones con más de 90 días'} · ${num(d.length)}</h2>
      ${d.length ? html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Radicación</th>${staff ? html`<th>Cliente</th>` : ''}<th>ARS</th><th>Radicada</th><th class="n">Días</th><th class="n">Radicado</th><th class="n">Pagado</th><th class="n">Glosa en disputa</th><th class="n">Saldo</th></tr></thead>
        <tbody>${d.map((r) => html`<tr><td data-l="Radicación"><a href="#/radicaciones/${r.id}" class="mono">${r.folio}</a><div class="small muted">${r.provider_name} · ${period(r.period)}</div></td>${staff ? html`<td data-l="Cliente">${r.client_name}</td>` : ''}
          <td data-l="ARS">${r.ars_name}</td><td data-l="Radicada">${date(r.submitted_on)}</td><td data-l="Días" class="n">${r.age_days}</td><td data-l="Radicado" class="n">${money(r.claimed)}</td>
          <td data-l="Pagado" class="n">${money(r.paid)}</td><td data-l="Glosa en disputa" class="n">${money(r.glosa_in_dispute)}</td><td data-l="Saldo" class="n"><b>${money(r.balance)}</b></td></tr>`)}</tbody></table></div>` : html`<p class="small muted">Ninguna.</p>`}</div>`);
  };
  const load = async () => { paint($('#m', main), loadingView(5)); try { rows = await openBalances(f); sel = null; draw(); } catch (err) { paint($('#m', main), errorView(err)); } };
  $('#tabs', main)?.addEventListener('click', (e) => { const b = e.target.closest('[data-b]'); if (!b) return; by = b.dataset.b; sel = null; main.querySelectorAll('#tabs [data-b]').forEach((x) => x.setAttribute('aria-pressed', String(x.dataset.b === by))); draw(); });
  $('#m', main).addEventListener('click', (e) => { const b = e.target.closest('[data-k]'); if (b) { sel = { k: b.dataset.k, b: b.dataset.b }; drawDetail(); $('#d', main).scrollIntoView({ behavior: 'smooth' }); } });
  $('#print', main).addEventListener('click', () => window.print());
  $('#csv', main).addEventListener('click', () => downloadCsv('sofa-aging.csv', ['Folio', 'Cliente', 'Prestador', 'ARS', 'Período', 'Radicada', 'Días', 'Tramo', 'Radicado', 'Pagado', 'Glosa aceptada', 'Glosa en disputa', 'Saldo'],
    rows.map((r) => [r.folio, r.client_name, r.provider_name, r.ars_name, r.period.slice(0, 7), r.submitted_on, r.age_days, r.aging_bucket, r.claimed, r.paid, r.glosa_accepted, r.glosa_in_dispute, r.balance])));
  load();
}
