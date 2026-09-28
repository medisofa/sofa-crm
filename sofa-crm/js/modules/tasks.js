/** SOFA · Tareas: hoy, vencidas, próximas y completadas */
import { html, render as paint, raw, $ } from '../utils/dom.js';
import { loadInto, emptyView } from '../utils/ui.js';
import { listTasks, taskCounts } from '../services/tasks.js';
import { PRIORITIES } from '../utils/constants.js';
import { date } from '../utils/formatters.js';
import { can } from '../utils/permissions.js';
import { taskDialog } from './crm-dialogs.js';
import { taskAction } from './opportunity.js';

const TABS = [['hoy', 'Hoy'], ['vencidas', 'Vencidas'], ['proximas', 'Próximas'], ['completadas', 'Completadas']];
const link = (t) => (t.entity_type === 'opportunity' ? `#/oportunidades/${t.entity_id}` : t.entity_type === 'organization' ? `#/clientes/${t.entity_id}` : null);

export async function render(main, ctx) {
  const edit = can('tasks.edit', ctx.role);
  const st = { bucket: 'hoy', mine: true };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Tareas</h2><p>Lo que hay que hacer, ligado a oportunidades, clientes y más adelante a radicaciones y glosas.</p></div>
      ${edit ? html`<button class="btn primary" id="new">+ Nueva tarea</button>` : ''}</div>
    <div class="toolbar"><div class="tabs" role="group" aria-label="Filtrar tareas" id="tabs" style="margin:0"></div><span style="flex:1"></span>
      <label class="check small"><input type="checkbox" id="mine" checked> Solo mis tareas</label></div>
    <div id="l"></div>`);
  const box = $('#l', main);
  const drawTabs = async () => {
    let c = { hoy: 0, vencidas: 0, proximas: 0, completadas: 0 };
    try { c = await taskCounts(st.mine ? ctx.session.user.id : ''); } catch { /* sin conteo */ }
    paint($('#tabs', main), html`${TABS.map(([k, l]) => html`<button data-b="${k}" aria-pressed="${st.bucket === k}">${l}<span class="c" style="${k === 'vencidas' && c[k] ? 'color:var(--bad)' : ''}">${c[k]}</span></button>`)}`);
  };
  const load = () => { drawTabs(); return loadInto(box, () => listTasks({ bucket: st.bucket, assignee: st.mine ? ctx.session.user.id : '' }), (list) => html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Tarea</th><th>Sobre</th><th>Vence</th><th>Responsable</th><th></th></tr></thead>
    <tbody>${list.map((t) => html`<tr>
      <td data-l="Tarea"><b>${t.title}</b> <span class="pill ${(PRIORITIES[t.priority] || ['', ''])[1]}">${(PRIORITIES[t.priority] || [t.priority])[0]}</span>${t.notes ? html`<div class="small muted">${t.notes}</div>` : ''}</td>
      <td data-l="Sobre">${link(t) ? html`<a href="${link(t)}">${t.entity_label || 'Ver'}</a>` : (t.entity_label || '—')}</td>
      <td data-l="Vence" style="${t.bucket === 'vencidas' ? 'color:var(--bad);font-weight:600' : ''}">${date(t.due_date)}</td>
      <td data-l="Responsable">${t.assignee_name || '—'}</td>
      <td data-l="">${edit ? (t.status === 'abierta'
        ? html`<button class="btn sm primary" data-task="done" data-id="${t.id}">Completar</button> <button class="btn sm" data-task="snooze" data-id="${t.id}" data-due="${t.due_date}">+3 días</button>`
        : html`<button class="btn sm" data-task="reopen" data-id="${t.id}">Reabrir</button>`) : ''}</td></tr>`)}</tbody></table></div>`,
  { empty: () => emptyView(st.bucket === 'vencidas' ? 'Nada vencido' : st.bucket === 'hoy' ? 'Nada para hoy' : 'Sin tareas', st.mine ? 'Desmarca "Solo mis tareas" para ver las del equipo.' : '') }); };
  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-b]'); if (b) { st.bucket = b.dataset.b; load(); } });
  $('#mine', main).addEventListener('change', (e) => { st.mine = e.target.checked; load(); });
  box.addEventListener('click', (e) => taskAction(e, load));
  $('#new', main)?.addEventListener('click', async () => { if (await taskDialog(ctx)) load(); });
  load();
}
