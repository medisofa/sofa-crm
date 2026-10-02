/**
 * SOFA · Consultorio (Iteración 16): agenda diaria del médico y su asistente, cobros a pacientes privados
 * y cuadre del día. Se muestra dentro de "Trabajo de hoy" (médico y secretaria) y como pantalla propia (#/agenda).
 * Los cobros privados son solo control de caja: no generan honorario SOFA.
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, opt, formDialog, fieldError, loadingView, emptyView } from '../utils/ui.js';
import { money, todayISO, date } from '../utils/formatters.js';
import { can } from '../utils/permissions.js';
import { captureProviders, activeArs } from '../services/claims.js';
import {
  listAppointments, saveAppointment, setAppointmentStatus, listPrivateCharges, registerPrivateCharge, collectPrivateCharge,
  voidPrivateCharge, daySummary, closeDay, reopenDay, privateServices
} from '../services/consultorio.js';

export const APPT_STATUS = { programada: ['Programada', ''], confirmada: ['Confirmada', 'info'], en_espera: ['En espera', 'warn'], atendida: ['Atendida', 'ok'], no_asistio: ['No asistió', 'bad'], cancelada: ['Cancelada', ''] };
const METHODS = { efectivo: 'Efectivo', tarjeta: 'Tarjeta', transferencia: 'Transferencia', cheque: 'Cheque', pendiente: 'Pendiente (paga después)' };
const hhmm = (t) => (t ? String(t).slice(0, 5) : '—');
const mem = { provider: '', date: '' };   // se conserva durante la sesión

export async function render(main, ctx) {
  paint(main, html`<div class="page-head"><div class="t"><h2>Agenda del consultorio</h2><p>Citas del día, cobros a pacientes privados y cuadre de caja.</p></div></div><div id="ag"></div>`);
  return renderAgenda($('#ag', main), ctx);
}

/** Bloque reutilizable (Trabajo de hoy o pantalla propia) */
export async function renderAgenda(box, ctx) {
  const role = ctx.role;
  paint(box, loadingView(3));
  let providers = []; let ars = [];
  try { [providers, ars] = await Promise.all([captureProviders(), activeArs()]); } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); return; }
  if (!document.body.contains(box)) return;
  if (!providers.length) { paint(box, emptyView('Sin médicos', role === 'capturer' ? 'Tu usuario todavía no tiene médicos asignados.' : 'No hay médicos visibles para tu usuario.')); return; }
  if (!providers.some((p) => p.id === mem.provider)) mem.provider = providers[0].id;
  mem.date = mem.date || todayISO();
  const canReopen = role === 'client' || can('onboarding.override', role);

  paint(box, html`
    <div class="toolbar" style="margin:0 0 10px">
      ${providers.length > 1 ? html`<label class="sr-only" for="ag_p">Médico</label><select class="input" id="ag_p" style="width:auto">${providers.map((p) => opt(p.id, p.full_name, mem.provider))}</select>` : html`<b>${providers[0].full_name}</b>`}
      <label class="sr-only" for="ag_d">Fecha</label><input class="input" id="ag_d" type="date" value="${mem.date}" style="width:auto">
      <button class="btn primary" id="ag_new">+ Nueva cita</button><button class="btn" id="ag_walk">+ Paciente sin cita</button>
    </div>
    <div class="grid two" style="align-items:start">
      <div class="card"><h2>Agenda del día</h2><div id="ag_list"></div></div>
      <div><div class="card"><h2>Cuadre del día</h2><div id="ag_sum"></div></div>
        <div class="card" style="margin-top:14px"><h2>Cobros privados</h2><div id="ag_chg"></div></div></div>
    </div>`);
  const el = (id) => $(`#${id}`, box);
  const alive = () => document.body.contains(box);
  let appts = []; let charges = []; let summary = null;

  async function load() {
    paint(el('ag_list'), loadingView(3));
    try {
      [appts, charges, summary] = await Promise.all([listAppointments(mem.provider, mem.date), listPrivateCharges(mem.provider, mem.date), daySummary(mem.provider, mem.date)]);
    } catch (err) { if (alive()) paint(el('ag_list'), html`<div class="note bad">${friendlyError(err)}</div>`); return; }
    if (!alive()) return;
    drawList(); drawCharges(); drawSummary();
  }

  function drawList() {
    const closed = summary?.closing && !summary.closing.reopened_at;
    paint(el('ag_list'), appts.length ? html`<div class="list">${appts.map((a) => { const [l, c] = APPT_STATUS[a.status] || [a.status, '']; const open = !['atendida', 'no_asistio', 'cancelada'].includes(a.status); return html`
      <div class="li" style="align-items:flex-start">
        <b class="mono" style="width:46px">${hhmm(a.appointment_time)}</b>
        <div class="b"><div class="t1">${a.patient_name} <span class="pill ${a.payer_type === 'privado' ? 'info' : ''}">${a.payer_type === 'privado' ? 'Privado' : a.ars?.name || 'ARS'}</span></div>
          <div class="t2">${[a.reason, a.member_number && `NSS ${a.member_number}`, a.phone].filter(Boolean).join(' · ')}</div>
          ${a.service_line_id ? html`<div class="t2"><a href="#/reclamaciones/${a.service_line_id}">Ver reclamación</a></div>` : ''}</div>
        <span class="pill ${c}">${l}</span>
        ${open && !closed ? html`<div class="toolbar" style="margin:0;gap:4px;flex-wrap:wrap;justify-content:flex-end">
          ${a.status !== 'en_espera' ? html`<button class="btn sm" data-st="en_espera" data-id="${a.id}" title="El paciente llegó">Llegó</button>` : ''}
          <button class="btn sm primary" data-attend="${a.id}">Atendido</button>
          <button class="btn sm" data-edit="${a.id}">Editar</button>
          <button class="btn sm" data-st="no_asistio" data-id="${a.id}">No vino</button>
          <button class="btn sm" data-st="cancelada" data-id="${a.id}">Cancelar</button></div>` : ''}
      </div>`; })}</div>`
      : html`<p class="small muted">No hay citas para este día. Usa "Nueva cita" o "Paciente sin cita".</p>`);
  }

  function drawCharges() {
    const closed = summary?.closing && !summary.closing.reopened_at;
    const rows = charges.filter((c) => c.charge_date === mem.date || c.collected_on === mem.date);
    paint(el('ag_chg'), rows.length ? html`<div class="list">${rows.map((c) => html`<div class="li"><div class="b">
        <div class="t1"><span class="mono">${c.folio}</span> · ${c.patient_name} · <b>${money(c.amount)}</b></div>
        <div class="t2">${c.service_name}${Number(c.discount) > 0 ? ` · descuento ${money(c.discount)} (${c.discount_reason})` : ''} · ${METHODS[c.payment_method] || c.payment_method}${c.reference ? ` · ${c.reference}` : ''}</div></div>
        <span class="pill ${c.status === 'cobrado' ? 'ok' : c.status === 'pendiente' ? 'warn' : 'bad'}">${c.status === 'cobrado' ? 'Cobrado' : c.status === 'pendiente' ? 'Pendiente' : 'Anulado'}</span>
        ${!closed && c.status === 'pendiente' ? html`<button class="btn sm" data-collect="${c.id}">Cobrar</button>` : ''}
        ${!closed && c.status !== 'anulado' ? html`<button class="btn sm" data-void="${c.id}">Anular</button>` : ''}</div>`)}</div>`
      : html`<p class="small muted">Sin cobros a privados este día.</p>`);
  }

  function drawSummary() {
    const s = summary; if (!s) return;
    const ap = s.appointments || {}; const col = s.collected || {}; const cl = s.closing; const closed = cl && !cl.reopened_at;
    paint(el('ag_sum'), html`
      <dl class="kv">
        <dt>Citas</dt><dd>${ap.total} · atendidas ${ap.atendida} · no vinieron ${ap.no_asistio} · por atender ${ap.pendiente}</dd>
        <dt>Reclamaciones ARS del día</dt><dd>${s.ars_claims.count} · ${money(s.ars_claims.claimed)}</dd>
        <dt>Privados facturados</dt><dd>${s.private.count} · ${money(s.private.billed)}${Number(s.private.pending) ? html` · <span style="color:var(--warn)">pendiente ${money(s.private.pending)}</span>` : ''}</dd>
        <dt>Cobrado hoy</dt><dd><b>${money(col.total)}</b> · efectivo ${money(col.efectivo)} · tarjeta ${money(col.tarjeta)} · transferencia ${money(col.transferencia)}${Number(col.cheque) ? ` · cheque ${money(col.cheque)}` : ''}</dd>
      </dl>
      ${s.unregistered.length ? html`<div class="note warn small"><b>Atendidos sin registrar:</b> ${s.unregistered.map((u) => `${hhmm(u.time)} ${u.patient}`).join(' · ')}. Registra su reclamación o su cobro antes de cuadrar.</div>` : ''}
      ${closed ? html`<div class="note ok small">Día cuadrado el ${date(String(cl.closed_at).slice(0, 10))}${Object.values(cl.difference || {}).some((v) => Number(v)) ? html` · <b>con diferencia</b> (${Object.entries(cl.difference).filter(([, v]) => Number(v)).map(([k, v]) => `${METHODS[k]} ${money(v)}`).join(', ')}): ${cl.notes || ''}` : ' · sin diferencias'}</div>
        ${canReopen ? html`<button class="btn sm" id="ag_reopen">Reabrir el día</button>` : ''}`
        : html`<button class="btn primary" id="ag_close" ${mem.date > todayISO() ? 'disabled' : ''}>Cerrar el día (cuadre)</button>`}
      <p class="small muted">Los cobros a privados son control de caja del consultorio: no generan honorario SOFA.</p>`);
  }

  // ---------------------------------------------------------------- diálogos
  const apptDialog = (a = {}, walkIn = false) => formDialog({
    title: a.id ? 'Editar cita' : walkIn ? 'Paciente sin cita' : 'Nueva cita', submitLabel: 'Guardar', wide: true,
    body: html`<div class="form-grid">
      <div class="field"><label for="ap_t">Hora</label><input id="ap_t" name="time" type="time" value="${a.appointment_time ? hhmm(a.appointment_time) : walkIn ? new Date().toTimeString().slice(0, 5) : ''}"></div>
      <div class="field"><label for="ap_pay">Paga con *</label><select id="ap_pay" name="payer">${opt('ars', 'ARS (seguro)', a.payer_type || 'ars')}${opt('privado', 'Privado', a.payer_type)}</select></div>
      <div class="field" style="grid-column:1/-1"><label for="ap_n">Paciente *</label><input id="ap_n" name="patient" maxlength="150" value="${a.patient_name || ''}"></div>
      <div class="field"><label for="ap_ars">ARS</label><select id="ap_ars" name="ars"><option value="">Seleccione…</option>${ars.map((x) => opt(x.id, x.name, a.ars_id))}</select></div>
      <div class="field"><label for="ap_nss">NSS / afiliado</label><input id="ap_nss" name="member" maxlength="40" value="${a.member_number || ''}"></div>
      <div class="field"><label for="ap_aut">Autorización</label><input id="ap_aut" name="authorization" maxlength="60" value="${a.authorization_number || ''}"></div>
      <div class="field"><label for="ap_doc">Cédula</label><input id="ap_doc" name="doc" maxlength="20" inputmode="numeric" value="${a.patient_doc || ''}"></div>
      <div class="field"><label for="ap_ph">Teléfono</label><input id="ap_ph" name="phone" maxlength="20" inputmode="tel" value="${a.phone || ''}"></div>
      <div class="field"><label for="ap_r">Motivo</label><input id="ap_r" name="reason" maxlength="200" value="${a.reason || ''}"></div></div>`,
    onOpen: (f) => { const sync = () => { const ars_ = f.elements.payer.value === 'ars'; ['ars', 'member', 'authorization'].forEach((k) => { f.elements[k].disabled = !ars_; }); }; f.elements.payer.addEventListener('change', sync); sync(); },
    onSubmit: async (d, f) => {
      if ((d.patient || '').trim().length < 3) { fieldError(f.elements.patient, 'Mínimo 3 caracteres'); return false; }
      if (d.payer === 'ars' && !d.ars) { fieldError(f.elements.ars, 'Seleccione la ARS o marque Privado'); return false; }
      const id = await saveAppointment({ id: a.id, provider: mem.provider, date: mem.date, time: d.time, patient: d.patient.trim(), doc: d.doc, member: d.member, phone: d.phone, payer: d.payer, ars: d.ars, authorization: d.authorization, reason: d.reason });
      if (walkIn) await setAppointmentStatus(id, 'en_espera');
      return true;
    }
  });

  async function chargeDialog(a = null) {
    const services = await privateServices(mem.provider, mem.date);
    if (!services.length) { toast('Este médico no tiene tarifas privadas vigentes. Configúralas en "Tarifas privadas".', 'bad'); return false; }
    return formDialog({
      title: a ? `Cobro · ${a.patient_name}` : 'Cobro a paciente privado', submitLabel: 'Registrar cobro', wide: true,
      body: html`<div class="form-grid">
        ${a ? '' : html`<div class="field" style="grid-column:1/-1"><label for="ch_n">Paciente *</label><input id="ch_n" name="patient" maxlength="150"></div>`}
        <div class="field" style="grid-column:1/-1"><label for="ch_s">Servicio *</label><select id="ch_s" name="procedure">${services.map((s) => opt(s.procedure_id, `${s.name} · ${money(s.amount)}`))}</select></div>
        <div class="field"><label for="ch_q">Cantidad</label><input id="ch_q" name="quantity" type="number" min="1" max="99" value="1"></div>
        <div class="field"><label for="ch_m">Forma de pago *</label><select id="ch_m" name="method">${Object.entries(METHODS).map(([k, l]) => opt(k, l, 'efectivo'))}</select></div>
        <div class="field"><label for="ch_ref">Referencia</label><input id="ch_ref" name="reference" maxlength="60" placeholder="Voucher, transferencia o cheque"></div>
        <div class="field"><label for="ch_dc">Descuento (RD$)</label><input id="ch_dc" name="discount" type="number" min="0" step="0.01" value="0"></div>
        <div class="field" style="grid-column:1/-1"><label for="ch_dr">Motivo del descuento</label><input id="ch_dr" name="discountReason" maxlength="200"></div></div>
        <p id="ch_tot" class="small" aria-live="polite"></p>`,
      onOpen: (f) => {
        const upd = () => { const s = services.find((x) => x.procedure_id === f.elements.procedure.value); const t = (s?.amount || 0) * Number(f.elements.quantity.value || 1) - Number(f.elements.discount.value || 0);
          f.querySelector('#ch_tot').innerHTML = `Total a cobrar: <b>${money(t)}</b>`; f.elements.reference.disabled = ['efectivo', 'pendiente'].includes(f.elements.method.value); };
        f.addEventListener('input', upd); f.addEventListener('change', upd); upd();
      },
      onSubmit: async (d, f) => {
        if (!a && (d.patient || '').trim().length < 3) { fieldError(f.elements.patient, 'Indique el paciente'); return false; }
        if (['tarjeta', 'transferencia', 'cheque'].includes(d.method) && (d.reference || '').trim().length < 3) { fieldError(f.elements.reference, 'Indique la referencia'); return false; }
        if (Number(d.discount) > 0 && (d.discountReason || '').trim().length < 5) { fieldError(f.elements.discountReason, 'Indique el motivo del descuento'); return false; }
        return registerPrivateCharge({ provider: mem.provider, date: mem.date, patient: a ? a.patient_name : d.patient.trim(), doc: a?.patient_doc, procedure: d.procedure, quantity: Number(d.quantity || 1),
          method: d.method, reference: d.reference, discount: d.discount, discountReason: d.discountReason, appointment: a?.id || null });
      }
    });
  }

  // ---------------------------------------------------------------- eventos
  el('ag_p')?.addEventListener('change', (e) => { mem.provider = e.target.value; load(); });
  el('ag_d').addEventListener('change', (e) => { mem.date = e.target.value || todayISO(); load(); });
  el('ag_new').addEventListener('click', async () => { try { if (await apptDialog()) { toast('Cita agendada', 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
  el('ag_walk').addEventListener('click', async () => { try { if (await apptDialog({}, true)) { toast('Paciente en espera', 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
  box.addEventListener('click', async (e) => {
    const b = e.target.closest('button'); if (!b) return;
    try {
      if (b.dataset.st) { await setAppointmentStatus(b.dataset.id, b.dataset.st); toast('Cita actualizada', 'ok'); load(); }
      else if (b.dataset.edit) { if (await apptDialog(appts.find((a) => a.id === b.dataset.edit))) { toast('Cita actualizada', 'ok'); load(); } }
      else if (b.dataset.attend) {
        const a = appts.find((x) => x.id === b.dataset.attend);
        if (a.payer_type === 'ars') { location.hash = `#/captura/cita-${a.id}`; return; }   // la Captura rápida se abre prellenada y cierra la cita al guardar
        if (await chargeDialog(a)) { toast('Cobro registrado · cita atendida', 'ok'); load(); }
      } else if (b.dataset.collect) {
        const r = await formDialog({ title: 'Cobrar saldo pendiente', submitLabel: 'Cobrar',
          body: html`<div class="field"><label for="co_m">Forma de pago</label><select id="co_m" name="method">${['efectivo', 'tarjeta', 'transferencia', 'cheque'].map((k) => opt(k, METHODS[k], 'efectivo'))}</select></div>
            <div class="field"><label for="co_r">Referencia</label><input id="co_r" name="reference" maxlength="60"></div>`,
          onSubmit: async (d, f) => { if (d.method !== 'efectivo' && (d.reference || '').trim().length < 3) { fieldError(f.elements.reference, 'Indique la referencia'); return false; } return collectPrivateCharge(b.dataset.collect, d.method, d.reference); } });
        if (r) { toast('Cobrado', 'ok'); load(); }
      } else if (b.dataset.void) {
        const r = await formDialog({ title: 'Anular cobro', submitLabel: 'Anular',
          body: html`<div class="field"><label for="vo_r">Motivo (mínimo 10 caracteres) *</label><textarea id="vo_r" name="reason" rows="2" class="input"></textarea></div>`,
          onSubmit: async (d, f) => { if ((d.reason || '').trim().length < 10) { fieldError(f.elements.reason, 'Mínimo 10 caracteres'); return false; } return voidPrivateCharge(b.dataset.void, d.reason.trim()); } });
        if (r) { toast('Cobro anulado', 'ok'); load(); }
      } else if (b.id === 'ag_close') {
        const col = summary.collected;
        const r = await formDialog({ title: `Cuadre del ${date(mem.date)}`, submitLabel: 'Cerrar el día', wide: true,
          body: html`<p class="small">Cuenta el dinero y los comprobantes y escribe lo que hay realmente. El sistema lo compara con lo registrado.</p>
            <div class="table-wrap"><table class="t"><thead><tr><th>Método</th><th class="n">Registrado</th><th class="n">Contado</th></tr></thead><tbody>
            ${['efectivo', 'tarjeta', 'transferencia', 'cheque'].map((k) => html`<tr><td>${METHODS[k]}</td><td class="n">${money(col[k])}</td>
              <td class="n"><label class="sr-only" for="cu_${k}">Contado ${METHODS[k]}</label><input id="cu_${k}" name="${k}" type="number" step="0.01" min="0" value="${Number(col[k]).toFixed(2)}" style="width:130px;text-align:right"></td></tr>`)}</tbody></table></div>
            <p id="cu_dif" class="small" aria-live="polite"></p>
            <div class="field"><label for="cu_n">Notas (obligatorio si hay diferencia)</label><textarea id="cu_n" name="notes" rows="2" class="input"></textarea></div>`,
          onOpen: (f) => { const u = () => { const d = ['efectivo', 'tarjeta', 'transferencia', 'cheque'].reduce((t, k) => t + (Number(f.elements[k].value || 0) - Number(col[k])), 0);
            f.querySelector('#cu_dif').innerHTML = Math.abs(d) < 0.005 ? '<span style="color:var(--ok)">Cuadra con lo registrado</span>' : `<span style="color:var(--bad)">Diferencia total ${money(d)}</span>`; }; f.addEventListener('input', u); u(); },
          onSubmit: async (d, f) => {
            const counted = Object.fromEntries(['efectivo', 'tarjeta', 'transferencia', 'cheque'].map((k) => [k, Number(d[k] || 0)]));
            const diff = Object.keys(counted).some((k) => Math.abs(counted[k] - Number(col[k])) > 0.005);
            if (diff && (d.notes || '').trim().length < 10) { fieldError(f.elements.notes, 'Explica la diferencia (mínimo 10 caracteres)'); return false; }
            return closeDay(mem.provider, mem.date, counted, d.notes);
          } });
        if (r) { toast('Día cuadrado', 'ok'); load(); }
      } else if (b.id === 'ag_reopen') {
        const r = await formDialog({ title: 'Reabrir el día', submitLabel: 'Reabrir',
          body: html`<div class="field"><label for="re_r">Motivo (mínimo 10 caracteres) *</label><textarea id="re_r" name="reason" rows="2" class="input"></textarea></div>`,
          onSubmit: async (d, f) => { if ((d.reason || '').trim().length < 10) { fieldError(f.elements.reason, 'Mínimo 10 caracteres'); return false; } return reopenDay(summary.closing.id, d.reason.trim()); } });
        if (r) { toast('Día reabierto', 'ok'); load(); }
      }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
  return { reload: load };
}

