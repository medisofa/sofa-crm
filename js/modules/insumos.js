/** SOFA · 3.7 · Iteración 47 · Insumos facturables.
 *  Hoja de consumo (en el celular), catálogo, salida de almacén (Excel o a mano) y cruce de tres vías del mes:
 *  despachado ↔ consumido ↔ reclamado a la ARS. */
import { rpc, h, money, num, note, guarded, kpi, clientOptions, clientName } from '../services/iter18.js';
import { readTable, excelDate, detectColumns } from '../utils/xlsx-lite.js';

const VERDICT = { fuga_facturacion: 'Fuga de facturación (recuperar)', fuga_inventario: 'Fuga de inventario (investigar)', no_facturable: 'No facturable (costear)', cuadra: 'Cuadra' };
const ALIASES = { codigo: ['codigo', 'cod', 'code', 'insumo', 'articulo'], fecha: ['fecha', 'date', 'dia'], cantidad: ['cantidad', 'cant', 'qty', 'unidades'], referencia: ['referencia', 'ref', 'documento', 'salida', 'vale'] };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const own = ['client', 'capturer'].includes(ctx.role);
  const seesCross = ['super_admin', 'admin', 'operations', 'glosas', 'auditor', 'client'].includes(ctx.role);
  const sel = h('select', { id: 'in-org' }, h('option', { value: '' }, 'Elija un cliente'));
  const tabs = h('div', { class: 'i18-bar', role: 'tablist' });
  const body = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Insumos facturables'),
    h('p', { class: 'i18-sub' }, 'El material que se usa en sala y nunca llega a la reclamación es dinero perdido. Registre el consumo y compare con lo despachado y lo reclamado.'),
    own ? null : h('div', { class: 'i18-bar' }, h('label', { for: 'in-org' }, 'Cliente', sel)), tabs, body));
  if (!own) { try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { body.replaceChildren(note(e.message, 'error')); } }
  const org = () => (own ? ctx.membership?.organization_id : sel.value);
  let current = 'consumo';
  const views = [['consumo', 'Hoja de consumo', consumo], ...(seesCross ? [['cruce', 'Cruce del mes', cruce]] : []), ['catalogo', 'Catálogo y almacén', catalogo]];
  views.forEach(([k, label, fn], i) => {
    const b = h('button', { class: `i18-btn ${i ? 'i18-sec' : ''}`, type: 'button', role: 'tab', id: `in-t-${k}` }, label);
    b.addEventListener('click', () => { current = k; tabs.querySelectorAll('button').forEach((x) => x.classList.add('i18-sec')); b.classList.remove('i18-sec'); fn(); });
    tabs.append(b);
  });
  sel.addEventListener('change', () => views.find((v) => v[0] === current)[2]());

  async function consumo() {
    if (!org()) { body.replaceChildren(note('Elija un cliente.')); return; }
    const d = await guarded(body, () => rpc('supply_catalog', { p_org: org() }));
    if (!d) return;
    const active = d.supplies.filter((s) => s.is_active);
    if (!active.length) { body.replaceChildren(note('Todavía no hay insumos en el catálogo. Agréguelos en «Catálogo y almacén».')); return; }
    const sup = h('select', { id: 'in-u-sup' }, active.map((s) => h('option', { value: s.id }, `${s.code} · ${s.name} (${s.unit})`)));
    const prov = h('select', { id: 'in-u-prov' }, h('option', { value: '' }, '—'), d.providers.map((p) => h('option', { value: p.id }, p.name)));
    const qty = h('input', { type: 'number', id: 'in-u-qty', min: '0', step: '1', value: '1', inputmode: 'decimal' });
    const day = h('input', { type: 'date', id: 'in-u-day', value: new Date().toISOString().slice(0, 10) });
    const pat = h('input', { type: 'text', id: 'in-u-pat', maxlength: '120' });
    const nt = h('input', { type: 'text', id: 'in-u-note', maxlength: '200', placeholder: 'Procedimiento' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Registrar consumo');
    const out = h('div', { 'aria-live': 'polite' });
    save.addEventListener('click', async () => {
      save.disabled = true; out.replaceChildren();
      try {
        await rpc('supply_usage_add', { p_org: org(), p_supply: sup.value, p_qty: Number(qty.value), p_used_on: day.value || null, p_provider: prov.value || null, p_patient: pat.value || null, p_note: nt.value || null });
        await consumo(); body.prepend(note('Consumo registrado.'));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    body.replaceChildren(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Nuevo consumo'), h('label', { for: 'in-u-sup' }, 'Insumo'), sup,
      h('label', { for: 'in-u-qty' }, 'Cantidad'), qty, h('label', { for: 'in-u-day' }, 'Fecha'), day, h('label', { for: 'in-u-prov' }, 'Médico'), prov,
      h('label', { for: 'in-u-pat' }, 'Paciente (opcional)'), pat, h('label', { for: 'in-u-note' }, 'Procedimiento (opcional)'), nt, h('div', {}, save), out),
      h('h3', {}, 'Últimos consumos'), d.recent.length ? table(['Fecha', 'Insumo', 'Cant.', 'Paciente', 'Médico', 'Registró'], d.recent.map((r) => [r.used_on, r.supply, num(r.quantity), r.patient || '—', r.provider || '—', r.by || '—']), [2]) : note('Sin consumos.'));
  }

  async function cruce() {
    if (!org()) { body.replaceChildren(note('Elija un cliente.')); return; }
    const m = h('input', { type: 'month', id: 'in-c-m', value: new Date().toISOString().slice(0, 7) });
    const out = h('div', { 'aria-live': 'polite' });
    const go = async () => {
      const d = await guarded(out, () => rpc('supply_reconciliation', { p_org: org(), p_month: `${m.value}-01` }));
      if (!d) return;
      const t = d.totals;
      out.replaceChildren(h('div', { class: 'i18-kpis' }, kpi('Fuga de facturación', money(t.unbilled), t.leak_pct == null ? '' : `${t.leak_pct} % de lo usado facturable · meta < 2 %`),
        kpi('Fuga de inventario (al costo)', money(t.inventory)), kpi('Consumo no facturable (costo)', money(t.nonbillable))),
        d.rows.length ? table(['Insumo', 'Despachado', 'Consumido', 'Reclamado', 'Sin reclamar', 'Monto a recuperar', 'Sin uso', 'Resultado'],
          d.rows.map((r) => [`${r.code} · ${r.name}${r.billable ? '' : ' (no facturable)'}`, num(r.dispatched), num(r.used), r.billable ? num(r.claimed) : '—', num(r.unbilled_qty), money(r.unbilled_amount),
            num(r.inventory_qty), h('span', { class: `in-v ${r.verdict}` }, VERDICT[r.verdict])]), [1, 2, 3, 4, 5, 6]) : note('Sin movimientos en el mes.'),
        h('p', { class: 'i18-sub' }, '«Reclamado» = cantidad del servicio enlazado al insumo en las reclamaciones del mes. El monto usa la tarifa vigente del cliente para ese servicio.'));
    };
    m.addEventListener('change', go);
    body.replaceChildren(h('div', { class: 'i18-bar' }, h('label', { for: 'in-c-m' }, 'Mes', m)), out);
    await go();
  }

  async function catalogo() {
    if (!org()) { body.replaceChildren(note('Elija un cliente.')); return; }
    const d = await guarded(body, () => rpc('supply_catalog', { p_org: org() }));
    if (!d) return;
    const list = d.supplies.length ? table(['Código', 'Insumo', 'Unidad', 'Costo', 'Facturable', 'Servicio con que se reclama', 'Activo'],
      d.supplies.map((s) => [s.code, s.name, s.unit, s.unit_cost == null ? '—' : money(s.unit_cost), s.billable ? 'Sí' : 'No', s.procedure || '—', s.is_active ? 'Sí' : 'No']), [3]) : note('Sin insumos.');
    if (!d.can_admin) { body.replaceChildren(list); return; }
    const code = h('input', { type: 'text', id: 'in-s-code', maxlength: '40' });
    const name = h('input', { type: 'text', id: 'in-s-name', maxlength: '160' });
    const unit = h('input', { type: 'text', id: 'in-s-unit', value: 'unidad', maxlength: '20' });
    const cost = h('input', { type: 'number', id: 'in-s-cost', min: '0', step: '0.01' });
    const bill = h('input', { type: 'checkbox', id: 'in-s-bill', checked: true });
    const proc = h('select', { id: 'in-s-proc' }, h('option', { value: '' }, '— elija —'));
    try { const { sb } = await import('../supabase.js'); const { data } = await sb().from('procedures').select('id, internal_code, description').eq('is_active', true).order('description').limit(2000); (data || []).forEach((p) => proc.append(h('option', { value: p.id }, `${p.internal_code} · ${p.description}`))); } catch (_) { /* lista opcional */ }
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Agregar insumo');
    const out = h('div', { 'aria-live': 'polite' });
    save.addEventListener('click', async () => {
      try { await rpc('supply_save', { p_org: org(), p_id: null, p_code: code.value, p_name: name.value, p_unit: unit.value, p_unit_cost: cost.value === '' ? null : Number(cost.value), p_billable: bill.checked, p_procedure: proc.value || null, p_active: true }); await catalogo(); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); }
    });
    const file = h('input', { type: 'file', id: 'in-x-file', accept: '.xlsx,.csv,.txt' });
    const chk = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Revisar archivo');
    const xout = h('div', { 'aria-live': 'polite' });
    chk.addEventListener('click', async () => {
      xout.replaceChildren();
      if (!file.files[0]) { xout.replaceChildren(note('Elija el archivo de salidas de almacén.', 'error')); return; }
      try {
        const t = await readTable(file.files[0]);
        let hi = -1; let map = null;
        for (let i = 0; i < Math.min(t.length, 15); i++) { const mm = detectColumns(t[i], ALIASES); if (mm.codigo != null && mm.cantidad != null && mm.fecha != null) { hi = i; map = mm; break; } }
        if (hi < 0) throw new Error('No se reconocieron las columnas. El archivo debe tener títulos «Código», «Fecha» y «Cantidad» (y opcional «Referencia»).');
        const g = (r, k) => (map[k] != null ? String(r[map[k]] ?? '').trim() : '');
        const rows = t.slice(hi + 1).filter((r) => r.some((c) => String(c ?? '').trim())).map((r) => ({ codigo: g(r, 'codigo'), fecha: excelDate(g(r, 'fecha')), cantidad: g(r, 'cantidad'), referencia: g(r, 'referencia') }));
        const rep = await rpc('supply_dispatch_import', { p_org: org(), p_rows: rows, p_commit: false, p_source: 'excel' });
        const go = h('button', { class: 'i18-btn', type: 'button', disabled: rep.errors.length > 0 || rep.ok === 0 }, `Guardar ${rep.ok} salida(s)`);
        go.addEventListener('click', async () => { try { const r = await rpc('supply_dispatch_import', { p_org: org(), p_rows: rows, p_commit: true, p_source: 'excel' }); xout.replaceChildren(note(`${r.ok} salida(s) guardadas.`)); } catch (e) { xout.replaceChildren(note(e.message, 'error')); } });
        xout.replaceChildren(note(`${rep.total} fila(s): ${rep.ok} listas, ${rep.duplicates} ya cargadas, ${rep.errors.length} con errores.`, rep.errors.length ? 'error' : 'info'),
          rep.errors.length ? h('ul', {}, rep.errors.slice(0, 30).map((e) => h('li', {}, `Fila ${e.row}: ${e.errors.join('; ')}`))) : null, go);
      } catch (e) { xout.replaceChildren(note(e.message, 'error')); }
    });
    body.replaceChildren(list, h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Agregar insumo'), h('label', { for: 'in-s-code' }, 'Código'), code,
      h('label', { for: 'in-s-name' }, 'Nombre'), name, h('label', { for: 'in-s-unit' }, 'Unidad'), unit, h('label', { for: 'in-s-cost' }, 'Costo unitario (RD$)'), cost,
      h('label', { class: 'i18-chk' }, bill, ' Se factura a la ARS'), h('label', { for: 'in-s-proc' }, 'Servicio del catálogo con que se reclama'), proc, h('div', {}, save), out),
      h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Salidas de almacén desde Excel o CSV'), h('p', { class: 'i18-sub' }, 'Columnas: Código, Fecha, Cantidad y (opcional) Referencia. Cargar el mismo archivo dos veces no duplica las salidas con referencia.'),
        file, h('div', {}, chk), xout));
  }

  const table = (head, rows, right = []) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x, i) => h('th', { class: right.includes(i) ? 'i18-r' : null }, x)))),
    h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x, i) => h('td', { class: right.includes(i) ? 'i18-r' : null }, x)))))));

  await consumo();
}
export default render;
