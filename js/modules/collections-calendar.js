/** SOFA · 18-B · Calendario de cobros proyectados por ARS, con alerta de atraso. */
import { rpc, clientOptions, h, money, num, fmtDate, clientName, kpi, table, note, guarded, downloadCsv, todayIso } from '../services/iter18.js';

const BASIS = { historial_cliente: 'Historial del cliente', historial_ars: 'Historial de la ARS', plazo_contractual: 'Plazo contractual' };
const STATUS = { atrasado: 'Atrasado', esta_semana: 'Esta semana', proximo: 'Próximo' };
const MES = (iso) => { const [y, m] = iso.slice(0, 10).split('-'); return ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'][Number(m) - 1] + ' ' + y; };

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const sel = h('select', { id: 'i18-cc-client' }, h('option', { value: '' }, 'Todos mis clientes'));
  const csvBtn = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: true }, 'Exportar CSV');
  let data = null;

  async function load() {
    csvBtn.disabled = true;
    data = await guarded(out, () => rpc('collection_calendar', { p_org: sel.value || null }));
    if (!data) return;
    out.replaceChildren(view(data)); csvBtn.disabled = false;
  }
  csvBtn.addEventListener('click', () => downloadCsv(`calendario_cobros_${todayIso()}.csv`, [
    ['Cliente', 'ARS', 'Lote', 'Médico', 'Radicado', 'Esperado', 'Días de atraso', 'Base de la fecha', 'Estado', 'Saldo'],
    ...data.lotes.map((l) => [l.client, l.ars, l.folio, l.provider || '', l.submitted_on, l.expected_on, l.days_late, BASIS[l.basis], STATUS[l.status], l.balance])]));
  sel.addEventListener('change', load);
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Calendario de cobros proyectados'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Cliente', sel), csvBtn), out));
  try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { /* la lista es opcional */ }
  await load();
}
export default render;
export const mount = render;

function view(d) {
  const t = d.totals;
  return h('div', { class: 'i18-wrap' },
    h('div', { class: 'i18-kpis' },
      kpi('Por cobrar', money(t.balance), `${num(t.lotes)} lote(s) radicados con saldo`),
      kpi('Atrasado', money(t.late_balance), `${num(t.late_lotes)} lote(s) pasaron su fecha esperada`),
      kpi('Se espera esta semana', money(t.this_week_balance))),
    note(d.method),
    h('h3', {}, 'Por ARS'),
    table([{ label: 'ARS', get: (x) => x.ars }, { label: 'Lotes', right: true, get: (x) => num(x.lotes) }, { label: 'Por cobrar', right: true, get: (x) => money(x.balance) },
           { label: 'Atrasado', right: true, get: (x) => money(x.late_balance) }, { label: 'Días típicos de pago', right: true, get: (x) => num(x.days_expected) },
           { label: 'Próximo cobro esperado', get: (x) => fmtDate(x.next_expected) }], d.by_ars),
    h('h3', {}, 'Por mes esperado (lo atrasado se cuenta en el mes actual)'),
    table([{ label: 'Mes', get: (x) => MES(x.month) }, { label: 'Lotes', right: true, get: (x) => num(x.lotes) }, { label: 'Por cobrar', right: true, get: (x) => money(x.balance) }], d.by_month),
    h('h3', {}, 'Lotes'),
    table([{ label: 'Cliente', get: (x) => x.client }, { label: 'ARS', get: (x) => x.ars }, { label: 'Lote', get: (x) => x.folio }, { label: 'Radicado', get: (x) => fmtDate(x.submitted_on) },
           { label: 'Esperado', get: (x) => fmtDate(x.expected_on) }, { label: 'Base', get: (x) => BASIS[x.basis] || x.basis },
           { label: 'Estado', get: (x) => h('span', { class: `i18-badge i18-${x.status}` }, x.status === 'atrasado' ? `Atrasado ${x.days_late} día(s)` : STATUS[x.status]) },
           { label: 'Saldo', right: true, get: (x) => money(x.balance) }], d.lotes));
}
