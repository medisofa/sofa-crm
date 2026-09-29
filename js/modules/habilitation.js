/** SOFA · Habilitación Express ante MISPAS: casos y checklist maestro */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, errorView } from '../utils/ui.js';
import { listCases, caseSummary, requirementsCatalog, saveRequirement, STAGE_LABEL, CASE_KIND } from '../services/habilitation.js';
import { money, num, date } from '../utils/formatters.js';
import { can, isStaff } from '../utils/permissions.js';
import { CONFIG } from '../config.js';
import { pager } from './clients.js';

export async function render(main, ctx) {
  if (ctx.arg) { const m = await import('./habilitation-case.js'); return m.render(main, ctx); }
  const edit = can('hab.edit', ctx.role); const staff = isStaff(ctx.role);
  const st = { group: 'activos', q: '', page: 0 };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Habilitación MISPAS</h2><p>Diagnóstico de brechas con semáforo, expediente completo antes del depósito, inspección y licencia con alerta de renovación.</p></div>
      ${edit ? html`<button class="btn primary" id="new">+ Nuevo caso</button>` : ''}</div>
    <div class="grid kpis" id="k"></div>
    <div class="tabs" id="tabs" role="group" aria-label="Vista" style="margin-top:14px"></div>
    <div class="toolbar" id="tb"><label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Establecimiento, folio o cliente"></div>
    <div id="l"></div>`);
  const tabs = [['activos', 'En proceso'], ['habilitados', 'Habilitados'], ['cancelados', 'Cancelados'], ['todos', 'Todos'], ...(staff ? [['catalogo', 'Checklist maestro']] : [])];
  const drawTabs = () => paint($('#tabs', main), html`${tabs.map(([k, l]) => html`<button data-g="${k}" aria-pressed="${st.group === k}">${l}</button>`)}`);
  drawTabs();
  caseSummary().then((rows) => {
    const act = rows.filter((r) => !['habilitado', 'cancelado'].includes(r.stage));
    const renew = rows.filter((r) => r.stage === 'habilitado' && r.license_days_left != null && r.license_days_left <= 60);
    paint($('#k', main), html`
      <div class="kpi"><div class="l">En proceso</div><div class="v">${num(act.length)}</div><div class="h">${num(act.filter((r) => r.critical_open > 0).length)} con requisitos críticos abiertos</div></div>
      <div class="kpi"><div class="l">Depositados o en inspección</div><div class="v">${num(rows.filter((r) => ['depositado', 'inspeccion'].includes(r.stage)).length)}</div></div>
      <div class="kpi"><div class="l">Habilitados</div><div class="v" style="color:var(--ok)">${num(rows.filter((r) => r.stage === 'habilitado').length)}</div></div>
      <div class="kpi"><div class="l">Licencias por renovar (60 días)</div><div class="v" style="${renew.length ? 'color:var(--warn)' : ''}">${num(renew.length)}</div></div>`);
  }).catch((e) => paint($('#k', main), errorView(e)));

  const list = $('#l', main);
  const load = () => {
    $('#tb', main).style.display = st.group === 'catalogo' ? 'none' : '';
    if (st.group === 'catalogo') return loadCatalog();
    return loadInto(list, () => listCases({ ...st, size: CONFIG.PAGE_SIZE }), ({ data, count }) => html`
      <div class="table-wrap"><table class="t cards"><thead><tr><th>Establecimiento</th><th>Etapa</th><th>Semáforo</th><th class="n">Listo</th><th>Fecha objetivo</th><th>Licencia</th></tr></thead>
      <tbody>${data.map((c) => html`<tr data-id="${c.id}" style="cursor:pointer">
        <td data-l="Establecimiento"><a href="#/habilitacion/${c.id}"><b>${c.establishment_name}</b></a><div class="small muted">${c.folio} · ${c.establishment_type} · ${CASE_KIND[c.case_kind]}${staff && (c.client_name || c.lead_company) ? ` · ${c.client_name || c.lead_company}` : ''}</div></td>
        <td data-l="Etapa"><span class="pill ${c.stage === 'habilitado' ? 'ok' : c.stage === 'cancelado' ? '' : 'info'}">${STAGE_LABEL[c.stage]}</span></td>
        <td data-l="Semáforo" class="small"><span class="pill ok">${c.verde}</span> <span class="pill warn">${c.amarillo}</span> <span class="pill bad">${c.rojo}</span>${c.pendiente ? html` <span class="pill">${c.pendiente} sin evaluar</span>` : ''}</td>
        <td data-l="Listo" class="n"><b>${c.ready_pct}%</b>${c.critical_open ? html`<div class="small" style="color:var(--bad)">${c.critical_open} críticos</div>` : ''}</td>
        <td data-l="Objetivo">${c.target_date ? html`${date(c.target_date)}<div class="small" style="${c.days_to_target < 0 && c.stage !== 'habilitado' ? 'color:var(--bad);font-weight:600' : ''}">${c.stage === 'habilitado' ? '' : c.days_to_target < 0 ? `vencida hace ${-c.days_to_target} días` : `faltan ${c.days_to_target} días`}</div>` : '—'}</td>
        <td data-l="Licencia">${c.license_valid_until ? html`${date(c.license_valid_until)}<div class="small" style="${c.license_days_left <= 60 ? 'color:var(--warn);font-weight:600' : ''}">${c.license_days_left < 0 ? 'vencida' : `${c.license_days_left} días`}</div>` : '—'}</td></tr>`)}</tbody></table></div>${pager(count, st.page)}`,
    { isEmpty: (r) => !r.data.length, empty: () => emptyView('Sin casos', edit ? 'Abre el primero con "+ Nuevo caso": el checklist se genera según el tipo de establecimiento.' : 'No hay casos de habilitación.') });
  };
  const loadCatalog = () => loadInto(list, requirementsCatalog, (rows) => {
    const areas = [...new Set(rows.map((r) => r.area))];
    return html`<div class="note">Checklist base de SOFA. <b>Verifícalo siempre contra la normativa vigente de la Dirección de Habilitación y Acreditación (DGHA)</b> y ajústalo cuando cambie. Los cambios aplican a los casos nuevos.</div>
      ${can('hab.catalog', ctx.role) ? html`<div class="toolbar"><button class="btn" id="addReq">+ Requisito</button></div>` : ''}
      ${areas.map((a) => html`<div class="card" style="margin-bottom:12px"><h2>${a}</h2><div class="table-wrap"><table class="t cards"><thead><tr><th>Código</th><th>Requisito</th><th>Aplica a</th><th>Crítico</th><th>Activo</th></tr></thead><tbody>
        ${rows.filter((r) => r.area === a).map((r) => html`<tr><td data-l="Código" class="mono small">${r.code}</td><td data-l="Requisito">${r.requirement}${r.evidence_hint ? html`<div class="small muted">Evidencia: ${r.evidence_hint}</div>` : ''}</td>
          <td data-l="Aplica a" class="small">${r.applies_to.length === 6 ? 'Todos' : r.applies_to.join(', ')}</td>
          <td data-l="Crítico">${can('hab.catalog', ctx.role) ? html`<input type="checkbox" data-crit="${r.id}" ${r.is_critical ? 'checked' : ''} aria-label="Crítico">` : r.is_critical ? 'Sí' : 'No'}</td>
          <td data-l="Activo">${can('hab.catalog', ctx.role) ? html`<input type="checkbox" data-act="${r.id}" ${r.is_active ? 'checked' : ''} aria-label="Activo">` : r.is_active ? 'Sí' : 'No'}</td></tr>`)}</tbody></table></div></div>`)}`;
  }).then((rows) => {
    $('#addReq', main)?.addEventListener('click', async () => {
      const { requirementDialog } = await import('./habilitation-dialogs.js');
      try { if (await requirementDialog([...new Set((rows || []).map((r) => r.area))])) { toast('Requisito agregado', 'ok'); loadCatalog(); } } catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });

  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-g]'); if (b) { st.group = b.dataset.g; st.page = 0; drawTabs(); load(); } });
  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; st.page = 0; load(); }, 350); });
  list.addEventListener('click', (e) => {
    const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); load(); return; }
    const row = e.target.closest('tr[data-id]'); if (row && !e.target.closest('a')) location.hash = `#/habilitacion/${row.dataset.id}`;
  });
  list.addEventListener('change', async (e) => {
    const c = e.target.closest('[data-crit],[data-act]'); if (!c) return;
    try { await saveRequirement(c.dataset.crit ? { is_critical: c.checked } : { is_active: c.checked }, c.dataset.crit || c.dataset.act); toast('Checklist maestro actualizado', 'ok'); }
    catch (err) { c.checked = !c.checked; toast(friendlyError(err), 'bad'); }
  });
  $('#new', main)?.addEventListener('click', async () => {
    const { caseDialog } = await import('./habilitation-dialogs.js');
    try { const id = await caseDialog(); if (id) { toast('Caso abierto con su checklist', 'ok'); location.hash = `#/habilitacion/${id}`; } } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
}
