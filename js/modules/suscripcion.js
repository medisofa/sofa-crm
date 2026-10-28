/** SOFA · 4.8.0 · P2 · «Mi suscripción»: el estado de la suscripción del consultorio, sus pre-facturas y la cancelación a fin de mes.
 *  El Médico ve solo lo suyo (el servidor lo verifica en cada función). Las pre-facturas son documentos internos de SOFA, NO fiscales:
 *  el comprobante fiscal se emite fuera de SOFA. Quien paga registra la referencia con SOFA; el cliente no cambia su plan ni su estado. */
import { rpc, h, money, fmtDate, note, kpi, guarded, table } from '../services/iter18.js';

const STATE = { prueba: 'En prueba', activa: 'Activa', pendiente_pago: 'Pendiente de pago', solo_lectura: 'Solo lectura', suspendida: 'Suspendida', cancelada: 'Cancelada' };
const INV = { borrador: 'Borrador', emitida_externa: 'Emitida', pagada: 'Pagada', vencida: 'Vencida' };
const KIND = { alta: 'Primera cuota', mensual: 'Cuota mensual', anual: 'Cuota anual', cambio_plan: 'Cambio de plan' };
const EXPORT = { solicitada: 'Solicitada', en_preparacion: 'En preparación', lista: 'Lista', entregada: 'Entregada', cancelada: 'Cancelada' };
const LEVEL_KIND = { aviso: 'warn', aviso_app: 'warn', solo_lectura: 'error', suspension: 'error' };

export const pill = (state) => h('span', { class: `su-st su-${state}` }, STATE[state] || state || 'Sin suscripción');

/** Detalle de una pre-factura (líneas, pagos y la nota de que NO es fiscal). Lo comparten «Mi suscripción» y la administración. */
export function invoiceDetail(d) {
  const lines = table([
    { label: 'Concepto', get: (r) => r.concept },
    { label: 'Precio', right: true, get: (r) => (r.unit_price == null ? '—' : money(r.unit_price)) },
    { label: 'Monto', right: true, get: (r) => money(r.amount) }], d.lines);
  const pays = d.payments.length ? table([
    { label: 'Fecha', get: (r) => fmtDate(r.paid_on) }, { label: 'Referencia', get: (r) => r.reference }, { label: 'Método', get: (r) => r.method }, { label: 'Monto', right: true, get: (r) => money(r.amount) }], d.payments) : null;
  return h('section', { class: 'i18-card su-detail', 'aria-label': `Pre-factura ${d.number}` },
    h('div', { class: 'i18-bar' }, h('h3', {}, `Pre-factura ${d.number}`), h('span', { class: `su-inv su-inv-${d.status}` }, INV[d.status] || d.status)),
    h('p', { class: 'i18-sub' }, `${d.org_name} · ${KIND[d.kind] || d.kind} · ${fmtDate(d.period_start)} al ${fmtDate(d.period_end)}${d.external_ref ? ` · Comprobante externo ${d.external_ref}` : ''}`),
    lines,
    h('dl', { class: 'su-totals' },
      h('dt', {}, 'Subtotal'), h('dd', {}, money(d.subtotal)),
      d.discount_amount > 0 ? [h('dt', {}, `Descuento por volumen (${d.discount_pct} %)`), h('dd', {}, '− ' + money(d.discount_amount))] : null,
      d.itbis_amount != null ? [h('dt', {}, `ITBIS (${d.itbis_rate} %)`), h('dd', {}, money(d.itbis_amount))] : null,
      h('dt', { class: 'su-tot' }, 'Total'), h('dd', { class: 'su-tot' }, money(d.total)),
      h('dt', {}, 'Pagado'), h('dd', {}, money(d.amount_paid)), h('dt', {}, 'Saldo'), h('dd', {}, money(d.balance))),
    d.due_on ? h('p', {}, `Vence el ${fmtDate(d.due_on)}.`) : null,
    pays ? [h('h4', {}, 'Pagos registrados'), pays] : null,
    h('p', { class: 'i18-note i18-info' }, d.fiscal_notice));
}

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  const picker = h('div', { class: 'i18-bar' });
  const detail = h('div', { 'aria-live': 'polite' });
  const out = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap su-wrap' }, h('h2', {}, 'Mi suscripción'),
    h('p', { class: 'i18-sub' }, 'El estado de su suscripción con SOFA, sus pre-facturas y la cancelación. Para cambiar de plan o pagar, escriba a SOFA.'), picker, box, detail, out));
  const staff = ['super_admin', 'admin'].includes(ctx.role);
  let org = staff ? null : (ctx.membership?.organization_id || null);

  async function load() {
    detail.replaceChildren();
    if (staff && !org) { box.replaceChildren(note('Elija un cliente para ver su suscripción.')); return; }
    const d = await guarded(box, () => rpc('my_subscription', { p_org: org }));
    if (!d) return;
    const s = d.subscription;
    if (!s) {
      box.replaceChildren(note('Su cuenta todavía no tiene una suscripción. Escriba a SOFA para iniciar la prueba o contratar su plan.', 'warn'), ...(d.alerts || []).map((a) => note(a, 'warn')), finePrint(d));
      return;
    }
    const alerts = (d.alerts || []).filter(Boolean).map((a) => note(a, LEVEL_KIND[d.overdue?.level] && /vencida|solo lectura|suspendida|cancelada/i.test(a) ? LEVEL_KIND[d.overdue.level] : 'warn'));
    const q = d.next_quote;
    const head = h('section', { class: 'i18-card' },
      h('div', { class: 'i18-bar' }, h('h3', {}, d.plan ? d.plan.name : 'Sin plan'), pill(s.state)),
      h('div', { class: 'i18-kpis' },
        kpi('Ciclo de cobro', s.cycle === 'anual' ? 'Anual' : 'Mensual'),
        s.state === 'prueba' ? kpi('Días de prueba que le quedan', String(s.trial_days_left ?? 0), s.trial_ends_on ? `Hasta el ${fmtDate(s.trial_ends_on)} · solo datos ficticios` : null) : null,
        s.next_billing_on ? kpi('Próximo cobro', fmtDate(s.next_billing_on)) : null,
        q ? kpi('Cuota estimada del próximo período', money(q.total), `${q.providers} médico(s) activo(s)${q.discount_pct > 0 ? ` · descuento ${q.discount_pct} %` : ''}`) : null,
        s.pending_plan ? kpi('Cambio de plan programado', s.pending_plan.name, `Desde el ${fmtDate(s.pending_plan.from)}`) : null));
    const invs = d.invoices.length ? table([
      { label: 'Número', get: (r) => r.number }, { label: 'Concepto', get: (r) => KIND[r.kind] || r.kind },
      { label: 'Período', get: (r) => `${fmtDate(r.period_start)} al ${fmtDate(r.period_end)}` },
      { label: 'Estado', get: (r) => h('span', { class: `su-inv su-inv-${r.status}` }, INV[r.status] || r.status) },
      { label: 'Vence', get: (r) => (r.due_on ? fmtDate(r.due_on) : '—') }, { label: 'Total', right: true, get: (r) => money(r.total) }, { label: 'Saldo', right: true, get: (r) => money(r.balance) },
      { label: '', get: (r) => { const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': `Ver la pre-factura ${r.number}` }, 'Ver'); b.addEventListener('click', () => open(r.id)); return b; } }], d.invoices)
      : note('Todavía no tiene pre-facturas emitidas.');
    const gate = d.export_gate;
    const cupo = gate && gate.limit != null ? h('section', { class: 'i18-card' }, h('h3', {}, 'Reclamaciones de este mes'),
      h('p', {}, h('meter', { class: `pl-meter ${gate.blocked ? 'pl-excedido' : gate.warn ? 'pl-aviso' : 'pl-ok'}`, min: '0', max: String(Math.max(gate.limit, 1)), value: String(Math.min(gate.used, Math.max(gate.limit, 1))), 'aria-label': `Reclamaciones del mes: ${gate.used} de ${gate.limit}` }), ` ${gate.used} de ${gate.limit}${gate.pct != null ? ` (${gate.pct} %)` : ''}`),
      h('p', { class: 'i18-sub' }, 'Al llegar al 80 % le avisamos. Pasado el 100 % no puede exportar lotes hasta mejorar su plan o hasta el próximo mes.')) : null;
    const exps = d.exports.length ? h('section', { class: 'i18-card' }, h('h3', {}, 'Exportación completa de sus datos'),
      table([{ label: 'Pedida', get: (r) => fmtDate(r.requested_at) }, { label: 'Termina la suscripción', get: (r) => fmtDate(r.effective_on) }, { label: 'Datos conservados hasta', get: (r) => fmtDate(r.retention_until) },
        { label: 'Estado', get: (r) => EXPORT[r.status] || r.status }], d.exports),
      h('p', { class: 'i18-sub' }, 'La prepara el equipo de SOFA y se la entrega; el archivo se genera en un paso posterior a la solicitud.')) : null;
    box.replaceChildren(head, ...alerts, h('h3', {}, 'Pre-facturas'), invs, cupo, exps, cancelBox(d), finePrint(d));
  }

  const finePrint = (d) => note(d.fiscal_notice);

  function cancelBox(d) {
    const s = d.subscription;
    if (s.state === 'cancelada') return null;
    const msg = h('div', { 'aria-live': 'polite' });
    if (s.cancel_effective_on) {
      const undo = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Anular la cancelación');
      undo.addEventListener('click', async () => {
        undo.disabled = true; msg.replaceChildren();
        try { await rpc('sub_cancel_undo', { p_org: org }); await load(); } catch (e) { msg.replaceChildren(note(e.message, 'error')); undo.disabled = false; }
      });
      return h('section', { class: 'i18-card' }, h('h3', {}, 'Cancelación pedida'), h('p', {}, `Su suscripción termina el ${fmtDate(s.cancel_effective_on)} y sus datos se conservan hasta el ${fmtDate(s.retention_until)}.`), undo, msg);
    }
    const why = h('textarea', { id: 'su-why', rows: '2', maxlength: '300', placeholder: 'Motivo (opcional)' });
    const go = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Pedir la cancelación a fin de mes');
    go.addEventListener('click', async () => {
      if (!window.confirm('La suscripción terminará el último día de este mes. SOFA preparará la exportación completa de sus datos y los conservará 90 días. ¿Desea continuar?')) return;
      go.disabled = true; msg.replaceChildren();
      try { const r = await rpc('sub_cancel_request', { p_org: org, p_note: why.value || null }); await load(); out.replaceChildren(note(r.message, 'ok')); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    return h('details', { class: 'i18-card' }, h('summary', {}, 'Cancelar la suscripción'),
      h('p', { class: 'i18-sub' }, 'La cancelación es a fin de mes. Se le prepara la exportación completa de sus datos y se conservan 90 días. Puede anularla antes de esa fecha.'),
      h('label', { for: 'su-why' }, 'Motivo', why), go, msg);
  }

  async function open(id) {
    const d = await guarded(detail, () => rpc('sub_invoice_detail', { p_invoice: id }));
    if (!d) return;
    const bar = h('div', { class: 'i18-actions' });
    const pr = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Imprimir'); pr.addEventListener('click', () => window.print());
    bar.append(pr);
    detail.replaceChildren(invoiceDetail(d), bar);
    detail.scrollIntoView?.({ block: 'nearest' });
  }

  if (staff) {
    const { clientOptions, clientName } = await import('../services/iter18.js');
    try {
      const cs = await clientOptions();
      const sel = h('select', { id: 'su-org' }, h('option', { value: '' }, 'Elija un cliente…'), cs.map((c) => h('option', { value: c.id }, clientName(c))));
      sel.addEventListener('change', () => { org = sel.value || null; load(); });
      picker.replaceChildren(h('label', { for: 'su-org' }, 'Cliente', sel));
    } catch (e) { picker.replaceChildren(note(e.message, 'error')); }
  }
  await load();
}
export default render;
