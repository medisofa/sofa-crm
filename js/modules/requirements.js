/**
 * SOFA · Requisitos documentales (Iteración 13). Reglas por tipo de servicio, servicio concreto, ARS y modalidad.
 * Para cada documento gana la regla más específica (servicio > tipo de servicio; con ARS > sin ARS; con modalidad > sin ella).
 * Una regla "No requerido" exime el documento (p. ej., una ARS que no pide copia del carnet).
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, opt, formDialog, fieldError } from '../utils/ui.js';
import { dateTime } from '../utils/formatters.js';
import { can } from '../utils/permissions.js';
import { activeArs, searchCatalog } from '../services/claims.js';
import { listRules, saveRule, documentTypes, serviceTypes, requiredDocsPreview } from '../services/dossier.js';

const REQ = { obligatorio: ['Obligatorio', 'bad'], opcional: ['Opcional', ''], no_requerido: ['No requerido', 'ok'] };
const MODES = [['', 'Cualquier modalidad'], ['ambulatorio', 'Ambulatorio'], ['emergencia', 'Emergencia'], ['internamiento', 'Internamiento']];
const scope = (r) => [r.procedures ? `Servicio: ${r.procedures.description}` : r.service_types ? `Tipo: ${r.service_types.name}` : 'Todos los servicios',
  r.ars ? `ARS: ${r.ars.name}` : 'Todas las ARS', r.care_mode ? `Modalidad: ${MODES.find(([v]) => v === r.care_mode)?.[1]}` : 'Cualquier modalidad'];

export async function render(main, ctx) {
  const edit = can('rules.edit', ctx.role);
  const st = { docType: '', serviceType: '', arsId: '', careMode: '', q: '', onlyActive: true };
  const [types, stypes, ars] = await Promise.all([documentTypes(), serviceTypes(), activeArs()]).catch(() => [[], [], []]);
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Requisitos documentales</h2>
      <p>Qué documentos exige cada expediente. Para cada documento gana la regla <b>más específica</b>: servicio concreto antes que tipo de servicio, con ARS antes que sin ARS, con modalidad antes que sin ella.</p></div>
      <div class="toolbar" style="margin:0"><button class="btn" id="prev">¿Qué se exige para…?</button>${edit ? html`<button class="btn primary" id="new">+ Nueva regla</button>` : ''}</div></div>
    <div class="toolbar">
      <label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Servicio, ARS, documento o nota">
      <label class="sr-only" for="fd">Documento</label><select class="input" id="fd" style="width:auto"><option value="">Todos los documentos</option>${types.map((t) => opt(t.code, t.name))}</select>
      <label class="sr-only" for="fs">Tipo de servicio</label><select class="input" id="fs" style="width:auto"><option value="">Todos los tipos</option>${stypes.map((t) => opt(t.code, t.name))}</select>
      <label class="sr-only" for="fa">ARS</label><select class="input" id="fa" style="width:auto"><option value="">Todas las ARS</option>${ars.map((a) => opt(a.id, a.name))}</select>
      <label class="sr-only" for="fm">Modalidad</label><select class="input" id="fm" style="width:auto">${MODES.map(([v, l]) => opt(v, v ? l : 'Todas las modalidades'))}</select>
      <label class="check"><input type="checkbox" id="act" checked> Solo activas</label>
    </div><div id="l"></div>`);

  const list = $('#l', main); let rows = [];
  const load = () => loadInto(list, () => listRules(st), (r) => { rows = r; return html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Documento</th><th>Exigencia</th><th>Alcance</th><th>Nota</th><th>Origen</th>${edit ? html`<th></th>` : ''}</tr></thead>
    <tbody>${r.map((x) => { const [l, c] = REQ[x.requirement] || [x.requirement, '']; return html`<tr style="${x.is_active ? '' : 'opacity:.55'}">
      <td data-l="Documento"><b>${x.document_types?.name || x.document_type_code}</b></td>
      <td data-l="Exigencia"><span class="pill ${c}">${l}</span>${x.is_active ? '' : html` <span class="pill">Inactiva</span>`}</td>
      <td data-l="Alcance" class="small">${scope(x).map((s) => html`<div>${s}</div>`)}</td>
      <td data-l="Nota" class="small">${x.notes || '—'}</td>
      <td data-l="Origen" class="small muted">${x.source}<div>${dateTime(x.updated_at)}</div></td>
      ${edit ? html`<td><button class="btn sm" data-edit="${x.id}">Editar</button></td>` : ''}</tr>`; })}</tbody></table></div>`; },
  { isEmpty: (r) => !r.length, empty: () => emptyView('Sin reglas', 'No hay reglas con estos filtros.') });

  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; load(); }, 300); });
  [['#fd', 'docType'], ['#fs', 'serviceType'], ['#fa', 'arsId'], ['#fm', 'careMode']].forEach(([s, k]) => $(s, main).addEventListener('change', (e) => { st[k] = e.target.value; load(); }));
  $('#act', main).addEventListener('change', (e) => { st.onlyActive = e.target.checked; load(); });
  const open = async (rule = null) => { try { if (await ruleDialog(rule, { types, stypes, ars })) { toast('Regla guardada', 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } };
  $('#new', main)?.addEventListener('click', () => open());
  list.addEventListener('click', (e) => { const b = e.target.closest('[data-edit]'); if (b) open(rows.find((x) => x.id === b.dataset.edit)); });
  $('#prev', main).addEventListener('click', () => previewDialog(ars));
  load();
}

/** Buscador del catálogo dentro de un formulario: escribe el id elegido en input[name=procedure] */
function catalogPicker(form, current = null) {
  const q = form.querySelector('#rp_q'); const box = form.querySelector('#rp_r'); const hid = form.elements.procedure; let tm;
  const run = async () => {
    if (!q.value.trim()) { paint(box, html``); return; }
    try { const rows = await searchCatalog(q.value, 10);
      paint(box, html`${rows.map((r) => html`<label class="li" style="cursor:pointer"><input type="radio" name="rp_pick" value="${r.id}" ${hid.value === r.id ? 'checked' : ''}><div class="b"><div class="t1">${r.name}</div><div class="t2">${[r.internal_code, r.cups && `CUPS ${r.cups}`].filter(Boolean).join(' · ')}</div></div></label>`)}`); }
    catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); }
  };
  q.addEventListener('input', () => { clearTimeout(tm); tm = setTimeout(run, 300); });
  box.addEventListener('change', (e) => { if (e.target.name === 'rp_pick') { hid.value = e.target.value; form.querySelector('#rp_sel').textContent = e.target.closest('label').querySelector('.t1').textContent; } });
  if (current) form.querySelector('#rp_sel').textContent = current;
}

function ruleDialog(rule, { types, stypes, ars }) {
  const r = rule || {};
  return formDialog({
    title: rule ? 'Editar regla documental' : 'Nueva regla documental', submitLabel: 'Guardar regla', wide: true,
    body: html`<div class="form-grid">
      <div class="field"><label for="r_doc">Documento *</label><select id="r_doc" name="docType"><option value="">Seleccione…</option>${types.map((t) => opt(t.code, t.name, r.document_type_code))}</select></div>
      <div class="field"><label for="r_req">Exigencia *</label><select id="r_req" name="requirement">${Object.entries(REQ).map(([k, [l]]) => opt(k, l, r.requirement || 'obligatorio'))}</select></div>
      <div class="field"><label for="r_st">Tipo de servicio</label><select id="r_st" name="serviceType"><option value="">Todos (o un servicio concreto abajo)</option>${stypes.map((t) => opt(t.code, t.name, r.service_type_code))}</select></div>
      <div class="field"><label for="r_ars">ARS</label><select id="r_ars" name="ars"><option value="">Todas las ARS</option>${ars.map((a) => opt(a.id, a.name, r.ars_id))}</select></div>
      <div class="field"><label for="r_mode">Modalidad</label><select id="r_mode" name="careMode">${MODES.map(([v, l]) => opt(v, l, r.care_mode || ''))}</select></div>
      <div class="field" style="grid-column:1/-1"><label for="rp_q">Servicio concreto (opcional; reemplaza el tipo de servicio)</label>
        <input id="rp_q" type="search" placeholder="Buscar en el catálogo maestro" autocomplete="off"><input type="hidden" name="procedure" value="${r.procedure_id || ''}">
        <div class="small">Elegido: <b id="rp_sel">ninguno</b> <a href="#" id="rp_clear">quitar</a></div><div id="rp_r" class="list" style="max-height:180px;overflow:auto"></div></div>
      <div class="field" style="grid-column:1/-1"><label for="r_n">Nota (por qué existe la regla)</label><input id="r_n" name="notes" maxlength="300" value="${r.notes || ''}"></div>
      ${rule ? html`<label class="check"><input type="checkbox" name="active" ${r.is_active ? 'checked' : ''}> Regla activa</label>` : ''}</div>
      <p class="small muted">Las reclamaciones abiertas toman la regla de inmediato. Las radicadas no cambian.</p>`,
    onOpen: (form) => {
      catalogPicker(form, r.procedures?.description);
      form.querySelector('#rp_clear').addEventListener('click', (e) => { e.preventDefault(); form.elements.procedure.value = ''; form.querySelector('#rp_sel').textContent = 'ninguno'; });
    },
    onSubmit: async (d, form) => {
      if (!d.docType) { fieldError(form.elements.docType, 'Seleccione el documento'); return false; }
      if (d.procedure && d.serviceType) { fieldError(form.elements.serviceType, 'Use servicio concreto o tipo de servicio, no ambos'); return false; }
      return saveRule({ id: rule?.id, docType: d.docType, requirement: d.requirement, serviceType: d.serviceType, ars: d.ars, careMode: d.careMode, procedure: d.procedure, notes: d.notes?.trim(), active: rule ? !!d.active : true });
    }
  });
}

/** Vista previa: qué documentos exige el expediente para un servicio, ARS y modalidad */
function previewDialog(ars) {
  return formDialog({
    title: '¿Qué se exige para…?', submitLabel: 'Cerrar', wide: true,
    body: html`<div class="form-grid">
      <div class="field" style="grid-column:1/-1"><label for="rp_q">Servicio *</label><input id="rp_q" type="search" placeholder="Buscar en el catálogo maestro" autocomplete="off"><input type="hidden" name="procedure">
        <div class="small">Elegido: <b id="rp_sel">ninguno</b></div><div id="rp_r" class="list" style="max-height:160px;overflow:auto"></div></div>
      <div class="field"><label for="pv_a">ARS</label><select id="pv_a" name="ars"><option value="">Sin ARS específica</option>${ars.map((a) => opt(a.id, a.name))}</select></div>
      <div class="field"><label for="pv_m">Modalidad</label><select id="pv_m" name="mode">${MODES.slice(1).map(([v, l]) => opt(v, l, 'ambulatorio'))}</select></div></div>
      <div id="pv_out" aria-live="polite"></div>`,
    onOpen: (form) => {
      catalogPicker(form);
      const out = form.querySelector('#pv_out');
      const run = async () => {
        if (!form.elements.procedure.value) { paint(out, html`<p class="small muted">Elija un servicio.</p>`); return; }
        try {
          const rows = await requiredDocsPreview(form.elements.procedure.value, form.elements.ars.value || null, form.elements.mode.value);
          paint(out, html`<div class="list">${rows.map((x) => { const [l, c] = REQ[x.requirement] || [x.requirement, '']; return html`<div class="li"><div class="b"><div class="t1">${x.name}</div><div class="t2">Regla de especificidad ${x.specificity}</div></div><span class="pill ${c}">${l}</span></div>`; })}</div>`);
        } catch (err) { paint(out, html`<div class="note bad">${friendlyError(err)}</div>`); }
      };
      form.addEventListener('change', run); run();
    },
    onSubmit: async () => true
  });
}
