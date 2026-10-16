/** SOFA · 4.8.0 · P1 · Planes (Administración): qué plan tiene cada cliente, asignarlo con vigencia y motivo, ver el catálogo y encender el bloqueo por plan.
 *  Solo Super Admin y Administrador. El servidor vuelve a verificar el rol en cada función; ocultar el menú no es un control. */
import { rpc, h, money, fmtDate, note, kpi, guarded, todayIso } from '../services/iter18.js';

const LINE = { servicio: 'Servicio SOFA', saas: 'SaaS (solo software)', legado: 'Fundador / Legado' };
const LIMIT_LABEL = { max_medicos: 'Médicos', reclamaciones_mes_por_medico: 'Reclamaciones/mes por médico', secretarias_por_medico: 'Secretarias por médico', usuarios_por_medico: 'Usuarios por médico' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const form = h('div', { 'aria-live': 'polite' });
  const list = h('div', { 'aria-live': 'polite' });
  const cat = h('div', { 'aria-live': 'polite' });
  const hist = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Planes de los clientes'),
    h('p', { class: 'i18-sub' }, 'Asigne el plan de cada cliente, vea su consumo y encienda el bloqueo por plan cuando todos tengan uno. El cliente nunca cambia su plan.'),
    top, form, list, hist, h('h3', {}, 'Catálogo de planes'), cat));
  const isSuper = ctx.role === 'super_admin';
  let ov = null;

  async function load() {
    ov = await guarded(list, () => rpc('plans_overview'));
    if (!ov) return;
    renderTop(); renderForm(); renderList(); renderCatalog();
  }

  function renderTop() {
    const sw = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !isSuper }, ov.enforced ? 'Desactivar el bloqueo por plan' : 'Activar el bloqueo por plan');
    const out = h('div', { 'aria-live': 'polite' });
    sw.addEventListener('click', async () => {
      const motivo = window.prompt(ov.enforced ? 'Motivo para DESACTIVAR el bloqueo por plan (mínimo 10 caracteres):' : 'Motivo para ACTIVAR el bloqueo por plan (mínimo 10 caracteres). Desde ese momento los clientes no podrán pasar los límites de su plan:');
      if (motivo == null) return;
      sw.disabled = true;
      try { await rpc('plans_set_enforce', { p_on: !ov.enforced, p_note: motivo }); await load(); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); sw.disabled = !isSuper; }
    });
    top.replaceChildren(h('div', { class: 'i18-kpis' }, kpi('Bloqueo por plan', ov.enforced ? 'ACTIVO' : 'Apagado', ov.enforced ? 'Los límites se aplican en el servidor' : 'Nada se bloquea todavía'),
      kpi('Clientes sin plan', String(ov.clients_without_plan), ov.clients_without_plan ? 'Asígneles plan antes de activar el bloqueo' : 'Todos tienen plan'),
      kpi('Clientes', String(ov.clients.length))),
      isSuper ? sw : note('Solo el Super Admin activa o desactiva el bloqueo por plan.'), out);
  }

  function renderForm() {
    const cl = h('select', { id: 'pl-org' }, h('option', { value: '' }, 'Elija un cliente…'), ov.clients.map((c) => h('option', { value: c.organization_id }, c.name)));
    const pl = h('select', { id: 'pl-plan' }, h('option', { value: '' }, 'Elija un plan…'), ov.plans.filter((p) => p.is_active).map((p) => h('option', { value: p.code }, `${p.name} · ${LINE[p.line] || p.line}`)));
    const since = h('input', { id: 'pl-since', type: 'date', value: todayIso() });
    const fnd = h('input', { id: 'pl-founder', type: 'checkbox' });
    const why = h('textarea', { id: 'pl-why', rows: '2', maxlength: '300', style: 'width:100%', placeholder: 'Motivo del cambio (mínimo 10 caracteres). Queda en el historial.' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Asignar plan');
    const out = h('div', { 'aria-live': 'polite' });
    go.addEventListener('click', async () => {
      out.replaceChildren(); go.disabled = true;
      try {
        const r = await rpc('assign_org_plan', { p_org: cl.value || null, p_plan: pl.value || null, p_starts_on: since.value || null, p_note: why.value, p_founder: fnd.checked });
        why.value = '';
        await load();
        const box = document.getElementById('pl-out');
        if (box) box.replaceChildren(note('Plan asignado.' + (r.warnings?.length ? ' Atención: ' + r.warnings.join(' ') : ''), r.warnings?.length ? 'warn' : 'ok'));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    form.replaceChildren(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Asignar o cambiar el plan de un cliente'),
      h('label', { for: 'pl-org' }, 'Cliente'), cl, h('label', { for: 'pl-plan' }, 'Plan'), pl, h('label', { for: 'pl-since' }, 'Vigente desde'), since,
      h('label', { class: 'i18-chk' }, fnd, ' Precio de fundador'), h('label', { for: 'pl-why' }, 'Motivo'), why, h('div', {}, go), out, h('div', { id: 'pl-out', 'aria-live': 'polite' })));
  }

  function renderList() {
    const rows = ov.clients.map((c) => {
      const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Historial');
      b.addEventListener('click', () => history(c));
      return h('tr', {}, h('td', {}, c.name), h('td', {}, c.plan_name || h('em', {}, 'Sin plan')), h('td', {}, c.starts_on ? fmtDate(c.starts_on) : '—'),
        h('td', {}, c.scheduled ? `${c.scheduled.plan_code} desde ${fmtDate(c.scheduled.starts_on)}` : '—'), h('td', { class: 'i18-r' }, String(c.providers)),
        h('td', { class: 'i18-r' }, c.claims_limit == null ? String(c.claims_max) : `${c.claims_max} / ${c.claims_limit}`), h('td', { class: 'i18-r' }, String(c.users)), h('td', {}, b));
    });
    list.replaceChildren(h('h3', {}, 'Clientes y su plan'), h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Cliente', 'Plan', 'Desde', 'Programado', 'Médicos', 'Reclamaciones del mes (mayor / límite)', 'Usuarios', ''].map((x) => h('th', {}, x)))),
      h('tbody', {}, rows.length ? rows : h('tr', {}, h('td', { colspan: '8', class: 'i18-empty' }, 'No hay clientes.'))))));
  }

  async function history(c) {
    const r = await guarded(hist, () => rpc('plan_history', { p_org: c.organization_id }));
    if (!r) return;
    hist.replaceChildren(h('h3', {}, `Historial de planes · ${c.name}`), h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Plan', 'Desde', 'Hasta', 'Estado', 'Motivo', 'Asignó'].map((x) => h('th', {}, x)))),
      h('tbody', {}, r.map((x) => h('tr', {}, h('td', {}, x.plan_name + (x.founder_price ? ' (fundador)' : '')), h('td', {}, fmtDate(x.starts_on)), h('td', {}, x.ends_on ? fmtDate(x.ends_on) : '—'),
        h('td', {}, x.status), h('td', {}, x.note || '—'), h('td', {}, x.assigned_by || '—')))))));
  }

  function renderCatalog() {
    cat.replaceChildren(h('p', { class: 'i18-sub' }, 'Precios y límites que se aplican. Se editan con las funciones plan_save, plan_limit_set y plan_feature_set (Super Admin y Administrador).'),
      h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Plan', 'Línea', 'Cuota', 'Fundador', 'Límites', 'Módulos', 'Clientes'].map((x) => h('th', {}, x)))),
        h('tbody', {}, ov.plans.map((p) => h('tr', {}, h('td', {}, p.name + (p.is_active ? '' : ' (inactivo)')), h('td', {}, LINE[p.line] || p.line), h('td', { class: 'i18-r' }, p.price_monthly == null ? '—' : money(p.price_monthly)),
          h('td', { class: 'i18-r' }, p.price_founder == null ? '—' : money(p.price_founder)),
          h('td', {}, Object.keys(p.limits).length ? Object.entries(p.limits).map(([k, v]) => `${LIMIT_LABEL[k] || k}: ${v.value}${v.on_exceed === 'avisar' ? ' (avisa)' : ''}`).join(' · ') : 'Sin límites'),
          h('td', { class: 'i18-r' }, String(p.features)), h('td', { class: 'i18-r' }, String(p.clients))))))));
  }

  await load();
}
export default render;
