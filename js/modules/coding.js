/** SOFA · Codificación y tarifas vigentes (consulta). Edición con vigencias: Iteración 7. */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, friendlyError } from '../utils/ui.js';
import { listArs, searchProcedures, codesFor, tariffsFor, codedProcedureIds } from '../services/catalog.js';
import { headCount } from '../services/stats.js';
import { money, num, todayISO, rangeContains } from '../utils/formatters.js';
import { CONFIG } from '../config.js';
import { pager } from './clients.js';

export async function render(main) {
  const st = { q: '', family: '', onlyUncoded: false, page: 0 };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Codificación y tarifas</h2><p>Busca un concepto por descripción o por código (CUPS, SIMON o propio de una ARS) y compara lo que paga cada ARS hoy.</p></div></div>
    <div class="grid kpis" id="k"></div>
    <div class="toolbar" style="margin-top:14px">
      <label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Ej.: consulta, 890402, S11305">
      <label class="sr-only" for="fam">Línea</label>
      <select class="input" id="fam" style="width:auto"><option value="">Todas las líneas</option><option>Medicina y hospitalización</option><option>Nutrición clínica</option></select>
      <label class="check small"><input type="checkbox" id="unc"> Solo sin código</label>
    </div>
    <div id="res"></div>`);

  let arsMap = {};
  try { arsMap = Object.fromEntries((await listArs()).map((a) => [a.id, a.name])); } catch { /* se muestra el id */ }
  const [total, coded] = await Promise.allSettled([headCount('procedures'), codedProcedureIds()]);
  const t = total.status === 'fulfilled' ? total.value : null; const c = coded.status === 'fulfilled' ? coded.value.length : null;
  paint($('#k', main), html`
    <div class="kpi"><div class="l">Conceptos</div><div class="v">${num(t)}</div></div>
    <div class="kpi"><div class="l">Con código</div><div class="v">${num(c)}</div></div>
    <div class="kpi"><div class="l">Sin ningún código</div><div class="v" style="color:var(--bad)">${t == null || c == null ? '—' : num(t - c)}</div><div class="h">Riesgo de glosa por codificación</div></div>`);

  const res = $('#res', main);
  const today = todayISO();
  const load = () => loadInto(res, async () => {
    const { data, count } = await searchProcedures({ ...st, size: CONFIG.PAGE_SIZE });
    const ids = data.map((p) => p.id);
    const [codes, tariffs] = await Promise.all([codesFor(ids), tariffsFor(ids)]);
    return { data, count, codes, tariffs };
  }, ({ data, count, codes, tariffs }) => html`
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Concepto</th><th>Códigos</th><th>Tarifas vigentes hoy</th></tr></thead>
    <tbody>${data.map((p) => {
      const cs = codes.filter((x) => x.procedure_id === p.id);
      const ts = tariffs.filter((x) => x.procedure_id === p.id && rangeContains(x.valid_during, today)).sort((a, b) => (arsMap[a.ars_id] || '').localeCompare(arsMap[b.ars_id] || ''));
      const amounts = ts.map((x) => Number(x.amount)); const gap = amounts.length > 1 && Math.max(...amounts) > Math.min(...amounts);
      return html`<tr>
        <td data-l="Concepto"><b>${p.description}</b><div class="small muted">${p.internal_code} · ${p.family}</div></td>
        <td data-l="Códigos">${cs.length ? cs.map((x) => html`<span class="pill info mono" style="margin:0 4px 4px 0">${x.code_system === 'ARS' ? (arsMap[x.ars_id] || 'ARS') : x.code_system} ${x.code}</span>`) : html`<span class="pill bad">Sin código</span>`}</td>
        <td data-l="Tarifas">${ts.length ? html`${ts.map((x) => html`<div class="small">${arsMap[x.ars_id] || x.ars_id}: <b>${money(x.amount)}</b></div>`)}${gap ? html`<span class="pill warn" style="margin-top:4px">Brecha entre ARS</span>` : ''}` : html`<span class="muted small">Sin tarifa cargada</span>`}</td></tr>`;
    })}</tbody></table></div>${pager(count, st.page)}`,
  { isEmpty: (r) => !r.data.length, empty: () => emptyView('Sin resultados', 'Prueba con otra palabra o código.') });

  let timer;
  $('#q', main).addEventListener('input', (e) => { clearTimeout(timer); timer = setTimeout(() => { st.q = e.target.value; st.page = 0; load(); }, 350); });
  $('#fam', main).addEventListener('change', (e) => { st.family = e.target.value; st.page = 0; load(); });
  $('#unc', main).addEventListener('change', (e) => { st.onlyUncoded = e.target.checked; st.page = 0; load(); });
  res.addEventListener('click', (e) => { const b = e.target.closest('[data-page]'); if (b) { st.page = Number(b.dataset.page); load(); } });
  load();
}
