/**
 * SOFA · Factura de honorarios SOFA (1.4.1). Documento imprimible / PDF con emisor, cliente,
 * conceptos (cuota prorrateada, % cobrado con folio PAG y lote, radicación, rezagados),
 * cobros recibidos y saldo. Los datos los arma public.sofa_invoice_document() con su propio control de acceso.
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, emptyView, errorView, toast, friendlyError } from '../utils/ui.js';
import { money, date, period } from '../utils/formatters.js';
import { INVOICE_STATUS } from '../utils/constants.js';
import { can } from '../utils/permissions.js';
import { invoiceDocument } from '../services/finance.js';
import { downloadInvoicePdf, ncfKind, amountInWords } from '../utils/pdf-invoice.js';

const METHOD = { transferencia: 'Transferencia', cheque: 'Cheque', deposito: 'Depósito', efectivo: 'Efectivo', otro: 'Otro' };
const fmtTax = (t) => (!t ? '—' : t.length === 9 ? `${t.slice(0, 3)}-${t.slice(3, 8)}-${t.slice(8)}` : t.length === 11 ? `${t.slice(0, 3)}-${t.slice(3, 10)}-${t.slice(10)}` : t);
const addr = (o) => [o.address, o.city].filter(Boolean).join(', ');

export async function render(main, ctx) {
  paint(main, html`<div id="fi">${loadingView(5)}</div>`);
  const box = $('#fi', main);
  let d;
  try { d = await invoiceDocument(ctx.arg); }
  catch (err) {
    if (err?.code === 'P0002' || err?.code === '42501') { paint(box, emptyView('Factura no disponible', 'No existe o tu usuario no tiene acceso a ella.', html`<a class="btn" href="#/honorarios">Volver a Honorarios</a>`)); return; }
    paint(box, errorView(err, 'fi')); return;
  }
  const { issuer: e, client: c, invoice: i, lines, payments } = d;
  const [st, stc] = INVOICE_STATUS[i.status] || [i.status, ''];
  ctx.setTitle(i.folio);
  const late = lines.some((l) => l.late);
  paint(box, html`
    <div class="page-head no-print"><div class="t"><p><a href="#/honorarios">← Honorarios SOFA</a></p><h2><span class="mono">${i.folio}</span> <span class="pill ${stc}">${st}</span></h2></div>
      <div class="toolbar" style="margin:0"><button class="btn primary" id="pdf">Descargar PDF</button>${navigator.canShare ? html`<button class="btn" id="share">Compartir PDF</button>` : ''}<button class="btn" id="print">Imprimir</button></div></div>
    ${i.status === 'anulada' ? html`<div class="note bad">Factura anulada el ${date(i.voided_at)}. ${i.lines_frozen ? 'Conserva sus conceptos originales; sus honorarios se liberaron para volver a facturarse.' : 'Se anuló antes de la versión 1.5: sus conceptos se liberaron y no quedaron guardados en ella.'}</div>` : ''}
    ${!e.tax_id && can('settings.edit', ctx.role) ? html`<div class="note warn no-print">Falta el RNC de SOFA. Regístralo en <a href="#/parametros">Parámetros › Datos fiscales de SOFA</a> para que salga en la factura.</div>` : ''}
    ${!i.ncf && i.status !== 'anulada' ? html`<div class="note warn no-print">Esta factura todavía no tiene NCF.</div>` : ''}
    <article class="card" id="doc" style="max-width:860px">
      <div style="display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap;align-items:flex-start;border-bottom:2px solid var(--line);padding-bottom:12px">
        <div><div style="font-size:20px;font-weight:700">${e.trade_name || e.legal_name || 'SOFA'}</div>
          ${e.trade_name && e.legal_name ? html`<div>${e.legal_name}</div>` : ''}
          <div class="small">RNC ${fmtTax(e.tax_id)}${addr(e) ? html` · ${addr(e)}` : ''}</div>
          <div class="small">${[e.phone, e.email].filter(Boolean).join(' · ')}</div></div>
        <div style="text-align:right"><div class="small muted">${ncfKind(i.ncf)}</div><div class="mono" style="font-size:22px;font-weight:700">${i.folio}</div>
          <div class="small">NCF: <b class="mono">${i.ncf || 'pendiente'}</b>${i.ncf && i.ncf_valid_until ? ` · válido hasta ${date(i.ncf_valid_until)}` : ''}</div>
          <div class="small">Emitida ${date(i.issued_on)} · Vence ${date(i.due_on)}</div><div class="small">Período ${period(i.period)}</div></div></div>
      <div style="margin:14px 0"><div class="small muted">FACTURAR A</div><div style="font-weight:600">${c.legal_name}</div>
        <div class="small">RNC / Cédula ${fmtTax(c.tax_id)}${addr(c) ? html` · ${addr(c)}` : ''}</div><div class="small">${[c.phone, c.email].filter(Boolean).join(' · ')}</div></div>
      <div class="table-wrap"><table class="t"><thead><tr><th>#</th><th>Concepto</th><th class="n">Monto</th></tr></thead>
        <tbody>${lines.map((l, n) => html`<tr><td>${n + 1}</td><td>${l.description}${l.late ? html` <span class="pill warn">Rezagado de ${period(l.period)}</span>` : ''}</td><td class="n">${money(l.amount)}</td></tr>`)}</tbody>
        <tfoot><tr><td></td><td style="text-align:right"><b>Total</b></td><td class="n"><b>${money(i.total)}</b></td></tr>
          ${Number(i.paid) > 0 ? html`<tr><td></td><td style="text-align:right">Cobrado</td><td class="n">${money(i.paid)}</td></tr>` : ''}
          <tr><td></td><td style="text-align:right"><b>Saldo pendiente</b></td><td class="n"><b>${money(i.balance)}</b></td></tr></tfoot></table></div>
      <p class="small"><b>Son:</b> ${amountInWords(i.total)}</p>
      <div class="note" style="margin-top:8px"><b>Forma de pago</b><br>${e.bank_account ? html`${e.bank_name || ''}${e.bank_account_type ? ` · ${e.bank_account_type}` : ''} · No. <span class="mono">${e.bank_account}</span>${e.bank_holder ? ` · a nombre de ${e.bank_holder}` : ''}` : html`<span class="muted">Datos bancarios no registrados (Parámetros › Datos fiscales de SOFA).</span>`}
        ${e.terms ? html`<div class="small muted">${e.terms}</div>` : ''}</div>
      ${late ? html`<p class="small muted">Los conceptos "rezagados" corresponden a honorarios de meses anteriores que no habían sido facturados (por ejemplo, pagos de la ARS registrados después del cierre).</p>` : ''}
      ${payments.length ? html`<h3 class="small" style="margin-top:12px">Cobros recibidos</h3><div class="table-wrap"><table class="t"><thead><tr><th>Fecha</th><th>Método</th><th>Referencia</th><th class="n">Monto</th></tr></thead>
        <tbody>${payments.map((p) => html`<tr><td>${date(p.paid_on)}</td><td>${METHOD[p.method] || p.method}</td><td class="mono">${p.reference || '—'}</td><td class="n">${money(p.amount)}</td></tr>`)}</tbody></table></div>` : ''}
      ${i.notes ? html`<p class="small" style="margin-top:10px">${i.notes}</p>` : ''}
      ${i.status === 'anulada' ? html`<p style="margin-top:10px;font-weight:700;color:var(--bad)">FACTURA ANULADA</p>` : ''}
      <p class="small muted" style="margin-top:16px">Honorarios por gestión de facturación médica y reclamaciones ante ARS. Precios no incluyen ITBIS (no aplica por ahora).</p>
    </article>`);
  $('#print', box).addEventListener('click', () => { try { window.print(); } catch (err) { toast(friendlyError(err), 'bad'); } });
  const pdf = async (btn, share) => {
    btn.disabled = true; const label = btn.textContent; btn.textContent = 'Generando…';
    try { const name = await downloadInvoicePdf(d, { share }); toast(share ? 'PDF listo para compartir' : `Descargado ${name}`, 'ok'); }
    catch (err) { if (err?.name !== 'AbortError') toast(friendlyError(err), 'bad'); }
    finally { btn.disabled = false; btn.textContent = label; }
  };
  $('#pdf', box).addEventListener('click', (ev) => pdf(ev.currentTarget, false));
  $('#share', box)?.addEventListener('click', (ev) => pdf(ev.currentTarget, true));
}
