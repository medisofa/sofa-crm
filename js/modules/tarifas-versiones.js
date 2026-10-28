/** SOFA · 4.7 · I57 · Versiones de tarifario por ARS y plan: lista con vigencias, comparador («qué subió y qué bajó»), alerta de reclamaciones con precio vencido,
 *  indicador «% de líneas con el precio del tarifario vigente» (meta 100 %) y carga de una versión desde Excel.
 *  La carga reutiliza el lector de Excel y las columnas de tarifario-import.js (Servicio o Código, SIMON, CUPS, Tarifa). Cada función del servidor vuelve a verificar
 *  el rol: ocultar un botón no es un control. Publicar versiones: Super Admin y Administrador. Consultar: Operaciones, Comercial, Auditor y Cobros/glosas (Facturación no entra: su alcance es de 5 módulos). */
import { rpc, h, money, fmtDate, note, kpi, guarded, pct, num, todayIso, downloadCsv } from '../services/iter18.js';
import { readTable, detectColumns } from '../utils/xlsx-lite.js';
import { mountExpiring } from './tarifario-import.js';

const ALIASES = {   // mismas columnas que tarifario-import.js
  servicio: ['servicio', 'codigo interno', 'codigo', 'cod', 'procedimiento', 'descripcion', 'concepto', 'prestacion'],
  simon: ['simon', 'codigo simon'], cups: ['cups', 'codigo cups'],
  tarifa: ['tarifa', 'monto', 'precio', 'valor', 'tarifa rd', 'importe']
};
const CHANGE = { nueva: ['Nueva', 'st-prep'], cambia: ['Cambia', 'st-req'], igual: ['Igual', 'st-none'], conservada: ['Se conserva', 'st-none'],
  subio: ['Subió', 'st-bad'], bajo: ['Bajó', 'st-ok'], nuevo: ['Nuevo', 'st-prep'], retirado: ['Retirado', 'st-req'] };
const STATE = { vigente: ['Vigente', 'st-ok'], futura: ['Futura', 'st-prep'], cerrada: ['Cerrada', 'st-none'] };
const pill = (map, k) => h('span', { class: `ac-pill ${(map[k] || ['', 'st-none'])[1]}` }, (map[k] || [k])[0]);
const scopeLabel = (v) => `${v.ars}${v.plan ? ' · ' + v.plan : ' · todos los planes'}${v.provider ? ' · ' + v.provider : ' · tarifa general'}`;
const keyOf = (v) => `${v.ars_id}|${v.plan_id || ''}|${v.provider_id || ''}`;
const dmy = (iso) => (iso ? iso.split('-').reverse().join('/') : '');
const monthStart = (back = 0) => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - back); return d.toISOString().slice(0, 10); };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const canPublish = ['super_admin', 'admin'].includes(ctx.role);
  const kpis = h('div', { 'aria-live': 'polite' });
  const body = h('div', { 'aria-live': 'polite' });
  const tabs = [['versiones', 'Versiones'], ['comparar', 'Comparar versiones'], ['vencidos', 'Precios vencidos'], ...(canPublish ? [['cargar', 'Cargar versión']] : [])];
  const bar = h('div', { class: 'i18-tabs', role: 'tablist' });
  root.append(h('div', { class: 'i18-wrap tv-wrap' }, h('h2', {}, 'Versiones de tarifario'),
    h('p', { class: 'i18-sub' }, 'Cada ARS (y plan, y médico si tiene contrato propio) tiene sus versiones con fecha de inicio y de fin. El precio de cada reclamación sale de la versión vigente en la FECHA DEL SERVICIO, no de la fecha de captura. Una versión nueva se carga desde el Excel de la ARS.'),
    kpis, bar, body));

  let ars = []; let versions = []; let cat = []; let tab = 'versiones'; let range = { from: monthStart(2), to: todayIso() };   // últimos 3 meses: lo vencido de meses anteriores también cuenta
  const optsArs = (sel, all = true) => [all ? h('option', { value: '' }, 'Todas las ARS') : h('option', { value: '' }, 'Elija la ARS'), ...cat.map((a) => h('option', { value: a.id, selected: sel === a.id }, a.name))];

  async function loadBase() {
    cat = await rpc('ars_catalog', { p_include_inactive: false }).catch(() => []);
    versions = (await rpc('tariff_versions_list', {})) || [];
  }

  async function drawKpis() {
    try {
      const d = await rpc('tariff_price_indicator', { p_org: null, p_ars: null, p_from: range.from, p_to: range.to });
      const ok = d.pct == null || Number(d.pct) >= d.goal_pct;
      kpis.replaceChildren(h('div', { class: 'i18-kpis' },
        kpi('Líneas con el precio vigente', d.pct == null ? '—' : pct(d.pct), `Meta ${d.goal_pct} % · ${num(d.current)} de ${num(d.known)} con tarifa conocida`),
        kpi('Con precio vencido', num(d.stale), d.stale ? 'Revise la pestaña «Precios vencidos»' : 'Ninguna'),
        kpi('Sin tarifa para su fecha', num(d.no_tariff), 'Servicio retirado o sin contrato'),
        kpi('Líneas del período', num(d.lines), `${fmtDate(d.from)} a ${fmtDate(d.to)}`)),
        !ok ? note(`El indicador está por debajo de la meta: ${num(d.stale)} reclamación(es) se capturaron con un precio que ya no es el vigente para su fecha de servicio. Revíselas en «Precios vencidos».`, 'warn') : null,
        d.by_ars && d.by_ars.length > 1 ? h('details', { class: 'i18-card' }, h('summary', {}, 'Por ARS'), h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
          h('thead', {}, h('tr', {}, ['ARS', 'Con tarifa', 'Vigentes', 'Vencidas', '%'].map((x) => h('th', {}, x)))),
          h('tbody', {}, d.by_ars.map((r) => h('tr', {}, h('td', {}, r.ars), h('td', { class: 'i18-r' }, num(r.known)), h('td', { class: 'i18-r' }, num(r.current)), h('td', { class: 'i18-r' }, num(r.stale)), h('td', { class: 'i18-r' }, r.pct == null ? '—' : pct(r.pct)))))))) : null);
    } catch (e) { kpis.replaceChildren(note(e.message, 'error')); }
  }

  function setTab(t) {
    tab = t;
    bar.replaceChildren(...tabs.map(([k, l]) => { const b = h('button', { class: 'i18-tab', type: 'button', role: 'tab', 'aria-selected': k === t ? 'true' : 'false', 'data-tab': k }, l); b.addEventListener('click', () => setTab(k)); return b; }));
    ({ versiones: drawVersions, comparar: drawCompare, vencidos: drawStale, cargar: drawUpload })[t]();
  }

  // ── Versiones ──────────────────────────────────────────────────────────────────────────────
  function drawVersions() {
    const sel = h('select', { id: 'tv-f-ars' }, optsArs(''));
    const list = h('div', { 'aria-live': 'polite' }); const det = h('div', { 'aria-live': 'polite' }); const exp = h('div', { 'aria-live': 'polite' });
    const draw = () => {
      const rows = versions.filter((v) => !sel.value || v.ars_id === sel.value);
      list.replaceChildren(rows.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['ARS · plan · médico', 'Versión', 'Desde', 'Hasta', 'Estado', 'Códigos', 'Origen', ''].map((x) => h('th', {}, x)))),
        h('tbody', {}, rows.map((v) => {
          const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Ver contenido');
          b.addEventListener('click', async () => {
            const r = await guarded(det, () => rpc('tariff_version_items', { p_version: v.id }));
            if (!r) return;
            const csv = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descargar CSV');
            csv.addEventListener('click', () => downloadCsv(`version_${v.id.slice(0, 8)}.csv`, [['Código', 'Servicio', 'Tarifa'], ...r.items.map((i) => [i.code, i.service, i.amount])]));
            det.replaceChildren(h('h3', {}, `${v.name} · ${fmtDate(r.version.valid_from)}${r.version.valid_to ? ' a ' + fmtDate(r.version.valid_to) : ' en adelante'}`),
              h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['Código', 'Servicio', 'Tarifa'].map((x) => h('th', {}, x)))),
                h('tbody', {}, r.items.map((i) => h('tr', {}, h('td', {}, i.code), h('td', {}, i.service), h('td', { class: 'i18-r' }, money(i.amount))))))), h('div', { class: 'i18-actions' }, csv));
          });
          return h('tr', {}, h('td', {}, scopeLabel(v)), h('td', {}, v.name), h('td', {}, fmtDate(v.valid_from)), h('td', {}, v.valid_to ? fmtDate(v.valid_to) : 'Sin fin'),
            h('td', {}, pill(STATE, v.state)), h('td', { class: 'i18-r' }, String(v.items)), h('td', {}, v.file || v.source || '—'), h('td', {}, b));
        })))) : note('Todavía no hay versiones para ese filtro. Cargue la primera desde «Cargar versión».'));
    };
    sel.addEventListener('change', draw);
    body.replaceChildren(h('div', { class: 'i18-form tv-filter' }, h('label', { for: 'tv-f-ars' }, 'ARS', sel)), list, det,
      h('h3', {}, 'Renegociación (próximos 120 días)'), exp);
    draw();
    mountExpiring(exp, { orgId: null, days: 120 }).catch((e) => exp.replaceChildren(note(e.message, 'error')));
  }

  // ── Comparador ─────────────────────────────────────────────────────────────────────────────
  function drawCompare() {
    const keys = [...new Map(versions.map((v) => [keyOf(v), v])).values()];
    const k = h('select', { id: 'tv-c-key' }, h('option', { value: '' }, 'Elija ARS, plan y médico'), keys.map((v) => h('option', { value: keyOf(v) }, scopeLabel(v))));
    const a = h('select', { id: 'tv-c-a' }); const b = h('select', { id: 'tv-c-b' });
    const out = h('div', { 'aria-live': 'polite' });
    const fill = () => {
      const vs = versions.filter((v) => keyOf(v) === k.value);
      const opts = (sel) => [h('option', { value: '' }, 'Elija una versión'), ...vs.map((v) => h('option', { value: v.id, selected: v.id === sel }, `${v.name} · desde ${fmtDate(v.valid_from)}`))];
      a.replaceChildren(...opts(vs[1] && vs[1].id)); b.replaceChildren(...opts(vs[0] && vs[0].id));
      out.replaceChildren(vs.length < 2 && k.value ? note('Esa ARS solo tiene una versión: no hay con qué comparar todavía.') : '');
    };
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Comparar');
    k.addEventListener('change', fill);
    go.addEventListener('click', async () => {
      if (!a.value || !b.value) return out.replaceChildren(note('Elija las dos versiones que quiere comparar.', 'error'));
      go.disabled = true;
      try {
        const r = await rpc('tariff_version_compare', { p_a: a.value, p_b: b.value }); const s = r.summary;
        const csv = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descargar CSV');
        csv.addEventListener('click', () => downloadCsv('comparacion_versiones.csv', [['Código', 'Servicio', r.a.name, r.b.name, 'Cambio', '% cambio'], ...r.rows.map((x) => [x.code, x.service, x.amount_a, x.amount_b, (CHANGE[x.change] || [x.change])[0], x.diff_pct ?? ''])]));
        out.replaceChildren(
          h('div', { class: 'ac-sum tv-sum' }, ...['subio', 'bajo', 'nuevo', 'retirado', 'igual'].map((c) => h('span', { class: `ac-pill ${CHANGE[c][1]}` }, `${s[c]} ${CHANGE[c][0].toLowerCase()}`)),
            s.avg_pct != null ? h('span', { class: 'i18-sub' }, `Cambio promedio de lo que se movió: ${s.avg_pct > 0 ? '+' : ''}${s.avg_pct} %`) : null),
          h('p', { class: 'i18-sub' }, `De «${r.a.name}» (desde ${fmtDate(r.a.valid_from)}) a «${r.b.name}» (desde ${fmtDate(r.b.valid_from)}).`),
          h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['Código', 'Servicio', r.a.name, r.b.name, 'Cambio'].map((x) => h('th', {}, x)))),
            h('tbody', {}, r.rows.map((x) => h('tr', {}, h('td', {}, x.code), h('td', {}, x.service), h('td', { class: 'i18-r' }, x.amount_a == null ? '—' : money(x.amount_a)), h('td', { class: 'i18-r' }, x.amount_b == null ? '—' : money(x.amount_b)),
              h('td', {}, pill(CHANGE, x.change), x.diff_pct != null ? ` ${x.diff_pct > 0 ? '+' : ''}${x.diff_pct} %` : '')))))), h('div', { class: 'i18-actions' }, csv));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { go.disabled = false; }
    });
    body.replaceChildren(h('div', { class: 'i18-form' }, h('label', { for: 'tv-c-key' }, 'ARS, plan y médico', k), h('label', { for: 'tv-c-a' }, 'Versión de partida', a), h('label', { for: 'tv-c-b' }, 'Versión a comparar', b), h('div', {}, go)), out);
  }

  // ── Precios vencidos ───────────────────────────────────────────────────────────────────────
  function drawStale() {
    const sc = h('select', { id: 'tv-s-sc' }, h('option', { value: 'abiertas' }, 'Aún corregibles (sin radicar)'), h('option', { value: 'todas' }, 'Todas, incluidas las radicadas'));
    const sa = h('select', { id: 'tv-s-ars' }, optsArs(''));
    const out = h('div', { 'aria-live': 'polite' });
    async function load() {
      const r = await guarded(out, () => rpc('tariff_stale_claims', { p_org: null, p_ars: sa.value || null, p_from: monthStart(3), p_to: null, p_scope: sc.value, p_limit: 500 }));
      if (!r) return;
      const csv = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descargar CSV');
      csv.addEventListener('click', () => downloadCsv('precios_vencidos.csv', [['Folio', 'Cliente', 'ARS', 'Fecha del servicio', 'Servicio', 'Estado', 'Precio capturado', 'Precio vigente', 'Diferencia'], ...r.rows.map((x) => [x.folio, x.client, x.ars, x.service_date, x.service, x.status, x.frozen_amount, x.current_amount, x.diff])]));
      out.replaceChildren(r.total ? h('section', {}, note(`${num(r.total)} reclamación(es) con un precio que ya no es el vigente para su fecha de servicio${r.truncated ? ` (se muestran las ${r.shown} más recientes)` : ''}. Corríjalas con el flujo de diferencias de tarifa antes de radicar.`, 'warn'),
        h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['Folio', 'Cliente', 'ARS', 'Fecha', 'Servicio', 'Estado', 'Capturado', 'Vigente', 'Diferencia'].map((x) => h('th', {}, x)))),
          h('tbody', {}, r.rows.map((x) => h('tr', {}, h('td', {}, x.folio), h('td', {}, x.client), h('td', {}, x.ars), h('td', {}, fmtDate(x.service_date)), h('td', {}, x.service),
            h('td', {}, h('span', { class: `ac-pill ${x.closed ? 'st-none' : 'st-req'}` }, x.status.replace(/_/g, ' '))), h('td', { class: 'i18-r' }, money(x.frozen_amount)), h('td', { class: 'i18-r' }, money(x.current_amount)),
            h('td', { class: 'i18-r' }, money(x.diff))))))), h('div', { class: 'i18-actions' }, csv)) : note('No hay reclamaciones con precio vencido en los últimos 3 meses. El indicador está en 100 %.', 'ok'));
    }
    sc.addEventListener('change', load); sa.addEventListener('change', load);
    body.replaceChildren(h('div', { class: 'i18-form tv-filter' }, h('label', { for: 'tv-s-sc' }, 'Alcance', sc), h('label', { for: 'tv-s-ars' }, 'ARS', sa)), out);
    load();
  }

  // ── Cargar versión desde Excel ─────────────────────────────────────────────────────────────
  async function drawUpload() {
    let provs = [];
    try { provs = (await (await import('../services/iter18.js')).providerOptions()) || []; } catch (_) { provs = []; }
    const sArs = h('select', { id: 'tv-u-ars' }, optsArs('', false));
    const sPlan = h('select', { id: 'tv-u-plan' }, h('option', { value: '' }, 'Todos los planes'));
    const sProv = h('select', { id: 'tv-u-prov' }, h('option', { value: '' }, 'Todos: tarifa general de la ARS'), provs.map((p) => h('option', { value: p.id }, p.full_name)));
    const name = h('input', { id: 'tv-u-name', maxlength: '120', placeholder: 'Ej.: Tarifario ARS 2026' });
    const from = h('input', { id: 'tv-u-from', type: 'date', value: todayIso() }); const to = h('input', { id: 'tv-u-to', type: 'date' });
    const contract = h('input', { id: 'tv-u-ct', maxlength: '120', placeholder: 'Opcional: contrato (solo con médico)' });
    const keep = h('input', { id: 'tv-u-keep', type: 'checkbox' });
    const file = h('input', { id: 'tv-u-file', type: 'file', accept: '.xlsx,.csv,.txt' });
    const go = h('button', { class: 'i18-btn', type: 'button', id: 'tv-u-go' }, 'Revisar el archivo'); const tpl = h('button', { class: 'i18-link', type: 'button' }, 'Descargar plantilla');
    const out = h('div', { 'aria-live': 'polite', id: 'tv-u-out' });
    sArs.addEventListener('change', () => { const a = cat.find((x) => x.id === sArs.value); sPlan.replaceChildren(h('option', { value: '' }, 'Todos los planes'), ...((a && a.plans) || []).map((p) => h('option', { value: p.id }, p.name))); });
    tpl.addEventListener('click', () => {
      const csv = '﻿Servicio;SIMON;CUPS;Tarifa\r\nSOFA-P07;;;1500.00\r\n';
      const a = h('a', { href: URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })), download: 'plantilla_version_tarifario.csv' });
      document.body.append(a); a.click(); a.remove();
    });
    body.replaceChildren(h('section', { class: 'i18-card' }, h('h3', { style: 'margin-top:0' }, 'Cargar una versión de tarifario'),
      h('p', { class: 'i18-sub' }, 'Suba el Excel completo que manda la ARS. La versión es una foto del tarifario: lo que estaba vigente y no viene en el archivo se retira en la fecha de inicio, salvo que marque «Conservar». Nada se guarda hasta que confirme. Columnas: Servicio o Código, SIMON, CUPS y Tarifa.'),
      h('div', { class: 'i18-form tv-form' }, h('label', { for: 'tv-u-ars' }, 'ARS', sArs), h('label', { for: 'tv-u-plan' }, 'Plan', sPlan), h('label', { for: 'tv-u-prov' }, 'Médico', sProv),
        h('label', { for: 'tv-u-name' }, 'Nombre de la versión', name), h('label', { for: 'tv-u-from' }, 'Rige desde', from), h('label', { for: 'tv-u-to' }, 'Hasta (opcional)', to),
        h('label', { for: 'tv-u-ct' }, 'Contrato', contract), h('label', { for: 'tv-u-file' }, 'Archivo (.xlsx o .csv)', file),
        h('label', { class: 'i18-chk' }, keep, ' Conservar los códigos que no vienen en el archivo (archivo parcial)')),
      h('div', { class: 'i18-actions' }, go, tpl)), out);

    let rows = null; let fname = '';
    const args = () => ({ p_ars: sArs.value || null, p_plan: sPlan.value || null, p_provider: sProv.value || null, p_desde: from.value || null, p_rows: rows, p_keep: keep.checked });
    go.addEventListener('click', async () => {
      out.replaceChildren();
      if (!sArs.value) return out.replaceChildren(note('Elija la ARS.', 'error'));
      if (!file.files[0]) return out.replaceChildren(note('Elija el archivo del tarifario.', 'error'));
      if (!from.value) return out.replaceChildren(note('Indique desde qué fecha rige la versión.', 'error'));
      go.disabled = true;
      try {
        const t = await readTable(file.files[0]); fname = file.files[0].name;
        if (t.length < 2) throw new Error('El archivo no tiene filas debajo de los encabezados.');
        const map = detectColumns(t[0], ALIASES);
        if (map.tarifa == null || (map.servicio == null && map.simon == null && map.cups == null)) throw new Error('No se reconocieron las columnas. La primera fila debe tener encabezados como «Servicio» (o «Código», «SIMON», «CUPS») y «Tarifa».');
        rows = t.slice(1).map((r) => ({ servicio: map.servicio != null ? r[map.servicio] || '' : '', simon: map.simon != null ? r[map.simon] || '' : '', cups: map.cups != null ? r[map.cups] || '' : '', tarifa: r[map.tarifa] || '' }))
          .filter((x) => x.servicio || x.simon || x.cups || x.tarifa);
        preview(await rpc('tariff_version_preview', args()));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { go.disabled = false; }
    });
    function preview(rep) {
      const ok = !rep.errors.length;
      const save = h('button', { class: 'i18-btn', type: 'button', id: 'tv-u-save', disabled: !ok || !rep.valid }, `Confirmar: publicar la versión (${rep.valid + rep.carried_count} códigos)`);
      save.addEventListener('click', async () => {
        save.disabled = true;
        try {
          const r = await rpc('tariff_version_publish', { ...args(), p_name: name.value, p_hasta: to.value || null, p_source: 'Excel', p_file: fname, p_contract: contract.value.trim() || null });
          await loadBase(); drawKpis();
          out.replaceChildren(note(`Versión publicada: ${r.items} códigos (${r.new} nuevos, ${r.changed} cambian, ${r.same} iguales, ${r.retired} retirados${r.carried ? `, ${r.carried} conservados` : ''}).`
            + (r.stale_claims ? ` Atención: ${r.stale_claims} reclamación(es) ya capturadas tienen otro precio; revíselas en «Precios vencidos».` : ''), r.stale_claims ? 'warn' : 'ok'));
        } catch (e) { out.replaceChildren(note(e.message, 'error')); }
      });
      out.replaceChildren(
        h('div', { class: 'ac-sum tv-sum' }, h('span', { class: 'ac-pill st-prep' }, `${rep.new} nuevas`), h('span', { class: 'ac-pill st-req' }, `${rep.changed} cambian`), h('span', { class: 'ac-pill st-none' }, `${rep.same} iguales`),
          h('span', { class: `ac-pill ${rep.retired_count ? 'st-req' : 'st-none'}` }, `${rep.retired_count} se retiran`), rep.carried_count ? h('span', { class: 'ac-pill st-none' }, `${rep.carried_count} se conservan`) : null,
          h('span', { class: `ac-pill ${rep.errors.length ? 'st-bad' : 'st-ok'}` }, `${rep.errors.length} con error`)),
        ...(rep.warnings || []).map((w) => note(w, 'warn')),
        rep.errors.length ? h('section', {}, note('Corrija estas filas en el archivo y vuelva a revisarlo. No se guarda nada mientras haya errores.', 'error'),
          h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, h('th', {}, 'Fila del archivo'), h('th', {}, 'Problema'))),
            h('tbody', {}, rep.errors.map((e) => h('tr', {}, h('td', {}, String(e.row)), h('td', {}, e.errors.join(' · ')))))))) : '',
        h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['Código', 'Servicio', 'Vigente', 'Nueva', 'Cambio'].map((x) => h('th', {}, x)))),
          h('tbody', {}, [...rep.rows, ...rep.carried].map((r) => h('tr', {}, h('td', {}, r.code), h('td', {}, r.service), h('td', { class: 'i18-r' }, r.current != null ? money(r.current) : '—'), h('td', { class: 'i18-r' }, money(r.amount)),
            h('td', {}, pill(CHANGE, r.change), r.diff_pct != null ? ` ${r.diff_pct > 0 ? '+' : ''}${r.diff_pct} %` : '')))))),
        rep.retired_count ? h('details', { class: 'i18-card' }, h('summary', {}, `Se retiran ${rep.retired_count} códigos que no vienen en el archivo`), h('ul', {}, rep.retired.map((r) => h('li', {}, `${r.code} · ${r.service} (${money(r.current)})`)))) : '',
        h('div', { class: 'i18-actions' }, save));
    }
  }

  try { await loadBase(); } catch (e) { body.replaceChildren(note(e.message, 'error')); return; }
  drawKpis(); setTab('versiones');
}
export default render;
