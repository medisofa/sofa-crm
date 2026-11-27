/** SOFA · Horas por usuario: tiempo conectado y activo por semana. Solo Super Admin y Administrador
 *  (la base vuelve a verificar el rol). */
import { h, note, kpi, table, guarded, downloadCsv, fmtDate, num } from '../services/iter18.js';
import { usageHoursReport } from '../services/usage.js';

const hours = (min) => `${Math.floor(min / 60)} h ${String(min % 60).padStart(2, '0')} min`;
const localIso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
/** Desde el lunes de hace (semanas − 1) hasta hoy. */
export function period(weeks, now = new Date()) {
  const from = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  from.setDate(from.getDate() - ((from.getDay() + 6) % 7) - (weeks - 1) * 7);
  return { from: localIso(from), to: localIso(now) };
}

export async function render(root, ctx = {}) {
  root.replaceChildren();
  if (!['super_admin', 'admin'].includes(ctx.role)) {
    root.append(note('Solo la Administración de SOFA puede ver las horas por usuario.', 'warn'));
    return;
  }
  const weeks = h('select', { id: 'hu-weeks' }, [[1, 'Esta semana'], [4, 'Últimas 4 semanas'], [12, 'Últimas 12 semanas']].map(([v, t]) => h('option', { value: v, selected: v === 4 }, t)));
  const who = h('select', { id: 'hu-who' }, [['sofa', 'Equipo SOFA'], ['otros', 'Médicos y consultorios'], ['', 'Todos']].map(([v, t]) => h('option', { value: v }, t)));
  const csv = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: true }, '⬇ CSV');
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Horas por usuario'),
    h('p', { class: 'i18-sub' }, 'Conectado: la app abierta con la sesión iniciada. Activo: además, usándola en los últimos 5 minutos. Semanas de lunes a domingo.'),
    h('div', { class: 'i18-bar' }, h('label', { for: 'hu-weeks' }, 'Período', weeks), h('label', { for: 'hu-who' }, 'Usuarios', who), csv), box));

  let data = null;
  const visible = () => (data?.rows || []).filter((r) => !who.value || (who.value === 'sofa') === r.is_sofa);
  function draw() {
    const rows = visible();
    const sum = (k) => rows.reduce((a, r) => a + Number(r[k] || 0), 0);
    csv.disabled = !rows.length;
    box.replaceChildren(
      note(data.since ? `Se mide desde el ${fmtDate(data.since)}. Antes de esa fecha no hay registro.` : 'Todavía no hay registro: empieza a medirse cuando cada persona abra SOFA con la versión nueva.'),
      h('div', { class: 'i18-kpis' }, kpi('Tiempo activo', hours(sum('active_minutes'))), kpi('Tiempo conectado', hours(sum('connected_minutes'))), kpi('Radicaciones hechas', num(sum('filed')))),
      table([
        { label: 'Semana del', get: (r) => (r.week_start ? fmtDate(r.week_start) : '—') },
        { label: 'Usuario', get: (r) => r.name || 'Sin nombre' },
        { label: 'Rol', get: (r) => r.roles || 'Sin acceso activo' },
        { label: 'Activo', right: true, get: (r) => hours(r.active_minutes) },
        { label: 'Conectado', right: true, get: (r) => hours(r.connected_minutes) },
        { label: 'Días', right: true, get: (r) => num(r.days) },
        { label: 'Radicaciones', right: true, get: (r) => num(r.filed) },
        { label: 'Última conexión', get: (r) => (r.last_at ? new Date(r.last_at).toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) : '—') }
      ], rows));
  }
  async function load() {
    const { from, to } = period(Number(weeks.value));
    csv.disabled = true;
    const d = await guarded(box, () => usageHoursReport(from, to));
    if (!d) return;
    data = d;
    draw();
  }
  weeks.addEventListener('change', load);
  who.addEventListener('change', () => data && draw());
  csv.addEventListener('click', () => downloadCsv('sofa-horas-por-usuario.csv', [
    ['Semana del', 'Usuario', 'Rol', 'Minutos activos', 'Minutos conectados', 'Días', 'Radicaciones'],
    ...visible().map((r) => [r.week_start || '', r.name || '', r.roles || '', r.active_minutes, r.connected_minutes, r.days, r.filed])
  ]));
  await load();
}
