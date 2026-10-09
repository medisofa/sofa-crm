/** SOFA · 4.0 · Iteración 50 · Seguridad y salud del sistema (Super Admin).
 *  Tablas grandes, tareas programadas que fallaron, revisión trimestral de accesos, simulacros de respaldo y exportaciones. */
import { rpc, h, fmtDate, note, guarded } from '../services/iter18.js';

const KIND = { respaldo_descargado: 'Respaldo descargado', restauracion_prueba: 'Restauración de prueba', pitr_verificado: 'Recuperación a un punto en el tiempo verificada' };

export async function render(root) {
  root.replaceChildren();
  const health = h('div', { 'aria-live': 'polite' });
  const review = h('div', { 'aria-live': 'polite' });
  const drill = h('div');
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Seguridad y salud del sistema'),
    h('p', { class: 'i18-sub' }, 'Lo que hay que revisar para crecer sin sustos: tareas que fallan, quién tiene acceso, respaldos probados y quién descarga datos.'), health, drill, review));

  async function loadHealth() {
    const d = await guarded(health, () => rpc('system_health'));
    if (!d) return;
    health.replaceChildren(
      d.drill_due ? note('Pasaron más de 90 días sin un simulacro de respaldo exitoso: hágalo con la guía de operación y regístrelo abajo.', 'warn') : null,
      d.access_review_due ? note('La revisión de accesos de este trimestre no está cerrada.', 'warn') : null,
      h('p', {}, `Base de datos: ${d.db_size} · última migración ${d.last_migration} · personal sin entrar en 90 días: ${d.staff_inactive_90d}.`),
      h('h3', {}, 'Tareas programadas con error (7 días)'),
      d.cron_failures.length ? h('ul', {}, d.cron_failures.map((f) => h('li', {}, `${f.job} · ${fmtDate(f.at)} · ${f.message || ''}`))) : note('Ninguna falló.'),
      h('details', {}, h('summary', {}, 'Tablas más grandes'), table(['Tabla', 'Filas aprox.', 'Tamaño'], d.tables.map((t) => [t.table, String(t.rows), t.size]))),
      h('details', {}, h('summary', {}, `Exportaciones de los últimos 30 días (${d.exports_30d.length})`),
        d.exports_30d.length ? table(['Fecha', 'Usuario', 'Módulo', 'Archivo', 'Filas'], d.exports_30d.map((e) => [fmtDate(e.at), e.user || '—', e.module, e.file || '—', e.rows == null ? '—' : String(e.rows)])) : note('Sin exportaciones.')));
    drawDrill(d);
  }

  function drawDrill(d) {
    const k = h('select', { id: 'ss-d-kind' }, Object.entries(KIND).map(([v, t]) => h('option', { value: v }, t)));
    const r = h('select', { id: 'ss-d-res' }, h('option', { value: 'ok' }, 'Salió bien'), h('option', { value: 'con_problemas' }, 'Con problemas'));
    const n = h('input', { type: 'text', id: 'ss-d-note', maxlength: '300' });
    const s = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Registrar simulacro');
    const o = h('div', { 'aria-live': 'polite' });
    s.addEventListener('click', async () => { try { await rpc('backup_drill_add', { p_kind: k.value, p_result: r.value, p_note: n.value || null, p_done_on: null }); await loadHealth(); } catch (e) { o.replaceChildren(note(e.message, 'error')); } });
    drill.replaceChildren(h('fieldset', { class: 'i18-fs' }, h('legend', {}, 'Simulacro de respaldo y restauración'),
      h('p', { class: 'i18-sub' }, d.last_drill ? `Último: ${KIND[d.last_drill.kind]} el ${fmtDate(d.last_drill.done_on)} (${d.last_drill.result === 'ok' ? 'bien' : 'con problemas'}).` : 'Todavía no hay simulacros registrados.'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'ss-d-kind' }, 'Tipo', k), h('label', { for: 'ss-d-res' }, 'Resultado', r), h('label', { for: 'ss-d-note' }, 'Nota', n), s), o));
  }

  async function loadReview() {
    const d = await guarded(review, () => rpc('access_review_get', { p_id: null }));
    if (!d) return;
    const start = h('button', { class: 'i18-btn', type: 'button' }, `Iniciar revisión ${d.quarter}`);
    start.addEventListener('click', async () => { try { await rpc('access_review_start'); loadReview(); loadHealth(); } catch (e) { review.prepend(note(e.message, 'error')); } });
    const rv = d.review;
    if (!rv || (rv.quarter !== d.quarter)) { review.replaceChildren(h('h3', {}, 'Revisión trimestral de accesos'), note('Toma una foto de quién tiene qué rol y le permite mantener o quitar cada acceso.'), start); return; }
    const pending = d.items.filter((i) => !i.decision).length;
    const close = h('button', { class: 'i18-btn', type: 'button', disabled: pending > 0 || !!rv.completed_at }, rv.completed_at ? `Cerrada el ${fmtDate(rv.completed_at)}` : 'Cerrar revisión');
    close.addEventListener('click', async () => { try { await rpc('access_review_complete', { p_id: rv.id }); loadReview(); loadHealth(); } catch (e) { review.prepend(note(e.message, 'error')); } });
    review.replaceChildren(h('h3', {}, `Revisión de accesos ${rv.quarter} · ${pending} por decidir`), h('div', { class: 'i18-bar' }, close),
      table(['Usuario', 'Correo', 'Rol', 'Organización', 'Último ingreso', 'Decisión'], d.items.map((i) => {
        let cell;
        if (i.decision || rv.completed_at) cell = i.decision ? `${i.decision === 'mantener' ? 'Mantener' : 'Quitado'}${i.note ? ` · ${i.note}` : ''}` : '—';
        else {
          const keep = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Mantener');
          const rm = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Quitar');
          const nt = h('input', { type: 'text', maxlength: '200', placeholder: 'Motivo (para quitar)', 'aria-label': 'Motivo' });
          const o = h('div', { 'aria-live': 'polite' });
          const go = (dec) => async () => { try { await rpc('access_review_decide', { p_item: i.id, p_decision: dec, p_note: nt.value || null }); loadReview(); } catch (e) { o.replaceChildren(note(e.message, 'error')); } };
          keep.addEventListener('click', go('mantener')); rm.addEventListener('click', go('quitar'));
          cell = h('div', {}, h('div', { class: 'i18-bar' }, keep, nt, rm), o);
        }
        return [i.user || '—', i.email || '—', i.role, i.organization || '—', h('span', { class: i.stale ? 'cs-over' : '' }, i.last_sign_in ? fmtDate(i.last_sign_in) : 'Nunca'), cell];
      })));
  }

  const table = (head, rows) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x) => h('th', {}, x)))), h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x) => h('td', {}, x)))))));

  await loadHealth(); await loadReview();
}
export default render;
