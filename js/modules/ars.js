/** SOFA · Catálogo de ARS y sus planes.
 *  2.6.1: el Super Admin y el Administrador agregan o editan ARS y planes (no se borran: se desactivan, porque hay tarifas
 *  y reclamaciones que los usan). Cada plan puede tener su propia tarifa: si la tiene, manda sobre la general de la ARS. */
import { rpc, h, note, guarded } from '../services/iter18.js';
import { can } from '../utils/permissions.js';

const REGIMES = ['Contributivo', 'Subsidiado', 'Pensionados', 'Plan voluntario'];
const PLAN_TYPES = [['Contributivo', 'Básico (PDSS) contributivo'], ['Subsidiado', 'Básico subsidiado'], ['Pensionados', 'Pensionados'],
  ['Complementario', 'Complementario'], ['Plan voluntario', 'Plan voluntario'], ['Internacional', 'Internacional'], ['Riesgos laborales', 'Riesgos laborales']];

export async function render(root, ctx = {}) {
  const edit = can('ars.edit', ctx.role);
  root.replaceChildren();
  const pane = h('div', { 'aria-live': 'polite' });
  const list = h('div', { 'aria-live': 'polite' });
  const q = h('input', { id: 'ars-q', type: 'search', placeholder: 'Buscar ARS o plan' });
  const inactive = h('input', { id: 'ars-inact', type: 'checkbox' });
  root.append(h('h2', {}, 'ARS y planes'),
    h('p', { class: 'i18-sub' }, edit
      ? 'Agregue o corrija ARS y planes. Los planes precargados vienen de fuentes públicas (2026): confírmelos con el tarifario de cada ARS. Nada se borra: se desactiva.'
      : 'Administradoras de Riesgos de Salud y sus planes. Si necesita una corrección, pídala al Administrador de SOFA.'),
    h('div', { class: 'i18-bar' }, h('label', { for: 'ars-q' }, 'Buscar', q),
      edit ? h('label', { class: 'i18-chk' }, inactive, ' Ver también las desactivadas') : '',
      edit ? h('button', { class: 'i18-btn', type: 'button', onclick: () => arsForm(null) }, '+ Nueva ARS') : ''),
    pane, list);
  let data = [];
  const norm = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  async function load() {
    const d = await guarded(list, () => rpc('ars_catalog', { p_include_inactive: edit && inactive.checked }));
    if (d) { data = d; draw(); }
  }
  function draw() {
    const t = norm(q.value);
    const rows = data.filter((a) => !t || norm(a.name).includes(t) || a.plans.some((p) => norm(p.name).includes(t)));
    list.replaceChildren(rows.length ? h('div', { class: 'ars-grid' }, rows.map(card)) : note('No hay ARS que coincidan con la búsqueda.'));
  }
  function card(a) {
    return h('section', { class: `i18-card ars-card${a.active ? '' : ' ars-off'}` },
      h('header', { class: 'hc-head' }, h('div', {}, h('strong', {}, a.name), h('div', { class: 'i18-sub' }, [a.regime, a.channel].filter(Boolean).join(' · ') || '—')),
        h('div', { class: 'i18-actions', style: 'margin:0' },
          a.active ? '' : h('span', { class: 'ac-pill st-none' }, 'Desactivada'),
          h('span', { class: `ac-pill ${a.tariffs ? 'st-ok' : 'st-req'}`, title: 'Tarifas vigentes de esta ARS' }, `${a.tariffs} tarifas`),
          edit ? h('button', { class: 'i18-link', type: 'button', onclick: () => arsForm(a) }, 'Editar') : '')),
      a.notes ? h('p', { class: 'i18-sub' }, a.notes) : '',
      h('ul', { class: 'ars-plans' }, a.plans.length ? a.plans.map((p) => h('li', { class: p.active ? '' : 'ars-off' },
        h('span', {}, p.name), h('span', { class: 'i18-sub' }, ` · ${p.regime}${p.tariffs ? ` · ${p.tariffs} tarifas propias` : ''}${p.active ? '' : ' · desactivado'}`),
        edit ? h('button', { class: 'i18-link', type: 'button', onclick: () => planForm(a, p) }, 'Editar') : '')) : h('li', { class: 'i18-sub' }, 'Sin planes registrados.')),
      edit ? h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => planForm(a, null) }, '+ Agregar plan') : '');
  }
  function field(id, label, el) { el.id = id; return h('label', { for: id }, label, el); }
  function arsForm(a) {
    const name = h('input', { value: a?.name || '', maxlength: '120' });
    const code = h('input', { value: a?.code || '', maxlength: '40', placeholder: 'Se genera solo si lo deja vacío', disabled: !!a });
    const regime = h('select', {}, REGIMES.map((r) => h('option', { value: r, selected: (a?.regime || 'Contributivo') === r }, r)));
    const channel = h('input', { value: a?.channel || '', maxlength: '120', placeholder: 'Ej.: Portal PSS + oficinas' });
    const notes = h('textarea', { rows: '2', maxlength: '500' }, a?.notes || '');
    const active = h('input', { type: 'checkbox', checked: a ? a.active : true });
    const msg = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar ARS');
    save.addEventListener('click', async () => {
      save.disabled = true;
      try {
        await rpc('ars_save', { p_id: a?.id || null, p_name: name.value, p_code: code.value || null, p_regime: regime.value, p_channel: channel.value, p_notes: notes.value, p_active: active.checked });
        pane.replaceChildren(note(`ARS «${name.value.trim()}» guardada.`, 'ok')); await load();
      } catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    pane.replaceChildren(h('section', { class: 'i18-card hc-form' }, h('header', { class: 'hc-head' }, h('strong', {}, a ? `Editar ${a.name}` : 'Nueva ARS'),
      h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')),
      h('div', { class: 'hc-grid' }, field('ars-name', 'Nombre', name), field('ars-code', 'Código corto', code), field('ars-regime', 'Régimen principal', regime),
        field('ars-channel', 'Canal de radicación', channel)), field('ars-notes', 'Notas', notes),
      h('label', { class: 'i18-chk' }, active, ' Activa (aparece en los formularios)'), h('div', { class: 'i18-actions' }, save), msg));
    name.focus();
  }
  function planForm(a, p) {
    const name = h('input', { value: p?.name || '', maxlength: '120', placeholder: 'Ej.: Royal, Max, Plan Básico de Salud (PDSS)' });
    const type = h('select', {}, PLAN_TYPES.map(([v, l]) => h('option', { value: v, selected: (p?.regime || 'Complementario') === v }, l)));
    const sort = h('input', { type: 'number', min: '1', max: '999', value: String(p?.sort || 100) });
    const notes = h('textarea', { rows: '2', maxlength: '500' }, p?.notes || '');
    const active = h('input', { type: 'checkbox', checked: p ? p.active : true });
    const msg = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar plan');
    save.addEventListener('click', async () => {
      save.disabled = true;
      try {
        await rpc('ars_plan_save', { p_id: p?.id || null, p_ars: a.id, p_name: name.value, p_regime: type.value, p_notes: notes.value, p_active: active.checked, p_sort: Number(sort.value) || 100 });
        pane.replaceChildren(note(`Plan «${name.value.trim()}» de ${a.name} guardado.`, 'ok')); await load();
      } catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    pane.replaceChildren(h('section', { class: 'i18-card hc-form' }, h('header', { class: 'hc-head' }, h('strong', {}, p ? `Editar plan ${p.name} · ${a.name}` : `Nuevo plan · ${a.name}`),
      h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')),
      h('div', { class: 'hc-grid' }, field('pl-name', 'Nombre del plan', name), field('pl-type', 'Tipo', type), field('pl-sort', 'Orden en las listas', sort)),
      field('pl-notes', 'Notas (por ejemplo, de dónde sale el dato)', notes),
      h('label', { class: 'i18-chk' }, active, ' Activo (se puede elegir en pacientes y tarifarios)'), h('div', { class: 'i18-actions' }, save), msg));
    name.focus();
  }
  q.addEventListener('input', draw);
  inactive.addEventListener('change', load);
  await load();
}
