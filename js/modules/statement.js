/** SOFA · 18-A · Estado de cuenta mensual con ROI (pantalla + PDF).
 *  Contrato de módulo: export async function render(root, ctx). Si tu router espera otro nombre (mount, default…), ver guía, Paso 0. */
import { rpc, clientOptions, h, money, pct, num, fmtDate, monthNow, monthToDate, clientName, kpi, table, note, guarded } from '../services/iter18.js';

const MESES = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
const periodLabel = (iso) => { const [y, m] = iso.slice(0, 10).split('-'); return `${MESES[Number(m) - 1]} de ${y}`; };

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const clientSel = h('select', { id: 'i18-st-client' });
  const monthIn = h('input', { id: 'i18-st-month', type: 'month', value: monthNow(), max: monthNow() });
  const pdfBtn = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: true }, 'Descargar PDF');
  let data = null;

  async function load() {
    pdfBtn.disabled = true; data = null;
    if (!clientSel.value) return out.replaceChildren(note('No hay clientes disponibles para su usuario.'));
    data = await guarded(out, () => rpc('account_statement', { p_org: clientSel.value, p_period: monthToDate(monthIn.value) }));
    if (!data) return;
    out.replaceChildren(view(data));
    pdfBtn.disabled = false;
  }
  pdfBtn.addEventListener('click', () => { try { buildPdf(data); } catch (e) { out.prepend(note(e.message, 'error')); } });
  clientSel.addEventListener('change', load); monthIn.addEventListener('change', load);

  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Estado de cuenta mensual'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Cliente', clientSel), h('label', {}, 'Mes', monthIn), pdfBtn),
    out));
  try {
    (await clientOptions()).forEach((c) => clientSel.append(h('option', { value: c.id }, clientName(c))));
    await load();
  } catch (e) { out.replaceChildren(note(e.message, 'error')); }
}
export default render;
export const mount = render;

function view(d) {
  const r = d.roi, p = d.production, prev = d.previous;
  const trend = (now, before) => (before > 0 ? `${now >= before ? '▲' : '▼'} ${pct(Math.abs((now - before) / before * 100))} vs. mes anterior` : 'Sin mes anterior para comparar');
  return h('div', { class: 'i18-wrap' },
    h('div', { class: 'i18-kpis' },
      kpi('Reclamado del mes', money(p.claimed), `${num(p.lines)} reclamaciones · ${trend(Number(p.claimed), Number(prev.claimed))}`),
      kpi('Cobrado de las ARS', money(d.cash.collected), `${num(d.cash.payments)} pago(s) · ${trend(Number(d.cash.collected), Number(prev.collected))}`),
      kpi('Honorarios de SOFA', money(d.fees.accrued), r.fee_pct_of_collected != null ? `${pct(r.fee_pct_of_collected)} de lo cobrado` : 'Sin honorarios devengados'),
      kpi('Retorno (ROI)', r.return_x != null ? `${r.return_x}×` : '—', r.roi_pct != null ? `ROI ${pct(r.roi_pct)}` : 'Se calcula cuando hay honorarios')),
    note(r.definition),
    h('h3', {}, 'Producción del mes por ARS'),
    table([
      { label: 'ARS', get: (x) => x.ars }, { label: 'Reclam.', right: true, get: (x) => num(x.lines) }, { label: 'Reclamado', right: true, get: (x) => money(x.claimed) },
      { label: 'Cobrado', right: true, get: (x) => money(x.paid) }, { label: 'Glosado', right: true, get: (x) => money(x.glosado) }, { label: 'Pendiente', right: true, get: (x) => money(x.balance) },
    ], d.by_ars),
    h('h3', {}, 'Glosas'), note(`Glosado: ${money(d.glosas.glosado)} (${pct(d.glosas.rate_pct)} de lo reclamado) · Aceptado: ${money(d.glosas.accepted)} · Recuperado: ${money(d.glosas.recovered)}`),
    h('h3', {}, 'Caja del consultorio'), note(`Cobros privados: ${money(d.private.private_collected)} · Copagos y diferencias: ${money(d.private.copays_collected)} · Pendiente de cobrar: ${money(d.private.pending)}. Son caja del consultorio y no generan honorario de SOFA.`),
    h('h3', {}, 'Lo que las ARS aún deben (hoy)'),
    table([{ label: 'Antigüedad', get: (x) => x.bucket }, { label: 'Lotes', right: true, get: (x) => num(x.lotes) }, { label: 'Saldo', right: true, get: (x) => money(x.balance) }], d.receivable_aging),
    h('h3', {}, 'Facturas de honorarios del mes'),
    table([{ label: 'Folio', get: (x) => x.folio }, { label: 'NCF', get: (x) => x.ncf || 'Pendiente' }, { label: 'Total', right: true, get: (x) => money(x.total) },
           { label: 'Pagado', right: true, get: (x) => money(x.paid) }, { label: 'Saldo', right: true, get: (x) => money(x.balance) }, { label: 'Vence', get: (x) => fmtDate(x.due_on) }], d.fees.invoices));
}

function buildPdf(d) {
  const lib = window.jspdf && window.jspdf.jsPDF;
  if (!lib) throw new Error('No se cargó la librería de PDF. Recargue la página (Ctrl+F5) e intente de nuevo.');
  const doc = new lib({ unit: 'pt', format: 'letter' });
  const W = doc.internal.pageSize.getWidth(), M = 40; let y = 48;
  const auto = (opts) => (typeof doc.autoTable === 'function' ? doc.autoTable(opts) : window.autoTable(doc, opts));
  const after = () => (doc.lastAutoTable ? doc.lastAutoTable.finalY : y) + 18;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(18); doc.text('Estado de cuenta mensual', M, y);
  doc.setFontSize(10); doc.setFont('helvetica', 'normal'); doc.text('SOFA · Soluciones de Facturación Médica', W - M, y, { align: 'right' }); y += 22;
  doc.setFontSize(12); doc.text(`${d.organization.legal_name}${d.organization.tax_id ? ' · RNC/Cédula ' + d.organization.tax_id : ''}`, M, y); y += 16;
  doc.setFontSize(10); doc.text(`Período: ${periodLabel(d.period)} · Generado el ${fmtDate(d.generated_at)}`, M, y); y += 20;
  const r = d.roi;
  auto({ startY: y, theme: 'grid', head: [['Indicador', 'Valor']], styles: { fontSize: 9 }, headStyles: { fillColor: [31, 111, 235] },
    body: [['Reclamado del mes', money(d.production.claimed)], ['Cobrado de las ARS en el mes', money(d.cash.collected)], ['Honorarios de SOFA devengados', money(d.fees.accrued)],
           ['Retorno (cobrado ÷ honorarios)', r.return_x != null ? `${r.return_x}×` : 'No aplica'], ['ROI', r.roi_pct != null ? pct(r.roi_pct) : 'No aplica'],
           ['Glosado (% de lo reclamado)', `${money(d.glosas.glosado)} (${pct(d.glosas.rate_pct)})`]] });
  y = after();
  auto({ startY: y, theme: 'striped', head: [['ARS', 'Reclam.', 'Reclamado', 'Cobrado', 'Glosado', 'Pendiente']], styles: { fontSize: 8.5 }, headStyles: { fillColor: [31, 111, 235] },
    columnStyles: { 1: { halign: 'right' }, 2: { halign: 'right' }, 3: { halign: 'right' }, 4: { halign: 'right' }, 5: { halign: 'right' } },
    body: d.by_ars.length ? d.by_ars.map((x) => [x.ars, x.lines, money(x.claimed), money(x.paid), money(x.glosado), money(x.balance)]) : [['Sin reclamaciones en el mes', '', '', '', '', '']] });
  y = after();
  auto({ startY: y, theme: 'striped', head: [['Lo que las ARS aún deben', 'Lotes', 'Saldo']], styles: { fontSize: 8.5 }, headStyles: { fillColor: [90, 100, 115] },
    columnStyles: { 1: { halign: 'right' }, 2: { halign: 'right' } }, body: d.receivable_aging.length ? d.receivable_aging.map((x) => [x.bucket, x.lotes, money(x.balance)]) : [['Sin saldos pendientes', '', '']] });
  y = after();
  doc.setFontSize(8); doc.setTextColor(90, 100, 115);
  doc.text(doc.splitTextToSize(`Definición de ROI: ${r.definition} Los cobros privados y copagos son caja del consultorio y no generan honorario de SOFA.`, W - 2 * M), M, y);
  doc.save(`estado_cuenta_${(d.organization.name || 'cliente').replace(/[^\w]+/g, '_')}_${d.period.slice(0, 7)}.pdf`);
}
