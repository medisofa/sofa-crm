/**
 * SOFA · Tarifario contractual (Iteración 12, §4–§6 y §11).
 * El servicio define QUÉ se factura; el contrato Médico × ARS define CUÁNTO, con vigencia.
 * Nunca se edita un monto: un cambio crea una nueva vigencia y la anterior se conserva.
 */
import { html, render as paint, $, debounceSearch } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, opt, busy, formDialog, fieldError, loadingView } from '../utils/ui.js';
import { money, num, date, todayISO } from '../utils/formatters.js';
import { CONTRACT_STATUS } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';
import { downloadCsv } from '../utils/filters.js';
import { CONFIG } from '../config.js';
import { viewAsState } from '../utils/view-as-state.js';
import { editTariffPrice, formatTariffAmount } from './tariff-price-editor.js';
import { pager } from './clients.js';
import {
  listContracts, contractHistory, createContractTariff, setContractStatus, importContracts, captureProviders, activeArs, searchCatalog
} from '../services/claims.js';

const IMPORT_COLS = ['medico', 'ars', 'servicio', 'simon', 'cups', 'tarifa', 'desde', 'hasta', 'contrato'];
const norm = (s) => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z]/g, '');
const ALIASES = { medico: ['medico', 'cliente', 'prestador', 'doctor'], ars: ['ars', 'aseguradora'], servicio: ['servicio', 'codigointerno', 'descripcion', 'procedimiento'],
  simon: ['simon', 'codigosimon'], cups: ['cups', 'codigocups'], tarifa: ['tarifa', 'monto', 'precio', 'tarifacontratada'], desde: ['desde', 'fechainicio', 'inicio', 'iniciovigencia', 'vigentedesde'],
  hasta: ['hasta', 'fechafin', 'fin', 'finvigencia', 'vigentehasta'], contrato: ['contrato', 'referencia', 'nocontrato', 'numerocontrato'] };

/** Lee filas pegadas desde Excel (tabulador) o CSV (; o ,). Detecta encabezados por nombre; sin encabezado usa el orden estándar. */
export function parseContractRows(textIn) {
  const lines = String(textIn || '').replace(/^\uFEFF/, '').replace(/\r/g, '').split('\n').filter((l) => l.trim());
  if (!lines.length) return [];
  const sep = lines[0].includes('\t') ? '\t' : lines[0].includes(';') ? ';' : ',';
  const split = (l) => { const out = []; let cur = '', q = false; for (let i = 0; i < l.length; i += 1) { const ch = l[i]; if (ch === '"') { if (q && l[i + 1] === '"') { cur += '"'; i += 1; } else q = !q; } else if (ch === sep && !q) { out.push(cur.trim()); cur = ''; } else cur += ch; } out.push(cur.trim()); return out; };
  let rows = lines.map(split);
  let map = IMPORT_COLS.map((_, i) => i);
  const head = rows[0].map(norm);
  const found = IMPORT_COLS.map((k) => head.findIndex((h) => ALIASES[k].includes(h)));
  if (found.filter((i) => i >= 0).length >= 3) { map = found; rows = rows.slice(1); }
  return rows.map((c) => Object.fromEntries(IMPORT_COLS.map((k, i) => [k, map[i] >= 0 ? (c[map[i]] ?? '') : ''])));
}

export async function render(main, ctx) {
  const role = ctx.role; const readOnly = !!ctx.viewAs || viewAsState.active;
  const edit = can('contracts.edit', role) && !readOnly;
  const st = { providerId: '', arsId: '', q: '', status: '', onlyCurrent: true, page: 0 };
  paint(main, html`<section class="tariff-workspace" aria-label="Tarifario contractual">
    <header class="page-head tariff-head"><div class="t"><h2>Tarifario contractual</h2>
      <p>Consulta el precio de cada servicio por médico y ARS. Cambia un precio con fecha de efecto e historial.</p></div>
      <div class="tariff-actions">${edit ? html`<button class="btn primary" id="new">+ Nueva tarifa</button><button class="btn" id="imp">Importar tarifario</button>` : ''}${!readOnly ? html`<button class="btn" id="csv">Exportar CSV</button>` : ''}</div></header>
    ${readOnly ? html`<div class="note info">Modo soporte · solo lectura. Puedes consultar precios, detalles e historial.</div>` : ''}
    <div class="tariff-kpis"><div class="tariff-kpi"><strong id="tariff-result-count">—</strong><span>Tarifas encontradas</span></div>
      <div class="tariff-kpi"><strong id="tariff-period-label">Vigentes hoy</strong><span>Período mostrado</span></div>
      <div class="tariff-kpi"><strong>Con historial</strong><span>Los cambios conservan las reclamaciones anteriores</span></div></div>
    <section class="tariff-filters" aria-label="Filtrar tarifas">
      <div class="tariff-field"><label for="q">Buscar servicio o código</label><input class="input" id="q" type="search" placeholder="Servicio, SIMON, CUPS o contrato"></div>
      <div class="tariff-field"><label for="cp">Médico</label><select class="input" id="cp"><option value="">Todos los médicos</option></select></div>
      <div class="tariff-field"><label for="ca">ARS</label><select class="input" id="ca"><option value="">Todas las ARS</option></select></div>
      <div class="tariff-field"><label for="cs">Estado</label><select class="input" id="cs"><option value="">Todos los estados</option>${Object.entries(CONTRACT_STATUS).map(([k, [l]]) => opt(k, l))}</select></div>
      <label class="check"><input type="checkbox" id="cur" checked> Solo vigentes hoy</label><button class="btn" type="button" id="clear-filters">Limpiar filtros</button>
    </section>
    <p class="small muted" id="tariff-summary" aria-live="polite">Consultando tarifas…</p><div id="l"></div></section>`);
  const [provs, ars] = await Promise.all([captureProviders().catch(() => []), activeArs().catch(() => [])]);
  if (!$('#cp', main)) return;
  paint($('#cp', main), html`<option value="">Todos los médicos</option>${provs.map((p) => opt(p.id, p.full_name))}`);
  paint($('#ca', main), html`<option value="">Todas las ARS</option>${ars.map((a) => opt(a.id, a.name))}`);
  const list = $('#l', main); const summary = $('#tariff-summary', main); let current = []; let sequence = 0;
  const rowTable = (data, count) => html`<div class="table-wrap tariff-table-wrap"><table class="t tariff-table"><thead><tr><th>Médico</th><th>ARS</th><th>Servicio</th><th class="n">Precio</th><th>Vigencia</th><th>Acciones</th></tr></thead><tbody>
    ${data.map((t) => { const [label, tone] = CONTRACT_STATUS[t.status] || [t.status, '']; return html`<tr class="tariff-row">
      <td data-l="Médico">${t.provider_name}${isStaff(role) && t.client_name && t.client_name !== t.provider_name ? html`<div class="small muted">${t.client_name}</div>` : ''}</td>
      <td data-l="ARS">${t.ars_name}<div class="small muted">Plan: ${t.plan_name || (t.plan_id ? 'Específico' : 'General')}</div></td><td data-l="Servicio"><b>${t.service_name}</b></td>
      <td data-l="Precio" class="n tariff-price"><b>${formatTariffAmount(t.amount, t.currency || 'DOP')}</b></td>
      <td data-l="Vigencia">${date(t.valid_from)} – ${t.valid_to ? date(t.valid_to) : 'abierta'}<div><span class="pill ${tone}">${label}</span>${t.is_current ? html` <span class="pill ok">Hoy</span>` : ''}</div></td>
      <td data-l="Acciones"><div class="tariff-row-actions">${edit && t.is_current && t.status === 'vigente' ? html`<button class="btn primary" type="button" data-change="${t.id}">Cambiar precio</button>` : ''}<button class="btn" type="button" data-details="${t.id}" aria-expanded="false" aria-controls="tariff-detail-${t.id}">Detalles</button></div></td></tr>
      <tr class="tariff-detail-row" id="tariff-detail-${t.id}" data-detailrow="${t.id}" hidden><td colspan="6"><div class="tariff-detail-grid">
        <dl><dt>Código interno</dt><dd class="mono">${t.internal_code || '—'}</dd><dt>SIMON</dt><dd>${t.simon || '—'}</dd><dt>CUPS</dt><dd>${t.cups || '—'}</dd></dl>
        <dl><dt>Código de servicio ARS</dt><dd>${t.ars_service_code || '—'}</dd><dt>Contrato</dt><dd>${t.contract_ref || '—'}</dd><dt>Plan</dt><dd>${t.plan_name || (t.plan_id ? 'Plan específico' : 'General')}</dd><dt>Fuente</dt><dd>${t.source || '—'}</dd></dl>
        <dl><dt>Estado</dt><dd>${label}</dd><dt>Reclamaciones vinculadas</dt><dd>${num(t.claims)}</dd><dt>Moneda</dt><dd>${t.currency || 'DOP'}</dd></dl>
      </div><div class="tariff-row-actions"><button class="btn" type="button" data-hist="${t.id}">Ver historial</button>${edit ? html`<button class="btn" type="button" data-st="${t.id}">Cambiar estado</button>` : ''}</div></td></tr>`; })}
    </tbody></table></div>${pager(count, st.page)}`;
  async function reload() {
    const my = ++sequence; paint(list, loadingView(4)); summary.textContent = 'Consultando tarifas…';
    try {
      const result = await listContracts({ ...st, size: CONFIG.PAGE_SIZE });
      if (my !== sequence || !list.isConnected) return;
      current = result.data || []; const count = result.count ?? current.length;
      $('#tariff-result-count', main).textContent = num(count);
      $('#tariff-period-label', main).textContent = st.onlyCurrent ? 'Vigentes hoy' : 'Todas las vigencias';
      const filters = [st.providerId ? provs.find((p) => p.id === st.providerId)?.full_name || 'Médico seleccionado' : 'Todos los médicos', st.arsId ? ars.find((a) => a.id === st.arsId)?.name || 'ARS seleccionada' : 'Todas las ARS'];
      summary.textContent = `${num(count)} tarifa(s) encontrada(s) · ${current.length ? `mostrando ${st.page * CONFIG.PAGE_SIZE + 1}–${st.page * CONFIG.PAGE_SIZE + current.length}` : 'sin resultados'} · ${filters.join(' · ')}.`;
      paint(list, current.length ? rowTable(current, count) : emptyView('Sin tarifas con estos filtros', 'Prueba otro médico, ARS o servicio. Las combinaciones sin tarifa siguen pendientes de configuración.', edit ? html`<button class="btn primary" data-new>+ Nueva tarifa</button>` : ''));
    } catch (err) {
      if (my !== sequence || !list.isConnected) return;
      current = []; $('#tariff-result-count', main).textContent = '—'; summary.textContent = 'No se pudo consultar el tarifario.';
      paint(list, html`<div class="note bad" role="alert">${friendlyError(err)}</div><button class="btn" type="button" data-retry-contracts>Reintentar</button>`);
    }
  }
  debounceSearch($('#q', main), st, reload);
  $('#cp', main).addEventListener('change', (e) => { st.providerId = e.target.value; st.page = 0; reload(); });
  $('#ca', main).addEventListener('change', (e) => { st.arsId = e.target.value; st.page = 0; reload(); });
  $('#cs', main).addEventListener('change', (e) => { st.status = e.target.value; st.page = 0; reload(); });
  $('#cur', main).addEventListener('change', (e) => { st.onlyCurrent = e.target.checked; st.page = 0; reload(); });
  $('#clear-filters', main).addEventListener('click', () => {
    Object.assign(st, { providerId: '', arsId: '', q: '', status: '', onlyCurrent: true, page: 0 });
    ['q', 'cp', 'ca', 'cs'].forEach((id) => { $(`#${id}`, main).value = ''; }); $('#cur', main).checked = true; reload();
  });
  const openNew = async (preset = {}) => { if (!edit || viewAsState.active) return; try { if (await contractDialog(provs, ars, preset)) { toast('Tarifa contractual registrada', 'ok'); reload(); } } catch (err) { toast(friendlyError(err), 'bad'); } };
  $('#new', main)?.addEventListener('click', () => openNew());
  $('#imp', main)?.addEventListener('click', async () => { if (!edit || viewAsState.active) return; try { const r = await importDialog(); if (r) { toast(`${num(r.imported)} tarifas importadas`, 'ok'); reload(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
  $('#csv', main)?.addEventListener('click', (e) => busy(e.currentTarget, async () => {
    if (readOnly || viewAsState.active) return;
    const r = await listContracts({ ...st, page: 0, size: 5000 });
    downloadCsv(`tarifario_contractual_${todayISO()}.csv`, ['Médico', 'ARS', 'Servicio', 'Código interno', 'SIMON', 'CUPS', 'Tarifa', 'Moneda', 'Desde', 'Hasta', 'Estado', 'Contrato', 'Código ARS', 'Reclamaciones'],
      r.data.map((x) => [x.provider_name, x.ars_name, x.service_name, x.internal_code, x.simon, x.cups, x.amount, x.currency, x.valid_from, x.valid_to, CONTRACT_STATUS[x.status]?.[0], x.contract_ref, x.ars_service_code, x.claims]));
  }));
  list.addEventListener('click', async (e) => {
    const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); reload(); return; }
    if (e.target.closest('[data-retry-contracts]')) { reload(); return; }
    if (e.target.closest('[data-new]')) { openNew(); return; }
    const row = (key) => current.find((x) => x.id === e.target.closest(`[data-${key}]`)?.dataset[key]);
    const details = e.target.closest('[data-details]');
    if (details) { const target = document.getElementById(details.getAttribute('aria-controls')); if (target && list.contains(target)) { target.hidden = !target.hidden; details.setAttribute('aria-expanded', String(!target.hidden)); } return; }
    if (e.target.closest('[data-hist]')) { const x = row('hist'); if (x) historyDialog(x); return; }
    if (!edit || viewAsState.active) return;
    if (e.target.closest('[data-change]')) {
      const x = row('change'); if (!x || !x.is_current || x.status !== 'vigente') return;
      try { const changed = await editTariffPrice(x, { readOnly }); if (changed) { toast('Nuevo precio registrado. El historial se conservó.', 'ok'); reload(); } }
      catch (err) { toast(friendlyError(err), 'bad'); } return;
    }
    if (e.target.closest('[data-st]')) {
      const x = row('st'); if (!x) return;
      const changed = await formDialog({ title: 'Estado de la tarifa', submitLabel: 'Guardar',
        body: html`<p class="small">${x.provider_name} · ${x.ars_name} · ${x.service_name} · ${formatTariffAmount(x.amount, x.currency || 'DOP')}</p>
          <div class="field"><label for="ss">Estado</label><select id="ss" name="status">${Object.entries(CONTRACT_STATUS).map(([k, [label]]) => opt(k, label, x.status))}</select><span class="hint">El estado no cambia el precio ni las reclamaciones anteriores.</span></div>
          <div class="field"><label for="sn">Comentario (opcional)</label><input id="sn" name="notes" maxlength="300"></div>`,
        onSubmit: async (data) => { if (viewAsState.active) throw new Error('El modo soporte es de solo lectura.'); await setContractStatus(x.id, data.status, String(data.notes || '').trim() || undefined); return true; } }).catch((err) => { toast(friendlyError(err), 'bad'); });
      if (changed) { toast('Estado actualizado', 'ok'); reload(); }
    }
  });
  await reload();
}

/** Nueva tarifa o nueva vigencia (la anterior abierta se cierra el día previo; nunca se sobrescribe) */
export function contractDialog(provs, ars, preset = {}) {
  if (viewAsState.active || preset.readOnly) return Promise.resolve(false);
  let pick = preset.procedure ? { id: preset.procedure, name: preset.service } : null;
  return formDialog({
    title: preset.procedure ? 'Nueva vigencia de tarifa' : 'Nueva tarifa contractual', submitLabel: 'Registrar', wide: true,
    body: html`<div class="form-grid">
      <div class="field"><label for="k_p">Médico *</label><select id="k_p" name="provider" required><option value="">Seleccione…</option>${provs.map((p) => opt(p.id, p.full_name, preset.provider))}</select></div>
      <div class="field"><label for="k_a">ARS *</label><select id="k_a" name="ars" required><option value="">Seleccione…</option>${ars.map((a) => opt(a.id, a.name, preset.ars))}</select></div>
      <div class="field" style="grid-column:1/-1"><label for="k_q">Servicio del catálogo maestro *</label>
        ${pick ? html`<div class="note"><b>${pick.name}</b></div>` : html`<input id="k_q" type="search" placeholder="Buscar por nombre, código interno, SIMON o CUPS" autocomplete="off"><div id="k_r" class="list" style="max-height:200px;overflow:auto"></div>`}</div>
      <div class="field"><label for="k_m">Tarifa contratada (RD$) *</label><input id="k_m" name="amount" type="number" min="0.01" step="0.01" required inputmode="decimal"></div>
      <div class="field"><label for="k_f">Vigente desde *</label><input id="k_f" name="valid_from" type="date" required value="${todayISO()}"></div>
      <div class="field"><label for="k_t">Vigente hasta</label><input id="k_t" name="valid_to" type="date"><span class="hint">Vacío = abierta. Una vigencia nueva cierra la anterior abierta el día previo.</span></div>
      <div class="field"><label for="k_c">No. / referencia de contrato</label><input id="k_c" name="contract_ref" maxlength="80" value="${preset.contractRef || ''}"></div>
      <div class="field"><label for="k_ac">Código particular de la ARS / autorización</label><input id="k_ac" name="ars_code" maxlength="40"></div>
      <div class="field"><label for="k_n">${preset.requireReason ? 'Motivo del cambio (mínimo 10 caracteres)' : 'Observaciones'}</label><input id="k_n" name="notes" maxlength="300"></div></div>`,
    onOpen: (form) => {
      const q = form.querySelector('#k_q'); if (!q) return;
      const box = form.querySelector('#k_r'); let tm;
      const run = async () => { try { const rows = await searchCatalog(q.value, 15);
        paint(box, html`${rows.map((r) => html`<label class="li" style="cursor:pointer"><input type="radio" name="proc" value="${r.id}" data-name="${r.name}"><div class="b"><div class="t1">${r.name}</div><div class="t2">${[r.internal_code, r.simon && `SIMON ${r.simon}`, r.cups && `CUPS ${r.cups}`].filter(Boolean).join(' · ')}</div></div></label>`)}`); } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); } };
      q.addEventListener('input', () => { clearTimeout(tm); tm = setTimeout(run, 300); }); run();
      box.addEventListener('change', (e) => { if (e.target.name === 'proc') pick = { id: e.target.value, name: e.target.dataset.name }; });
    },
    onSubmit: async (d, form) => {
      if (viewAsState.active) throw new Error('El modo soporte es de solo lectura.');
      let ok = true;
      [['provider', 'Seleccione el médico'], ['ars', 'Seleccione la ARS'], ['valid_from', 'Indique la fecha']].forEach(([k, m]) => { if (!d[k]) { fieldError(form.elements[k], m); ok = false; } else fieldError(form.elements[k], ''); });
      if (!(Number(d.amount) > 0)) { fieldError(form.elements.amount, 'Debe ser mayor que cero'); ok = false; }
      if (d.valid_to && d.valid_to < d.valid_from) { fieldError(form.elements.valid_to, 'Anterior al inicio'); ok = false; }
      if (preset.requireReason && String(d.notes || '').trim().length < 10) { fieldError(form.elements.notes, 'Indique el motivo del cambio (mínimo 10 caracteres)'); ok = false; }
      if (!pick) { toast('Seleccione el servicio del catálogo', 'bad'); ok = false; }
      if (!ok) return false;
      return (preset.onSave || createContractTariff)({ provider: d.provider, ars: d.ars, procedure: pick.id, amount: d.amount, validFrom: d.valid_from, validTo: d.valid_to, contractRef: d.contract_ref, arsCode: d.ars_code, notes: d.notes });
    }
  });
}

function historyDialog(x) {
  return formDialog({ title: `Historial · ${x.service_name}`, submitLabel: 'Cerrar', wide: true,
    body: html`<p class="small">${x.provider_name} · ${x.ars_name} · Plan ${x.plan_name || (x.plan_id ? 'específico' : 'General')}</p><div id="hh"></div>`,
    onOpen: async (form) => {
      const box = form.querySelector('#hh'); paint(box, loadingView(2));
      try {
        const rows = await contractHistory(x.provider_id, x.ars_id, x.procedure_id, x.plan_id || null);
        paint(box, html`<div class="table-wrap"><table class="t"><thead><tr><th>Vigencia</th><th class="n">Tarifa</th><th>Estado</th><th>Contrato / fuente</th><th class="n">Reclamaciones</th></tr></thead><tbody>
          ${rows.map((r) => html`<tr><td>${date(r.valid_from)} – ${r.valid_to ? date(r.valid_to) : 'abierta'}</td><td class="n">${money(r.amount)}</td><td>${CONTRACT_STATUS[r.status]?.[0] || r.status}</td><td class="small">${r.contract_ref || ''} ${r.source ? `· ${r.source}` : ''}${r.notes ? html`<div>${r.notes}</div>` : ''}</td><td class="n">${num(r.claims)}</td></tr>`)}</tbody></table></div>
          <p class="small muted">Las reclamaciones conservan la tarifa de la vigencia de su fecha de servicio aunque se registre una nueva.</p>`);
      } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); }
    },
    onSubmit: async () => true });
}

/** Importación masiva con reporte previo de errores (nada se guarda hasta confirmar) */
function importDialog() {
  let parsed = []; let report = null;
  return formDialog({
    title: 'Importar tarifario contractual', submitLabel: 'Importar filas válidas', wide: true,
    body: html`<p class="small">Pegue desde Excel (copiar las celdas) o suba un CSV. Columnas: <span class="mono">Médico · ARS · Servicio · SIMON · CUPS · Tarifa · Desde · Hasta · Contrato</span>.
      El médico puede ir por nombre exacto, cédula/RNC o exequátur; la ARS por nombre o código; el servicio por código interno o nombre, y/o por SIMON / CUPS. Fechas DD/MM/AAAA o AAAA-MM-DD.</p>
      <p class="small"><button type="button" class="btn" id="tpl">Descargar plantilla</button></p>
      <div class="field"><label for="i_file">Archivo CSV</label><input id="i_file" type="file" accept=".csv,.txt,text/csv,text/plain"></div>
      <div class="field"><label for="i_paste">Filas</label><textarea id="i_paste" rows="7" class="input"></textarea></div>
      <div class="toolbar"><button type="button" class="btn" id="i_check">Validar (vista previa)</button><span class="small" id="i_cnt">0 filas</span></div>
      <div id="i_rep" aria-live="polite"></div>`,
    onOpen: (form) => {
      const ta = form.querySelector('#i_paste'); const rep = form.querySelector('#i_rep');
      const up = () => { parsed = parseContractRows(ta.value); report = null; paint(rep, html``); form.querySelector('#i_cnt').textContent = `${parsed.length} filas`; };
      ta.addEventListener('input', up);
      form.querySelector('#i_file').addEventListener('change', async (e) => { const f = e.target.files[0]; if (f) { ta.value = await f.text(); up(); } });
      form.querySelector('#tpl').addEventListener('click', () => downloadCsv('plantilla_tarifario_contractual.csv', ['Médico', 'ARS', 'Servicio', 'SIMON', 'CUPS', 'Tarifa', 'Desde', 'Hasta', 'Contrato'],
        [['Dra. Ana Pérez', 'ARS Humano', 'CONSULTA-ESP', '', '890201', '1800', '01/01/2026', '', 'CT-2026-015']]));
      form.querySelector('#i_check').addEventListener('click', (e) => busy(e.currentTarget, async () => {
        if (!parsed.length) { fieldError(ta, 'Pegue al menos una fila'); return; }
        try {
          report = await importContracts(parsed, false);
          paint(rep, html`<div class="note ${report.errors.length ? 'warn' : 'ok'}">${num(report.total)} filas · <b>${num(report.valid)} válidas</b> · <b>${num(report.errors.length)} con errores</b></div>
            ${report.errors.length ? html`<div class="table-wrap" style="max-height:220px;overflow:auto"><table class="t"><thead><tr><th>Fila</th><th>Errores</th><th>Datos</th></tr></thead><tbody>
              ${report.errors.map((r) => html`<tr><td>${r.row}</td><td style="color:var(--bad)">${r.errors.join(' · ')}</td><td class="small">${[r.data.medico, r.data.ars, r.data.servicio || r.data.cups || r.data.simon, r.data.tarifa].join(' · ')}</td></tr>`)}</tbody></table></div>
              <p class="small">Corrija estas filas en el archivo y vuelva a validar. La importación solo se confirma sin errores.</p>` : ''}
            ${report.rows.length ? html`<details><summary class="small">Ver filas válidas (${num(report.rows.length)})</summary><div class="table-wrap" style="max-height:220px;overflow:auto"><table class="t"><tbody>
              ${report.rows.map((r) => html`<tr><td>${r.row}</td><td>${r.provider}</td><td>${r.ars}</td><td>${r.service}</td><td class="n">${money(r.amount)}</td><td>${date(r.valid_from)}${r.valid_to ? ` – ${date(r.valid_to)}` : ''}</td></tr>`)}</tbody></table></div></details>` : ''}`);
        } catch (err) { paint(rep, html`<div class="note bad">${friendlyError(err)}</div>`); }
      }));
    },
    onSubmit: async (d, form) => {
      if (!report) { toast('Primero valide las filas (vista previa)', 'bad'); form.querySelector('#i_check').focus(); return false; }
      if (report.errors.length) { toast('Corrija las filas con errores antes de importar', 'bad'); return false; }
      return importContracts(parsed, true);
    }
  });
}
