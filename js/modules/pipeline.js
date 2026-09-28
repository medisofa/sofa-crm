/** SOFA · Pipeline comercial (tablero de 8 etapas y lista) */
import { html, render as paint, raw, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, opt } from '../utils/ui.js';
import { listOpportunities, listStaff, updateOpportunity } from '../services/crm.js';
import { STAGES, OPEN_STAGES, SERVICES, serviceName, stageLabel } from '../utils/constants.js';
import { money, num, date } from '../utils/formatters.js';
import { can } from '../utils/permissions.js';
import { newProspectDialog, lostDialog, convertDialog } from './crm-dialogs.js';

let view = 'tablero';
export async function render(main, ctx) {
  if (ctx.arg) { const m = await import('./opportunity.js'); return m.render(main, ctx); }
  const edit = can('crm.edit', ctx.role);
  const st = { q: '', owner: '', service: '', closed: false };
  let staff = [];
  try { staff = await listStaff(); } catch { /* sin lista */ }
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Pipeline comercial</h2><p>Oportunidades por etapa. Mueve cada tarjeta con ◀ ▶ o ábrela para el detalle, el diagnóstico de fugas y el seguimiento.</p></div>
      ${edit ? html`<button class="btn primary" id="new">+ Nuevo prospecto</button>` : ''}</div>
    <div class="grid kpis" id="k"></div>
    <div class="toolbar" style="margin-top:14px">
      <label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Buscar por médico o centro">
      <label class="sr-only" for="own">Responsable</label><select class="input" id="own" style="width:auto"><option value="">Todos los responsables</option>${staff.map((s) => opt(s.id, s.full_name || 'Sin nombre'))}</select>
      <label class="sr-only" for="svc">Servicio</label><select class="input" id="svc" style="width:auto"><option value="">Todos los servicios</option>${SERVICES.map((s) => opt(s.code, s.name))}</select>
      <label class="check small"><input type="checkbox" id="closed"> Incluir ganadas y perdidas</label>
      <div class="seg" role="group" aria-label="Vista"><button data-view="tablero" aria-pressed="${view === 'tablero'}">Tablero</button><button data-view="lista" aria-pressed="${view === 'lista'}">Lista</button></div>
    </div>
    <div id="board"></div>`);

  const board = $('#board', main);
  let rows = [];
  const draw = (data) => {
    rows = data;
    const open = data.filter((o) => OPEN_STAGES.includes(o.stage));
    const month = new Date().toISOString().slice(0, 7);
    const won = data.filter((o) => o.stage === 'cliente' && String(o.closed_on || '').startsWith(month));
    paint($('#k', main), html`
      <div class="kpi"><div class="l">Pipeline abierto (mensual)</div><div class="v">${money(open.reduce((t, o) => t + Number(o.estimated_value), 0))}</div><div class="h">${num(open.length)} oportunidades</div></div>
      <div class="kpi"><div class="l">Ponderado por probabilidad</div><div class="v">${money(open.reduce((t, o) => t + Number(o.weighted_value), 0))}</div></div>
      <div class="kpi"><div class="l">Seguimientos vencidos</div><div class="v" style="${open.some((o) => o.overdue) ? 'color:var(--bad)' : ''}">${num(open.filter((o) => o.overdue).length)}</div></div>
      <div class="kpi"><div class="l">Ganadas este mes</div><div class="v" style="color:var(--ok)">${st.closed ? num(won.length) : '—'}</div><div class="h">${st.closed ? money(won.reduce((t, o) => t + Number(o.estimated_value), 0)) : 'Activa "Incluir ganadas"'}</div></div>`);
    if (view === 'lista') return listView(data, edit);
    const stages = STAGES.filter((s) => st.closed || OPEN_STAGES.includes(s.code));
    return html`<div class="kanban" role="list">${stages.map((s) => {
      const items = data.filter((o) => o.stage === s.code);
      return html`<section class="kcol" role="listitem" aria-label="${s.label}"><h3>${s.label} <span>${num(items.length)} · ${money(items.reduce((t, o) => t + Number(o.estimated_value), 0))}</span></h3>
        ${items.length ? items.map((o) => card(o, edit)) : html`<p class="small muted" style="margin:4px">Sin oportunidades</p>`}</section>`;
    })}</div>`;
  };
  const load = () => loadInto(board, () => listOpportunities({ q: st.q, owner: st.owner, service: st.service, includeClosed: st.closed }), draw,
    { isEmpty: (d) => !d.length, empty: () => emptyView('Sin oportunidades', st.q || st.owner || st.service ? 'Prueba con otros filtros.' : 'Registra tu primer prospecto con el botón "Nuevo prospecto".') });

  $('#new', main)?.addEventListener('click', async () => { const id = await newProspectDialog(); if (id) location.hash = `#/oportunidades/${id}`; });
  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; load(); }, 350); });
  $('#own', main).addEventListener('change', (e) => { st.owner = e.target.value; load(); });
  $('#svc', main).addEventListener('change', (e) => { st.service = e.target.value; load(); });
  $('#closed', main).addEventListener('change', (e) => { st.closed = e.target.checked; load(); });
  main.querySelectorAll('[data-view]').forEach((b) => b.addEventListener('click', () => {
    view = b.dataset.view; main.querySelectorAll('[data-view]').forEach((x) => x.setAttribute('aria-pressed', String(x === b))); load();
  }));
  board.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-move]'); if (!b) return;
    const o = rows.find((x) => x.id === b.dataset.id); if (!o) return;
    const idx = OPEN_STAGES.indexOf(o.stage) + Number(b.dataset.move);
    await moveTo(o, idx >= OPEN_STAGES.length ? 'cliente' : OPEN_STAGES[Math.max(0, idx)], ctx);
    load();
  });
  load();
}

function card(o, edit) {
  const first = o.stage === OPEN_STAGES[0];
  return html`<article class="kcard">
    <a class="t" href="#/oportunidades/${o.id}">${o.company}</a>
    <div class="small muted">${serviceName(o.service_code)} · ${money(o.estimated_value)}/mes · ${o.probability}%</div>
    ${o.next_action ? html`<div class="small" style="margin-top:6px">${o.next_action}${o.next_action_date ? html` · <span class="${o.overdue ? 'pill bad' : 'muted'}">${date(o.next_action_date)}</span>` : ''}</div>` : html`<div class="small" style="margin-top:6px"><span class="pill warn">Sin próxima acción</span></div>`}
    <div class="row">${o.days_in_stage >= 14 && OPEN_STAGES.includes(o.stage) ? html`<span class="pill warn" title="Días en esta etapa">${o.days_in_stage} días aquí</span>` : ''}${o.owner_name ? html`<span class="small muted">${o.owner_name}</span>` : ''}<span class="sp"></span>
      ${edit && OPEN_STAGES.includes(o.stage) ? html`<button class="btn sm" data-move="-1" data-id="${o.id}" ${first ? raw('disabled') : ''} aria-label="Mover a la etapa anterior">◀</button><button class="btn sm" data-move="1" data-id="${o.id}" aria-label="Mover a la etapa siguiente">▶</button>` : ''}</div>
  </article>`;
}

function listView(data, edit) {
  return html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Médico o centro</th><th>Etapa</th><th>Servicio</th><th class="n">Valor/mes</th><th class="n">Prob.</th><th>Próxima acción</th><th>Responsable</th></tr></thead>
    <tbody>${data.map((o) => html`<tr>
      <td data-l="Médico o centro"><a href="#/oportunidades/${o.id}"><b>${o.company}</b></a><div class="small muted">${o.source || 'Cliente actual'}</div></td>
      <td data-l="Etapa"><span class="pill ${o.stage === 'cliente' ? 'ok' : o.stage === 'perdido' ? 'bad' : 'info'}">${stageLabel(o.stage)}</span></td>
      <td data-l="Servicio">${serviceName(o.service_code)}</td>
      <td data-l="Valor/mes" class="n">${money(o.estimated_value)}</td><td data-l="Prob." class="n">${o.probability}%</td>
      <td data-l="Próxima acción">${o.next_action || '—'}${o.next_action_date ? html`<div class="small ${o.overdue ? '' : 'muted'}" style="${o.overdue ? 'color:var(--bad);font-weight:600' : ''}">${date(o.next_action_date)}</div>` : ''}</td>
      <td data-l="Responsable">${o.owner_name || '—'}</td></tr>`)}</tbody></table></div>`;
}

/** Cambia la etapa pidiendo lo necesario (motivo de pérdida o conversión en cliente) */
export async function moveTo(o, stage, ctx) {
  try {
    if (stage === o.stage) return false;
    if (stage === 'perdido') { const reason = await lostDialog(); if (!reason) return false; await updateOpportunity(o.id, { stage, lost_reason: reason }); toast('Oportunidad marcada como perdida'); return true; }
    if (stage === 'cliente' && o.lead_id && !o.converted_org_id) {
      if (!can('crm.convert', ctx.role)) { toast('Solo un administrador convierte oportunidades en clientes. Deja la oportunidad en Negociación y avísale.', 'bad'); return false; }
      const orgId = await convertDialog(o); if (orgId) location.hash = `#/clientes/${orgId}`; return !!orgId;
    }
    await updateOpportunity(o.id, { stage });
    toast(`Movida a ${stageLabel(stage)}`, 'ok');
    return true;
  } catch (err) { toast(friendlyError(err), 'bad'); return false; }
}
