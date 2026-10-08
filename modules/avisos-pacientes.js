/** SOFA · 23 · Avisos a pacientes (opciones del médico): control periódico y reprogramar cuando no asistió.
 *  Los mensajes se preparan cada día a las 10:30 a. m. y aparecen en «Mensajes» para enviarlos por WhatsApp con un clic. */
import { rpc, providerOptions, h, note, guarded } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  const msg = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Avisos a pacientes'),
    h('p', {}, 'Usted decide si SOFA prepara estos mensajes. Nada se envía solo: aparecen en «Mensajes» para enviarlos por WhatsApp con un clic.'), box, msg);
  const providers = await guarded(box, providerOptions);
  if (!providers) return;
  if (!providers.length) { box.replaceChildren(note('No tiene médicos asignados. Pida al Administrador que le asigne su consultorio.')); return; }

  const sel = h('select', { id: 'av-prov' }, providers.map((p) => h('option', { value: p.id }, p.full_name)));
  const cOn = h('input', { type: 'checkbox', id: 'av-c-on' });
  const cMonths = h('input', { type: 'number', min: '1', max: '24', id: 'av-c-m', style: 'width:5rem' });
  const cTxt = h('textarea', { id: 'av-c-txt', rows: '3', maxlength: '600', style: 'width:100%' });
  const nOn = h('input', { type: 'checkbox', id: 'av-n-on' });
  const nTxt = h('textarea', { id: 'av-n-txt', rows: '3', maxlength: '600', style: 'width:100%' });
  const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar');
  const gen = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Preparar avisos ahora');
  box.replaceChildren(h('div', { class: 'i18-form' },
    h('label', { for: 'av-prov' }, 'Médico'), sel,
    h('fieldset', { class: 'i18-fs' }, h('legend', {}, 'Consulta de control'),
      h('label', { class: 'i18-chk' }, cOn, ' Invitar a control al paciente que no ha vuelto'),
      h('label', { for: 'av-c-m' }, 'Meses sin volver (1 a 24)'), cMonths,
      h('label', { for: 'av-c-txt' }, 'Texto (opcional; puede usar {paciente} y {medico})'), cTxt),
    h('fieldset', { class: 'i18-fs' }, h('legend', {}, 'Paciente que no asistió'),
      h('label', { class: 'i18-chk' }, nOn, ' Ofrecer reprogramar la cita (inasistencias de los últimos 7 días sin nueva cita)'),
      h('label', { for: 'av-n-txt' }, 'Texto (opcional; puede usar {paciente} y {medico})'), nTxt),
    h('div', {}, save, ' ', gen)));

  async function load() {
    msg.replaceChildren();
    try {
      const s = await rpc('patient_notice_settings', { p_provider: sel.value });
      cOn.checked = !!s.control_enabled; cMonths.value = s.control_months; cTxt.value = s.control_text || ''; cTxt.placeholder = s.control_default;
      nOn.checked = !!s.noshow_enabled; nTxt.value = s.noshow_text || ''; nTxt.placeholder = s.noshow_default;
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); }
  }
  sel.addEventListener('change', load);
  save.addEventListener('click', async () => {
    save.disabled = true; msg.replaceChildren();
    try {
      await rpc('set_patient_notice_settings', { p_provider: sel.value, p_control_enabled: cOn.checked, p_control_months: Number(cMonths.value),
        p_control_text: cTxt.value.trim() || null, p_noshow_enabled: nOn.checked, p_noshow_text: nTxt.value.trim() || null });
      msg.replaceChildren(note('Listo. Los avisos activos se prepararán cada día a las 10:30 a. m.'));
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); }
    finally { save.disabled = false; }
  });
  gen.addEventListener('click', async () => {
    gen.disabled = true; msg.replaceChildren();
    try {
      const r = await rpc('generate_patient_notices', { p_provider: sel.value });
      msg.replaceChildren(note(`${r.control} aviso(s) de control y ${r.reprogramar} de reprogramación preparados. Envíelos desde «Mensajes».`));
    } catch (e) { msg.replaceChildren(note(e.message, 'error')); }
    finally { gen.disabled = false; }
  });
  await load();
}
