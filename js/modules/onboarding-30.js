/** SOFA · 4.5 · Iteración 55 · Onboarding del cliente nuevo en 30 días.
 *  Médico: «Mis primeros 30 días con SOFA». Equipo SOFA: tablero de clientes nuevos, plan por cliente y revisión del día 30.
 *  5.33.0 · Flujo por etapas con porcentajes visibles: stepper global, barra general y
 *  tarjetas de etapa con progreso propio, en lugar de un listado plano de hitos. */
import { rpc, h, money, fmtDate, note, guarded } from '../services/iter18.js';

/** Las tres etapas visibles del onboarding, cada una con el rango de días que cubre.
 *  Cualquier hito del plan cae en la etapa que contiene su `day` dentro de [from, to].
 *  Si el RPC agrega días nuevos (p.ej. día 45), la última etapa los absorbe. */
const ETAPAS = [
  { key: 'base',      titulo: 'Base lista',       descr: 'Perfil, médicos y captura funcionando.',       from: 0,  to: 7,   icono: '🏗' },
  { key: 'operacion', titulo: 'Operación en marcha', descr: 'ARS avisadas y secretaria capturando.',      from: 8,  to: 14,  icono: '⚙' },
  { key: 'resultado', titulo: 'Primer resultado', descr: 'Primer lote radicado y revisión de resultados.', from: 15, to: 999, icono: '✅' }
];

/** Agrupa los `milestones` del RPC en sus etapas. Devuelve [{etapa, items[], done, total, pct}]. */
function armarEtapas(milestones = []) {
  const grupos = ETAPAS.map((e) => ({ etapa: e, items: [], done: 0, total: 0 }));
  for (const m of milestones) {
    const g = grupos.find((x) => m.day >= x.etapa.from && m.day <= x.etapa.to) || grupos[grupos.length - 1];
    g.items.push(m);
    g.total++;
    if (m.done) g.done++;
  }
  return grupos.map((g) => ({ ...g, pct: g.total ? Math.round((g.done / g.total) * 100) : 0 }));
}

function etapaActual(grupos, day) {
  // La actual es la primera que no llegó al 100% y cuyo rango inicial ya ocurrió.
  const abierta = grupos.find((g) => g.pct < 100 && day >= g.etapa.from);
  if (abierta) return abierta;
  return grupos[grupos.length - 1];
}

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const client = ctx.role === 'client';
  const board = h('div', { 'aria-live': 'polite' });
  const plan = h('div', { 'aria-live': 'polite', id: 'ob-plan' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, client ? 'Mis primeros 30 días con SOFA' : 'Onboarding de 30 días'),
    h('p', { class: 'i18-sub' }, 'Tres etapas de 7, 14 y 30 días. Cada etapa muestra su porcentaje de avance; el total resume dónde va el cliente hoy.'), board, plan));

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
    const grupos = armarEtapas(p.milestones);
    const totalHechos = grupos.reduce((s, g) => s + g.done, 0);
    const totalTotal  = grupos.reduce((s, g) => s + g.total, 0);
    const pctGlobal   = totalTotal ? Math.round((totalHechos / totalTotal) * 100) : 0;
    const diaMax = 30;
    const diaPct = Math.min(100, Math.round(((p.day || 0) / diaMax) * 100));
    const actual = etapaActual(grupos, p.day || 0);

    const kids = [
      h('h3', {}, `${p.client} · día ${p.day} de ${diaMax} (desde ${fmtDate(p.start)})`),

      // ── Encabezado con progreso global: % de hitos + % de tiempo transcurrido ──
      h('div', { class: 'ob-overview' },
        h('div', { class: 'ob-overview-row' },
          h('div', { class: 'ob-overview-label' }, 'Avance general'),
          h('div', { class: 'ob-overview-val' }, `${totalHechos} de ${totalTotal} hitos · ${pctGlobal} %`)),
        h('div', { class: 'ob-bar ob-bar-lg', role: 'progressbar', 'aria-valuenow': String(pctGlobal), 'aria-valuemin': '0', 'aria-valuemax': '100', 'aria-label': 'Avance general del onboarding' },
          h('div', { class: 'ob-bar-fill', style: `width:${pctGlobal}%` })),
        h('div', { class: 'ob-overview-row' },
          h('div', { class: 'ob-overview-label' }, 'Tiempo transcurrido'),
          h('div', { class: 'ob-overview-val' }, `${diaPct} % del plan de 30 días`)),
        h('div', { class: 'ob-bar ob-bar-sm', role: 'progressbar', 'aria-valuenow': String(diaPct), 'aria-valuemin': '0', 'aria-valuemax': '100', 'aria-label': 'Tiempo transcurrido' },
          h('div', { class: 'ob-bar-fill ob-bar-fill-ghost', style: `width:${diaPct}%` }))),

      // ── Stepper visual de las 3 etapas, con % por etapa y estado ──
      h('div', { class: 'ob-stepper', role: 'list' }, grupos.map((g, i) => {
        const esActual = g.etapa.key === actual.etapa.key;
        const completa = g.pct === 100;
        const estado = completa ? 'completa' : esActual ? 'actual' : g.etapa.from > (p.day || 0) ? 'futura' : 'parcial';
        const nombre = `Etapa ${i + 1} · ${g.etapa.titulo}`;
        return h('div', { class: `ob-step ob-step-${estado}`, role: 'listitem', 'aria-label': `${nombre} · ${g.pct} %` },
          h('div', { class: 'ob-step-badge', 'aria-hidden': 'true' }, completa ? '✓' : g.etapa.icono),
          h('div', { class: 'ob-step-body' },
            h('div', { class: 'ob-step-title' }, nombre),
            h('div', { class: 'ob-step-descr' }, `Días ${g.etapa.from}–${g.etapa.to === 999 ? '30+' : g.etapa.to} · ${g.etapa.descr}`),
            h('div', { class: 'ob-step-meter', role: 'progressbar', 'aria-valuenow': String(g.pct), 'aria-valuemin': '0', 'aria-valuemax': '100', 'aria-label': `${nombre} · ${g.pct} %` },
              h('div', { class: 'ob-step-fill', style: `width:${g.pct}%` })),
            h('div', { class: 'ob-step-foot' }, `${g.done} de ${g.total} hitos · ${g.pct} %`)));
      })),

      // ── Detalle por etapa: cada hito con su estado y faltantes ──
      h('h4', {}, 'Detalle por etapa'),
      ...grupos.map((g, i) => h('details', { class: 'ob-details', open: g.etapa.key === actual.etapa.key },
        h('summary', {},
          h('strong', {}, `Etapa ${i + 1} · ${g.etapa.titulo}`),
          h('span', { class: 'ob-summary-pct' }, ` · ${g.done} de ${g.total} · ${g.pct} %`)),
        g.items.length ? h('ol', { class: 'ob-ms' }, g.items.map((m) => h('li', { class: m.done ? 'ob-done' : m.late ? 'ob-late' : '' },
          h('strong', {}, `Día ${m.day} · ${m.label}`),
          ` · ${m.done ? 'Listo' : m.late ? `Atrasado (vencía ${fmtDate(m.due)})` : `Para el ${fmtDate(m.due)}`}`,
          (m.missing || []).length ? h('div', { class: 'i18-sub' }, 'Falta: ' + m.missing.map(lbl).join(', ')) : null)))
          : h('p', { class: 'i18-sub' }, 'Esta etapa aún no tiene hitos cargados en el plan.'))),

      // ── Comparativa antes/ahora ──
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
    plan.replaceChildren(h('div', { class: 'i18-card' }, ...kids.filter(Boolean)));
    plan.scrollIntoView({ behavior: 'smooth' });
  }
}
export default render;
