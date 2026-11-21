/**
 * SOFA · Episodio de hospitalización (migración 264): aviso de ingreso, tramos por área con su autorización
 * de la ARS, traslados y egreso. Lo usan el médico (en su reporte), su secretaria y el personal de SOFA.
 *
 * Mientras no haya egreso, el reporte es un AVISO de servicio prestado: el servidor no deja enviarlo para
 * reclamar. Aquí solo se muestran los botones; las reglas y los permisos viven en las funciones de Postgres
 * (hospital_episode_*), que vuelven a validar todo.
 */
import { rpc, h, note, fmtDate } from '../services/iter18.js';
import { confirmDialog } from '../utils/ui.js';

export const AREAS = { emergencia: 'Emergencia', hospitalizacion: 'Hospitalización (planta)', cirugia: 'Cirugía', uci: 'UCI' };
const ESTADO = { sin_notificar: 'Sin avisar', ingresado: 'Ingresado', egresado: 'Egresado · listo para enviar', enviado: 'Enviado para reclamar', cerrado: 'Cerrado' };
const today = () => new Date(Date.now() - new Date().getTimezoneOffset() * 6e4).toISOString().slice(0, 10);
const areaSel = (id, exclude) => h('select', { id }, Object.entries(AREAS).filter(([k]) => k !== exclude).map(([k, l]) => h('option', { value: k }, l)));
const daysTxt = (n) => (n == null ? '' : n === 1 ? '1 día' : `${n} días`);

/**
 * Bloque del episodio dentro de un reporte.
 * @param {string} reportId
 * @param {{admission_date?:string|null, onChange?:() => void}} [opt]  onChange: recargar el reporte que lo contiene
 * @returns {HTMLElement}
 */
export function episodeBlock(reportId, opt = {}) {
  const box = h('section', { class: 'i18-card hosp-episode', 'aria-live': 'polite' }, note('Cargando el episodio…'));
  const run = async (fn) => {
    try { draw(await fn()); opt.onChange?.(); }
    catch (e) { box.querySelector('.hosp-ep-msg')?.replaceChildren(note(e.message, 'error')); }
  };
  rpc('hospital_episode_get', { p_report: reportId }).then(draw).catch((e) => box.replaceChildren(note(e.message, 'error')));

  function draw(ep) {
    const msg = h('div', { class: 'hosp-ep-msg', 'aria-live': 'polite' });
    const head = h('header', {}, h('h4', {}, 'Estancia del paciente'),
      h('span', { class: `i18-badge ${ep.estado === 'ingresado' ? 'i18-esta_semana' : 'i18-proximo'}` }, ESTADO[ep.estado] || ep.estado),
      ep.dias != null ? h('span', { class: 'i18-sub' }, ` · ${daysTxt(ep.dias)}${ep.area_actual ? ` · ahora en ${AREAS[ep.area_actual]}` : ''}`) : '');
    const parts = [head];
    if (ep.estado === 'ingresado') parts.push(note('Paciente todavía ingresado: este reporte es un aviso de servicio prestado. Se envía para reclamar cuando se registre el egreso.', 'info'));
    if (ep.sin_autorizacion) parts.push(note('Falta el número de autorización de la ARS en al menos un tramo (Hospitalización, Cirugía o UCI). Regístrelo para evitar glosas.', 'warn'));

    if (ep.tramos.length) {
      parts.push(h('table', { class: 'i18-table hosp-ep-table' },
        h('thead', {}, h('tr', {}, ['Área', 'Desde', 'Hasta', 'Días', 'Autorización ARS'].map((t) => h('th', { scope: 'col' }, t)))),
        h('tbody', {}, ep.tramos.map((t) => h('tr', {},
          h('td', {}, AREAS[t.area] || t.area), h('td', {}, fmtDate(t.started_on)), h('td', {}, t.ended_on ? fmtDate(t.ended_on) : 'En curso'),
          h('td', {}, String(t.dias)), h('td', {}, authCell(t, ep.puede_mover)))))));
    }

    if (ep.puede_mover && !ep.tramos.length) {
      if (!ep.admission_date) parts.push(note('Ponga la fecha de ingreso en los datos del reporte para poder avisar el ingreso.', 'warn'));
      else {
        const area = areaSel(`ep-a-${reportId}`); const auth = h('input', { id: `ep-au-${reportId}`, maxlength: '40', placeholder: 'Opcional' });
        const go = h('button', { class: 'i18-btn', type: 'button', onclick: () => run(() => rpc('hospital_episode_notify', { p_report: reportId, p_area: area.value, p_auth: auth.value || null })) }, 'Avisar ingreso');
        parts.push(h('div', { class: 'hosp-form' }, h('label', { for: area.id }, `Área de ingreso (${fmtDate(ep.admission_date)})`, area), h('label', { for: auth.id }, 'Autorización o aviso de ingreso ARS', auth), go));
      }
    }
    if (ep.puede_mover && ep.area_actual) {
      const area = areaSel(`ep-t-${reportId}`, ep.area_actual);
      const on = h('input', { id: `ep-td-${reportId}`, type: 'date', value: today(), max: today() });
      const auth = h('input', { id: `ep-ta-${reportId}`, maxlength: '40', placeholder: 'Opcional' });
      const tr = h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => run(() => rpc('hospital_episode_transfer', { p_report: reportId, p_area: area.value, p_on: on.value || null, p_auth: auth.value || null })) }, 'Trasladar');
      const dOn = h('input', { id: `ep-dd-${reportId}`, type: 'date', value: today(), max: today() });
      const dis = h('button', { class: 'i18-btn', type: 'button', onclick: async () => {
        if (!await confirmDialog('Registrar egreso', `¿Registrar el egreso del ${fmtDate(dOn.value)}? Se cierra el tramo actual y ya no se trasladan.`, 'Registrar egreso', true)) return;
        run(() => rpc('hospital_episode_discharge', { p_report: reportId, p_on: dOn.value || null }));
      } }, 'Registrar egreso');
      parts.push(h('details', {}, h('summary', {}, 'Trasladar a otra área'),
        h('div', { class: 'hosp-form' }, h('label', { for: area.id }, 'Nueva área', area), h('label', { for: on.id }, 'Fecha del traslado', on), h('label', { for: auth.id }, 'Autorización ARS', auth), tr)));
      parts.push(h('details', {}, h('summary', {}, 'Registrar egreso'),
        h('div', { class: 'hosp-form' }, h('label', { for: dOn.id }, 'Fecha de egreso (alta)', dOn), dis)));
    }
    parts.push(msg);
    box.replaceChildren(...parts);
  }

  function authCell(t, editable) {
    if (!editable) return t.auth_number || '—';
    const id = `ep-auth-${t.id}`;
    const inp = h('input', { id, value: t.auth_number || '', maxlength: '40', size: '12', 'aria-label': `Autorización ARS del tramo ${AREAS[t.area]}` });
    const b = h('button', { class: 'i18-link', type: 'button', onclick: () => run(() => rpc('hospital_episode_set_auth', { p_stay: t.id, p_auth: inp.value })) }, 'Guardar');
    return h('span', {}, inp, ' ', b);
  }
  return box;
}

/**
 * Panel «Pacientes ingresados»: episodios avisados que todavía no se envían para reclamar.
 * @param {(id:string) => void} [onOpen]  si se da, cada fila abre el reporte; si no, el episodio se despliega ahí mismo.
 */
export function ingresadosPanel(onOpen) {
  const box = h('section', { class: 'hosp-ingresados', 'aria-live': 'polite' }, h('h3', {}, 'Pacientes ingresados'), note('Cargando…'));
  async function load() {
    let list;
    try { list = await rpc('hospital_episodes_open'); }
    catch (e) { box.replaceChildren(h('h3', {}, 'Pacientes ingresados'), note(e.message, 'error')); return; }
    const rows = list.map((ep) => {
      const quiet = ep.ultimo_movimiento ? Math.floor((Date.now() - new Date(ep.ultimo_movimiento)) / 864e5) : 0;
      const tags = [ep.estado === 'egresado' ? 'Egresado: falta enviar para reclamar' : `${daysTxt(ep.dias)} · ${AREAS[ep.area_actual] || '—'}`,
        ep.sin_autorizacion ? 'Falta autorización' : null, ep.estado === 'ingresado' && quiet >= 3 ? `${quiet} días sin novedades: confirme si ya salió` : null].filter(Boolean);
      const slot = h('div');
      const btn = h('button', { class: 'hosp-row', type: 'button', 'aria-expanded': 'false', onclick: () => {
        if (onOpen) { onOpen(ep.id); return; }
        const open = btn.getAttribute('aria-expanded') === 'true';
        btn.setAttribute('aria-expanded', String(!open));
        slot.replaceChildren(open ? '' : episodeBlock(ep.id, { onChange: load }));
      } }, h('span', {}, `${ep.patient_name} · ${ep.medico} · ${ep.centro}`), h('span', { class: 'hosp-mut' }, tags.join(' · ')));
      return h('div', {}, btn, slot);
    });
    box.replaceChildren(h('h3', {}, `Pacientes ingresados (${list.length})`),
      list.length ? h('div', { class: 'hosp-list' }, rows) : note('No hay pacientes ingresados avisados.', 'info'));
  }
  load();
  return box;
}
