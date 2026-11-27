/** SOFA · Consulta virtual: campos del formulario de cita y datos que comparten la agenda del día y la semana. */
import { html, raw } from './dom.js';

/** Solo enlaces https sin espacios (la base valida lo mismo, migración 278). */
export const validVisitLink = (url) => /^https:\/\/[^\s<>"]+$/.test(url || '') && url.length <= 500;
export const isVirtual = (a) => a?.modality === 'virtual';

export const visitFields = (a = {}) => html`
  <div class="field"><label for="vv_m">Modalidad</label><select class="input" id="vv_m" name="modality">
    <option value="presencial">Presencial</option><option value="virtual" ${isVirtual(a) ? raw('selected') : ''}>Virtual (cobro privado)</option></select></div>
  <div class="field"><label for="vv_l">Enlace de la videollamada (opcional)</label>
    <input id="vv_l" name="link" type="url" maxlength="500" placeholder="https://meet.google.com/…" value="${a.virtual_link || ''}"></div>
  <div class="note small" id="vv_note" role="status" style="grid-column:1/-1" hidden>La consulta virtual se cobra como privada: ninguna ARS la cubre.</div>`;

/** Virtual: ninguna ARS la cubre (27/11/2026), así que siempre es cobro privado; la base lo exige (278).
 *  Al volver a presencial se devuelve la forma de pago que había. El enlace solo se escribe cuando la cita es virtual. */
export function bindVisitFields(form) {
  let before = null;
  const sync = () => {
    const virtual = form.elements.modality.value === 'virtual';
    const payer = form.elements.payer;
    const setPayer = (value) => { if (payer.value !== value) { payer.value = value; payer.dispatchEvent(new Event('change', { bubbles: true })); } };
    form.elements.link.disabled = !virtual;
    form.querySelector('#vv_note').hidden = !virtual;
    payer.querySelector('option[value="ars"]').disabled = virtual;
    if (virtual) { before ??= payer.value; setPayer('privado'); }
    else if (before !== null) { setPayer(before); before = null; }
  };
  form.elements.modality.addEventListener('change', sync);
  sync();
}

/** Frase para el recordatorio de WhatsApp. */
export const visitReminder = (a) => (isVirtual(a)
  ? (validVisitLink(a.virtual_link) ? ` Es una consulta virtual; conéctese aquí: ${a.virtual_link}` : ' Es una consulta virtual; le enviaremos el enlace.')
  : '');
