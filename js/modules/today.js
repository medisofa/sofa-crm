/** SOFA · Trabajo de hoy: lo que requiere acción, ordenado por urgencia y filtrado por rol */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, errorView, emptyView, toast, friendlyError } from '../utils/ui.js';
import { workQueue } from '../services/bi.js';
import { updateTask } from '../services/tasks.js';
import { money, date } from '../utils/formatters.js';
import { isStaff, canOpen } from '../utils/permissions.js';

const GROUPS = {
  configuracion: 'Reclamaciones sin contrato (pendientes de configuración)', inconsistencia: 'Reclamaciones con inconsistencia', diferencia: 'Diferencias tarifarias por autorizar',
  retiro: 'Reclamaciones por retirar', fiscal: 'Radicaciones sin factura fiscal o con diferencia',
  validacion: 'Retiradas sin validar (más días de lo previsto)', enviada: 'Lotes enviados sin acuse de la ARS',
  glosa_normativa: 'Glosas: plazos de la normativa (respuesta de la ARS, conciliación y arbitraje)',
  consultorio: 'Pacientes atendidos sin registrar', cuadre: 'Días sin cuadre de caja', autorizacion: 'Autorizaciones por vencer (la ARS depura a los 180 días)',
  reenvio: 'Devueltas por la ARS sin reenviar', pago_incompleto: 'Pagos incompletos (aprobado mayor que pagado)', sofa_ncf: 'Facturas SOFA sin NCF',
  ventana: 'Ventana de radicación', cobro: 'Cobros vencidos o por vencer', glosa: 'Glosas por responder', radicar: 'Listas para radicar',
  depurar: 'Radicaciones por depurar', codigo: 'Códigos de prestador pendientes', tarea: 'Tareas', seguimiento: 'Seguimientos comerciales',
  factura_sofa: 'Facturas SOFA vencidas', habilitacion: 'Habilitaciones: fechas e inspecciones', renovacion: 'Licencias por renovar', borrador: 'Borradores'
};
const ORDER = Object.keys(GROUPS);
const FOR_ROLE = {
  billing: ['autorizacion', 'reenvio', 'pago_incompleto', 'validacion', 'configuracion', 'diferencia', 'inconsistencia', 'retiro'],   // solo sus módulos (decisión 01/10/2026)
  glosas: ['glosa_normativa', 'pago_incompleto', 'glosa', 'cobro', 'tarea'],
  assistant: ['retiro', 'depurar', 'borrador', 'seguimiento', 'tarea', 'ventana', 'habilitacion', 'renovacion'], client: ['consultorio', 'cuadre', 'autorizacion', 'configuracion', 'inconsistencia', 'borrador', 'depurar', 'glosa', 'cobro', 'ventana', 'habilitacion', 'renovacion'],
  operations: ['autorizacion', 'enviada', 'validacion', 'retiro', 'inconsistencia', 'configuracion', 'radicar', 'fiscal', 'tarea'], auditor: ['validacion', 'inconsistencia', 'retiro', 'diferencia'], capturer: ['consultorio', 'cuadre', 'autorizacion', 'configuracion', 'inconsistencia']
};
const SEV = { critica: ['Urgente', 'bad'], alta: ['Alta', 'warn'], media: ['Media', 'info'], info: ['Info', ''] };
const link = (i) => (i.kind === 'cuadre' || i.entity_type === 'appointment' ? '#/agenda' : { submission: `#/radicaciones/${i.entity_id}`, glosa: `#/glosas/${i.entity_id}`, task: '#/tareas', opportunity: `#/oportunidades/${i.entity_id}`, organization: `#/clientes/${i.entity_id}`, sofa_invoice: '#/honorarios', habilitation: `#/habilitacion/${i.entity_id}`, claim: `#/reclamaciones/${i.entity_id}`, provider: '#/retiros', reception: `#/retiros/${i.entity_id}` }[i.entity_type] || '#/inicio');

export async function render(main, ctx) {
  const roleKinds = FOR_ROLE[ctx.role];
  let mode = roleKinds ? 'rol' : 'todo'; let items = [];
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Trabajo de hoy</h2><p>Lo que requiere acción hoy, calculado al momento desde los datos. ${new Date().toLocaleDateString('es-DO', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Santo_Domingo' })}.</p></div>
      <button class="btn" id="reload">Actualizar</button></div>
    <div class="tabs" id="tabs" role="group" aria-label="Filtro"></div>
    ${['client', 'capturer'].includes(ctx.role) ? html`<div class="card" style="margin-bottom:14px"><h2>Consultorio de hoy</h2><div id="agz"></div></div>` : ''}
    <div class="grid kpis" id="k"></div><div id="l" style="margin-top:14px"></div>`);
  if ($('#agz', main)) import('./agenda.js').then((m) => m.renderAgenda($('#agz', main), ctx)).catch(() => {});
  const drawTabs = () => paint($('#tabs', main), html`${roleKinds ? html`<button data-m="rol" aria-pressed="${mode === 'rol'}">Para mi rol</button>` : ''}${isStaff(ctx.role) ? html`<button data-m="mio" aria-pressed="${mode === 'mio'}">Asignado a mí</button>` : ''}<button data-m="todo" aria-pressed="${mode === 'todo'}">Todo</button>`);
  const visible = () => items.filter((i) => (mode === 'todo' ? true : mode === 'mio' ? i.mine : roleKinds.includes(i.kind) || i.mine));
  const draw = () => {
    const rows = visible();
    const crit = rows.filter((i) => i.severity === 'critica');
    paint($('#k', main), html`
      <div class="kpi"><div class="l">Urgentes</div><div class="v" style="${crit.length ? 'color:var(--bad)' : ''}">${crit.length}</div></div>
      <div class="kpi"><div class="l">Pendientes</div><div class="v">${rows.length}</div></div>
      <div class="kpi"><div class="l">Monto involucrado en cobros</div><div class="v">${money(rows.filter((i) => i.kind === 'cobro').reduce((t, i) => t + Number(i.amount || 0), 0))}</div></div>`);
    if (!rows.length) { paint($('#l', main), emptyView('Todo al día', mode === 'todo' ? 'No hay pendientes accionables hoy.' : 'Nada pendiente con este filtro. Prueba con "Todo".')); return; }
    const groups = ORDER.map((k) => [k, rows.filter((i) => i.kind === k)]).filter(([, r]) => r.length);
    paint($('#l', main), html`${groups.map(([k, r]) => html`<div class="card" style="margin-bottom:14px"><h2>${GROUPS[k]} · ${r.length}</h2><div class="list">
      ${r.sort((a, b) => ['critica', 'alta', 'media', 'info'].indexOf(a.severity) - ['critica', 'alta', 'media', 'info'].indexOf(b.severity) || String(a.due_on || '9').localeCompare(String(b.due_on || '9'))).map((i) => html`<div class="li">
        <span class="pill ${SEV[i.severity]?.[1] || ''}" style="min-width:64px;justify-content:center">${SEV[i.severity]?.[0] || i.severity}</span>
        <div class="b"><div class="t1">${canOpen(link(i), ctx.role) ? html`<a href="${link(i)}">${i.title}</a>` : html`<b>${i.title}</b>`}${i.mine ? html` <span class="pill info">Mío</span>` : ''}</div>
          <div class="t2">${i.detail || ''}${i.client_name && isStaff(ctx.role) ? ` · ${i.client_name}` : ''}${i.due_on ? ` · ${date(i.due_on)}` : ''}</div></div>
        ${i.amount != null && Number(i.amount) > 0 ? html`<b class="small">${money(i.amount)}</b>` : ''}
        ${i.kind === 'tarea' && isStaff(ctx.role) ? html`<button class="btn sm" data-done="${i.entity_id}">Completar</button>` : ''}</div>`)}</div></div>`)}`);
  };
  const load = async () => {
    paint($('#l', main), loadingView(5));
    try { items = await workQueue(); drawTabs(); draw(); }
    catch (err) { paint($('#l', main), errorView(err)); }
  };
  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-m]'); if (b) { mode = b.dataset.m; drawTabs(); draw(); } });
  $('#reload', main).addEventListener('click', load);
  $('#l', main).addEventListener('click', async (e) => {
    const b = e.target.closest('[data-done]'); if (!b) return;
    b.disabled = true;
    try { await updateTask(b.dataset.done, { status: 'completada', completed_at: new Date().toISOString() }); toast('Tarea completada', 'ok'); items = items.filter((i) => i.entity_id !== b.dataset.done); draw(); }
    catch (err) { b.disabled = false; toast(friendlyError(err), 'bad'); }
  });
  load();
}
