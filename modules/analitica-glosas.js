/** SOFA · 26 · Analítica de glosas: cuánto se glosa, por qué, qué ARS y cuánto se recupera (solo lectura).
 *  Personal de SOFA puede ver todos los clientes; el médico ve solo los suyos. */
import { rpc, clientOptions, h, money, num, pct, note, guarded, kpi, table, todayIso, monthsAgoIso, clientName } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const out = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Analítica de glosas'), top, out);
  const clients = await guarded(top, clientOptions);
  if (!clients) return;
  const org = h('select', { id: 'ag-org' }, h('option', { value: '' }, 'Todos los clientes (solo SOFA)'), clients.map((c) => h('option', { value: c.id }, clientName(c))));
  if (clients.length === 1) org.value = clients[0].id;
  const from = h('input', { id: 'ag-from', type: 'date', value: monthsAgoIso(5) });
  const to = h('input', { id: 'ag-to', type: 'date', value: todayIso() });
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Ver');
  top.replaceChildren(h('div', { class: 'i18-form' }, h('label', { for: 'ag-org' }, 'Cliente'), org,
    h('label', { for: 'ag-from' }, 'Glosas notificadas desde'), from, h('label', { for: 'ag-to' }, 'Hasta'), to, go));

  async function load() {
    const d = await guarded(out, () => rpc('glosa_analytics', { p_org: org.value || null, p_from: from.value, p_to: to.value }));
    if (!d) return;
    const t = d.totals, r = d.rates;
    out.replaceChildren(
      h('div', { class: 'i18-kpis' },
        kpi('Glosado', money(t.glosado), `${num(t.glosas)} glosa(s)`),
        kpi('% glosado de lo radicado', r.glosa_pct == null ? '—' : pct(r.glosa_pct), `Radicado: ${money(t.radicado)}`),
        kpi('Recuperado', money(t.recuperado), r.recuperacion_pct == null ? null : `Recuperación ${pct(r.recuperacion_pct)}`),
        kpi('Aceptado (perdido)', money(t.aceptado)), kpi('En disputa', money(t.en_disputa))),
      h('h3', {}, 'Por motivo y cómo prevenirlo'),
      table([{ label: 'Motivo', get: (x) => x.reason }, { label: 'Servicios', right: true, get: (x) => num(x.items) },
        { label: 'Glosado', right: true, get: (x) => money(x.glosado) }, { label: 'Recuperado', right: true, get: (x) => money(x.recuperado) },
        { label: 'Cómo prevenirlo', get: (x) => x.tip }], d.by_reason),
      h('h3', {}, 'Por ARS'),
      table([{ label: 'ARS', get: (x) => x.ars }, { label: 'Glosado', right: true, get: (x) => money(x.glosado) },
        { label: 'Recuperado', right: true, get: (x) => money(x.recuperado) }, { label: 'Recuperación', right: true, get: (x) => (x.recuperacion_pct == null ? '—' : pct(x.recuperacion_pct)) }], d.by_ars),
      h('h3', {}, 'Auditores de ARS con más glosas'),
      table([{ label: 'Auditor', get: (x) => x.auditor }, { label: 'Glosas', right: true, get: (x) => num(x.glosas) },
        { label: 'Glosado', right: true, get: (x) => money(x.glosado) }], d.by_auditor));
  }
  go.addEventListener('click', load);
  if (org.value) await load(); else out.replaceChildren(note('Elija un cliente y toque «Ver». «Todos los clientes» solo funciona para el personal de SOFA.'));
}
