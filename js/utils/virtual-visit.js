/** SOFA · Consulta virtual: campos del formulario de cita y datos que comparten la agenda del día y la semana. */
import { html, raw } from './dom.js';

/** Solo enlaces https sin espacios (la base valida lo mismo, migración 278). */
export const validVisitLink = (url) => /^https:\/\/[^\s<>"]+$/.test(url || '') && url.length <= 500;
export const isVirtual = (a) => a?.modality === 'virtual';

export const visitFields = (a = {}) => html`
  <div class="field"><label for="vv_m">Modalidad</label><select class="input" id="vv_m" name="modality">
    <option value="presencial">Presencial</option><option value="virtual" ${isVirtual(a) ? raw('selected') : ''}>Virtual</option></select></div>
  <div class="field"><label for="vv_l">Enlace de la videollamada (opcional)</label>
    <input id="vv_l" name="link" type="url" maxlength="500" placeholder="https://meet.google.com/…" value="${a.virtual_link || ''}"></div>`;

/** El enlace solo se puede escribir cuando la cita es virtual. */
export function bindVisitFields(form) {
  const sync = () => { form.elements.link.disabled = form.elements.modality.value !== 'virtual'; };
  form.elements.modality.addEventListener('change', sync);
  sync();
}

/** Frase para el recordatorio de WhatsApp. */
export const visitReminder = (a) => (isVirtual(a)
  ? (validVisitLink(a.virtual_link) ? ` Es una consulta virtual; conéctese aquí: ${a.virtual_link}` : ' Es una consulta virtual; le enviaremos el enlace.')
  : '');
