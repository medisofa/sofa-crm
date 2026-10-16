/** SOFA · 4.8.0 · P1 · «Mi plan»: el plan del consultorio, cuánto lleva usado de cada límite y qué módulos incluye.
 *  Solo lectura: el plan lo asigna la Administración de SOFA. Los bloqueos reales están en la base de datos. */
import { rpc, h, money, fmtDate, note, kpi, guarded } from '../services/iter18.js';

const STATE = { sin_limite: 'Sin límite', ok: 'En orden', aviso: 'Llegando al límite', al_limite: 'En el límite', excedido: 'Pasó el límite' };
const KIND = { modulo: 'Módulos de la app', servicio_sofa: 'Servicio del equipo SOFA', seguridad: 'Seguridad y control' };

/** Barra de consumo accesible (meter). Sin estilos en línea: el color lo da el estado. */
function meter(l) {
  if (l.limit == null) return h('span', { class: 'i18-sub' }, 'Sin límite');
  const m = h('meter', { class: `pl-meter pl-${l.state}`, min: '0', max: String(Math.max(l.effective_limit, 1)), value: String(Math.min(l.used, Math.max(l.effective_limit, 1))), 'aria-label': `${l.label}: ${l.used} de ${l.effective_limit}` });
  return h('span', {}, m, ' ', `${l.used} de ${l.effective_limit}`);
}

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  const picker = h('div', { class: 'i18-bar' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Mi plan'),
    h('p', { class: 'i18-sub' }, 'Lo que incluye su plan con SOFA y cuánto lleva usado este mes. Para cambiar de plan, escriba a SOFA.'), picker, box));
  const staff = ['super_admin', 'admin', 'operations', 'assistant'].includes(ctx.role);
  let org = staff ? null : (ctx.membership?.organization_id || null);

  async function load() {
    if (staff && !org) { box.replaceChildren(note('Elija un cliente para ver su plan.')); return; }
    const d = await guarded(box, () => rpc('my_plan_usage', { p_org: org }));
    if (!d) return;
    const p = d.plan;
    const head = p
      ? h('section', { class: 'i18-card' }, h('div', { class: 'i18-bar' }, h('h3', {}, p.name), h('span', { class: 'i18-sub' }, `Desde el ${fmtDate(p.starts_on)}${p.ends_on ? ` hasta el ${fmtDate(p.ends_on)}` : ''}`)),
          p.description ? h('p', {}, p.description) : null,
          h('div', { class: 'i18-kpis' }, p.price_monthly != null ? kpi('Cuota por médico al mes', money(p.founder_price && p.price_founder != null ? p.price_founder : p.price_monthly), p.founder_price ? 'Precio de fundador' : 'Precio regular') : null,
            kpi('Mes que se mide', d.month), kpi('Bloqueo por plan', d.enforced ? 'Activo' : 'Todavía no se aplica')))
      : note('Su cuenta todavía no tiene un plan asignado. Escriba a SOFA para activarlo.', 'warn');
    const alerts = (d.alerts || []).filter(Boolean).map((a) => note(a, 'warn'));
    const limits = d.limits.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Límite', 'Uso', 'Estado'].map((x) => h('th', {}, x)))),
      h('tbody', {}, d.limits.map((l) => h('tr', {}, h('td', {}, l.label), h('td', {}, meter(l)), h('td', {}, STATE[l.state] || l.state)))))) : null;
    const provs = d.providers.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Médico', 'Reclamaciones este mes', 'Límite mensual'].map((x) => h('th', {}, x)))),
      h('tbody', {}, d.providers.map((x) => h('tr', {}, h('td', {}, x.name), h('td', {}, String(x.claims_month)), h('td', {}, x.claims_limit == null ? 'Sin límite' : String(x.claims_limit))))))) : null;
    const groups = Object.keys(KIND).map((k) => {
      const rows = d.features.filter((f) => f.kind === k);
      return rows.length ? h('details', { class: 'i18-card', open: k === 'modulo' }, h('summary', {}, KIND[k]),
        h('ul', { class: 'pl-list' }, rows.map((f) => h('li', { class: f.included ? 'pl-yes' : 'pl-no' }, h('span', { 'aria-hidden': 'true' }, f.included ? '✔ ' : '— '),
          f.label, f.included ? '' : ' (no incluido en su plan)', f.note ? h('small', { class: 'i18-sub' }, ` · ${f.note}`) : null)))) : null;
    });
    box.replaceChildren(head, ...alerts, h('h3', {}, 'Consumo de los límites'), limits, h('h3', {}, 'Por médico'), provs, h('h3', {}, 'Qué incluye'), ...groups);
  }

  if (staff) {
    const { clientOptions, clientName } = await import('../services/iter18.js');
    try {
      const cs = await clientOptions();
      const sel = h('select', { id: 'mp-org' }, h('option', { value: '' }, 'Elija un cliente…'), cs.map((c) => h('option', { value: c.id }, clientName(c))));
      sel.addEventListener('change', () => { org = sel.value || null; load(); });
      picker.replaceChildren(h('label', { for: 'mp-org' }, 'Cliente', sel));
    } catch (e) { picker.replaceChildren(note(e.message, 'error')); }
  }
  await load();
}
export default render;
