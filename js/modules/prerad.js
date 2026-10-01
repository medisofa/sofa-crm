/**
 * SOFA · Bandeja de pre-radicación (Iteración 13). Un renglón por lote (médico × ARS × período) aún no radicado:
 * cuántas reclamaciones siguen en el consultorio, en revisión, con inconsistencia o validadas, cuántas tienen el
 * expediente completo, si la factura fiscal cuadra y si el lote ya fue enviado. Responde "¿qué falta para radicar?".
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, opt } from '../utils/ui.js';
import { money, num, date, period as periodLabel } from '../utils/formatters.js';
import { captureProviders, activeArs } from '../services/claims.js';
import { preradBatches } from '../services/dossier.js';

const STATUS = { borrador: 'Borrador', recibida: 'Recibida', pendiente_documentos: 'Pendiente de documentos', en_depuracion: 'En depuración', lista_para_radicar: 'Lista para radicar' };

/** Qué le falta a un lote, en orden de proceso */
export function batchGaps(b) {
  const g = [];
  if (!b.claims) return ['Sin reclamaciones'];
  if (b.in_clinic) g.push(`${b.in_clinic} por retirar del consultorio`);
  if (b.in_review) g.push(`${b.in_review} por auditar`);
  if (b.inconsistent) g.push(`${b.inconsistent} con inconsistencia`);
  if (b.dossier_ok < b.claims) g.push(`${b.claims - b.dossier_ok} con expediente incompleto`);
  if (b.fiscal_amount == null) g.push('Falta la factura fiscal del contador');
  else if (!b.fiscal_ok) g.push('La factura fiscal no cuadra');
  return g;
}
export function batchStage(b) {
  if (b.sent_on) return ['Enviada a la ARS', 'info'];
  if (b.status === 'lista_para_radicar' && b.fiscal_ok) return ['Lista para enviar', 'ok'];
  if (b.claims_ready && b.fiscal_ok) return ['Lista para pasar a "Lista para radicar"', 'ok'];
  if (b.claims_ready) return ['Falta factura fiscal', 'warn'];
  return ['En preparación', ''];
}

export async function render(main) {
  const st = { providerId: '', arsId: '', readyOnly: false };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Pre-radicación</h2><p>Lotes por médico, ARS y período que aún no se han radicado, con lo que le falta a cada uno.</p></div></div>
    <div class="grid kpis" id="k"></div>
    <div class="toolbar" style="margin-top:14px">
      <label class="sr-only" for="pp">Médico</label><select class="input" id="pp" style="width:auto"><option value="">Todos los médicos</option></select>
      <label class="sr-only" for="pa">ARS</label><select class="input" id="pa" style="width:auto"><option value="">Todas las ARS</option></select>
      <label class="check"><input type="checkbox" id="ready"> Solo lotes listos</label>
    </div>
    <div id="l"></div>`);
  Promise.all([captureProviders(), activeArs()]).then(([provs, ars]) => {
    if (!$('#pp', main)) return;
    paint($('#pp', main), html`<option value="">Todos los médicos</option>${provs.map((p) => opt(p.id, p.full_name))}`);
    paint($('#pa', main), html`<option value="">Todas las ARS</option>${ars.map((a) => opt(a.id, a.name))}`);
  }).catch(() => {});

  const list = $('#l', main);
  const load = () => loadInto(list, () => preradBatches(st), (rows) => {
    const ready = rows.filter((b) => b.claims_ready && b.fiscal_ok).length;
    if ($('#k', main)) paint($('#k', main), html`
      <div class="kpi"><div class="l">Lotes abiertos</div><div class="v">${num(rows.length)}</div></div>
      <div class="kpi"><div class="l">Listos (reclamaciones + factura)</div><div class="v" style="color:var(--ok)">${num(ready)}</div></div>
      <div class="kpi"><div class="l">Enviados sin acuse</div><div class="v">${num(rows.filter((b) => b.sent_on).length)}</div></div>
      <div class="kpi"><div class="l">Monto en preparación</div><div class="v">${money(rows.reduce((t, b) => t + Number(b.claimed || 0), 0))}</div></div>`);
    return html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Lote</th><th>Médico · ARS</th><th class="n">Reclamaciones</th><th>Avance</th><th class="n">Monto</th><th>Factura fiscal</th><th>Qué falta</th></tr></thead>
      <tbody>${rows.map((b) => { const [lbl, cls] = batchStage(b); const gaps = batchGaps(b); return html`<tr data-id="${b.submission_id}" style="cursor:pointer">
        <td data-l="Lote"><a href="#/radicaciones/${b.submission_id}" class="mono"><b>${b.folio}</b></a><div class="small muted">${periodLabel ? periodLabel(b.period) : date(b.period)} · ${STATUS[b.status] || b.status}</div>
          <div><span class="pill ${cls}">${lbl}</span></div>${b.sent_on ? html`<div class="small">Enviada ${date(b.sent_on)} · ${b.sent_via}${b.sent_tracking ? ` · ${b.sent_tracking}` : ''}</div>` : ''}</td>
        <td data-l="Médico · ARS">${b.provider_name}<div class="small muted">${b.ars_name}</div></td>
        <td data-l="Reclamaciones" class="n">${num(b.claims)}</td>
        <td data-l="Avance"><div class="small">Validadas ${num(b.validated)}/${num(b.claims)} · Expediente ${num(b.dossier_ok)}/${num(b.claims)}</div>
          <div style="height:8px;background:var(--surface-2);border-radius:5px;overflow:hidden;margin-top:4px" aria-hidden="true"><div style="height:100%;width:${b.claims ? Math.round(100 * Math.min(b.validated, b.dossier_ok) / b.claims) : 0}%;background:var(--ok)"></div></div></td>
        <td data-l="Monto" class="n">${money(b.claimed)}</td>
        <td data-l="Factura fiscal">${b.fiscal_amount == null ? html`<span class="pill warn">Pendiente</span>` : b.fiscal_ok ? html`<span class="pill ok">Cuadra</span>` : html`<span class="pill bad">Diferencia</span>`}
          ${b.fiscal_amount != null ? html`<div class="small muted">${money(b.fiscal_amount)}</div>` : ''}</td>
        <td data-l="Qué falta">${gaps.length ? html`<ul class="small" style="margin:0;padding-left:16px">${gaps.map((g) => html`<li>${g}</li>`)}</ul>` : html`<span class="small" style="color:var(--ok)">Nada: listo</span>`}</td></tr>`; })}</tbody></table></div>`;
  }, { isEmpty: (r) => !r.length, empty: () => emptyView('Sin lotes abiertos', 'No hay lotes pendientes de radicar con estos filtros.') });

  $('#pp', main).addEventListener('change', (e) => { st.providerId = e.target.value; load(); });
  $('#pa', main).addEventListener('change', (e) => { st.arsId = e.target.value; load(); });
  $('#ready', main).addEventListener('change', (e) => { st.readyOnly = e.target.checked; load(); });
  list.addEventListener('click', (e) => { if (e.target.closest('a')) return; const r = e.target.closest('tr[data-id]'); if (r) location.hash = `#/radicaciones/${r.dataset.id}`; });
  load();
}
