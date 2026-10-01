/** SOFA · Diálogos de reclamaciones: mover de estado, auditar (D5), decidir diferencia tarifaria y ajustar reparto de pago (D4) */
import { html } from '../utils/dom.js';
import { formDialog, opt, fieldError } from '../utils/ui.js';
import { money, num } from '../utils/formatters.js';
import { claimStatus, CLAIM_MOVE_LABELS } from '../utils/constants.js';
import { changeClaimStatus, auditClaims, decideDiscrepancy, adjustDistribution, resubmitClaims } from '../services/claims.js';

const field = (id, label, input, hint = '') => html`<div class="field"><label for="${id}">${label}</label>${input}${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`;

/**
 * Mover una o varias reclamaciones a otro estado registrando ubicación, responsable y observación.
 * Si la transición no está permitida, un administrador puede forzarla con motivo (queda como EXCEPCIÓN).
 */
export function moveDialog(ids, to, { role, transitions = [], locations = [], count = ids.length, from = null } = {}) {
  const tr = transitions.find((t) => t.to_code === to && (!from || t.from_code === from));
  const allowed = !from || (tr && tr.allowed_roles.includes(role));
  const needsOverride = !allowed;
  const defLoc = tr?.default_location || '';
  return formDialog({
    title: `${CLAIM_MOVE_LABELS[to] || claimStatus(to)[0]} · ${num(count)} reclamación${count === 1 ? '' : 'es'}`, submitLabel: 'Confirmar',
    body: html`<div class="form-grid">
      ${field('mv_loc', 'Ubicación física después del cambio', html`<select id="mv_loc" name="location"><option value="">Sin cambio</option>${locations.map((l) => opt(l.code, l.name, defLoc))}</select>`)}
      ${field('mv_cus', 'Responsable (quién la tiene)', html`<input id="mv_cus" name="custodian" maxlength="120" placeholder="Nombre del mensajero, auditor, etc.">`, 'Si lo deja vacío, queda como responsable su usuario.')}
      <div class="field" style="grid-column:1/-1"><label for="mv_c">Observación${to === 'devuelta' ? ' *' : ''}</label><textarea id="mv_c" name="comment" rows="2" class="input" maxlength="500"></textarea></div>
      ${needsOverride ? html`<div class="field" style="grid-column:1/-1"><div class="note warn">Esta transición no es la secuencia normal del proceso. Solo un administrador puede autorizarla y quedará registrada como <b>EXCEPCIÓN</b>.</div>
        <label for="mv_o">Motivo de la excepción (mín. 10 caracteres) *</label><textarea id="mv_o" name="override" rows="2" class="input"></textarea></div>` : ''}</div>`,
    onSubmit: async (d, form) => {
      if (to === 'devuelta' && (d.comment || '').trim().length < 5) { fieldError(form.elements.comment, 'Indique qué devolvió la ARS'); return false; }
      if (needsOverride && (d.override || '').trim().length < 10) { fieldError(form.elements.override, 'Mínimo 10 caracteres'); return false; }
      return changeClaimStatus(ids, to, { comment: d.comment?.trim() || null, location: d.location || null, custodian: d.custodian?.trim() || null, override: needsOverride ? d.override.trim() : null });
    }
  });
}

/** Auditoría del expediente (D5): resultado, observaciones, errores, documentos faltantes y correcciones solicitadas */
export function auditDialog(ids, { missing = [] } = {}) {
  return formDialog({
    title: `Auditar expediente · ${num(ids.length)} reclamación${ids.length === 1 ? '' : 'es'}`, submitLabel: 'Registrar auditoría', wide: true,
    body: html`<div class="form-grid">
      ${field('au_r', 'Resultado *', html`<select id="au_r" name="result">${opt('validada', 'Validada: expediente correcto', 'validada')}${opt('con_inconsistencia', 'Con inconsistencia: requiere corrección')}</select>`)}
      <div class="field" style="grid-column:1/-1"><label for="au_o">Observaciones</label><textarea id="au_o" name="observations" rows="2" class="input" maxlength="1000"></textarea></div>
      <div class="field" style="grid-column:1/-1"><label for="au_e">Errores detectados (uno por línea)</label><textarea id="au_e" name="errors" rows="3" class="input" placeholder="Autorización vencida&#10;NSS no coincide con la cédula"></textarea></div>
      <div class="field" style="grid-column:1/-1"><label for="au_m">Documentos faltantes (uno por línea)</label><textarea id="au_m" name="missing" rows="2" class="input">${missing.join('\n')}</textarea></div>
      <div class="field" style="grid-column:1/-1"><label for="au_c">Correcciones solicitadas</label><textarea id="au_c" name="corrections" rows="2" class="input" maxlength="1000"></textarea></div></div>
      <p class="small muted">Queda registrado con su usuario, fecha y hora. “Validada” exige que el sistema no detecte errores críticos (contrato, tarifa, NSS, autorización, códigos, documentos, duplicados).</p>`,
    onSubmit: async (d, form) => {
      const lines = (s) => String(s || '').split('\n').map((x) => x.trim()).filter(Boolean);
      const errors = lines(d.errors); const miss = lines(d.missing);
      if (d.result === 'con_inconsistencia' && !errors.length && !miss.length && (d.observations || '').trim().length < 5) {
        fieldError(form.elements.errors, 'Indique al menos un error, un documento faltante o una observación'); return false;
      }
      return auditClaims(ids, { result: d.result, observations: d.observations?.trim() || null, errors, missing: miss, corrections: d.corrections?.trim() || null });
    }
  });
}

/** Autorizar o rechazar una diferencia tarifaria pendiente */
export function decideDialog(disc) {
  return formDialog({
    title: 'Diferencia tarifaria', submitLabel: 'Registrar decisión',
    body: html`<dl class="kv"><dt>Tarifa contractual</dt><dd>${money(disc.tariff_amount)}</dd><dt>Monto registrado</dt><dd>${money(disc.registered_amount)}</dd>
        <dt>Diferencia</dt><dd><b>${money(disc.diff_amount)}</b> (${disc.diff_pct ?? '—'} %)</dd><dt>Motivo de quien registró</dt><dd>${disc.reason || '—'}</dd></dl>
      ${field('dd_a', 'Decisión *', html`<select id="dd_a" name="approve">${opt('1', 'Autorizar la diferencia', '1')}${opt('0', 'Rechazar: corregir al monto contractual')}</select>`)}
      ${field('dd_n', 'Nota de la decisión (mín. 5 caracteres) *', html`<textarea id="dd_n" name="note" rows="2" class="input"></textarea>`)}`,
    onSubmit: async (d, form) => {
      if ((d.note || '').trim().length < 5) { fieldError(form.elements.note, 'Mínimo 5 caracteres'); return false; }
      await decideDiscrepancy(disc.id, d.approve === '1', d.note.trim()); return true;
    }
  });
}

/**
 * Ajuste manual del reparto de un pago aplicado a una radicación (D4).
 * current: [{ service_line_id, amount, folio, patient, claimed }] del reparto vigente. La suma debe ser exacta.
 */
export function adjustDialog(allocation, current) {
  const total = Number(allocation.amount);
  return formDialog({
    title: `Ajustar reparto del pago ${money(total)}`, submitLabel: 'Guardar ajuste', wide: true,
    body: html`<p class="small">El reparto automático fue proporcional al monto reclamado. Ajuste por reclamación: la suma debe ser exactamente ${money(total)}. El cálculo anterior se conserva en el historial.</p>
      <div class="table-wrap"><table class="t"><thead><tr><th>Reclamación</th><th class="n">Reclamado</th><th class="n">Actual</th><th class="n">Nuevo</th></tr></thead><tbody>
      ${current.map((c, i) => html`<tr><td><span class="mono">${c.folio}</span> · ${c.patient}</td><td class="n">${money(c.claimed)}</td><td class="n">${money(c.amount)}</td>
        <td class="n"><label class="sr-only" for="aj_${i}">Nuevo monto ${c.folio}</label><input id="aj_${i}" name="a_${c.service_line_id}" type="number" step="0.01" min="0" value="${Number(c.amount).toFixed(2)}" style="width:130px;text-align:right"></td></tr>`)}
      </tbody></table></div>
      <p id="aj_sum" class="small" aria-live="polite"></p>
      ${field('aj_r', 'Motivo del ajuste (mín. 10 caracteres) *', html`<textarea id="aj_r" name="reason" rows="2" class="input" placeholder="La ARS detalló el pago por paciente en su relación de pago"></textarea>`)}`,
    onOpen: (form) => {
      const sum = () => { const s = current.reduce((t, c) => t + Number(form.elements[`a_${c.service_line_id}`].value || 0), 0);
        const d = Math.round((s - total) * 100) / 100;
        form.querySelector('#aj_sum').innerHTML = `Suma: <b>${money(s)}</b> · ${d === 0 ? '<span style="color:var(--ok)">cuadra con el pago</span>' : `<span style="color:var(--bad)">diferencia ${money(d)}</span>`}`; };
      form.addEventListener('input', sum); sum();
    },
    onSubmit: async (d, form) => {
      const items = current.map((c) => ({ service_line_id: c.service_line_id, amount: Number(d[`a_${c.service_line_id}`] || 0) }));
      const s = items.reduce((t, i) => t + i.amount, 0);
      if (Math.abs(s - total) > 0.005) { fieldError(form.elements.reason, `La suma (${money(s)}) debe ser ${money(total)}`); return false; }
      if ((d.reason || '').trim().length < 10) { fieldError(form.elements.reason, 'Mínimo 10 caracteres'); return false; }
      return adjustDistribution(allocation.id, items, d.reason.trim());
    }
  });
}

/** Iteración 14 · Reenviar reclamaciones devueltas en una radicación complementaria (devuelve el id del lote nuevo) */
export function resubmitDialog(ids, fromFolio = '') {
  return formDialog({
    title: `Reenviar ${num(ids.length)} reclamación${ids.length === 1 ? '' : 'es'} devuelta${ids.length === 1 ? '' : 's'}`, submitLabel: 'Crear radicación complementaria',
    body: html`<p class="small">Se crea un lote nuevo${fromFolio ? html` vinculado a <b class="mono">${fromFolio}</b>` : ''} (mismo médico, ARS y período) y la reclamación pasa a él conservando su folio, monto y tarifa. Vuelve a auditarse antes de radicar. El lote complementario no cobra otra vez el honorario por radicación.</p>
      ${field('rs_r', 'Motivo de la devolución y corrección realizada (mín. 10 caracteres) *', html`<textarea id="rs_r" name="reason" rows="3" class="input" placeholder="La ARS devolvió por falta de firma del médico; ya firmada"></textarea>`)}`,
    onSubmit: async (d, form) => {
      if ((d.reason || '').trim().length < 10) { fieldError(form.elements.reason, 'Mínimo 10 caracteres'); return false; }
      return resubmitClaims(ids, d.reason.trim());
    }
  });
}
