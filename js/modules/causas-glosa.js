/** SOFA · 3.3 · Iteración 43 · Glosas: plazo de respuesta y causa raíz.
 *  Equipo SOFA: semáforo de 7 días hábiles, Pareto de causas, acciones correctivas con su efecto y feriados.
 *  Médico: sus glosas abiertas con el plazo y sus 3 causas más frecuentes con cómo evitarlas. */
import { rpc, h, money, fmtDate, note, guarded, kpi, clientOptions, clientName } from '../services/iter18.js';

const LIGHT = { verde: 'A tiempo', amarillo: 'Vence pronto', rojo: 'Vencida' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const client = ctx.role === 'client';
  const myOrg = ctx.membership?.organization_id || null;
  const canAct = ['super_admin', 'admin', 'glosas'].includes(ctx.role);
  const tabs = h('div', { class: 'i18-bar', role: 'tablist' });
  const body = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, client ? 'Mis glosas: plazo y causas' : 'Glosas: plazo de respuesta y causa raíz'),
    h('p', { class: 'i18-sub' }, 'Cada glosa se trabaja dos veces: se responde a tiempo para recuperar el dinero y se corrige el proceso para que no vuelva a pasar.'), tabs, body));
  const views = client ? [['plazo', 'Plazo de respuesta', plazo], ['causas', 'Mis causas', misCausas]]
    : [['plazo', 'Plazo de respuesta', plazo], ['pareto', 'Causas raíz', pareto], ['acciones', 'Acciones correctivas', acciones], ['feriados', 'Feriados', feriados]];
  views.forEach(([k, label, fn], i) => {
    const b = h('button', { class: `i18-btn ${i ? 'i18-sec' : ''}`, type: 'button', role: 'tab', id: `cg-t-${k}` }, label);
    b.addEventListener('click', () => { tabs.querySelectorAll('button').forEach((x) => x.classList.add('i18-sec')); b.classList.remove('i18-sec'); fn(); });
    tabs.append(b);
  });

  async function plazo() {
    const d = await guarded(body, () => rpc('glosa_response_board', { p_org: client ? myOrg : null }));
    if (!d) return;
    const l = d.last90 || {};
    body.replaceChildren(h('div', { class: 'i18-kpis' }, kpi('Glosas por responder', String(d.open.length), `Plazo interno: ${d.business_days} días hábiles`),
      kpi('Respondidas a tiempo (90 días)', l.pct_on_time == null ? '—' : `${l.pct_on_time} %`, `${l.on_time || 0} de ${l.answered || 0}`)),
      d.open.length ? table(['Glosa', client ? null : 'Cliente', 'ARS', 'Lote', 'Notificada', 'Vence', 'Monto', 'Semáforo'].filter(Boolean),
        d.open.map((g) => [g.folio || '—', client ? null : g.client, g.ars || '—', g.lot || '—', fmtDate(g.notified_on), fmtDate(g.due), money(g.amount),
          h('span', { class: `ecf-l ${g.light}` }, `${LIGHT[g.light]} · ${g.days_left} día(s) hábil(es)`)].filter((x) => x !== null)), [client ? 5 : 6])
        : note('No hay glosas pendientes de respuesta.'));
  }

  async function misCausas() {
    const d = await guarded(body, () => rpc('my_glosa_causes', { p_org: myOrg }));
    if (!d) return;
    body.replaceChildren(h('h3', {}, 'Sus causas de glosa más frecuentes (6 meses)'),
      d.length ? h('ol', {}, d.map((c) => h('li', {}, h('strong', {}, `${c.name}: ${money(c.amount)} en ${c.items} servicio(s)`), h('div', {}, 'Cómo evitarla: ', c.tip))))
        : note('No tiene glosas en los últimos 6 meses.'));
  }

  async function pareto() {
    const org = h('select', { id: 'cg-org' }, h('option', { value: '' }, 'Toda la cartera'));
    const from = h('input', { type: 'date', id: 'cg-from', value: isoDays(-90) });
    const to = h('input', { type: 'date', id: 'cg-to', value: isoDays(0) });
    const out = h('div', { 'aria-live': 'polite' });
    const go = async () => {
      const d = await guarded(out, () => rpc('glosa_root_pareto', { p_org: org.value || null, p_from: from.value, p_to: to.value }));
      if (!d) return;
      out.replaceChildren(h('p', { class: 'i18-sub' }, `Total glosado: ${money(d.total)}. Las causas «vitales» suman el primer 80 %: atacarlas primero.`),
        d.causes.length ? table(['Causa', 'Categoría', 'Servicios', 'Monto', '%', 'Acumulado', 'ARS', 'Prevención', ''],
          d.causes.map((c) => {
            const add = canAct ? h('button', { class: 'i18-btn i18-sec', type: 'button' }, c.open_actions ? `${c.open_actions} acción(es)` : 'Crear acción') : '';
            if (canAct) add.addEventListener('click', () => newAction(c, org.value || null));
            return [h('span', {}, c.vital ? h('strong', {}, `★ ${c.name}`) : c.name), c.category, String(c.items), money(c.amount), `${c.pct} %`, `${c.acc_pct} %`, c.ars || '—', c.tip, add];
          }), [2, 3, 4, 5]) : note('No hay glosas en el período.'));
    };
    try { (await clientOptions()).forEach((c) => org.append(h('option', { value: c.id }, clientName(c)))); } catch (_) { /* filtro opcional */ }
    [org, from, to].forEach((x) => x.addEventListener('change', go));
    body.replaceChildren(h('div', { class: 'i18-bar' }, h('label', { for: 'cg-org' }, 'Cliente', org), h('label', { for: 'cg-from' }, 'Desde', from), h('label', { for: 'cg-to' }, 'Hasta', to)), out);
    await go();
  }

  function newAction(c, org) {
    const txt = h('textarea', { id: 'cg-a-txt', rows: '3', maxlength: '600', style: 'width:100%', placeholder: 'Qué cambia en el proceso para que no vuelva a pasar' });
    const due = h('input', { type: 'date', id: 'cg-a-due', value: isoDays(15) });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar acción');
    const out = h('div', { 'aria-live': 'polite' });
    save.addEventListener('click', async () => {
      save.disabled = true; out.replaceChildren();
      try { await rpc('glosa_root_action_save', { p_reason: c.reason_code, p_action: txt.value, p_org: org, p_ars: null, p_provider: null, p_owner: null, p_due: due.value || null }); acciones(); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    body.prepend(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, `Acción correctiva · ${c.name}`), h('p', { class: 'i18-sub' }, `Sugerencia: ${c.tip}`),
      h('label', { for: 'cg-a-txt' }, 'Acción'), txt, h('label', { for: 'cg-a-due' }, 'Fecha compromiso'), due, h('div', {}, save), out));
    txt.focus();
  }

  async function acciones() {
    const st = h('select', { id: 'cg-st' }, ['abierta', 'hecha', 'descartada'].map((s) => h('option', { value: s }, s[0].toUpperCase() + s.slice(1) + 's')));
    const out = h('div', { 'aria-live': 'polite' });
    const go = async () => {
      const d = await guarded(out, () => rpc('glosa_root_actions_list', { p_status: st.value }));
      if (!d) return;
      out.replaceChildren(d.length ? h('div', { class: 'i18-list' }, d.map((a) => {
        const eff = a.after ? `Antes: ${a.before.items} glosa(s), ${money(a.before.amount)} · Después: ${a.after.items}, ${money(a.after.amount)}${a.measurable ? '' : ' (se mide a los 60 días)'}` : `Línea base: ${a.before.items} glosa(s), ${money(a.before.amount)} en los 60 días previos`;
        const acts = [];
        if (canAct && a.status === 'abierta') {
          const done = h('button', { class: 'i18-btn', type: 'button' }, 'Marcar hecha');
          const drop = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descartar');
          const n = h('input', { type: 'text', maxlength: '300', 'aria-label': 'Nota', placeholder: 'Resultado o motivo' });
          const o = h('div', { 'aria-live': 'polite' });
          const close = (s) => async () => { try { await rpc('glosa_root_action_close', { p_id: a.id, p_status: s, p_note: n.value || null }); go(); } catch (e) { o.replaceChildren(note(e.message, 'error')); } };
          done.addEventListener('click', close('hecha')); drop.addEventListener('click', close('descartada'));
          acts.push(h('div', { class: 'i18-bar' }, n, done, drop), o);
        }
        return h('div', { class: 'i18-card' }, h('strong', {}, `${a.reason} · ${a.client || 'Toda la cartera'}${a.ars ? ` · ${a.ars}` : ''}`), h('p', {}, a.action),
          h('div', { class: 'i18-sub' }, `${a.owner || '—'} · compromiso ${fmtDate(a.due_date)}${a.overdue ? ' · ATRASADA' : ''}${a.result_note ? ` · ${a.result_note}` : ''}`),
          h('div', { class: 'i18-sub' }, eff), ...acts);
      })) : note('No hay acciones con ese estado.'));
    };
    st.addEventListener('change', go);
    body.replaceChildren(h('div', { class: 'i18-bar' }, h('label', { for: 'cg-st' }, 'Estado', st)), out);
    await go();
  }

  async function feriados() {
    const year = new Date().getFullYear();
    const d = await guarded(body, () => rpc('holidays_list', { p_year: null }));
    if (!d) return;
    const day = h('input', { type: 'date', id: 'cg-h-day' });
    const name = h('input', { type: 'text', id: 'cg-h-name', maxlength: '80' });
    const save = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Guardar feriado');
    const out = h('div', { 'aria-live': 'polite' });
    save.addEventListener('click', async () => { try { await rpc('holiday_save', { p_day: day.value || null, p_name: name.value, p_delete: false }); feriados(); } catch (e) { out.replaceChildren(note(e.message, 'error')); } });
    body.replaceChildren(h('p', { class: 'i18-sub' }, 'Días que no cuentan como hábiles. Los feriados que la ley permite mover se agregan cada año con su fecha real (confírmela con el calendario oficial).'),
      table(['Fecha', 'Feriado', ''], d.filter((x) => Number(String(x.day).slice(0, 4)) >= year).map((x) => {
        const del = ['super_admin', 'admin'].includes(ctx.role) ? h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Quitar') : '';
        if (del) del.addEventListener('click', async () => { try { await rpc('holiday_save', { p_day: x.day, p_name: null, p_delete: true }); feriados(); } catch (e) { out.replaceChildren(note(e.message, 'error')); } });
        return [fmtDate(x.day), x.name, del];
      })),
      ['super_admin', 'admin'].includes(ctx.role) ? h('div', { class: 'i18-bar' }, h('label', { for: 'cg-h-day' }, 'Fecha', day), h('label', { for: 'cg-h-name' }, 'Nombre', name), save) : null, out);
  }

  const table = (head, rows, right = []) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x, i) => h('th', { class: right.includes(i) ? 'i18-r' : null }, x)))),
    h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x, i) => h('td', { class: right.includes(i) ? 'i18-r' : null }, x)))))));
  const isoDays = (n) => { const x = new Date(); x.setDate(x.getDate() + n); return x.toISOString().slice(0, 10); };

  await plazo();
}
export default render;
