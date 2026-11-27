/**
 * SOFA · 244 · Agenda de la semana por médico y centro (opción B).
 * La secretaria ve la semana del médico en SU centro: huecos libres según el horario, sus citas, y como
 * «No disponible» las horas en que el médico está en otro centro (sin paciente ni nombre del centro: lo
 * garantiza agenda_week en la base de datos, no esta pantalla).
 * A la derecha: las citas del día siguiente por confirmar, con WhatsApp gratuito (wa.me) y «Confirmó».
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, opt, formDialog, fieldError, loadingView, emptyView, confirmDialog } from '../utils/ui.js';
import { todayISO } from '../utils/formatters.js';
import { captureProviders, activeArs } from '../services/claims.js';
import { agendaWeek, myAgendaScopes, saveAppointment, setAppointmentStatus, setProviderSchedule,
  calendarFeedStatus, calendarFeedCreate, calendarFeedRevoke, CALENDAR_FEED_URL } from '../services/consultorio.js';
import { dateTime } from '../utils/formatters.js';
import { openDay } from './agenda.js';
import { APPT_STATUS, STATUS_CLS } from '../utils/appointment-status.js';
import { freeSlots, toMin, toHHMM, isoDow } from '../utils/agenda-slots.js';
import { visitFields, bindVisitFields, validVisitLink, isVirtual, visitReminder } from '../utils/virtual-visit.js';

const DIAS = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const DIAS_LARGOS = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
const mem = { provider: '', center: '', from: '', day: '' };

const addDays = (iso, n) => { const d = new Date(`${iso}T12:00:00`); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
const mondayOf = (iso) => addDays(iso, 1 - isoDow(iso));
const dayLabel = (iso) => `${DIAS[isoDow(iso) - 1]} ${Number(iso.slice(8, 10))}`;

/** Igual que agenda.js: RD local de 10 dígitos → +1. */
function waNumber(raw) {
  const d = String(raw || '').replace(/\D+/g, '');
  if (d.length === 10 && /^(809|829|849)/.test(d)) return `1${d}`;
  return d;
}

export async function render(main, ctx) {
  paint(main, html`<div class="page-head"><div class="t"><h2>Agenda de la semana</h2><p>Huecos libres, citas y confirmaciones del médico en su centro.</p></div>
    <div class="actions"><a class="btn" href="#/agenda">Ver el día</a></div></div><div id="wk"></div>`);
  const box = $('#wk', main);
  paint(box, loadingView(4));
  let providers = []; let scopes = { centers_by_provider: {}, reception: [] }; let ars = [];
  try { [providers, scopes, ars] = await Promise.all([captureProviders(), myAgendaScopes(), activeArs()]); }
  catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); return; }
  if (!document.body.contains(box)) return;
  providers = providers.filter((p) => (scopes.centers_by_provider || {})[p.id]?.length);
  if (!providers.length) {
    paint(box, emptyView('Sin médicos con centro', 'Para usar la semana, el médico necesita al menos un centro en «Centros», y usted acceso a su agenda en ese centro.'));
    return;
  }
  if (!providers.some((p) => p.id === mem.provider)) mem.provider = providers[0].id;
  if (!mem.from) mem.from = mondayOf(todayISO());
  let lastData = { appointments: [] };
  const canEditSchedule = ['super_admin', 'admin', 'client', 'assistant'].includes(ctx.role);
  const canCalendar = ['super_admin', 'admin', 'client'].includes(ctx.role);   // la base valida además que sea su médico (calendar_feed_can)

  async function load() {
    const centers = scopes.centers_by_provider[mem.provider] || [];
    if (!centers.some((c) => c.id === mem.center)) mem.center = centers[0]?.id || '';
    paint(box, html`
      <div class="wk-bar card">
        <div class="field"><label for="wk_p">Médico</label><select id="wk_p">${providers.map((p) => opt(p.id, p.full_name, mem.provider))}</select></div>
        <div class="field"><label for="wk_c">Centro</label><select id="wk_c" ${centers.length < 2 ? 'disabled' : ''}>${centers.map((c) => opt(c.id, c.name, mem.center))}</select></div>
        <div class="wk-nav">
          <button class="btn" type="button" data-nav="-7">‹ Semana anterior</button>
          <button class="btn" type="button" data-nav="0">Esta semana</button>
          <button class="btn" type="button" data-nav="7">Semana siguiente ›</button>
          ${canEditSchedule ? html`<button class="btn" type="button" data-schedule>Horario</button>` : ''}
          ${canCalendar ? html`<button class="btn" type="button" data-calendar>Calendario en mi teléfono</button>` : ''}
        </div>
      </div>
      <div id="wk_body">${loadingView(4)}</div>`);
    const body = $('#wk_body', box);
    let data;
    try { data = await agendaWeek(mem.provider, mem.center, mem.from, 7); }
    catch (err) { paint(body, html`<div class="note bad">${friendlyError(err)}</div>`); return; }
    if (!document.body.contains(body)) return;
    paintWeek(body, data, centers);
  }

  function paintWeek(body, data, centers) {
    lastData = data;
    const days = Array.from({ length: 7 }, (_, i) => addDays(mem.from, i));
    const sched = data.schedule || [];
    const slot = Math.min(...sched.map((s) => s.slot_min), 30) || 30;
    const startMin = Math.min(8 * 60, ...sched.map((s) => toMin(s.start)), ...data.appointments.filter((a) => a.time).map((a) => toMin(a.time)));
    const endMin = Math.max(12 * 60, ...sched.map((s) => toMin(s.end)), ...data.appointments.filter((a) => a.time).map((a) => toMin(a.time) + a.duration_min));
    const rows = Math.ceil((endMin - startMin) / slot);
    const rowOf = (t) => Math.floor((toMin(t) - startMin) / slot) + 2;
    const spanOf = (mins) => Math.max(1, Math.ceil(mins / slot));
    const showDays = days.filter((d, i) => i < 5 || sched.some((s) => s.weekday === isoDow(d)) || data.appointments.some((a) => a.date === d));

    // Libre = dentro del horario y sin cita ni bloqueo encima.
    const free = showDays.flatMap((d) => freeSlots(data, d).map((time) => ({ date: d, time })));

    const tomorrow = addDays(todayISO(), 1);
    const toConfirm = data.appointments.filter((a) => a.date === tomorrow && a.status === 'programada');
    const tomorrowAll = data.appointments.filter((a) => a.date === tomorrow && !['cancelada'].includes(a.status));
    const centerName = (centers.find((c) => c.id === mem.center) || {}).name || '';

    if (!showDays.includes(mem.day)) mem.day = showDays.includes(todayISO()) ? todayISO() : showDays[0];
    const eligPending = (a) => a.payer_type === 'ars' && a.eligibility_status !== 'verificada' && !['cancelada', 'no_asistio', 'atendida'].includes(a.status);
    const joinable = (a) => isVirtual(a) && validVisitLink(a.virtual_link) && !['cancelada', 'no_asistio'].includes(a.status);

    paint(body, html`
      <div class="wk-wrap">
        <div class="wk-col">
        <div class="wk-legend" aria-label="Colores de la agenda">${['programada', 'confirmada', 'en_espera', 'atendida'].map((s) => html`<span class="pill ${APPT_STATUS[s][1]}">${APPT_STATUS[s][0]}</span>`)}
          <span class="pill warn">⚠ Eleg. = elegibilidad sin verificar</span></div>
        <div class="wk-cal wk-week card" role="grid" aria-label="Semana de citas en ${centerName}"
             style="grid-template-columns: 64px repeat(${showDays.length}, minmax(0, 1fr)); grid-template-rows: 40px repeat(${rows}, 64px)">
          <div class="wk-hd"></div>
          ${showDays.map((d, i) => html`<div class="wk-hd ${d === todayISO() ? 'today' : ''}" style="grid-column:${i + 2};grid-row:1">${dayLabel(d)}</div>`)}
          ${Array.from({ length: rows }, (_, r) => html`<div class="wk-hr" style="grid-column:1;grid-row:${r + 2}">${(r * slot) % 60 === 0 || slot >= 60 ? toHHMM(startMin + r * slot) : ''}</div>`)}
          <div class="wk-lines" style="grid-column:2 / ${showDays.length + 2};grid-row:2 / ${rows + 2};background-size:100% 64px"></div>
          ${(data.busy || []).filter((b) => showDays.includes(b.date)).map((b) => html`
            <div class="wk-blk" style="grid-column:${showDays.indexOf(b.date) + 2};grid-row:${Math.max(2, rowOf(b.start))} / span ${spanOf(toMin(b.end) - Math.max(toMin(b.start), startMin))}">
              ${b.kind === 'bloqueo' ? `Bloqueado${b.reason ? ` · ${b.reason}` : ''}` : 'No disponible'}<br><small>${b.start}–${b.end}</small></div>`)}
          ${free.filter((f) => showDays.includes(f.date)).map((f) => html`
            <button class="wk-free" type="button" data-free="${f.date}|${f.time}" style="grid-column:${showDays.indexOf(f.date) + 2};grid-row:${rowOf(f.time)}"
              aria-label="Agendar el ${dayLabel(f.date)} a las ${f.time}">+ ${f.time}</button>`)}
          ${data.appointments.filter((a) => a.time && showDays.includes(a.date)).map((a) => {
            const [label] = APPT_STATUS[a.status] || [a.status];
            return html`<div class="wk-ap ${STATUS_CLS[a.status] || 'p'}" style="grid-column:${showDays.indexOf(a.date) + 2};grid-row:${rowOf(a.time)} / span ${spanOf(a.duration_min)}"
                title="${a.time} · ${a.patient_name} · ${label} · ${a.payer_type === 'ars' ? (a.ars_name || 'ARS') : 'Privado'}">
              <b>${a.patient_name}</b><span class="wk-line">${(toMin(a.time) - startMin) % slot ? `${a.time} · ` : ''}${label}</span>
              ${joinable(a) ? html`<span class="wk-line"><a href="${a.virtual_link}" target="_blank" rel="noopener noreferrer" title="Entrar a la consulta virtual">Virtual ↗</a></span>`
                : isVirtual(a) ? html`<span class="wk-line">Virtual</span>` : eligPending(a) ? html`<span class="wk-line">⚠ Eleg.</span>` : ''}
            </div>`;
          })}
        </div>
        ${dayList(data, showDays, free)}
        </div>
        <aside class="wk-side card" aria-label="Confirmaciones de mañana">
          <h3>${DIAS_LARGOS[isoDow(tomorrow) - 1]} · por confirmar</h3>
          <p class="muted">${tomorrowAll.length ? `${toConfirm.length} de ${tomorrowAll.length} sin confirmar.` : 'No hay citas mañana en esta semana.'}
            Envíe el recordatorio y marque cuando el paciente responda.</p>
          ${tomorrowAll.map((a) => html`
            <div class="wk-row">
              <div class="who"><b>${a.patient_name}</b><small>${a.time || 'Sin hora'}${a.phone ? ` · ${a.phone}` : ''}</small></div>
              ${a.status === 'programada'
                ? html`${a.phone ? html`<button class="btn sm" type="button" data-wa="${a.id}">WhatsApp</button>` : html`<span class="pill">Sin teléfono</span>`}
                       <button class="btn sm" type="button" data-ok="${a.id}">Confirmó</button>`
                : html`<span class="pill ${(APPT_STATUS[a.status] || [])[1] || ''}">${(APPT_STATUS[a.status] || [a.status])[0]}</span>`}
            </div>`)}
          <div class="wk-kpi">
            <div><b>${data.appointments.filter((a) => !['cancelada', 'no_asistio'].includes(a.status)).length}</b><small>citas</small></div>
            <div><b>${free.length}</b><small>huecos libres</small></div>
            <div><b>${data.appointments.filter((a) => a.payer_type === 'ars' && a.eligibility_status !== 'verificada' && !['cancelada', 'no_asistio', 'atendida'].includes(a.status)).length}</b><small>sin elegibilidad</small></div>
          </div>
          ${!sched.length ? html`<div class="note warn">Este médico no tiene horario en este centro, por eso no se ven huecos libres. ${canEditSchedule ? 'Defínalo con el botón «Horario».' : 'Pida al médico que lo defina.'}</div>` : ''}
        </aside>
      </div>`);
  }

  /** Celular: un día a la vez. Las acciones de cada cita están en la agenda de ese día. */
  function dayList(data, showDays, free) {
    const day = mem.day;
    const items = [
      ...data.appointments.filter((a) => a.date === day && !['cancelada', 'no_asistio'].includes(a.status)).map((a) => ({ time: a.time || '', a })),
      ...(data.busy || []).filter((b) => b.date === day).map((b) => ({ time: b.start, b })),
      ...free.filter((f) => f.date === day).map((f) => ({ time: f.time }))
    ].sort((x, y) => x.time.localeCompare(y.time));
    return html`<div class="wk-mobile">
      <div class="wk-days" role="group" aria-label="Elegir el día">${showDays.map((d) => html`<button class="btn ${d === day ? 'primary' : ''}" type="button" data-day="${d}" aria-pressed="${d === day ? 'true' : 'false'}">${dayLabel(d)}</button>`)}</div>
      <div class="card">${items.length ? items.map(({ time, a, b }) => {
        if (b) return html`<div class="ag-row"><b class="mono">${b.start}</b><div class="ag-info muted">${b.kind === 'bloqueo' ? `Bloqueado${b.reason ? ` · ${b.reason}` : ''}` : 'No disponible'} hasta las ${b.end}</div></div>`;
        if (!a) return html`<div class="ag-row"><b class="mono">${time}</b><div class="ag-act"><button class="btn" type="button" data-free="${day}|${time}">+ Agendar ${time}</button></div></div>`;
        const [label, cls] = APPT_STATUS[a.status] || [a.status, ''];
        return html`<div class="ag-row"><b class="mono">${a.time || 'Sin hora'}</b>
          <div class="ag-info"><div class="t1">${a.patient_name} <span class="pill">${a.payer_type === 'ars' ? (a.ars_name || 'ARS') : 'Privado'}</span>
            ${isVirtual(a) ? html`<span class="pill info">Virtual</span>` : ''}${a.payer_type === 'ars' && a.eligibility_status !== 'verificada' && a.status !== 'atendida' ? html`<span class="pill warn">⚠ Elegibilidad sin verificar</span>` : ''}</div>
            ${a.phone ? html`<div class="t2"><a href="tel:${a.phone}">${a.phone}</a></div>` : ''}</div>
          <span class="pill ag-status ${cls}">${label}</span>
          <div class="ag-act">${isVirtual(a) && validVisitLink(a.virtual_link) ? html`<a class="btn primary" href="${a.virtual_link}" target="_blank" rel="noopener noreferrer">Entrar a la consulta virtual</a>` : ''}
            <button class="btn" type="button" data-open="${day}" aria-label="Abrir en el día la cita de ${a.patient_name}">Abrir en el día</button></div></div>`;
      }) : html`<p class="small muted">Sin citas ni horario este día.</p>`}</div>
    </div>`;
  }

  async function newAppointment(date, time) {
    const saved = await formDialog({
      title: `Nueva cita · ${dayLabel(date)} a las ${time}`,
      body: html`<div class="form-grid">
        <div class="field"><label for="na_n">Paciente *</label><input id="na_n" name="patient" required minlength="3" autocomplete="off"></div>
        <div class="field"><label for="na_t">Teléfono (WhatsApp)</label><input id="na_t" name="phone" inputmode="tel" placeholder="809-555-0000"></div>
        <div class="field"><label for="na_doc">Cédula</label><input id="na_doc" name="doc" inputmode="numeric"></div>
        <div class="field"><label for="na_p">Paga</label><select id="na_p" name="payer">${opt('privado', 'Privado')}${opt('ars', 'ARS')}</select></div>
        <div class="field"><label for="na_a">ARS</label><select id="na_a" name="ars"><option value="">—</option>${ars.map((a) => opt(a.id, a.name))}</select></div>
        <div class="field"><label for="na_m">Número de afiliado</label><input id="na_m" name="member"></div>
        <div class="field"><label for="na_r">Motivo</label><input id="na_r" name="reason" placeholder="Consulta, control, procedimiento…"></div>
        <div class="field"><label for="na_d">Duración (minutos)</label><input id="na_d" name="duration" type="number" min="5" max="480" step="5" value="30"></div>
        ${visitFields()}
      </div>`,
      submitLabel: 'Agendar',
      onOpen: bindVisitFields,
      onSubmit: async (d, f) => {
        if ((d.patient || '').trim().length < 3) { fieldError(f.elements.patient, 'Escriba el nombre del paciente'); return false; }
        if (d.payer === 'ars' && !d.ars) { fieldError(f.elements.ars, 'Elija la ARS, o marque el paciente como privado'); return false; }
        if (d.modality === 'virtual' && (d.link || '').trim() && !validVisitLink(d.link.trim())) { fieldError(f.elements.link, 'Pegue el enlace completo, empezando por https://'); return false; }
        return saveAppointment({ modality: d.modality, link: d.link, provider: mem.provider, center: mem.center, date, time, patient: d.patient.trim(), phone: d.phone, doc: d.doc,
          payer: d.payer, ars: d.ars, member: d.member, reason: d.reason, duration: d.duration });
      }
    });
    if (saved) { toast('Cita agendada.', 'ok'); load(); }
  }

  async function editSchedule() {
    const data = await agendaWeek(mem.provider, mem.center, mem.from, 1).catch(() => ({ schedule: [] }));
    const byDay = Object.fromEntries((data.schedule || []).map((s) => [s.weekday, s]));
    const saved = await formDialog({
      title: 'Horario del médico en este centro', wide: true,
      body: html`<p class="muted">Marque los días que atiende aquí. Un mismo día no puede chocar con su horario en otro centro.</p>
        <div class="wk-sched">${DIAS_LARGOS.map((n, i) => {
          const s = byDay[i + 1];
          return html`<div class="wk-sched-row">
            <label class="chk"><input type="checkbox" name="on${i + 1}" ${s ? 'checked' : ''}> ${n}</label>
            <label>Desde <input type="time" name="s${i + 1}" value="${s?.start || '08:00'}"></label>
            <label>Hasta <input type="time" name="e${i + 1}" value="${s?.end || '12:00'}"></label>
            <label>Cita de <input type="number" name="m${i + 1}" min="5" max="240" step="5" value="${s?.slot_min || 30}"> min</label>
          </div>`;
        })}</div>`,
      submitLabel: 'Guardar horario',
      onSubmit: async (d) => {
        const rows = [1, 2, 3, 4, 5, 6, 7].filter((w) => d[`on${w}`]).map((w) => ({ weekday: w, start: d[`s${w}`], end: d[`e${w}`], slot_min: Number(d[`m${w}`]) || 30 }));
        return setProviderSchedule(mem.provider, mem.center, rows);
      }
    });
    if (saved) { toast('Horario guardado.', 'ok'); load(); }
  }

  /** 260 · Calendario del médico: el enlace privado se muestra UNA vez, al crearlo. */
  async function calendarDialog() {
    const prov = providers.find((p) => p.id === mem.provider);
    let st;
    try { st = await calendarFeedStatus(mem.provider); } catch (err) { toast(friendlyError(err), 'bad'); return; }
    const d = document.createElement('dialog');
    d.className = 'dlg'; d.style.width = 'min(640px, 96vw)'; d.setAttribute('aria-labelledby', 'cal-t');
    const paintCal = (token) => {
      const https = token ? `${CALENDAR_FEED_URL}?t=${token}` : '';
      const webcal = https.replace(/^https:/, 'webcal:');
      paint(d, html`<div class="dh" id="cal-t">Calendario en mi teléfono · ${prov?.full_name || ''}</div>
        <div class="db">
          <p>Sus citas aparecen en el calendario de su teléfono (iPhone, Google Calendar u Outlook), con un aviso 30 minutos antes.
             Se actualizan solas cuando la secretaria agenda, mueve o cancela.</p>
          <div class="note info">Por privacidad, el calendario muestra solo las <b>iniciales</b> del paciente, el motivo y el centro. Nunca el nombre completo, la cédula ni el teléfono.</div>
          ${token ? html`
            <div class="note warn" role="alert"><b>Copie el enlace ahora:</b> por seguridad no se puede volver a mostrar. Si lo pierde, cree uno nuevo.</div>
            <div class="field"><label for="cal_w">iPhone u Outlook (toque para suscribirse)</label>
              <div class="wk-nav"><input id="cal_w" readonly value="${webcal}" style="flex:1;min-width:0"><a class="btn" href="${webcal}">Abrir</a><button class="btn" type="button" data-copy="cal_w">Copiar</button></div></div>
            <div class="field"><label for="cal_h">Google Calendar (Otros calendarios › Desde URL)</label>
              <div class="wk-nav"><input id="cal_h" readonly value="${https}" style="flex:1;min-width:0"><button class="btn" type="button" data-copy="cal_h">Copiar</button></div></div>
            <p class="muted">Google Calendar puede tardar varias horas en mostrar cambios; el iPhone se actualiza cada hora.</p>`
          : html`<p><b>Estado:</b> ${st.active ? `Activo desde ${dateTime(st.created_at)}${st.last_access_at ? ` · último uso ${dateTime(st.last_access_at)}` : ' · todavía no se ha usado'}` : 'Sin enlace activo.'}</p>
                 ${st.active ? html`<p class="muted">Si cambió de teléfono o cree que alguien más tiene el enlace, revóquelo o cree uno nuevo (el anterior deja de funcionar).</p>` : ''}`}
        </div>
        <div class="df">
          ${st.active && !token ? html`<button class="btn" type="button" data-revoke>Revocar enlace</button>` : ''}
          ${!token ? html`<button class="btn primary" type="button" data-create>${st.active ? 'Crear enlace nuevo' : 'Crear enlace'}</button>` : ''}
          <button class="btn" type="button" data-close>Cerrar</button>
        </div>`);
    };
    paintCal(null);
    d.addEventListener('click', async (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      if (b.hasAttribute('data-close')) { d.close(); return; }
      if (b.dataset.copy) {
        const inp = d.querySelector(`#${b.dataset.copy}`);
        try { await navigator.clipboard.writeText(inp.value); toast('Enlace copiado.', 'ok'); } catch { inp.select(); toast('Seleccione el enlace y cópielo.', ''); }
        return;
      }
      if (b.hasAttribute('data-create')) {
        if (st.active && !(await confirmDialog('Crear enlace nuevo', 'El enlace anterior dejará de funcionar y tendrá que suscribirse de nuevo. ¿Continuar?', 'Crear enlace nuevo'))) return;
        try { const token = await calendarFeedCreate(mem.provider); st = { active: true }; paintCal(token); }
        catch (err) { toast(friendlyError(err), 'bad'); }
        return;
      }
      if (b.hasAttribute('data-revoke')) {
        if (!(await confirmDialog('Revocar enlace', 'El calendario dejará de actualizarse en todos los teléfonos donde esté suscrito. ¿Continuar?', 'Revocar', true))) return;
        try { await calendarFeedRevoke(mem.provider); st = await calendarFeedStatus(mem.provider); paintCal(null); toast('Enlace revocado.', 'ok'); }
        catch (err) { toast(friendlyError(err), 'bad'); }
      }
    });
    d.addEventListener('close', () => d.remove());
    document.body.appendChild(d);
    d.showModal();
  }

  box.addEventListener('change', (e) => {
    if (e.target.id === 'wk_p') { mem.provider = e.target.value; mem.center = ''; load(); }
    if (e.target.id === 'wk_c') { mem.center = e.target.value; load(); }
  });
  box.addEventListener('click', async (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.nav) { mem.from = b.dataset.nav === '0' ? mondayOf(todayISO()) : addDays(mem.from, Number(b.dataset.nav)); load(); return; }
    if (b.hasAttribute('data-schedule')) { editSchedule(); return; }
    if (b.hasAttribute('data-calendar')) { calendarDialog(); return; }
    if (b.dataset.day) { mem.day = b.dataset.day; paintWeek($('#wk_body', box), lastData, scopes.centers_by_provider[mem.provider] || []); return; }
    if (b.dataset.open) { openDay(mem.provider, b.dataset.open); return; }
    if (b.dataset.free) { const [d, t] = b.dataset.free.split('|'); newAppointment(d, t); return; }
    if (b.dataset.wa) {
      const a = lastData.appointments.find((x) => x.id === b.dataset.wa);
      const num = waNumber(a?.phone);
      if (!num) { toast('El paciente no tiene teléfono registrado. Agréguelo en la cita.', 'bad'); return; }
      const prov = providers.find((p) => p.id === mem.provider);
      const nombre = (a.patient_name || '').split(/\s+/).slice(0, 2).join(' ');
      const texto = `Hola ${nombre}, le recordamos su cita con ${prov?.full_name || 'su médico'} mañana a las ${a.time || ''}. Por favor confirme su asistencia respondiendo a este mensaje. Gracias.${visitReminder(a)}`;
      window.open(`https://wa.me/${num}?text=${encodeURIComponent(texto)}`, '_blank', 'noopener');
      return;
    }
    if (b.dataset.ok) {
      try { await setAppointmentStatus(b.dataset.ok, 'confirmada'); toast('Cita confirmada.', 'ok'); load(); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    }
  });
  load();
}
