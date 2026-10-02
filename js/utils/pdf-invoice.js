/**
 * SOFA · Factura de honorarios en PDF (1.5.0), formato de factura con NCF de República Dominicana.
 * jsPDF y su plugin de tablas viven en /vendor (la CSP solo permite scripts propios) y se cargan solo al generar.
 */
const VENDOR = ['vendor/jspdf-4.2.1.umd.min.js', 'vendor/jspdf-autotable-5.0.8.min.js'];
let loading = null;
function loadScript(src) {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[data-vendor="${src}"]`)) { resolve(); return; }
    const s = document.createElement('script'); s.src = src; s.dataset.vendor = src; s.async = false;
    s.onload = () => resolve(); s.onerror = () => reject(new Error(`No se pudo cargar ${src}. Revisa la conexión y vuelve a intentar.`));
    document.head.appendChild(s);
  });
}
export async function loadPdfLib() {
  if (window.jspdf?.jsPDF?.API?.autoTable) return window.jspdf.jsPDF;
  loading = loading || (async () => { for (const src of VENDOR) await loadScript(src); })();
  await loading;
  if (!window.jspdf?.jsPDF) throw new Error('La librería de PDF no se cargó');
  return window.jspdf.jsPDF;
}

// ---------------------------------------------------------------- utilidades de formato
const rd = (n) => `RD$ ${Number(n || 0).toLocaleString('es-DO', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const fdate = (d) => { if (!d) return '—'; const [y, m, day] = String(d).slice(0, 10).split('-'); return `${day}/${m}/${y}`; };
const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const fperiod = (d) => { if (!d) return '—'; const [y, m] = String(d).split('-'); return `${MONTHS[Number(m) - 1]} ${y}`; };
export const fmtTax = (t) => (!t ? '—' : t.length === 9 ? `${t.slice(0, 3)}-${t.slice(3, 8)}-${t.slice(8)}` : t.length === 11 ? `${t.slice(0, 3)}-${t.slice(3, 10)}-${t.slice(10)}` : t);

/** Tipo de comprobante según el prefijo del NCF (DGII) */
export function ncfKind(ncf) {
  const p = String(ncf || '').toUpperCase().slice(0, 3);
  return { B01: 'FACTURA DE CRÉDITO FISCAL', B02: 'FACTURA DE CONSUMO', B14: 'FACTURA · RÉGIMEN ESPECIAL', B15: 'FACTURA GUBERNAMENTAL',
    E31: 'FACTURA DE CRÉDITO FISCAL ELECTRÓNICA', E32: 'FACTURA DE CONSUMO ELECTRÓNICA', E33: 'NOTA DE DÉBITO ELECTRÓNICA', E34: 'NOTA DE CRÉDITO ELECTRÓNICA' }[p] || 'FACTURA';
}

/** Monto en letras (pesos dominicanos), como se acostumbra en las facturas */
const U = ['', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez', 'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve',
  'veinte', 'veintiuno', 'veintidós', 'veintitrés', 'veinticuatro', 'veinticinco', 'veintiséis', 'veintisiete', 'veintiocho', 'veintinueve'];
const D = ['', '', '', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];
const C = ['', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos', 'seiscientos', 'setecientos', 'ochocientos', 'novecientos'];
function under1000(n) {
  if (n === 0) return '';
  if (n === 100) return 'cien';
  const c = Math.floor(n / 100); const r = n % 100;
  const rest = r < 30 ? U[r] : `${D[Math.floor(r / 10)]}${r % 10 ? ` y ${U[r % 10]}` : ''}`;
  return [C[c], rest].filter(Boolean).join(' ');
}
export function amountInWords(amount) {
  const v = Math.round(Number(amount || 0) * 100); const int = Math.floor(v / 100); const cents = v % 100;
  if (int === 0) return `Cero pesos dominicanos con ${String(cents).padStart(2, '0')}/100`;
  const parts = []; const mill = Math.floor(int / 1e6); const th = Math.floor((int % 1e6) / 1000); const rest = int % 1000;
  if (mill) parts.push(mill === 1 ? 'un millón' : `${under1000(mill).replace(/uno$/, 'un')} millones`);
  if (th) parts.push(th === 1 ? 'mil' : `${under1000(th).replace(/uno$/, 'un').replace(/veintiuno$/, 'veintiún')} mil`);
  if (rest) parts.push(under1000(rest));
  let words = parts.join(' ').replace(/\s+/g, ' ').trim();
  if (rest === 0 && mill && !th) words += ' de';
  words = words.replace(/uno$/, 'un').replace(/\bveintiun\b/g, 'veintiún');
  const unit = int === 1 ? 'peso dominicano' : 'pesos dominicanos';
  return `${words.charAt(0).toUpperCase()}${words.slice(1)} ${unit} con ${String(cents).padStart(2, '0')}/100`;
}

// ---------------------------------------------------------------- documento
const NAVY = [26, 54, 93]; const WINE = [139, 0, 0]; const SOFT = [243, 246, 250]; const GRAY = [96, 104, 120]; const LINE = [214, 219, 227];
let logoData = null;
async function logo() {
  if (logoData) return logoData;
  try {
    const blob = await (await fetch('assets/brand/sofa-logo.png')).blob();
    logoData = await new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(blob); });
  } catch { logoData = null; }
  return logoData;
}

/**
 * Construye el PDF a partir de public.sofa_invoice_document(). Devuelve { doc, fileName }.
 * Formato (plantilla aprobada 02/10/2026): logo arriba a la izquierda; "Factura" y sus datos arriba a la derecha;
 * De / Facturar a; tabla Descripción · Tarifa · Cantidad · Impuesto · Importe; Instrucción de pago y totales con Saldo pendiente.
 * Colores corporativos: azul marino #1A365D y vino #8B0000. Carta, márgenes 14 mm.
 */
export async function buildInvoicePdf(d) {
  const JsPDF = await loadPdfLib();
  const { issuer: e, client: c, invoice: i, lines, payments } = d;
  const doc = new JsPDF({ unit: 'mm', format: 'letter' });
  const W = doc.internal.pageSize.getWidth(); const M = 14; const half = (W - 2 * M - 8) / 2; const xr = M + half + 8;
  doc.setProperties({ title: `Factura ${i.folio}`, subject: 'Honorarios SOFA', author: e.legal_name || 'SOFA', creator: 'SOFA' });
  const box = (x, y, w, h, fill = null) => { doc.setDrawColor(...LINE); doc.setLineWidth(0.3); if (fill) { doc.setFillColor(...fill); doc.roundedRect(x, y, w, h, 1.5, 1.5, 'FD'); } else doc.roundedRect(x, y, w, h, 1.5, 1.5); };

  // 1) Logo (izquierda) — misma área que "Añadir logotipo" en la plantilla
  const img = await logo();
  if (img) doc.addImage(img, 'PNG', M, 12, half, half * 321 / 942, undefined, 'FAST');
  else { doc.setFont('helvetica', 'bold'); doc.setFontSize(22); doc.setTextColor(...NAVY); doc.text('SOFA', M, 26); }

  // 2) Título y datos de la factura (derecha)
  doc.setFont('helvetica', 'bold'); doc.setFontSize(24); doc.setTextColor(...NAVY); doc.text('Factura', W - M, 21, { align: 'right' });
  doc.setFontSize(8); doc.setTextColor(...WINE); doc.text('DOCUMENTO DE COBRO', W - M, 26, { align: 'right' });
  // 1.7: el comprobante fiscal se emite en el sistema fiscal externo; aquí va solo como referencia
  const meta = [['Núm. de factura', i.folio], ['Comprobante fiscal', i.ncf || 'En sistema fiscal'], ['Fecha de la factura', fdate(i.issued_on)], ['Vencimiento', fdate(i.due_on)], ['Período', fperiod(i.period)]];
  meta.forEach(([k, v], n) => {
    const y = 29 + n * 7.2; box(xr, y, half, 6.2, SOFT);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.2); doc.setTextColor(...GRAY); doc.text(`${k}:`, xr + 3, y + 4.2);
    doc.setFont('helvetica', 'bold'); doc.setTextColor(25, 25, 25); doc.text(String(v), xr + half - 3, y + 4.2, { align: 'right' });
  });

  // 3) De / Facturar a
  let y = 70;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...NAVY); doc.text('De', M, y); doc.text('Facturar a', W - M, y, { align: 'right' });
  doc.setDrawColor(...WINE); doc.setLineWidth(0.6); doc.line(M, y + 1.5, M + 8, y + 1.5); doc.line(W - M - 19, y + 1.5, W - M, y + 1.5);
  const party = (x, o, align) => {
    const tx = align === 'right' ? x + half - 3 : x + 3; const opt = align === 'right' ? { align: 'right' } : {};
    box(x, y + 4, half, 8, SOFT); doc.setFont('helvetica', 'bold'); doc.setFontSize(9.5); doc.setTextColor(25, 25, 25);
    doc.text(doc.splitTextToSize(o.legal_name || '—', half - 6)[0], tx, y + 9.3, opt);
    const det = [`RNC / Cédula: ${fmtTax(o.tax_id)}`, [o.address, o.city].filter(Boolean).join(', ') || null, o.phone ? `Tel.: ${o.phone}` : null, o.email || null].filter(Boolean);
    box(x, y + 14, half, 6 + det.length * 4.4);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(55, 55, 55);
    det.forEach((t, k) => doc.text(doc.splitTextToSize(t, half - 6)[0], tx, y + 19 + k * 4.4, opt));
    return 20 + det.length * 4.4;
  };
  const issuerName = { ...e, legal_name: e.trade_name && e.legal_name ? `${e.trade_name} · ${e.legal_name}` : (e.legal_name || 'SOFA') };
  const hL = party(M, issuerName, 'left'); const hR = party(xr, c, 'right');
  y += Math.max(hL, hR) + 6;
  doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(...GRAY); doc.text(`Período facturado: ${fperiod(i.period)}`, M, y); y += 3;

  // 4) Detalle
  const multi = new Set(lines.map((l) => l.service_code || 'facturacion')).size > 1; let lastSvc = null;
  const body = lines.length ? lines.flatMap((l) => {
    const row = [`${l.description}${l.late ? `\nRezagado de ${fperiod(l.period)}` : ''}`, Number(l.amount).toLocaleString('es-DO', { minimumFractionDigits: 2 }), '1', '0.00%', Number(l.amount).toLocaleString('es-DO', { minimumFractionDigits: 2 })];
    if (!multi || l.service === lastSvc) return [row];
    lastSvc = l.service;   // varios servicios: subtítulo por servicio
    return [[{ content: (l.service || 'Facturación médica').toUpperCase(), colSpan: 5, styles: { fontStyle: 'bold', fillColor: SOFT, textColor: NAVY } }], row];
  })
    : [[i.status === 'anulada' ? 'Factura anulada antes de la versión 1.5: sus conceptos se liberaron para volver a facturarse.' : 'Sin conceptos', '', '', '', '']];
  doc.autoTable({
    startY: y + 2, margin: { left: M, right: M }, head: [['DESCRIPCIÓN', 'TARIFA, RD$', 'CANTIDAD', 'IMPUESTO', 'IMPORTE, RD$']], body,
    styles: { font: 'helvetica', fontSize: 8.6, cellPadding: 2.4, textColor: [25, 25, 25], lineColor: LINE, lineWidth: 0.2, valign: 'top' },
    headStyles: { fillColor: NAVY, textColor: 255, fontStyle: 'bold', fontSize: 8 },
    columnStyles: { 0: { cellWidth: 'auto' }, 1: { cellWidth: 28, halign: 'right' }, 2: { cellWidth: 22, halign: 'center' }, 3: { cellWidth: 22, halign: 'center' }, 4: { cellWidth: 30, halign: 'right' } },
    didParseCell: (h) => { if (h.section === 'head' && h.column.index > 0) h.cell.styles.halign = h.column.index === 2 || h.column.index === 3 ? 'center' : 'right'; },
    alternateRowStyles: { fillColor: [248, 249, 252] }
  });
  y = doc.lastAutoTable.finalY + 6;
  doc.setDrawColor(...LINE); doc.setLineWidth(0.3); doc.line(M, y, W - M, y); y += 6;
  if (y > 200) { doc.addPage(); y = 20; }

  // 5) Instrucción de pago (izquierda) y totales (derecha)
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...NAVY); doc.text('Instrucción de pago', M, y);
  const bank = [e.bank_name && `Banco: ${e.bank_name}`, e.bank_account_type && `Tipo de cuenta: ${e.bank_account_type}`, e.bank_account && `No. de cuenta: ${e.bank_account}`, e.bank_holder && `A nombre de: ${e.bank_holder}`].filter(Boolean);
  const terms = doc.splitTextToSize(e.terms || '', half - 6);
  const ph = Math.max(34, 8 + bank.length * 4.6 + terms.length * 4 + 4);
  box(M, y + 3, half, ph);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(8.6); doc.setTextColor(40, 40, 40);
  (bank.length ? bank : ['Datos bancarios no registrados (Parámetros › Datos fiscales de SOFA).']).forEach((t, k) => doc.text(t, M + 3, y + 9 + k * 4.6));
  doc.setFontSize(7.8); doc.setTextColor(...GRAY); doc.text(terms, M + 3, y + 9 + Math.max(bank.length, 1) * 4.6 + 2);
  const tot = [['Total parcial', i.total], ['Impuesto sobre la venta', 0], ['Descuento', 0]];
  if (Number(i.paid) > 0) tot.push(['Cobrado', i.paid]);
  tot.forEach(([k, v], n) => {
    const yy = y + 2 + n * 6.4; doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(25, 25, 25); doc.text(k, xr + 3, yy);
    doc.setFont('helvetica', k === 'Total parcial' ? 'bold' : 'normal'); doc.setTextColor(k === 'Total parcial' ? 25 : 120, k === 'Total parcial' ? 25 : 120, k === 'Total parcial' ? 25 : 120);
    doc.text(rd(v), W - M - 3, yy, { align: 'right' });
  });
  const ys = y + 2 + tot.length * 6.4 - 1;
  doc.setFillColor(...SOFT); doc.setDrawColor(...SOFT); doc.roundedRect(xr, ys, half, 11, 1.5, 1.5, 'F');
  doc.setFillColor(...WINE); doc.rect(xr, ys, 1.4, 11, 'F');
  doc.setFont('helvetica', 'bold'); doc.setFontSize(9.5); doc.setTextColor(...NAVY); doc.text('Saldo pendiente', xr + 4, ys + 7);
  doc.setFillColor(255, 255, 255); doc.setDrawColor(...LINE); doc.roundedRect(xr + half / 2 - 7, ys + 2.6, 14, 5.8, 1.2, 1.2, 'FD');
  doc.setFontSize(8); doc.setTextColor(...NAVY); doc.text('DOP', xr + half / 2, ys + 6.6, { align: 'center' });
  doc.setFontSize(11.5); doc.setTextColor(25, 25, 25); doc.text(rd(i.balance), W - M - 3, ys + 7.3, { align: 'right' });
  y = Math.max(y + 3 + ph, ys + 11) + 6;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(8.5); doc.setTextColor(25, 25, 25); doc.text('Son:', M, y);
  doc.setFont('helvetica', 'normal'); doc.text(doc.splitTextToSize(amountInWords(i.total), W - 2 * M - 10), M + 9, y); y += 7;

  // 6) Cobros recibidos
  if (payments.length) {
    doc.autoTable({ startY: y, margin: { left: M, right: M }, head: [['Cobros recibidos · fecha', 'Método', 'Referencia', 'Monto, RD$']],
      body: payments.map((p) => [fdate(p.paid_on), p.method, p.reference || '—', Number(p.amount).toLocaleString('es-DO', { minimumFractionDigits: 2 })]),
      styles: { fontSize: 8, cellPadding: 1.8, lineColor: LINE, lineWidth: 0.2 }, headStyles: { fillColor: GRAY, textColor: 255 }, columnStyles: { 3: { halign: 'right' } } });
    y = doc.lastAutoTable.finalY + 6;
  }

  // 7) Firmas
  if (y > 245) { doc.addPage(); y = 30; }
  y = Math.max(y + 12, 236);
  doc.setDrawColor(120, 120, 120); doc.setLineWidth(0.3); doc.line(M, y, M + 70, y); doc.line(W - M - 70, y, W - M, y);
  doc.setFontSize(8); doc.setTextColor(...GRAY); doc.text('Preparado por (SOFA)', M + 35, y + 4, { align: 'center' }); doc.text('Recibido por (nombre, firma y fecha)', W - M - 35, y + 4, { align: 'center' });

  // 8) Pie, franja corporativa y marca de anulada
  const pages = doc.getNumberOfPages();
  for (let p = 1; p <= pages; p += 1) {
    doc.setPage(p); const H = doc.internal.pageSize.getHeight();
    doc.setFillColor(...NAVY); doc.rect(0, H - 5, W * 0.72, 5, 'F'); doc.setFillColor(...WINE); doc.rect(W * 0.72, H - 5, W * 0.28, 5, 'F');
    doc.setFontSize(7.5); doc.setTextColor(...GRAY);
    doc.text(`${i.folio} · Documento de cobro no fiscal · comprobante fiscal ${i.ncf ? i.ncf : `emitido en ${e.fiscal_system || 'el sistema fiscal de SOFA'}`} · Página ${p} de ${pages}`, W / 2, H - 8, { align: 'center' });
    if (i.status === 'anulada') {
      doc.saveGraphicsState?.(); doc.setGState?.(new doc.GState({ opacity: 0.16 }));
      doc.setFont('helvetica', 'bold'); doc.setFontSize(90); doc.setTextColor(...WINE); doc.text('ANULADA', W / 2, H / 2 + 10, { align: 'center', angle: 35 });
      doc.restoreGraphicsState?.();
      doc.setFontSize(9); doc.setTextColor(...WINE); doc.text(`Anulada el ${fdate(i.voided_at)}. Motivo: ${String(i.notes || '').replace(/^.*?Anulada[^:]*:\s*/, '') || '—'}`.slice(0, 140), M, H - 13);
    }
  }
  return { doc, fileName: `${i.folio}${i.status === 'anulada' ? '-ANULADA' : ''}.pdf` };
}

/** Descarga el PDF; en celulares que lo permiten ofrece compartirlo (WhatsApp, correo) */
export async function downloadInvoicePdf(d, { share = false } = {}) {
  const { doc, fileName } = await buildInvoicePdf(d);
  if (share && navigator.canShare) {
    const file = new File([doc.output('blob')], fileName, { type: 'application/pdf' });
    if (navigator.canShare({ files: [file] })) { await navigator.share({ files: [file], title: fileName, text: `Factura ${d.invoice.folio} · ${rd(d.invoice.total)}` }); return fileName; }
  }
  doc.save(fileName);
  return fileName;
}

// ---------------------------------------------------------------- documentos comerciales A–E (membrete SOFA)
/**
 * Carta / contrato con membrete: logo arriba a la izquierda, código y fecha a la derecha, texto con saltos
 * respetados, franja corporativa y numeración al pie. `d` = fila de commercial_documents.
 */
export async function buildLetterPdf(d) {
  const JsPDF = await loadPdfLib();
  const doc = new JsPDF({ unit: 'mm', format: 'letter' });
  const W = doc.internal.pageSize.getWidth(); const H = doc.internal.pageSize.getHeight(); const M = 20;
  const v = d.variables || {};
  doc.setProperties({ title: d.title, subject: 'Documento comercial SOFA', author: v['sofa.razon_social'] || 'SOFA', creator: 'SOFA' });
  const img = await logo();
  const head = () => {
    if (img) doc.addImage(img, 'PNG', M, 10, 58, 58 * 321 / 942, undefined, 'FAST');
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...NAVY); doc.text(`Documento ${d.template_code}`, W - M, 15, { align: 'right' });
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...GRAY);
    doc.text(`Versión de plantilla ${d.template_version} · ${fdate(String(d.created_at || '').slice(0, 10))}`, W - M, 19.5, { align: 'right' });
    doc.setDrawColor(...WINE); doc.setLineWidth(0.6); doc.line(M, 33, W - M, 33);
  };
  head();
  doc.setFont('times', 'normal'); doc.setFontSize(11); doc.setTextColor(25, 25, 25);
  let y = 42; const lh = 5.4;
  for (const para of String(d.content || '').split('\n')) {
    const isTitle = para.trim() && para === para.toUpperCase() && /[A-ZÁÉÍÓÚÑ]/.test(para) && para.trim().length < 90;
    doc.setFont('times', isTitle ? 'bold' : 'normal');
    const wrapped = para.trim() ? doc.splitTextToSize(para, W - 2 * M) : [''];
    for (const ln of wrapped) {
      if (y > H - 24) { doc.addPage(); head(); y = 42; doc.setFont('times', isTitle ? 'bold' : 'normal'); doc.setFontSize(11); doc.setTextColor(25, 25, 25); }
      doc.text(ln, isTitle ? W / 2 : M, y, isTitle ? { align: 'center' } : {}); y += lh;
    }
  }
  const pages = doc.getNumberOfPages();
  for (let p = 1; p <= pages; p += 1) {
    doc.setPage(p);
    doc.setFillColor(...NAVY); doc.rect(0, H - 5, W * 0.72, 5, 'F'); doc.setFillColor(...WINE); doc.rect(W * 0.72, H - 5, W * 0.28, 5, 'F');
    doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(...GRAY);
    doc.text(`${v['sofa.razon_social'] || 'SOFA'}${v['sofa.rnc'] ? ` · RNC ${v['sofa.rnc']}` : ''} · ${d.title} · Página ${p} de ${pages}`.slice(0, 160), W / 2, H - 8, { align: 'center' });
    if (d.status === 'anulado') {
      doc.saveGraphicsState?.(); doc.setGState?.(new doc.GState({ opacity: 0.16 })); doc.setFont('helvetica', 'bold'); doc.setFontSize(80); doc.setTextColor(...WINE);
      doc.text('ANULADO', W / 2, H / 2, { align: 'center', angle: 35 }); doc.restoreGraphicsState?.();
    }
  }
  const safe = d.title.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^\w.-]+/g, '_').slice(0, 80);
  return { doc, fileName: `${safe}.pdf` };
}
export async function downloadLetterPdf(d) { const { doc, fileName } = await buildLetterPdf(d); doc.save(fileName); return fileName; }
