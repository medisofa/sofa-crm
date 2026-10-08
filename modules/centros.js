/** SOFA · Centros de salud del médico: catálogo por cliente y asignación de varios centros a cada médico. */
import { supabase, rpc, h, note, guarded, providerOptions } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const provSel = h('select', { id: 'i18-ce-prov' });
  let provs = [], centers = [], mine = [], primary = null;

  const nameIn = h('input', { id: 'i18-ce-name', placeholder: 'Nombre del centro', required: true });
  const rncIn = h('input', { id: 'i18-ce-rnc', placeholder: 'RNC (opcional)', inputmode: 'numeric' });
  const addBtn = h('button', { class: 'i18-btn i18-sec', type: 'submit' }, 'Agregar centro');
  const list = h('div', { class: 'i18-list' });
  const saveBtn = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar centros del médico');

  const prov = () => provs.find((p) => p.id === provSel.value);
  async function load() {
    if (!provSel.value) return;
    const org = prov().organization_id;
    const c = await supabase.from('health_centers').select('id, name, tax_id').eq('organization_id', org).eq('is_active', true).order('name');
    if (c.error) throw new Error(c.error.message);
    centers = c.data;
    const m = await rpc('provider_centers_of', { p_provider: provSel.value });
    mine = m.map((x) => x.id); primary = (m.find((x) => x.primary) || {}).id || null;
    paint();
  }
  function paint() {
    list.replaceChildren(...(centers.length ? centers.map((c) => {
      const chk = h('input', { type: 'checkbox', checked: mine.includes(c.id) });
      const pri = h('input', { type: 'radio', name: 'i18-ce-primary', checked: primary === c.id, disabled: !mine.includes(c.id) });
      chk.addEventListener('change', () => { mine = chk.checked ? [...new Set([...mine, c.id])] : mine.filter((x) => x !== c.id); if (!chk.checked && primary === c.id) primary = null; pri.disabled = !chk.checked; });
      pri.addEventListener('change', () => { primary = c.id; });
      return h('div', { class: 'i18-card' }, h('label', {}, chk, ' ', h('strong', {}, c.name), c.tax_id ? ` · RNC ${c.tax_id}` : ''), h('label', { class: 'i18-sub' }, pri, ' Principal'));
    }) : [note('Este cliente aún no tiene centros. Agregue el primero arriba.')]));
  }
  const form = h('form', { class: 'i18-form', novalidate: true }, nameIn, rncIn, addBtn);
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault(); out.replaceChildren();
    try {
      await rpc('save_health_center', { p_id: null, p_org: prov().organization_id, p_name: nameIn.value, p_tax_id: rncIn.value || null, p_active: true });
      form.reset(); await load();
    } catch (e) { out.replaceChildren(note(e.message, 'error')); }
  });
  saveBtn.addEventListener('click', async () => {
    out.replaceChildren(); saveBtn.disabled = true;
    try { await rpc('set_provider_centers', { p_provider: provSel.value, p_centers: mine, p_primary: primary }); out.replaceChildren(note('Centros del médico guardados.')); }
    catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { saveBtn.disabled = false; }
  });
  provSel.addEventListener('change', () => guarded(out, load));

  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Centros de salud del médico'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Médico', provSel)), form, list, saveBtn, out));
  await guarded(out, async () => {
    provs = await providerOptions();
    provSel.replaceChildren(...provs.map((p) => h('option', { value: p.id }, p.full_name)));
    await load(); return true;
  });
}
export default render;
export const mount = render;
