/** Preparación de radicación: conserva las bandejas existentes y presenta causas verificables. */
import { html, render as paint, $ } from '../utils/dom.js';
import { emptyView, loadingView, opt, friendlyError } from '../utils/ui.js';
import { money, num, date, period as periodLabel } from '../utils/formatters.js';
import { canOpen } from '../utils/permissions.js';
import { claimStatus } from '../utils/constants.js';
import { captureProviders, activeArs, listClaims } from '../services/claims.js';
import { preradBatches } from '../services/dossier.js';

const STATUS = { borrador: 'Borrador', recibida: 'Recibida', pendiente_documentos: 'Pendiente de documentos', en_depuracion: 'En depuración', lista_para_radicar: 'Lista para radicar' };
const CLAIM_LIMIT = 1000;
const CAUSES = [['', 'Todas las causas'], ['autorizacion', 'Autorización por revisar'], ['contrato', 'Contrato pendiente'], ['documentos', 'Expediente incompleto'], ['monto', 'Diferencia de monto'], ['inconsistencia', 'Con inconsistencia']];
const n = (v) => Math.max(0, Number(v) || 0);
const lotHref = (id) => `#/radicaciones/${id}`;

/** Qué falta según los datos agregados existentes del lote. */
export function batchGaps(b) {
  const g = [];
  if (!n(b.claims)) return ['Sin reclamaciones'];
  if (n(b.in_clinic)) g.push(`${b.in_clinic} por retirar del consultorio`);
  if (n(b.in_review)) g.push(`${b.in_review} por auditar`);
  if (n(b.inconsistent)) g.push(`${b.inconsistent} con inconsistencia`);
  if (n(b.dossier_ok) < n(b.claims)) g.push(`${n(b.claims) - n(b.dossier_ok)} con expediente incompleto`);
  if (b.fiscal_amount == null) g.push('Falta la factura fiscal del contador');
  else if (!b.fiscal_ok) g.push('La factura fiscal no cuadra');
  if (!g.length && !b.claims_ready) g.push('Comprobar las validaciones pendientes en el lote');
  return g;
}
export function batchStage(b) {
  if (b.sent_on) return ['Envío registrado', 'info'];
  if (n(b.claims) && !batchGaps(b).length && b.claims_ready && b.fiscal_ok) return ['Preparación completa · comprobar lote', 'info'];
  if (b.claims_ready && !b.fiscal_ok) return ['Factura fiscal por revisar', 'warn'];
  return ['En preparación', 'warn'];
}
/** No confirma la radicabilidad: son causas de revisión visibles en v_claims. */
export function claimPreparationIssues(c) {
  const issues = [];
  if (!String(c.authorization_number || '').trim()) issues.push({ key: 'autorizacion', label: 'Autorización sin registrar', next: 'Verificar autorización o excepción' });
  if (c.contracted === false) issues.push({ key: 'contrato', label: 'Servicio sin contrato aplicado', next: 'Revisar contrato aplicado' });
  if (c.dossier_ok === false || n(c.dossier_missing)) issues.push({ key: 'documentos', label: n(c.dossier_missing) ? `${num(c.dossier_missing)} ${n(c.dossier_missing) === 1 ? 'requisito documental pendiente' : 'requisitos documentales pendientes'}` : 'Expediente incompleto', next: 'Completar expediente' });
  if (c.discrepancy_status === 'pendiente') issues.push({ key: 'monto', label: 'Diferencia tarifaria pendiente', next: 'Revisar diferencia de monto' });
  if (c.claim_status === 'con_inconsistencia') issues.push({ key: 'inconsistencia', label: 'Con inconsistencia registrada', next: 'Revisar inconsistencia' });
  return issues;
}

export async function render(main, ctx = {}) {
  const st = { providerId: '', arsId: '', readyOnly: false, q: '', cause: '', view: 'claims' };
  let batches = [], claims = [], totalClaims = 0, loadedClaimCount = 0, sequence = 0;
  paint(main, html`<section class="claim-preparation">
    <div class="page-head"><div class="t"><h2>Preparar radicación</h2><p>Encuentra qué revisar en cada reclamación y abre el lote para comprobar sus validaciones completas.</p></div><button type="button" class="btn" id="cp-refresh">Actualizar</button></div>
    <div class="cp-filters" aria-label="Filtros de preparación">
      <div class="cp-field"><label for="pp">Médico</label><select class="input" id="pp"><option value="">Todos los médicos</option></select></div>
      <div class="cp-field"><label for="pa">ARS</label><select class="input" id="pa"><option value="">Todas las ARS</option></select></div>
      <div class="cp-field"><label for="cp-search">Buscar en los resultados</label><input class="input" id="cp-search" type="search" placeholder="Folio, paciente, médico o ARS"></div>
      <div class="cp-field"><label for="cp-cause">Qué revisar</label><select class="input" id="cp-cause">${CAUSES.map(([value, label]) => opt(value, label))}</select></div>
      <label class="check"><input type="checkbox" id="ready"> Solo lotes con reclamaciones y factura listas</label><button type="button" class="btn" id="cp-clear">Limpiar filtros</button>
    </div>
    <div id="cp-filter-error" role="alert"></div><div id="cp-error" role="alert"></div><div class="cp-kpis" id="k"></div>
    <div class="cp-tabs" role="group" aria-label="Vista de preparación"><button type="button" class="btn" data-view="claims" aria-pressed="true">Reclamaciones</button><button type="button" class="btn" data-view="batches" aria-pressed="false">Lotes y factura</button></div>
    <p class="cp-scope" id="cp-scope" role="status"></p><div id="l">${loadingView(4)}</div>
    <p class="cp-note">Registrar una autorización o completar un documento no marca automáticamente una reclamación como lista. La comprobación final se realiza en su lote.</p>
  </section>`);
  const root = $('.claim-preparation', main);
  const alive = () => document.body.contains(root) && $('.claim-preparation', main) === root;
  const normalized = (v) => String(v || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const matches = (text) => !st.q || normalized(text).includes(normalized(st.q));
  const link = (href, label, cls = '') => canOpen(href, ctx.role) ? html`<a class="${cls}" href="${href}">${label}</a>` : html`<span>${label}</span>`;
  const claimRows = () => claims.filter((c) => matches([c.folio, c.patient_name, c.provider_name, c.ars_name, c.submission_folio].join(' ')) && (!st.cause || claimPreparationIssues(c).some((i) => i.key === st.cause)));
  const lotRows = () => batches.filter((b) => matches([b.folio, b.provider_name, b.ars_name].join(' ')));
  function draw() {
    if (!alive()) return;
    const visibleClaims = claimRows(), visibleBatches = lotRows();
    const missingAuth = visibleClaims.filter((c) => claimPreparationIssues(c).some((i) => i.key === 'autorizacion')).length;
    const missingDocs = visibleClaims.filter((c) => claimPreparationIssues(c).some((i) => i.key === 'documentos')).length;
    const otherIssues = visibleClaims.filter((c) => claimPreparationIssues(c).some((i) => ['contrato', 'monto', 'inconsistencia'].includes(i.key))).length;
    const ready = visibleBatches.filter((b) => !batchGaps(b).length && b.claims_ready && b.fiscal_ok).length;
    paint($('#k', main), html`<div class="cp-kpi"><span>Autorización por revisar</span><strong>${num(missingAuth)}</strong><small>En las reclamaciones mostradas</small></div><div class="cp-kpi"><span>Expediente por completar</span><strong>${num(missingDocs)}</strong><small>En las reclamaciones mostradas</small></div><div class="cp-kpi"><span>Otras revisiones</span><strong>${num(otherIssues)}</strong><small>Contrato, monto o inconsistencia</small></div><div class="cp-kpi"><span>Lotes con preparación completa</span><strong>${num(ready)}</strong><small>Reclamaciones + factura</small></div>`);
    root.querySelectorAll('[data-view]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.view === st.view)));
    $('#cp-cause', main).disabled = st.view === 'batches';
    $('#cp-scope', main).textContent = st.view === 'claims'
      ? `${visibleClaims.length} reclamaciones de los lotes consultados, encontradas entre ${loadedClaimCount} de ${totalClaims} registros visibles. ${totalClaims > loadedClaimCount ? 'Vista parcial: abre cada lote para consultar todas sus reclamaciones.' : 'Los indicadores resumen esta lista; una reclamación puede tener más de una causa.'}`
      : `${visibleBatches.length} lotes consultados · Monto ${money(visibleBatches.reduce((total, b) => total + n(b.claimed), 0))}${batches.length === 500 ? ' · Se alcanzó el límite de 500 lotes; utiliza los filtros.' : ''}.`;
    if (st.view === 'batches') {
      paint($('#l', main), visibleBatches.length ? html`<div class="cp-batches">${visibleBatches.map((b) => {
        const [label, tone] = batchStage(b), gaps = batchGaps(b);
        return html`<article class="cp-batch"><header><div>${link(lotHref(b.submission_id), b.folio, 'mono')}<p>${b.provider_name} · ${b.ars_name}</p><small>${periodLabel(b.period)} · ${STATUS[b.status] || b.status}</small></div><span class="pill ${tone}">${label}</span></header>
          <div class="cp-lot-numbers"><span><b>${num(b.claims)}</b> reclamaciones</span><span><b>${money(b.claimed)}</b> reclamado</span><span><b>${num(b.validated)}/${num(b.claims)}</b> validadas</span><span><b>${num(b.dossier_ok)}/${num(b.claims)}</b> expedientes completos</span></div>
          <div class="cp-batch-body"><div><h3>Qué falta según el resumen del lote</h3>${gaps.length ? html`<ul>${gaps.map((gap) => html`<li>${gap}</li>`)}</ul>` : html`<p>Preparación completa según el resumen. Abre el lote para comprobar la validación final.</p>`}</div><div><h3>Factura fiscal</h3><p>${b.fiscal_amount == null ? 'Pendiente de registrar' : money(b.fiscal_amount)}${b.fiscal_amount != null ? b.fiscal_ok ? ' · Cuadra' : ' · Diferencia por revisar' : ''}</p>${b.sent_on ? html`<p>Envío registrado ${date(b.sent_on)}${b.sent_via ? ` · ${b.sent_via}` : ''}${b.sent_tracking ? ` · ${b.sent_tracking}` : ''}</p>` : ''}</div></div>
          <footer>${link(lotHref(b.submission_id), gaps.length ? `Abrir lote · ${gaps[0]}` : 'Comprobar lote y continuar', 'btn primary')}</footer></article>`;
      })}</div>` : emptyView('Sin lotes en esta vista', 'Ajusta los filtros o actualiza la consulta.'));
      return;
    }
    paint($('#l', main), visibleClaims.length ? html`<div class="table-wrap cp-table-wrap"><table class="t cards cp-table"><thead><tr><th>Reclamación y paciente</th><th>Médico · ARS</th><th>Qué revisar</th><th>Siguiente paso</th></tr></thead><tbody>${visibleClaims.map((c) => {
      const issues = claimPreparationIssues(c), [status, tone] = claimStatus(c.claim_status);
      return html`<tr><td data-l="Reclamación y paciente">${link(`#/reclamaciones/${c.id}`, c.folio, 'mono')}<b class="cp-patient">${c.patient_name}</b><small>${date(c.service_date)} · ${c.service_name}</small><span class="pill ${tone}">${status}</span></td><td data-l="Médico · ARS">${c.provider_name}<small>${c.ars_name}</small>${link(lotHref(c.submission_id), c.submission_folio || 'Abrir lote', 'cp-lot-link')}</td><td data-l="Qué revisar">${issues.length ? html`<ul>${issues.map((i) => html`<li>${i.label}</li>`)}</ul>` : html`<span class="cp-review-clear">Sin observaciones en los campos de esta lista</span><small>Falta comprobar el lote completo.</small>`}</td><td data-l="Siguiente paso">${link(issues.length ? `#/reclamaciones/${c.id}` : lotHref(c.submission_id), issues[0]?.next || 'Comprobar lote', 'btn primary')}</td></tr>`;
    })}</tbody></table></div>` : emptyView('Sin reclamaciones en esta lista', totalClaims > loadedClaimCount ? 'La vista es parcial. Abre «Lotes y factura» para consultar las reclamaciones completas de cada lote.' : 'Prueba otra causa o búsqueda. Los lotes pueden incluir otros registros que debes comprobar en su detalle.'));
  }
  async function load() {
    const id = ++sequence;
    $('#cp-refresh', main).disabled = true;
    try {
      const [lotData, claimData] = await Promise.all([
        preradBatches({ providerId: st.providerId, arsId: st.arsId, readyOnly: st.readyOnly }),
        listClaims({ providerId: st.providerId, arsId: st.arsId, realOnly: false, page: 0, size: CLAIM_LIMIT })
      ]);
      if (!alive() || id !== sequence) return;
      batches = lotData || []; loadedClaimCount = (claimData.data || []).length; totalClaims = Number.isFinite(Number(claimData.count)) ? Number(claimData.count) : loadedClaimCount;
      const batchIds = new Set(batches.map((b) => b.submission_id));
      claims = (claimData.data || []).filter((c) => batchIds.has(c.submission_id));
      paint($('#cp-error', main), html``); draw();
    } catch (error) {
      if (!alive() || id !== sequence) return;
      paint($('#cp-error', main), html`<div class="note bad">${friendlyError(error)} <button type="button" class="btn sm" id="cp-retry">Reintentar</button></div>`);
      if (!batches.length && !claims.length) paint($('#l', main), emptyView('Consulta no completada', 'No se pudo determinar qué falta. Reintenta antes de decidir que un lote está listo.'));
      else $('#cp-scope', main).textContent = 'No se pudo actualizar. Los resultados anteriores se conservan; vuelve a comprobar antes de continuar.';
      $('#cp-retry', main)?.addEventListener('click', load);
    } finally { if (alive() && id === sequence) $('#cp-refresh', main).disabled = false; }
  }
  const catalogs = await Promise.allSettled([captureProviders(), activeArs()]);
  if (!alive()) return;
  if (catalogs[0].status === 'fulfilled') paint($('#pp', main), html`<option value="">Todos los médicos</option>${catalogs[0].value.map((p) => opt(p.id, p.full_name))}`);
  if (catalogs[1].status === 'fulfilled') paint($('#pa', main), html`<option value="">Todas las ARS</option>${catalogs[1].value.map((a) => opt(a.id, a.name))}`);
  if (catalogs.some((c) => c.status === 'rejected')) paint($('#cp-filter-error', main), html`<p class="note warn">Algunos filtros no pudieron cargarse. La consulta usa los accesos disponibles; actualiza la pantalla para recuperar los catálogos.</p>`);
  $('#pp', main).addEventListener('change', (e) => { st.providerId = e.target.value; load(); });
  $('#pa', main).addEventListener('change', (e) => { st.arsId = e.target.value; load(); });
  $('#ready', main).addEventListener('change', (e) => { st.readyOnly = e.target.checked; load(); });
  $('#cp-search', main).addEventListener('input', (e) => { st.q = e.target.value.trim(); draw(); });
  $('#cp-cause', main).addEventListener('change', (e) => { st.cause = e.target.value; draw(); });
  root.querySelectorAll('[data-view]').forEach((b) => b.addEventListener('click', () => { st.view = b.dataset.view; draw(); }));
  $('#cp-refresh', main).addEventListener('click', load);
  $('#cp-clear', main).addEventListener('click', () => { Object.assign(st, { providerId: '', arsId: '', readyOnly: false, q: '', cause: '' }); ['pp', 'pa', 'cp-search', 'cp-cause'].forEach((id) => { $(`#${id}`, main).value = ''; }); $('#ready', main).checked = false; load(); });
  await load();
}
