/** SOFA · Radicaciones: listado con filtros y cifras */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, opt } from '../utils/ui.js';
import { listSubmissions, submissionSummary, GROUPS } from '../services/submissions.js';
import { listArs } from '../services/catalog.js';
import { money, num, date, period, todayISO } from '../utils/formatters.js';
import { subStatus } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';
import { CONFIG } from '../config.js';
import { pager } from './clients.js';

const daysTo = (iso) => (iso ? Math.round((new Date(`${iso}T00:00:00`) - new Date(`${todayISO()}T00:00:00`)) / 86400000) : null);

export async function render(main, ctx) {
  if (ctx.arg) { const m = await import('./submission.js'); return m.render(main, ctx); }
  const staff = isStaff(ctx.role);
  const st = { group: staff && ctx.role !== 'auditor' ? 'preparacion' : 'todas', arsId: '', period: '', q: '', page: 0 };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Radicaciones</h2><p>Desglose de los servicios de cada mes por prestador y ARS, desde la recepción hasta el cobro.</p></div>
      ${can('subs.create', ctx.role) ? html`<button class="btn primary" id="new">+ Nueva radicación</button>` : ''}</div>
    <div class="grid kpis" id="k"></div>
    <div class="tabs" id="tabs" role="group" aria-label="Estado" style="margin-top:14px"></div>
    <div class="toolbar">
      <label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Folio, prestador o cliente">
      <label class="sr-only" for="ars">ARS</label><select class="input" id="ars" style="width:auto"><option value="">Todas las ARS</option></select>
      <label class="sr-only" for="per">Período</label><input class="input" id="per" type="month" style="width:auto" max="${todayISO().slice(0, 7)}">
    </div>
    <div id="l"></div>`);

  const drawTabs = () => paint($('#tabs', main), html`${Object.entries(GROUPS).map(([k, g]) => html`<button data-g="${k}" aria-pressed="${st.group === k}">${g.label}</button>`)}`);
  drawTabs();
  listArs().then((ars) => paint($('#ars', main), html`<option value="">Todas las ARS</option>${ars.map((a) => opt(a.id, a.name))}`)).catch(() => {});

  // Tarjetas
  submissionSummary().then((rows) => {
    const prep = rows.filter((r) => ['borrador', 'recibida', 'pendiente_documentos', 'en_depuracion'].includes(r.status));
    const ready = rows.filter((r) => r.status === 'lista_para_radicar');
    const open = rows.filter((r) => ['radicada', 'en_auditoria_ars'].includes(r.status) && Number(r.balance) > 0);
    const late = open.filter((r) => daysTo(r.payment_deadline) < 0);
    const soon = open.filter((r) => { const d = daysTo(r.payment_deadline); return d >= 0 && d <= 15; });
    paint($('#k', main), html`
      <div class="kpi"><div class="l">En preparación</div><div class="v">${num(prep.length)}</div><div class="h">${money(prep.reduce((t, r) => t + Number(r.claimed), 0))}</div></div>
      <div class="kpi"><div class="l">Listas para radicar</div><div class="v">${num(ready.length)}</div><div class="h">${money(ready.reduce((t, r) => t + Number(r.claimed), 0))}</div></div>
      <div class="kpi"><div class="l">Radicadas por cobrar</div><div class="v">${money(open.reduce((t, r) => t + Number(r.balance), 0))}</div><div class="h">${num(open.length)} radicaciones</div></div>
      <div class="kpi"><div class="l">Plazo de pago vencido</div><div class="v" style="${late.length ? 'color:var(--bad)' : ''}">${num(late.length)}</div><div class="h">${num(soon.length)} vencen en 15 días o menos</div></div>`);
  }).catch((e) => paint($('#k', main), html`<div class="note bad">${friendlyError(e)}</div>`));

  const list = $('#l', main);
  const load = () => loadInto(list, () => listSubmissions({ ...st, size: CONFIG.PAGE_SIZE }), ({ data, count }) => html`
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Radicación</th><th>Prestador</th><th>ARS</th><th>Período</th><th class="n">Servicios</th><th class="n">Reclamado</th><th>Estado</th><th class="n">Expediente</th><th class="n">Saldo</th></tr></thead>
    <tbody>${data.map((s) => {
      const [lbl, cls] = subStatus(s.display_status);
      const d = daysTo(s.payment_deadline);
      return html`<tr data-id="${s.id}" style="cursor:pointer">
        <td data-l="Radicación"><a href="#/radicaciones/${s.id}"><b class="mono">${s.folio}</b></a>${s.sequence > 1 ? html` <span class="pill">#${s.sequence}</span>` : ''}</td>
        <td data-l="Prestador">${s.provider_name}${staff ? html`<div class="small muted">${s.client_name}</div>` : ''}</td>
        <td data-l="ARS">${s.ars_name}${s.provider_code_status !== 'codificado' ? html`<div><span class="pill bad" title="El prestador no tiene código en esta ARS">Sin código</span></div>` : ''}</td>
        <td data-l="Período">${period(s.period)}</td>
        <td data-l="Servicios" class="n">${num(s.lines)}</td>
        <td data-l="Reclamado" class="n">${money(s.claimed)}</td>
        <td data-l="Estado"><span class="pill ${cls}">${lbl}</span>${s.submitted_on ? html`<div class="small muted">Radicada ${date(s.submitted_on)}</div>` : ''}</td>
        <td data-l="Expediente" class="n">${s.lines ? `${s.docs_pct}%` : '—'}${s.last_total ? html`<div class="small muted">Validación ${s.last_passed}/${s.last_total}</div>` : ''}</td>
        <td data-l="Saldo" class="n">${s.submitted_on ? money(s.balance) : '—'}${d != null && Number(s.balance) > 0 ? html`<div class="small" style="${d < 0 ? 'color:var(--bad);font-weight:600' : ''}">${d < 0 ? `Vencida hace ${-d} días` : `Vence en ${d} días`}</div>` : ''}</td></tr>`;
    })}</tbody></table></div>${pager(count, st.page)}`,
  { isEmpty: (r) => !r.data.length,
    empty: () => emptyView('Sin radicaciones', st.group === 'preparacion' ? 'No hay radicaciones en preparación.' : 'No hay radicaciones con estos filtros.',
      can('subs.create', ctx.role) ? html`<button class="btn primary" data-new>+ Nueva radicación</button>` : '') });

  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-g]'); if (b) { st.group = b.dataset.g; st.page = 0; drawTabs(); load(); } });
  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; st.page = 0; load(); }, 350); });
  $('#ars', main).addEventListener('change', (e) => { st.arsId = e.target.value; st.page = 0; load(); });
  $('#per', main).addEventListener('change', (e) => { st.period = e.target.value; st.page = 0; load(); });
  list.addEventListener('click', (e) => {
    const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); load(); return; }
    if (e.target.closest('[data-new]')) { createNew(); return; }
    const row = e.target.closest('tr[data-id]'); if (row && !e.target.closest('a')) location.hash = `#/radicaciones/${row.dataset.id}`;
  });
  const createNew = async () => {
    const { newSubmissionDialog } = await import('./submission-dialogs.js');
    try { const id = await newSubmissionDialog(); if (id) { toast('Radicación creada en Borrador', 'ok'); location.hash = `#/radicaciones/${id}`; } }
    catch (err) { toast(friendlyError(err), 'bad'); }
  };
  $('#new', main)?.addEventListener('click', createNew);
  load();
}
