/** Flujo del consultorio. Conserva las transiciones de Agenda y el cierre mediante captura/cobro. */
import { html, render as paint, $, raw } from '../utils/dom.js';
import { toast, friendlyError, loadingView, emptyView, formDialog, busy } from '../utils/ui.js';
import { todayISO } from '../utils/formatters.js';
import { captureProviders } from '../services/claims.js';
import { setAppointmentStatus, callAppointmentIn, flowBoard } from '../services/consultorio.js';

const REFRESH_MS = 25000;
const COLS = [
  { key: 'agendados', title: 'Agendados', empty: 'Sin pacientes agendados', match: (a) => a.status === 'programada' },
  { key: 'confirmados', title: 'Confirmados', empty: 'Sin pacientes confirmados', match: (a) => a.status === 'confirmada' },
  { key: 'esperando', title: 'En sala', empty: 'Nadie en sala de espera', match: (a) => a.status === 'en_espera' },
  { key: 'consulta', title: 'En consulta', empty: 'Ninguna consulta en curso', match: (a) => a.status === 'en_consulta' },
  { key: 'atendido', title: 'Atendidos', empty: 'Sin atenciones registradas', match: (a) => a.status === 'atendida' }
];
const mem = { org: '', date: '' };
const rdDate = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Santo_Domingo', year: 'numeric', month: '2-digit', day: '2-digit' });
let dispose = () => {};

function elapsed(iso, selectedDate) {
  if (!iso || selectedDate !== todayISO()) return '';
  const start = new Date(iso); const delta = Date.now() - start.getTime();
  if (!Number.isFinite(delta) || delta < 0) return '';
  if (rdDate.format(start) !== selectedDate) return 'Inicio registrado en fecha anterior';
  const minutes = Math.floor(delta / 60000);
  return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
}

export async function render(main, ctx) {
  dispose();
  paint(main, html`<div class="patient-flow"><div class="page-head"><div class="t"><h2>${ctx.role === 'client' ? 'Plan del día' : 'Flujo de pacientes'}</h2><p>Del registro a la atención, con el estado de cada paciente a la vista.</p></div></div><div id="fp"></div></div>`);
  return renderBoard($('#fp', main), ctx);
}

async function renderBoard(box, ctx) {
  paint(box, loadingView(3));
  let stopped = false; let timer = null; let request = 0; let rows = [];
  const stop = () => { stopped = true; request += 1; clearTimeout(timer); window.removeEventListener('hashchange', stop); };
  dispose = stop; window.addEventListener('hashchange', stop, { once: true });
  let providers;
  try { providers = await captureProviders(); }
  catch (err) { if (!stopped && document.body.contains(box)) paint(box, html`<div class="note bad" role="alert">${friendlyError(err)}</div>`); stop(); return; }
  if (stopped || !document.body.contains(box)) { stop(); return; }
  if (!providers.length) { paint(box, emptyView('Sin médicos', ctx.role === 'client' ? 'No tiene médicos registrados.' : 'Su usuario todavía no tiene médicos asignados.')); stop(); return; }
  const orgs = [...new Map(providers.map((p) => [p.organization_id, p.organizations?.legal_name || 'Consultorio'])).entries()];
  if (!orgs.some(([id]) => id === mem.org)) mem.org = orgs[0][0];
  mem.date = mem.date || todayISO();
  const readOnly = !!ctx.viewAs;
  paint(box, html`<section class="flow-controls" aria-label="Filtros del flujo de pacientes">
    <div class="flow-field"><label for="fp-org">Consultorio</label><select id="fp-org" ${orgs.length === 1 ? raw('disabled') : ''}>${orgs.map(([id, name]) => html`<option value="${id}" ${id === mem.org ? raw('selected') : ''}>${name}</option>`)}</select></div>
    <div class="flow-field"><label for="fp-date">Fecha de atención</label><input id="fp-date" type="date" value="${mem.date}"></div>
    <div class="flow-field flow-search"><label for="fp-search">Buscar en este día</label><input id="fp-search" type="search" placeholder="Paciente, médico o servicio" autocomplete="off"></div>
    <button class="btn" id="fp-refresh" type="button">Actualizar</button>
    <div class="flow-update"><span>Actualización automática cada 25 s</span><span id="fp-updated" role="status">Cargando pacientes…</span></div>
  </section>${readOnly ? html`<p class="note">Modo soporte: consulta de solo lectura.</p>` : ''}<div id="fp-error" role="alert"></div><p id="fp-summary" class="flow-summary" role="status"></p><div id="fp-board"></div><p class="flow-footnote">La atención se cierra al registrar la reclamación o el cobro en Agenda.</p>`);
  const normal = (s) => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const paintRows = () => {
    const q = normal($('#fp-search', box).value.trim());
    const filtered = rows.filter((a) => !q || normal(`${a.patient} ${a.doctor} ${a.type || ''}`).includes(q));
    const total = rows.filter((a) => COLS.some((c) => c.match(a))).length;
    const shown = filtered.filter((a) => COLS.some((c) => c.match(a))).length;
    $('#fp-summary', box).textContent = `${q ? `${shown} de ${total}` : total} pacientes en el flujo${mem.date === todayISO() ? ' de hoy' : ' de la fecha seleccionada'}${q && !shown ? ' · Sin coincidencias para esta búsqueda' : ''}.`;
    paint($('#fp-board', box), html`<div class="flow-board">${COLS.map((c) => {
      const items = filtered.filter(c.match);
      return html`<section class="flow-col flow-${c.key}" aria-labelledby="fp-${c.key}"><header class="flow-col-head"><h3 id="fp-${c.key}">${c.title}</h3><span class="flow-count" aria-label="${items.length} pacientes">${items.length}</span></header><div class="flow-patients">${items.length ? items.map((a) => flowCard(a, c.key, mem.date, readOnly)) : html`<p class="flow-empty">${q ? 'Sin coincidencias en este estado' : c.empty}</p>`}</div></section>`;
    })}</div>`);
  };
  const schedule = () => { clearTimeout(timer); if (!stopped && document.body.contains(box)) timer = setTimeout(draw, REFRESH_MS); };
  async function draw() {
    if (stopped || !document.body.contains(box)) { stop(); return; }
    clearTimeout(timer); const sequence = ++request; const org = mem.org; const selectedDate = mem.date;
    $('#fp-updated', box).textContent = 'Actualizando…';
    try {
      const result = await flowBoard(org, selectedDate);
      if (stopped || sequence !== request || !document.body.contains(box)) return;
      rows = result || []; paint($('#fp-error', box), html``); paintRows();
      $('#fp-updated', box).textContent = `Actualizado a las ${new Date().toLocaleTimeString('es-DO', { timeZone: 'America/Santo_Domingo', hour: '2-digit', minute: '2-digit' })}`;
    } catch (err) {
      if (stopped || sequence !== request || !document.body.contains(box)) return;
      paint($('#fp-error', box), html`<div class="note bad">${friendlyError(err)} Usa «Actualizar» para volver a intentar.</div>`);
      $('#fp-updated', box).textContent = 'No se pudo actualizar';
    } finally { if (!stopped && sequence === request) schedule(); }
  }
  const changeContext = () => { rows = []; paintRows(); paint($('#fp-error', box), html``); draw(); };
  $('#fp-org', box).addEventListener('change', (e) => { mem.org = e.target.value; changeContext(); });
  $('#fp-date', box).addEventListener('change', (e) => { mem.date = e.target.value || todayISO(); e.target.value = mem.date; changeContext(); });
  $('#fp-search', box).addEventListener('input', paintRows);
  $('#fp-refresh', box).addEventListener('click', (e) => busy(e.currentTarget, draw));
  $('#fp-board', box).addEventListener('click', async (e) => {
    if (readOnly) return;
    const button = e.target.closest('button'); if (!button || button.disabled) return;
    if (button.dataset.call) {
      const id = button.dataset.call;
      const result = await formDialog({ title: 'Llamar a consulta', submitLabel: 'Llamar',
        body: html`<div class="field"><label for="fp-room">Sala o consultorio *</label><input id="fp-room" name="room" required maxlength="40" placeholder="Ej.: Sala 2"></div>`,
        onSubmit: async (d) => { if (!d.room?.trim()) return false; await callAppointmentIn(id, d.room.trim()); return true; }
      });
      if (result === true && !stopped) { toast('Paciente llamado a consulta', 'ok'); await draw(); }
      return;
    }
    const id = button.dataset.arrive || button.dataset.back; if (!id) return;
    await busy(button, async () => {
      try { await setAppointmentStatus(id, 'en_espera'); if (!stopped) { toast(button.dataset.arrive ? 'Paciente registrado en espera' : 'Paciente devuelto a espera', 'ok'); await draw(); } }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });
  await draw();
}

function flowCard(a, col, selectedDate, readOnly) {
  const time = typeof a.time === 'string' && /^\d{2}:\d{2}/.test(a.time) ? a.time.slice(0, 5) : a.time;
  const wait = elapsed(col === 'esperando' ? a.status_changed_at : col === 'consulta' ? a.consult_started_at : null, selectedDate);
  return html`<article class="flow-card"><div class="flow-card-meta"><span class="flow-time">${time || 'Sin hora'}</span>${wait ? html`<span class="flow-wait">${col === 'esperando' ? 'Espera' : 'En consulta'} · ${wait}</span>` : ''}</div>
    <h4 class="flow-patient">${a.patient}</h4><div class="flow-doctor">${a.doctor}</div>${a.type ? html`<p class="flow-service">${a.type}</p>` : ''}${col === 'consulta' && a.room ? html`<p class="flow-room">Sala: ${a.room}</p>` : ''}
    ${!readOnly && ['agendados', 'confirmados'].includes(col) ? html`<button class="btn" data-arrive="${a.id}">Registrar llegada</button>` : ''}
    ${!readOnly && col === 'esperando' ? html`<button class="btn primary" data-call="${a.id}">Llamar a consulta</button>` : ''}
    ${!readOnly && col === 'consulta' ? html`<button class="btn" data-back="${a.id}" title="La atención se cierra al registrar la reclamación o el cobro en Agenda">Volver a espera</button>` : ''}
  </article>`;
}
export default render;
