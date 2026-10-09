/** SOFA · 27 · Saldos pendientes de pacientes (cobros privados y copagos en «pendiente»).
 *  «Preparar recordatorio» deja un WhatsApp en «Mensajes»; nada se envía solo. */
import { rpc, providerOptions, h, money, num, fmtDate, note, guarded, table } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const msg = h('div', { 'aria-live': 'polite' });
  const out = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Saldos pendientes de pacientes'), top, msg, out);
  const provs = await guarded(top, providerOptions);
  if (!provs) return;
  if (!provs.length) { top.replaceChildren(note('No tiene médicos asignados. Pida al Administrador que le asigne su consultorio.')); return; }
  const sel = h('select', { id: 'sp-prov' }, provs.map((p) => h('option', { value: p.id }, p.full_name)));
  top.replaceChildren(h('div', { class: 'i18-form' }, h('label', { for: 'sp-prov' }, 'Médico'), sel));

  async function remind(btn, r) {
    btn.disabled = true; msg.replaceChildren();
    try {
      await rpc('queue_balance_reminder', { p_provider: sel.value, p_doc: r.doc || null, p_name: r.name });
      msg.replaceChildren(note(`Recordatorio preparado para ${r.name}. Envíelo desde «Mensajes».`));
      await load();
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); btn.disabled = false; }
  }
  async function load() {
    const rows = await guarded(out, () => rpc('patient_balances', { p_provider: sel.value }));
    if (!rows) return;
    const total = rows.reduce((s, r) => s + Number(r.amount || 0), 0);
    out.replaceChildren(
      note(`${num(rows.length)} paciente(s) con saldo · Total pendiente ${money(total)}`),
      table([
        { label: 'Paciente', get: (r) => r.name }, { label: 'Documento', get: (r) => r.doc || '—' },
        { label: 'Cobros', right: true, get: (r) => num(r.charges) }, { label: 'Saldo', right: true, get: (r) => money(r.amount) },
        { label: 'Desde', get: (r) => `${fmtDate(r.oldest)} (${num(r.days)} días)` },
        { label: 'Último recordatorio', get: (r) => (r.last_reminder ? fmtDate(r.last_reminder) : '—') },
        { label: '', get: (r) => (r.phone
            ? h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: (e) => remind(e.currentTarget, r) }, 'Preparar recordatorio')
            : h('span', { class: 'i18-sub' }, 'Sin teléfono')) }], rows));
  }
  sel.addEventListener('change', load);
  await load();
}
