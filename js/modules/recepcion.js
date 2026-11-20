/**
 * SOFA · 244 · Recepción del centro (opción C): el día completo con una columna por médico.
 * Solo aparecen los médicos de la organización del centro (lo filtra reception_day en la base de datos).
 * La Administración asigna aquí qué usuarias atienden la recepción de cada centro.
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, opt, loadingView, emptyView, confirmDialog } from '../utils/ui.js';
import { todayISO } from '../utils/formatters.js';
import { sb } from '../supabase.js';
import { receptionDay, myAgendaScopes, setAppointmentStatus, receptionStaff, setReceptionScope } from '../services/consultorio.js';
import { APPT_STATUS } from './agenda.js';

const STATUS_CLS = { programada: 'p', confirmada: 'c', en_espera: 'e', en_consulta: 'e', atendida: 'd', no_asistio: 'd', cancelada: 'd' };
const mem = { center: '', date: '' };
const toMin = (t) => { const [h, m] = String(t).split(':').map(Number); return h * 60 + (m || 0); };
const toHHMM = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
const addDays = (iso, n) => { const d = new Date(`${iso}T12:00:00`); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
const ROW = 76;   // alto de cada franja: cabe nombre, estado y el botón «Llegó» (44 px los cortaba)
/** Minutos desde ts, o null. Más de 12 h es un dato viejo (p. ej. estado de otro día): se muestra como texto. */
const minsSince = (ts) => (ts ? Math.max(0, Math.round((Date.now() - new Date(ts).getTime()) / 60000)) : null);

const waitText = (m) => (m > 720 ? 'más de 12 h' : `${m} min`);

export async function render(main, ctx) {
  const isAdmin = ['super_admin', 'admin'].includes(ctx.role);
  paint(main, html`<div class="page-head"><div class="t"><h2>Recepción del centro</h2><p>Todos los médicos de su organización en este centro, el día completo.</p></div></div><div id="rc"></div>`);
  const box = $('#rc', main);
  paint(box, loadingView(4));
  let centers = [];
  try {
    const scopes = await myAgendaScopes();
    centers = scopes.reception || [];
    if (isAdmin || ['client', 'assistant', 'operations'].includes(ctx.role)) {
      // Roles de la organización: sus centros activos (RLS de health_centers limita a su organización).
      const { data, error } = await sb().from('health_centers').select('id, name').eq('is_active', true).order('name').limit(200);
      if (error) throw error;
      const seen = new Set(centers.map((c) => c.id));
      (data || []).forEach((c) => { if (!seen.has(c.id)) centers.push(c); });
    }
  } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); return; }
  if (!document.body.contains(box)) return;
  if (!centers.length) { paint(box, emptyView('Sin recepción asignada', 'Pida al Administrador que le asigne la recepción de su centro.')); return; }
  if (!centers.some((c) => c.id === mem.center)) mem.center = centers[0].id;
  if (!mem.date) mem.date = todayISO();

  async function load() {
    paint(box, html`
      <div class="wk-bar card">
        <div class="field"><label for="rc_c">Centro</label><select id="rc_c" ${centers.length < 2 ? 'disabled' : ''}>${centers.map((c) => opt(c.id, c.name, mem.center))}</select></div>
        <div class="field"><label for="rc_d">Día</label><input id="rc_d" type="date" value="${mem.date}"></div>
        <div class="wk-nav">
          <button class="btn" type="button" data-nav="-1">‹ Día anterior</button>
          <button class="btn" type="button" data-nav="0">Hoy</button>
          <button class="btn" type="button" data-nav="1">Día siguiente ›</button>
        </div>
      </div>
      <div class="note info" role="note">Solo ve los médicos de su organización que atienden en este centro. Sus citas en otros centros aparecen como «No disponible».</div>
      <div id="rc_body">${loadingView(4)}</div>
      ${isAdmin ? html`<section class="card wk-admin" id="rc_admin" aria-label="Quién atiende la recepción"></section>` : ''}`);
    const body = $('#rc_body', box);
    let data;
    try { data = await receptionDay(mem.center, mem.date); }
    catch (err) { paint(body, html`<div class="note bad">${friendlyError(err)}</div>`); return; }
    if (!document.body.contains(body)) return;
    paintDay(body, data);
    if (isAdmin) loadAdmin();
  }

  function paintDay(body, data) {
    const provs = data.providers || [];
    if (!provs.length) { paint(body, emptyView('Sin médicos en este centro', 'Agregue el centro a los médicos en «Centros» para que aparezcan aquí.')); return; }
    const all = provs.flatMap((p) => [...p.schedule, ...p.appointments.filter((a) => a.time).map((a) => ({ start: a.time, end: toHHMM(toMin(a.time) + a.duration_min) }))]);
    const slot = Math.min(30, ...provs.flatMap((p) => p.schedule.map((s) => s.slot_min)));
    const startMin = Math.min(8 * 60, ...all.map((x) => toMin(x.start)));
    const endMin = Math.max(12 * 60, ...all.map((x) => toMin(x.end)));
    const rows = Math.ceil((endMin - startMin) / slot);
    const rowOf = (t) => Math.floor((toMin(t) - startMin) / slot) + 2;
    const spanOf = (mins) => Math.max(1, Math.ceil(mins / slot));
    const waiting = provs.flatMap((p) => p.appointments.filter((a) => a.status === 'en_espera').map((a) => ({ ...a, provider: p.full_name })))
      .sort((a, b) => String(a.status_changed_at).localeCompare(String(b.status_changed_at)));
    const pend = provs.flatMap((p) => p.appointments);
    const noElig = pend.filter((a) => a.payer_type === 'ars' && a.eligibility_status !== 'verificada' && !['cancelada', 'no_asistio', 'atendida'].includes(a.status)).length;

    paint(body, html`
      <div class="wk-wrap">
        <div class="wk-cal card" role="grid" aria-label="Citas del día por médico"
             style="grid-template-columns: 64px repeat(${provs.length}, minmax(160px, 1fr)); grid-template-rows: 52px repeat(${rows}, ${ROW}px)">
          <div class="wk-hd"></div>
          ${provs.map((p, i) => html`<div class="wk-hd" style="grid-column:${i + 2};grid-row:1">${p.full_name}<small>${p.specialty || ''}${p.specialty ? ' · ' : ''}${p.appointments.filter((a) => a.status !== 'cancelada').length} citas</small></div>`)}
          ${Array.from({ length: rows }, (_, r) => html`<div class="wk-hr" style="grid-column:1;grid-row:${r + 2}">${(r * slot) % 60 === 0 ? toHHMM(startMin + r * slot) : ''}</div>`)}
          <div class="wk-lines" style="grid-column:2 / ${provs.length + 2};grid-row:2 / ${rows + 2};background-size:100% ${ROW}px"></div>
          ${provs.map((p, i) => html`
            ${p.busy.map((b) => html`<div class="wk-blk" style="grid-column:${i + 2};grid-row:${Math.max(2, rowOf(b.start))} / span ${spanOf(toMin(b.end) - Math.max(toMin(b.start), startMin))}">${b.kind === 'bloqueo' ? 'Bloqueado' : 'No disponible'}<br><small>${b.start}–${b.end}</small></div>`)}
            ${p.appointments.filter((a) => a.time).map((a) => {
              const [label] = APPT_STATUS[a.status] || [a.status];
              const wait = a.status === 'en_espera' ? minsSince(a.status_changed_at) : null;
              return html`<div class="wk-ap ${STATUS_CLS[a.status] || 'p'}" style="grid-column:${i + 2};grid-row:${rowOf(a.time)} / span ${spanOf(a.duration_min)}">
                <b>${a.patient_name}</b><span>${a.time} · ${a.payer_type === 'ars' ? (a.ars_name || 'ARS') : 'Privado'}</span>
                <span class="pill ${a.status === 'confirmada' ? 'ok' : a.status === 'en_espera' ? 'warn' : ''}">${label}${wait != null ? ` · ${waitText(wait)}` : ''}</span>
                ${['programada', 'confirmada'].includes(a.status) ? html`<button class="btn sm" type="button" data-st="en_espera" data-id="${a.id}">Llegó</button>` : ''}
              </div>`;
            })}`)}
        </div>
        <aside class="wk-side card" aria-label="Sala de espera">
          <h3>Sala de espera</h3>
          <p class="muted">Pacientes que ya llegaron, por orden de llegada.</p>
          ${waiting.length ? waiting.map((a) => html`
            <div class="wk-row"><div class="who"><b>${a.patient_name}</b><small>${a.provider} · cita ${a.time || '—'}</small></div>
              <span class="pill ${minsSince(a.status_changed_at) >= 15 ? 'warn' : ''}">${waitText(minsSince(a.status_changed_at) ?? 0)}</span>
              <button class="btn sm" type="button" data-st="en_consulta" data-id="${a.id}">Pasar</button></div>`) : html`<p class="muted">Nadie esperando.</p>`}
          <h3>Pendientes del día</h3>
          <div class="wk-row"><span class="who">Elegibilidad por verificar</span><b>${noElig}</b></div>
          <div class="wk-row"><span class="who">Por confirmar</span><b>${pend.filter((a) => a.status === 'programada').length}</b></div>
          <div class="wk-row"><span class="who">No asistieron</span><b>${pend.filter((a) => a.status === 'no_asistio').length}</b></div>
        </aside>
      </div>`);
  }

  async function loadAdmin() {
    const el = $('#rc_admin', box);
    if (!el) return;
    let staff;
    try { staff = await receptionStaff(mem.center); } catch (err) { paint(el, html`<div class="note bad">${friendlyError(err)}</div>`); return; }
    paint(el, html`<h3>Quién atiende la recepción de este centro</h3>
      <p class="muted">Solo aparecen las usuarias activas de la organización del centro. La recepción ve a todos sus médicos en este centro y puede dar citas.</p>
      ${staff.length ? staff.map((u) => html`<div class="wk-row"><div class="who"><b>${u.full_name}</b><small>${u.role_name || u.role_code}</small></div>
        <label class="chk"><input type="checkbox" data-rec="${u.user_id}" ${u.assigned ? 'checked' : ''}> Atiende la recepción</label></div>`)
      : html`<p class="muted">No hay usuarias de secretaría en esta organización. Créelas en «Usuarios y roles».</p>`}`);
  }

  box.addEventListener('change', async (e) => {
    if (e.target.id === 'rc_c') { mem.center = e.target.value; load(); return; }
    if (e.target.id === 'rc_d' && e.target.value) { mem.date = e.target.value; load(); return; }
    if (e.target.dataset.rec) {
      const on = e.target.checked;
      try { await setReceptionScope(e.target.dataset.rec, mem.center, on, true); toast(on ? 'Recepción asignada.' : 'Recepción retirada.', 'ok'); }
      catch (err) { e.target.checked = !on; toast(friendlyError(err), 'bad'); }
    }
  });
  box.addEventListener('click', async (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.nav) { mem.date = b.dataset.nav === '0' ? todayISO() : addDays(mem.date, Number(b.dataset.nav)); load(); return; }
    if (b.dataset.st) {
      if (b.dataset.st === 'en_consulta' && !(await confirmDialog('Pasar a consulta', '¿El paciente entra ahora a consulta?', 'Pasar'))) return;
      try { await setAppointmentStatus(b.dataset.id, b.dataset.st); load(); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    }
  });
  load();
}
