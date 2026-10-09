/** SOFA · 3.9 · Iteración 49 · Tablero de dirección de SOFA (Super Admin y Administrador).
 *  MRR contra la meta, mezcla por servicio, retención, ARPA, horas por cliente y conversión de diagnósticos. */
import { rpc, h, money, note, guarded, kpi } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const m = h('input', { type: 'month', id: 'di-m', value: new Date().toISOString().slice(0, 7) });
  const pdf = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Informe del mes (imprimir o PDF)');
  const box = h('div', { 'aria-live': 'polite' });
  const cfg = h('div');
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Tablero de dirección'),
    h('p', { class: 'i18-sub' }, 'El negocio SOFA contra su meta. Los ingresos salen de los honorarios calculados de cada mes.'),
    h('div', { class: 'i18-bar' }, h('label', { for: 'di-m' }, 'Mes', m), pdf), box, cfg));
  let last = null;

  async function load() {
    const d = await guarded(box, () => rpc('direction_board', { p_month: `${m.value}-01` }));
    if (!d) return;
    last = d;
    const max = Math.max(1, ...d.trend.map((t) => Number(t.mrr)), Number(d.target_mrr));
    const r = d.retention_12m; const f = d.funnel || {};
    box.replaceChildren(
      h('div', { class: 'i18-kpis' },
        kpi('Ingreso recurrente (MRR)', money(d.mrr), `${d.mrr_pct_of_target ?? 0} % de la meta ${money(d.target_mrr)}`),
        kpi('Facturación médica en la mezcla', d.billing_mix_pct == null ? '—' : `${d.billing_mix_pct} %`, `Meta: ${d.target_mix_pct} %`),
        kpi('Clientes que pagan', String(d.clients_paying), `Ingreso por cliente: ${money(d.arpa)}`),
        kpi('Retención a 12 meses', r.pct == null ? '—' : `${r.pct} %`, `${r.kept} de ${r.base} · meta 90 %`),
        kpi('Clientes con 2 o más servicios', d.multi_service_pct == null ? '—' : `${d.multi_service_pct} %`),
        kpi('Diagnóstico gratuito → cliente', f.pct == null ? '—' : `${f.pct} %`, `${f.converted || 0} de ${f.diagnostics || 0} · meta 40 %`)),
      h('h3', {}, 'MRR de los últimos 12 meses'),
      h('div', { class: 'di-chart', role: 'img', 'aria-label': 'Ingreso recurrente por mes' },
        h('div', { class: 'di-target', style: `bottom:${(100 * d.target_mrr) / max}%`, title: `Meta ${money(d.target_mrr)}` }),
        ...d.trend.map((t) => h('div', { class: 'di-col', title: `${t.month.slice(0, 7)}: ${money(t.mrr)} · ${t.clients} cliente(s)` },
          h('span', { style: `height:${(100 * Number(t.mrr)) / max}%` }), h('small', {}, t.month.slice(5, 7))))),
      h('h3', {}, 'Mezcla por servicio'),
      d.mix.length ? table(['Servicio', 'Monto', '%'], d.mix.map((x) => [x.service, money(x.amount), `${x.pct ?? 0} %`]), [1, 2]) : note('Sin honorarios en el mes.'),
      h('h3', {}, 'Por cliente'),
      d.by_client.length ? table(['Cliente', 'Honorarios', 'Horas', 'RD$ por hora', 'Margen', 'Servicios'],
        d.by_client.map((c) => [c.client, money(c.fees), String(c.hours), c.fee_per_hour == null ? '—' : money(c.fee_per_hour), c.margin == null ? '—' : money(c.margin), String(c.services)]), [1, 2, 3, 4, 5])
        : note('Sin datos por cliente en el mes.'),
      h('p', { class: 'i18-sub' }, `Horas registradas en el mes: ${d.hours_total}. ${Number(d.hour_cost) > 0 ? `Costo por hora: ${money(d.hour_cost)}.` : 'Defina el costo por hora para ver el margen.'}`));
    if (ctx.role === 'super_admin') drawCfg(d);
  }

  function drawCfg(d) {
    const t = h('input', { type: 'number', id: 'di-c-t', min: '0', step: '5000', value: String(d.target_mrr) });
    const mx = h('input', { type: 'number', id: 'di-c-m', min: '0', max: '100', value: String(d.target_mix_pct) });
    const hc = h('input', { type: 'number', id: 'di-c-h', min: '0', step: '50', value: String(d.hour_cost) });
    const s = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Guardar metas');
    const o = h('div', { 'aria-live': 'polite' });
    s.addEventListener('click', async () => { try { await rpc('direction_settings_save', { p_target_mrr: Number(t.value), p_mix_pct: Number(mx.value), p_hour_cost: Number(hc.value) }); await load(); } catch (e) { o.replaceChildren(note(e.message, 'error')); } });
    cfg.replaceChildren(h('details', { class: 'i18-card' }, h('summary', {}, 'Metas del negocio'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'di-c-t' }, 'Meta mensual (RD$)', t), h('label', { for: 'di-c-m' }, 'Facturación médica (%)', mx), h('label', { for: 'di-c-h' }, 'Costo por hora (RD$)', hc), s), o));
  }

  pdf.addEventListener('click', () => {
    if (!last) return;
    const d = last; const w = openPrint();
    if (!fillPrint(w, `Informe de dirección · ${d.month.slice(0, 7)}`, 'Soluciones de Facturación Médica (SOFA)', [
      { big: `MRR: ${money(d.mrr)} (${d.mrr_pct_of_target ?? 0} % de la meta ${money(d.target_mrr)})` },
      { p: `Facturación médica: ${d.billing_mix_pct ?? '—'} % (meta ${d.target_mix_pct} %). Clientes que pagan: ${d.clients_paying}. Ingreso por cliente: ${money(d.arpa)}. Retención a 12 meses: ${d.retention_12m.pct ?? '—'} %. Conversión de diagnósticos: ${d.funnel?.pct ?? '—'} %.` },
      { h: 'Tendencia' }, { table: { head: ['Mes', 'MRR', 'Clientes'], right: [1, 2], rows: d.trend.map((t) => [t.month.slice(0, 7), money(t.mrr), String(t.clients)]) } },
      { h: 'Mezcla por servicio' }, { table: { head: ['Servicio', 'Monto', '%'], right: [1, 2], rows: d.mix.map((x) => [x.service, money(x.amount), `${x.pct ?? 0} %`]) } },
      { h: 'Por cliente' }, { table: { head: ['Cliente', 'Honorarios', 'Horas', 'Margen'], right: [1, 2, 3], rows: d.by_client.map((c) => [c.client, money(c.fees), String(c.hours), c.margin == null ? '—' : money(c.margin)]) } }])) {
      box.prepend(note('El navegador bloqueó la ventana. Permita las ventanas emergentes de SOFA e intente de nuevo.', 'error'));
    }
  });

  const table = (head, rows, right = []) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x, i) => h('th', { class: right.includes(i) ? 'i18-r' : null }, x)))),
    h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x, i) => h('td', { class: right.includes(i) ? 'i18-r' : null }, x)))))));

  m.addEventListener('change', load);
  await load();
}
export default render;
