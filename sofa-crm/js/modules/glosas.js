/** SOFA · Glosas: bandeja con plazos, Pareto de motivos, tasa por ARS y ficha de cada glosa */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, errorView, loadingView, toast, friendlyError, opt, busy } from '../utils/ui.js';
import { listGlosas, glosaSummary, glosaPareto, arsReconciliation, getGlosa, glosaItems, glosaAppeals, glosaHistory, changeGlosaStatus, GLOSA_OPEN } from '../services/finance.js';
import { profileNames } from '../services/submissions.js';
import { listArs } from '../services/catalog.js';
import { money, num, date, dateTime, period } from '../utils/formatters.js';
import { glosaStatus } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';
import { CONFIG } from '../config.js';
import { pager } from './clients.js';

const pct = (a, b) => (Number(b) > 0 ? Math.round((1000 * Number(a)) / Number(b)) / 10 : 0);
const bar = (v, max, color = 'var(--navy-2)') => html`<div style="height:8px;background:var(--surface-2);border-radius:4px;overflow:hidden;margin-top:4px"><div style="height:100%;width:${max ? Math.max(2, Math.round((100 * v) / max)) : 0}%;background:${color}"></div></div>`;

export async function render(main, ctx) {
  if (ctx.arg) return renderDetail(main, ctx);
  const st = { group: 'abiertas', arsId: '', q: '', page: 0 };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Glosas</h2><p>Cada glosa se trabaja dos veces: se apela para recuperar el dinero y se corrige la causa para que no se repita.</p></div></div>
    <div class="grid kpis" id="k"></div>
    <div class="grid two" style="margin-top:14px"><div class="card"><h2>Principales motivos</h2><p class="sub">Monto glosado por motivo (Pareto).</p><div id="par"></div></div>
      <div class="card"><h2>Tasa de glosa por ARS</h2><p class="sub">Glosado sobre lo radicado.</p><div id="rate"></div></div></div>
    <div class="tabs" id="tabs" role="group" aria-label="Estado" style="margin-top:14px"></div>
    <div class="toolbar"><label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Folio, prestador, cliente o referencia ARS">
      <label class="sr-only" for="ars">ARS</label><select class="input" id="ars" style="width:auto"><option value="">Todas las ARS</option></select></div>
    <div id="l"></div>`);
  const tabs = [['abiertas', 'Abiertas'], ['resueltas', 'Resueltas'], ['todas', 'Todas']];
  const drawTabs = () => paint($('#tabs', main), html`${tabs.map(([k, l]) => html`<button data-g="${k}" aria-pressed="${st.group === k}">${l}</button>`)}`);
  drawTabs();
  listArs().then((a) => paint($('#ars', main), html`<option value="">Todas las ARS</option>${a.map((x) => opt(x.id, x.name))}`)).catch(() => {});

  Promise.all([glosaSummary(), glosaPareto(), arsReconciliation()]).then(([rows, par, rec]) => {
    const tot = rows.reduce((t, r) => t + Number(r.amount), 0), disp = rows.reduce((t, r) => t + Number(r.in_dispute), 0);
    const recov = rows.reduce((t, r) => t + Number(r.recovered), 0), acc = rows.reduce((t, r) => t + Number(r.accepted), 0);
    const soon = rows.filter((r) => GLOSA_OPEN.includes(r.status) && r.days_left <= 7);
    paint($('#k', main), html`
      <div class="kpi"><div class="l">Glosado</div><div class="v">${money(tot)}</div><div class="h">${num(rows.length)} glosas</div></div>
      <div class="kpi"><div class="l">En disputa</div><div class="v">${money(disp)}</div></div>
      <div class="kpi"><div class="l">Recuperado</div><div class="v" style="color:var(--ok)">${money(recov)}</div><div class="h">${pct(recov, recov + acc)}% de lo resuelto</div></div>
      <div class="kpi"><div class="l">Vencen en 7 días o menos</div><div class="v" style="${soon.length ? 'color:var(--bad)' : ''}">${num(soon.length)}</div><div class="h">Incluye las vencidas</div></div>`);
    const byReason = {}; par.forEach((p) => { byReason[p.reason_name] = (byReason[p.reason_name] || 0) + Number(p.amount); });
    const reasons = Object.entries(byReason).sort((a, b) => b[1] - a[1]).slice(0, 8); const maxR = reasons[0]?.[1] || 0;
    paint($('#par', main), reasons.length ? html`${reasons.map(([n, v]) => html`<div style="margin:8px 0"><div class="small" style="display:flex;justify-content:space-between"><span>${n}</span><b>${money(v)}</b></div>${bar(v, maxR, 'var(--red)')}</div>`)}` : html`<p class="small muted">Aún no hay glosas.</p>`);
    const byArs = {}; par.forEach((p) => { byArs[p.ars_id] = byArs[p.ars_id] || { name: p.ars_name, g: 0 }; byArs[p.ars_id].g += Number(p.amount); });
    const radByArs = {}; rec.forEach((r) => { radByArs[r.ars_id] = (radByArs[r.ars_id] || 0) + Number(r.radicado || 0); });
    const rates = Object.entries(byArs).map(([id, x]) => [x.name, pct(x.g, radByArs[id]), x.g]).sort((a, b) => b[1] - a[1]);
    paint($('#rate', main), rates.length ? html`${rates.map(([n, r, g]) => html`<div style="margin:8px 0"><div class="small" style="display:flex;justify-content:space-between"><span>${n}</span><b>${r}% · ${money(g)}</b></div>${bar(r, Math.max(...rates.map((x) => x[1])), r > 5 ? 'var(--red)' : 'var(--navy-2)')}</div>`)}<p class="small muted">Meta de SOFA: menos de 5%.</p>` : html`<p class="small muted">Sin datos.</p>`);
  }).catch((e) => paint($('#k', main), errorView(e)));

  const list = $('#l', main);
  const load = () => loadInto(list, () => listGlosas({ ...st, size: CONFIG.PAGE_SIZE }), ({ data, count }) => html`
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Radicación</th><th>Prestador</th><th>ARS</th><th>Motivo principal</th><th class="n">Glosado</th><th class="n">En disputa</th><th>Estado</th><th>Responder antes de</th></tr></thead>
    <tbody>${data.map((g) => { const [l, c] = glosaStatus(g.status); const open = GLOSA_OPEN.includes(g.status); return html`<tr data-id="${g.id}" style="cursor:pointer">
      <td data-l="Radicación"><a href="#/glosas/${g.id}" class="mono"><b>${g.folio}</b></a><div class="small muted">${period(g.period)}${g.ars_reference ? ` · ${g.ars_reference}` : ''}</div></td>
      <td data-l="Prestador">${g.provider_name}${isStaff(ctx.role) ? html`<div class="small muted">${g.client_name}</div>` : ''}</td>
      <td data-l="ARS">${g.ars_name}</td><td data-l="Motivo">${g.main_reason || '—'}${g.items > 1 ? html` <span class="small muted">(${g.items} servicios)</span>` : ''}</td>
      <td data-l="Glosado" class="n">${money(g.amount)}</td><td data-l="En disputa" class="n">${money(g.in_dispute)}</td>
      <td data-l="Estado"><span class="pill ${c}">${l}</span></td>
      <td data-l="Plazo">${open ? html`${date(g.appeal_deadline)}<div class="small" style="${g.days_left < 0 ? 'color:var(--bad);font-weight:600' : g.days_left <= 7 ? 'color:var(--warn);font-weight:600' : ''}">${g.days_left < 0 ? `Vencida hace ${-g.days_left} días` : `Faltan ${g.days_left} días`}</div>` : '—'}</td></tr>`; })}</tbody></table></div>${pager(count, st.page)}`,
  { isEmpty: (r) => !r.data.length, empty: () => emptyView(st.group === 'abiertas' ? 'Sin glosas abiertas' : 'Sin glosas', 'Las glosas se registran desde la ficha de una radicación ya radicada.') });
  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-g]'); if (b) { st.group = b.dataset.g; st.page = 0; drawTabs(); load(); } });
  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; st.page = 0; load(); }, 350); });
  $('#ars', main).addEventListener('change', (e) => { st.arsId = e.target.value; st.page = 0; load(); });
  list.addEventListener('click', (e) => {
    const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); load(); return; }
    const row = e.target.closest('tr[data-id]'); if (row && !e.target.closest('a')) location.hash = `#/glosas/${row.dataset.id}`;
  });
  load();
}

async function renderDetail(main, ctx) {
  const id = ctx.arg;
  paint(main, html`<div id="g">${loadingView(6)}</div>`);
  const box = $('#g', main);
  const refresh = async () => {
    try {
      const g = await getGlosa(id);
      if (!g) { paint(box, emptyView('Glosa no encontrada', 'No existe o tu rol no tiene acceso.', html`<a class="btn" href="#/glosas">Volver</a>`)); return; }
      const [items, appeals, hist] = await Promise.all([glosaItems(id), glosaAppeals(id), glosaHistory(id)]);
      const names = await profileNames([...hist.map((h) => h.changed_by), ...appeals.map((a) => a.created_by)]).catch(() => ({}));
      draw(g, items, appeals, hist, names);
    } catch (err) { paint(box, errorView(err)); }
  };
  const draw = (g, items, appeals, hist, names) => {
    ctx.setTitle(`Glosa · ${g.folio}`);
    const [l, c] = glosaStatus(g.status); const edit = can('glosas.edit', ctx.role); const open = GLOSA_OPEN.includes(g.status);
    const acts = [];
    if (edit && g.status === 'pendiente') acts.push(['analizada', 'Marcar analizada', '']);
    if (edit && open) acts.push(['__appeal', g.appeals ? 'Registrar otra apelación' : 'Apelar', 'primary']);
    if (edit && g.status === 'apelada') acts.push(['en_revision', 'En revisión por la ARS', '']);
    if (edit && open) acts.push(['__resolve', 'Registrar resultado', 'primary']);
    if (edit && ['pendiente', 'analizada'].includes(g.status)) acts.push(['aceptada', 'Aceptar sin apelar', 'danger']);
    if (edit && ['aceptada', 'revertida', 'parcial'].includes(g.status)) acts.push(['cerrada', 'Cerrar', '']);
    paint(box, html`
      <div class="page-head"><div class="t"><p><a href="#/glosas">← Glosas</a></p>
        <h2>Glosa · <a href="#/radicaciones/${g.submission_id}" class="mono">${g.folio}</a> <span class="pill ${c}">${l}</span></h2>
        <p>${isStaff(ctx.role) ? `${g.client_name} · ` : ''}${g.provider_name} · ${g.ars_name} · ${period(g.period)}${g.ars_reference ? ` · Ref. ARS ${g.ars_reference}` : ''}</p></div>
        <div class="toolbar" style="margin:0">${acts.map(([k, lb, cl]) => html`<button class="btn ${cl}" data-act="${k}">${lb}</button>`)}</div></div>
      ${open ? html`<div class="note ${g.days_left < 0 ? 'bad' : g.days_left <= 7 ? 'warn' : ''}">Notificada el ${date(g.notified_on)}. Responder antes del <b>${date(g.appeal_deadline)}</b> (${g.days_left < 0 ? `vencida hace ${-g.days_left} días` : `faltan ${g.days_left} días`}).</div>` : ''}
      <div class="grid kpis"><div class="kpi"><div class="l">Glosado</div><div class="v">${money(g.amount)}</div><div class="h">${num(g.items)} servicios</div></div>
        <div class="kpi"><div class="l">En disputa</div><div class="v">${money(g.in_dispute)}</div></div>
        <div class="kpi"><div class="l">Recuperado</div><div class="v" style="color:var(--ok)">${money(g.recovered)}</div></div>
        <div class="kpi"><div class="l">Aceptado (pérdida)</div><div class="v" style="color:var(--bad)">${money(g.accepted)}</div></div></div>
      <div class="card" style="margin-top:14px"><h2>Servicios glosados</h2>
        <div class="table-wrap"><table class="t cards"><thead><tr><th>Servicio</th><th>Motivo</th><th class="n">Glosado</th><th class="n">Recuperado</th><th class="n">Aceptado</th></tr></thead><tbody>
        ${items.map((i) => html`<tr><td data-l="Servicio">${i.service_lines?.patient_name}<div class="small muted">${date(i.service_lines?.service_date)} · ${i.service_lines?.procedures?.description}</div></td>
          <td data-l="Motivo">${i.glosa_reasons?.name}<div class="small muted">${i.glosa_reasons?.category}</div></td><td data-l="Glosado" class="n">${money(i.amount)}</td>
          <td data-l="Recuperado" class="n">${money(i.recovered_amount)}</td><td data-l="Aceptado" class="n">${money(i.accepted_amount)}</td></tr>`)}</tbody></table></div></div>
      <div class="grid two" style="margin-top:14px">
        <div class="card"><h2>Apelaciones</h2>${appeals.length ? html`<div class="list">${appeals.map((a) => html`<div class="li"><div class="b"><div class="t1" style="font-weight:500">${date(a.submitted_on)} · <span class="pill ${a.outcome === 'favorable' ? 'ok' : a.outcome === 'desfavorable' ? 'bad' : a.outcome === 'parcial' ? 'warn' : ''}">${{ pendiente: 'Pendiente', favorable: 'Favorable', parcial: 'Parcial', desfavorable: 'Desfavorable' }[a.outcome]}</span></div><div class="t2" style="white-space:pre-wrap">${a.argument}</div><div class="t2">${names[a.created_by] || ''}</div></div></div>`)}</div>` : html`<p class="small muted">Sin apelaciones.</p>`}</div>
        <div class="card"><h2>Historial</h2><div class="list">${hist.map((h) => html`<div class="li"><div class="b"><div class="t1" style="font-weight:500">${h.from_status ? `${glosaStatus(h.from_status)[0]} → ` : ''}${glosaStatus(h.to_status)[0]}</div><div class="t2">${dateTime(h.changed_at)}${names[h.changed_by] ? ` · ${names[h.changed_by]}` : ''}${h.comment ? ` · ${h.comment}` : ''}</div></div></div>`)}</div></div>
      </div>`);
    box.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', () => busy(b, async () => {
      try {
        const d = await import('./finance-dialogs.js');
        if (b.dataset.act === '__appeal') { if (!(await d.appealDialog(g))) return; toast('Apelación registrada', 'ok'); }
        else if (b.dataset.act === '__resolve') { const r = await d.resolveDialog(g, items); if (!r) return; toast(`Resultado guardado: ${glosaStatus(r)[0]}`, 'ok'); }
        else { await changeGlosaStatus(g.id, b.dataset.act); toast(`Glosa: ${glosaStatus(b.dataset.act)[0]}`, 'ok'); }
        await refresh();
      } catch (err) { toast(friendlyError(err), 'bad'); }
    })));
  };
  await refresh();
}
