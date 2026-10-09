/** SOFA · 28 · Salud de los clientes (solo personal de SOFA). Semáforo por cliente con sus motivos. */
import { rpc, h, money, num, fmtDate, note, guarded, kpi, table } from '../services/iter18.js';

const COLOR = { verde: '#1a7f37', amarillo: '#9a6700', rojo: '#cf222e' };

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Salud de los clientes'),
    h('p', {}, 'Del más débil al más sano. Revise primero los rojos: son los clientes con más riesgo de dejar el servicio.'), out);
  const rows = await guarded(out, () => rpc('client_health', {}));
  if (!rows) return;
  if (!rows.length) { out.replaceChildren(note('No hay clientes activos ni en incorporación.')); return; }
  const count = (l) => rows.filter((r) => r.level === l).length;
  out.replaceChildren(
    h('div', { class: 'i18-kpis' }, kpi('Rojos', num(count('rojo'))), kpi('Amarillos', num(count('amarillo'))), kpi('Verdes', num(count('verde')))),
    table([
      { label: 'Cliente', get: (r) => h('span', {}, h('span', { 'aria-hidden': 'true', style: `display:inline-block;width:.8em;height:.8em;border-radius:50%;margin-right:.4em;background:${COLOR[r.level]}` }), r.name) },
      { label: 'Puntos', right: true, get: (r) => `${r.score} (${r.level})` },
      { label: 'Reclamaciones 30 días', right: true, get: (r) => `${num(r.claims_30)}${r.trend_pct == null ? '' : ` (${r.trend_pct > 0 ? '+' : ''}${r.trend_pct} %)`}` },
      { label: 'Monto 30 días', right: true, get: (r) => money(r.amount_30) },
      { label: 'Deuda vencida', right: true, get: (r) => (r.overdue_debt > 0 ? `${money(r.overdue_debt)} · ${num(r.overdue_days)} d` : '—') },
      { label: 'Último acceso', get: (r) => (r.last_login ? fmtDate(r.last_login) : 'Nunca') },
      { label: 'Motivos', get: (r) => (r.reasons && r.reasons.length ? h('ul', { class: 'i18-list' }, r.reasons.map((m) => h('li', {}, m))) : 'Sin alertas') }], rows));
}
