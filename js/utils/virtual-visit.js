/** SOFA · Consulta virtual: campos del formulario de cita y datos que comparten la agenda del día y la semana. */
import { html, raw } from './dom.js';

/** Solo enlaces https sin espacios (la base valida lo mismo, migración 278). */
export const validVisitLink = (url) => /^https:\/\/[^\s<>"]+$/.test(url || '') && url.length <= 500;
export const isVirtual = (a) => a?.modality === 'virtual';

export const visitFields = (a = {}) => html`
  <div class="field"><label for="vv_m">Modalidad</label><select class="input" id="vv_m" name="modality">
    <option value="presencial">Presencial</option><option value="virtual" ${isVirtual(a) ? raw('selected') : ''}>Virtual (cobro privado)</option></select></div>
  <div class="field"><label for="vv_l">Enlace de la videollamada (opcional)</label>
    <input id="vv_l" name="link" type="url" maxlength="500" placeholder="https://meet.google.com/…" value="${a.virtual_link || ''}"></div>`;

/** Virtual: ninguna ARS la cubre (27/11/2026), así que siempre es cobro privado; la base lo exige (278).
 *  El enlace solo se puede escribir cuando la cita es virtual. */
export function bindVisitFields(form) {
  const sync = () => {
    const virtual = form.elements.modality.value === 'virtual';
    const payer = form.elements.payer;
    form.elements.link.disabled = !virtual;
    if (virtual && payer.value !== 'privado') { payer.value = 'privado'; payer.dispatchEvent(new Event('change', { bubbles: true })); }
    payer.querySelector('option[value="ars"]').disabled = virtual;
  };
  form.elements.modality.addEventListener('change', sync);
  sync();
}

/** Frase para el recordatorio de WhatsApp. */
export const visitReminder = (a) => (isVirtual(a)
  ? (validVisitLink(a.virtual_link) ? ` Es una consulta virtual; conéctese aquí: ${a.virtual_link}` : ' Es una consulta virtual; le enviaremos el enlace.')
  : '');
