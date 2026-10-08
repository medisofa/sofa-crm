/** SOFA · 25 · Indicadores de la agenda del médico (solo lectura). */
import { rpc, providerOptions, h, num, pct, note, guarded, kpi, table, todayIso } from '../services/iter18.js';

const DOW = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

export async function render(root) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const out = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Indicadores de la agenda'), top, out);
  const provs = await guarded(top, providerOptions);
  if (!provs) return;
  if (!provs.length) { top.replaceChildren(note('No tiene médicos asignados. Pida al Administrador que le asigne su consultorio.')); return; }
  const sel = h('select', { id: 'ia-prov' }, provs.map((p) => h('option', { value: p.id }, p.full_name)));
  const from = h('input', { id: 'ia-from', type: 'date', value: todayIso().slice(0, 8) + '01' });
  const to = h('input', { id: 'ia-to', type: 'date', value: todayIso() });
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Ver');
  top.replaceChildren(h('div', { class: 'i18-form' }, h('label', { for: 'ia-prov' }, 'Médico'), sel,
    h('label', { for: 'ia-from' }, 'Desde'), from, h('label', { for: 'ia-to' }, 'Hasta'), to, go));

  async function load() {
    const d = await guarded(out, () => rpc('agenda_indicators', { p_provider: sel.value, p_from: from.value, p_to: to.value }));
    if (!d) return;
    const t = d.totals, r = d.rates, p = d.patients;
    out.replaceChildren(
      h('div', { class: 'i18-kpis' },
        kpi('Citas', num(t.citas)), kpi('Atendidas', num(t.atendidas)),
        kpi('No asistieron', num(t.no_asistio), r.inasistencia_pct == null ? null : `Inasistencia ${pct(r.inasistencia_pct)}`),
        kpi('Canceladas', num(t.canceladas), r.cancelacion_pct == null ? null : pct(r.cancelacion_pct)),
        kpi('Pacientes nuevos', num(p.nuevos), `${num(p.recurrentes)} recurrentes`),
        kpi('Atendidas por ARS', num(t.ars), r.ars_pct == null ? null : `${pct(r.ars_pct)} del total · ${num(t.privado)} privadas`)),
      t.sin_cerrar > 0 ? note(`Hay ${num(t.sin_cerrar)} cita(s) pasadas sin cerrar (programadas, confirmadas o en espera). Márquelas como atendidas, no asistió o canceladas para que los números sean exactos.`, 'error') : null,
      h('h3', {}, 'Atendidas por día de la semana'),
      table([{ label: 'Día', get: (x) => DOW[x.dow] }, { label: 'Atendidas', right: true, get: (x) => num(x.atendidas) }], d.by_weekday),
      h('h3', {}, 'Citas por hora'),
      table([{ label: 'Hora', get: (x) => `${String(x.hour).padStart(2, '0')}:00` }, { label: 'Citas', right: true, get: (x) => num(x.citas) }], d.by_hour),
      h('h3', {}, 'Motivos más frecuentes'),
      table([{ label: 'Motivo', get: (x) => x.reason }, { label: 'Citas', right: true, get: (x) => num(x.citas) }], d.top_reasons));
  }
  go.addEventListener('click', load);
  sel.addEventListener('change', load);
  await load();
}
