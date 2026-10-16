/** SOFA · 5.8.0 · Médico · «Mis glosas»: cuánto dinero del médico está glosado, en disputa, recuperado,
 *  con el desglose por ARS y por causa, en lenguaje del médico. Síntesis sobre glosa_analytics (ya probada).
 *  El médico no trabaja las glosas aquí; ve qué está en juego para presionar. El trabajo va en Reconsideración. */
import { rpc, h, money, pct, num, kpi, table, note, guarded, clientOptions, clientName, monthNow, monthToDate } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const clientSel = h('select', { 'aria-label': 'Cliente' });
  const fromIn = h('input', { type: 'month', value: monthNow(), max: monthNow(), 'aria-label': 'Desde el mes' });

  async function load() {
    if (!clientSel.value) { out.replaceChildren(note('No hay clientes disponibles para tu usuario.')); return; }
    const data = await guarded(out, () => rpc('glosa_analytics', { p_org: clientSel.value, p_from: monthToDate(fromIn.value) }));
    if (!data) return;
    out.replaceChildren(view(data));
  }
  clientSel.addEventListener('change', load);
  fromIn.addEventListener('change', load);

  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Mis glosas'),
    h('p', { class: 'i18-sub' }, 'Cuánto de tu dinero está glosado y qué se ha recuperado. El trabajo de respuesta se hace en «Reconsideración de glosas».'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Cliente ', clientSel), h('label', {}, 'Desde ', fromIn)),
    out));
  try {
    (await clientOptions()).forEach((c) => clientSel.append(h('option', { value: c.id }, clientName(c))));
    await load();
  } catch (e) { out.replaceChildren(note(e.message, 'error')); }
}

function view(d) {
  const t = d.totals || {}, rates = d.rates || {};
  const byArs = Array.isArray(d.by_ars) ? d.by_ars : [];
  const byReason = Array.isArray(d.by_reason) ? d.by_reason : [];
  return h('div', {},
    h('div', { class: 'i18-kpis' },
      kpi('Glosado', money(t.glosado), `${num(t.glosas)} glosa(s)`),
      kpi('En disputa', money(t.en_disputa), 'aún se puede recuperar'),
      kpi('Recuperado', money(t.recuperado), 'ya ganado'),
      kpi('Aceptado (perdido)', money(t.aceptado), 'no se recuperó')),
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
