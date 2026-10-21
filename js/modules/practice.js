/** SOFA · "Mi práctica" (Iteración 16): tablero del médico con lo que cobró, lo que le deben y lo que falta. */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, emptyView, errorView, opt } from '../utils/ui.js';
import { money, num, date } from '../utils/formatters.js';
import { captureProviders } from '../services/claims.js';
import { practiceDashboard } from '../services/consultorio.js';
import { getDashboardPreference, setDashboardPreference } from '../services/dashboard-preferences.js';
import { visibleNav } from '../utils/permissions.js';

export async function render(main, ctx) {
  paint(main, html`<div class="page-head"><div class="t"><h2>Mi práctica</h2><p>Lo que cobraste, lo que te deben las ARS y lo que falta para cobrarlo.</p></div></div>
    <div class="toolbar" id="tb"></div>
    <div class="tabs" id="dashViews" role="group" aria-label="Modelo de dashboard" style="margin:10px 0 6px">
      <button type="button" data-view="ejecutivo" aria-pressed="true">Ejecutivo</button>
      <button type="button" data-view="operativo" aria-pressed="false">Operativo</button>
      <button type="button" data-view="compacto" aria-pressed="false">Compacto</button>
    </div>
    <div class="small muted" id="dashHint" style="margin-bottom:12px">Vista financiera y de decisiones.</div>
    <div id="d"></div><div id="modules" style="margin-top:18px"></div>`);
  const provs = await captureProviders().catch(() => []);
  if (!$('#d', main)) return;
  if (!provs.length) { paint($('#d', main), emptyView('Sin médicos', 'No hay médicos visibles para tu usuario.')); return; }
  if (provs.length > 1) paint($('#tb', main), html`<label class="sr-only" for="pr_p">Médico</label><select class="input" id="pr_p" style="width:auto">${provs.map((p) => opt(p.id, p.full_name))}</select>`);
  const box = $('#d', main);
  let dashboardView = 'ejecutivo';
  const viewHint = () => ({ ejecutivo: 'Vista financiera y de decisiones.', operativo: 'Vista orientada al trabajo pendiente y al avance de reclamaciones.', compacto: 'Vista rápida con los indicadores esenciales.' }[dashboardView]);
  const syncViewButtons = () => { main.querySelectorAll('#dashViews [data-view]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.view === dashboardView))); const h = $('#dashHint', main); if (h) h.textContent = viewHint(); };
  async function load() {
    const id = $('#pr_p', main)?.value || provs[0].id;
    const provider = provs.find((p) => p.id === id) || provs[0];
    dashboardView = await getDashboardPreference(provider.organization_id).catch(() => dashboardView);
    syncViewButtons();
    paint(box, loadingView(5));
    let d; try { d = await practiceDashboard(id); } catch (err) { paint(box, errorView(err, 'pr')); return; }
    if (!document.body.contains(box)) return;
    const pend = d.pending_by_ars || []; const totalPend = pend.reduce((t, x) => t + Number(x.balance || 0), 0);
    if (dashboardView === 'compacto') {
      paint(box, html`<div class="card"><div class="grid kpis"><div class="kpi"><div class="l">Reclamado este mes</div><div class="v">${money(d.claimed_month)}</div></div><div class="kpi"><div class="l">Cobrado ARS</div><div class="v" style="color:var(--ok)">${d.paid_month == null ? '—' : money(d.paid_month)}</div></div><div class="kpi"><div class="l">Pendiente ARS</div><div class="v">${money(totalPend)}</div></div><div class="kpi"><div class="l">Requieren atención</div><div class="v">${num(Number(d.dossier_missing || 0) + Number(d.returned || 0))}</div></div></div><div class="toolbar" style="margin:14px 0 0"><a class="btn" href="#/reclamaciones">Reclamaciones</a><a class="btn" href="#/radicaciones">Radicaciones</a></div></div>`);
      return;
    }
    if (dashboardView === 'operativo') {
      paint(box, html`<div class="grid kpis"><div class="kpi"><div class="l">Capturadas este mes</div><div class="v">${num(d.captured_month)}</div><div class="h">${money(d.claimed_month)}</div></div><div class="kpi"><div class="l">Expedientes incompletos</div><div class="v" style="${d.dossier_missing ? 'color:var(--bad)' : ''}">${num(d.dossier_missing)}</div></div><div class="kpi"><div class="l">Devueltas por ARS</div><div class="v" style="${d.returned ? 'color:var(--bad)' : ''}">${num(d.returned)}</div></div><div class="kpi"><div class="l">Pendiente de cobro</div><div class="v">${money(totalPend)}</div></div></div><div class="grid two" style="margin-top:14px"><div class="card"><h2>Flujo de trabajo</h2><div class="list"><a class="li" href="#/reclamaciones"><div class="b"><div class="t1">Revisar reclamaciones</div><div class="t2">Captura, coincidencias, inconsistencias y expediente</div></div><b>→</b></a><a class="li" href="#/radicaciones"><div class="b"><div class="t1">Preparar ciclo de radicación</div><div class="t2">Seleccionar las reclamaciones listas del período</div></div><b>→</b></a></div></div><div class="card"><h2>Alertas</h2><div class="list"><div class="li"><div class="b"><div class="t1">Documentación</div><div class="t2">Expedientes incompletos</div></div><span class="pill ${d.dossier_missing ? 'bad' : 'ok'}">${num(d.dossier_missing)}</span></div><div class="li"><div class="b"><div class="t1">Glosas abiertas</div><div class="t2">${money(d.glosas_open?.amount)}</div></div><span class="pill ${d.glosas_open?.count ? 'warn' : 'ok'}">${num(d.glosas_open?.count)}</span></div></div></div></div>`);
      return;
    }
    paint(box, html`
      <div class="grid kpis">
        <div class="kpi"><div class="l">Cobrado de las ARS este mes</div><div class="v" style="color:var(--ok)">${d.paid_month == null ? '—' : money(d.paid_month)}</div></div>
        <div class="kpi"><div class="l">Te deben las ARS</div><div class="v">${money(totalPend)}</div><div class="h">${num(pend.reduce((t, x) => t + Number(x.claims), 0))} reclamaciones radicadas</div></div>
        <div class="kpi"><div class="l">Pacientes privados este mes</div><div class="v">${money(d.private_month?.collected)}</div><div class="h">${num(d.private_month?.count)} cobros${Number(d.private_pending) ? ` · pendiente ${money(d.private_pending)}` : ''}</div></div>
        <div class="kpi"><div class="l">Reclamado este mes</div><div class="v">${money(d.claimed_month)}</div><div class="h">${num(d.captured_month)} servicios</div></div>
      </div>
      <div class="grid two" style="margin-top:14px">
        <div class="card"><h2>Lo que te deben, por ARS</h2>${pend.length ? html`<div class="table-wrap"><table class="t cards"><thead><tr><th>ARS</th><th class="n">Reclamaciones</th><th class="n">Saldo</th><th>Pago esperado</th></tr></thead><tbody>
          ${pend.map((x) => html`<tr><td data-l="ARS">${x.ars}</td><td data-l="Reclamaciones" class="n">${num(x.claims)}</td><td data-l="Saldo" class="n">${money(x.balance)}</td><td data-l="Pago esperado">${x.expected_on ? date(x.expected_on) : '—'}</td></tr>`)}</tbody></table></div>
          <p class="small muted">El pago esperado usa el tiempo real que tarda cada ARS en pagar (o 60 días si aún no hay historial).</p>` : html`<p class="small muted">No hay reclamaciones radicadas pendientes de pago.</p>`}</div>
        <div class="card"><h2>Lo que falta para cobrar</h2><div class="list">
          <a class="li" href="#/reclamaciones" style="text-decoration:none;color:inherit"><div class="b"><div class="t1">Expedientes incompletos</div><div class="t2">Reclamaciones a las que les falta algún documento</div></div><b>${num(d.dossier_missing)}</b></a>
          <a class="li" href="#/reclamaciones" style="text-decoration:none;color:inherit"><div class="b"><div class="t1">Devueltas por la ARS</div><div class="t2">Hay que corregirlas y reenviarlas</div></div><b>${num(d.returned)}</b></a>
          <div class="li"><div class="b"><div class="t1">Glosas abiertas</div><div class="t2">SOFA las está gestionando</div></div><b>${num(d.glosas_open?.count)} · ${money(d.glosas_open?.amount)}</b></div></div></div>
      </div>`);
  }
  $('#dashViews', main)?.addEventListener('click', async (e) => { const b = e.target.closest('[data-view]'); if (!b) return; const id = $('#pr_p', main)?.value || provs[0].id; const provider = provs.find((p) => p.id === id) || provs[0]; dashboardView = b.dataset.view; syncViewButtons(); try { await setDashboardPreference(provider.organization_id, dashboardView); await load(); } catch (err) { toast(friendlyError(err), 'bad'); } });
  const modulesBox = $('#modules', main);
  if (modulesBox) {
    const groups = visibleNav(ctx.role).filter((g) => g.group !== 'Mi cuenta')
      .map((g) => ({ ...g, items: g.items.filter((i) => !['mi-dashboard','practica'].includes(i.route)) }))
      .filter((g) => g.items.length);
    paint(modulesBox, html`<h2 style="margin-bottom:10px">Mis módulos</h2><div class="grid two">${groups.map((g) => html`<div class="card"><div class="small muted" style="font-weight:700;text-transform:uppercase;letter-spacing:.04em">${g.group}</div><div class="list" style="margin-top:6px">${g.items.map((i) => html`<a class="li" href="#/${i.route}" style="text-decoration:none;color:inherit"><div class="b"><div class="t1">${i.label}</div></div><span>›</span></a>`)}</div></div>`)}</div>`);
  }
  $('#pr_p', main)?.addEventListener('change', load);
  load();
}
