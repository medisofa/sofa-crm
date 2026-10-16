/** SOFA · 5.2 · I62 · «Expediente digital»: los soportes de cada reclamación (autorización, orden, informe, factura) adjuntos a la reclamación.
 *  Pestañas: Expedientes (semáforo, faltantes, subida con cámara), Indicador (% de expedientes completos al radicar), Espacio (consumo de Storage) y
 *  Configuración (documentos requeridos por ARS, bloqueo opcional de radicar, conservación y límites).
 *  Todo lo que cambia datos pasa por funciones de la base; esta pantalla nunca escribe directo. Quién puede qué lo decide el servidor:
 *  los botones se ocultan solo para que nadie vea lo que no puede hacer. Nada se borra solo: el espacio y la conservación solo se miden y se avisan. */
import { h, note, kpi, guarded, clientOptions, clientName, fmtDate, pct, num } from '../services/iter18.js';
import { openDocument, sizeLabel } from '../services/documents.js';
import { camaraEnVivoDisponible, iniciarCamara, procesarFoto, subirCaptura } from '../services/camera.js';
import * as X from '../services/expediente.js';

const STAFF = ['super_admin', 'admin', 'operations', 'billing', 'glosas', 'assistant', 'auditor'];
const CONFIG = ['super_admin', 'admin'];
const ORIGEN = { archivo: 'Archivo', camara: 'Cámara', escaner: 'Escáner' };
const PAGE = 50;

const pill = (txt, cls) => h('span', { class: `ac-pill ${cls}` }, txt);
const semPill = (s) => { const m = X.SEMAFORO[s] || { texto: s, clase: 'st-none', icono: '·' }; return h('span', { class: `ac-pill ${m.clase}` }, h('span', { 'aria-hidden': 'true' }, `${m.icono} `), m.texto); };
const field = (label, input, id) => h('label', { for: id, class: 'ex-field' }, label, input);
const tabla = (cols, rows, vacio = 'Nada por aquí.') => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table ex-table' },
  h('thead', {}, h('tr', {}, cols.map((c) => h('th', { class: c.r ? 'i18-r' : '' }, c.t)))),
  h('tbody', {}, rows.length ? rows : h('tr', {}, h('td', { colspan: cols.length, class: 'i18-empty' }, vacio)))));

export async function render(root, ctx = {}) {
  const role = ctx.role;
  const isStaff = STAFF.includes(role);
  const canConfig = CONFIG.includes(role);
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const tabsBar = h('div', { class: 'ex-tabs', role: 'tablist', 'aria-label': 'Secciones del expediente' });
  const msg = h('div', { 'aria-live': 'polite', id: 'ex-msg' });
  const body = h('div', { 'aria-live': 'polite', id: 'ex-body' });
  root.append(h('div', { class: 'i18-wrap ex-wrap' }, h('h2', {}, 'Expediente digital'),
    h('p', { class: 'i18-sub' }, 'Los soportes de cada reclamación (autorización, orden, informe, factura) adjuntos a la reclamación y no en el WhatsApp. El semáforo dice qué falta antes de radicar.'),
    top, tabsBar, msg, body));

  const say = (text, kind = 'ok') => msg.replaceChildren(note(text, kind));
  const fail = (e) => msg.replaceChildren(note(e.message || String(e), 'error'));

  // Cliente: el personal elige; el Médico y la Secretaria usan el suyo
  let org = isStaff ? null : (ctx.membership?.organization_id || null);
  if (isStaff) {
    const clients = await guarded(top, () => clientOptions());
    if (!clients) return;
    const sel = h('select', { id: 'ex-org' }, h('option', { value: '' }, 'Todos los clientes'), clients.map((c) => h('option', { value: c.id }, clientName(c))));
    sel.addEventListener('change', () => { org = sel.value || null; abierta = null; drawTab(); });
    top.replaceChildren(h('div', { class: 'i18-bar' }, field('Cliente', sel, 'ex-org')));
  }

  let tab = 'expedientes'; let abierta = null; let filtro = { semaforo: null, radicacion: null, offset: 0, texto: '' };
  const TABS = [['expedientes', 'Expedientes'], ...(role === 'capturer' ? [] : [['indicador', 'Indicador']]), ['espacio', 'Espacio'], ...(canConfig ? [['config', 'Configuración']] : [])];
  function drawTabs() {
    tabsBar.replaceChildren(...TABS.map(([k, t]) => h('button', { type: 'button', role: 'tab', id: `ex-tab-${k}`, class: `ex-tab${tab === k ? ' ex-on' : ''}`, 'aria-selected': tab === k ? 'true' : 'false',
      onclick: () => { tab = k; msg.replaceChildren(); drawTab(); } }, t)));
  }
  function drawTab() {
    drawTabs();
    if (tab === 'expedientes') return tabExpedientes();
    if (tab === 'indicador') return tabIndicador();
    if (tab === 'espacio') return tabEspacio();
    return tabConfig();
  }

  // ───────────────────────────────────────────────────────────── Expedientes
  async function tabExpedientes() {
    body.replaceChildren();
    const aviso = h('div', { 'aria-live': 'polite' }); const kpis = h('div', { 'aria-live': 'polite' }); const barra = h('div', { class: 'i18-bar ex-filters' });
    const lista = h('div', { 'aria-live': 'polite' }); const detalle = h('div', { 'aria-live': 'polite', id: 'ex-detail' });
    body.append(aviso, kpis, barra, lista, detalle);
    if (org) {
      X.espacioDeCliente(org).then((u) => { if (u && (u.status === 'aviso' || u.status === 'excedido')) aviso.replaceChildren(note(u.message, u.status === 'excedido' ? 'error' : 'warn')); }).catch(() => {});
    }
    let radic = [];
    if (org) { try { radic = await X.listarRadicaciones(org); } catch (_) { radic = []; } }
    const selR = h('select', { id: 'ex-rad' }, h('option', { value: '' }, 'Todas las radicaciones'), radic.map((r) => h('option', { value: r.id }, `${r.folio || r.id.slice(0, 8)} · ${String(r.period || '').slice(0, 7)}`)));
    selR.value = filtro.radicacion || '';
    selR.addEventListener('change', () => { filtro.radicacion = selR.value || null; filtro.offset = 0; cargar(); });
    const txt = h('input', { type: 'search', id: 'ex-q', placeholder: 'Buscar paciente o folio', value: filtro.texto, 'aria-label': 'Buscar paciente o folio' });
    txt.addEventListener('input', () => { filtro.texto = txt.value; pintar(ultimo); });
    barra.replaceChildren(org ? field('Radicación', selR, 'ex-rad') : null, field('Buscar', txt, 'ex-q'));
    let ultimo = null;

    let turno = 0;   // una respuesta lenta de una consulta anterior no debe pisar a la última
    async function cargar() {
      const mio = ++turno;
      const d = await guarded(lista, () => X.listarExpedientes(org, { submission: filtro.radicacion, semaforo: filtro.semaforo, limit: PAGE, offset: filtro.offset }));
      if (!d || mio !== turno) return;
      ultimo = d; pintar(d);
    }
    function pintar(d) {
      if (!d) return;
      const c = d.counts || {};
      kpis.replaceChildren(h('div', { class: 'i18-kpis' },
        ...['vacio', 'parcial', 'completo'].map((k) => h('button', { type: 'button', class: `ex-chip${filtro.semaforo === k ? ' ex-on' : ''}`, id: `ex-f-${k}`, 'aria-pressed': filtro.semaforo === k ? 'true' : 'false',
          onclick: () => { filtro.semaforo = filtro.semaforo === k ? null : k; filtro.offset = 0; cargar(); } }, semPill(k), ` ${num(c[k] || 0)}`))));
      const t = filtro.texto.trim().toLowerCase();
      const rows = (d.rows || []).filter((r) => !t || [r.patient_name, r.claim_folio, r.submission_folio].some((v) => (v || '').toLowerCase().includes(t)));
      const tb = tabla([{ t: 'Semáforo' }, { t: 'Reclamación' }, { t: 'Paciente' }, { t: 'ARS' }, { t: 'Falta' }, { t: '' }], rows.map((r) => h('tr', { class: abierta === r.service_line_id ? 'ex-sel' : '' },
        h('td', {}, semPill(r.semaforo), r.excepted ? h('div', { class: 'i18-sub' }, 'Con excepción') : null),
        h('td', {}, r.claim_folio || '—', h('div', { class: 'i18-sub' }, `${r.submission_folio || ''} · ${fmtDate(r.service_date)}`)),
        h('td', {}, r.patient_name), h('td', {}, r.ars || '—'),
        h('td', {}, (r.missing || []).length ? (r.missing || []).join(', ') : 'Nada'),
        h('td', {}, h('button', { type: 'button', class: 'btn sm', 'data-line': r.service_line_id, onclick: () => abrir(r.service_line_id) }, 'Abrir')))), 'No hay reclamaciones con este filtro.');
      const pie = h('div', { class: 'i18-bar' },
        h('span', { class: 'i18-sub' }, `${num(d.total)} reclamación(es)${d.total > PAGE ? ` · mostrando ${filtro.offset + 1}–${Math.min(filtro.offset + PAGE, d.total)}` : ''}`),
        filtro.offset > 0 ? h('button', { type: 'button', class: 'btn sm', onclick: () => { filtro.offset = Math.max(0, filtro.offset - PAGE); cargar(); } }, 'Anteriores') : null,
        filtro.offset + PAGE < d.total ? h('button', { type: 'button', class: 'btn sm', onclick: () => { filtro.offset += PAGE; cargar(); } }, 'Siguientes') : null);
      lista.replaceChildren(tb, pie);
    }

    let turnoDetalle = 0;
    async function abrir(line) {
      abierta = line; if (ultimo) pintar(ultimo);
      const mio = ++turnoDetalle;
      const d = await guarded(detalle, () => X.detalleExpediente(line));
      if (!d || mio !== turnoDetalle) return;
      pintarDetalle(d);
      detalle.scrollIntoView?.({ block: 'nearest' });
    }

    function pintarDetalle(d) {
      const items = (d.items || []).map((it) => {
        const docs = it.documents || [];
        return h('li', { class: `ex-item ${it.present ? 'ex-has' : (it.mandatory ? 'ex-miss' : '')}` },
          h('div', { class: 'ex-item-h' }, h('strong', {}, it.name), ' ', pill(it.mandatory ? 'Obligatorio' : 'Opcional', it.mandatory ? 'st-prep' : 'st-none'), ' ',
            it.present ? pill(docs.length ? 'Con archivo' : 'Recibido en físico', 'st-ok') : (it.mandatory ? pill('Falta', 'st-bad') : null)),
          docs.length ? h('ul', { class: 'ex-files' }, docs.map((f) => h('li', {}, h('button', { type: 'button', class: 'btn sm', onclick: () => ver(f) }, 'Ver'), ' ', f.file_name,
            h('span', { class: 'i18-sub' }, ` · ${sizeLabel(f.size_bytes)} · ${fmtDate(f.uploaded_at)} · ${ORIGEN[f.capture_origin] || f.capture_origin}`)))) : null,
          d.can_upload ? h('div', { class: 'ex-act' }, h('button', { type: 'button', class: 'btn sm', 'data-upload': it.code, onclick: () => panelSubida(d, it) }, docs.length ? 'Agregar otra página' : 'Subir o fotografiar')) : null);
      });
      const otros = d.other_documents || [];
      const exc = d.exception;
      detalle.replaceChildren(h('section', { class: 'i18-card ex-detail', 'aria-label': 'Detalle del expediente' },
        h('div', { class: 'i18-bar' }, h('h3', {}, `Reclamación ${d.claim_folio || ''}`), semPill(d.semaforo), h('button', { type: 'button', class: 'btn sm', id: 'ex-close', onclick: () => { abierta = null; detalle.replaceChildren(); if (ultimo) pintar(ultimo); } }, 'Cerrar')),
        h('p', { class: 'i18-sub' }, `${d.patient_name} · ${d.ars || 'Sin ARS'} · ${d.care_mode} · radicación ${d.submission_folio || '—'}`),
        d.semaforo === 'completo' ? note('Expediente completo: todos los documentos obligatorios están.', 'ok') : note(`Faltan ${(d.missing || []).length} documento(s) obligatorio(s): ${(d.missing || []).join(', ')}.`, 'warn'),
        exc ? note(`Excepción de expediente autorizada: ${exc.reason}. Se puede radicar aunque falten documentos.`, 'info') : null,
        h('ul', { class: 'ex-items' }, items),
        otros.length ? h('details', {}, h('summary', {}, `Otros archivos de la reclamación (${otros.length})`), h('ul', { class: 'ex-files' }, otros.map((f) => h('li', {}, h('button', { type: 'button', class: 'btn sm', onclick: () => ver(f) }, 'Ver'), ' ', f.file_name)))) : null,
        d.can_exception && d.semaforo !== 'completo' && !exc ? formExcepcion(d) : null,
        h('div', { id: 'ex-upload' })));
    }

    async function ver(f) {
      try { const url = await openDocument(f); if (url) say(`El navegador bloqueó la ventana. Abra el documento aquí: ${url}`, 'warn'); } catch (e) { fail(e); }
    }

    function formExcepcion(d) {
      const ta = h('textarea', { id: 'ex-exc-motivo', rows: 2, placeholder: 'Motivo (mínimo 10 caracteres)', 'aria-label': 'Motivo de la excepción' });
      return h('details', { class: 'ex-exc' }, h('summary', {}, 'Pedir excepción de expediente'),
        h('p', { class: 'i18-sub' }, 'Permite radicar aunque falten documentos. Queda registrada con su nombre y el motivo.'), ta,
        h('button', { type: 'button', class: 'btn', id: 'ex-exc-go', onclick: async () => {
          try { const n = await X.pedirExcepcion([d.service_line_id], ta.value); say(n ? 'Excepción registrada.' : 'No hacía falta: el expediente ya estaba completo.'); await abrir(d.service_line_id); cargar(); } catch (e) { fail(e); }
        } }, 'Autorizar excepción'));
    }

    // ── Subida: archivo (foto o PDF), foto con el teléfono o cámara en vivo
    function panelSubida(d, it) {
      const box = detalle.querySelector('#ex-upload'); let cam = null;
      const salida = h('div', { 'aria-live': 'polite' });
      const parar = () => { cam?.detener(); cam = null; };
      const terminar = async (texto) => { parar(); box.replaceChildren(); say(texto); await abrir(d.service_line_id); cargar(); };
      async function subirArchivo(file, origen) {
        salida.replaceChildren(note('Subiendo…'));
        try { await X.subirDocumento({ orgId: d.organization_id, submissionId: d.submission_id, lineId: d.service_line_id, docType: it.code, file, origen }); await terminar(`Documento «${it.name}» guardado en el expediente.`); }
        catch (e) { salida.replaceChildren(note(e.message || String(e), 'error')); }
      }
      const fileIn = h('input', { type: 'file', id: 'ex-file', accept: 'image/jpeg,image/png,image/webp,application/pdf', hidden: true });
      fileIn.addEventListener('change', () => { if (fileIn.files[0]) subirArchivo(fileIn.files[0], 'archivo'); });
      const capIn = h('input', { type: 'file', id: 'ex-cap', accept: 'image/*', capture: 'environment', hidden: true });
      capIn.addEventListener('change', () => { if (capIn.files[0]) subirArchivo(capIn.files[0], 'camara'); });
      const video = h('video', { id: 'ex-video', playsinline: true, muted: true, class: 'ex-video', 'aria-label': 'Vista de la cámara' });
      const camBox = h('div', { class: 'ex-cam', hidden: true }, video,
        h('button', { type: 'button', class: 'btn primary', id: 'ex-snap', onclick: async () => {
          try {
            const canvas = cam.foto(); const f = await procesarFoto(canvas);
            parar(); camBox.hidden = true; salida.replaceChildren(note('Subiendo…'));
            await subirCaptura({ orgId: d.organization_id, submissionId: d.submission_id, lineId: d.service_line_id, docType: it.code, blob: f.blob, sha256: f.sha256, origen: 'camara', nombre: `${it.code}.jpg` });
            await terminar(`Foto de «${it.name}» guardada en el expediente.`);
          } catch (e) { salida.replaceChildren(note(e.message || String(e), 'error')); }
        } }, 'Tomar foto'),
        h('button', { type: 'button', class: 'btn', onclick: () => { parar(); camBox.hidden = true; } }, 'Cerrar cámara'));
      box.replaceChildren(h('section', { class: 'i18-card ex-up', 'aria-label': `Subir ${it.name}` },
        h('h4', {}, `Subir: ${it.name}`),
        h('p', { class: 'i18-sub' }, 'La foto se reduce y se limpia en este dispositivo antes de subirla. Acepta fotos y PDF de hasta 10 MB.'),
        h('div', { class: 'i18-bar' },
          h('button', { type: 'button', class: 'btn', id: 'ex-pick', onclick: () => fileIn.click() }, 'Elegir archivo'),
          h('button', { type: 'button', class: 'btn', id: 'ex-phone', onclick: () => capIn.click() }, 'Tomar foto con el teléfono'),
          camaraEnVivoDisponible() ? h('button', { type: 'button', class: 'btn', id: 'ex-live', onclick: async () => {
            try { camBox.hidden = false; cam = await iniciarCamara(video); salida.replaceChildren(); } catch (e) { camBox.hidden = true; salida.replaceChildren(note(e.message, 'error')); }
          } }, 'Abrir cámara') : null,
          h('button', { type: 'button', class: 'btn', onclick: () => { parar(); box.replaceChildren(); } }, 'Cancelar')),
        fileIn, capIn, camBox, salida));
      box.scrollIntoView?.({ block: 'nearest' });
    }

    await cargar();
  }

  // ───────────────────────────────────────────────────────────── Indicador
  async function tabIndicador() {
    body.replaceChildren();
    const hoy = new Date(); const ini = new Date(hoy); ini.setDate(ini.getDate() - 90);
    const iso = (d) => d.toISOString().slice(0, 10);
    const desde = h('input', { type: 'date', id: 'ex-desde', value: iso(ini) }); const hasta = h('input', { type: 'date', id: 'ex-hasta', value: iso(hoy) });
    const out = h('div', { 'aria-live': 'polite' });
    const go = h('button', { type: 'button', class: 'btn', id: 'ex-ind-go', onclick: cargar }, 'Ver indicador');
    body.append(h('p', { class: 'i18-sub' }, 'Porcentaje de reclamaciones que tenían el expediente completo en el momento de radicar. Es la foto de ese instante: subir documentos después no la cambia.'),
      h('div', { class: 'i18-bar' }, field('Desde', desde, 'ex-desde'), field('Hasta', hasta, 'ex-hasta'), go), out);
    if (!org && !isStaff) { out.replaceChildren(note('No se encontró su consultorio. Escriba a SOFA.', 'warn')); return; }
    async function cargar() {
      const d = await guarded(out, () => X.indicadorExpediente(org, desde.value || null, hasta.value || null));
      if (!d) return;
      const s = d.summary || {};
      out.replaceChildren(
        h('div', { class: 'i18-kpis' }, kpi('Expedientes completos al radicar', s.pct_completo == null ? '—' : pct(s.pct_completo), `Meta: ${d.target_pct} % o más`),
          kpi('Reclamaciones radicadas', num(s.total)), kpi('Completas', num(s.completos)), kpi('Con excepción', num(s.con_excepcion)), kpi('Incompletas', num(s.incompletos))),
        d.meets_target == null ? note('Todavía no hay reclamaciones radicadas en este período.', 'info')
          : d.meets_target ? note('Se cumple la meta del período.', 'ok') : note(`Por debajo de la meta de ${d.target_pct} %. Revise las ARS con menos expedientes completos y pida los documentos antes de radicar.`, 'warn'),
        h('h3', {}, 'Por ARS'), tabla([{ t: 'ARS' }, { t: 'Radicadas', r: true }, { t: 'Completas', r: true }, { t: '% completo', r: true }],
          (d.by_ars || []).map((r) => h('tr', {}, h('td', {}, r.ars || '—'), h('td', { class: 'i18-r' }, num(r.total)), h('td', { class: 'i18-r' }, num(r.completos)), h('td', { class: 'i18-r' }, pct(r.pct_completo))))),
        h('h3', {}, 'Por mes'), tabla([{ t: 'Mes' }, { t: 'Radicadas', r: true }, { t: 'Completas', r: true }, { t: '% completo', r: true }],
          (d.by_month || []).map((r) => h('tr', {}, h('td', {}, r.month), h('td', { class: 'i18-r' }, num(r.total)), h('td', { class: 'i18-r' }, num(r.completos)), h('td', { class: 'i18-r' }, pct(r.pct_completo))))));
    }
    await cargar();
  }

  // ───────────────────────────────────────────────────────────── Espacio
  const mb = (n) => `${Number(n || 0).toLocaleString('es-DO', { maximumFractionDigits: 1 })} MB`;
  async function tabEspacio() {
    body.replaceChildren();
    const out = h('div', { 'aria-live': 'polite' }); body.append(out);
    body.prepend(note('Aquí solo se mide y se avisa. SOFA no borra documentos ni archivos por su cuenta: qué hacer con lo antiguo o con lo que pasó el límite lo decide el administrador.', 'info'));
    if (!canConfig) {
      if (!org) { out.replaceChildren(note('Elija un cliente para ver su espacio.', 'info')); return; }
      const u = await guarded(out, () => X.espacioDeCliente(org)); if (!u) return;
      const e = X.ESTADO_ESPACIO[u.status] || { texto: u.status, clase: 'st-none' };
      out.replaceChildren(h('div', { class: 'i18-kpis' }, kpi('Espacio usado', mb(u.mb), `${num(u.files)} archivo(s)`), kpi('Límite', u.limit_mb == null ? 'Sin límite' : mb(u.limit_mb), u.pct_used == null ? '' : pct(u.pct_used)), kpi('Estado', pill(e.texto, e.clase))),
        u.message ? note(u.message, u.status === 'excedido' ? 'error' : 'warn') : null);
      return;
    }
    const r = await guarded(out, () => X.reporteEspacio()); if (!r) return;
    const s = r.summary || {};
    const filas = (r.rows || []).map((x) => {
      const e = X.ESTADO_ESPACIO[x.status] || { texto: x.status, clase: 'st-none' };
      const inp = h('input', { type: 'number', min: '1', step: '1', value: x.limit_source === 'cliente' ? x.limit_mb : '', placeholder: x.limit_mb == null ? 'Sin límite' : `${x.limit_mb} (general)`, class: 'ex-lim', 'aria-label': `Límite en MB de ${x.client}`, 'data-org': x.organization_id });
      return h('tr', {}, h('td', {}, x.client), h('td', { class: 'i18-r' }, num(x.files)), h('td', { class: 'i18-r' }, mb(x.mb)),
        h('td', { class: 'i18-r' }, x.pct_used == null ? '—' : pct(x.pct_used)), h('td', {}, pill(e.texto, e.clase)),
        h('td', { class: 'i18-r' }, x.files_over_retention ? `${num(x.files_over_retention)} (${mb(x.mb_over_retention)})` : '0'),
        h('td', {}, inp, ' ', h('button', { type: 'button', class: 'btn sm', 'data-save': x.organization_id, onclick: async () => {
          try { await X.fijarLimiteCliente(x.organization_id, inp.value ? Number(inp.value) : null); say(`Límite de ${x.client} guardado.`); tabEspacio(); } catch (e2) { fail(e2); }
        } }, 'Guardar')));
    });
    out.replaceChildren(
      h('div', { class: 'i18-kpis' }, kpi('Espacio total', mb(s.mb), `${num(s.files)} archivo(s) · ${num(s.clients)} cliente(s)`), kpi('Cerca del límite', num(s.en_aviso)), kpi('Pasaron el límite', num(s.excedidos)),
        kpi(`Más viejos de ${s.retention_years} años`, num(s.files_over_retention), 'Solo se cuentan; no se borran')),
      tabla([{ t: 'Cliente' }, { t: 'Archivos', r: true }, { t: 'Espacio', r: true }, { t: '% del límite', r: true }, { t: 'Estado' }, { t: 'Pasan la conservación', r: true }, { t: 'Límite propio (MB)' }], filas));
  }

  // ───────────────────────────────────────────────────────────── Configuración
  async function tabConfig() {
    body.replaceChildren();
    const params = h('div', { 'aria-live': 'polite' }); const reglas = h('div', { 'aria-live': 'polite' });
    body.append(params, h('h3', {}, 'Documentos requeridos por ARS'), reglas);
    const p = await guarded(params, () => X.parametros(org)); if (!p) return;
    const bloqueo = h('input', { type: 'checkbox', id: 'ex-p-bloqueo' }); bloqueo.checked = !!p.block_radicar;
    const anios = h('input', { type: 'number', min: '1', max: '50', id: 'ex-p-anios', value: p.retention_years });
    const lim = h('input', { type: 'number', min: '1', id: 'ex-p-lim', value: p.default_limit_mb ?? '', placeholder: 'Sin límite' });
    const aviso = h('input', { type: 'number', min: '50', max: '99', id: 'ex-p-aviso', value: p.warn_pct });
    const meta = h('input', { type: 'number', min: '50', max: '100', id: 'ex-p-meta', value: p.target_pct });
    params.replaceChildren(h('section', { class: 'i18-card' }, h('h3', {}, 'Parámetros del expediente'),
      h('label', { for: 'ex-p-bloqueo', class: 'ex-check' }, bloqueo, ' Bloquear radicar si el expediente está incompleto'),
      h('p', { class: 'i18-sub' }, 'Apagado al inicio. Encendido, una radicación no pasa a Radicada si alguna reclamación no tiene sus documentos obligatorios; la salida es la excepción de expediente.'),
      h('div', { class: 'i18-form ex-grid' }, field('Años de conservación (solo aviso)', anios, 'ex-p-anios'), field('Límite general de espacio por cliente (MB)', lim, 'ex-p-lim'),
        field('Avisar al llegar a (%)', aviso, 'ex-p-aviso'), field('Meta de expedientes completos al radicar (%)', meta, 'ex-p-meta')),
      h('p', { class: 'i18-sub' }, 'La conservación y el espacio solo se miden y se avisan: nada se borra automáticamente.'),
      h('button', { type: 'button', class: 'btn primary', id: 'ex-p-save', onclick: async () => {
        try {
          await X.guardarParametros({ bloqueo: bloqueo.checked, anios: Number(anios.value), limiteMb: lim.value ? Number(lim.value) : null, aviso: Number(aviso.value), meta: Number(meta.value) });
          say('Parámetros guardados.');
        } catch (e) { fail(e); }
      } }, 'Guardar parámetros')));
    let arsList = [];
    try { arsList = await X.listarArs(); } catch (e) { reglas.replaceChildren(note(e.message, 'error')); return; }
    const selA = h('select', { id: 'ex-ars' }, h('option', { value: '' }, 'Elija una ARS…'), arsList.map((a) => h('option', { value: a.id }, a.name)));
    const caja = h('div', { 'aria-live': 'polite' });
    reglas.replaceChildren(h('p', { class: 'i18-sub' }, 'Lo que se escribe aquí manda sobre la regla general de esa ARS. «Heredar» quita la regla propia y vuelve a regir la general.'), h('div', { class: 'i18-bar' }, field('ARS', selA, 'ex-ars')), caja);
    selA.addEventListener('change', () => cargarReglas());
    async function cargarReglas() {
      if (!selA.value) { caja.replaceChildren(); return; }
      const d = await guarded(caja, () => X.reglasDeArs(selA.value)); if (!d) return;
      const nombre = Object.fromEntries((d.types || []).map((t) => [t.code, t.name]));
      const fila = (r) => {
        const s = h('select', { 'aria-label': `Exigencia de ${nombre[r.document_type_code] || r.document_type_code}` }, Object.entries(X.EXIGENCIA).map(([k, v]) => h('option', { value: k }, v))); s.value = r.requirement;
        s.addEventListener('change', async () => { try { await X.guardarRegla(selA.value, r.document_type_code, s.value, r.care_mode); say('Regla guardada.'); } catch (e) { fail(e); } });
        return h('tr', {}, h('td', {}, nombre[r.document_type_code] || r.document_type_code), h('td', {}, X.MODALIDAD[r.care_mode || ''] || r.care_mode), h('td', {}, s),
          h('td', {}, h('button', { type: 'button', class: 'btn sm', onclick: async () => { try { await X.guardarRegla(selA.value, r.document_type_code, 'heredar', r.care_mode); say('Regla quitada: vuelve a regir la general.'); cargarReglas(); } catch (e) { fail(e); } } }, 'Heredar')));
      };
      const nt = h('select', { id: 'ex-n-tipo', 'aria-label': 'Tipo de documento' }, (d.types || []).map((t) => h('option', { value: t.code }, t.name)));
      const nm = h('select', { id: 'ex-n-mod', 'aria-label': 'Modalidad' }, Object.entries(X.MODALIDAD).map(([k, v]) => h('option', { value: k }, v)));
      const ne = h('select', { id: 'ex-n-exi', 'aria-label': 'Exigencia' }, Object.entries(X.EXIGENCIA).map(([k, v]) => h('option', { value: k }, v)));
      caja.replaceChildren(tabla([{ t: 'Documento' }, { t: 'Modalidad' }, { t: 'Exigencia' }, { t: '' }], (d.ars_rules || []).map(fila), 'Esta ARS no tiene reglas propias: rige la regla general.'),
        h('div', { class: 'i18-bar' }, nt, nm, ne, h('button', { type: 'button', class: 'btn', id: 'ex-n-add', onclick: async () => {
          try { await X.guardarRegla(selA.value, nt.value, ne.value, nm.value || null); say('Regla guardada.'); cargarReglas(); } catch (e) { fail(e); }
        } }, 'Agregar regla')));
    }
  }

  drawTab();
}
