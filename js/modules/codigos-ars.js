/** SOFA · 2.3 · Iteración 33 · Tablero de códigos ARS de todos los clientes (equipo SOFA).
 *  Por ARS: cuántos códigos hay en cada estado y cuántos días tarda en dar el código; lista de solicitudes atrasadas y rechazadas. */
import { rpc, h, fmtDate, note, guarded } from '../services/iter18.js';
import { can } from '../utils/permissions.js';

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const days = h('select', { id: 'ca-days' }, [15, 30, 45, 60].map((d) => h('option', { value: String(d), selected: d === 30 }, `${d} días`)));
  const run = can('arscodes.followup', ctx.role) ? h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Crear tareas de seguimiento ahora') : '';
  const msg = h('div', { 'aria-live': 'polite' }); const box = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Códigos ARS de todos los clientes'),
    h('p', { class: 'i18-sub' }, 'Sin código, la ARS no paga. Cada mañana SOFA crea una tarea por cada solicitud que pasa del plazo sin respuesta (una cada 7 días por código).'),
    h('div', { class: 'i18-bar' }, h('label', { for: 'ca-days' }, 'Atrasado después de', days), run), msg, box);
  if (run) run.addEventListener('click', async () => {
    run.disabled = true;
    try { const r = await rpc('ars_codes_followup', { p_days: Number(days.value), p_every: 7 }); msg.replaceChildren(note(`${r.tasks_created} tarea(s) nueva(s) en «Trabajo de hoy».`, 'ok')); }
    catch (e) { msg.replaceChildren(note(e.message, 'error')); } finally { run.disabled = false; }
  });
  const draw = async () => {
    const d = await guarded(box, () => rpc('ars_codes_board', { p_alert_days: Number(days.value) }));
    if (!d) return;
    const tot = (k) => d.by_ars.reduce((a, x) => a + Number(x[k] || 0), 0);
    box.replaceChildren(
      h('div', { class: 'i18-kpis' }, [['Codificados', 'codificado'], ['En trámite', 'en_tramite'], ['Atrasados', 'atrasados'], ['Rechazados', 'rechazado']].map(([l, k]) =>
        h('div', { class: `i18-kpi ${k === 'atrasados' && tot(k) ? 'i18-lvl-critico' : ''}` }, h('div', { class: 'i18-kpi-v' }, String(tot(k))), h('div', { class: 'i18-kpi-l' }, l)))),
      h('h3', {}, 'Por ARS'),
      h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['ARS', 'Codificados', 'En trámite', 'Atrasados', 'Rechazados', 'Prestadores sin iniciar', 'Días promedio hasta el código'].map((x) => h('th', {}, x)))),
        h('tbody', {}, d.by_ars.map((a) => h('tr', {}, h('td', {}, h('strong', {}, a.ars)), h('td', { class: 'i18-r' }, a.codificado), h('td', { class: 'i18-r' }, a.en_tramite),
          h('td', { class: 'i18-r' }, a.atrasados ? h('span', { class: 'ac-pill st-bad' }, String(a.atrasados)) : '0'), h('td', { class: 'i18-r' }, a.rechazado),
          h('td', { class: 'i18-r' }, a.sin_codigo), h('td', { class: 'i18-r' }, a.dias_promedio ?? '—')))))),
      h('h3', {}, `Solicitudes atrasadas (${d.overdue.length})`),
      d.overdue.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Cliente', 'Prestador', 'ARS', 'N.º solicitud', 'Solicitado', 'Días', 'Último recordatorio'].map((x) => h('th', {}, x)))),
        h('tbody', {}, d.overdue.map((o) => h('tr', { class: 'ac-alert' }, h('td', {}, h('a', { href: `#/clientes/${o.organization_id}` }, o.client)), h('td', {}, o.provider), h('td', {}, o.ars),
          h('td', {}, o.request_number || '—'), h('td', {}, fmtDate(o.requested_on)), h('td', { class: 'i18-r' }, o.days), h('td', {}, o.last_reminder_at ? fmtDate(o.last_reminder_at) : '—')))))) : note('No hay solicitudes atrasadas.'),
      d.rejected.length ? [h('h3', {}, `Rechazados (${d.rejected.length})`), h('ul', {}, d.rejected.map((x) => h('li', {}, h('a', { href: `#/clientes/${x.organization_id}` }, x.client), ` · ${x.provider} · ${x.ars}: ${x.reason || 'sin motivo'}`)))] : '');
  };
  days.addEventListener('change', draw);
  await draw();
}
