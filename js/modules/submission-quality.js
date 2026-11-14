/** Control de calidad del lote: una consulta fallida no equivale a una validación aprobada. */
import { html } from '../utils/dom.js';
import { dateTime } from '../utils/formatters.js';
import { canOpen } from '../utils/permissions.js';

export function ensureSubmissionQualityStyles() {
  if (document.getElementById('submission-quality-styles')) return;
  const link = document.createElement('link'); link.id = 'submission-quality-styles'; link.rel = 'stylesheet';
  link.href = new URL('../../css/submission-quality.css', import.meta.url).href; document.head.appendChild(link);
}

const SOURCES = {
  validation: ['Validación prefacturación', 'lote'], fiscal: ['Datos de la factura fiscal', 'lote'], fiscalCheck: ['Comprobación de la factura fiscal', 'lote'],
  lineChecklist: ['Documentación por reclamación', 'reclamación'], checks: ['Comprobaciones documentales', 'reclamación'], docs: ['Expediente digital', 'lote'],
  duplicates: ['Coincidencias de reclamaciones', 'par'], pays: ['Pagos aplicados', 'lote'], glosas: ['Glosas', 'lote'],
  distribution: ['Reparto del pago', 'lote'], claimMoney: ['Aprobado y pagado por reclamación', 'reclamación'], delivery: ['Constancia de envío', 'lote']
};
const stateLabels = { blocked: ['Requiere corrección', 'bad'], warning: ['Revisar', 'warn'], unchecked: ['No comprobado', 'warn'] };
const lineLabel = (line) => line.claim_folio || line.folio || `Reclamación ${String(line.id || '').slice(0, 8)}`;
const pairKey = (a, b) => [a, b].sort().join(':');

/** Los hallazgos orientan el trabajo; la autorización para avanzar sigue en el backend. */
export function buildSubmissionQuality(data, role) {
  const { sub = {}, lines = [], lineCk = [], val, fcheck, duplicates = [], qualitySources = {} } = data;
  const findings = [];
  const sourceAvailable = (key) => qualitySources[key]?.state !== 'unavailable';
  const add = (finding) => findings.push(finding);
  for (const [key, [label, scope]] of Object.entries(SOURCES)) {
    if (qualitySources[key]?.state === 'unavailable') add({ key: `source:${key}`, state: 'unchecked', scope,
      reference: sub.folio || 'Lote actual', title: label, detail: qualitySources[key].error || 'La consulta no respondió. Vuelve a comprobar antes de continuar.', target: 'submission-quality', action: 'Reintentar comprobación' });
  }
  if (sourceAvailable('validation') && val?.items) {
    val.items.filter((item) => !item.ok).forEach((item, index) => add({ key: `validation:${index}`, state: item.critical ? 'blocked' : 'warning', scope: 'lote',
      reference: sub.folio || 'Lote actual', title: item.label || 'Validación pendiente',
      detail: item.n > 1 ? `${item.ok_count ?? 0} de ${item.n} servicios cumplen. La comprobación corresponde al lote.` : 'Validación del lote pendiente según la última respuesta del servidor.', target: 'submission-validation', action: 'Ver validación' }));
  }
  for (const line of lines) {
    const reference = lineLabel(line);
    const href = canOpen(`#/reclamaciones/${line.id}`, role) ? `#/reclamaciones/${line.id}` : null;
    if (!String(line.authorization_number || '').trim()) add({ key: `auth:${line.id}`, state: 'warning', scope: 'reclamación', reference,
      title: 'Número de autorización por revisar', detail: 'El número no figura en la reclamación. La exigencia depende del servicio y la validación del servidor; revisa su expediente antes de corregir.', href, target: 'submission-lines', action: href ? 'Abrir reclamación' : 'Ver servicio' });
    if (!String(line.member_number || '').trim()) add({ key: `member:${line.id}`, state: 'warning', scope: 'reclamación', reference,
      title: 'NSS o afiliado pendiente', detail: 'Completa el identificador del paciente en la reclamación correspondiente.', href, target: 'submission-lines', action: href ? 'Abrir reclamación' : 'Ver servicio' });
    if (sourceAvailable('lineChecklist')) {
      const check = lineCk.find((c) => c.service_line_id === line.id);
      if (!check) add({ key: `docs-unknown:${line.id}`, state: 'unchecked', scope: 'reclamación', reference,
        title: 'Cobertura documental sin resultado', detail: 'No se recibió el resultado documental de esta reclamación. No se interpreta como expediente completo.', target: 'submission-documents', action: 'Ver expediente' });
      else if (Number(check.required) > 0 && Number(check.pct) < 100) add({ key: `docs:${line.id}`, state: 'warning', scope: 'reclamación', reference,
        title: 'Documentación obligatoria incompleta', detail: `${Number(check.pct) || 0}% de cobertura documental en esta reclamación.`, target: 'submission-documents', action: 'Revisar documentos' });
    }
  }
  if (sourceAvailable('duplicates')) {
    const seen = new Set();
    duplicates.forEach((d) => {
      const key = pairKey(d.line_id, d.other_line_id); if (seen.has(key)) return; seen.add(key);
      if (d.blocks_radicacion) add({ key: `duplicate:${key}`, state: 'blocked', scope: 'par', reference: `${d.folio || 'Reclamación'} ↔ ${d.other_folio || 'Coincidencia'}`,
        title: d.review_decision === 'duplicado_confirmado' ? 'Duplicado confirmado pendiente de gestión' : 'Coincidencia que bloquea la radicación',
        detail: d.resolution_request_status === 'pendiente' ? 'Hay una solicitud de exclusión pendiente; todavía no elimina la reclamación ni levanta el bloqueo.' : 'El par incluye al menos una reclamación de este lote. Registrar una revisión no corrige automáticamente los registros.', target: 'duplicateCard', action: 'Gestionar par' });
    });
  }
  if (sourceAvailable('fiscalCheck') && fcheck && !fcheck.registered) add({ key: 'fiscal:missing', state: 'blocked', scope: 'lote', reference: sub.folio || 'Lote actual', title: 'Factura fiscal pendiente de registrar', detail: 'Completa número, NCF y monto antes de radicar.', target: 'fisc', action: 'Revisar factura' });
  else if (sourceAvailable('fiscalCheck') && fcheck && !fcheck.ok) add({ key: 'fiscal:difference', state: fcheck.mode === 'advertir' ? 'warning' : 'blocked', scope: 'lote', reference: sub.folio || 'Lote actual', title: 'Diferencia en la factura fiscal', detail: 'Revisa la diferencia o la excepción autorizada. El control corresponde al total del lote.', target: 'fisc', action: 'Revisar diferencia' });
  const counts = { blocked: findings.filter((f) => f.state === 'blocked').length, unchecked: findings.filter((f) => f.state === 'unchecked').length, warning: findings.filter((f) => f.state === 'warning').length };
  return { findings, counts };
}

export function submissionQualityPanel(data, role) {
  const { findings, counts } = buildSubmissionQuality(data, role);
  const formatCheckedAt = data.qualityCheckedAt ? dateTime(data.qualityCheckedAt) : 'Sin comprobación registrada';
  return html`<section class="sq-panel" id="submission-quality" aria-labelledby="sq-title">
    <header class="sq-header"><div><h2 id="sq-title">Control de calidad del lote</h2><p>Hallazgos por reclamación, par o lote. Una revisión registrada no equivale a un caso resuelto.</p></div><button type="button" class="btn" data-quality-refresh>Volver a comprobar</button></header>
    <div class="sq-status"><span><b>${counts.blocked}</b> requieren corrección</span><span><b>${counts.unchecked}</b> no comprobados</span><span><b>${counts.warning}</b> advertencias</span></div>
    <p class="sq-updated">Última consulta del control: ${formatCheckedAt}. Los permisos y validaciones finales del servidor siguen vigentes.</p>
    ${findings.length ? html`<div class="sq-findings">${findings.map((finding) => { const [label, tone] = stateLabels[finding.state]; return html`<article class="sq-finding" data-quality-state="${finding.state}"><div class="sq-scope"><span class="sq-scope-label">${finding.scope}</span><b>${finding.reference}</b></div><div class="sq-copy"><h3>${finding.title}</h3><p>${finding.detail}</p><span class="pill ${tone}">${label}</span></div><div class="sq-action">${finding.href ? html`<a class="btn sm" href="${finding.href}">${finding.action}</a>` : html`<button type="button" class="btn sm" data-quality-target="${finding.target}">${finding.action}</button>`}</div></article>`; })}</div>` : html`<p class="sq-empty">No se encontraron hallazgos en las comprobaciones cargadas. Esto no sustituye la validación final de radicación.</p>`}
  </section>`;
}
