/** SOFA · 5.8.0 · Médico · «Mi dinero»: resumen financiero del médico en una sola pantalla.
 *  Síntesis sobre lo que SOFA ya calcula: account_statement (cobrado, reclamado, honorarios, ROI, glosas)
 *  y collection_calendar (lo que está por cobrar y lo atrasado). No inventa datos. */
import { rpc, h, money, pct, num, kpi, table, note, guarded, clientOptions, clientName, monthNow, monthToDate } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const clientSel = h('select', { 'aria-label': 'Cliente' });
  const monthIn = h('input', { type: 'month', value: monthNow(), max: monthNow(), 'aria-label': 'Mes' });

  async function load() {
    if (!clientSel.value) { out.replaceChildren(note('No hay clientes disponibles para tu usuario.')); return; }
    const org = clientSel.value, period = monthToDate(monthIn.value);
    const [st, cc] = await Promise.all([
      guarded(out, () => rpc('account_statement', { p_org: org, p_period: period })),
      rpc('collection_calendar', { p_org: org }).catch(() => null),
    ]);
    if (!st) return;
    out.replaceChildren(view(st, cc));
  }
  clientSel.addEventListener('change', load);
  monthIn.addEventListener('change', load);

  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Mi dinero'),
    h('p', { class: 'i18-sub' }, 'Cómo vas este mes: lo cobrado, lo que falta por cobrar y lo que las glosas te están frenando.'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Cliente ', clientSel), h('label', {}, 'Mes ', monthIn)),
    out));
  try {
    (await clientOptions()).forEach((c) => clientSel.append(h('option', { value: c.id }, clientName(c))));
    await load();
  } catch (e) { out.replaceChildren(note(e.message, 'error')); }
}

function trend(now, before) {
  now = Number(now); before = Number(before);
  if (!(before > 0)) return 'sin mes anterior';
  return `${now >= before ? '▲' : '▼'} ${pct(Math.abs((now - before) / before * 100))} vs. mes anterior`;
}

function view(st, cc) {
  const p = st.production || {}, cash = st.cash || {}, fees = st.fees || {}, r = st.roi || {}, g = st.glosas || {}, prev = st.previous || {};
  const t = (cc && cc.totals) || {};
  return h('div', {},
    h('div', { class: 'i18-kpis' },
      kpi('Cobrado este mes', money(cash.collected), `${num(cash.payments)} pago(s) · ${trend(cash.collected, prev.collected)}`),
      kpi('Reclamado este mes', money(p.claimed), `${num(p.lines)} reclamación(es) · ${trend(p.claimed, prev.claimed)}`),
      kpi('Honorarios de SOFA', money(fees.accrued), r.fee_pct_of_collected != null ? `${pct(r.fee_pct_of_collected)} de lo cobrado` : 'sin honorarios este mes'),
      kpi('Retorno (ROI)', r.return_x != null ? `${r.return_x}×` : '—', r.roi_pct != null ? `ROI ${pct(r.roi_pct)}` : 'se calcula con honorarios')),
    h('h3', {}, 'Lo que está por cobrarte'),
    cc ? h('div', { class: 'i18-kpis' },
      kpi('Por cobrar (total)', money(t.balance), `${num(t.lotes)} lote(s) radicado(s)`),
      kpi('Atrasado', money(t.late_balance), `${num(t.late_lotes)} lote(s) vencido(s)`),
      kpi('Esta semana', money(t.this_week_balance), 'vence en los próximos 7 días'))
      : note('El calendario de cobros no está disponible ahora.', 'info'),
    h('h3', {}, 'Glosas (dinero en juego)'),
    h('div', { class: 'i18-kpis' },
      kpi('Glosado', money(g.glosado), g.rate_pct != null ? `${pct(g.rate_pct)} de lo reclamado` : ''),
      kpi('Recuperado', money(g.recovered), 'de glosas trabajadas'),
      kpi('Aceptado (perdido)', money(g.accepted), 'glosas que no se recuperaron')),
    note('Las cifras salen de tu estado de cuenta y del calendario de cobros. Para el detalle por ARS, abre «Estado de cuenta» o «Calendario de cobros».'));
}
