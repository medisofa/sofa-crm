/**
 * SOFA · Corregir una tarifa (error de carga) desde la reclamación. Solo Super Admin y Administrador.
 * Diferente de «Cambiar precio» (tariff-price-editor.js), que abre una versión nueva con vigencia futura:
 * aquí el monto se corrige en la misma tarifa y se recalculan las reclamaciones NO radicadas que la usan.
 * Toda la regla vive en la base (migración 266): public.tariff_correction_preview y public.tariff_correct.
 */
import { html, render as paint } from '../utils/dom.js';
import { formDialog, fieldError } from '../utils/ui.js';
import { money, date, num } from '../utils/formatters.js';
import { claimStatus } from '../utils/constants.js';
import { rpc } from '../services/iter18.js';
import { viewAsState } from '../utils/view-as-state.js';

const OUTCOME = {
  realinear: ['Pasa al monto nuevo', 'ok'],
  resuelta: ['Ya tenía ese monto: la diferencia se cierra', 'ok'],
  decision: ['Conserva su monto; queda diferencia pendiente', 'warn']
};

/** Frase que resume el efecto, en lenguaje de quien factura. */
export function effectSummary(counts) {
  if (!counts) return [];
  const lines = [];
  const total = counts.total - counts.sin_tocar;
  if (total > 0) lines.push(`Se recalculan ${num(total)} reclamación${total === 1 ? '' : 'es'} no radicada${total === 1 ? '' : 's'}${counts.clients > 1 ? ` de ${num(counts.clients)} clientes` : ''}.`);
  if (counts.realinear) lines.push(`${num(counts.realinear)} pasan al monto nuevo (su monto era igual a la tarifa anterior).`);
  if (counts.resuelta) lines.push(`${num(counts.resuelta)} ya estaban registradas con el monto nuevo: su diferencia pendiente se cierra.`);
  if (counts.decision) lines.push(`${num(counts.decision)} conservan su monto registrado y quedan con una diferencia pendiente para que Facturación la decida.`);
  if (counts.sin_tocar) lines.push(`${num(counts.sin_tocar)} ya radicada${counts.sin_tocar === 1 ? '' : 's'} o en cobro NO se tocan: siguen en la alerta «precio vencido».`);
  if (!lines.length) lines.push('Ninguna reclamación usa esta tarifa todavía: solo cambia el monto del contrato.');
  return lines;
}

export function correctTariffDialog(tariffId) {
  if (viewAsState.active) return Promise.resolve(false);
  let last = null; let seq = 0; let timer = null; let base = null;
  return formDialog({
    title: 'Corregir tarifa del contrato', submitLabel: 'Aplicar corrección', wide: true,
    body: html`<div class="tariff-correction">
      <div id="tc_ctx" aria-live="polite"><p class="small muted">Cargando la tarifa…</p></div>
      <div class="field"><label for="tc_amount">Monto correcto (RD$) *</label><input id="tc_amount" name="amount" type="number" min="0.01" step="0.01" inputmode="decimal" required></div>
      <div class="field"><label for="tc_reason">Motivo de la corrección (mín. 10 caracteres) *</label><textarea id="tc_reason" name="reason" rows="2" class="input" minlength="10" maxlength="1000" required placeholder="Ej.: El contrato con la ARS dice 850; se cargó 750 por error"></textarea></div>
      <div class="note info" id="tc_effect" role="status" aria-live="polite">Escriba el monto correcto para ver qué reclamaciones cambian.</div>
      <p class="small muted">Esto corrige un error de carga en la misma tarifa. Para un aumento con fecha futura use «Cambiar precio» en el tarifario. Las reclamaciones ya radicadas conservan su monto. Para deshacer, corrija de nuevo al monto anterior: las reclamaciones que se realinearon vuelven a él, pero una registrada a mano con el monto nuevo también se realinea.</p>
    </div>`,
    onOpen: async (form) => {
      const ctx = form.querySelector('#tc_ctx'); const effect = form.querySelector('#tc_effect'); const amount = form.querySelector('#tc_amount');
      const disable = (msg) => { paint(ctx, html`<div class="note bad">${msg}</div>`); form.querySelectorAll('input,textarea,[type=submit]').forEach((e) => { e.disabled = true; }); };
      const showContext = (r) => {
        const t = r.tariff;
        paint(ctx, html`<dl class="kv"><dt>Servicio</dt><dd><b>${t.service}</b></dd><dt>ARS</dt><dd>${t.ars}</dd>
          <dt>Alcance</dt><dd>${t.scope === 'general' ? html`<span class="pill warn">Tarifa general de la ARS</span> afecta a todos los clientes que la usan` : html`Contrato de ${t.provider || 'un médico'}`}</dd>
          <dt>Vigencia</dt><dd>${date(t.valid_from)} – ${t.valid_to ? date(t.valid_to) : 'abierta'}${t.contract_ref ? html` · contrato ${t.contract_ref}` : ''}</dd>
          <dt>Monto actual</dt><dd><b>${money(t.amount)}</b></dd></dl>
          ${r.history?.length ? html`<details><summary class="small">Correcciones anteriores (${r.history.length})</summary><ul class="small">${r.history.map((h) => html`<li>${date(h.at)} · ${money(h.old_amount)} → ${money(h.new_amount)} · ${h.by || 'Usuario'} · ${h.reason}</li>`)}</ul></details>` : ''}`);
      };
      try { base = await rpc('tariff_correction_preview', { p_tariff: tariffId, p_amount: null }); showContext(base); amount.value = Number(base.tariff.amount).toFixed(2); }
      catch (err) { disable(err.message || 'No se pudo cargar la tarifa.'); return; }
      const refresh = async () => {
        const v = Number(amount.value); const mine = ++seq; last = null;
        if (!amount.value || !Number.isFinite(v)) { paint(effect, html`Escriba el monto correcto para ver qué reclamaciones cambian.`); return; }
        paint(effect, html`Calculando el efecto…`);
        try {
          const r = await rpc('tariff_correction_preview', { p_tariff: tariffId, p_amount: v });
          if (mine !== seq) return;
          if (!r.valid) { paint(effect, html`<span class="bad">${r.message || 'Monto no válido.'}</span>`); return; }
          last = { amount: v, old_amount: r.tariff.amount, total: r.counts.total };
          const sinTocar = Object.entries(r.counts.sin_tocar_por_estado || {});
          paint(effect, html`<b>${money(r.tariff.amount)} → ${money(v)}</b>
            <ul>${effectSummary(r.counts).map((l) => html`<li>${l}</li>`)}</ul>
            ${r.sample?.length ? html`<div class="table-wrap"><table class="t"><thead><tr><th>Reclamación</th><th>Estado</th><th class="n">Registrado</th><th>Qué pasa</th></tr></thead><tbody>
              ${r.sample.map((s) => html`<tr><td class="mono">${s.folio}</td><td>${claimStatus(s.status)[0]}</td><td class="n">${money(s.unit_amount)}</td><td>${OUTCOME[s.outcome]?.[0] || s.outcome}</td></tr>`)}
            </tbody></table></div>${r.counts.total - r.counts.sin_tocar > r.sample.length ? html`<p class="small muted">Se muestran ${r.sample.length}; el cambio alcanza a todas las del alcance.</p>` : ''}` : ''}
            ${sinTocar.length ? html`<p class="small muted">Sin tocar: ${sinTocar.map(([s, n]) => `${num(n)} ${claimStatus(s)[0].toLowerCase()}`).join(', ')}.</p>` : ''}`);
        } catch (err) { if (mine === seq) paint(effect, html`<span class="bad">${err.message || 'No se pudo calcular el efecto.'}</span>`); }
      };
      amount.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(refresh, 350); });
    },
    onSubmit: async (data, form) => {
      if (viewAsState.active) throw new Error('El modo soporte es de solo lectura.');
      const amount = Number(data.amount); const reason = String(data.reason || '').trim();
      let ok = true;
      const checks = [['amount', Number.isFinite(amount) && amount > 0, 'Indique un monto mayor que cero.'],
        ['amount', !last || Math.abs(amount - Number(base?.tariff?.amount)) >= 0.005, 'Es el monto actual. Escriba un importe diferente.'],
        ['reason', reason.length >= 10, 'Indique el motivo (mínimo 10 caracteres).']];
      for (const [name, pass, message] of checks) { if (!pass) { fieldError(form.elements[name], message); ok = false; break; } fieldError(form.elements[name], ''); }
      if (!ok) return false;
      if (!last || last.amount !== amount) { fieldError(form.elements.amount, 'Espere a que se muestre el efecto de este monto antes de aplicar.'); return false; }
      return rpc('tariff_correct', { p_tariff: tariffId, p_amount: amount, p_reason: reason, p_expected: { old_amount: last.old_amount, total: last.total } });
    }
  });
}
