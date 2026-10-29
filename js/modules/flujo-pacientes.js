/** SOFA · 29/10/2026 · Flujo de pacientes: tablero en vivo (Esperado → Esperando → En consulta → Atendido)
 *  de todos los médicos de un consultorio el mismo día. Reutiliza el estado de appointments.status que ya
 *  existía en Agenda; "en_consulta" es el único estado nuevo. "Atendida" sigue siendo exclusivo de la
 *  captura de la reclamación o el cobro (Agenda), no se toca desde aquí. */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, loadingView, emptyView, formDialog } from '../utils/ui.js';
import { todayISO } from '../utils/formatters.js';
import { captureProviders } from '../services/claims.js';
import { setAppointmentStatus, callAppointmentIn, flowBoard } from '../services/consultorio.js';

const REFRESH_MS = 25000;
const COLS = [
  { key: 'esperado', title: 'Esperado', match: (a) => ['programada', 'confirmada'].includes(a.status) },
  { key: 'esperando', title: 'Esperando', match: (a) => a.status === 'en_espera' },
  { key: 'consulta', title: 'En consulta', match: (a) => a.status === 'en_consulta' },
  { key: 'atendido', title: 'Atendido', match: (a) => a.status === 'atendida' }
];
const mem = { org: '', date: '' };

const minsSince = (iso) => (iso ? Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000)) : null);

export async function render(main, ctx) {
  paint(main, html`<div class="page-head"><div class="t"><h2>Flujo de pacientes</h2><p>Quién está por llegar, quién espera, quién está en consulta y quién ya fue atendido — de todos los médicos del consultorio, hoy.</p></div></div><div id="fp"></div>`);
  return renderBoard($('#fp', main), ctx);
}

async function renderBoard(box, ctx) {
  paint(box, loadingView(3));
  let providers = [];
  try { providers = await captureProviders(); } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); return; }
  if (!document.body.contains(box)) return;
  if (!providers.length) { paint(box, emptyView('Sin médicos', ctx.role === 'client' ? 'No tiene médicos registrados.' : 'Su usuario todavía no tiene médicos asignados.')); return; }
  const orgs = [...new Map(providers.map((p) => [p.organization_id, p.organizations?.legal_name || 'Consultorio'])).entries()];
  if (!orgs.some(([id]) => id === mem.org)) mem.org = orgs[0][0];
  mem.date = mem.date || todayISO();

  let timer = null;
  const stop = () => { clearTimeout(timer); window.removeEventListener('hashchange', stop); };
  window.addEventListener('hashchange', stop, { once: true });

  const draw = async () => {
    let rows = [];
    try { rows = await flowBoard(mem.org, mem.date); }
    catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); return; }
    if (!document.body.contains(box)) { stop(); return; }
    paint(box, html`
      <div class="toolbar">
        ${orgs.length > 1 ? html`<label for="fp-org">Consultorio</label><select id="fp-org">${orgs.map(([id, name]) => html`<option value="${id}" ${id === mem.org ? 'selected' : ''}>${name}</option>`)}</select>` : ''}
        <label for="fp-date">Fecha</label><input id="fp-date" type="date" value="${mem.date}">
        <span class="small muted" style="margin-left:auto">Se actualiza solo cada ${REFRESH_MS / 1000}s</span>
      </div>
      <div class="grid four flow-board">
        ${COLS.map((c) => { const items = rows.filter(c.match); return html`
          <section class="card flow-col">
            <h3>${c.title} <span class="pill">${items.length}</span></h3>
            ${items.length ? html`<div class="list">${items.map((a) => flowCard(a, c.key))}</div>` : html`<p class="small muted">Nadie aquí.</p>`}
          </section>`; })}
      </div>`);
    $('#fp-org', box)?.addEventListener('change', (e) => { mem.org = e.target.value; draw(); });
    $('#fp-date', box)?.addEventListener('change', (e) => { mem.date = e.target.value || todayISO(); draw(); });
    box.querySelectorAll('[data-arrive]').forEach((b) => b.addEventListener('click', () => act(b.dataset.arrive, () => setAppointmentStatus(b.dataset.arrive, 'en_espera'), 'Paciente registrado en espera')));
    box.querySelectorAll('[data-call]').forEach((b) => b.addEventListener('click', async () => {
      const room = await formDialog({
        title: 'Llamar a consulta', submitLabel: 'Llamar',
        body: html`<div class="field"><label for="fp-room">Sala o consultorio *</label><input id="fp-room" name="room" required maxlength="40" placeholder="Ej.: Sala 2"></div>`,
        onSubmit: async (d, form) => { if (!d.room?.trim()) { return false; } await callAppointmentIn(b.dataset.call, d.room.trim()); return true; }
      });
      if (room === true) { toast('Paciente llamado a consulta', 'ok'); draw(); }
    }));
    box.querySelectorAll('[data-back]').forEach((b) => b.addEventListener('click', () => act(b.dataset.back, () => setAppointmentStatus(b.dataset.back, 'en_espera'), 'Paciente devuelto a espera')));
    timer = setTimeout(draw, REFRESH_MS);
  };

  async function act(id, fn, okMsg) {
    try { await fn(); toast(okMsg, 'ok'); draw(); } catch (err) { toast(friendlyError(err), 'bad'); }
  }

  await draw();
}

function flowCard(a, col) {
  const wait = col === 'esperando' ? minsSince(a.status_changed_at) : col === 'consulta' ? minsSince(a.consult_started_at) : null;
  return html`<div class="li flow-card">
    <div class="b">
      <div class="t1">${a.patient}${a.time ? ` · ${a.time}` : ''}</div>
      <div class="t2">${a.doctor}${a.type ? ` · ${a.type}` : ''}${col === 'consulta' && a.room ? ` · ${a.room}` : ''}${wait != null ? ` · ${wait} min` : ''}</div>
    </div>
    ${col === 'esperado' ? html`<button class="btn sm" data-arrive="${a.id}">Llegó</button>` : ''}
    ${col === 'esperando' ? html`<button class="btn sm primary" data-call="${a.id}">Llamar a consulta</button>` : ''}
    ${col === 'consulta' ? html`<button class="btn sm" data-back="${a.id}" title="La atención se cierra al capturar la reclamación o el cobro en Agenda">Volver a espera</button>` : ''}
  </div>`;
}
export default render;
