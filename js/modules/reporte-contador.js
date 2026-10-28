/** SOFA · 5.12.0 · Médico · «Reporte para mi contador»: lo que el contador necesita del mes, en una pantalla
 *  y en un CSV que abre en Excel. Síntesis sobre accountant_report, que SOFA ya calcula. No inventa datos
 *  y no incluye información de pacientes. */
import { rpc, h, money, num, fmtDate, kpi, table, note, guarded, downloadCsv, clientOptions, clientName, monthNow, monthToDate } from '../services/iter18.js';

const METODOS = { efectivo: 'Efectivo', transferencia: 'Transferencia', tarjeta: 'Tarjeta', cheque: 'Cheque', sin_metodo: 'Sin método registrado' };
const metodo = (k) => METODOS[k] || k;
const mesLargo = (iso) => { if (!iso) return ''; const [y, m] = String(iso).slice(0, 10).split('-');
  return ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'][Number(m) - 1] + ' de ' + y; };

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const clientSel = h('select', { 'aria-label': 'Consultorio' });
  const clientLbl = h('label', {}, 'Consultorio ', clientSel);   // 5.22.0: se esconde si hay uno solo
  const monthIn = h('input', { type: 'month', value: monthNow(), max: monthNow(), 'aria-label': 'Mes' });
  const btnCsv = h('button', { class: 'i18-btn', type: 'button', disabled: true }, 'Descargar para el contador (CSV)');
  let ultimo = null;

  async function load() {
    btnCsv.disabled = true;
    if (!clientSel.value) { out.replaceChildren(note('No hay consultorios disponibles para tu usuario.')); return; }
    const r = await guarded(out, () => rpc('accountant_report', { p_org: clientSel.value, p_period: monthToDate(monthIn.value) }));
    if (!r) return;
    ultimo = r;
    btnCsv.disabled = false;
    out.replaceChildren(view(r));
  }
  clientSel.addEventListener('change', load);
  monthIn.addEventListener('change', load);
  btnCsv.addEventListener('click', () => { if (ultimo) descargar(ultimo); });

  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Reporte para mi contador'),
    h('p', { class: 'i18-sub' }, 'Todo lo que tu contador necesita del mes: lo que entró, de dónde vino y lo que SOFA te facturó. Sin datos de pacientes.'),
    h('div', { class: 'i18-bar' }, clientLbl, h('label', {}, 'Mes ', monthIn), btnCsv),
    out));
  try {
    const cl = await clientOptions();
    cl.forEach((c) => clientSel.append(h('option', { value: c.id }, clientName(c))));
    if (cl.length < 2) clientLbl.hidden = true;   // 5.22.0: no se le pide escogerse a sí mismo de una lista de uno
    await load();
  } catch (e) { out.replaceChildren(note(e.message, 'error')); }
}

/** Convierte {metodo: monto} en filas ordenadas de mayor a menor */
const porMetodo = (obj) => Object.entries(obj || {}).map(([k, v]) => ({ metodo: metodo(k), monto: Number(v) })).sort((a, b) => b.monto - a.monto);

function view(r) {
  const s = r.summary || {}, org = r.organization || {};
  const pagos = r.ars_payments || [], glosas = r.glosas_accepted || [], facturas = r.sofa_invoices || [];
  const priv = porMetodo(r.private_by_method), cop = porMetodo(r.copays_by_method);

  return h('div', {},
    h('p', { class: 'i18-sub' },
      `${org.legal_name || org.name || ''}${org.tax_id ? ' · RNC ' + org.tax_id : ''} · ${mesLargo(r.period)}`),

    h('h3', {}, 'Lo que entró este mes'),
    h('div', { class: 'i18-kpis' },
      kpi('Ingresos totales', money(s.income_total), 'ARS + privados + copagos'),
      kpi('De las ARS', money(s.income_ars), `${num(pagos.length)} pago(s) recibido(s)`),
      kpi('De pacientes privados', money(s.income_private), 'cobros en consultorio'),
      kpi('Copagos y diferencias', money(s.income_copays), 'cobrados al paciente')),

    h('h3', {}, 'Pagos recibidos de las ARS'),
    table(
      [{ label: 'Fecha', key: 'f', get: (p) => fmtDate(p.paid_on) },
       { label: 'ARS', key: 'a', get: (p) => p.ars || '—' },
       { label: 'Forma de pago', key: 'm', get: (p) => metodo(p.method) },
       { label: 'Referencia', key: 'r', get: (p) => p.reference || '—' },
       { label: 'Folio', key: 'o', get: (p) => p.folio || '—' },
       { label: 'Monto', key: 'v', right: true, get: (p) => money(p.amount) }],
      pagos, { f: 'Total', v: money(r.ars_total) }),

    h('h3', {}, 'Cobros en el consultorio, por forma de pago'),
    h('div', { class: 'i18-kpis' },
      kpi('Privados', money(r.private_total), priv.length ? priv.map((x) => `${x.metodo}: ${money(x.monto)}`).join(' · ') : 'sin cobros este mes'),
      kpi('Copagos y diferencias', money(r.copays_total), cop.length ? cop.map((x) => `${x.metodo}: ${money(x.monto)}`).join(' · ') : 'sin copagos este mes')),

    h('h3', {}, 'Honorarios que SOFA te facturó'),
    table(
      [{ label: 'Folio', key: 'f', get: (i) => i.folio || '—' },
       { label: 'NCF', key: 'n', get: (i) => i.ncf || '—' },
       { label: 'Fecha', key: 'd', get: (i) => fmtDate(i.issued_on) },
       { label: 'Estado', key: 'e', get: (i) => i.status || '—' },
       { label: 'Total', key: 't', right: true, get: (i) => money(i.total) },
       { label: 'Pagado', key: 'p', right: true, get: (i) => money(i.paid) },
       { label: 'Balance', key: 'b', right: true, get: (i) => money(i.balance) }],
      facturas, { f: 'Total', t: money(r.sofa_invoices_total) }),
    note('Estos honorarios son un gasto de tu práctica, no un ingreso. El NCF es el que debe registrar tu contador.'),

    h('h3', {}, 'Glosas aceptadas en el mes'),
    table(
      [{ label: 'ARS', key: 'a', get: (g) => g.ars || '—' },
       { label: 'Monto aceptado', key: 'v', right: true, get: (g) => money(g.accepted) }],
      glosas, { a: 'Total', v: money(r.glosas_accepted_total) }),
    note('Una glosa aceptada es dinero que ya no se va a cobrar: no es un ingreso ni un gasto, es facturación que no procedió. Se muestra para que el contador no la busque como cuenta por cobrar.'),

    note(r.note || ''));
}

function descargar(r) {
  const org = r.organization || {}, s = r.summary || {};
  const nombre = org.legal_name || org.name || 'cliente';
  const f = [];
  f.push(['REPORTE PARA EL CONTADOR']);
  f.push(['Cliente', nombre]);
  if (org.tax_id) f.push(['RNC', org.tax_id]);
  f.push(['Mes', mesLargo(r.period)]);
  f.push(['Generado', new Date(r.generated_at || Date.now()).toLocaleString('es-DO')]);
  f.push([]);
  f.push(['RESUMEN']);
  f.push(['Concepto', 'Monto (RD$)']);
  f.push(['Ingresos de las ARS', s.income_ars ?? 0]);
  f.push(['Ingresos de pacientes privados', s.income_private ?? 0]);
  f.push(['Copagos y diferencias', s.income_copays ?? 0]);
  f.push(['INGRESOS TOTALES', s.income_total ?? 0]);
  f.push(['Honorarios facturados por SOFA (gasto)', s.sofa_fees_invoiced ?? 0]);
  f.push(['Glosas aceptadas (facturación que no procedió)', s.glosas_accepted ?? 0]);
  f.push([]);
  f.push(['PAGOS RECIBIDOS DE LAS ARS']);
  f.push(['Fecha', 'ARS', 'Forma de pago', 'Referencia', 'Folio', 'Monto (RD$)']);
  (r.ars_payments || []).forEach((p) => f.push([p.paid_on, p.ars || '', metodo(p.method), p.reference || '', p.folio || '', p.amount]));
  f.push(['', '', '', '', 'Total', r.ars_total ?? 0]);
  f.push([]);
  f.push(['COBROS PRIVADOS POR FORMA DE PAGO']);
  f.push(['Forma de pago', 'Monto (RD$)']);
  porMetodo(r.private_by_method).forEach((x) => f.push([x.metodo, x.monto]));
  f.push(['Total', r.private_total ?? 0]);
  f.push([]);
  f.push(['COPAGOS Y DIFERENCIAS POR FORMA DE PAGO']);
  f.push(['Forma de pago', 'Monto (RD$)']);
  porMetodo(r.copays_by_method).forEach((x) => f.push([x.metodo, x.monto]));
  f.push(['Total', r.copays_total ?? 0]);
  f.push([]);
  f.push(['HONORARIOS FACTURADOS POR SOFA (gasto de la práctica)']);
  f.push(['Folio', 'NCF', 'Fecha', 'Estado', 'Total (RD$)', 'Pagado (RD$)', 'Balance (RD$)']);
  (r.sofa_invoices || []).forEach((i) => f.push([i.folio || '', i.ncf || '', i.issued_on, i.status || '', i.total, i.paid, i.balance]));
  f.push(['', '', '', 'Total', r.sofa_invoices_total ?? 0]);
  f.push([]);
  f.push(['GLOSAS ACEPTADAS (facturación que no procedió)']);
  f.push(['ARS', 'Monto aceptado (RD$)']);
  (r.glosas_accepted || []).forEach((g) => f.push([g.ars || '', g.accepted]));
  f.push(['Total', r.glosas_accepted_total ?? 0]);
  f.push([]);
  f.push([r.note || '']);
  const per = String(r.period || '').slice(0, 7);
  downloadCsv(`contador_${nombre.replace(/[^\p{L}\p{N}]+/gu, '_').slice(0, 40)}_${per}.csv`, f);
}
