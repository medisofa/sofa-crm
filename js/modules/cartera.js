/** SOFA · 3.4 · Iteración 44 · Cartera escalonada por ARS.
 *  0–30 días seguimiento · 31–60 reclamación formal · 61–90 escalamiento · más de 90 queja ante la SISALRIL.
 *  Cartas modelo para imprimir o guardar en PDF y bitácora de gestión de cobro. */
import { rpc, h, money, fmtDate, note, guarded, kpi, clientOptions, clientName } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';

const KIND = { llamada: 'Llamada', correo: 'Correo', carta: 'Carta', reclamacion_formal: 'Reclamación formal', escalamiento: 'Escalamiento', queja_sisalril: 'Queja SISALRIL',
  respuesta: 'Respuesta de la ARS', promesa_pago: 'Promesa de pago', otro: 'Otro' };
const LETTER = { reclamacion_formal: 'Carta de reclamación formal', escalamiento: 'Carta de escalamiento', queja_sisalril: 'Borrador de queja SISALRIL' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const client = ctx.role === 'client';
  const sel = h('select', { id: 'ca-org' }, h('option', { value: '' }, 'Todos los clientes'));
  const box = h('div', { 'aria-live': 'polite' });
  const side = h('div', { id: 'ca-side' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, client ? 'Mi cartera con las ARS' : 'Cartera escalonada por ARS'),
    h('p', { class: 'i18-sub' }, 'Que ningún lote pase de 90 días sin acción formal: 31–60 reclamación escrita, 61–90 escalamiento a la gerencia de red, más de 90 queja ante la SISALRIL.'),
    client ? null : h('div', { class: 'i18-bar' }, h('label', { for: 'ca-org' }, 'Cliente', sel)), box, side));
  if (!client) { try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { box.replaceChildren(note(e.message, 'error')); } }
  const org = () => (client ? ctx.membership?.organization_id || null : sel.value || null);

  async function load() {
    side.replaceChildren();
    const d = await guarded(box, () => rpc('collection_board', { p_org: org() }));
    if (!d) return;
    const t = d.totals;
    box.replaceChildren(
      h('div', { class: 'i18-kpis' }, kpi('Saldo por cobrar', money(t.balance), `${t.lots} lote(s)`), kpi('Más de 90 días', money(t.over_90)), kpi('Acciones pendientes', String(t.pending_actions))),
      h('h3', {}, 'Por ARS'),
      d.by_ars.length ? table(['ARS', client ? null : 'Cliente', 'Lotes', 'Saldo', 'Más antiguo', 'Pendientes', 'Días promedio de pago', ''].filter((x) => x !== null), d.by_ars.map((a) => {
        const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Historial');
        b.addEventListener('click', () => history(a));
        return [a.ars, client ? null : a.client, String(a.lots), money(a.balance), `${a.max_age} días`, String(a.pending), a.dso == null ? '—' : `${a.dso} días`, b].filter((x) => x !== null);
      }), [2, 3, 5]) : note('No hay lotes radicados con saldo.'),
      h('h3', {}, 'Lotes con saldo'),
      d.lots.length ? table(['Lote', client ? null : 'Cliente', 'ARS', 'Radicado', 'Días', 'Saldo', 'Toca', 'Última gestión', d.can_edit ? '' : null].filter((x) => x !== null), d.lots.map((l) => {
        const st = l.stage === 'seguimiento' ? l.stage_label : l.stage_done_on ? `${l.stage_label} · hecho ${fmtDate(l.stage_done_on)}` : h('strong', { class: 'cs-over' }, l.stage_label);
        let act = null;
        if (d.can_edit) {
          act = h('div', { class: 'i18-bar' });
          if (LETTER[l.stage]) { const c = h('button', { class: 'i18-btn', type: 'button' }, 'Carta'); c.addEventListener('click', () => letter(l, d)); act.append(c); }
          const g = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Registrar gestión'); g.addEventListener('click', () => action(l)); act.append(g);
        }
        return [l.folio || '—', client ? null : l.client, l.ars, fmtDate(l.submitted_on), String(l.age_days), money(l.balance), st,
          l.last_action ? `${KIND[l.last_action.kind] || l.last_action.kind} ${fmtDate(l.last_action.done_on)}` : '—', d.can_edit ? act : null].filter((x) => x !== null);
      }), [4, 5]) : null);
  }

  async function letter(l, d) {
    const same = d.lots.filter((x) => x.organization_id === l.organization_id && x.ars_id === l.ars_id && x.stage === l.stage).map((x) => x.id);
    const w = openPrint();
    try {
      const r = await rpc('collection_letter', { p_kind: l.stage, p_submissions: same });
      if (!fillPrint(w, r.title, `${l.client} · ${l.ars} · ${same.length} lote(s)`, [r.warning ? { warn: r.warning } : null, { pre: r.body }].filter(Boolean))) {
        side.replaceChildren(note('El navegador bloqueó la ventana. Permita las ventanas emergentes de SOFA e intente de nuevo.', 'error')); return;
      }
      action(l, l.stage, same, `${LETTER[l.stage]} generada (${same.length} lote(s)). Márquela aquí cuando la envíe.`);
    } catch (e) { if (w) w.close(); side.replaceChildren(note(e.message, 'error')); }
  }

  function action(l, kind = 'llamada', subs = [l.id], hint = null) {
    const k = h('select', { id: 'ca-a-kind' }, Object.entries(KIND).map(([v, t]) => h('option', { value: v, selected: v === kind }, t)));
    const day = h('input', { type: 'date', id: 'ca-a-day', value: new Date().toISOString().slice(0, 10) });
    const txt = h('textarea', { id: 'ca-a-note', rows: '2', maxlength: '1000', style: 'width:100%' });
    const pd = h('input', { type: 'date', id: 'ca-a-pd' });
    const pa = h('input', { type: 'number', id: 'ca-a-pa', min: '0', step: '0.01' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar gestión');
    const out = h('div', { 'aria-live': 'polite' });
    save.addEventListener('click', async () => {
      save.disabled = true; out.replaceChildren();
      try {
        await rpc('collection_action_add', { p_org: l.organization_id, p_ars: l.ars_id, p_kind: k.value, p_note: txt.value || null, p_submissions: subs,
          p_promise_date: pd.value || null, p_promise_amount: pa.value ? Number(pa.value) : null, p_done_on: day.value || null });
        await load(); side.replaceChildren(note('Gestión registrada.'));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    side.replaceChildren(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, `Gestión de cobro · ${l.ars} · ${subs.length} lote(s)`), hint ? note(hint) : null,
      h('label', { for: 'ca-a-kind' }, 'Tipo'), k, h('label', { for: 'ca-a-day' }, 'Fecha'), day, h('label', { for: 'ca-a-note' }, 'Qué se hizo o qué respondió la ARS'), txt,
      h('label', { for: 'ca-a-pd' }, 'Promesa de pago: fecha'), pd, h('label', { for: 'ca-a-pa' }, 'Promesa de pago: monto (RD$)'), pa, h('div', {}, save), out));
    side.scrollIntoView({ behavior: 'smooth' });
  }

  async function history(a) {
    const d = await guarded(side, () => rpc('collection_history', { p_org: a.organization_id, p_ars: a.ars_id }));
    if (!d) return;
    side.replaceChildren(h('div', { class: 'i18-card' }, h('h3', {}, `Gestión de cobro · ${a.ars}${client ? '' : ` · ${a.client}`}`),
      d.length ? h('ul', {}, d.map((x) => h('li', {}, h('strong', {}, `${fmtDate(x.done_on)} · ${KIND[x.kind] || x.kind}`), x.note ? ` · ${x.note}` : '',
        x.promise_date ? ` · promete pagar ${x.promise_amount ? money(x.promise_amount) + ' ' : ''}el ${fmtDate(x.promise_date)}` : '', x.lots ? ` · ${x.lots.join(', ')}` : '', x.by ? h('span', { class: 'i18-sub' }, ` — ${x.by}`) : '')))
        : note('Sin gestiones registradas.')));
    side.scrollIntoView({ behavior: 'smooth' });
  }

  const table = (head, rows, right = []) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x, i) => h('th', { class: right.includes(i) ? 'i18-r' : null }, x)))),
    h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x, i) => h('td', { class: right.includes(i) ? 'i18-r' : null }, x)))))));

  sel.addEventListener('change', load);
  await load();
}
export default render;
