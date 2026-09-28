/** SOFA · Parámetros operativos (edita solo el Super Admin; la base de datos lo exige) */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, busy, fieldError } from '../utils/ui.js';
import { getSettings, updateSettings } from '../services/admin.js';
import { can } from '../utils/permissions.js';
import { money } from '../utils/formatters.js';

const FIELDS = [
  ['payment_term_days', 'Plazo de pago de las ARS (días)', 1, 365, 'Res. 00219-2017: 90 días desde la radicación.'],
  ['alert_days', 'Aviso antes del vencimiento (días)', 1, 90, 'Cuándo se alerta que un cobro está por vencer.'],
  ['appeal_days', 'Plazo interno para responder glosas (días)', 1, 90, 'Ajustar según contrato con cada ARS.'],
  ['submission_window_days', 'Ventana para radicar tras cerrar el período (días)', 1, 120, ''],
  ['target_mrr', 'Meta de ingreso mensual recurrente (RD$)', 0, 100000000, ''],
  ['target_billing_mix_pct', '% objetivo del ingreso en facturación médica', 0, 100, ''],
  ['founder_slots', 'Cupos de clientes fundadores', 0, 1000, '']
];

export async function render(main, ctx) {
  const editable = can('settings.edit', ctx.role);
  paint(main, html`<div class="page-head"><div class="t"><h2>Parámetros</h2><p>Plazos y metas que usan las alertas, el aging y el módulo de crecimiento.${editable ? '' : ' Solo lectura para tu rol.'}</p></div></div><div id="b"></div>`);
  const box = $('#b', main);
  const s = await loadInto(box, getSettings, (s) => html`<form class="card" id="f" novalidate>
      <div class="form-grid">${FIELDS.map(([k, l, min, max, hint]) => html`<div class="field"><label for="${k}">${l}</label><input id="${k}" name="${k}" type="number" min="${min}" max="${max}" step="${k.includes('pct') ? '0.01' : '1'}" value="${s[k]}" ${editable ? '' : 'disabled'}>${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`)}
        <div class="field"><label for="circular_deadline">Fecha límite de la Circular SSRL vigente</label><input id="circular_deadline" name="circular_deadline" type="date" value="${s.circular_deadline || ''}" ${editable ? '' : 'disabled'}></div></div>
      <p class="small muted">Meta actual: ${money(s.target_mrr)} al mes.</p>
      ${editable ? html`<button class="btn primary" type="submit">Guardar cambios</button>` : ''}</form>`,
  { isEmpty: (d) => !d, empty: () => emptyView('Sin parámetros', 'Ejecuta 005_seed_catalogs.sql.') });
  if (!s || !editable) return;
  $('#f', main).addEventListener('submit', async (e) => {
    e.preventDefault();
    const values = {}; let bad = false;
    FIELDS.forEach(([k, , min, max]) => {
      const inp = $(`#${k}`, main); const v = Number(inp.value);
      const err = inp.value === '' || Number.isNaN(v) || v < min || v > max ? `Debe estar entre ${min} y ${max}.` : null;
      fieldError(inp, err); if (err) bad = true; values[k] = v;
    });
    values.circular_deadline = $('#circular_deadline', main).value || null;
    if (bad) return;
    await busy(e.submitter, async () => {
      try { await updateSettings(s.operator_id, values); toast('Parámetros guardados', 'ok'); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });
}
