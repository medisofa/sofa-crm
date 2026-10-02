/** SOFA · "Mi práctica" (Iteración 16): tablero del médico con lo que cobró, lo que le deben y lo que falta. */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, emptyView, errorView, opt } from '../utils/ui.js';
import { money, num, date } from '../utils/formatters.js';
import { captureProviders } from '../services/claims.js';
import { practiceDashboard } from '../services/consultorio.js';

export async function render(main, ctx) {
  paint(main, html`<div class="page-head"><div class="t"><h2>Mi práctica</h2><p>Lo que cobraste, lo que te deben las ARS y lo que falta para cobrarlo.</p></div></div>
    <div class="toolbar" id="tb"></div><div id="d"></div>`);
  const provs = await captureProviders().catch(() => []);
  if (!$('#d', main)) return;
  if (!provs.length) { paint($('#d', main), emptyView('Sin médicos', 'No hay médicos visibles para tu usuario.')); return; }
  if (provs.length > 1) paint($('#tb', main), html`<label class="sr-only" for="pr_p">Médico</label><select class="input" id="pr_p" style="width:auto">${provs.map((p) => opt(p.id, p.full_name))}</select>`);
  const box = $('#d', main);
  async function load() {
    const id = $('#pr_p', main)?.value || provs[0].id;
    paint(box, loadingView(5));
    let d; try { d = await practiceDashboard(id); } catch (err) { paint(box, errorView(err, 'pr')); return; }
    if (!document.body.contains(box)) return;
    const pend = d.pending_by_ars || []; const totalPend = pend.reduce((t, x) => t + Number(x.balance || 0), 0);
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
  $('#pr_p', main)?.addEventListener('change', load);
  load();
}
