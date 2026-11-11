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
import { requiredDocsPreview, dossierStatus } from '../services/dossier.js';
import { dossierPill } from './dossier-card.js';
import { captureIdentifiers } from './capture-identifiers.js';
import { viewAsState } from '../utils/view-as-state.js';
import { initCamara } from './captura-camara.js';
import { revisarCaptura, capturarConDiagnostico, mostrarAviso, limpiarAvisos, pistaCedula, cie10Suggestions } from '../services/calidad-dato.js';   // I61: calidad del dato
import { launchARSPortal } from '../services/ars-bridge.js';

/** Se conserva entre visitas dentro de la misma sesión: médico, ARS, fecha y clínica */
const memory = { provider: '', ars: '', date: '', clinic: '', careMode: 'ambulatorio' };
let sessionCount = 0;
const pct = (a, b) => (b ? Math.round((10000 * (a - b)) / b) / 100 : 0);

export async function render(main, ctx) {
  const role = ctx.role;
  const staff = isStaff(role);
  if (!can('claims.capture', role)) { emptyView(main, 'Sin acceso', 'Esta pantalla es para Capturadores y Administradores.'); return; }

  // ---------------------------------------------------------------- Estado cita (si se llama desde Work-Today)
  const params = new URLSearchParams(location.hash.split('?')[1] || '');
  const citaId = params.get('cita');
  let cita = null;

  // ---------------------------------------------------------------- Datos estáticos
  const [providers, ars] = await Promise.all([captureProviders(), activeArs()]);
  const S = { providers, ars, services: [], service: null, catalogPick: null };

  paint(main, html`
    <div class="split-layout">
      <div class="split-main">
        <form class="card" id="cf" novalidate autocomplete="off" aria-describedby="kbhelp">
          <h2>Nueva reclamación</h2>
          <div class="form-grid">
            <div class="field"><label for="c_prov">1 · Médico *</label><select id="c_prov" name="provider" required><option value="">Cargando…</option></select></div>
            <div class="field"><label for="c_ars">2 · ARS *</label><select id="c_ars" name="ars" required><option value="">Cargando…</option></select></div>
            <div class="field"><label for="c_date">3 · Fecha del servicio *</label><input id="c_date" name="service_date" type="date" required max="${todayISO()}"></div>
            <div class="field"><label for="c_mode">Modalidad</label><select id="c_mode" name="care_mode">${CARE_MODES.map(([v, l]) => opt(v, l, memory.careMode))}</select></div>
            <div class="field" style="grid-column:1/-1"><label for="c_pat">4 · Paciente *</label><input id="c_pat" name="patient_name" list="c_pats" required maxlength="150" placeholder="Nombre completo (escriba 2 letras o el NSS para buscar)"><datalist id="c_pats"></datalist></div>
            <div class="field"><label for="c_nss">NSS / No. afiliado *</label><input id="c_nss" name="member" required maxlength="40" inputmode="numeric"></div>
            <div id="arsPortalBridge" style="grid-column:1/-1" aria-live="polite"></div>
            <div class="field"><label for="c_auth">No. de autorización <span id="authReq">*</span></label><input id="c_auth" name="authorization" maxlength="60"></div>
            <div class="field"><label for="c_authdate">Fecha de la autorización</label><input id="c_authdate" name="authdate" type="date" max="${todayISO()}"><span class="hint">Avisa a los 150 días si no se ha radicado</span></div>
            <div class="field"><label for="c_doc">Cédula del paciente</label><input id="c_doc" name="patient_doc" maxlength="20" inputmode="numeric"></div><div id="globalPatientMatch" style="grid-column:1/-1"></div>
            <div class="field"><label for="c_dx">Diagnóstico (CIE-10)</label><input id="c_dx" name="diagnosis" maxlength="60" autocomplete="off" placeholder="Ej.: I10, E11.9"><span class="hint">SOFA sugiere códigos según servicio, SIMON y CUPS. Confirma el diagnóstico documentado; puedes escribir otro código.</span><div id="dxSuggest" class="small" style="margin-top:6px"></div></div>
            <div class="field"><label for="c_clinic">Centro / clínica</label><input id="c_clinic" name="clinic" maxlength="120"></div>
            <div class="field" style="grid-column:1/-1"><label for="c_srv">5 · Servicio contratado *</label>
              <select id="c_srv" name="procedure" required disabled><option value="">Seleccione médico, ARS y fecha</option></select>
              <span class="hint" id="srvHint">Solo aparecen los servicios contratados para ese médico con esa ARS en la fecha del servicio.</span></div>
          </div>
          <div id="capture-identifiers" aria-live="polite"></div>
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
          <div class="actions" id="kbhelp">
            <button type="submit" class="primary" id="save">✓ Guardar reclamación</button>
            <button type="button" id="clear">Limpiar paciente</button>
            <span class="hint">Ctrl+Enter guarda · Escape limpia paciente</span>
          </div>
        </form>
      </div>
      <div class="split-side">
        <div id="camBox"></div>
        <section class="card">
          <h3>Recientes</h3>
          <div id="recent"></div>
        </section>
      </div>
    </div>`);

  const el = (id) => document.getElementById(id);
  const form = el('cf');
  let alive = () => main.contains(form);

  const cam = initCamara(el('camBox'), { onCapture: (file) => {
    // La cámara solo captura imágenes; el adjunto se sube aparte si se implementa
    console.log('[cam] imagen capturada (adjunto pendiente de implementar)', file?.name);
  }});

  // ---------------------------------------------------------------- Cita previa
  if (citaId) {
    try {
      const { rpc } = await import('../services/iter18.js');
      cita = await rpc('get_cita_for_capture', { p_cita: citaId });
      if (cita) { memory.provider = cita.provider_id; memory.ars = cita.ars_id || memory.ars; memory.date = cita.appointment_date; }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  }
  if (!S.providers.some((p) => p.id === memory.provider)) memory.provider = S.providers.length === 1 ? S.providers[0].id : '';
  if (!S.ars.some((a) => a.id === memory.ars)) memory.ars = S.ars.length === 1 ? S.ars[0].id : '';
  paint(el('c_prov'), html`<option value="">Seleccione…</option>${S.providers.map((p) => opt(p.id, staff && p.organizations?.legal_name && p.organizations.legal_name !== p.full_name ? `${p.full_name} · ${p.organizations.legal_name}` : p.full_name, memory.provider))}`);
  paint(el('c_ars'), html`<option value="">Seleccione…</option>${S.ars.map((a) => opt(a.id, a.name, memory.ars))}`);

  // ------------------------------------------------------------ portal PSS bridge
  function updatePortalBridge() {
    const selectedArs = S.ars.find((a) => a.id === el('c_ars').value);
    const bridge = el('arsPortalBridge');
    if (!bridge) return;
    if (!selectedArs?.portal_url) {
      paint(bridge, html`<div class="hint" style="margin-top:-8px;font-size:12px;color:var(--ink-2)">Verifica la elegibilidad del paciente en el portal web de su ARS o en SISALRIL antes de radicar — la cobertura no se valida automáticamente en este paso.</div>`);
      return;
    }
    paint(bridge, html`<div class="note info" style="margin-top:-8px;padding:8px 12px;display:flex;align-items:center;gap:10px;flex-wrap:wrap">
      <span style="flex:1;min-width:0;font-size:13px">Verifica elegibilidad en el portal de <b>${selectedArs.name}</b> — los datos del paciente se copian al portapapeles.</span>
      <button type="button" class="btn" id="arsPortalBtn" style="white-space:nowrap;flex-shrink:0">🔗 Ir al portal ARS</button>
    </div>`);
    el('arsPortalBtn')?.addEventListener('click', () => {
      launchARSPortal(selectedArs, {
        member:        el('c_nss')?.value,
        patientDoc:    el('c_doc')?.value,
        patientName:   el('c_pat')?.value,
        serviceDate:   el('c_date')?.value,
        diagnosis:     el('c_dx')?.value,
        procedureName: S.service?.name,
        simon:         S.service?.simon,
        cups:          S.service?.cups,
      });
    });
  }
  updatePortalBridge();

  // ------------------------------------------------------------ servicios contratados
  let srvSeq = 0;
  async function loadServices() {
    const provider = el('c_prov').value; const ars = el('c_ars').value; const d = el('c_date').value;
    memory.provider = provider; memory.ars = ars; memory.date = d;
    refreshIdentifiers(provider, ars, null);
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
      paint(sel, html`<option value="">${rows.length ? `Seleccione (${rows.length} contratados)…` : 'Tarifario pendiente: seleccione un servicio del catálogo'}</option>
        ${rows.map((r) => opt(r.procedure_id, `${r.name}${r.cups ? ` · CUPS ${r.cups}` : ''}${r.simon ? ` · SIMON ${r.simon}` : ''} · ${money(r.amount)}`))}
        <option value="__catalog">${rows.length ? '¿No aparece? Buscar en el catálogo maestro…' : 'Capturar con tarifario pendiente'}</option>`);
      if (rows.length === 1) { sel.value = rows[0].procedure_id; pickService(); }
    } catch (err) { if (my === srvSeq && alive()) { paint(sel, html`<option value="">Error al cargar</option>`); toast(friendlyError(err), 'bad'); } }
  }

  function pickService() {
    const v = el('c_srv').value;
    S.catalogPick = null; paint(el('notContracted'), html``);
    if (v === '__catalog') { refreshIdentifiers(el('c_prov').value, el('c_ars').value, null); S.service = null; paint(el('srvInfo'), html``); openCatalog(); drawDiff(); return; }
    S.service = S.services.find((s) => s.procedure_id === v) || null;
    const s = S.service;
    refreshIdentifiers(el('c_prov').value, el('c_ars').value, s);
    el('c_amt').value = s ? Number(s.amount).toFixed(2) : '';
    paint(el('srvInfo'), s ? html`<div class="note ok" style="margin:6px 0 10px">
      <b>${s.name}</b><br>
      SIMON <b class="mono">${s.simon || '—'}</b> · CUPS <b class="mono">${s.cups || '—'}</b>${s.internal_code ? html` · Interno <span class="mono">${s.internal_code}</span>` : ''}${s.ars_service_code ? html` · Código ARS <span class="mono">${s.ars_service_code}</span>` : ''}<br>
      Tarifa contractual <b>${money(s.amount)}</b> · vigente ${date(s.valid_from)}${s.valid_to ? ` al ${date(s.valid_to)}` : ' en adelante'}${s.contract_ref ? html` · contrato <span class="mono">${s.contract_ref}</span>` : ''}
      <div class="small" style="margin-top:4px" id="reqDocs"></div></div>` : html``);
    if (s) { loadReqDocs(); loadDxSuggestions(); } else paint(el('dxSuggest'), html``);
    drawDiff();
  }

  /** Servicio existente en el catálogo pero NO contratado (§10) */
  async function openCatalog() {
    const result = await formDialog({
      title: 'Buscar en el catálogo maestro',
      fields: [{ id: 'q', label: 'Nombre, SIMON o CUPS', type: 'search', required: true, minlength: 2 }],
      submit: 'Buscar',
      onSubmit: async ({ q }) => {
        const rows = await searchCatalog(q, el('c_ars').value);
        if (!rows.length) throw new Error('Sin resultados. Pruebe otro término.');
        return rows;
      },
      renderResult: (rows) => html`<ul class="search-results">${rows.map((r) =>
        html`<li><button type="button" class="i18-link" data-id="${r.id}">${r.name}${r.simon ? html` · SIMON <span class="mono">${r.simon}</span>` : ''}${r.cups ? html` · CUPS <span class="mono">${r.cups}</span>` : ''}</button></li>`)}</ul>`,
      onSelect: (el2) => el2.closest('[data-id]')?.dataset.id,
    });
    if (!result) return;
    const rows = await searchCatalog(result, el('c_ars').value);
    const pick = rows.find((r) => r.id === result) || rows[0];
    if (!pick) return;
    S.catalogPick = pick; S.service = null;
    refreshIdentifiers(el('c_prov').value, el('c_ars').value, null);
    el('c_amt').value = '';
    paint(el('notContracted'), html`<div class="note warn" style="margin:6px 0 10px">
      Servicio sin contrato vigente: <b>${pick.name}</b>${pick.simon ? html` · SIMON <span class="mono">${pick.simon}</span>` : ''}${pick.cups ? html` · CUPS <span class="mono">${pick.cups}</span>` : ''}<br>
      <span class="small">Ingrese el monto manualmente. Esta reclamación quedará marcada como sin tarifa contractual.</span></div>`);
    drawDiff();
  }

  // ------------------------------------------------------------ identificadores de captura
  async function refreshIdentifiers(provider, ars2, service) {
    const box = el('capture-identifiers');
    if (!box) return;
    try {
      const identifiers = await captureIdentifiers(provider, ars2, service);
      paint(box, identifiers);
    } catch (_) { paint(box, html``); }
  }

  // ------------------------------------------------------------ documentos requeridos
  async function loadReqDocs() {
    const box = el('reqDocs'); if (!box || !S.service) return;
    try {
      const docs = await requiredDocsPreview(S.service.procedure_id, el('c_ars').value);
      if (!docs?.length) { paint(box, html``); return; }
      paint(box, html`Documentos requeridos: ${docs.map((d) => html`<span class="pill">${d}</span>`)}`);
    } catch (_) { paint(box, html``); }
  }

  // ------------------------------------------------------------ sugerencias CIE-10 (I61)
  async function loadDxSuggestions() {
    const box = el('dxSuggest'); if (!box || !S.service) return;
    try {
      const sugs = await cie10Suggestions(S.service.procedure_id, S.service.simon, S.service.cups);
      if (!sugs?.length) { paint(box, html``); return; }
      paint(box, html`Diagnósticos frecuentes: ${sugs.map((s) => html`<button type="button" class="i18-link" onclick="this.closest('form').querySelector('#c_dx').value='${s.code}';">${s.code} ${s.desc}</button>`)}`
      );
    } catch (_) { paint(box, html``); }
  }

  // ------------------------------------------------------------ diferencia de tarifa
  function drawDiff() {
    const s = S.service;
    const entered = parseFloat(el('c_amt').value);
    if (!s || isNaN(entered) || Math.abs(entered - Number(s.amount)) < 0.005) { paint(el('diffBox'), html``); return; }
    const diff = pct(entered, Number(s.amount));
    const cls = diff > 0 ? 'warn' : 'info';
    paint(el('diffBox'), html`<div class="note ${cls}" style="margin:4px 0">
      Diferencia vs. tarifa contractual: <b>${diff > 0 ? '+' : ''}${diff}%</b>
      (contractual ${money(s.amount)} · ingresado ${money(entered)})
      <div class="field" style="margin-top:6px"><label for="d_reason">Motivo de la diferencia *</label><input id="d_reason" name="diff_reason" maxlength="200"></div></div>`);
  }

  // ------------------------------------------------------------ búsqueda de paciente
  let patSeq = 0;
  el('c_pat').addEventListener('input', async () => {
    const v = el('c_pat').value.trim();
    if (v.length < 2) { paint($('#c_pats'), html``); return; }
    const my = ++patSeq;
    try {
      const orgId = S.providers.find((p) => p.id === el('c_prov').value)?.organization_id;
      if (!orgId) return;
      const rows = await patientLookup(v, orgId);
      if (my !== patSeq) return;
      paint($('#c_pats'), html`${rows.map((r) => html`<option value="${r.patient_name}" data-nss="${r.member_number}" data-doc="${r.patient_doc || ''}">`)}`
      );
    } catch (_) { /* no-op */ }
  });
  el('c_pat').addEventListener('change', () => {
    const hit = Array.from($('#c_pats').children).find((o) => o.value === el('c_pat').value);
    if (hit && !el('c_nss').value) { el('c_nss').value = hit.dataset.nss || ''; if (!el('c_doc').value) el('c_doc').value = hit.dataset.doc || ''; }
  });

  // ------------------------------------------------------------ NSS pista cédula
  el('c_nss').addEventListener('blur', () => pistaCedula(el('c_nss'), el('c_doc')));

  // ------------------------------------------------------------ paciente global
  async function checkUniversalPatient() {
    const doc = el('c_doc').value.trim(); const nss = el('c_nss').value.trim();
    const box = el('globalPatientMatch'); if (!box) return;
    if (!doc && !nss) { paint(box, html``); return; }
    const orgId = S.providers.find((p) => p.id === el('c_prov').value)?.organization_id;
    if (!orgId) return;
    try {
      const { globalPatientMatch } = await import('../services/claims.js');
      const r = await globalPatientMatch(doc || null, nss || null, orgId);
      if (!alive()) return;
      if (r?.match === 'found' && r.patient) {
        paint(box, html`<div class="note info">Paciente encontrado en otra organización: <b>${r.patient.patient_name}</b>
          <button type="button" class="i18-link" id="reusePatient">Reutilizar datos</button></div>`);
        el('reusePatient')?.addEventListener('click', async () => {
          if (!el('c_pat').value) el('c_pat').value = r.patient.patient_name;
          if (!el('c_nss').value) el('c_nss').value = r.patient.member_number || '';
          if (!el('c_doc').value) el('c_doc').value = r.patient.patient_doc || '';
          if (r.patient.ars_id && S.ars.some((a) => a.id === r.patient.ars_id)) { el('c_ars').value = r.patient.ars_id; await onArs(); }
          const orgId2 = S.providers.find((p) => p.id === el('c_prov').value)?.organization_id;
          if (orgId2) {
            try { const { rpc } = await import('../services/iter18.js'); await rpc('attach_global_patient', { p_global: r.patient.id, p_org: orgId2 }); } catch (_) { console.warn('attach_global_patient falló', _); }
          }
          paint(box, html`<div class="note ok">Datos administrativos reutilizados. La nueva consulta continúa limpia.</div>`);
        });
      } else if (r?.match === 'conflict') {
        paint(box, html`<div class="note bad">La cédula y el NSS apuntan a registros diferentes. Revise los identificadores antes de continuar.</div>`);
      } else paint(box, html``);
    } catch (_) { paint(box, html``); }
  }
  el('c_doc').addEventListener('change', checkUniversalPatient);
  el('c_nss').addEventListener('change', checkUniversalPatient);

  // ------------------------------------------------------------ guardar
  const clearPatient = () => {
    ['c_pat', 'c_nss', 'c_auth', 'c_authdate', 'c_doc', 'c_dx', 'c_notes'].forEach((i) => { el(i).value = ''; fieldError(el(i), ''); });
    limpiarAvisos(el('c_doc'), el('c_nss'), el('c_dx'));
    el('c_qty').value = '1'; paint(el('dupBox'), html``); cam.limpiar();
  };
  function values() {
    return {
      provider: el('c_prov').value, ars: el('c_ars').value, serviceDate: el('c_date').value,
      procedure: S.service?.procedure_id || S.catalogPick?.id || '',
      patientName: el('c_pat').value.trim(), member: el('c_nss').value.trim(), authorization: el('c_auth').value.trim(), patientDoc: el('c_doc').value.trim(), diagnosis: el('c_dx').value.trim(),
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
    if (viewAsState.active) { toast('Modo soporte, solo lectura. Salga del modo soporte para registrar una reclamación.', 'warn'); return; }
    const v = values();
    if (!validate(v)) return;
    const amt = el('c_amt').value === '' ? null : Number(el('c_amt').value);
    if (S.service) {
      if (amt != null && Math.abs(amt - Number(S.service.amount)) >= 0.005) {
        const r = el('d_reason')?.value.trim() || '';
        if (r.length < 5) { fieldError(el('d_reason'), 'Indique el motivo (mínimo 5 caracteres)'); el('d_reason').focus(); return; }
      }
    }
    try {
      const result = await captureClaim({
        p_provider: v.provider, p_ars: v.ars, p_service_date: v.serviceDate,
        p_procedure: v.procedure || null, p_patient_name: v.patientName,
        p_member: v.member, p_authorization: v.authorization || null,
        p_patient_doc: v.patientDoc || null, p_diagnosis: v.diagnosis || null,
        p_amount: amt, p_quantity: v.quantity,
        p_care_mode: v.careMode, p_clinic: v.clinic || null,
        p_notes: v.notes || null, p_allow_duplicate: allowDuplicate,
        p_diff_reason: el('d_reason')?.value.trim() || null,
        p_catalog_pick: S.catalogPick?.id || null,
      });
      sessionCount++;
      toast(`Reclamación ${result.folio} guardada (${sessionCount} hoy)`, 'ok');
      paint(el('diffBox'), html``);
      if (el('c_keep').checked) {
        // Mantener paciente: limpiar solo los campos de servicio
        ['c_srv', 'c_auth', 'c_authdate', 'c_dx', 'c_notes'].forEach((i) => { el(i).value = ''; fieldError(el(i), ''); });
        S.service = null; S.catalogPick = null;
        paint(el('srvInfo'), html``); paint(el('notContracted'), html``); paint(el('dupBox'), html``);
        el('c_srv').disabled = true; paint(el('c_srv'), html`<option value="">Seleccione médico, ARS y fecha</option>`);
        await loadServices();
      } else {
        clearPatient();
      }
      loadRecent();
    } catch (err) {
      if (err?.code === '23505' && /duplicad/i.test(err.message || '')) {
        paint(el('dupBox'), html`<div class="dup-box" role="alert"><b>${err.message}</b><br>Revise que no esté registrando dos veces el mismo servicio.
          ${can('claims.duplicate', role) ? html`<div style="margin-top:6px"><button type="button" class="btn" id="dupOk">Es un servicio distinto: registrar de todos modos</button></div>` : html`<div class="small">Si es un servicio distinto, pida a Facturación que lo registre.</div>`}</div>`);
        el('dupOk')?.addEventListener('click', () => busy(el('dupOk'), () => save(true)));
        return;
      }
      toast(friendlyError(err), 'bad');
      if (err?.hint === 'calidad_dato') revisarDato();   // marca en cada casilla qué corregir
    }
  }

  const submitCapture = () => {
    if (viewAsState.active) { el('save').disabled = true; toast('Salga del modo soporte para registrar una reclamación.', 'warn'); return; }
    return busy(el('save'), () => save(false));
  };
  form.addEventListener('submit', (e) => { e.preventDefault(); submitCapture(); });
  form.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); submitCapture(); }
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
      const ds = await dossierStatus(rows.map((r) => r.id)).catch(() => ({}));
      if (!alive()) return;
      paint(box, rows.length ? html`<div class="list">${rows.map((c) => { const [l, cl] = claimStatus(c.claim_status); return html`
        <a class="li" href="#/reclamaciones/${c.id}" style="text-decoration:none;color:inherit"><div class="b">
          <div class="t1"><span class="mono">${c.folio}</span> · ${c.patient_name}</div>
          <div class="t2">${c.service_name} · ${money(c.claimed)}${staff ? ` · ${c.provider_name}` : ''} · ${c.ars_name}</div>
          <div class="t2">${dateTime(c.created_at)} ${dossierPill(ds[c.id])}</div></div>
          <div style="text-align:right"><span class="pill ${cl}">${l}</span>${c.discrepancy_status ? html`<div><span class="pill ${DISCREPANCY_STATUS[c.discrepancy_status]?.[1] || ''}">${DISCREPANCY_STATUS[c.discrepancy_status]?.[0] || c.discrepancy_status}</span></div>` : ''}</div></a>`; })}</div>`
        : html`<p class="small muted">Aún no hay reclamaciones registradas hoy.</p>`);
    } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); }
  }

  const onArs = async () => { await loadServices(); updatePortalBridge(); };

  const syncAuth = () => { el('authReq').textContent = el('c_mode').value === 'emergencia' ? '(opcional en emergencia)' : '*'; };
  el('c_prov').addEventListener('change', loadServices);
  el('c_ars').addEventListener('change', loadServices);
  el('c_ars').addEventListener('change', updatePortalBridge);
  el('c_date').addEventListener('change', loadServices);
  el('c_mode').addEventListener('change', () => { memory.careMode = el('c_mode').value; syncAuth(); loadReqDocs(); });
  el('c_srv').addEventListener('change', pickService);
  el('c_amt').addEventListener('input', drawDiff);
  syncAuth();

  // ------------------------------------------------------------ I61 · calidad del dato (avisos en la misma casilla)
  const dqCampos = { cedula: 'c_doc', nss: 'c_nss', diagnostico: 'c_dx' };
  el('c_doc').addEventListener('blur', () => mostrarAviso('cedula', el('c_doc'), el('c_nss')));
  el('c_nss').addEventListener('blur', () => mostrarAviso('nss', el('c_doc'), el('c_nss')));
  el('c_dx').addEventListener('blur', () => mostrarAviso('diagnostico', el('c_doc'), el('c_nss'), el('c_dx')));

  // ------------------------------------------------------------ revisión de dato al guardar
  function revisarDato() {
    const campos = ['c_doc', 'c_nss', 'c_dx'];
    campos.forEach((id) => mostrarAviso(dqCampos[Object.keys(dqCampos).find((k) => dqCampos[k] === id)], el('c_doc'), el('c_nss'), el('c_dx')));
  }

  if (memory.provider && memory.ars) loadServices();
  if (cita) {
    el('c_pat').value = cita.patient_name || ''; el('c_nss').value = cita.member_number || ''; el('c_auth').value = cita.authorization_number || ''; el('c_doc').value = cita.patient_doc || '';
    el('c_authdate').value = cita.authorization_date || '';
    form.insertAdjacentHTML('afterbegin', `<div class="note info" id="citaNote">Registrando la atención de la cita de <b>${(cita.patient_name || '').replace(/[<>&"]/g, '')}</b>. Al guardar, la cita queda como atendida y vuelves a Trabajo de hoy.</div>`);
  }
  loadRecent();
  (memory.provider ? (memory.ars ? el('c_pat') : el('c_ars')) : el('c_prov')).focus();
}
