/** SOFA · 4.8.0 · P2 · Suscripciones (Administración): tablero de estados, pre-facturas, pago manual con referencia y aplicar atraso.
 *  Solo Super Admin y Administrador. El servidor vuelve a verificar el rol en cada función; ocultar el menú no es un control.
 *  La pre-factura es un documento interno NO fiscal: el comprobante fiscal (e-CF) se emite fuera de SOFA y aquí solo se anota su número. */
import { rpc, h, money, fmtDate, note, kpi, guarded, todayIso, table } from '../services/iter18.js';
import { pill, invoiceDetail } from './suscripcion.js';

const STATE_ORDER = ['prueba', 'activa', 'pendiente_pago', 'solo_lectura', 'suspendida', 'cancelada', 'sin_suscripcion'];
const STATE_LABEL = { prueba: 'En prueba', activa: 'Activas', pendiente_pago: 'Pendiente de pago', solo_lectura: 'Solo lectura', suspendida: 'Suspendidas', cancelada: 'Canceladas', sin_suscripcion: 'Sin suscripción' };
const LEVEL = { ninguno: '—', aviso: 'Aviso (día 1)', aviso_app: 'Aviso en la app (día 10)', solo_lectura: 'Solo lectura (día 20)', suspension: 'Suspensión (día 60)' };
const INV = { borrador: 'Borrador', emitida_externa: 'Emitida', pagada: 'Pagada', vencida: 'Vencida' };
const KIND = { alta: 'Primera cuota', mensual: 'Mensual', anual: 'Anual', cambio_plan: 'Cambio de plan' };
const EXPORT_NEXT = { solicitada: ['en_preparacion', 'lista', 'entregada'], en_preparacion: ['lista', 'entregada'], lista: ['entregada'] };
const METHODS = ['transferencia', 'deposito', 'efectivo', 'cheque', 'tarjeta', 'otro'];

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const acts = h('div', { 'aria-live': 'polite' });
  const list = h('div', { 'aria-live': 'polite' });
  const panel = h('div', { 'aria-live': 'polite' });
  const detail = h('div', { 'aria-live': 'polite' });
  const gmsg = h('div', { id: 'su-msg', 'aria-live': 'polite' });   // mensajes de las acciones: fuera de lo que se vuelve a dibujar
  const cfg = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap su-wrap' }, h('h2', {}, 'Suscripciones y pre-facturas'),
    h('p', { class: 'i18-sub' }, 'Estado de cada cliente, pre-facturas (documento interno, NO fiscal), pagos manuales y el calendario de atraso. Nunca se borran datos.'),
    top, acts, gmsg, list, panel, detail, h('h3', {}, 'Parámetros y descuento por volumen'), cfg));
  let ov = null; let plans = []; let sel = null;

  async function load() {
    ov = await guarded(list, () => rpc('sub_overview'));
    if (!ov) return;
    try { plans = (await rpc('plans_overview')).plans.filter((p) => p.is_active); } catch (_) { plans = []; }
    renderTop(); renderActions(); renderList(); renderConfig();
    if (sel) await openClient(sel);
  }

  function renderTop() {
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Aplicar atraso hoy');
    const out = h('div', { 'aria-live': 'polite' });
    go.addEventListener('click', async () => {
      go.disabled = true; out.replaceChildren();
      try {
        const r = await rpc('sub_apply_overdue');
        await load();
        const o = document.getElementById('su-apply-out');
        if (o) o.replaceChildren(note(`Atraso aplicado al ${fmtDate(r.al)}: ${r.cambios.length} cliente(s) cambiaron de estado, ${r.borradores_generados} borrador(es) de pre-factura generados.`, 'ok'));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    top.replaceChildren(h('div', { class: 'i18-kpis' }, STATE_ORDER.map((k) => kpi(STATE_LABEL[k], String(ov.counts[k] || 0))),
      kpi('Bloqueo por plan', ov.enforced ? 'ACTIVO' : 'Apagado', ov.enforced ? 'Solo lectura y suspensión se aplican' : 'Los estados se calculan, pero nada se bloquea')),
      h('div', { class: 'i18-actions' }, go), out, h('div', { id: 'su-apply-out', 'aria-live': 'polite' }));
  }

  function field(id, label, el) { return h('label', { for: id }, label, el); }
  function clientSelect(id) { return h('select', { id }, h('option', { value: '' }, 'Elija un cliente…'), ov.clients.map((c) => h('option', { value: c.organization_id }, c.name))); }
  function planSelect(id, withNone) { return h('select', { id }, h('option', { value: '' }, withNone ? 'Sin cambiar de plan' : 'Elija un plan…'), plans.map((p) => h('option', { value: p.code }, p.name))); }

  function renderActions() {
    const msg = gmsg;
    const run = async (btn, fn) => {
      btn.disabled = true; msg.replaceChildren();
      try { const r = await fn(); await load(); msg.replaceChildren(note(r?.message || 'Listo.', 'ok')); } catch (e) { msg.replaceChildren(note(e.message, 'error')); } finally { btn.disabled = false; }
    };
    // Prueba
    const tOrg = clientSelect('su-t-org'); const tPlan = planSelect('su-t-plan', true); const tWhy = h('input', { id: 'su-t-why', type: 'text', maxlength: '300', placeholder: 'Nota (opcional)' });
    const tGo = h('button', { class: 'i18-btn', type: 'button' }, 'Iniciar prueba');
    tGo.addEventListener('click', () => run(tGo, () => rpc('sub_start_trial', { p_org: tOrg.value || null, p_plan: tPlan.value || null, p_note: tWhy.value || null })));
    // Contratar
    const cOrg = clientSelect('su-c-org'); const cPlan = planSelect('su-c-plan'); const cCycle = h('select', { id: 'su-c-cycle' }, h('option', { value: 'mensual' }, 'Mensual'), h('option', { value: 'anual' }, 'Anual'));
    const cSince = h('input', { id: 'su-c-since', type: 'date', value: todayIso() }); const cFnd = h('input', { id: 'su-c-fnd', type: 'checkbox' });
    const cWhy = h('input', { id: 'su-c-why', type: 'text', maxlength: '300', placeholder: 'Condiciones de la contratación (mínimo 10 caracteres)' });
    const cGo = h('button', { class: 'i18-btn', type: 'button' }, 'Contratar y generar la primera pre-factura');
    cGo.addEventListener('click', () => run(cGo, async () => {
      const r = await rpc('sub_contract', { p_org: cOrg.value || null, p_plan: cPlan.value || null, p_cycle: cCycle.value, p_start: cSince.value || null, p_founder: cFnd.checked, p_note: cWhy.value });
      sel = cOrg.value; return r;
    }));
    // Cambiar plan
    const pOrg = clientSelect('su-p-org'); const pPlan = planSelect('su-p-plan'); const pFnd = h('input', { id: 'su-p-fnd', type: 'checkbox' });
    const pWhy = h('input', { id: 'su-p-why', type: 'text', maxlength: '300', placeholder: 'Motivo del cambio (mínimo 10 caracteres)' });
    const pGo = h('button', { class: 'i18-btn', type: 'button' }, 'Cambiar plan');
    pGo.addEventListener('click', () => run(pGo, async () => { const r = await rpc('sub_change_plan', { p_org: pOrg.value || null, p_plan: pPlan.value || null, p_note: pWhy.value, p_founder: pFnd.checked }); sel = pOrg.value; return r; }));
    // Generar pre-factura
    const gOrg = clientSelect('su-g-org'); const gMonth = h('input', { id: 'su-g-from', type: 'date', title: 'Primer día del período (vacío: el próximo)' });
    const gGo = h('button', { class: 'i18-btn', type: 'button' }, 'Generar pre-factura (borrador)');
    gGo.addEventListener('click', () => run(gGo, async () => { await rpc('sub_invoice_generate', { p_org: gOrg.value || null, p_period_start: gMonth.value || null, p_note: null }); sel = gOrg.value; return { message: 'Pre-factura generada en borrador. Revísela y emítala.' }; }));
    acts.replaceChildren(
      h('details', { class: 'i18-card' }, h('summary', {}, 'Iniciar la prueba de 14 días'), h('div', { class: 'i18-form' }, field('su-t-org', 'Cliente', tOrg), field('su-t-plan', 'Plan de la prueba', tPlan), field('su-t-why', 'Nota', tWhy), tGo)),
      h('details', { class: 'i18-card' }, h('summary', {}, 'Contratar un plan'), h('div', { class: 'i18-form' }, field('su-c-org', 'Cliente', cOrg), field('su-c-plan', 'Plan', cPlan), field('su-c-cycle', 'Ciclo', cCycle),
        field('su-c-since', 'El cobro empieza', cSince), h('label', { class: 'i18-chk' }, cFnd, ' Precio de fundador'), field('su-c-why', 'Condiciones', cWhy), cGo)),
      h('details', { class: 'i18-card' }, h('summary', {}, 'Cambiar de plan (subir al instante, bajar el mes siguiente)'), h('div', { class: 'i18-form' }, field('su-p-org', 'Cliente', pOrg), field('su-p-plan', 'Plan nuevo', pPlan),
        h('label', { class: 'i18-chk' }, pFnd, ' Precio de fundador'), field('su-p-why', 'Motivo', pWhy), pGo)),
      h('details', { class: 'i18-card' }, h('summary', {}, 'Generar la pre-factura de un período'), h('div', { class: 'i18-form' }, field('su-g-org', 'Cliente', gOrg), field('su-g-from', 'Primer día del período', gMonth), gGo)));
  }

  function renderList() {
    list.replaceChildren(h('h3', {}, 'Clientes'), table([
      { label: 'Cliente', get: (c) => c.name },
      { label: 'Estado', get: (c) => pill(c.state) },
      { label: 'Plan', get: (c) => c.plan_name || '—' },
      { label: 'Ciclo', get: (c) => c.cycle || '—' },
      { label: 'Médicos', right: true, get: (c) => String(c.providers) },
      { label: 'Atraso', get: (c) => (c.overdue.days > 0 ? `${c.overdue.days} día(s) · ${LEVEL[c.overdue.level] || c.overdue.level}` : '—') },
      { label: 'Saldo', right: true, get: (c) => money(c.balance) },
      { label: 'Próximo cobro', get: (c) => (c.next_billing_on ? fmtDate(c.next_billing_on) : '—') },
      { label: 'Notas', get: (c) => [c.trial_ends_on && c.state === 'prueba' ? `Prueba hasta ${fmtDate(c.trial_ends_on)}` : null, c.pending_plan ? `Baja a ${c.pending_plan} el ${fmtDate(c.pending_plan_from)}` : null,
        c.cancel_effective_on ? `Cancela el ${fmtDate(c.cancel_effective_on)}` : null, c.drafts ? `${c.drafts} borrador(es)` : null].filter(Boolean).join(' · ') || '—' },
      { label: '', get: (c) => { const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': `Pre-facturas de ${c.name}` }, 'Pre-facturas'); b.addEventListener('click', () => openClient(c.organization_id)); return b; } }], ov.clients));
  }

  async function openClient(orgId) {
    sel = orgId;
    const d = await guarded(panel, () => rpc('my_subscription', { p_org: orgId }));
    if (!d) return;
    const msg = h('div', { 'aria-live': 'polite' });
    const act = async (btn, fn, ok) => {
      btn.disabled = true; msg.replaceChildren();
      try { await fn(); await load(); const m = document.getElementById('su-act-out'); if (m) m.replaceChildren(note(ok, 'ok')); } catch (e) { msg.replaceChildren(note(e.message, 'error')); btn.disabled = false; }
    };
    const rows = d.invoices.map((i) => {
      const cells = [];
      const ver = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': `Ver la pre-factura ${i.number}` }, 'Ver');
      ver.addEventListener('click', async () => { const x = await guarded(detail, () => rpc('sub_invoice_detail', { p_invoice: i.id })); if (x) detail.replaceChildren(invoiceDetail(x)); });
      cells.push(ver);
      if (i.status === 'borrador') {
        const due = h('input', { type: 'date', 'aria-label': `Vencimiento de ${i.number}`, class: 'su-mini' }); const ref = h('input', { type: 'text', 'aria-label': `Comprobante externo de ${i.number}`, placeholder: 'Comprobante externo (opcional)', class: 'su-mini', maxlength: '40' });
        const em = h('button', { class: 'i18-btn', type: 'button' }, 'Emitir');
        em.addEventListener('click', () => act(em, () => rpc('sub_invoice_issue', { p_invoice: i.id, p_due_on: due.value || null, p_external_ref: ref.value || null }), `Pre-factura ${i.number} emitida. Recuerde: el comprobante fiscal se emite fuera de SOFA.`));
        const rc = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Recalcular');
        rc.addEventListener('click', () => act(rc, () => rpc('sub_invoice_generate', { p_org: orgId, p_period_start: i.period_start, p_note: null }), `Pre-factura ${i.number} recalculada.`));
        cells.push(due, ref, em, rc);
      } else if (i.status === 'emitida_externa' || i.status === 'vencida') {
        const amt = h('input', { type: 'number', step: '0.01', min: '0.01', value: String(i.balance), 'aria-label': `Monto del pago de ${i.number}`, class: 'su-mini' });
        const dt = h('input', { type: 'date', value: todayIso(), 'aria-label': `Fecha del pago de ${i.number}`, class: 'su-mini' });
        const rf = h('input', { type: 'text', placeholder: 'Referencia del pago', 'aria-label': `Referencia del pago de ${i.number}`, class: 'su-mini', maxlength: '60' });
        const me = h('select', { 'aria-label': `Método de pago de ${i.number}`, class: 'su-mini' }, METHODS.map((m) => h('option', { value: m }, m)));
        const pg = h('button', { class: 'i18-btn', type: 'button' }, 'Registrar pago');
        pg.addEventListener('click', () => act(pg, () => rpc('sub_invoice_pay', { p_invoice: i.id, p_amount: Number(amt.value), p_paid_on: dt.value || null, p_reference: rf.value, p_method: me.value }), `Pago registrado en ${i.number}.`));
        cells.push(amt, dt, rf, me, pg);
      }
      return h('tr', {}, h('td', {}, i.number), h('td', {}, KIND[i.kind] || i.kind), h('td', {}, `${fmtDate(i.period_start)} al ${fmtDate(i.period_end)}`),
        h('td', {}, h('span', { class: `su-inv su-inv-${i.status}` }, INV[i.status] || i.status)), h('td', { class: 'i18-r' }, money(i.total)), h('td', { class: 'i18-r' }, money(i.balance)),
        h('td', {}, i.due_on ? fmtDate(i.due_on) : '—'), h('td', { class: 'su-acts' }, ...cells));
    });
    const exps = d.exports.map((e) => {
      const nx = EXPORT_NEXT[e.status] || [];
      const sl = h('select', { 'aria-label': 'Nuevo estado de la exportación' }, nx.map((x) => h('option', { value: x }, x.replace('_', ' '))));
      const gb = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !nx.length }, 'Cambiar estado');
      gb.addEventListener('click', () => act(gb, () => rpc('sub_export_set_status', { p_request: e.id, p_status: sl.value, p_note: null }), 'Estado de la exportación actualizado.'));
      return h('tr', {}, h('td', {}, fmtDate(e.requested_at)), h('td', {}, fmtDate(e.effective_on)), h('td', {}, fmtDate(e.retention_until)), h('td', {}, e.status.replace('_', ' ')), h('td', {}, nx.length ? [sl, ' ', gb] : '—'));
    });
    panel.replaceChildren(h('h3', {}, `Pre-facturas · ${d.org_name}`), h('div', { class: 'i18-bar' }, pill(d.subscription?.state), h('span', { class: 'i18-sub' }, d.plan ? d.plan.name : 'Sin plan')),
      ...(d.alerts || []).map((a) => note(a, 'warn')),
      d.invoices.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Número', 'Concepto', 'Período', 'Estado', 'Total', 'Saldo', 'Vence', 'Acciones'].map((x) => h('th', {}, x)))), h('tbody', {}, rows))) : note('Este cliente todavía no tiene pre-facturas.'),
      exps.length ? [h('h3', {}, 'Exportación completa solicitada'), h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Pedida', 'Termina', 'Datos hasta', 'Estado', ''].map((x) => h('th', {}, x)))), h('tbody', {}, exps)))] : null,
      msg, h('div', { id: 'su-act-out', 'aria-live': 'polite' }), note(d.fiscal_notice));
  }

  function renderConfig() {
    const msg = h('div', { 'aria-live': 'polite' });
    const prow = ov.params.map((p) => {
      const inp = h('input', { type: 'number', step: 'any', min: '0', value: p.value == null ? '' : String(p.value), 'aria-label': p.label, class: 'su-mini' });
      const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': `Guardar ${p.label}` }, 'Guardar');
      b.addEventListener('click', async () => {
        b.disabled = true; msg.replaceChildren();
        try { await rpc('sub_param_set', { p_code: p.code, p_value: inp.value === '' ? null : Number(inp.value) }); await load(); const m = document.getElementById('su-cfg-out'); if (m) m.replaceChildren(note('Parámetro guardado.', 'ok')); }
        catch (e) { msg.replaceChildren(note(e.message, 'error')); b.disabled = false; }
      });
      return h('tr', {}, h('td', {}, p.label, p.value == null ? h('small', { class: 'i18-sub' }, ' · sin definir') : null), h('td', {}, inp, ` ${p.unit}`), h('td', {}, b));
    });
    const dmin = h('input', { type: 'number', min: '2', step: '1', 'aria-label': 'Desde cuántos médicos', class: 'su-mini', placeholder: 'Desde (médicos)' });
    const dpct = h('input', { type: 'number', min: '0', max: '100', step: '0.01', 'aria-label': 'Porcentaje de descuento', class: 'su-mini', placeholder: '% (vacío = quitar)' });
    const db = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar escala');
    db.addEventListener('click', async () => {
      db.disabled = true; msg.replaceChildren();
      try { await rpc('sub_discount_set', { p_min_doctors: dmin.value === '' ? null : Number(dmin.value), p_pct: dpct.value === '' ? null : Number(dpct.value) }); await load(); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); db.disabled = false; }
    });
    cfg.replaceChildren(h('p', { class: 'i18-sub' }, 'Los precios están en «Planes». El descuento por volumen y el ITBIS son decisiones abiertas: se cargan aquí, sin programar.'),
      h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['Parámetro', 'Valor', ''].map((x) => h('th', {}, x)))), h('tbody', {}, prow))),
      h('h4', {}, 'Descuento por volumen (por cantidad de médicos activos)'),
      ov.discounts.length ? h('ul', {}, ov.discounts.map((d) => h('li', {}, `Desde ${d.min_doctors} médicos: ${d.pct} %`))) : note('No hay escalas cargadas: hoy no se aplica descuento por volumen.'),
      h('div', { class: 'i18-bar' }, dmin, dpct, db), msg, h('div', { id: 'su-cfg-out', 'aria-live': 'polite' }));
  }

  await load();
}
export default render;
