/** SOFA · Parámetros operativos (edita solo el Super Admin; la base de datos lo exige) */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, busy, fieldError } from '../utils/ui.js';
import { getSettings, updateSettings } from '../services/admin.js';
import { can } from '../utils/permissions.js';
import { money } from '../utils/formatters.js';
import { operatorProfile, updateOperatorProfile } from '../services/finance.js';

const FIELDS = [
  ['payment_term_days', 'Plazo de pago de las ARS (días)', 1, 365, 'Res. 00219-2017: 90 días desde la radicación.'],
  ['alert_days', 'Aviso antes del vencimiento (días)', 1, 90, 'Cuándo se alerta que un cobro está por vencer.'],
  ['appeal_days', 'Plazo interno para responder glosas (días)', 1, 90, 'Ajustar según contrato con cada ARS.'],
  ['submission_window_days', 'Ventana para radicar tras cerrar el período (días)', 1, 120, ''],
  ['target_mrr', 'Meta de ingreso mensual recurrente (RD$)', 0, 100000000, ''],
  ['target_billing_mix_pct', '% objetivo del ingreso en facturación médica', 0, 100, ''],
  ['founder_slots', 'Cupos de clientes fundadores', 0, 1000, ''],
  ['payment_gap_days', 'Alerta de pago incompleto (días sin pagos nuevos)', 5, 180, 'Iteración 14: "Trabajo de hoy" avisa cuando una reclamación con pago parcial lleva más de estos días sin pagos nuevos.'],
  ['validation_alert_days', 'Alerta de reclamación retirada sin validar (días)', 1, 60, 'Iteración 13: "Trabajo de hoy" avisa cuando una reclamación retirada lleva más de estos días sin auditar.'],
  ['pickup_alert_days', 'Alerta de reclamación sin retirar (días)', 1, 60, 'Iteración 12: "Trabajo de hoy" avisa cuando una reclamación capturada lleva más de estos días en el consultorio.']
];

export async function render(main, ctx) {
  const editable = can('settings.edit', ctx.role);
  paint(main, html`<div class="page-head"><div class="t"><h2>Parámetros</h2><p>Plazos y metas que usan las alertas, el aging y el módulo de crecimiento.${editable ? '' : ' Solo lectura para tu rol.'}</p></div></div><div id="b"></div><div id="op" style="margin-top:14px"></div>`);
  drawOperator(main, editable);
  const box = $('#b', main);
  const s = await loadInto(box, getSettings, (s) => html`<form class="card" id="f" novalidate>
      <div class="form-grid">${FIELDS.filter(([k]) => k in s).map(([k, l, min, max, hint]) => html`<div class="field"><label for="${k}">${l}</label><input id="${k}" name="${k}" type="number" min="${min}" max="${max}" step="${k.includes('pct') ? '0.01' : '1'}" value="${s[k]}" ${editable ? '' : 'disabled'}>${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`)}
        <div class="field"><label for="circular_deadline">Fecha límite de la Circular SSRL vigente</label><input id="circular_deadline" name="circular_deadline" type="date" value="${s.circular_deadline || ''}" ${editable ? '' : 'disabled'}></div></div>
      <h3 style="margin-top:18px">Reclamaciones y radicación (Iteración 12)</h3>
      <label class="check"><input type="checkbox" id="require_claim_audit" ${s.require_claim_audit ? 'checked' : ''} ${editable ? '' : 'disabled'}> Exigir que cada reclamación esté <b>validada por el Auditor</b> antes de pasar el lote a “Lista para radicar” (D5)</label>
      <label class="check"><input type="checkbox" id="require_delivery_evidence" ${s.require_delivery_evidence ? 'checked' : ''} ${editable ? '' : 'disabled'}> Exigir <b>evidencia de entrega</b> (acuse o comprobante de la ARS) para marcar una radicación como Radicada</label>
      <p class="small">Diferencia entre reclamaciones y factura fiscal: <b>${s.fiscal_mismatch_mode === 'advertir' ? 'Solo advertir (configurado por SQL)' : 'Bloquear la radicación'}</b>. Solo un administrador autoriza una excepción, con motivo y bitácora (D2).</p>
      <p class="small muted">Meta actual: ${money(s.target_mrr)} al mes.</p>
      ${editable ? html`<button class="btn primary" type="submit">Guardar cambios</button>` : ''}</form>`,
  { isEmpty: (d) => !d, empty: () => emptyView('Sin parámetros', 'Ejecuta 005_seed_catalogs.sql.') });
  if (!s || !editable) return;
  $('#f', main).addEventListener('submit', async (e) => {
    e.preventDefault();
    const values = {}; let bad = false;
    FIELDS.filter(([k]) => k in s).forEach(([k, , min, max]) => {
      const inp = $(`#${k}`, main); const v = Number(inp.value);
      const err = inp.value === '' || Number.isNaN(v) || v < min || v > max ? `Debe estar entre ${min} y ${max}.` : null;
      fieldError(inp, err); if (err) bad = true; values[k] = v;
    });
    values.circular_deadline = $('#circular_deadline', main).value || null;
    if ('require_claim_audit' in s) { values.require_claim_audit = $('#require_claim_audit', main).checked; values.require_delivery_evidence = $('#require_delivery_evidence', main).checked; }
    if (bad) return;
    await busy(e.submitter, async () => {
      try { await updateSettings(s.operator_id, values); toast('Parámetros guardados', 'ok'); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });
}

/** 1.4.1 · Datos fiscales de SOFA (emisor de las facturas de honorarios). Solo el Super Admin los edita. */
async function drawOperator(main, editable) {
  const box = $('#op', main); if (!box) return;
  let o;
  try { o = await operatorProfile(); } catch { return; }
  if (!o || !document.body.contains(box)) return;
  const f = (k, label, extra = '') => html`<div class="field"><label for="op_${k}">${label}</label><input id="op_${k}" name="${k}" value="${o[k] || ''}" ${editable ? '' : 'disabled'} ${extra}></div>`;
  paint(box, html`<form class="card" id="opf" novalidate><h2>Datos fiscales de SOFA</h2>
    <p class="sub">Aparecen como emisor en las facturas de honorarios.${o.tax_id ? '' : ' <b>Falta el RNC.</b>'}</p>
    <div class="form-grid">${f('legal_name', 'Razón social *', 'maxlength="150"')}${f('trade_name', 'Nombre comercial', 'maxlength="80"')}${f('tax_id', 'RNC', 'maxlength="13" inputmode="numeric"')}
      ${f('address', 'Dirección', 'maxlength="200"')}${f('city', 'Ciudad', 'maxlength="60"')}${f('phone', 'Teléfono', 'maxlength="20"')}${f('email', 'Correo de facturación', 'type="email" maxlength="120"')}</div>
    <h3 class="small" style="margin-top:12px">Forma de pago que sale en la factura</h3>
    <div class="form-grid">${f('bank_name', 'Banco', 'maxlength="60" placeholder="Banco Popular Dominicano"')}
      <div class="field"><label for="op_bank_account_type">Tipo de cuenta</label><select id="op_bank_account_type" name="bank_account_type" ${editable ? '' : 'disabled'}>
        ${['', 'Corriente', 'Ahorros'].map((t) => html`<option value="${t}" ${o.bank_account_type === t ? 'selected' : ''}>${t || 'Seleccione…'}</option>`)}</select></div>
      ${f('bank_account', 'Número de cuenta', 'maxlength="24" inputmode="numeric"')}${f('bank_holder', 'A nombre de', 'maxlength="120"')}</div>
    <div class="field"><label for="op_terms">Condiciones de pago</label><textarea id="op_terms" name="terms" rows="2" class="input" maxlength="400" ${editable ? '' : 'disabled'}>${o.terms || ''}</textarea></div>
    ${editable ? html`<div><button class="btn primary" type="submit">Guardar datos fiscales</button></div>` : ''}</form>`);
  $('#opf', box).addEventListener('submit', (e) => {
    e.preventDefault(); const form = e.target; const v = Object.fromEntries(new FormData(form).entries());
    if ((v.legal_name || '').trim().length < 3) { fieldError(form.elements.legal_name, 'Indique la razón social'); return; }
    const tax = (v.tax_id || '').replace(/\D/g, '');
    if (tax && !/^(\d{9}|\d{11})$/.test(tax)) { fieldError(form.elements.tax_id, 'RNC de 9 dígitos o cédula de 11'); return; }
    const acc = (v.bank_account || '').replace(/[\s-]/g, '');
    if (acc && !/^\d{6,20}$/.test(acc)) { fieldError(form.elements.bank_account, 'Solo dígitos (6 a 20)'); return; }
    busy(e.submitter, async () => { try { await updateOperatorProfile(v); toast('Datos fiscales de SOFA guardados', 'ok'); } catch (err) { toast(friendlyError(err), 'bad'); } });
  });
}
