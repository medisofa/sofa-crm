/** SOFA · 29/10/2026 · Puesta al día: reclamaciones que ya ocurrieron fuera de SOFA (Excel, papel,
 *  WhatsApp) o que están en SOFA pero en el cliente/estado equivocado. Captura por lote (CSV) o una
 *  a una, usando el mismo motor de calidad de dato y bloqueo de duplicados de siempre (capture_claim_dx).
 *  La Radicación y el Cobro NO se fuerzan aquí: exigen NCF, factura fiscal y evidencia real, así que
 *  esta pantalla agrupa lo capturado por su lote automático y lleva al usuario a radicarlo de verdad. */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, busy, formDialog, opt, requireFields, confirmDialog } from '../utils/ui.js';
import { money, date } from '../utils/formatters.js';
import { captureProviders, activeArs, contractedServices } from '../services/claims.js';
import { capturarConDiagnostico } from '../services/calidad-dato.js';
import { findDuplicateClaim, pendingSubmissionsSummary } from '../services/puesta-al-dia.js';

const norm = (v) => String(v ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').trim().toLowerCase().replace(/\s+/g, ' ');
const parseDate = (v) => {
  const s = String(v ?? '').trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  const m = s.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/);
  if (m) return `${m[3]}-${String(m[2]).padStart(2, '0')}-${String(m[1]).padStart(2, '0')}`;
  return '';
};
function parseCsv(text) {
  const rows = []; let row = []; let cell = ''; let q = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i], nx = text[i + 1];
    if (ch === '"' && q && nx === '"') { cell += '"'; i++; continue; }
    if (ch === '"') { q = !q; continue; }
    if (ch === ',' && !q) { row.push(cell); cell = ''; continue; }
    if ((ch === '\n' || ch === '\r') && !q) {
      if (ch === '\r' && nx === '\n') i++;
      row.push(cell); cell = '';
      if (row.some((x) => String(x).trim() !== '')) rows.push(row);
      row = []; continue;
    }
    cell += ch;
  }
  row.push(cell); if (row.some((x) => String(x).trim() !== '')) rows.push(row);
  return rows;
}
const CSV_COLS = ['Médico', 'ARS', 'Fecha del servicio', 'Modalidad', 'Paciente', 'NSS / Afiliado', 'Autorización', 'Cédula', 'Servicio', 'Cantidad', 'Monto', 'Notas'];

export async function render(main, ctx) {
  const S = { providers: [], ars: [], rows: [] };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Puesta al día</h2>
      <p>Captura reclamaciones que ya pasaron fuera de SOFA (Excel, papel, WhatsApp) sin volver a escribirlas si ya están aquí. Pasa por las mismas reglas de siempre: tarifario, calidad de dato y bloqueo de duplicados.</p></div></div>
    <div class="note">Esta pantalla solo captura la <b>reclamación</b>. SOFA la agrupa sola en su lote (radicación) del médico/ARS/mes; la Radicación y el Cobro se completan después, en sus pantallas, porque exigen NCF, factura fiscal y evidencia real — eso protege que los montos declarados cuadren.</div>
    <div class="grid two" style="align-items:start;margin-top:14px">
      <div class="card"><h2>Una por una</h2><p class="small muted">Para lo que llega por WhatsApp o papel, en el momento.</p><div class="toolbar"><button class="btn primary" id="one">+ Capturar reclamación</button></div></div>
      <div class="card"><h2>Por lote (CSV)</h2><p class="small muted">Columnas: ${CSV_COLS.join(' · ')}. Fecha en AAAA-MM-DD o DD/MM/AAAA.</p>
        <div class="field"><label for="pad-csv">Archivo CSV</label><input id="pad-csv" type="file" accept=".csv,text/csv"></div>
        <div class="toolbar"><button class="btn primary" id="loadCsv" disabled>Cargar y validar</button></div></div>
    </div>
    <div class="card" style="margin-top:14px"><h2>Resultado de esta sesión</h2><div id="pad-summary"><p class="small muted">Nada capturado todavía.</p></div></div>
    <div class="card" style="margin-top:14px"><h2>Lotes listos para radicar</h2><p class="small muted">Las reclamaciones capturadas aquí, agrupadas por su radicación automática.</p><div id="pad-lotes"><p class="small muted">—</p></div></div>
  `);

  try { [S.providers, S.ars] = await Promise.all([captureProviders(), activeArs()]); }
  catch (err) { toast(friendlyError(err), 'bad'); return; }

  const results = [];
  const submissionIds = [];
  const summaryBox = $('#pad-summary', main);
  const lotesBox = $('#pad-lotes', main);

  const drawSummary = () => {
    if (!results.length) { paint(summaryBox, html`<p class="small muted">Nada capturado todavía.</p>`); return; }
    paint(summaryBox, html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Paciente</th><th>Médico</th><th>Fecha</th><th>Resultado</th></tr></thead><tbody>
      ${results.map((r) => html`<tr>
        <td data-l="Paciente">${r.patient}</td><td data-l="Médico">${r.providerName}</td><td data-l="Fecha">${r.serviceDate ? date(r.serviceDate) : '—'}</td>
        <td data-l="Resultado">${r.ok
          ? html`<span class="pill ok">Capturada</span> <span class="mono">${r.folio}</span>`
          : r.duplicate
            ? html`<span class="pill warn">Ya existe en SOFA</span> <a href="#/reclamaciones/${r.duplicate.id}">${r.duplicate.folio}</a>`
            : html`<span class="pill bad">Error</span><div class="small muted">${r.error}</div>`}</td>
      </tr>`)}</tbody></table></div>`);
  };

  const refreshLotes = async () => {
    if (!submissionIds.length) { paint(lotesBox, html`<p class="small muted">—</p>`); return; }
    try {
      const subs = await pendingSubmissionsSummary(submissionIds);
      paint(lotesBox, html`<div class="list">${subs.map((s) => html`<div class="li">
        <div class="b"><div class="t1">${s.provider_name} · ${s.ars_name} · ${s.period ? date(s.period) : ''}</div>
        <div class="t2">${s.lines ?? 0} reclamación(es) · ${money(s.claimed || 0)} · <span class="pill ${s.status === 'radicada' ? 'ok' : ''}">${s.status_name || s.status}</span></div></div>
        <a class="btn sm" href="#/radicaciones/${s.id}">Ir a radicar</a></div>`)}</div>`);
    } catch (err) { paint(lotesBox, html`<div class="note bad">${friendlyError(err)}</div>`); }
  };

  async function captureOne(v) {
    const provider = S.providers.find((p) => p.id === v.provider);
    const ars = S.ars.find((a) => a.id === v.ars);
    const entry = { patient: v.patientName, providerName: provider?.full_name || '', serviceDate: v.serviceDate, ok: false };
    try {
      const dup = await findDuplicateClaim({ providerId: v.provider, memberNumber: v.member, serviceDate: v.serviceDate, procedureId: v.procedure, authorization: v.authorization });
      if (dup && dup.service_date === v.serviceDate) { entry.duplicate = dup; results.unshift(entry); drawSummary(); return entry; }
      const result = await capturarConDiagnostico(v);
      entry.ok = true; entry.folio = result.folio;
      if (result.submission_id) submissionIds.push(result.submission_id);
      results.unshift(entry); drawSummary(); await refreshLotes();
    } catch (err) {
      entry.error = friendlyError(err); results.unshift(entry); drawSummary();
    }
    return entry;
  }

  $('#one', main).addEventListener('click', async () => {
    const result = await formDialog({
      title: 'Capturar reclamación histórica', submitLabel: 'Capturar', wide: true,
      body: html`<div class="form-grid">
        <div class="field"><label>Médico *</label><select name="provider" required><option value="">Seleccione…</option>${S.providers.map((p) => opt(p.id, p.full_name))}</select></div>
        <div class="field"><label>ARS *</label><select name="ars" required><option value="">Seleccione…</option>${S.ars.map((a) => opt(a.id, a.name))}</select></div>
        <div class="field"><label>Fecha del servicio *</label><input name="service_date" type="date" required max="${new Date().toISOString().slice(0, 10)}"></div>
        <div class="field"><label>Modalidad</label><select name="care_mode">${['ambulatorio', 'emergencia', 'internamiento'].map((x) => opt(x, x))}</select></div>
        <div class="field" style="grid-column:1/-1"><label>Paciente *</label><input name="patient" required></div>
        <div class="field"><label>NSS / Afiliado *</label><input name="member" required></div>
        <div class="field"><label>Autorización</label><input name="authorization"></div>
        <div class="field" style="grid-column:1/-1"><label>Servicio *</label><select name="service" required><option value="">Elija médico, ARS y fecha primero</option></select></div>
        <div class="field"><label>Cantidad</label><input name="quantity" type="number" min="1" value="1"></div>
        <div class="field"><label>Monto</label><input name="amount" type="number" min="0" step="0.01"><span class="hint">Vacío = tarifa contractual.</span></div>
        <div class="field" style="grid-column:1/-1"><label>Notas</label><textarea name="notes" rows="2" placeholder="Ej.: capturada de WhatsApp del 12/10, registro de Leimy"></textarea></div>
      </div>`,
      onOpen: (form) => {
        const loadServices = async () => {
          const p = form.elements.provider.value, a = form.elements.ars.value, d = form.elements.service_date.value, s = form.elements.service;
          if (!p || !a || !d) { paint(s, html`<option value="">Elija médico, ARS y fecha primero</option>`); return; }
          paint(s, html`<option value="">Cargando…</option>`);
          try {
            const rows = await contractedServices(p, a, d);
            paint(s, html`<option value="">Seleccione…</option>${rows.map((x) => html`<option value="${x.procedure_id}">${x.name}${x.cups ? ` · CUPS ${x.cups}` : ''} · ${money(x.amount)}</option>`)}`);
          } catch { paint(s, html`<option value="">No se pudo cargar el tarifario</option>`); }
        };
        ['provider', 'ars', 'service_date'].forEach((n) => form.elements[n].addEventListener('change', loadServices));
      },
      onSubmit: async (d, form) => {
        if (!requireFields(form, ['provider', 'ars', 'service_date', 'patient', 'member', 'service'])) return false;
        const r = await captureOne({
          provider: d.provider, ars: d.ars, serviceDate: d.service_date, careMode: d.care_mode, patientName: d.patient.trim(),
          member: d.member.trim(), authorization: d.authorization?.trim() || null, procedure: d.service, quantity: Number(d.quantity) || 1,
          amount: d.amount ? Number(d.amount) : null, notes: d.notes?.trim() || 'Puesta al día: captura histórica'
        });
        if (r.duplicate) { toast(`Ya existe como ${r.duplicate.folio} — no se duplicó`, 'warn'); return true; }
        if (!r.ok) { toast(r.error, 'bad'); return false; }
        toast(`Reclamación ${r.folio} capturada`, 'ok');
        return true;
      }
    });
    if (result) { /* el formulario no se reabre: usar + Capturar reclamación de nuevo para otra */ }
  });

  const file = $('#pad-csv', main), loadCsv = $('#loadCsv', main);
  file.addEventListener('change', () => { loadCsv.disabled = !file.files?.length; });
  loadCsv.addEventListener('click', () => busy(loadCsv, async () => {
    const f = file.files?.[0]; if (!f) return;
    const rows = parseCsv(await f.text());
    if (rows.length < 2) { toast('El archivo no tiene filas para cargar', 'bad'); return; }
    const headers = rows[0].map((h) => String(h).trim());
    const objs = rows.slice(1).map((r) => Object.fromEntries(headers.map((h, i) => [h, r[i] ?? ''])));
    if (!(await confirmBulk(objs.length))) return;
    for (const r of objs) {
      const provider = S.providers.find((p) => norm(p.full_name) === norm(r['Médico']));
      const ars = S.ars.find((a) => norm(a.name) === norm(r['ARS']) || norm(a.code) === norm(r['ARS']));
      const serviceDate = parseDate(r['Fecha del servicio']);
      if (!provider || !ars || !serviceDate || !r['Paciente'] || !r['NSS / Afiliado'] || !r['Servicio']) {
        results.unshift({ patient: r['Paciente'] || '(fila inválida)', providerName: r['Médico'] || '', serviceDate, ok: false, error: 'Faltan datos obligatorios o el médico/ARS no coincide con SOFA' });
        drawSummary(); continue;
      }
      let procedure = null;
      try {
        const services = await contractedServices(provider.id, ars.id, serviceDate);
        const wanted = norm(r['Servicio']);
        procedure = services.find((s) => [s.name, s.cups, s.simon, s.internal_code].some((v) => norm(v) === wanted))?.procedure_id || null;
      } catch { /* se reporta abajo */ }
      if (!procedure) {
        results.unshift({ patient: r['Paciente'], providerName: provider.full_name, serviceDate, ok: false, error: 'Servicio no contratado o no coincide con el catálogo' });
        drawSummary(); continue;
      }
      await captureOne({
        provider: provider.id, ars: ars.id, serviceDate, careMode: norm(r['Modalidad']) || 'ambulatorio', patientName: r['Paciente'].trim(),
        member: r['NSS / Afiliado'].trim(), authorization: r['Autorización']?.trim() || null, patientDoc: r['Cédula']?.trim() || null,
        procedure, quantity: Math.max(1, Math.trunc(Number(r['Cantidad']) || 1)), amount: Number(r['Monto']) || null,
        notes: `Puesta al día (CSV) · ${r['Notas']?.trim() || ''}`.trim()
      });
    }
    toast('Carga terminada', 'ok');
  }));

  async function confirmBulk(n) {
    return confirmDialog('Cargar lote', `Se intentarán capturar ${n} fila(s). Las que ya existan en SOFA no se duplicarán; se listarán como "Ya existe".`, 'Cargar');
  }

  drawSummary(); await refreshLotes();
}
export default render;
