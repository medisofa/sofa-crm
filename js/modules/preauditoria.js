/** SOFA · 3.2 · Iteración 42 · Pre-auditoría del lote y glosa de primera pasada.
 *  Cada lote abierto con su puntaje y la lista de correcciones (qué hacer y en qué reclamaciones) antes de radicar. */
import { rpc, h, money, fmtDate, note, guarded, kpi, clientOptions, clientName } from '../services/iter18.js';

const SEV = { bloquea: 'Bloquea', advierte: 'Advierte' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const staff = !['client'].includes(ctx.role);
  const sel = h('select', { id: 'pa-org' }, h('option', { value: '' }, staff ? 'Todos los clientes' : 'Mi consultorio'));
  const kpis = h('div', { 'aria-live': 'polite' });
  const lots = h('div', { 'aria-live': 'polite' });
  const detail = h('div', { id: 'pa-detail' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Pre-auditoría de lotes'),
    h('p', { class: 'i18-sub' }, 'Revisa cada lote abierto con las reglas de radicación antes de enviarlo a la ARS. «Bloquea» = hoy impide radicar; «Advierte» = conviene corregir.'),
    staff ? h('div', { class: 'i18-bar' }, h('label', { for: 'pa-org' }, 'Cliente', sel)) : null, kpis, lots, detail));
  if (staff) {
    try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { lots.replaceChildren(note(e.message, 'error')); }
  }
  const org = () => (staff ? sel.value || null : ctx.membership?.organization_id || null);

  async function load() {
    detail.replaceChildren();
    const fp = await guarded(kpis, () => rpc('first_pass_glosa', { p_org: org(), p_months: 6 }));
    if (fp) {
      const t = fp.total || {};
      kpis.replaceChildren(h('div', { class: 'i18-kpis' },
        kpi('Glosa de primera pasada (6 meses)', t.pct == null ? '—' : `${t.pct} %`, `Meta: menos de ${fp.target_pct} % · Línea base RD: ${fp.baseline_pct} %`),
        kpi('Radicado en el primer envío', money(t.claimed), `${t.lots || 0} lote(s)`), kpi('Glosado en el primer envío', money(t.glosado))),
        fp.by_ars.length ? h('details', {}, h('summary', {}, 'Por ARS'), table(['ARS', 'Radicado', 'Glosado', '%'], fp.by_ars.map((a) => [a.ars, money(a.claimed), money(a.glosado), a.pct == null ? '—' : `${a.pct} %`]), [1, 2, 3])) : null);
    }
    const list = await guarded(lots, () => rpc('preaudit_open_lots', { p_org: org() }));
    if (!list) return;
    lots.replaceChildren(h('h3', {}, `Lotes abiertos (${list.length})`), list.length ? table(['Lote', staff ? 'Cliente' : null, 'Médico', 'ARS', 'Período', 'Reclamaciones', 'Puntaje', 'Estado', ''].filter((x) => x !== null),
      list.map((l) => {
        const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Ver correcciones');
        b.addEventListener('click', () => show(l));
        return [l.folio || '—', staff ? l.client : null, l.provider || '—', l.ars || '—', String(l.period || '').slice(0, 7), String(l.lines),
          h('span', { class: `pa-score ${l.score >= 90 ? 'ok' : l.score >= 60 ? 'warn' : 'bad'}` }, `${l.score}`),
          l.can_submit ? 'Listo para radicar' : l.empty ? 'Sin reclamaciones' : `${l.lines_with_problems} con problemas`, b].filter((x) => x !== null);
      }), [5, 6]) : note('No hay lotes abiertos.'));
  }

  function show(l) {
    detail.replaceChildren(h('div', { class: 'i18-card' }, h('h3', {}, `Lote ${l.folio || ''} · puntaje ${l.score}`),
      l.can_submit ? note('Sin problemas que bloqueen: el lote se puede radicar.') : null,
      l.problems.length ? h('ol', { class: 'pa-list' }, l.problems.map((p) => h('li', {},
        h('span', { class: `pa-sev ${p.severity}` }, SEV[p.severity]), ' ', h('strong', {}, p.label), p.scope === 'lote' ? ' (todo el lote)' : ` · ${p.count} reclamación(es)`,
        h('div', {}, 'Qué hacer: ', p.todo),
        p.claims.length ? h('div', { class: 'i18-sub' }, p.claims.map((c) => `${c.folio || 'sin folio'} · ${c.patient}${c.missing && c.missing.length ? ` (falta: ${c.missing.join(', ')})` : ''}`).join(' — ')) : null)))
        : note('El lote no tiene reclamaciones todavía.')));
    detail.scrollIntoView({ behavior: 'smooth' });
  }

  const table = (head, rows, right = []) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x, i) => h('th', { class: right.includes(i) ? 'i18-r' : null }, x)))),
    h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x, i) => h('td', { class: right.includes(i) ? 'i18-r' : null }, x)))))));

  sel.addEventListener('change', load);
  await load();
}
export default render;
