/** Cambiar un precio conserva la tarifa anterior y las reclamaciones registradas. */
import { html, render as paint } from '../utils/dom.js';
import { formDialog, fieldError } from '../utils/ui.js';
import { money, date, todayISO } from '../utils/formatters.js';
import { rpc } from '../services/iter18.js';
import { viewAsState } from '../utils/view-as-state.js';

const normalized = (value) => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().replace(/\s+/g, ' ').toUpperCase();
export function isAmbulatoryConsultation(row) {
  const code = normalized(row.internal_code);
  return code ? code === 'SOFA-P07' : normalized(row.service_name || row.name || row.description) === 'CONSULTA AMBULATORIA';
}
export function priceEffectiveMinimum(row, today = todayISO()) {
  const start = new Date(`${String(row.valid_from || '').slice(0, 10)}T00:00:00Z`);
  const next = Number.isNaN(start.getTime()) ? today : new Date(start.getTime() + 86400000).toISOString().slice(0, 10);
  return next > today ? next : today;
}
export function initialTariffPrice(row) {
  const currency = row.currency || 'DOP';
  const current = Number(row.amount);
  if (Number.isFinite(current) && current > 0) return current;
  return isAmbulatoryConsultation(row) && currency === 'DOP' ? 750 : 0;
}
export function formatTariffAmount(amount, currency = 'DOP') {
  if (currency === 'DOP') return money(amount);
  try { return new Intl.NumberFormat('es-DO', { style: 'currency', currency }).format(Number(amount)); }
  catch (_) { return `${Number(amount).toFixed(2)} ${currency}`; }
}

export function editTariffPrice(row, { readOnly = false, onSave } = {}) {
  if (readOnly || viewAsState.active) return Promise.resolve(false);
  const currency = row.currency || 'DOP';
  const display = (n) => formatTariffAmount(n, currency);
  const minimum = priceEffectiveMinimum(row);
  return formDialog({
    title: 'Cambiar precio', submitLabel: 'Guardar nuevo precio', wide: true,
    body: html`<div class="tariff-price-editor">
      <p class="tariff-price-context"><b>${row.service_name}</b><br>${row.provider_name} · ${row.ars_name}<br>Plan ${row.plan_name || (row.plan_id ? 'específico' : 'General')}</p>
      <dl class="kv"><dt>Precio actual</dt><dd><b>${display(row.amount)}</b></dd><dt>Vigente desde</dt><dd>${date(row.valid_from)}</dd></dl>
      <div class="tariff-price-grid">
        <div class="field"><label for="te_amount">Nuevo precio (${currency === 'DOP' ? 'RD$' : currency}) *</label><input id="te_amount" name="amount" type="number" min="0.01" step="0.01" inputmode="decimal" value="${initialTariffPrice(row).toFixed(2)}" required></div>
        <div class="field"><label for="te_effective">Fecha de efecto *</label><input id="te_effective" name="effective" type="date" value="${minimum}" min="${minimum}" required><span class="hint">Desde ${date(minimum)}. Se conserva la vigencia anterior.</span></div>
        <div class="field"><label for="te_reason">Motivo del cambio *</label><textarea id="te_reason" name="reason" rows="2" minlength="10" maxlength="300" required placeholder="Indica por qué cambia el precio (mínimo 10 caracteres)"></textarea></div>
      </div>
      <div class="note info tariff-price-summary" id="te_summary" role="status"></div>
      <p class="small muted">Este cambio se aplica solo a la tarifa seleccionada. El historial y los importes de las reclamaciones ya registradas se conservan.</p>
    </div>`,
    onOpen: (form) => {
      const amount = form.querySelector('#te_amount'); const effect = form.querySelector('#te_effective'); const summary = form.querySelector('#te_summary');
      const update = () => paint(summary, html`Precio actual ${display(row.amount)} → nuevo ${amount.value && Number(amount.value) > 0 ? display(amount.value) : 'por indicar'} · desde ${effect.value ? date(effect.value) : 'fecha por indicar'}.`);
      amount.addEventListener('input', update); effect.addEventListener('change', update); update();
    },
    onSubmit: async (data, form) => {
      if (readOnly || viewAsState.active) throw new Error('El modo soporte es de solo lectura.');
      let valid = true; const amount = Number(data.amount); const reason = String(data.reason || '').trim();
      const checks = [['amount', Number.isFinite(amount) && amount > 0, 'Indica un precio mayor que cero.'],
        ['effective', /^\d{4}-\d{2}-\d{2}$/.test(data.effective || '') && data.effective >= minimum, `La fecha debe ser ${date(minimum)} o posterior.`],
        ['reason', reason.length >= 10, 'Indica el motivo (mínimo 10 caracteres).']];
      for (const [name, ok, message] of checks) { fieldError(form.elements[name], ok ? '' : message); if (!ok) valid = false; }
      if (!valid) return false;
      if (Math.abs(amount - Number(row.amount)) < .005) { fieldError(form.elements.amount, 'Es el precio actual. Escribe un importe diferente.'); return false; }
      const values = { tariffId: row.id, amount, effective: data.effective, reason };
      return onSave ? onSave(values) : rpc('change_contract_tariff_price', { p_tariff: row.id, p_amount: amount, p_effective: data.effective, p_reason: reason });
    }
  });
}
