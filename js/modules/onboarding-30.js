/** SOFA · 4.5 · Iteración 55 · Onboarding del cliente nuevo en 30 días.
 *  Médico: «Mis primeros 30 días con SOFA». Equipo SOFA: tablero de clientes nuevos, plan por cliente y revisión del día 30. */
import { rpc, h, money, fmtDate, note, guarded } from '../services/iter18.js';

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const client = ctx.role === 'client';
  const board = h('div', { 'aria-live': 'polite' });
  const plan = h('div', { 'aria-live': 'polite', id: 'ob-plan' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, client ? 'Mis primeros 30 días con SOFA' : 'Onboarding de 30 días'),
    h('p', { class: 'i18-sub' }, 'Día 7: base lista y primera reclamación. Día 14: ARS avisadas y secretaria trabajando. Día 30: primer lote radicado y revisión de resultados.'), board, plan));

  if (client) { await drawPlan(ctx.membership?.organization_id, false); return; }
  const d = await guarded(board, () => rpc('onboarding_board'));
  if (!d) return;
  board.replaceChildren(d.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, ['Cliente', 'Día', 'Siguiente hito', 'Vence', 'Estado', ''].map((x) => h('th', {}, x)))),
    h('tbody', {}, d.map((c) => {
      const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Ver plan');
      b.addEventListener('click', () => drawPlan(c.organization_id, true));
      return h('tr', {}, h('td', {}, c.client), h('td', {}, String(c.day)), h('td', {}, c.next ? `Día ${c.next.day}: ${c.next.label}` : 'Completo'),
        h('td', {}, c.next ? fmtDate(c.next.due) : '—'), h('td', { class: c.late ? 'cs-over' : '' }, c.late ? 'Atrasado' : 'A tiempo'), h('td', {}, b));
    })))) : note('No hay clientes en sus primeros 45 días.'));

  async function drawPlan(org, staff) {
    if (!org) { plan.replaceChildren(note('No se encontró su consultorio.', 'error')); return; }
    const p = await guarded(plan, () => rpc('onboarding_plan', { p_org: org }));
    if (!p) return;
    const lbl = (code) => p.labels[code] || (p.steps.find((s) => s.code === code) || {}).label || code;
    const b = p.baseline; const a = p.actual;
    const kids = [h('h3', {}, `${p.client} · día ${p.day} (desde ${fmtDate(p.start)})`),
      h('ol', { class: 'ob-ms' }, p.milestones.map((m) => h('li', { class: m.done ? 'ob-done' : m.late ? 'ob-late' : '' },
        h('strong', {}, `Día ${m.day} · ${m.label}`), ` · ${m.done ? 'Listo' : m.late ? `Atrasado (vencía ${fmtDate(m.due)})` : `Para el ${fmtDate(m.due)}`}`,
        m.missing.length ? h('div', { class: 'i18-sub' }, 'Falta: ' + m.missing.map(lbl).join(', ')) : null))),
      h('h4', {}, 'Antes y ahora'),
      h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['', 'Diagnóstico inicial', 'Con SOFA'].map((x) => h('th', {}, x)))),
        h('tbody', {}, [['Glosa', b ? `${b.glosa_pct} %` : '—', a.glosa_pct == null ? '—' : `${a.glosa_pct} %`], ['Días para cobrar', b ? String(b.dso_days) : '—', '(se mide al cobrar los primeros lotes)'],
          ['Reclamaciones capturadas', '—', String(a.claims)], ['Lotes radicados', '—', `${a.lots_submitted}${a.first_lot_on ? ` (primero el ${fmtDate(a.first_lot_on)})` : ''}`],
          ['Radicado', b ? `${money(b.monthly_billing)} al mes (estimado)` : '—', money(a.claimed)]].map((r) => h('tr', {}, r.map((x) => h('td', {}, x))))))),
      p.reviews.length ? [h('h4', {}, 'Revisiones de resultados'), h('ul', {}, p.reviews.map((r) => h('li', {}, `${fmtDate(r.held_on)} · satisfacción ${r.satisfaction}/5 · metas: ${r.next_goals}${r.pending ? ` · pendiente: ${r.pending}` : ''}`)))] : null];
    if (staff) {
      const sat = h('select', { id: 'ob-r-sat' }, [5, 4, 3, 2, 1].map((n) => h('option', { value: String(n) }, `${n}`)));
      const well = h('input', { type: 'text', id: 'ob-r-well', maxlength: '300' });
      const pend = h('input', { type: 'text', id: 'ob-r-pend', maxlength: '300' });
      const goals = h('textarea', { id: 'ob-r-goals', rows: '2', style: 'width:100%' });
      const sv = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar revisión');
      const o = h('div', { 'aria-live': 'polite' });
      sv.addEventListener('click', async () => { try { await rpc('onboarding_review_add', { p_org: org, p_satisfaction: Number(sat.value), p_went_well: well.value || null, p_pending: pend.value || null, p_next_goals: goals.value, p_held_on: null }); drawPlan(org, true); } catch (e) { o.replaceChildren(note(e.message, 'error')); } });
      kids.push(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Revisión de resultados (día 30)'), h('label', { for: 'ob-r-sat' }, 'Satisfacción del cliente (1 a 5)'), sat,
        h('label', { for: 'ob-r-well' }, 'Qué funcionó'), well, h('label', { for: 'ob-r-pend' }, 'Qué falta'), pend, h('label', { for: 'ob-r-goals' }, 'Metas del siguiente trimestre'), goals, h('div', {}, sv), o));
    }
    plan.replaceChildren(h('div', { class: 'i18-card' }, ...kids));
    plan.scrollIntoView({ behavior: 'smooth' });
  }
}
export default render;
