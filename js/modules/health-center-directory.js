/** SOFA · Directorio de centros de salud: ficha con datos de contacto para facilitar la gestión con las ARS.
 *  5.40.0: nuevo directorio tipo ficha, llamando a health_center_directory(). Solo super_admin y admin pueden
 *  agregar/editar centros desde aquí. */
import { rpc, h, note, guarded } from '../services/iter18.js';
import { can } from '../utils/permissions.js';

const CENTER_TYPES = ['Clínica', 'Hospital', 'Centro diagnóstico', 'Laboratorio', 'Consultorio', 'Farmacia', 'Centro de rehabilitación', 'Otro'];

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const wrap = h('div', { class: 'i18-wrap' });
  const q = h('input', { type: 'search', class: 'i18-input', placeholder: 'Buscar centro por nombre, ciudad o tipo…', style: 'margin-bottom:.7rem;max-width:28rem' });
  const inactive = h('label', { class: 'i18-chk', style: 'margin-left:1rem' }, h('input', { type: 'checkbox' }), ' Incluir inactivos');
  const inactiveChk = inactive.querySelector('input');
  const pane = h('div', { 'aria-live': 'polite' });
  const list = h('div', { class: 'hc-list', style: 'display:grid;gap:.8rem' });
  const edit = can('centros.edit');
  let data = [];

  const toolbar = h('div', { class: 'i18-toolbar', style: 'display:flex;align-items:center;flex-wrap:wrap;gap:.5rem;margin-bottom:.7rem' },
    q, inactive,
    edit ? h('button', { class: 'i18-btn', type: 'button', onclick: () => centerForm() }, '+ Agregar centro') : '');

  wrap.append(h('h2', {}, 'Directorio de centros de salud'), toolbar, pane, list);
  root.append(wrap);

  async function load() {
    try {
      const r = await rpc('health_center_directory', { p_org: null, p_include_inactive: inactiveChk.checked });
      data = r?.centros || [];
      draw();
    } catch (e) { list.replaceChildren(note('Error al cargar el directorio: ' + e.message, 'error')); }
  }

  function draw() {
    const term = q.value.trim().toLowerCase();
    const filtered = term ? data.filter(c => [c.name, c.city, c.center_type, c.contact_name].some(v => v && v.toLowerCase().includes(term))) : data;
    if (!filtered.length) { list.replaceChildren(note(term ? 'No se encontraron centros con esa búsqueda.' : 'No hay centros registrados todavía.', 'info')); return; }
    list.replaceChildren(...filtered.map(card));
  }

  function card(c) {
    const pills = [
      c.center_type ? h('span', { class: 'ac-pill st-ok' }, c.center_type) : '',
      c.city ? h('span', { class: 'ac-pill st-req' }, c.city) : '',
      !c.active ? h('span', { class: 'ac-pill st-none' }, 'Inactivo') : ''
    ].filter(Boolean);

    const details = [];
    if (c.address) details.push(h('div', { class: 'i18-sub' }, '📍 ', c.address));
    const contactLine = [c.phone && `📞 ${c.phone}`, c.contact_email && `✉️ ${c.contact_email}`].filter(Boolean);
    if (contactLine.length) details.push(h('div', { class: 'i18-sub' }, contactLine.join(' · ')));
    if (c.contact_name) details.push(h('div', { class: 'i18-sub' }, '👤 ', c.contact_name));
    if (c.notes) details.push(h('p', { class: 'i18-sub', style: 'margin-top:.3rem;font-style:italic' }, c.notes));

    return h('section', { class: `i18-card${c.active ? '' : ' ars-off'}`, style: 'padding:.8rem 1rem' },
      h('header', { class: 'hc-head' },
        h('div', {}, h('strong', {}, c.name), pills.length ? h('div', { style: 'display:flex;gap:.3rem;margin-top:.2rem;flex-wrap:wrap' }, ...pills) : ''),
        h('div', { class: 'i18-actions', style: 'margin:0' },
          edit ? h('button', { class: 'i18-link', type: 'button', onclick: () => centerForm(c) }, 'Editar') : '')),
      ...details);
  }

  function centerForm(c) {
    const name = h('input', { value: c?.name || '', maxlength: '200', placeholder: 'Nombre del centro de salud' });
    const taxId = h('input', { value: c?.tax_id || '', maxlength: '20', placeholder: 'RNC' });
    const centerType = h('select', {}, h('option', { value: '' }, '— Tipo —'), ...CENTER_TYPES.map(t => h('option', { value: t, selected: c?.center_type === t }, t)));
    const city = h('input', { value: c?.city || '', maxlength: '100', placeholder: 'Ej.: Santiago' });
    const address = h('input', { value: c?.address || '', maxlength: '300', placeholder: 'Dirección completa' });
    const phone = h('input', { type: 'tel', value: c?.phone || '', maxlength: '30', placeholder: '809-000-0000' });
    const contactName = h('input', { value: c?.contact_name || '', maxlength: '200', placeholder: 'Nombre del contacto' });
    const contactEmail = h('input', { type: 'email', value: c?.contact_email || '', maxlength: '200', placeholder: 'email@centro.com.do' });
    const notes = h('textarea', { rows: '2', maxlength: '500' }, c?.notes || '');
    const active = h('input', { type: 'checkbox', checked: c ? c.active : true });
    const msg = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, c ? 'Guardar cambios' : 'Crear centro');
    save.addEventListener('click', async () => {
      if (!name.value.trim()) { msg.replaceChildren(note('El nombre del centro es obligatorio.', 'error')); return; }
      save.disabled = true;
      try {
        await rpc('save_health_center', {
          p_id: c?.id || null, p_org: c?.org_id || null, p_name: name.value.trim(),
          p_tax_id: taxId.value || null, p_active: active.checked,
          p_address: address.value || null, p_city: city.value || null, p_phone: phone.value || null,
          p_contact_name: contactName.value || null, p_contact_email: contactEmail.value || null,
          p_center_type: centerType.value || null, p_notes: notes.value || null
        });
        pane.replaceChildren(note(`Centro «${name.value.trim()}» guardado.`, 'ok'));
        await load();
      } catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    pane.replaceChildren(h('section', { class: 'i18-card hc-form' },
      h('header', { class: 'hc-head' }, h('strong', {}, c ? `Editar ${c.name}` : 'Nuevo centro de salud'),
        h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')),
      h('div', { class: 'hc-grid' },
        field('hc-name', 'Nombre', name), field('hc-rnc', 'RNC', taxId), field('hc-type', 'Tipo de centro', centerType),
        field('hc-city', 'Ciudad', city), field('hc-address', 'Dirección', address), field('hc-phone', 'Teléfono', phone),
        field('hc-contact', 'Contacto', contactName), field('hc-email', 'Email de contacto', contactEmail)),
      field('hc-notes', 'Notas', notes),
      h('label', { class: 'i18-chk' }, active, ' Activo'),
      h('div', { class: 'i18-actions' }, save), msg));
    name.focus();
  }

  function field(id, label, input) {
    input.id = id;
    return h('div', { class: 'hc-field' }, h('label', { for: id }, label), input);
  }

  let dt; q.addEventListener('input', () => { clearTimeout(dt); dt = setTimeout(draw, 250); });
  inactiveChk.addEventListener('change', load);
  await load();
}
