/** SOFA · Pagos de pacientes: lo que el consultorio cobra directo al paciente (no es un pago de ARS).
 *  El médico siempre puede registrar los suyos; una secretaria solo si el médico la autorizó para
 *  esto en «Mis secretarias» (can_payments, mismo patrón que can_book/can_whatsapp). */
import { rpc, h, money, note, guarded, clientOptions, clientName } from '../services/iter18.js';

const METHOD = { efectivo: 'Efectivo', tarjeta: 'Tarjeta', transferencia: 'Transferencia', cheque: 'Cheque', otro: 'Otro' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const own = ['client', 'capturer'].includes(ctx.role);
  const sel = h('select', { id: 'pp-org' }, h('option', { value: '' }, 'Elija un cliente'));
  const body = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Pagos de pacientes'),
    h('p', { class: 'i18-sub' }, 'Lo que el paciente paga directo en el consultorio (efectivo, tarjeta, transferencia) por un servicio que no se reclama a la ARS.'),
    own ? null : h('div', { class: 'i18-bar' }, h('label', { for: 'pp-org' }, 'Cliente', sel)), body));
  if (!own) { try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { body.replaceChildren(note(e.message, 'error')); return; } }
  const org = () => (own ? ctx.membership?.organization_id : sel.value);
  sel.addEventListener('change', draw);

  async function draw() {
    if (!org()) { body.replaceChildren(note('Elija un cliente.')); return; }
    const d = await guarded(body, () => rpc('patient_payments_board', { p_org: org() }));
    if (!d) return;
    const writable = d.providers.filter((p) => p.can_write);

    const prov = h('select', { id: 'pp-u-prov' }, writable.map((p) => h('option', { value: p.id }, p.name)));
    const pat = h('input', { type: 'text', id: 'pp-u-pat', maxlength: '120', required: true });
    const concept = h('input', { type: 'text', id: 'pp-u-concept', maxlength: '160', required: true, placeholder: 'Ej.: Consulta, curación, estética…' });
    const amount = h('input', { type: 'number', id: 'pp-u-amount', min: '0.01', step: '0.01', required: true });
    const method = h('select', { id: 'pp-u-method' }, Object.entries(METHOD).map(([k, l]) => h('option', { value: k }, l)));
    const day = h('input', { type: 'date', id: 'pp-u-day', value: new Date().toISOString().slice(0, 10) });
    const nt = h('input', { type: 'text', id: 'pp-u-note', maxlength: '200', placeholder: 'Nota (opcional)' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Registrar pago');
    const out = h('div', { 'aria-live': 'polite' });
    save.addEventListener('click', async () => {
      save.disabled = true; out.replaceChildren();
      try {
        await rpc('patient_payment_add', { p_org: org(), p_provider: prov.value, p_patient_name: pat.value, p_concept: concept.value, p_amount: Number(amount.value), p_method: method.value, p_paid_on: day.value || null, p_notes: nt.value || null });
        pat.value = ''; concept.value = ''; amount.value = ''; nt.value = '';
        await draw(); body.prepend(note('Pago registrado.'));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });

    const form = writable.length
      ? h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Nuevo pago'),
          h('label', { for: 'pp-u-prov' }, 'Médico'), prov,
          h('label', { for: 'pp-u-pat' }, 'Paciente'), pat,
          h('label', { for: 'pp-u-concept' }, 'Concepto'), concept,
          h('label', { for: 'pp-u-amount' }, 'Monto (RD$)'), amount,
          h('label', { for: 'pp-u-method' }, 'Método'), method,
          h('label', { for: 'pp-u-day' }, 'Fecha'), day,
          h('label', { for: 'pp-u-note' }, 'Nota'), nt,
          h('div', {}, save), out)
      : note(own && ctx.role === 'capturer'
          ? 'El médico todavía no le autorizó registrar pagos de pacientes. Pídaselo en «Mis secretarias».'
          : 'No hay médicos activos para registrar pagos.');

    const kpis = h('div', { class: 'i18-kpis' },
      h('div', { class: 'i18-kpi' }, h('div', { class: 'i18-kpi-v' }, money(d.total_hoy)), h('div', { class: 'i18-kpi-l' }, 'Cobrado hoy')),
      h('div', { class: 'i18-kpi' }, h('div', { class: 'i18-kpi-v' }, money(d.total_mes)), h('div', { class: 'i18-kpi-l' }, 'Cobrado este mes')));

    const rows = d.recent;
    const paymentRow = (r) => {
      const amountCell = r.voided ? h('s', {}, money(r.amount)) : money(r.amount);
      const lastCell = r.voided
        ? h('span', { class: 'i18-sub' }, `Anulado: ${r.void_reason || ''}`)
        : (d.can_void ? h('button', { class: 'i18-link', type: 'button', onclick: () => voidPayment(r) }, 'Anular') : '');
      return h('tr', { style: r.voided ? 'opacity:.55' : '' },
        h('td', {}, r.paid_on), h('td', {}, r.patient), h('td', {}, r.concept), h('td', {}, r.provider || '—'),
        h('td', {}, METHOD[r.method] || r.method), h('td', { class: 'i18-r' }, amountCell), h('td', {}, r.by || '—'), h('td', {}, lastCell));
    };
    const list = rows.length
      ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
          h('thead', {}, h('tr', {}, ['Fecha', 'Paciente', 'Concepto', 'Médico', 'Método', 'Monto', 'Registró', ''].map((x) => h('th', {}, x)))),
          h('tbody', {}, rows.map(paymentRow))))
      : note('Sin pagos registrados todavía.');

    body.replaceChildren(kpis, form, h('h3', {}, 'Últimos pagos'), list);
  }

  async function voidPayment(r) {
    const reason = prompt(`Motivo para anular el pago de ${r.patient} (${money(r.amount)}):`);
    if (reason === null) return;
    try { await rpc('patient_payment_void', { p_id: r.id, p_reason: reason }); await draw(); }
    catch (e) { body.prepend(note(e.message, 'error')); }
  }

  await draw();
}
export default render;
