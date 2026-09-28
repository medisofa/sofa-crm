/** SOFA · Aliados referidores (contadores, administradores): canal de ventas sin nómina */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView } from '../utils/ui.js';
import { listPartners } from '../services/crm.js';
import { money, num } from '../utils/formatters.js';
import { waLink, phoneFmt } from '../utils/whatsapp.js';
import { can } from '../utils/permissions.js';
import { partnerDialog } from './crm-dialogs.js';

export async function render(main, ctx) {
  const edit = can('partners.edit', ctx.role);
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Aliados referidores</h2><p>Contadores y administradores que refieren clientes. La comisión estimada es el porcentaje acordado sobre 12 cuotas de los clientes que refirieron.</p></div>
      ${edit ? html`<button class="btn primary" id="new">+ Nuevo aliado</button>` : ''}</div><div id="l"></div>`);
  const box = $('#l', main);
  let rows = [];
  const load = () => loadInto(box, async () => { rows = await listPartners(); return rows; }, (list) => html`
    <div class="grid kpis" style="margin-bottom:14px">
      <div class="kpi"><div class="l">Aliados activos</div><div class="v">${num(list.filter((p) => p.is_active).length)}</div></div>
      <div class="kpi"><div class="l">Prospectos referidos</div><div class="v">${num(list.reduce((t, p) => t + Number(p.leads), 0))}</div></div>
      <div class="kpi"><div class="l">Convertidos en cliente</div><div class="v">${num(list.reduce((t, p) => t + Number(p.won), 0))}</div></div>
      <div class="kpi"><div class="l">Comisiones estimadas (año)</div><div class="v">${money(list.reduce((t, p) => t + Number(p.est_commission_year), 0))}</div></div></div>
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Aliado</th><th>Tipo</th><th class="n">Referidos</th><th class="n">Clientes</th><th class="n">Comisión</th><th class="n">Estimado año</th><th></th></tr></thead>
    <tbody>${list.map((p) => { const wa = waLink(p.phone); return html`<tr>
      <td data-l="Aliado"><b>${p.full_name}</b>${p.is_active ? '' : html` <span class="pill">Inactivo</span>`}<div class="small">${wa ? html`<a href="${wa}" target="_blank" rel="noopener">${phoneFmt(p.phone)}</a>` : ''}</div></td>
      <td data-l="Tipo">${p.partner_type}</td><td data-l="Referidos" class="n">${num(p.leads)}</td><td data-l="Clientes" class="n">${num(p.won)}</td>
      <td data-l="Comisión" class="n">${num(p.commission_rate)}%</td><td data-l="Estimado año" class="n">${money(p.est_commission_year)}</td>
      <td data-l="">${edit ? html`<button class="btn sm" data-edit="${p.id}">Editar</button>` : ''}</td></tr>`; })}</tbody></table></div>`,
  { empty: () => emptyView('Aún no hay aliados', 'Meta del plan de 90 días: firmar el primer contador aliado en la semana 4.') });
  box.addEventListener('click', async (e) => { const b = e.target.closest('[data-edit]'); if (b && await partnerDialog(ctx, rows.find((x) => x.id === b.dataset.edit))) load(); });
  $('#new', main)?.addEventListener('click', async () => { if (await partnerDialog(ctx)) load(); });
  load();
}
