/** SOFA · Dashboard: operación y cobro (todos) · crecimiento de SOFA (roles con honorarios) */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, errorView, emptyView } from '../utils/ui.js';
import { financialEvents, collectionDays, serviceMix, openBalances, feesInRange, monthsBetween, monthKey, BUCKETS,
  growthMonthly, mrr, pipelineTotals, growthTargets, settings } from '../services/bi.js';
import { filterBar } from '../utils/filters.js';
import { barChart, hBars, progress } from '../utils/charts.js';
import { money, num, period, date, todayISO } from '../utils/formatters.js';
import { can, isStaff } from '../utils/permissions.js';

const pct = (a, b) => (Number(b) > 0 ? Math.round((1000 * Number(a)) / Number(b)) / 10 : null);
const pctTxt = (v) => (v == null ? '—' : `${v}%`);
const sum = (rows, k = 'amount') => rows.reduce((t, r) => t + Number(r[k] || 0), 0);

export async function render(main, ctx) {
  const growth = can('fees.view', ctx.role) && isStaff(ctx.role);
  const intel = can('intel.view', ctx.role);
  let tab = 'operacion';
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Dashboard</h2><p>${isStaff(ctx.role) ? 'Cómo va el ciclo de ingresos de los clientes y el negocio de SOFA.' : 'Cómo va la facturación y el cobro de tu práctica.'}</p></div>
      <button class="btn no-print" id="print">Imprimir</button></div>
    ${growth || intel ? html`<div class="tabs no-print" id="tabs" role="group" aria-label="Vista"><button data-t="operacion" aria-pressed="true">Operación y cobro</button>${growth ? html`<button data-t="crecimiento" aria-pressed="false">Crecimiento SOFA</button>` : ''}${intel ? html`<button data-t="mercado" aria-pressed="false">Mercado e ideas</button>` : ''}</div>` : ''}
    <div id="fb"></div><div id="body">${loadingView(6)}</div>`);
  $('#print', main).addEventListener('click', () => window.print());
  const body = $('#body', main);
  let f = await filterBar($('#fb', main), ctx, (nf) => { f = nf; draw(); });
  $('#tabs', main)?.addEventListener('click', (e) => {
    const b = e.target.closest('[data-t]'); if (!b) return; tab = b.dataset.t;
    main.querySelectorAll('#tabs [data-t]').forEach((x) => x.setAttribute('aria-pressed', String(x.dataset.t === tab)));
    $('#fb', main).style.display = tab === 'operacion' ? '' : 'none'; draw();
  });

  async function draw() {
    paint(body, loadingView(6));
    try { if (tab === 'operacion') { await drawOps(); await drawNewsCard(); } else if (tab === 'mercado') await (await import('./market.js')).renderMarketSummary(body, ctx); else await drawGrowth(); }
    catch (err) { console.error(err); paint(body, errorView(err)); }
  }

  async function drawOps() {
    const [ev, cd, mix, open, fees] = await Promise.all([financialEvents(f), collectionDays(f), serviceMix(f), openBalances(f),
      can('fees.view', ctx.role) ? feesInRange(f).catch(() => []) : Promise.resolve([])]);
    const k = (kind) => ev.filter((e) => e.kind === kind);
    const rad = sum(k('radicado')), cob = sum(k('cobrado')), glo = sum(k('glosado')), rec = sum(k('recuperado')), acc = sum(k('glosa_aceptada'));
    const dso = cd.length ? Math.round(cd.reduce((t, r) => t + Number(r.days), 0) / cd.length) : null;
    const saldo = sum(open, 'balance'), vencido = sum(open.filter((r) => r.age_days > 90), 'balance');
    const feeTot = sum(fees);
    const months = monthsBetween(f.from, f.to);
    const byMonth = (kind) => months.map((m) => sum(k(kind).filter((e) => monthKey(e.event_date) === m)));
    const byBucket = BUCKETS.map((b) => ({ label: `${b} días`, value: sum(open.filter((r) => r.aging_bucket === b), 'balance'), color: b === '120+' || b === '91-120' ? 'var(--red)' : 'var(--navy-2)' }));
    const arsSaldo = {}; open.forEach((r) => { arsSaldo[r.ars_name] = (arsSaldo[r.ars_name] || 0) + Number(r.balance); });
    const mixBy = {}; mix.forEach((r) => { mixBy[r.description] = (mixBy[r.description] || 0) + Number(r.amount); });
    const arsRad = {}; k('radicado').forEach((e) => { arsRad[e.ars_id] = (arsRad[e.ars_id] || 0) + Number(e.amount); });

    if (!rad && !cob && !saldo && !mix.length) { paint(body, emptyView('Sin movimientos en este período', 'Cambia el rango de meses o los filtros. Las cifras aparecen cuando hay radicaciones enviadas, pagos o glosas.')); return; }
    paint(body, html`
      <div class="grid kpis">
        <div class="kpi"><div class="l">Radicado</div><div class="v">${money(rad)}</div><div class="h">${period(`${f.from}-01`)} a ${period(`${f.to}-01`)}</div></div>
        <div class="kpi"><div class="l">Cobrado</div><div class="v" style="color:var(--ok)">${money(cob)}</div><div class="h">${pctTxt(pct(cob, rad))} de lo radicado</div></div>
        <div class="kpi"><div class="l">Glosa sobre lo radicado</div><div class="v" style="${pct(glo, rad) > 5 ? 'color:var(--bad)' : ''}">${pctTxt(pct(glo, rad))}</div><div class="h">${money(glo)} glosado · meta &lt; 5%</div></div>
        <div class="kpi"><div class="l">Recuperación de glosas</div><div class="v">${pctTxt(pct(rec, rec + acc))}</div><div class="h">${money(rec)} recuperado · meta &gt; 75%</div></div>
        <div class="kpi"><div class="l">Días promedio de cobro</div><div class="v" style="${dso > 60 ? 'color:var(--warn)' : ''}">${dso == null ? '—' : num(dso)}</div><div class="h">${num(cd.length)} radicaciones pagadas · meta &lt; 60</div></div>
        <div class="kpi"><div class="l">Saldo por cobrar hoy</div><div class="v">${money(saldo)}</div><div class="h" style="${vencido ? 'color:var(--bad);font-weight:600' : ''}">${money(vencido)} con más de 90 días</div></div>
        ${can('fees.view', ctx.role) ? html`<div class="kpi"><div class="l">Honorarios SOFA del período</div><div class="v">${money(feeTot)}</div><div class="h">${feeTot > 0 ? `RD$${(cob / feeTot).toFixed(1)} cobrados por cada RD$1 de honorario` : 'Sin honorarios en el período'}</div></div>` : ''}
      </div>
      <div class="card" style="margin-top:14px"><h2>Radicado y cobrado por mes</h2>${barChart({ labels: months.map((m) => period(`${m}-01`).replace(/ \d{4}$/, (y) => ` ${y.trim().slice(2)}`)), series: [
        { name: 'Radicado', color: 'var(--navy-2)', values: byMonth('radicado') }, { name: 'Cobrado', color: 'var(--ok)', values: byMonth('cobrado') }, { name: 'Glosado', color: 'var(--red)', values: byMonth('glosado') }] })}</div>
      <div class="grid two" style="margin-top:14px">
        <div class="card"><h2>Antigüedad del saldo</h2><p class="sub">Días desde la radicación. <a href="#/aging">Ver detalle</a></p>${hBars(byBucket)}</div>
        <div class="card"><h2>Saldo por ARS</h2>${Object.keys(arsSaldo).length ? hBars(Object.entries(arsSaldo).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([label, value]) => ({ label, value }))) : html`<p class="small muted">Sin saldos pendientes.</p>`}</div>
        <div class="card"><h2>Conceptos más facturados</h2><p class="sub">Monto de los servicios del período.</p>${Object.keys(mixBy).length ? hBars(Object.entries(mixBy).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([label, value]) => ({ label, value }))) : html`<p class="small muted">Sin servicios en el período.</p>`}</div>
        <div class="card"><h2>Lo más antiguo por cobrar</h2>${open.length ? html`<div class="list">${open.slice(0, 6).map((r) => html`<div class="li"><div class="b"><div class="t1"><a href="#/radicaciones/${r.id}" class="mono">${r.folio}</a> · ${r.ars_name}</div><div class="t2">${isStaff(ctx.role) ? `${r.client_name} · ` : ''}radicada ${date(r.submitted_on)} · ${r.age_days} días</div></div><b>${money(r.balance)}</b></div>`)}</div>` : html`<p class="small muted">Nada pendiente.</p>`}</div>
      </div>`);
  }

  async function drawNewsCard() {
    if (!intel || tab !== 'operacion') return;
    const card = document.createElement('div'); card.className = 'card no-print'; card.style.marginTop = '14px';
    body.appendChild(card);
    try {
      const { topItems } = await import('../services/intel.js'); const { itemCard } = await import('./market.js');
      const top = await topItems({ days: 7, limit: 4 });
      paint(card, html`<h2>Noticias del sector · 7 días</h2>${top.length ? html`<div class="list">${top.map((i) => itemCard(i))}</div>` : html`<p class="small muted">Sin noticias recientes.</p>`}<p class="small" style="margin-top:8px"><a href="#/mercado">Ver inteligencia de mercado →</a></p>`);
    } catch { card.remove(); }
  }

  async function drawGrowth() {
    const [gm, m, pipe, targets, st] = await Promise.all([growthMonthly(), mrr().catch(() => null), pipelineTotals().catch(() => []), growthTargets().catch(() => []), settings().catch(() => null)]);
    const target = Number(st?.target_mrr || 0); const current = Number(m?.fixed_monthly || 0) + Number(m?.success_monthly_avg || 0);
    const open = pipe.filter((p) => !['cliente', 'perdido'].includes(p.stage));
    const weighted = sum(open, 'weighted_value'); const oppCount = sum(open, 'opportunities');
    const goal = targets.find((t) => t.metric === 'mrr' && t.ends_on >= todayISO()) || targets[targets.length - 1];
    const daysLeft = goal ? Math.round((new Date(`${goal.ends_on}T00:00:00`) - new Date(`${todayISO()}T00:00:00`)) / 86400000) : null;
    const labels = gm.map((r) => period(r.month).replace(/ (\d{4})$/, (x, y) => ` ${y.slice(2)}`));
    paint(body, html`
      <div class="grid kpis">
        <div class="kpi"><div class="l">Ingreso recurrente estimado (MRR)</div><div class="v">${money(current)}</div><div class="h">Cuotas ${money(m?.fixed_monthly)} + éxito prom. ${money(m?.success_monthly_avg)}</div></div>
        <div class="kpi"><div class="l">Meta de ingreso mensual</div><div class="v">${money(target)}</div><div class="h">${goal ? `${goal.name} · ${daysLeft >= 0 ? `faltan ${daysLeft} días` : 'plazo cumplido'}` : 'Configurable en Parámetros'}</div></div>
        <div class="kpi"><div class="l">Clientes activos</div><div class="v">${num(m?.active_clients || 0)}</div><div class="h">de ${num(st?.founder_slots || 0)} cupos fundadores</div></div>
        <div class="kpi"><div class="l">Pipeline ponderado</div><div class="v">${money(weighted)}</div><div class="h">${num(oppCount)} oportunidades abiertas (mensual)</div></div>
      </div>
      <div class="grid two" style="margin-top:14px">
        <div class="card"><h2>Avance hacia la meta de ingreso</h2>${progress(current, target)}
          <p class="small" style="margin-top:10px">Si se ganara todo el pipeline ponderado, el MRR llegaría a <b>${money(current + weighted)}</b> (${pctTxt(pct(current + weighted, target))} de la meta).</p></div>
        <div class="card"><h2>Clientes contra cupos fundadores</h2>${progress(Number(m?.active_clients || 0), Number(st?.founder_slots || 0), 'var(--navy-2)')}</div>
      </div>
      <div class="card" style="margin-top:14px"><h2>Honorarios devengados por mes</h2>${barChart({ labels, series: [{ name: 'Cuotas fijas', color: 'var(--navy-2)', values: gm.map((r) => r.fees_fixed) }, { name: 'Éxito y radicación', color: 'var(--ok)', values: gm.map((r) => r.fees_variable) }] })}</div>
      <div class="card" style="margin-top:14px"><h2>Actividad comercial por mes</h2>${barChart({ labels, money: false, series: [{ name: 'Prospectos nuevos', color: 'var(--navy-3)', values: gm.map((r) => r.new_leads) }, { name: 'Diagnósticos de fugas', color: 'var(--warn)', values: gm.map((r) => r.diagnostics) }, { name: 'Clientes nuevos', color: 'var(--ok)', values: gm.map((r) => r.new_clients) }] })}</div>`);
  }
  draw();
}
