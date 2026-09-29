/** SOFA · Codificación y tarifarios: buscador, tarifario por ARS, negociadas, brechas e importación */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, friendlyError, toast, opt, confirmDialog } from '../utils/ui.js';
import { listArs, searchProcedures, codesFor, tariffsFor, codedProcedureIds } from '../services/catalog.js';
import { listCurrentTariffs, tariffGaps } from '../services/tariffs.js';
import { headCount } from '../services/stats.js';
import { money, num, date, todayISO, rangeContains } from '../utils/formatters.js';
import { can, isStaff } from '../utils/permissions.js';
import { CONFIG } from '../config.js';
import { pager } from './clients.js';

export async function render(main, ctx) {
  if (ctx.arg) { const m = await import('./coding-concept.js'); return m.render(main, ctx); }
  const edit = can('tariffs.edit', ctx.role);
  const st = { tab: 'buscar', q: '', family: '', onlyUncoded: false, arsId: '', page: 0 };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Codificación y tarifarios</h2><p>Conceptos con sus códigos (CUPS, SIMON, propios de cada ARS) y lo que paga cada ARS, con vigencias. Una tarifa nunca se sobrescribe: se crea una nueva y la anterior queda en el histórico.</p></div>
      ${edit ? html`<div class="toolbar" style="margin:0"><button class="btn" id="newConcept">+ Nuevo concepto</button><button class="btn" id="newTariff">+ Nueva tarifa</button><button class="btn primary" id="import">Importar tarifario</button></div>` : ''}</div>
    <div class="grid kpis" id="k"></div>
    <div class="tabs" id="tabs" role="group" aria-label="Vista" style="margin-top:14px"></div>
    <div class="toolbar" id="tb"></div>
    <div id="res"></div>`);

  let arsList = [], arsMap = {};
  try { arsList = await listArs(); arsMap = Object.fromEntries(arsList.map((a) => [a.id, a.name])); } catch { /* se muestra el id */ }
  const [total, coded] = await Promise.allSettled([headCount('procedures', (q) => q.eq('is_active', true)), codedProcedureIds()]);
  const t = total.status === 'fulfilled' ? total.value : null; const c = coded.status === 'fulfilled' ? coded.value.length : null;
  paint($('#k', main), html`
    <div class="kpi"><div class="l">Conceptos activos</div><div class="v">${num(t)}</div></div>
    <div class="kpi"><div class="l">Con código</div><div class="v">${num(c)}</div></div>
    <div class="kpi"><div class="l">Sin ningún código</div><div class="v" style="color:var(--bad)">${t == null || c == null ? '—' : num(Math.max(0, t - c))}</div><div class="h">Riesgo de glosa por codificación</div></div>`);

  const tabs = [['buscar', 'Buscador'], ['tarifario', 'Tarifario por ARS'], ['negociadas', 'Tarifas negociadas'], ['brechas', 'Brechas entre ARS']];
  const drawTabs = () => paint($('#tabs', main), html`${tabs.map(([k, l]) => html`<button data-t="${k}" aria-pressed="${st.tab === k}">${l}</button>`)}`);
  const drawToolbar = () => {
    const arsSel = html`<label class="sr-only" for="ars">ARS</label><select class="input" id="ars" style="width:auto">${st.tab === 'tarifario' ? '' : html`<option value="">Todas las ARS</option>`}${arsList.map((a) => opt(a.id, a.name, st.arsId))}</select>`;
    paint($('#tb', main), st.tab === 'buscar' ? html`
      <label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" value="${st.q}" placeholder="Ej.: consulta, 890402, S11305">
      <label class="sr-only" for="fam">Línea</label><select class="input" id="fam" style="width:auto"><option value="">Todas las líneas</option>${['Medicina y hospitalización', 'Nutrición clínica'].map((x) => opt(x, x, st.family))}</select>
      <label class="check small"><input type="checkbox" id="unc" ${st.onlyUncoded ? 'checked' : ''}> Solo sin código</label>`
      : st.tab === 'brechas' ? html`<span class="small muted grow">Mismo concepto, distinto pago según la ARS: base para renegociar tarifarios.</span><button class="btn sm" id="csvGap">Exportar CSV</button>`
      : html`<label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" value="${st.q}" placeholder="Concepto o prestador">${arsSel}`);
  };
  const res = $('#res', main); const today = todayISO(); let gapRows = [];

  const load = () => {
    if (st.tab === 'buscar') return loadInto(res, async () => {
      const { data, count } = await searchProcedures({ ...st, size: CONFIG.PAGE_SIZE });
      const ids = data.map((p) => p.id);
      const [codes, tariffs] = await Promise.all([codesFor(ids), tariffsFor(ids)]);
      return { data, count, codes, tariffs };
    }, ({ data, count, codes, tariffs }) => html`
      <div class="table-wrap"><table class="t cards"><thead><tr><th>Concepto</th><th>Códigos</th><th>Tarifas vigentes hoy</th></tr></thead>
      <tbody>${data.map((p) => {
        const cs = codes.filter((x) => x.procedure_id === p.id);
        const ts = tariffs.filter((x) => x.procedure_id === p.id && rangeContains(x.valid_during, today)).sort((a, b) => (arsMap[a.ars_id] || '').localeCompare(arsMap[b.ars_id] || ''));
        const amounts = ts.map((x) => Number(x.amount)); const gap = amounts.length > 1 && Math.max(...amounts) > Math.min(...amounts);
        return html`<tr data-id="${p.id}" style="cursor:pointer">
          <td data-l="Concepto"><a href="#/codificacion/${p.id}"><b>${p.description}</b></a><div class="small muted">${p.internal_code} · ${p.family}</div></td>
          <td data-l="Códigos">${cs.length ? cs.map((x) => html`<span class="pill info mono" style="margin:0 4px 4px 0">${x.code_system === 'ARS' ? (arsMap[x.ars_id] || 'ARS') : x.code_system} ${x.code}</span>`) : html`<span class="pill bad">Sin código</span>`}</td>
          <td data-l="Tarifas">${ts.length ? html`${ts.map((x) => html`<div class="small">${arsMap[x.ars_id] || x.ars_id}: <b>${money(x.amount)}</b></div>`)}${gap ? html`<span class="pill warn" style="margin-top:4px">Brecha entre ARS</span>` : ''}` : html`<span class="muted small">Sin tarifa cargada</span>`}</td></tr>`;
      })}</tbody></table></div>${pager(count, st.page)}`,
    { isEmpty: (r) => !r.data.length, empty: () => emptyView('Sin resultados', 'Prueba con otra palabra o código.') });

    if (st.tab === 'tarifario' || st.tab === 'negociadas') {
      if (st.tab === 'tarifario' && !st.arsId && arsList.length) st.arsId = arsList[0].id;
      return loadInto(res, () => listCurrentTariffs({ arsId: st.arsId, scope: st.tab === 'negociadas' ? 'prestador' : 'general', q: st.q, page: st.page, size: 50 }), ({ data, count }) => html`
        <div class="table-wrap"><table class="t cards"><thead><tr><th>Concepto</th>${st.tab === 'negociadas' ? html`<th>Prestador</th>` : ''}<th>ARS</th><th class="n">Monto vigente</th><th>Desde</th><th>Fuente</th><th class="n">Servicios que la usan</th>${edit ? html`<th></th>` : ''}</tr></thead>
        <tbody>${data.map((x) => html`<tr>
          <td data-l="Concepto"><a href="#/codificacion/${x.procedure_id}">${x.description}</a><div class="small muted">${x.internal_code}${x.plan_name ? ` · Plan ${x.plan_name}` : ''}</div></td>
          ${st.tab === 'negociadas' ? html`<td data-l="Prestador">${x.provider_name}${isStaff(ctx.role) ? html`<div class="small muted">${x.client_name}</div>` : ''}</td>` : ''}
          <td data-l="ARS">${x.ars_name}</td><td data-l="Monto" class="n"><b>${money(x.amount)}</b></td><td data-l="Desde">${date(x.valid_from)}${x.valid_to ? html`<div class="small muted">hasta ${date(x.valid_to)}</div>` : ''}</td>
          <td data-l="Fuente" class="small">${x.source || '—'}</td><td data-l="Uso" class="n">${num(x.used_by_lines)}</td>
          ${edit ? html`<td data-l=""><button class="btn sm" data-new="${x.procedure_id}" data-ars="${x.ars_id}">Nueva tarifa</button></td>` : ''}</tr>`)}</tbody></table></div>${pager(count, st.page, 50)}`,
      { isEmpty: (r) => !r.data.length, empty: () => emptyView(st.tab === 'negociadas' ? 'Sin tarifas negociadas' : 'Sin tarifas para esta ARS', st.tab === 'negociadas' ? 'Registra la tarifa pactada con un prestador desde "+ Nueva tarifa" o desde la ficha del cliente.' : 'Importa su tarifario con "Importar tarifario".') });
    }

    return loadInto(res, async () => { gapRows = await tariffGaps(); return gapRows; }, (rows) => html`
      <div class="table-wrap"><table class="t cards"><thead><tr><th>Concepto</th><th class="n">ARS con tarifa</th><th class="n">Mínimo</th><th class="n">Máximo</th><th class="n">Brecha</th><th>Paga menos</th><th>Paga más</th></tr></thead>
      <tbody>${rows.map((g) => html`<tr><td data-l="Concepto"><a href="#/codificacion/${g.procedure_id}">${g.description}</a><div class="small muted">${g.detail}</div></td>
        <td data-l="ARS" class="n">${num(g.ars_count)}</td><td data-l="Mínimo" class="n">${money(g.min_amount)}</td><td data-l="Máximo" class="n">${money(g.max_amount)}</td>
        <td data-l="Brecha" class="n"><span class="pill ${g.gap_pct >= 20 ? 'bad' : 'warn'}">${g.gap_pct}%</span></td><td data-l="Paga menos">${g.lowest_ars}</td><td data-l="Paga más">${g.highest_ars}</td></tr>`)}</tbody></table></div>
      <p class="small muted">Úsalo en la negociación: "Por el mismo servicio, ${rows[0]?.highest_ars || 'otra ARS'} paga ${rows[0]?.gap_pct || 0}% más".</p>`,
    { empty: () => emptyView('Sin brechas', 'Todas las ARS pagan lo mismo por los conceptos cargados.') });
  };

  const redraw = () => { drawTabs(); drawToolbar(); bindToolbar(); load(); };
  function bindToolbar() {
    let tm;
    $('#q', main)?.addEventListener('input', (e) => { clearTimeout(tm); tm = setTimeout(() => { st.q = e.target.value; st.page = 0; load(); }, 350); });
    $('#fam', main)?.addEventListener('change', (e) => { st.family = e.target.value; st.page = 0; load(); });
    $('#unc', main)?.addEventListener('change', (e) => { st.onlyUncoded = e.target.checked; st.page = 0; load(); });
    $('#ars', main)?.addEventListener('change', (e) => { st.arsId = e.target.value; st.page = 0; load(); });
    $('#csvGap', main)?.addEventListener('click', () => {
      const q = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
      const csv = '\uFEFF' + [['Código', 'Concepto', 'ARS con tarifa', 'Mínimo', 'Máximo', 'Brecha %', 'Paga menos', 'Paga más', 'Detalle'], ...gapRows.map((g) => [g.internal_code, g.description, g.ars_count, g.min_amount, g.max_amount, g.gap_pct, g.lowest_ars, g.highest_ars, g.detail])].map((r) => r.map(q).join(';')).join('\n');
      const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); a.download = 'sofa-brechas-tarifarias.csv'; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    });
  }
  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-t]'); if (b) { st.tab = b.dataset.t; st.page = 0; st.q = ''; if (st.tab !== 'tarifario') st.arsId = ''; redraw(); } });
  res.addEventListener('click', async (e) => {
    const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); load(); return; }
    const n = e.target.closest('[data-new]');
    if (n) { const d = await import('./tariff-dialogs.js'); try { if (await d.tariffDialog({ procedure: n.dataset.new, ars: n.dataset.ars })) { toast('Tarifa registrada con su vigencia', 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } return; }
    const row = e.target.closest('tr[data-id]'); if (row && !e.target.closest('a')) location.hash = `#/codificacion/${row.dataset.id}`;
  });
  const dlg = async (name, done) => { const d = await import('./tariff-dialogs.js'); try { const r = await d[name](); if (r) done(r); } catch (err) { toast(friendlyError(err), 'bad'); } };
  $('#newConcept', main)?.addEventListener('click', () => dlg('conceptDialog', (id) => { toast('Concepto creado', 'ok'); location.hash = `#/codificacion/${id}`; }));
  $('#newTariff', main)?.addEventListener('click', () => dlg('tariffDialog', () => { toast('Tarifa registrada con su vigencia', 'ok'); load(); }));
  $('#import', main)?.addEventListener('click', () => dlg('importTariffDialog', async (r) => {
    toast(`${r.created} tarifas nuevas · ${r.unchanged} sin cambio${r.errors ? ` · ${r.errors} con error` : ''}`, r.errors ? '' : 'ok');
    const errs = r.rows.filter((x) => !x.ok);
    if (errs.length) await confirmDialog('Filas no importadas', html`${errs.slice(0, 40).map((x) => html`<div class="small"><b>Fila ${x.row}:</b> ${x.error}</div>`)}`, 'Entendido');
    load();
  }));
  redraw();
}
