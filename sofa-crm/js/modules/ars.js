/** SOFA · Catálogo de ARS */
import { html, render as paint } from '../utils/dom.js';
import { loadInto, emptyView } from '../utils/ui.js';
import { listArs, tariffCountsByArs } from '../services/catalog.js';
import { num } from '../utils/formatters.js';

export async function render(main) {
  paint(main, html`<div class="page-head"><div class="t"><h2>ARS</h2><p>Administradoras de Riesgos de Salud del catálogo. Las notas indican lo que falta confirmar.</p></div></div><div id="l"></div>`);
  await loadInto(main.querySelector('#l'), async () => {
    const [ars, counts] = await Promise.all([listArs(), tariffCountsByArs().catch(() => ({}))]);
    return ars.map((a) => ({ ...a, tariffs: counts[a.id] || 0 }));
  }, (rows) => html`<div class="table-wrap"><table class="t cards"><thead><tr><th>ARS</th><th>Régimen</th><th>Canal de radicación</th><th class="n">Tarifas</th><th>Notas</th></tr></thead>
    <tbody>${rows.map((a) => html`<tr>
      <td data-l="ARS"><b>${a.name}</b><div class="small muted mono">${a.code}</div></td>
      <td data-l="Régimen">${a.regime_default || '—'}</td><td data-l="Canal">${a.submission_channel || '—'}</td>
      <td data-l="Tarifas" class="n">${a.tariffs ? num(a.tariffs) : html`<span class="pill warn">0</span>`}</td>
      <td data-l="Notas" class="small">${a.notes || ''}</td></tr>`)}</tbody></table></div>`,
  { empty: () => emptyView('Sin ARS', 'Ejecuta 005_seed_catalogs.sql para cargar el catálogo.') });
}
