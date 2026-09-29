/** SOFA · Clientes PSS (lectura). La creación llega con el CRM (Iteración 4). */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView } from '../utils/ui.js';
import { listClients } from '../services/clients.js';
import { money, date, num } from '../utils/formatters.js';
import { CONFIG } from '../config.js';
import { isStaff, can } from '../utils/permissions.js';
import { clientDialog } from './crm-dialogs.js';

const STATUS = { incorporacion: ['Incorporación', 'info'], activo: ['Activo', 'ok'], suspendido: ['Suspendido', 'warn'], inactivo: ['Inactivo', ''] };

export async function render(main, ctx) {
  if (ctx.arg) { const m = await import('./client.js'); return m.render(main, ctx); }
  const st = { q: '', status: '', page: 0 };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Clientes PSS</h2><p>${isStaff(ctx.role) ? 'Cartera de clientes con su desempeño de cobro. Solo ves los clientes que tu rol permite.' : 'La información de tu organización.'}</p></div>
      ${can('clients.create', ctx.role) ? html`<button class="btn primary" id="newc">+ Nuevo cliente</button>` : ''}</div>
    <div class="toolbar">
      <label class="sr-only" for="q">Buscar cliente</label><input class="input grow" id="q" type="search" placeholder="Buscar por nombre">
      <label class="sr-only" for="st">Estado</label>
      <select class="input" id="st" style="width:auto"><option value="">Todos los estados</option>${Object.entries(STATUS).map(([k, [l]]) => html`<option value="${k}">${l}</option>`)}</select>
    </div>
    <div id="list"></div>`);
  const list = $('#list', main);
  const load = () => loadInto(list, () => listClients({ ...st, size: CONFIG.PAGE_SIZE }), ({ data, count }) => html`
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Cliente</th><th>Estado</th><th class="n">Radicaciones</th><th class="n">Radicado</th><th class="n">Pagado</th><th class="n">Saldo</th><th class="n">% glosa</th><th class="n">Códigos pendientes</th></tr></thead>
    <tbody>${data.map((c) => html`<tr>
      <td data-l="Cliente"><a href="#/clientes/${c.organization_id}"><b>${c.legal_name}</b></a><div class="small muted">Desde ${date(c.started_on)}</div></td>
      <td data-l="Estado"><span class="pill ${(STATUS[c.status] || ['', ''])[1]}">${(STATUS[c.status] || [c.status])[0]}</span></td>
      <td data-l="Radicaciones" class="n">${num(c.submissions)}</td><td data-l="Radicado" class="n">${money(c.radicado)}</td>
      <td data-l="Pagado" class="n">${money(c.pagado)}</td><td data-l="Saldo" class="n">${money(c.saldo)}</td>
      <td data-l="% glosa" class="n">${c.tasa_glosa == null ? '—' : `${c.tasa_glosa}%`}</td>
      <td data-l="Códigos pendientes" class="n">${c.codigos_pendientes ? html`<span class="pill warn">${c.codigos_pendientes}</span>` : '0'}</td></tr>`)}</tbody></table></div>
    ${pager(count, st.page)}`,
  { isEmpty: (r) => !r.data.length, empty: () => emptyView(st.q || st.status ? 'Sin resultados' : 'Aún no hay clientes', st.q || st.status ? 'Prueba con otra búsqueda.' : 'Crea uno con "Nuevo cliente" o convirtiendo una oportunidad ganada del pipeline.') });
  let t;
  $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; st.page = 0; load(); }, 350); });
  $('#st', main).addEventListener('change', (e) => { st.status = e.target.value; st.page = 0; load(); });
  list.addEventListener('click', (e) => { const b = e.target.closest('[data-page]'); if (b) { st.page = Number(b.dataset.page); load(); } });
  $('#newc', main)?.addEventListener('click', async () => { const id = await clientDialog(); if (id) location.hash = `#/clientes/${id}`; });
  load();
}
export function pager(count, page, size = CONFIG.PAGE_SIZE) {
  const pages = Math.max(1, Math.ceil((count || 0) / size));
  if (pages <= 1) return html`<div class="pager">${num(count)} registros</div>`;
  return html`<div class="pager"><span>${num(count)} registros · página ${page + 1} de ${pages}</span>
    <button class="btn sm" data-page="${page - 1}" ${page <= 0 ? 'disabled' : ''}>Anterior</button>
    <button class="btn sm" data-page="${page + 1}" ${page >= pages - 1 ? 'disabled' : ''}>Siguiente</button></div>`;
}
