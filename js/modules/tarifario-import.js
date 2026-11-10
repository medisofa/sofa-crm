/** SOFA · 2.2 · Iteración 32 · Carga del tarifario de una ARS desde Excel (o CSV) para un médico del cliente.
 *  2.6.1: plan opcional (la tarifa del plan manda sobre la general) y renegociación cada 2 años, visible solo para SOFA.
 *  Pasos: elegir ARS, médico y vigencia → subir el archivo → revisar la vista previa (nueva, cambia, igual, con error) → confirmar.
 *  Usa public.import_contract_tariffs_v2 (116), que valida igual que el Tarifario contractual y omite las tarifas iguales. */
import { rpc, h, money, fmtDate, note, guarded } from '../services/iter18.js';
import { codeExceptionEditor } from './tariff-code-exceptions.js';
import { readTable, excelDate, detectColumns, normHead } from '../utils/xlsx-lite.js';

const ALIASES = {
  servicio: ['servicio', 'codigo interno', 'codigo', 'cod', 'procedimiento', 'concepto', 'prestacion'],
  descripcion: ['descripcion', 'texto', 'detalle'],
  simon: ['simon', 'codigo simon'], cups: ['cups', 'codigo cups'],
  tarifa: ['tarifa', 'monto', 'precio', 'valor', 'tarifa rd', 'importe'],
  desde: ['desde', 'vigencia desde', 'inicio', 'fecha inicio'], hasta: ['hasta', 'vigencia hasta', 'fin', 'fecha fin']
};
const CHANGE = { nueva: ['Nueva', 'st-prep'], cambia: ['Cambia', 'st-req'], igual: ['Igual (se omite)', 'st-none'] };

export async function mountTariffImport(box, { orgId, canEdit, isStaff = false }) {
  const top = h('div'); const hist = h('div', { 'aria-live': 'polite' }); const exp = h('div', { 'aria-live': 'polite' });
  box.replaceChildren(top, isStaff ? h('h3', {}, 'Renegociación (próximos 120 días)') : '', isStaff ? exp : '', h('h3', {}, 'Historial de cargas'), hist);
  if (isStaff) drawExpiring();
  drawHistory();
  if (!canEdit) { top.replaceChildren(note('La carga de tarifarios la hace Administración o Facturación de SOFA.')); return; }
  const m = await guarded(top, () => rpc('client_ars_matrix', { p_org: orgId }));
  if (!m) return;
  if (!m.providers.length) { top.replaceChildren(note('Agregue primero un prestador en la pestaña Resumen.')); return; }
  const ars = h('select', { id: 'ti-ars' }, h('option', { value: '' }, 'Elija la ARS'), m.ars.map((a) => h('option', { value: a.id }, a.name)));
  const plan = h('select', { id: 'ti-plan' }, h('option', { value: '' }, 'Todos los planes (tarifa general)'));
  const cat = await rpc('ars_catalog', { p_include_inactive: false }).catch(() => []);
  ars.addEventListener('change', () => {
    const a = cat.find((x) => x.id === ars.value);
    plan.replaceChildren(h('option', { value: '' }, 'Todos los planes (tarifa general)'),
      ...((a && a.plans) || []).map((p) => h('option', { value: p.id }, p.name)));
  });
  const prov = h('select', { id: 'ti-prov' }, m.providers.map((p) => h('option', { value: p.id }, p.name)));
  const from = h('input', { id: 'ti-from', type: 'date', value: new Date().toISOString().slice(0, 10) });
  const to = h('input', { id: 'ti-to', type: 'date' });
  const contract = h('input', { id: 'ti-ct', placeholder: 'Ej.: Contrato ARS 2026', maxlength: '120' });
  const contractHelp = h('p', { class: 'i18-sub', 'aria-live': 'polite' }, 'Seleccione médico y ARS para consultar el contrato.');
  const file = h('input', { id: 'ti-file', type: 'file', accept: '.xlsx,.csv,.txt', multiple: true, 'aria-describedby': 'ti-files-help' });
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Revisar archivos');
  const tpl = h('button', { class: 'i18-link', type: 'button' }, 'Descargar plantilla');
  const out = h('div', { 'aria-live': 'polite' });
  const selected = h('div', { id: 'ti-files-help', class: 'i18-sub' }, 'Seleccione uno o varios archivos. Todos usarán la misma ARS, plan, médico y contrato. Máximo 5,000 filas entre todos los archivos.');
  top.replaceChildren(h('section', { class: 'i18-card' }, h('h3', { style: 'margin-top:0' }, 'Cargar tarifario desde Excel'),
    h('p', { class: 'i18-sub' }, 'Suba el Excel que manda la ARS. La plantilla incluye Descripción para identificar fácilmente el servicio; es informativa y no modifica el catálogo. Use Servicio o Código, SIMON o CUPS para identificar el servicio al importar. Columnas que se reconocen: Servicio o Código, SIMON, CUPS, Tarifa, Desde y Hasta (las dos últimas son opcionales: si faltan se usa la vigencia de abajo). Las ARS contratan por tiempo indefinido: deje «Hasta» vacío salvo que el contrato diga una fecha. Si el tarifario es de un plan (por ejemplo «Royal»), elíjalo: esa tarifa manda para los pacientes de ese plan. Nada se guarda hasta que usted confirme.'),
    h('div', { class: 'hc-grid i18-form', style: 'max-width:none' },
      h('label', { for: 'ti-ars' }, 'ARS', ars), h('label', { for: 'ti-plan' }, 'Plan', plan), h('label', { for: 'ti-prov' }, 'Médico', prov),
      h('label', { for: 'ti-from' }, 'Vigencia desde', from), h('label', { for: 'ti-to' }, 'Hasta (opcional)', to),
      h('label', { for: 'ti-ct' }, 'Contrato', contract, contractHelp), h('label', { for: 'ti-file', class: 'hc-wide' }, 'Archivos (.xlsx o .csv)', file)), selected,
    h('div', { class: 'i18-actions' }, go, tpl), out));
  tpl.addEventListener('click', () => {
    const csv = '﻿Servicio;Descripción;SIMON;CUPS;Tarifa;Desde;Hasta\r\nSOFA-P07;Escriba aquí la descripción del servicio;;;1500.00;01/01/2026;\r\n';
    const a = h('a', { href: URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })), download: 'plantilla_tarifario_ars.csv' });
    document.body.append(a); a.click(); a.remove();
  });

  let rows = null; let sources = []; let fname = ''; let busy = false; let saveButton = null; let saveFeedback = null;
  const contextControls = [ars, plan, prov, from, to, contract, file];
  const disabledBefore = new Map();
  function setBusy(value) {
    if (value === busy) return;
    busy = value;
    if (value) {
      [go, ...contextControls, ...out.querySelectorAll('button,input,select,textarea')].forEach((el) => {
        disabledBefore.set(el, el.disabled); el.disabled = true;
      });
    } else {
      disabledBefore.forEach((disabled, el) => { if (el.isConnected) el.disabled = disabled; });
      disabledBefore.clear();
    }
  }
  function resetReview() {
    rows = null; sources = []; saveButton = null; saveFeedback = null;
    out.replaceChildren(note('La selección cambió. Pulse «Revisar archivos» para validar los datos actuales.'));
  }
  contextControls.forEach((el) => el.addEventListener('change', resetReview));
  let contractSeq = 0;
  async function loadContract() {
    const my = ++contractSeq; contract.readOnly = true; contract.value = '';
    if (!ars.value || !prov.value) return;
    contractHelp.textContent = 'Consultando permisos del contrato…';
    try {
      const c = await rpc('ars_identifier_context', { p_provider: prov.value, p_ars: ars.value, p_plan: plan.value || null });
      if (my !== contractSeq || !contract.isConnected) return;
      contract.value = c.contract_ref || ''; contract.readOnly = !c.can_edit_contract;
      contractHelp.textContent = c.can_edit_contract
        ? (c.contract_registered ? 'Administración puede actualizar esta referencia.' : 'Primer registro permitido. Después solo Administración podrá cambiarlo.')
        : 'Referencia registrada. Solo Administrador o Super Admin puede modificarla.';
      resetReview();
    } catch(e) { if (my === contractSeq) contractHelp.textContent = e.message; }
  }
  [ars, plan, prov].forEach(el => el.addEventListener('change', loadContract));
  contract.readOnly = true;

  file.addEventListener('change', () => {
    selected.replaceChildren(h('p', {}, `${file.files.length} archivo(s) seleccionado(s). Se revisan juntos para detectar duplicados. Todos usan la ARS, plan, médico y contrato indicados arriba.`),
      h('ul', {}, [...file.files].map((f) => h('li', {}, `${f.name} (${Math.ceil(f.size / 1024)} KB)`))));
  });
  // Los cambios de texto invalidan la revisión incluso antes de salir del campo.
  [from, to, contract].forEach((el) => el.addEventListener('input', resetReview));
  function downloadCsv(name, data) {
    const cell = (v) => {
      let text = String(v ?? '');
      if (/^\s*[=+@-]/.test(text)) text = "'" + text;
      return '"' + text.replace(/"/g, '""') + '"';
    };
    const csv = '\uFEFF' + data.map((row) => row.map(cell).join(';')).join('\r\n') + '\r\n';
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const a = h('a', { href: url, download: name }); document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  function location(rowNumber) {
    const source = sources[Number(rowNumber) - 1];
    return source ? `${source.file} · fila ${source.line}` : `Fila del lote ${rowNumber}`;
  }
  function explain(message) {
    // La base numera el lote; el usuario necesita la fila del archivo original.
    return String(message).replace(/con la fila (\d+)/g, (_, n) => `con ${location(n)}`);
  }
  async function validate() {
    if (saveButton) { saveButton.disabled = true; saveButton.dataset.ready = 'false'; }
    if (saveFeedback) saveFeedback.textContent = 'Validando el lote antes de habilitar el guardado…';
    setBusy(true);
    try {
      const rep = await rpc('import_contract_tariffs_v2', { p_rows: rows, p_commit: false, p_file: fname });
      preview(rep);
    } catch (e) {
      if (saveFeedback) saveFeedback.textContent = 'No se pudo validar. Pulse «Validar para guardar» para intentarlo de nuevo.';
      out.append(note(e.message, 'error'));
    }
    finally { setBusy(false); if (saveButton) saveButton.disabled = saveButton.dataset.ready !== 'true'; }
  }
  go.addEventListener('click', async () => {
    if (busy) return;
    out.replaceChildren(); rows = null; sources = []; saveButton = null;
    if (!ars.value) return out.replaceChildren(note('Elija la ARS.', 'error'));
    if (!from.value) return out.replaceChildren(note('Indique la vigencia desde.', 'error'));
    const files = [...file.files];
    if (!files.length) return out.replaceChildren(note('Seleccione uno o varios archivos del tarifario.', 'error'));
    setBusy(true);
    try {
      const nextRows = []; const nextSources = []; const failures = [];
      for (const f of files) {
        try {
          const table = await readTable(f);
          if (table.length < 2) throw new Error('No hay filas debajo de los encabezados.');
          const map = detectColumns(table[0], ALIASES);
          const explicit = table[0].findIndex((cell) => ['servicio', 'codigo interno', 'codigo', 'cod'].includes(normHead(cell)));
          if (explicit >= 0) map.servicio = explicit;
          else if ([map.descripcion, map.simon, map.cups].includes(map.servicio)) delete map.servicio;
          // Las plantillas antiguas podían identificar el servicio solo por su descripción.
          if (map.servicio == null && map.simon == null && map.cups == null) map.servicio = map.descripcion;
          if (map.tarifa == null || (map.servicio == null && map.simon == null && map.cups == null)) {
            throw new Error('Faltan encabezados: incluya Servicio/Código, SIMON o CUPS y Tarifa.');
          }
          let count = 0;
          for (let i = 1; i < table.length; i++) {
            const r = table[i];
            const value = (key) => map[key] != null ? String(r[map[key]] ?? '') : '';
            const row = {
              medico: prov.value, ars: ars.value, plan: plan.value, contrato: contract.value.trim(),
              servicio: value('servicio'), descripcion: value('descripcion'), simon: value('simon'), cups: value('cups'), tarifa: value('tarifa'),
              desde: value('desde') ? excelDate(value('desde')) : from.value.split('-').reverse().join('/'),
              hasta: value('hasta') ? excelDate(value('hasta')) : (to.value ? to.value.split('-').reverse().join('/') : '')
            };
            if (![row.servicio, row.descripcion, row.simon, row.cups, row.tarifa].some(Boolean)) continue;
            nextRows.push(row); count++;
            nextSources.push({ file: f.name, line: r.sourceRow || i + 1, original: { ...row } });
          }
          if (!count) throw new Error('No se encontraron servicios o tarifas para revisar.');
        } catch (e) { failures.push(`${f.name}: ${e.message}`); }
      }
      if (failures.length) {
        out.replaceChildren(note('No se revisó el lote. Corrija o retire los archivos indicados y vuelva a seleccionarlos.', 'error'),
          h('ul', {}, failures.map((text) => h('li', {}, text))));
        return;
      }
      if (nextRows.length > 5000) throw new Error(`El lote tiene ${nextRows.length} filas. Seleccione menos archivos: el máximo por carga es 5,000.`);
      rows = nextRows; sources = nextSources; fname = files.map((f) => f.name).join(' · ');
      await validate();
    } catch (e) { out.replaceChildren(note(e.message, 'error')); }
    finally { setBusy(false); if (saveButton) saveButton.disabled = saveButton.dataset.ready !== 'true'; }
  });

  function preview(rep) {
    const ok = !rep.errors.length;
    const approvals = sources.filter((source) => source.authorization);
    const ready = ok && ((rep.new + rep.changed) > 0 || approvals.length > 0);
    const save = h('button', { class: 'i18-btn ti-save-primary', type: 'button', disabled: !ready, 'data-ready': String(ready), 'aria-describedby': 'ti-save-help' }, `Guardar tarifario: ${rep.new + rep.changed} tarifa(s)${approvals.length ? ` y ${approvals.length} excepción(es)` : ''}`);
    saveButton = save;
    const help = h('p', { id: 'ti-save-help', class: 'ti-save-help' }, !ok
      ? `Guardado bloqueado: hay ${rep.errors.length} fila(s) con error. Corrija o excluya esas filas y pulse «Validar para guardar».`
      : ready ? 'Lote validado. Pulse «Guardar tarifario» para confirmar los cambios.' : 'Todas las tarifas son iguales a las existentes y no hay excepciones nuevas. No hay cambios para guardar.');
    saveFeedback = help;
    const validateToSave = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Validar para guardar');
    validateToSave.addEventListener('click', () => { if (!busy) validate(); });
    const status = h('p', { role: 'status' }, ok ? 'Revisión completa. Compruebe las tarifas antes de confirmar.' : '1. Revise los valores señalados. 2. Corrija aquí o excluya la fila. 3. Vuelva a validar.');
    const recheck = h('button', { class: 'i18-btn', type: 'button' }, 'Volver a validar correcciones');
    recheck.addEventListener('click', () => { if (!busy) validate(); });
    const copy = h('button', { class: 'i18-link', type: 'button' }, 'Descargar copia corregida (CSV)');
    copy.addEventListener('click', () => downloadCsv('tarifario_corregido.csv', [
      ['Servicio', 'Descripción', 'SIMON', 'CUPS', 'Tarifa', 'Desde', 'Hasta'],
      ...rows.map((r) => [r.servicio, r.descripcion, r.simon, r.cups, r.tarifa, r.desde, r.hasta])
    ]));
    const dirty = () => {
      save.disabled = true; save.dataset.ready = 'false';
      help.textContent = 'Guardado pendiente: hay cambios sin validar. Pulse «Validar para guardar»; después se habilitará «Guardar tarifario» si no quedan errores.';
      status.textContent = 'Hay cambios pendientes de validar. Pulse «Volver a validar correcciones» antes de confirmar.';
    };
    save.addEventListener('click', async () => {
      if (busy || save.disabled || save.dataset.ready !== 'true') return;
      setBusy(true);
      try {
        const r = await rpc('import_contract_tariffs_v2', { p_rows: rows, p_commit: true, p_file: fname });
        out.replaceChildren(note(`Listo: ${r.imported} tarifa(s) guardadas. ${r.same} igual(es) se omitieron.${approvals.length ? ` ${approvals.length} excepción(es) de ARS guardada(s).` : ''}`, 'ok'));
        rows = null; sources = []; saveButton = null; saveFeedback = null; file.value = '';
        selected.replaceChildren('Carga completada. Puede seleccionar nuevos archivos.');
        drawHistory(); drawExpiring();
      } catch (e) { out.append(note(e.message, 'error')); }
      finally { setBusy(false); }
    });
    const fields = [['servicio', 'Servicio / Código'], ['descripcion', 'Descripción (informativa)'], ['simon', 'SIMON'], ['cups', 'CUPS'], ['tarifa', 'Tarifa'], ['desde', 'Desde (DD/MM/AAAA)'], ['hasta', 'Hasta (DD/MM/AAAA, opcional)']];
    function errorCard(error) {
      const index = Number(error.row) - 1; const row = rows[index]; const source = sources[index];
      if (!row || !source) return note(`No se pudo localizar ${location(error.row)}. Revise los archivos de nuevo.`, 'error');
      const messages = error.errors.map(explain);
      const problemId = `ti-error-${index}`;
      let exceptionEditor = null;
      const inputs = fields.map(([key, label]) => {
        const invalid = key === 'descripcion' ? false : error.errors.some((m) => {
          const text = m.toLowerCase();
          if (key === 'simon' || key === 'cups') return text.includes(key);
          if (key === 'servicio') return text.includes('servicio') && !text.includes('vigencia');
          if (key === 'tarifa') return text.includes('tarifa inválida');
          return key === 'desde' ? /inicio|inicia|vigencia|duplicado/.test(text) : /fin|vigencia|duplicado/.test(text);
        });
        const input = h(key === 'descripcion' ? 'textarea' : 'input', { rows: key === 'descripcion' ? '2' : null, value: row[key], 'aria-label': `${label} · ${location(error.row)}`, 'aria-invalid': String(invalid), 'aria-describedby': problemId });
        input.addEventListener('input', () => {
          row[key] = input.value; delete row.code_authorization; delete source.authorization;
          exceptionEditor?.invalidate(); dirty();
        });
        const original = h('span', { class: 'i18-sub', style: 'overflow-wrap:anywhere' }, `Original: ${source.original[key] || '(vacío)'}`);
        return h('label', {}, label, input, original);
      });
      const tips = [];
      if (error.errors.some((m) => /SIMON|CUPS/.test(m))) tips.push('Compruebe que Servicio, SIMON y CUPS identifiquen el mismo procedimiento. Corrija el código o proponga una excepción si el contrato de esta ARS usa una asociación exclusiva. Si no dispone del código adicional, puede dejarlo vacío conservando al menos un identificador válido.');
      if (error.errors.some((m) => /Tarifa inválida/.test(m))) tips.push('Indique un monto mayor que cero y hasta 10,000,000; por ejemplo 1500.00.');
      if (error.errors.some((m) => /fecha|vigencia|inicio|fin/i.test(m))) tips.push('Use DD/MM/AAAA. Revise las vigencias existentes; Hasta puede quedar vacío si el contrato no vence.');
      if (error.errors.some((m) => /Duplicado/.test(m))) tips.push('Compare con la fila indicada. Si es la misma tarifa, excluya una de las dos para evitar duplicarla.');
      const exclude = h('button', { class: 'i18-link', type: 'button' }, 'Excluir esta fila del lote');
      exclude.addEventListener('click', async () => {
        if (busy) return;
        rows.splice(index, 1); sources.splice(index, 1); dirty();
        if (!rows.length) { rows = null; sources = []; saveButton = null; out.replaceChildren(note('Se excluyeron todas las filas. Seleccione los archivos y revíselos de nuevo.')); return; }
        // Retirar inmediatamente los editores antiguos evita que sus índices apunten a otra fila.
        saveButton = null; out.replaceChildren(note('Revisando el lote sin la fila excluida…'));
        await validate();
      });
      if (error.errors.some((m) => /SIMON|CUPS/.test(m))) {
        exceptionEditor = codeExceptionEditor({ orgId, row, source, errors: error.errors, setBusy, isBusy: () => busy,
          onInvalidate: () => { delete row.code_authorization; delete source.authorization; dirty(); },
          onAuthorized: (approval) => { row.code_authorization = approval.id; source.authorization = approval; dirty(); } });
      }
      return h('section', { class: 'i18-card ti-error-card' }, h('h4', {}, location(error.row)),
        h('ul', { id: problemId, class: 'ti-problems' }, messages.map((m) => h('li', {}, m))),
        tips.map((tip) => h('p', {}, tip)), h('div', { class: 'hc-grid i18-form', style: 'max-width:none' }, inputs), exceptionEditor?.element || '', exclude);
    }
    out.replaceChildren(
      h('div', { class: 'ac-sum', style: 'margin:10px 0' },
        h('span', { class: 'ac-pill st-prep' }, `${rep.new} nuevas`), h('span', { class: 'ac-pill st-req' }, `${rep.changed} cambian`),
        h('span', { class: 'ac-pill st-none' }, `${rep.same} iguales`), h('span', { class: `ac-pill ${ok ? 'st-ok' : 'st-bad'}` }, `${rep.errors.length} con error`)),
      status,
      approvals.length ? h('section', {}, h('h4', {}, 'Excepciones autorizadas pendientes de guardar'),
        h('ul', {}, approvals.map((source) => h('li', {}, `${source.file} · fila ${source.line}: ${source.authorization.proposal.ars_name} · ${source.authorization.proposal.codes.map((code) => `${code.system} ${code.code}`).join(', ')} → ${source.authorization.proposal.service_code} · ${source.authorization.proposal.service_description}`)))) : '',
      rep.errors.length ? h('section', {}, note('Puede corregir los valores aquí sin editar el Excel. Se conserva el texto original para comparar. Los cambios no modifican el archivo de su equipo ni el catálogo de servicios.', 'error'), rep.errors.map(errorCard)) : '',
      h('div', { class: 'i18-actions' }, recheck, copy),
      rep.rows.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Archivo / Fila', 'Servicio', 'Descripción del archivo', 'Plan', 'Actual', 'Nueva', 'Cambio', 'Desde', 'Hasta'].map((x) => h('th', {}, x)))),
        h('tbody', {}, rep.rows.map((r) => h('tr', {}, h('td', {}, location(r.row)), h('td', {}, r.service || '—'), h('td', {}, rows[Number(r.row) - 1]?.descripcion || '—'), h('td', {}, r.plan || 'General'), h('td', { class: 'i18-r' }, r.current != null ? money(r.current) : '—'),
          h('td', { class: 'i18-r' }, money(r.amount)), h('td', {}, h('span', { class: `ac-pill ${CHANGE[r.change][1]}` }, CHANGE[r.change][0]), r.diff_pct != null ? ` ${r.diff_pct > 0 ? '+' : ''}${r.diff_pct} %` : ''),
          h('td', {}, fmtDate(r.valid_from)), h('td', {}, r.valid_to ? fmtDate(r.valid_to) : 'Sin fin')))))) : '',
      h('section', { class: 'ti-save-bar', 'aria-label': 'Validación y guardado del tarifario' },
        h('strong', {}, 'Guardar cambios del tarifario'), help, h('div', { class: 'i18-actions' }, validateToSave, save)));
    out.querySelectorAll('.i18-table').forEach((table) => {
      const labels = [...table.querySelectorAll('thead th')].map((th) => th.textContent);
      table.querySelectorAll('tbody tr').forEach((tr) => [...tr.children].forEach((td, i) => { td.dataset.l = labels[i] || ''; }));
    });
  }

  async function drawHistory() {
    const l = await guarded(hist, () => rpc('tariff_import_history', { p_org: orgId }));
    if (!l) return;
    hist.replaceChildren(l.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Fecha', 'ARS', 'Plan', 'Médico', 'Archivo', 'Nuevas', 'Cambian', 'Iguales', 'Por'].map((x) => h('th', {}, x)))),
      h('tbody', {}, l.map((x) => h('tr', {}, h('td', {}, fmtDate(x.at)), h('td', {}, x.ars || '—'), h('td', {}, x.plan || 'General'), h('td', {}, x.provider || '—'), h('td', {}, x.file || '—'),
        h('td', { class: 'i18-r' }, x.new), h('td', { class: 'i18-r' }, x.changed), h('td', { class: 'i18-r' }, x.same), h('td', {}, x.by || '—')))))) : note('Todavía no hay cargas desde Excel para este cliente.'));
  }
  async function drawExpiring() { if (isStaff) await mountExpiring(exp, { orgId, days: 120 }); }
}

/** 2.6.1 · Renegociación de tarifarios (solo SOFA): cada grupo de tarifas se revisa a los 2 años de su última vigencia
 *  o cuando vence el contrato, lo que llegue primero. Lo usa la ficha del cliente y la pantalla «Renegociación de tarifarios». */
/** 3.0 · Iteración 40: la renegociación es un servicio con caso propio. Un clic abre el caso (o lleva al que ya existe). */
function caseCell(t) {
  if (t.case) return h('a', { href: `#/casos-servicio/${t.case.id}` }, `${t.case.folio} · ver caso`);
  if (!t.provider_id) return '';   // base anterior a la 138
  const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Abrir caso de renegociación');
  b.addEventListener('click', async () => {
    b.disabled = true;
    try {
      const r = await rpc('tariff_renewal_open_case', { p_org: t.organization_id, p_provider: t.provider_id, p_ars: t.ars_id, p_plan: t.plan_id || null });
      b.replaceWith(h('a', { href: `#/casos-servicio/${r.id}` }, `${r.folio} · ver caso`));
    } catch (e) { b.disabled = false; b.after(note(e.message, 'error')); }
  });
  return b;
}

export async function mountExpiring(box, { orgId = null, days = 120 } = {}) {
  const d = await guarded(box, () => rpc('tariffs_expiring', { p_days: days, p_org: orgId }));
  if (!d) return;
  const cls = (n) => (n <= 0 ? 'st-bad' : n <= 30 ? 'st-req' : 'st-prep');
  const KIND = { renegociar: 'Renegociar', vence: 'Vence el contrato' };
  const left = (n) => (n < 0 ? `atrasado ${-n} días` : n === 0 ? 'hoy' : `${n} días`);
  box.replaceChildren(
    d.tariffs.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, [orgId ? null : 'Cliente', 'Médico', 'ARS', 'Plan', 'Contrato', 'Tarifas', 'Vigente desde', 'Motivo', 'Fecha', '', 'Servicio SOFA'].filter(Boolean).map((x) => h('th', {}, x)))),
      h('tbody', {}, d.tariffs.map((t) => h('tr', {}, orgId ? '' : h('td', {}, h('a', { href: `#/clientes/${t.organization_id}` }, t.client)), h('td', {}, t.provider), h('td', {}, t.ars),
        h('td', {}, t.plan || 'General'), h('td', {}, t.contract || '—'), h('td', { class: 'i18-r' }, t.count), h('td', {}, fmtDate(t.since)), h('td', {}, KIND[t.kind] || t.kind),
        h('td', {}, fmtDate(t.valid_to)), h('td', {}, h('span', { class: `ac-pill ${cls(t.days_left)}` }, left(t.days_left))), h('td', {}, caseCell(t))))))) : note(`Ningún tarifario llega a su revisión en los próximos ${days} días.`),
    h('p', { class: 'i18-sub' }, `Las ARS contratan por tiempo indefinido: SOFA propone renegociar cada ${d.years || 2} años. Cada mañana se crea una tarea «Renegociar tarifario» 90 días antes.`),
    d.contracts.length ? h('p', { class: 'i18-sub' }, 'Contratos con SOFA por revisar: ' + d.contracts.map((c) => `${orgId ? '' : c.client + ' · '}${c.folio || c.service} (${fmtDate(c.end_date)})`).join(' · ')) : '');
}
