/** SOFA · 2.2 · Iteración 32 · Carga del tarifario de una ARS desde Excel (o CSV) para un médico del cliente.
 *  2.6.1: plan opcional (la tarifa del plan manda sobre la general) y renegociación cada 2 años, visible solo para SOFA.
 *  Pasos: elegir ARS, médico y vigencia → subir el archivo → revisar la vista previa (nueva, cambia, igual, con error) → confirmar.
 *  Usa public.import_contract_tariffs_v2 (116), que valida igual que el Tarifario contractual y omite las tarifas iguales. */
import { rpc, h, money, fmtDate, note, guarded } from '../services/iter18.js';
import { readTable, excelDate, detectColumns } from '../utils/xlsx-lite.js';

const ALIASES = {
  servicio: ['servicio', 'codigo interno', 'codigo', 'cod', 'procedimiento', 'descripcion', 'concepto', 'prestacion'],
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
  const file = h('input', { id: 'ti-file', type: 'file', accept: '.xlsx,.csv,.txt' });
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Revisar el archivo');
  const tpl = h('button', { class: 'i18-link', type: 'button' }, 'Descargar plantilla');
  const out = h('div', { 'aria-live': 'polite' });
  top.replaceChildren(h('section', { class: 'i18-card' }, h('h3', { style: 'margin-top:0' }, 'Cargar tarifario desde Excel'),
    h('p', { class: 'i18-sub' }, 'Suba el Excel que manda la ARS. Columnas que se reconocen: Servicio o Código, SIMON, CUPS, Tarifa, Desde y Hasta (las dos últimas son opcionales: si faltan se usa la vigencia de abajo). Las ARS contratan por tiempo indefinido: deje «Hasta» vacío salvo que el contrato diga una fecha. Si el tarifario es de un plan (por ejemplo «Royal»), elíjalo: esa tarifa manda para los pacientes de ese plan. Nada se guarda hasta que usted confirme.'),
    h('div', { class: 'hc-grid i18-form', style: 'max-width:none' },
      h('label', { for: 'ti-ars' }, 'ARS', ars), h('label', { for: 'ti-plan' }, 'Plan', plan), h('label', { for: 'ti-prov' }, 'Médico', prov),
      h('label', { for: 'ti-from' }, 'Vigencia desde', from), h('label', { for: 'ti-to' }, 'Hasta (opcional)', to),
      h('label', { for: 'ti-ct' }, 'Contrato', contract), h('label', { for: 'ti-file' }, 'Archivo (.xlsx o .csv)', file)),
    h('div', { class: 'i18-actions' }, go, tpl), out));
  tpl.addEventListener('click', () => {
    const csv = '﻿Servicio;SIMON;CUPS;Tarifa;Desde;Hasta\r\nSOFA-P07;;;1500.00;01/01/2026;\r\n';
    const a = h('a', { href: URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })), download: 'plantilla_tarifario_ars.csv' });
    document.body.append(a); a.click(); a.remove();
  });

  let rows = null; let fname = '';
  go.addEventListener('click', async () => {
    out.replaceChildren();
    if (!ars.value) return out.replaceChildren(note('Elija la ARS.', 'error'));
    if (!file.files[0]) return out.replaceChildren(note('Elija el archivo del tarifario.', 'error'));
    go.disabled = true;
    try {
      const t = await readTable(file.files[0]); fname = file.files[0].name;
      if (t.length < 2) throw new Error('El archivo no tiene filas debajo de los encabezados.');
      const map = detectColumns(t[0], ALIASES);
      if (map.tarifa == null || (map.servicio == null && map.simon == null && map.cups == null)) {
        throw new Error('No se reconocieron las columnas. La primera fila debe tener encabezados como «Servicio» (o «Código», «SIMON», «CUPS») y «Tarifa».');
      }
      const df = from.value ? from.value.split('-').reverse().join('/') : '';
      const dt = to.value ? to.value.split('-').reverse().join('/') : '';
      rows = t.slice(1).map((r) => ({
        medico: prov.value, ars: ars.value, plan: plan.value, contrato: contract.value.trim(),
        servicio: map.servicio != null ? r[map.servicio] || '' : '', simon: map.simon != null ? r[map.simon] || '' : '', cups: map.cups != null ? r[map.cups] || '' : '',
        tarifa: r[map.tarifa] || '', desde: map.desde != null && r[map.desde] ? excelDate(r[map.desde]) : df, hasta: map.hasta != null && r[map.hasta] ? excelDate(r[map.hasta]) : dt
      })).filter((x) => x.servicio || x.simon || x.cups || x.tarifa);
      const rep = await rpc('import_contract_tariffs_v2', { p_rows: rows, p_commit: false, p_file: fname });
      preview(rep);
    } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { go.disabled = false; }
  });

  function preview(rep) {
    const ok = !rep.errors.length;
    const save = h('button', { class: 'i18-btn', type: 'button', disabled: !ok || !(rep.new + rep.changed) }, `Confirmar: guardar ${rep.new + rep.changed} tarifa(s)`);
    save.addEventListener('click', async () => {
      save.disabled = true;
      try {
        const r = await rpc('import_contract_tariffs_v2', { p_rows: rows, p_commit: true, p_file: fname });
        out.replaceChildren(note(`Listo: ${r.imported} tarifa(s) guardadas. ${r.same} igual(es) se omitieron.`, 'ok')); drawHistory(); drawExpiring();
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
    });
    out.replaceChildren(
      h('div', { class: 'ac-sum', style: 'margin:10px 0' },
        h('span', { class: 'ac-pill st-prep' }, `${rep.new} nuevas`), h('span', { class: 'ac-pill st-req' }, `${rep.changed} cambian`),
        h('span', { class: 'ac-pill st-none' }, `${rep.same} iguales`), h('span', { class: `ac-pill ${rep.errors.length ? 'st-bad' : 'st-ok'}` }, `${rep.errors.length} con error`)),
      rep.errors.length ? h('section', {}, note('Corrija estas filas en el archivo y vuelva a revisarlo. No se guarda nada mientras haya errores.', 'error'),
        h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, h('th', {}, 'Fila'), h('th', {}, 'Problema'))),
          h('tbody', {}, rep.errors.map((e) => h('tr', {}, h('td', {}, String(e.row + 1)), h('td', {}, e.errors.join(' · ')))))))) : '',
      rep.rows.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Servicio', 'Plan', 'Actual', 'Nueva', 'Cambio', 'Desde', 'Hasta'].map((x) => h('th', {}, x)))),
        h('tbody', {}, rep.rows.map((r) => h('tr', {}, h('td', {}, r.service || '—'), h('td', {}, r.plan || 'General'), h('td', { class: 'i18-r' }, r.current != null ? money(r.current) : '—'),
          h('td', { class: 'i18-r' }, money(r.amount)), h('td', {}, h('span', { class: `ac-pill ${CHANGE[r.change][1]}` }, CHANGE[r.change][0]), r.diff_pct != null ? ` ${r.diff_pct > 0 ? '+' : ''}${r.diff_pct} %` : ''),
          h('td', {}, fmtDate(r.valid_from)), h('td', {}, r.valid_to ? fmtDate(r.valid_to) : 'Sin fin')))))) : '',
      h('div', { class: 'i18-actions' }, save));
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
export async function mountExpiring(box, { orgId = null, days = 120 } = {}) {
  const d = await guarded(box, () => rpc('tariffs_expiring', { p_days: days, p_org: orgId }));
  if (!d) return;
  const cls = (n) => (n <= 0 ? 'st-bad' : n <= 30 ? 'st-req' : 'st-prep');
  const KIND = { renegociar: 'Renegociar', vence: 'Vence el contrato' };
  const left = (n) => (n < 0 ? `atrasado ${-n} días` : n === 0 ? 'hoy' : `${n} días`);
  box.replaceChildren(
    d.tariffs.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, [orgId ? null : 'Cliente', 'Médico', 'ARS', 'Plan', 'Contrato', 'Tarifas', 'Vigente desde', 'Motivo', 'Fecha', ''].filter(Boolean).map((x) => h('th', {}, x)))),
      h('tbody', {}, d.tariffs.map((t) => h('tr', {}, orgId ? '' : h('td', {}, h('a', { href: `#/clientes/${t.organization_id}` }, t.client)), h('td', {}, t.provider), h('td', {}, t.ars),
        h('td', {}, t.plan || 'General'), h('td', {}, t.contract || '—'), h('td', { class: 'i18-r' }, t.count), h('td', {}, fmtDate(t.since)), h('td', {}, KIND[t.kind] || t.kind),
        h('td', {}, fmtDate(t.valid_to)), h('td', {}, h('span', { class: `ac-pill ${cls(t.days_left)}` }, left(t.days_left)))))))) : note(`Ningún tarifario llega a su revisión en los próximos ${days} días.`),
    h('p', { class: 'i18-sub' }, `Las ARS contratan por tiempo indefinido: SOFA propone renegociar cada ${d.years || 2} años. Cada mañana se crea una tarea «Renegociar tarifario» 90 días antes.`),
    d.contracts.length ? h('p', { class: 'i18-sub' }, 'Contratos con SOFA por revisar: ' + d.contracts.map((c) => `${orgId ? '' : c.client + ' · '}${c.folio || c.service} (${fmtDate(c.end_date)})`).join(' · ')) : '');
}
