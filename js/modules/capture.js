/**
 * SOFA · Captura rápida de reclamaciones (Iteración 12, §8, §9, §10 y §18).
 * Flujo: Médico → ARS → fecha → paciente / NSS / autorización → servicio contratado
 *        → SIMON + CUPS + tarifa automáticos → Guardar y registrar siguiente.
 * La secretaria nunca escribe códigos ni tarifas cuando existe contrato vigente.
 * Todas las reglas se vuelven a verificar en PostgreSQL (public.capture_claim).
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, opt, busy, confirmDialog, fieldError, emptyView, formDialog } from '../utils/ui.js';
import { money, date, todayISO, dateTime } from '../utils/formatters.js';
import { claimStatus, CARE_MODES, DISCREPANCY_STATUS } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';
import {
  captureProviders, activeArs, contractedServices, searchCatalog, patientLookup, captureClaim, myRecentClaims
} from '../services/claims.js';

/** Se conserva entre visitas dentro de la misma sesión: médico, ARS, fecha y clínica */
const memory = { provider: '', ars: '', date: '', clinic: '', careMode: 'ambulatorio' };
const pct = (a, b) => (b ? Math.round((10000 * (a - b)) / b) / 100 : 0);

export async function render(main, ctx) {
  const role = ctx.role;
  const staff = isStaff(role);
  const S = { providers: [], ars: [], services: [], service: null, catalogPick: null, saving: false };

  paint(main, html`
    <div class="page-head"><div class="t"><h2>Captura rápida</h2>
      <p>Registra cada servicio como una reclamación individual. Los códigos SIMON/CUPS y la tarifa salen del contrato del médico con la ARS.</p></div>
      <div class="toolbar no-print" style="margin:0"><a class="btn" href="#/reclamaciones">Ver reclamaciones</a></div></div>
    <div class="grid two" style="align-items:start">
      <form class="card" id="cf" novalidate autocomplete="off" aria-describedby="kbhelp">
        <h2>Nueva reclamación</h2>
        <div class="form-grid">
          <div class="field"><label for="c_prov">1 · Médico *</label><select id="c_prov" name="provider" required><option value="">Cargando…</option></select></div>
          <div class="field"><label for="c_ars">2 · ARS *</label><select id="c_ars" name="ars" required><option value="">Cargando…</option></select></div>
          <div class="field"><label for="c_date">3 · Fecha del servicio *</label><input id="c_date" name="service_date" type="date" required max="${todayISO()}"></div>
          <div class="field"><label for="c_mode">Modalidad</label><select id="c_mode" name="care_mode">${CARE_MODES.map(([v, l]) => opt(v, l, memory.careMode))}</select></div>
          <div class="field" style="grid-column:1/-1"><label for="c_pat">4 · Paciente *</label><input id="c_pat" name="patient_name" list="c_pats" required maxlength="150" placeholder="Nombre completo (escriba 2 letras o el NSS para buscar)"><datalist id="c_pats"></datalist></div>
          <div class="field"><label for="c_nss">NSS / No. afiliado *</label><input id="c_nss" name="member" required maxlength="40" inputmode="numeric"></div>
          <div class="field"><label for="c_auth">No. de autorización <span id="authReq">*</span></label><input id="c_auth" name="authorization" maxlength="60"></div>
          <div class="field"><label for="c_doc">Cédula del paciente</label><input id="c_doc" name="patient_doc" maxlength="20" inputmode="numeric"></div>
          <div class="field"><label for="c_clinic">Centro / clínica</label><input id="c_clinic" name="clinic" maxlength="120"></div>
          <div class="field" style="grid-column:1/-1"><label for="c_srv">5 · Servicio contratado *</label>
            <select id="c_srv" name="procedure" required disabled><option value="">Seleccione médico, ARS y fecha</option></select>
            <span class="hint" id="srvHint">Solo aparecen los servicios contratados para ese médico con esa ARS en la fecha del servicio.</span></div>
        </div>
        <div id="srvInfo" aria-live="polite"></div>
        <div id="notContracted"></div>
        <div class="form-grid">
          <div class="field"><label for="c_qty">Cantidad</label><input id="c_qty" name="quantity" type="number" min="1" step="1" value="1" inputmode="numeric"></div>
          <div class="field"><label for="c_amt">Monto unitario a reclamar</label><input id="c_amt" name="amount" type="number" min="0" step="0.01" inputmode="decimal" placeholder="Tarifa automática"></div>
        </div>
        <div id="diffBox" aria-live="assertive"></div>
        <div class="field"><label for="c_notes">Observaciones</label><input id="c_notes" name="notes" maxlength="300"></div>
        <label class="check" style="margin:8px 0"><input type="checkbox" id="c_keep"> Mantener el mismo paciente para el siguiente registro (varios servicios del mismo paciente)</label>
        <div id="dupBox"></div>
        <div class="toolbar" style="margin-top:10px">
          <button class="btn primary" type="submit" id="save">Guardar y registrar siguiente</button>
          <button class="btn" type="button" id="clear">Limpiar</button>
        </div>
        <p class="small muted" id="kbhelp">Teclado: <b>Tab</b> avanza entre campos · <b>Ctrl + Enter</b> guarda desde cualquier campo · <b>Esc</b> limpia el paciente.</p>
      </form>
      <div class="card"><h2>Registradas recientemente</h2><div id="recent"></div></div>
    </div>`);

  const form = $('#cf', main);
  const el = (id) => $(`#${id}`, main);
  /** Las tareas asíncronas (búsquedas, cargas) terminan después de que el usuario puede haber salido de la pantalla */
  const alive = () => document.body.contains(form);
  el('c_date').value = memory.date || todayISO();
  el('c_clinic').value = memory.clinic || '';

  // ------------------------------------------------------------ catálogos
  try {
    [S.providers, S.ars] = await Promise.all([captureProviders(), activeArs()]);
  } catch (err) { paint(el('recent'), html`<div class="note bad">${friendlyError(err)}</div>`); }
  if (!S.providers.length) {
    paint(form, emptyView('Sin médicos asignados', role === 'capturer'
      ? 'Tu usuario todavía no tiene médicos asignados. Pide al administrador de SOFA que te asigne los médicos para los que registras reclamaciones.'
      : 'No hay médicos activos visibles para tu usuario.'));
    return;
  }
  if (!S.providers.some((p) => p.id === memory.provider)) memory.provider = S.providers.length === 1 ? S.providers[0].id : '';
  paint(el('c_prov'), html`<option value="">Seleccione…</option>${S.providers.map((p) => opt(p.id, staff && p.organizations?.legal_name && p.organizations.legal_name !== p.full_name ? `${p.full_name} · ${p.organizations.legal_name}` : p.full_name, memory.provider))}`);
  paint(el('c_ars'), html`<option value="">Seleccione…</option>${S.ars.map((a) => opt(a.id, a.name, memory.ars))}`);

  // ------------------------------------------------------------ servicios contratados
  let srvSeq = 0;
  async function loadServices() {
    const provider = el('c_prov').value; const ars = el('c_ars').value; const d = el('c_date').value;
    memory.provider = provider; memory.ars = ars; memory.date = d;
    S.service = null; S.catalogPick = null; paint(el('srvInfo'), html``); paint(el('notContracted'), html``); drawDiff();
    const sel = el('c_srv');
    if (!provider || !ars || !d) { sel.disabled = true; paint(sel, html`<option value="">Seleccione médico, ARS y fecha</option>`); return; }
    const my = ++srvSeq;
    sel.disabled = true; paint(sel, html`<option value="">Cargando servicios contratados…</option>`);
    try {
      const rows = await contractedServices(provider, ars, d);
      if (my !== srvSeq || !alive()) return;
      S.services = rows;
      sel.disabled = false;
      paint(sel, html`<option value="">${rows.length ? `Seleccione (${rows.length} contratados)…` : 'Sin servicios contratados vigentes en esa fecha'}</option>
        ${rows.map((r) => opt(r.procedure_id, `${r.name}${r.cups ? ` · CUPS ${r.cups}` : ''}${r.simon ? ` · SIMON ${r.simon}` : ''} · ${money(r.amount)}`))}
        <option value="__catalog">¿No aparece? Buscar en el catálogo maestro…</option>`);
      if (rows.length === 1) { sel.value = rows[0].procedure_id; pickService(); }
    } catch (err) { if (my === srvSeq && alive()) { paint(sel, html`<option value="">Error al cargar</option>`); toast(friendlyError(err), 'bad'); } }
  }

  function pickService() {
    const v = el('c_srv').value;
    S.catalogPick = null; paint(el('notContracted'), html``);
    if (v === '__catalog') { S.service = null; paint(el('srvInfo'), html``); openCatalog(); drawDiff(); return; }
    S.service = S.services.find((s) => s.procedure_id === v) || null;
    const s = S.service;
    el('c_amt').value = s ? Number(s.amount).toFixed(2) : '';
    paint(el('srvInfo'), s ? html`<div class="note ok" style="margin:6px 0 10px">
      <b>${s.name}</b><br>
      SIMON <b class="mono">${s.simon || '—'}</b> · CUPS <b class="mono">${s.cups || '—'}</b>${s.internal_code ? html` · Interno <span class="mono">${s.internal_code}</span>` : ''}${s.ars_service_code ? html` · Código ARS <span class="mono">${s.ars_service_code}</span>` : ''}<br>
      Tarifa contractual <b>${money(s.amount)}</b> · vigente ${date(s.valid_from)}${s.valid_to ? ` al ${date(s.valid_to)}` : ' en adelante'}${s.contract_ref ? html` · contrato <span class="mono">${s.contract_ref}</span>` : ''}
      ${s.requirements?.length ? html`<div class="small" style="margin-top:4px">Documentos requeridos: ${s.requirements.join(', ')}</div>` : ''}</div>` : html``);
    drawDiff();
  }

  /** Servicio existente en el catálogo pero NO contratado (§10) */
  async function openCatalog() {
    const pick = await formDialog({
      title: 'Buscar en el catálogo maestro', submitLabel: 'Usar este servicio', wide: true,
      body: html`<div class="field"><label for="cat_q">Nombre, código interno, SIMON, CUPS o especialidad</label><input id="cat_q" class="input" type="search" autocomplete="off"></div>
        <div id="cat_r" class="list" style="max-height:320px;overflow:auto"></div><input type="hidden" name="id" id="cat_id">`,
      onOpen: (f) => {
        let t; const q = f.querySelector('#cat_q'); const box = f.querySelector('#cat_r');
        const run = async () => {
          try {
            const rows = await searchCatalog(q.value, 20);
            paint(box, rows.length ? html`${rows.map((r) => html`<label class="li" style="cursor:pointer"><input type="radio" name="pick" value="${r.id}" data-name="${r.name}">
              <div class="b"><div class="t1">${r.name}</div><div class="t2">${[r.internal_code, r.simon && `SIMON ${r.simon}`, r.cups && `CUPS ${r.cups}`, r.specialty || r.category].filter(Boolean).join(' · ')}</div></div></label>`)}`
              : html`<p class="small muted">Sin coincidencias.</p>`);
          } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); }
        };
        q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(run, 300); }); run();
      },
      onSubmit: async (d, f) => {
        const r = f.querySelector('input[name=pick]:checked');
        if (!r) { toast('Seleccione un servicio', 'bad'); return false; }
        return { id: r.value, name: r.dataset.name };
      }
    });
    if (!pick) { el('c_srv').value = ''; return; }
    const contracted = S.services.find((s) => s.procedure_id === pick.id);
    if (contracted) { el('c_srv').value = pick.id; pickService(); return; }
    S.catalogPick = pick; el('c_amt').value = '';
    const admin = can('claims.exception', role);
    paint(el('notContracted'), html`<div class="note bad" role="alert" style="margin:6px 0 10px">
      <b>${pick.name}</b><br>Este servicio existe en el catálogo, pero no está registrado como contratado/autorizado para este médico con esta ARS.
      <div class="field" style="margin-top:8px"><label for="nc_mode">¿Qué desea hacer?</label>
        <select id="nc_mode" name="nc_mode">
          ${opt('bloquear', 'No registrar (corregir el servicio)', 'bloquear')}
          ${opt('pendiente', 'Registrar como “Pendiente de configuración” y solicitar revisión del contrato')}
          ${admin ? opt('excepcion', 'Excepción administrativa auditada (solo administradores)') : ''}
        </select></div>
      <div class="field" id="nc_rs" hidden><label for="nc_reason">Motivo de la excepción (mín. 10 caracteres, queda en bitácora) *</label><textarea id="nc_reason" name="nc_reason" rows="2" class="input"></textarea></div>
      <p class="small">Indique el monto a reclamar: sin contrato no hay tarifa automática. La reclamación no será válida para radicar hasta configurar el contrato o autorizar la excepción.</p></div>`);
    el('nc_mode').addEventListener('change', (e) => { el('nc_rs').hidden = e.target.value !== 'excepcion'; });
    el('c_amt').focus();
  }

  // ------------------------------------------------------------ alerta de diferencia tarifaria (§9)
  function drawDiff() {
    const s = S.service; const box = el('diffBox');
    const v = el('c_amt').value === '' ? null : Number(el('c_amt').value);
    if (!s || v == null || Math.abs(v - Number(s.amount)) < 0.005) { if (box.dataset.shown) { paint(box, html``); delete box.dataset.shown; } return; }
    const d = v - Number(s.amount);
    const keep = box.querySelector('#d_reason')?.value || '';
    box.dataset.shown = '1';
    paint(box, html`<div class="note bad" role="alert" style="margin:0 0 10px">
      <b>ALERTA DE DIFERENCIA TARIFARIA</b>
      <dl class="kv" style="margin:6px 0"><dt>Tarifa contractual</dt><dd>${money(s.amount)}</dd><dt>Monto introducido</dt><dd>${money(v)}</dd>
        <dt>Diferencia</dt><dd><b>${money(d)}</b> (${pct(v, Number(s.amount))} %)</dd></dl>
      ${can('claims.discrepancy', role)
        ? html`<p class="small">Tu rol puede autorizar la diferencia: quedará registrada en bitácora como autorizada con tu usuario.</p>`
        : html`<p class="small">Se registrará como <b>diferencia pendiente</b>: un supervisor de facturación debe autorizarla antes de radicar.</p>`}
      <div class="field"><label for="d_reason">Motivo de la diferencia (obligatorio) *</label><input id="d_reason" name="discrepancy_reason" maxlength="300" value="${keep}"></div>
      <button type="button" class="btn" id="d_reset">Usar la tarifa contractual</button></div>`);
    el('d_reset').addEventListener('click', () => { el('c_amt').value = Number(s.amount).toFixed(2); drawDiff(); el('c_notes').focus(); });
  }

  // ------------------------------------------------------------ pacientes ya registrados
  let pt; let patients = [];
  const lookup = (q) => { clearTimeout(pt); pt = setTimeout(async () => {
    if (!alive()) return;
    const provider = el('c_prov').value; if (!provider) return;
    try {
      patients = await patientLookup(provider, q);
      if (!alive()) return;
      paint(el('c_pats'), html`${patients.map((p) => html`<option value="${p.patient_name}">${p.member_number || ''}${p.last_service ? ` · último ${date(p.last_service)}` : ''}</option>`)}`);
    } catch { /* autocompletar es opcional */ }
  }, 250); };
  el('c_pat').addEventListener('input', (e) => {
    lookup(e.target.value);
    const hit = patients.find((p) => p.patient_name === e.target.value);
    if (hit) { if (!el('c_nss').value) el('c_nss').value = hit.member_number || ''; if (!el('c_doc').value) el('c_doc').value = hit.patient_doc || ''; }
  });
  el('c_nss').addEventListener('change', (e) => {
    if (el('c_pat').value || String(e.target.value).trim().length < 3) return;
    patientLookup(el('c_prov').value, e.target.value).then((rows) => {
      if (!alive()) return;
      const hit = rows.find((p) => p.member_number === e.target.value.trim());
      if (hit && !el('c_pat').value) { el('c_pat').value = hit.patient_name; if (!el('c_doc').value) el('c_doc').value = hit.patient_doc || ''; toast(`Paciente encontrado: ${hit.patient_name}`); }
    }).catch(() => {});
  });

  const syncAuth = () => { el('authReq').textContent = el('c_mode').value === 'emergencia' ? '(opcional en emergencia)' : '*'; };
  el('c_prov').addEventListener('change', loadServices);
  el('c_ars').addEventListener('change', loadServices);
  el('c_date').addEventListener('change', loadServices);
  el('c_mode').addEventListener('change', () => { memory.careMode = el('c_mode').value; syncAuth(); });
  el('c_srv').addEventListener('change', pickService);
  el('c_amt').addEventListener('input', drawDiff);
  syncAuth();

  // ------------------------------------------------------------ guardar
  const clearPatient = () => {
    ['c_pat', 'c_nss', 'c_auth', 'c_doc', 'c_notes'].forEach((i) => { el(i).value = ''; fieldError(el(i), ''); });
    el('c_qty').value = '1'; paint(el('dupBox'), html``);
  };
  function values() {
    return {
      provider: el('c_prov').value, ars: el('c_ars').value, serviceDate: el('c_date').value,
      procedure: S.service?.procedure_id || S.catalogPick?.id || '',
      patientName: el('c_pat').value.trim(), member: el('c_nss').value.trim(), authorization: el('c_auth').value.trim(), patientDoc: el('c_doc').value.trim(),
      quantity: Number(el('c_qty').value || 1), careMode: el('c_mode').value, clinic: el('c_clinic').value.trim(), notes: el('c_notes').value.trim()
    };
  }
  function validate(v) {
    let ok = true;
    const need = [['c_prov', v.provider, 'Seleccione el médico'], ['c_ars', v.ars, 'Seleccione la ARS'], ['c_date', v.serviceDate, 'Indique la fecha'],
      ['c_pat', v.patientName.length >= 3, 'Mínimo 3 caracteres'], ['c_nss', v.member.length >= 3, 'Indique el NSS'],
      ['c_auth', v.careMode === 'emergencia' || v.authorization.length >= 2, 'Indique la autorización (solo emergencias van sin ella)'],
      ['c_srv', v.procedure, 'Seleccione el servicio']];
    need.forEach(([id, good, msg]) => { fieldError(el(id), good ? '' : msg); if (!good && ok) { ok = false; el(id).focus(); } });
    if (ok && v.serviceDate > todayISO()) { fieldError(el('c_date'), 'La fecha no puede ser futura'); el('c_date').focus(); ok = false; }
    if (ok && !(v.quantity > 0)) { fieldError(el('c_qty'), 'Debe ser mayor que cero'); el('c_qty').focus(); ok = false; }
    return ok;
  }

  async function save(allowDuplicate = false) {
    const v = values();
    if (!validate(v)) return;
    const amt = el('c_amt').value === '' ? null : Number(el('c_amt').value);
    if (S.service) {
      if (amt != null && Math.abs(amt - Number(S.service.amount)) >= 0.005) {
        const r = el('d_reason')?.value.trim() || '';
        if (r.length < 5) { fieldError(el('d_reason'), 'Indique el motivo (mínimo 5 caracteres)'); el('d_reason').focus(); return; }
        v.amount = amt; v.discrepancyReason = r;
      }
    } else if (S.catalogPick) {
      const mode = el('nc_mode').value;
      if (mode === 'bloquear') { toast('El servicio no está contratado para este médico con esta ARS. Corrija el servicio o elija otra opción.', 'bad'); el('nc_mode').focus(); return; }
      if (!(amt > 0)) { fieldError(el('c_amt'), 'Sin tarifa contractual: indique el monto'); el('c_amt').focus(); return; }
      v.amount = amt; v.notContracted = mode;
      if (mode === 'excepcion') {
        const r = el('nc_reason').value.trim();
        if (r.length < 10) { fieldError(el('nc_reason'), 'Mínimo 10 caracteres'); el('nc_reason').focus(); return; }
        v.exceptionReason = r;
      }
    }
    v.allowDuplicate = allowDuplicate;
    try {
      const r = await captureClaim(v);
      memory.clinic = v.clinic;
      const [lbl] = claimStatus(r.status);
      toast(`${r.folio} registrada · ${lbl}${r.discrepancy ? ` · ${DISCREPANCY_STATUS[r.discrepancy]?.[0] || r.discrepancy}` : ''}`, r.status === 'pendiente_configuracion' ? 'bad' : 'ok');
      const keep = el('c_keep').checked;
      const kept = keep ? { p: el('c_pat').value, n: el('c_nss').value, d: el('c_doc').value } : null;
      clearPatient();
      if (kept) { el('c_pat').value = kept.p; el('c_nss').value = kept.n; el('c_doc').value = kept.d; }
      el('c_srv').value = ''; S.service = null; S.catalogPick = null; paint(el('srvInfo'), html``); paint(el('notContracted'), html``); el('c_amt').value = ''; drawDiff();
      if (S.services.length === 1) { el('c_srv').value = S.services[0].procedure_id; pickService(); }
      (kept ? el('c_auth') : el('c_pat')).focus();
      loadRecent();
    } catch (err) {
      if (err?.code === '23505' && /duplicad/i.test(err.message || '')) {
        paint(el('dupBox'), html`<div class="dup-box" role="alert"><b>${err.message}</b><br>Revise que no esté registrando dos veces el mismo servicio.
          ${can('claims.duplicate', role) ? html`<div style="margin-top:6px"><button type="button" class="btn" id="dupOk">Es un servicio distinto: registrar de todos modos</button></div>` : html`<div class="small">Si es un servicio distinto, pida a Facturación que lo registre.</div>`}</div>`);
        el('dupOk')?.addEventListener('click', () => busy(el('dupOk'), () => save(true)));
        return;
      }
      toast(friendlyError(err), 'bad');
    }
  }

  form.addEventListener('submit', (e) => { e.preventDefault(); busy(el('save'), () => save(false)); });
  form.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); busy(el('save'), () => save(false)); }
    if (e.key === 'Escape') { e.preventDefault(); clearPatient(); el('c_pat').focus(); }
  });
  el('clear').addEventListener('click', async () => {
    if (el('c_pat').value && !(await confirmDialog('Limpiar', 'Se borrarán los datos del paciente en pantalla.', 'Limpiar'))) return;
    clearPatient(); el('c_pat').focus();
  });

  // ------------------------------------------------------------ lista lateral
  async function loadRecent() {
    const box = el('recent'); if (!box) return;
    try {
      const rows = await myRecentClaims(15);
      if (!alive()) return;
      paint(box, rows.length ? html`<div class="list">${rows.map((c) => { const [l, cl] = claimStatus(c.claim_status); return html`
        <a class="li" href="#/reclamaciones/${c.id}" style="text-decoration:none;color:inherit"><div class="b">
          <div class="t1"><span class="mono">${c.folio}</span> · ${c.patient_name}</div>
          <div class="t2">${c.service_name} · ${money(c.claimed)}${staff ? ` · ${c.provider_name}` : ''} · ${c.ars_name}</div>
          <div class="t2">${dateTime(c.created_at)}</div></div>
          <div style="text-align:right"><span class="pill ${cl}">${l}</span>${c.discrepancy_status ? html`<div><span class="pill ${DISCREPANCY_STATUS[c.discrepancy_status]?.[1] || ''}">${DISCREPANCY_STATUS[c.discrepancy_status]?.[0] || c.discrepancy_status}</span></div>` : ''}</div></a>`; })}</div>`
        : html`<p class="small muted">Aún no hay reclamaciones registradas hoy.</p>`);
    } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); }
  }

  if (memory.provider && memory.ars) loadServices();
  loadRecent();
  (memory.provider ? (memory.ars ? el('c_pat') : el('c_ars')) : el('c_prov')).focus();
}
