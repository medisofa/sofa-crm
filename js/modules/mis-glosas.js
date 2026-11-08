/** SOFA · 5.8.0 · Médico · «Mis glosas»: cuánto dinero del médico está glosado, en disputa, recuperado,
 *  con el desglose por ARS y por causa, en lenguaje del médico. Síntesis sobre glosa_analytics (ya probada).
 *  El médico no trabaja las glosas aquí; ve qué está en juego para presionar. El trabajo va en Reconsideración. */
import { rpc, h, money, pct, num, kpi, table, note, guarded, clientOptions, clientName, monthNow, monthToDate } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const clientSel = h('select', { 'aria-label': 'Consultorio' });
  const clientLbl = h('label', {}, 'Consultorio ', clientSel);   // 5.22.0: se esconde si hay uno solo
  const fromIn = h('input', { type: 'month', value: monthNow(), max: monthNow(), 'aria-label': 'Desde el mes' });
  const printBtn = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: true, title: 'Genera un documento imprimible con el resumen de glosas.' }, '📄 Imprimir');
  let lastData = null; let lastVentana = '';

  async function load() {
    if (!clientSel.value) { out.replaceChildren(note('No hay consultorios disponibles para tu usuario.')); return; }
    const data = await guarded(out, () => rpc('glosa_analytics', { p_org: clientSel.value, p_from: monthToDate(fromIn.value) }));
    if (!data) return;
    lastData = data; lastVentana = desdeMes(fromIn.value);
    out.replaceChildren(view(data, lastVentana)); printBtn.disabled = false;
  }
  clientSel.addEventListener('change', load);
  fromIn.addEventListener('change', load);
  printBtn.addEventListener('click', () => {
    if (!lastData) return;
    const w = openPrint();
    if (!w) return;
    const fecha = new Date().toLocaleDateString('es-DO', { year: 'numeric', month: 'long', day: 'numeric' });
    const t = lastData.totals || {}, rates = lastData.rates || {};
    const byArs = Array.isArray(lastData.by_ars) ? lastData.by_ars : [];
    const byReason = Array.isArray(lastData.by_reason) ? lastData.by_reason : [];
    const blocks = [
      { table: { head: ['Concepto', 'Monto'], rows: [
        ['Glosado', money(t.glosado)],
        ['En disputa (recuperable)', money(t.en_disputa)],
        ['Recuperado', money(t.recuperado)],
        ['Perdido', money(t.aceptado)],
      ], right: [1] } },
    ];
    if (rates.recovery_pct != null) blocks.push({ p: `Tasa de recuperación: ${pct(rates.recovery_pct)} del monto glosado trabajado.` });
    if (byArs.length) {
      blocks.push({ h: 'Por ARS' });
      blocks.push({ table: { head: ['ARS', 'Glosado', 'Recuperado'], rows: byArs.map((r) => [r.ars || r.name || '—', money(r.glosado), money(r.recuperado)]), right: [1, 2] } });
    }
    if (byReason.length) {
      blocks.push({ h: 'Por causa' });
      blocks.push({ table: { head: ['Causa', 'Glosado', 'Veces'], rows: byReason.map((r) => [r.reason || r.causa || r.motivo || '—', money(r.glosado), num(r.glosas || r.count || 0)]), right: [1, 2] } });
    }
    fillPrint(w, `Mis glosas · ${lastVentana}`, `Generado el ${fecha}`, blocks);
  });

  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Mis glosas'),
    h('p', { class: 'i18-sub' }, 'Cuánto de tu dinero está glosado y qué se ha recuperado. El trabajo de respuesta se hace en «Reconsideración de glosas».'),
    h('div', { class: 'i18-bar' }, clientLbl, h('label', {}, 'Desde ', fromIn), printBtn),
    out));
  try {
    const cl = await clientOptions();
    cl.forEach((c) => clientSel.append(h('option', { value: c.id }, clientName(c))));
    if (cl.length < 2) clientLbl.hidden = true;   // 5.22.0: no se le pide escogerse a sí mismo de una lista de uno
    await load();
  } catch (e) { out.replaceChildren(note(e.message, 'error')); }
}

const MES_C = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
/** 'desde oct 2026' — la ventana real de glosa_analytics: del mes elegido hasta hoy. */
function desdeMes(ym) { if (!ym) return ''; const [y, m] = ym.split('-').map(Number); return `desde ${MES_C[m - 1]} ${y}`; }

function view(d, ventana) {
  const t = d.totals || {}, rates = d.rates || {};
  const byArs = Array.isArray(d.by_ars) ? d.by_ars : [];
  const byReason = Array.isArray(d.by_reason) ? d.by_reason : [];
  return h('div', {},
    h('div', { class: 'i18-kpis' },
      // 5.22.0: la ventana va EN la tarjeta. «Glosado» quería decir cuatro períodos distintos
      // en cuatro pantallas y el médico creía que el sistema se contradecía.
      kpi(`Glosado ${ventana}`, money(t.glosado), `${num(t.glosas)} glosa(s)`),
      kpi(`En disputa ${ventana}`, money(t.en_disputa), 'aún se puede recuperar'),
      kpi(`Recuperado ${ventana}`, money(t.recuperado), 'ya ganado'),
      kpi(`Perdido ${ventana}`, money(t.aceptado), 'glosas que no se recuperaron')),
    rates && rates.recovery_pct != null ? note(`Tasa de recuperación: ${pct(rates.recovery_pct)} del monto glosado trabajado.`, 'info') : null,
    h('h3', {}, 'Por ARS'),
    table(
      [{ label: 'ARS', get: (r) => r.ars || r.name || '—' },
       { label: 'Glosado', right: true, get: (r) => money(r.glosado) },
       { label: 'Recuperado', right: true, get: (r) => money(r.recuperado) }],
      byArs),
    h('h3', {}, 'Por causa'),
    table(
      [{ label: 'Causa', get: (r) => r.reason || r.causa || r.motivo || '—' },
       { label: 'Glosado', right: true, get: (r) => money(r.glosado) },
       { label: 'Veces', right: true, get: (r) => num(r.glosas || r.count || 0) }],
      byReason),
    note('¿Tienes glosas por responder? Ve a «Reconsideración de glosas» para armar el paquete y recuperarlas dentro del plazo.'));
}
