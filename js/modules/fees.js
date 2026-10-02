/** SOFA · Honorarios: devengado por cliente, facturas SOFA y sus cobros */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, busy, confirmDialog } from '../utils/ui.js';
import { feeSummary, listInvoices, listFees, generateMonthlyFees, generateInvoices } from '../services/finance.js';
import { money, num, date, dateTime, period, todayISO } from '../utils/formatters.js';
import { INVOICE_STATUS, FEE_SOURCE } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';
import { CONFIG } from '../config.js';
import { pager } from './clients.js';
import * as adm from './fees-admin.js';   // estático: los botones de 1.7 responden apenas se pintan

export async function render(main, ctx) {
  if (ctx.arg) { const m = await import('./fee-invoice.js'); return m.render(main, ctx); }
  const manage = can('fees.manage', ctx.role); const staff = isStaff(ctx.role);
  const st = { inv: 'pendientes', page: 0 };
  const thisMonth = todayISO().slice(0, 7);
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Honorarios SOFA</h2><p>${staff ? 'Lo que SOFA gana por cliente: cuotas, porcentaje sobre lo cobrado y cargos por radicación. Cada honorario guarda la regla y la base que lo originaron.' : 'Tus honorarios con SOFA y tus facturas.'}</p></div></div>
    <div class="grid kpis" id="k"></div>
    ${manage ? html`<div class="card" style="margin-top:14px"><h2>Cierre del mes</h2><p class="sub">1) Genera las cuotas mensuales (también lo hace pg_cron el día 1). 2) Genera las facturas: agrupan por cliente lo no facturado del mes <b>y los honorarios rezagados de meses anteriores</b> (por ejemplo, de un pago registrado tarde). Las cuotas se <b>prorratean por días activos</b> cuando el cliente entra o sale a mitad de mes.</p>
      <div class="toolbar" style="margin:0"><label class="sr-only" for="mon">Mes</label><input class="input" type="month" id="mon" value="${thisMonth}" max="${thisMonth}" style="width:auto">
        <button class="btn" id="genFees">Generar cuotas del mes</button><button class="btn primary" id="genInv">Generar facturas del mes</button>
        <button class="btn" id="newInv">+ Nueva factura</button>${can('fees.cleanup', ctx.role) ? html`<button class="btn" id="cleanup">Limpieza del libro</button>` : ''}</div>
        <p class="small muted" style="margin:8px 0 0">Las facturas de SOFA son documentos de cobro. El comprobante fiscal (NCF / e-CF) se emite en el sistema fiscal; aquí se registra como referencia.</p></div>` : ''}
    <div class="card" style="margin-top:14px"><h2>Por cliente</h2><p class="sub">Esquema de facturación: monto fijo mensual, % de lo cobrado o ambos.</p><div id="sum"></div></div>
    ${staff ? html`<div class="card" style="margin-top:14px"><h2>Servicios por proyecto</h2><p class="sub">Codificación, Habilitación y otros cobros independientes de la facturación de reclamaciones: pago único, cuotas mensuales o 3 pagos por porcentaje.</p><div id="proj"></div></div>` : ''}
    <div class="card" style="margin-top:14px"><h2>Facturas de SOFA</h2><div class="tabs" id="tabs" role="group" aria-label="Estado"></div><div id="inv"></div></div>
    ${staff ? html`<div class="card" style="margin-top:14px"><h2>Libro de honorarios</h2><p class="sub">Los 100 más recientes. El cálculo no se edita: para corregir un pago se anula y se registra de nuevo.</p><div id="led"></div></div>` : ''}`);

  const loadSummary = () => loadInto($('#sum', main), feeSummary, (rows) => {
    const t = rows.reduce((a, r) => ({ accrued: a.accrued + Number(r.accrued), invoiced: a.invoiced + Number(r.invoiced), collected: a.collected + Number(r.collected), unin: a.unin + Number(r.uninvoiced) }), { accrued: 0, invoiced: 0, collected: 0, unin: 0 });
    paint($('#k', main), html`
      <div class="kpi"><div class="l">Devengado</div><div class="v">${money(t.accrued)}</div></div>
      <div class="kpi"><div class="l">Por facturar</div><div class="v">${money(t.unin)}</div></div>
      <div class="kpi"><div class="l">Facturado</div><div class="v">${money(t.invoiced)}</div></div>
      <div class="kpi"><div class="l">Por cobrar</div><div class="v" style="${t.invoiced - t.collected > 0 ? 'color:var(--warn)' : ''}">${money(t.invoiced - t.collected)}</div><div class="h">Cobrado ${money(t.collected)}</div></div>`);
    return html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Cliente</th><th>Esquema vigente</th><th class="n">Devengado</th><th class="n">Por facturar</th><th class="n">Facturado</th><th class="n">Cobrado</th></tr></thead>
      <tbody>${rows.map((r) => html`<tr><td data-l="Cliente">${staff ? html`<a href="#/clientes/${r.organization_id}">${r.client_name}</a>` : r.client_name}</td><td data-l="Esquema" class="small">${r.rules || '—'}${manage ? html` <button class="btn sm" data-scheme="${r.organization_id}" data-name="${r.client_name}">Cambiar</button>` : ''}</td>
        <td data-l="Devengado" class="n">${money(r.accrued)}</td><td data-l="Por facturar" class="n">${money(r.uninvoiced)}</td><td data-l="Facturado" class="n">${money(r.invoiced)}</td><td data-l="Cobrado" class="n">${money(r.collected)}</td></tr>`)}</tbody></table></div>`;
  }, { empty: () => emptyView('Sin reglas de honorario', 'Las reglas se crean al convertir una oportunidad o al dar de alta un cliente.') });

  const tabs = [['pendientes', 'Por cobrar'], ['pagadas', 'Cobradas'], ['anuladas', 'Anuladas'], ['', 'Todas']];
  const drawTabs = () => paint($('#tabs', main), html`${tabs.map(([k, l]) => html`<button data-t="${k}" aria-pressed="${st.inv === k}">${l}</button>`)}`);
  drawTabs();
  let invRows = [];
  const loadInv = () => loadInto($('#inv', main), async () => { const r = await listInvoices({ status: st.inv, page: st.page, size: CONFIG.PAGE_SIZE }); invRows = r.data; return r; }, ({ data, count }) => html`
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Factura</th>${staff ? html`<th>Cliente</th>` : ''}<th>Mes</th><th>NCF fiscal</th><th class="n">Total</th><th class="n">Saldo</th><th>Estado</th>${manage ? html`<th></th>` : ''}</tr></thead>
    <tbody>${data.map((i) => { const [l, c] = INVOICE_STATUS[i.status] || [i.status, '']; return html`<tr><td data-l="Factura"><a href="#/honorarios/${i.id}"><b class="mono">${i.folio}</b></a><div class="small muted">Emitida ${date(i.issued_on)} · vence ${date(i.due_on)}</div></td>
      ${staff ? html`<td data-l="Cliente">${i.client_name}</td>` : ''}<td data-l="Mes">${period(i.period)}</td><td data-l="NCF fiscal" class="mono">${i.ncf || html`<span class="muted">—</span>`}</td>
      <td data-l="Total" class="n">${money(i.total)}</td><td data-l="Saldo" class="n"><b>${money(i.balance)}</b>${i.days_overdue > 0 ? html`<div class="small" style="color:var(--bad);font-weight:600">Vencida hace ${i.days_overdue} días</div>` : ''}</td>
      <td data-l="Estado"><span class="pill ${c}">${l}</span></td>
      ${manage ? html`<td data-l="">${['emitida', 'pagada_parcial'].includes(i.status) ? html`<button class="btn sm primary" data-inv="pay" data-id="${i.id}">Cobro</button> ` : ''}<button class="btn sm" data-inv="pdf" data-id="${i.id}" title="Descargar PDF">PDF</button> ${i.status !== 'anulada' ? html`<button class="btn sm" data-inv="ncf" data-id="${i.id}" title="Registrar el NCF emitido en el sistema fiscal">NCF fiscal</button> ` : ''}${i.status === 'emitida' ? html`<button class="btn sm danger" data-inv="void" data-id="${i.id}">Anular</button>` : ''}</td>` : ''}</tr>`; })}</tbody></table></div>${pager(count, st.page)}`,
  { isEmpty: (r) => !r.data.length, empty: () => emptyView('Sin facturas', manage ? 'Genera las facturas del mes en "Cierre del mes".' : 'Aún no hay facturas.') });

  const loadLedger = () => staff && loadInto($('#led', main), () => listFees(100), (rows) => html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Fecha</th><th>Cliente</th><th>Origen</th><th class="n">Base</th><th class="n">Tasa</th><th class="n">Honorario</th><th>Factura</th></tr></thead>
    <tbody>${rows.map((f) => html`<tr><td data-l="Fecha">${dateTime(f.calculated_at)}</td><td data-l="Cliente">${f.organizations?.legal_name}</td><td data-l="Origen">${FEE_SOURCE[f.source_type] || f.source_type}<div class="small muted">${period(f.period)}</div></td>
      <td data-l="Base" class="n">${f.source_type === 'cuota' ? (Number(f.base_amount) > 0 && Number(f.base_amount) < new Date(Number(String(f.period).slice(0, 4)), Number(String(f.period).slice(5, 7)), 0).getDate() ? html`${num(f.base_amount)} días <span class="pill warn">prorrateada</span>` : 'Mes completo') : money(f.base_amount)}</td><td data-l="Tasa" class="n">${f.rate != null ? `${Number(f.rate)}%` : 'Fijo'}</td><td data-l="Honorario" class="n"><b>${money(f.amount)}</b></td>
      <td data-l="Factura" class="mono">${f.sofa_invoices?.folio || html`<span class="pill warn">Por facturar</span>`}</td></tr>`)}</tbody></table></div>`,
  { empty: () => emptyView('Sin honorarios todavía', 'Se generan al registrar pagos, al radicar (según la regla) y con las cuotas mensuales.') });

  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-t]'); if (b) { st.inv = b.dataset.t; st.page = 0; drawTabs(); loadInv(); } });
  $('#inv', main).addEventListener('click', async (e) => {
    const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); loadInv(); return; }
    const b = e.target.closest('[data-inv]'); if (!b) return;
    if (b.dataset.inv === 'pdf') {
      b.disabled = true;
      try { const { invoiceDocument } = await import('../services/finance.js'); const { downloadInvoicePdf } = await import('../utils/pdf-invoice.js');
        toast(`Descargado ${await downloadInvoicePdf(await invoiceDocument(b.dataset.id))}`, 'ok'); }
      catch (err) { toast(friendlyError(err), 'bad'); } finally { b.disabled = false; }
      return;
    }
    const inv = invRows.find((x) => x.id === b.dataset.id);
    try {
      const d = await import('./finance-dialogs.js');
      const done = b.dataset.inv === 'pay' ? await d.invoicePaymentDialog(inv) : b.dataset.inv === 'ncf' ? await d.ncfDialog(inv) : await d.voidInvoiceDialog(inv);
      if (done) { toast(b.dataset.inv === 'pay' ? 'Cobro registrado' : b.dataset.inv === 'ncf' ? 'Referencia fiscal guardada' : 'Factura anulada', 'ok'); loadInv(); loadSummary(); }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  $('#genFees', main)?.addEventListener('click', (e) => busy(e.currentTarget, async () => {
    try { const n = await generateMonthlyFees(`${$('#mon', main).value}-01`); toast(n ? `${n} cuotas generadas` : 'Las cuotas de ese mes ya estaban generadas', 'ok'); loadSummary(); loadLedger(); }
    catch (err) { toast(friendlyError(err), 'bad'); }
  }));
  $('#genInv', main)?.addEventListener('click', async (e) => {
    const btn = e.currentTarget; const m = $('#mon', main).value;
    if (!(await confirmDialog('Generar facturas', `Se creará una factura por cliente con todos sus honorarios no facturados de ${period(`${m}-01`)}. Vencen a los 15 días.`, 'Generar'))) return;
    await busy(btn, async () => {
      try { const n = await generateInvoices(`${m}-01`); toast(n ? `${n} facturas generadas` : 'No hay honorarios por facturar en ese mes', n ? 'ok' : ''); loadInv(); loadSummary(); loadLedger(); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });
  // ---- 1.7: esquema, proyectos, factura manual y limpieza
  if ($('#proj', main)) adm.renderProjects($('#proj', main), ctx);
  $('#sum', main).addEventListener('click', async (e) => {
    const b = e.target.closest('[data-scheme]'); if (!b) return;
    try { if (await adm.schemeDialog(ctx, { id: b.dataset.scheme, name: b.dataset.name })) { toast('Esquema aplicado; lo no facturado se recalculó', 'ok'); loadSummary(); loadLedger(); } }
    catch (err) { toast(friendlyError(err), 'bad'); }
  });
  $('#newInv', main)?.addEventListener('click', async () => {
    try { const id = await adm.manualInvoiceDialog(ctx); if (id) { toast('Factura emitida', 'ok'); location.hash = `#/honorarios/${id}`; } } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  $('#cleanup', main)?.addEventListener('click', async () => {
    try { if (await adm.cleanupWizard(ctx)) { loadSummary(); loadInv(); loadLedger(); } } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  loadSummary(); loadInv(); loadLedger();
}
