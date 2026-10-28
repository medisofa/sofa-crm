/** SOFA · 5.8.0 · Médico · «Mis glosas»: cuánto dinero del médico está glosado, en disputa, recuperado,
 *  con el desglose por ARS y por causa, en lenguaje del médico. Síntesis sobre glosa_analytics (ya probada).
 *  El médico no trabaja las glosas aquí; ve qué está en juego para presionar. El trabajo va en Reconsideración. */
import { rpc, h, money, pct, num, kpi, table, note, guarded, clientOptions, clientName, monthNow, monthToDate } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const clientSel = h('select', { 'aria-label': 'Consultorio' });
  const clientLbl = h('label', {}, 'Consultorio ', clientSel);   // 5.22.0: se esconde si hay uno solo
  const fromIn = h('input', { type: 'month', value: monthNow(), max: monthNow(), 'aria-label': 'Desde el mes' });

  async function load() {
    if (!clientSel.value) { out.replaceChildren(note('No hay consultorios disponibles para tu usuario.')); return; }
    const data = await guarded(out, () => rpc('glosa_analytics', { p_org: clientSel.value, p_from: monthToDate(fromIn.value) }));
    if (!data) return;
    out.replaceChildren(view(data, desdeMes(fromIn.value)));
  }
  clientSel.addEventListener('change', load);
  fromIn.addEventListener('change', load);

  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Mis glosas'),
    h('p', { class: 'i18-sub' }, 'Cuánto de tu dinero está glosado y qué se ha recuperado. El trabajo de respuesta se hace en «Reconsideración de glosas».'),
    h('div', { class: 'i18-bar' }, clientLbl, h('label', {}, 'Desde ', fromIn)),
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
