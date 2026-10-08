/** SOFA · 21-A · Mensaje de seguimiento después de la cita (configuración del médico).
 *  El médico decide si se envía, a cuántos días de la cita y con qué texto. Los mensajes aparecen en «Mensajes» (cola de WhatsApp). */
import { rpc, providerOptions, h, note, guarded } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  const msg = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Seguimiento después de la cita'),
    h('p', {}, 'Cuando una cita queda como «atendida», SOFA prepara un mensaje de WhatsApp para preguntar al paciente cómo se siente. Usted decide si se envía.'), box, msg);
  const providers = await guarded(box, providerOptions);
  if (!providers) return;
  if (!providers.length) { box.replaceChildren(note('No tiene médicos asignados. Pida al Administrador que le asigne su consultorio.')); return; }

  const sel = h('select', { id: 'seg-prov' }, providers.map((p) => h('option', { value: p.id }, p.full_name)));
  const on = h('input', { type: 'checkbox', id: 'seg-on' });
  const days = h('input', { type: 'number', min: '1', max: '14', id: 'seg-days', style: 'width:5rem' });
  const txt = h('textarea', { id: 'seg-txt', rows: '4', maxlength: '600', style: 'width:100%' });
  const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar');
  const form = h('div', { class: 'i18-form' },
    h('label', { for: 'seg-prov' }, 'Médico'), sel,
    h('label', { class: 'i18-chk' }, on, ' Enviar mensaje de seguimiento'),
    h('label', { for: 'seg-days' }, 'Días después de la cita (1 a 14)'), days,
    h('label', { for: 'seg-txt' }, 'Texto (opcional). Puede usar {paciente} y {medico}. Si lo deja vacío se usa el texto sugerido.'), txt,
    save);
  box.replaceChildren(form);

  async function load() {
    msg.replaceChildren();
    try {
      const s = await rpc('followup_settings', { p_provider: sel.value });
      on.checked = !!s.enabled; days.value = s.days; txt.value = s.text || ''; txt.placeholder = s.default_text;
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); }
  }
  sel.addEventListener('change', load);
  save.addEventListener('click', async () => {
    save.disabled = true; msg.replaceChildren();
    try {
      await rpc('set_followup_settings', { p_provider: sel.value, p_enabled: on.checked, p_days: Number(days.value), p_text: txt.value.trim() || null });
      msg.replaceChildren(note(on.checked ? `Listo. Los mensajes se prepararán cada día a las 10:00 a. m. para las citas atendidas hace ${days.value} día(s).` : 'Listo. El seguimiento quedó apagado.'));
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); }
    finally { save.disabled = false; }
  });
  await load();
}
