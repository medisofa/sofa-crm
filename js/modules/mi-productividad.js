/** SOFA · 5.9.0 · Médico · «Mi productividad»: cuánto produzco, mi ticket promedio y mi tasa de glosa,
 *  por ARS o por procedimiento, en el período que elija. Síntesis sobre public.profitability (ya probada). */
import { rpc, h, money, pct, num, kpi, table, note, guarded, clientOptions, clientName, monthNow, monthToDate } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const clientSel = h('select', { 'aria-label': 'Cliente' });
  const desde = h('input', { type: 'month', 'aria-label': 'Desde' });
  const hasta = h('input', { type: 'month', value: monthNow(), max: monthNow(), 'aria-label': 'Hasta' });
  const grupo = h('select', { 'aria-label': 'Agrupar por' }, h('option', { value: 'ars' }, 'Por ARS'), h('option', { value: 'procedure' }, 'Por procedimiento'));
  // por defecto, últimos 3 meses
  { const d = new Date(); d.setMonth(d.getMonth() - 2); desde.value = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`; }

  function lastDay(iso) { const [y, m] = iso.split('-').map(Number); return new Date(y, m, 0).toISOString().slice(0, 10); }

  async function load() {
    if (!clientSel.value) { out.replaceChildren(note('No hay clientes disponibles para tu usuario.')); return; }
    const d = await guarded(out, () => rpc('profitability', { p_org: clientSel.value, p_from: monthToDate(desde.value), p_to: lastDay(hasta.value), p_group: grupo.value }));
    if (!d) return;
    out.replaceChildren(view(d));
  }
  [clientSel, desde, hasta, grupo].forEach((el) => el.addEventListener('change', load));

  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Mi productividad'),
    h('p', { class: 'i18-sub' }, 'Cuánto produces, tu ticket promedio y tu tasa de glosa, por ARS o por procedimiento.'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Cliente ', clientSel), h('label', {}, 'Desde ', desde), h('label', {}, 'Hasta ', hasta), h('label', {}, 'Ver ', grupo)),
    out));
  try {
    (await clientOptions()).forEach((c) => clientSel.append(h('option', { value: c.id }, clientName(c))));
    await load();
  } catch (e) { out.replaceChildren(note(e.message, 'error')); }
}

function view(d) {
  const t = d.totals || {}, rows = Array.isArray(d.rows) ? d.rows : [];
  const esArs = d.group === 'ars';
  return h('div', {},
    h('div', { class: 'i18-kpis' },
      kpi('Reclamaciones', num(t.lines), 'en el período'),
      kpi('Reclamado', money(t.claimed), t.collected_pct != null ? `${pct(t.collected_pct)} cobrado` : ''),
      kpi('Ticket promedio', money(rows.length ? promedioTicket(t, rows) : 0), 'por reclamación'),
      kpi('Tasa de glosa', t.glosa_rate_pct != null ? pct(t.glosa_rate_pct) : '—', money(t.glosado) + ' glosado')),
    h('h3', {}, esArs ? 'Por ARS' : 'Por procedimiento'),
    table(
      [{ label: esArs ? 'ARS' : 'Procedimiento', get: (r) => (esArs ? r.ars : r.procedure) || '—' },
       { label: 'Reclam.', right: true, get: (r) => num(r.lines) },
       { label: 'Reclamado', right: true, get: (r) => money(r.claimed) },
       { label: 'Ticket', right: true, get: (r) => money(r.avg_ticket) },
       { label: 'Cobrado', right: true, get: (r) => (r.collected_pct != null ? pct(r.collected_pct) : '—') },
       { label: 'Glosa', right: true, get: (r) => (r.glosa_rate_pct != null ? pct(r.glosa_rate_pct) : '—') },
       { label: 'Días a pago', right: true, get: (r) => (r.avg_days_to_pay != null ? num(r.avg_days_to_pay) : '—') }],
      rows),
    note('«Días a pago» es el promedio de días entre radicar y cobrar. Un ticket que baja o una tasa de glosa que sube te dicen dónde revisar.'));
}
function promedioTicket(t, rows) {
  const lines = Number(t.lines) || 0; return lines > 0 ? (Number(t.claimed) || 0) / lines : 0;
}
