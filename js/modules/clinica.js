/** SOFA · 5.6.0 · I66 · «Mi clínica»: departamentos del Centro médico y resumen (caja central del mes).
 *  Crear/renombrar/desactivar departamentos lo hacen Super Admin, Administrador y Operaciones; el director
 *  de la clínica ve pero no cambia. La base valida todo; ocultar un botón aquí no es un control.
 *  Se abre con #/clinica/<id-de-la-clinica>. */
import { rpc, h, note, guarded, money } from '../services/iter18.js';

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const org = ctx.arg || null;
  const wrap = h('div', { class: 'i18-wrap cli-wrap' });
  root.append(wrap);
  if (!org) {
    wrap.append(h('h2', {}, 'Mi clínica'), note('Abre esta pantalla desde la ficha de un Centro médico.', 'info'));
    return;
  }
  const head = h('div', { 'aria-live': 'polite' });
  const body = h('div', { 'aria-live': 'polite' });
  wrap.append(h('h2', {}, 'Mi clínica'), head, body);

  async function load() {
    const [ov, deps] = await Promise.all([
      guarded(head, () => rpc('clinic_overview', { p_org: org })),
      guarded(body, () => rpc('clinic_departments_list', { p_org: org })),
    ]);
    if (!ov || !deps) return;
    drawHead(ov); drawBody(deps);
  }

  function drawHead(ov) {
    head.replaceChildren(h('div', { class: 'cli-kpis' },
      kpi('Médicos activos', ov.medicos_activos),
      kpi('Departamentos', ov.departamentos),
      kpi('Caja del mes', money(ov.caja_mes || 0))));
  }

  function drawBody(deps) {
    body.replaceChildren();
    const canManage = !!deps.can_manage;
    const status = h('div', { 'aria-live': 'polite' });
    body.append(h('h3', {}, 'Departamentos'), status);

    const ul = h('div', { class: 'cli-deps' }, (deps.departments || []).map((d) =>
      h('div', { class: 'cli-dep' },
        h('div', {}, h('b', {}, d.name), h('span', { class: 'cli-mut' }, ` · ${d.medicos} médico(s)`)),
        canManage ? h('div', { class: 'cli-acc' },
          btn('Renombrar', () => rename(d, status)),
          btn('Desactivar', () => setActive(d.id, false, status), 'i18-sec')) : null)));
    body.append(ul);
    if (!(deps.departments || []).length) body.append(note('Esta clínica aún no tiene departamentos.', 'info'));
    if ((deps.sin_departamento || 0) > 0) body.append(note(`${deps.sin_departamento} médico(s) sin departamento.`, 'info'));

    if (canManage) {
      const inp = h('input', { type: 'text', placeholder: 'Nombre del nuevo departamento', maxlength: '120', 'aria-label': 'Nombre del nuevo departamento' });
      const add = btn('Agregar', async () => {
        const name = (inp.value || '').trim();
        if (!name) { status.replaceChildren(note('Escribe el nombre del departamento.', 'warn')); return; }
        try { await rpc('clinic_department_save', { p_org: org, p_name: name }); inp.value = ''; status.replaceChildren(note('Departamento agregado.', 'ok')); await load(); }
        catch (e) { status.replaceChildren(note(e.message, 'error')); }
      });
      body.append(h('div', { class: 'cli-add' }, inp, add));
    }
  }

  async function rename(d, status) {
    const name = (prompt('Nuevo nombre del departamento:', d.name) || '').trim();
    if (!name || name === d.name) return;
    try { await rpc('clinic_department_save', { p_org: org, p_name: name, p_id: d.id }); status.replaceChildren(note('Renombrado.', 'ok')); await load(); }
    catch (e) { status.replaceChildren(note(e.message, 'error')); }
  }
  async function setActive(id, on, status) {
    try { await rpc('clinic_department_set_active', { p_id: id, p_on: on }); status.replaceChildren(note('Listo.', 'ok')); await load(); }
    catch (e) { status.replaceChildren(note(e.message, 'error')); }
  }

  function kpi(label, val) { return h('div', { class: 'cli-kpi' }, h('div', { class: 'cli-kpi-n' }, String(val)), h('div', { class: 'cli-kpi-l' }, label)); }
  function btn(label, fn, cls = '') { const b = h('button', { class: `i18-btn ${cls}`, type: 'button' }, label); b.addEventListener('click', fn); return b; }

  await load();
}
