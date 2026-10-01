/** SOFA · Pagos de ARS: registro, conciliación por ARS y cuentas por cobrar */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, opt, confirmDialog } from '../utils/ui.js';
import { listPayments, arsReconciliation, voidPayment } from '../services/finance.js';
import { listSubmissions } from '../services/submissions.js';
import { listArs } from '../services/catalog.js';
import { money, num, date, period, todayISO } from '../utils/formatters.js';
import { PAYMENT_METHODS } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';
import { CONFIG } from '../config.js';
import { pager } from './clients.js';

const METHOD = Object.fromEntries(PAYMENT_METHODS);
const daysTo = (iso) => (iso ? Math.round((new Date(`${iso}T00:00:00`) - new Date(`${todayISO()}T00:00:00`)) / 86400000) : null);

export async function render(main, ctx) {
  const st = { tab: 'pagos', arsId: '', q: '', page: 0 };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Pagos y conciliación</h2><p>Pagos recibidos de las ARS, repartidos entre radicaciones. El saldo se calcula solo: radicado − pagado − glosa aceptada.</p></div>
      ${can('payments.create', ctx.role) ? html`<button class="btn primary" id="new">+ Registrar pago</button>` : ''}</div>
    <div class="tabs" id="tabs" role="group" aria-label="Vista"></div>
    <div class="toolbar" id="tb"><label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Referencia, cliente o folio">
      <label class="sr-only" for="ars">ARS</label><select class="input" id="ars" style="width:auto"><option value="">Todas las ARS</option></select></div>
    <div id="l"></div>`);
  const tabs = [['pagos', 'Pagos recibidos'], ['conciliacion', 'Conciliación por ARS'], ['cobrar', 'Por cobrar']];
  const drawTabs = () => paint($('#tabs', main), html`${tabs.map(([k, l]) => html`<button data-t="${k}" aria-pressed="${st.tab === k}">${l}</button>`)}`);
  drawTabs();
  listArs().then((a) => paint($('#ars', main), html`<option value="">Todas las ARS</option>${a.map((x) => opt(x.id, x.name))}`)).catch(() => {});
  const list = $('#l', main);
  const showFee = can('fees.view', ctx.role);

  const load = () => {
    $('#q', main).style.display = st.tab === 'conciliacion' ? 'none' : '';
    if (st.tab === 'pagos') return loadInto(list, () => listPayments({ ...st, size: CONFIG.PAGE_SIZE }), ({ data, count }) => html`
      <div class="table-wrap"><table class="t cards"><thead><tr><th>Fecha</th>${isStaff(ctx.role) ? html`<th>Cliente</th>` : ''}<th>ARS</th><th>Folio · referencia</th><th>Aplicado a</th><th class="n">Monto</th>${showFee ? html`<th class="n">Honorario SOFA</th>` : ''}${can('payments.void', ctx.role) ? html`<th></th>` : ''}</tr></thead>
      <tbody>${data.map((p) => html`<tr><td data-l="Fecha">${date(p.paid_on)}</td>${isStaff(ctx.role) ? html`<td data-l="Cliente">${p.client_name}</td>` : ''}<td data-l="ARS">${p.ars_name}</td>
        <td data-l="Referencia">${p.payment_folio ? html`<b class="mono">${p.payment_folio}</b><br>` : ''}<span class="mono">${p.reference}</span><div class="small muted">${METHOD[p.method] || p.method}</div></td>
        <td data-l="Aplicado a" class="small">${p.folios || '—'}</td><td data-l="Monto" class="n"><b>${money(p.amount)}</b></td>
        ${showFee ? html`<td data-l="Honorario" class="n">${p.sofa_fee == null ? '—' : money(p.sofa_fee)}</td>` : ''}
        ${can('payments.void', ctx.role) ? html`<td data-l=""><button class="btn sm danger" data-void="${p.id}" data-ref="${p.reference}">Anular</button></td>` : ''}</tr>`)}</tbody></table></div>${pager(count, st.page)}`,
    { isEmpty: (r) => !r.data.length, empty: () => emptyView('Sin pagos registrados', 'Registra el primer pago de una ARS y repártelo entre sus radicaciones.') });

    if (st.tab === 'conciliacion') return loadInto(list, async () => (await arsReconciliation()).filter((r) => !st.arsId || r.ars_id === st.arsId), (rows) => {
      const by = {}; rows.forEach((r) => { const k = r.ars_id; by[k] = by[k] || { ars: r.ars, radicado: 0, pagado: 0, glosa: 0, saldo: 0 }; by[k].radicado += Number(r.radicado || 0); by[k].pagado += Number(r.pagado || 0); by[k].glosa += Number(r.glosa_aceptada || 0); by[k].saldo += Number(r.saldo || 0); });
      const list2 = Object.values(by).filter((x) => x.radicado > 0).sort((a, b) => b.saldo - a.saldo);
      const tot = list2.reduce((t, x) => ({ radicado: t.radicado + x.radicado, pagado: t.pagado + x.pagado, glosa: t.glosa + x.glosa, saldo: t.saldo + x.saldo }), { radicado: 0, pagado: 0, glosa: 0, saldo: 0 });
      return list2.length ? html`<div class="table-wrap"><table class="t cards"><thead><tr><th>ARS</th><th class="n">Radicado</th><th class="n">Pagado</th><th class="n">Glosa aceptada</th><th class="n">Saldo</th><th class="n">% cobrado</th></tr></thead>
        <tbody>${list2.map((x) => html`<tr><td data-l="ARS">${x.ars}</td><td data-l="Radicado" class="n">${money(x.radicado)}</td><td data-l="Pagado" class="n">${money(x.pagado)}</td><td data-l="Glosa aceptada" class="n">${money(x.glosa)}</td><td data-l="Saldo" class="n"><b>${money(x.saldo)}</b></td><td data-l="% cobrado" class="n">${x.radicado ? Math.round((1000 * x.pagado) / x.radicado) / 10 : 0}%</td></tr>`)}
        <tr><td data-l="ARS"><b>Total</b></td><td data-l="Radicado" class="n"><b>${money(tot.radicado)}</b></td><td data-l="Pagado" class="n"><b>${money(tot.pagado)}</b></td><td data-l="Glosa aceptada" class="n"><b>${money(tot.glosa)}</b></td><td data-l="Saldo" class="n"><b>${money(tot.saldo)}</b></td><td data-l="% cobrado" class="n"><b>${tot.radicado ? Math.round((1000 * tot.pagado) / tot.radicado) / 10 : 0}%</b></td></tr></tbody></table></div>` : emptyView('Sin radicaciones enviadas', 'La conciliación aparece cuando hay radicaciones radicadas.');
    }, { isEmpty: () => false });

    return loadInto(list, () => listSubmissions({ group: 'radicadas', arsId: st.arsId, q: st.q, page: st.page, size: CONFIG.PAGE_SIZE }), ({ data, count }) => html`
      <div class="table-wrap"><table class="t cards"><thead><tr><th>Radicación</th><th>Prestador</th><th>ARS</th><th>Radicada</th><th class="n">Saldo</th><th>Plazo</th>${can('payments.create', ctx.role) ? html`<th></th>` : ''}</tr></thead>
      <tbody>${data.map((s) => { const d = daysTo(s.payment_deadline); return html`<tr><td data-l="Radicación"><a href="#/radicaciones/${s.id}" class="mono"><b>${s.folio}</b></a><div class="small muted">${period(s.period)}</div></td>
        <td data-l="Prestador">${s.provider_name}</td><td data-l="ARS">${s.ars_name}</td><td data-l="Radicada">${date(s.submitted_on)}</td><td data-l="Saldo" class="n"><b>${money(s.balance)}</b></td>
        <td data-l="Plazo"><span style="${d < 0 ? 'color:var(--bad);font-weight:600' : d <= 15 ? 'color:var(--warn);font-weight:600' : ''}">${d < 0 ? `Vencido hace ${-d} días` : `Vence en ${d} días`}</span></td>
        ${can('payments.create', ctx.role) ? html`<td data-l=""><button class="btn sm" data-pay="${s.id}" data-org="${s.organization_id}" data-ars="${s.ars_id}">Registrar pago</button></td>` : ''}</tr>`; })}</tbody></table></div>${pager(count, st.page)}`,
    { isEmpty: (r) => !r.data.length, empty: () => emptyView('Nada por cobrar', 'No hay radicaciones con saldo pendiente.') });
  };

  const pay = async (preset = {}) => {
    try { const { paymentDialog } = await import('./finance-dialogs.js'); if (await paymentDialog(preset)) { toast('Pago registrado y aplicado', 'ok'); load(); } }
    catch (err) { toast(friendlyError(err), 'bad'); }
  };
  $('#new', main)?.addEventListener('click', () => pay());
  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-t]'); if (b) { st.tab = b.dataset.t; st.page = 0; drawTabs(); load(); } });
  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; st.page = 0; load(); }, 350); });
  $('#ars', main).addEventListener('change', (e) => { st.arsId = e.target.value; st.page = 0; load(); });
  list.addEventListener('click', async (e) => {
    const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); load(); return; }
    const pb = e.target.closest('[data-pay]'); if (pb) { pay({ orgId: pb.dataset.org, arsId: pb.dataset.ars, submissionId: pb.dataset.pay }); return; }
    const v = e.target.closest('[data-void]');
    if (v) {
      if (!(await confirmDialog('Anular pago', `Se anulará el pago ${v.dataset.ref}: el saldo de sus radicaciones vuelve a abrirse y su honorario SOFA se revierte (si no se facturó).`, 'Anular pago', true))) return;
      try { await voidPayment(v.dataset.void); toast('Pago anulado', 'ok'); load(); } catch (err) { toast(friendlyError(err), 'bad'); }
    }
  });
  load();
}
