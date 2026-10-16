/** SOFA · 4.8 · I58 · «Aplicar pago»: conciliación automática de la relación de pago de la ARS.
 *  1) Cargar el Excel o CSV de la relación (el mapeo de columnas se guarda por ARS y se reutiliza).
 *  2) El motor pone a cada línea un nivel de confianza: segura, dudosa o sin pareja (las reglas son visibles).
 *  3) Las seguras se aplican con un clic; las dudosas se resuelven una por una; las sin pareja quedan a la vista.
 *  4) Lo pagado de menos y lo rechazado se convierte en glosa con un clic.
 *  Todo se aplica con las funciones de pagos de la base (register_payment y adjust_payment_distribution); esta pantalla nunca escribe directo.
 *  Quién puede qué lo decide el servidor en cada función; los botones se ocultan solo para que nadie vea lo que no puede hacer. */
import { rpc, h, money, fmtDate, note, kpi, guarded, todayIso, clientOptions, clientName } from '../services/iter18.js';
import { readTable, excelDate, detectColumns } from '../utils/xlsx-lite.js';

const MANAGE = ['super_admin', 'admin', 'glosas'];   // cargar, resolver, ignorar y convertir en glosa
const APPLY = ['super_admin', 'admin'];              // aplicar el pago (mueve dinero)
const CHUNK = 250;                                   // líneas por llamada al aplicar: la API corta las llamadas largas
const REVIEW_CHUNK = 300;

const FIELDS = [
  ['nss', 'NSS o cédula del afiliado'], ['autorizacion', 'Número de autorización'], ['fecha', 'Fecha del servicio'], ['facturado', 'Monto facturado'],
  ['pagado', 'Monto pagado (obligatorio)'], ['estado', 'Estado (pagada, parcial, rechazada)'], ['motivo', 'Motivo o causa de la ARS'], ['paciente', 'Nombre del paciente']];
const ALIASES = {
  nss: ['nss', 'no afiliado', 'numero afiliado', 'numero de afiliado', 'afiliado', 'cedula', 'id afiliado', 'documento afiliado', 'nss afiliado', 'no nss'],
  autorizacion: ['autorizacion', 'no autorizacion', 'numero autorizacion', 'numero de autorizacion', 'aut', 'no aut', 'nro autorizacion', 'codigo autorizacion'],
  fecha: ['fecha servicio', 'fecha de servicio', 'fecha atencion', 'fecha de atencion', 'fecha'],
  facturado: ['monto facturado', 'facturado', 'valor reclamado', 'valor facturado', 'monto reclamado', 'reclamado'],
  pagado: ['monto pagado', 'pagado', 'valor aprobado', 'monto aprobado', 'valor pagado', 'importe pagado', 'aprobado'],
  estado: ['estado', 'estatus', 'status', 'situacion'],
  motivo: ['motivo', 'observacion', 'observaciones', 'causa', 'motivo rechazo', 'motivo de glosa', 'comentario'],
  paciente: ['paciente', 'nombre paciente', 'nombre del paciente', 'nombre afiliado', 'nombre del afiliado']
};
const PILL = { segura: ['Segura', 'st-ok'], dudosa: ['Dudosa', 'st-req'], sin_pareja: ['Sin pareja', 'st-bad'], duplicado: ['Duplicado', 'st-none'], aplicada: ['Aplicada', 'st-ok'],
  glosada: ['Convertida en glosa', 'st-prep'], ignorada: ['Ignorada', 'st-none'], pendiente: ['Sin revisar', 'st-none'] };
const REM_STATUS = { cargada: 'Cargada', en_aplicacion: 'En aplicación', aplicada: 'Aplicada', anulada: 'Anulada' };
const TABS = [['segura', 'Seguras'], ['dudosa', 'Dudosas'], ['sin_pareja', 'Sin pareja'], ['diferencia', 'Diferencias'], ['hechas', 'Aplicadas'], ['duplicado', 'Duplicados'], ['ignorada', 'Ignoradas']];

const pill = (s) => h('span', { class: `ac-pill ${(PILL[s] || [s, 'st-none'])[1]}` }, (PILL[s] || [s])[0]);
const num = (n) => Number(n || 0);

/** Reglas cumplidas por una línea (visibles: qué sumó y qué no) */
function rulesList(rules) {
  return h('ul', { class: 'ap-rules' }, (rules || []).map((r) => h('li', { class: r.ok ? 'ap-ok' : 'ap-no' },
    h('span', { 'aria-hidden': 'true' }, r.ok ? '✔ ' : '✖ '), r.detail || r.code, r.points ? h('strong', {}, ` (+${r.points})`) : null)));
}

function table(cols, rows) {
  return h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table ap-table' },
    h('thead', {}, h('tr', {}, cols.map((c) => h('th', { class: c.r ? 'i18-r' : '' }, c.t)))),
    h('tbody', {}, rows.length ? rows : h('tr', {}, h('td', { colspan: cols.length, class: 'i18-empty' }, 'Nada por aquí.')))));
}

export async function render(root, ctx = {}) {
  const canManage = MANAGE.includes(ctx.role);
  const canApply = APPLY.includes(ctx.role);
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const msg = h('div', { 'aria-live': 'polite', id: 'ap-msg' });
  const kpis = h('div', { 'aria-live': 'polite' });
  const upload = h('div', { 'aria-live': 'polite' });
  const list = h('div', { 'aria-live': 'polite' });
  const detail = h('div', { 'aria-live': 'polite', id: 'ap-detail' });
  root.append(h('div', { class: 'i18-wrap ap-wrap' }, h('h2', {}, 'Aplicar pago'),
    h('p', { class: 'i18-sub' }, 'Cargue la relación de pago de la ARS: las coincidencias seguras se aplican con un clic, las dudosas se resuelven una por una y lo pagado de menos se convierte en glosa.'),
    top, msg, kpis, upload, list, detail));

  const clients = await guarded(top, () => clientOptions());
  if (!clients) return;
  if (!clients.length) { top.replaceChildren(note('No hay clientes activos.')); return; }
  const orgSel = h('select', { id: 'ap-org' }, clients.map((c) => h('option', { value: c.id }, clientName(c))));
  top.replaceChildren(h('div', { class: 'i18-bar' }, h('label', { for: 'ap-org' }, 'Cliente', orgSel)));
  let openId = null; let tab = 'segura'; let offset = 0; let ars = null;
  orgSel.addEventListener('change', () => { openId = null; detail.replaceChildren(); loadAll(); });
  const say = (text, kind = 'ok') => { msg.replaceChildren(note(text, kind)); };
  const fail = (e) => { msg.replaceChildren(note(e.message || String(e), 'error')); };

  async function loadAll() {
    msg.replaceChildren();
    await Promise.all([loadKpis(), loadList()]);
    if (canManage) await drawUpload();
  }

  async function loadKpis() {
    const d = await guarded(kpis, () => rpc('remittance_indicator', { p_org: orgSel.value }));
    if (!d) return;
    const s = d.summary || {};
    kpis.replaceChildren(h('div', { class: 'i18-kpis' },
      kpi('Pagos aplicados sin intervención manual', s.pct_auto == null ? '—' : `${s.pct_auto} %`, `${money(s.auto)} de ${money(s.total)} en las relaciones`),
      kpi('Aplicado a mano', money(s.manual)), kpi('Por resolver', money(s.pending), 'Seguras sin aplicar, dudosas y sin pareja'), kpi('Relaciones', String(s.remittances || 0))));
  }

  async function loadList() {
    const rows = await guarded(list, () => rpc('remittance_list', { p_org: orgSel.value }));
    if (!rows) return;
    const trs = rows.map((r) => {
      const c = r.counts || {};
      const open = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Abrir');
      open.addEventListener('click', () => { openId = r.id; tab = (c.segura ? 'segura' : c.dudosa ? 'dudosa' : c.sin_pareja ? 'sin_pareja' : 'hechas'); offset = 0; drawDetail(); });
      return h('tr', {}, h('td', {}, r.folio), h('td', {}, r.ars), h('td', {}, r.reference), h('td', {}, fmtDate(r.paid_on)), h('td', { class: 'i18-r' }, money(r.total_paid)),
        h('td', { class: 'i18-r' }, money(r.applied_amount)),
        h('td', {}, [['segura', 'seguras'], ['dudosa', 'dudosas'], ['sin_pareja', 'sin pareja']].filter(([k]) => c[k]).map(([k, l]) => `${c[k]} ${l}`).join(' · ') || '—'),
        h('td', {}, REM_STATUS[r.status] || r.status), h('td', {}, open));
    });
    list.replaceChildren(h('h3', {}, 'Relaciones de pago cargadas'),
      table([{ t: 'Folio' }, { t: 'ARS' }, { t: 'Referencia' }, { t: 'Fecha de pago' }, { t: 'Total pagado', r: 1 }, { t: 'Aplicado', r: 1 }, { t: 'Por resolver' }, { t: 'Estado' }, { t: '' }], trs));
  }

  /* ───────────────────────── Cargar una relación ───────────────────────── */
  async function drawUpload() {
    const catalog = await rpc('ars_catalog', { p_include_inactive: false }).catch(() => []);
    const arsSel = h('select', { id: 'ap-ars' }, h('option', { value: '' }, 'Elija la ARS…'), catalog.map((a) => h('option', { value: a.id }, a.name)));
    const fmtSel = h('select', { id: 'ap-fmt' }, h('option', { value: '' }, 'Formato nuevo (indicar columnas)'));
    const file = h('input', { id: 'ap-file', type: 'file', accept: '.xlsx,.csv,.txt' });
    const ref = h('input', { id: 'ap-ref', maxlength: '60', placeholder: 'Ej.: transferencia 0045123' });
    const paidOn = h('input', { id: 'ap-paid', type: 'date', value: todayIso(), max: todayIso() });
    const total = h('input', { id: 'ap-total', type: 'number', min: '0', step: '0.01', placeholder: 'Opcional' });
    const mapBox = h('div', { id: 'ap-map', 'aria-live': 'polite' });
    const out = h('div', { 'aria-live': 'polite', id: 'ap-up-out' });
    const review = h('button', { class: 'i18-btn', type: 'button', id: 'ap-review' }, 'Revisar el archivo');
    let formats = []; let table_ = null; let hi = 0; let selects = {}; let saveName = null; let saveChk = null;

    async function loadFormats() {
      formats = arsSel.value ? await rpc('payment_formats_list', { p_org: orgSel.value, p_ars: arsSel.value }).catch(() => []) : [];
      fmtSel.replaceChildren(h('option', { value: '' }, 'Formato nuevo (indicar columnas)'), formats.map((f) => h('option', { value: f.id }, `${f.name}${f.used_count ? ` · usado ${f.used_count} vez(es)` : ''}`)));
      if (formats.length) { fmtSel.value = formats[0].id; }
      drawMap();
    }
    arsSel.addEventListener('change', loadFormats);
    fmtSel.addEventListener('change', drawMap);
    file.addEventListener('change', async () => {
      out.replaceChildren(); table_ = null;
      if (!file.files[0]) return;
      try {
        const t = await readTable(file.files[0]);
        // Algunas ARS ponen líneas de título antes de la tabla: se busca la fila de encabezados (monto pagado y NSS o autorización)
        hi = -1;
        for (let i = 0; i < Math.min(t.length, 25); i++) { const m = detectColumns(t[i], ALIASES); if (m.pagado != null && (m.nss != null || m.autorizacion != null)) { hi = i; break; } }
        if (hi < 0) hi = t.findIndex((r) => r.filter((x) => String(x).trim()).length >= 3);
        if (hi < 0) throw new Error('No se encontraron los títulos de las columnas. El archivo debe tener, por ejemplo, «Afiliado», «Autorización» y «Monto pagado».');
        table_ = t; drawMap();
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
    });

    function headers() { return table_ ? table_[hi].map((x) => String(x).trim()).filter(Boolean) : []; }
    function drawMap() {
      selects = {};
      if (!table_) { mapBox.replaceChildren(note('Elija la ARS y el archivo para indicar qué columna es cada dato.')); return; }
      const hd = headers(); const saved = formats.find((f) => f.id === fmtSel.value);
      const auto = detectColumns(table_[hi], ALIASES);
      const sels = FIELDS.map(([k, lab]) => {
        const s = h('select', { id: `ap-col-${k}`, 'aria-label': lab }, h('option', { value: '' }, k === 'pagado' ? 'Elija la columna…' : '— no viene en el archivo —'), hd.map((x) => h('option', { value: x }, x)));
        const want = saved ? saved.columns[k] : (auto[k] != null ? String(table_[hi][auto[k]]).trim() : '');
        if (want && hd.includes(want)) s.value = want;
        selects[k] = s; return h('label', { for: `ap-col-${k}` }, lab, s);
      });
      saveName = h('input', { id: 'ap-fname', maxlength: '60', placeholder: 'Ej.: Humano · relación mensual' });
      saveChk = h('input', { id: 'ap-fsave', type: 'checkbox', checked: !saved });
      mapBox.replaceChildren(h('fieldset', { class: 'i18-fs ap-map' }, h('legend', {}, saved ? `Columnas del formato «${saved.name}» (puede ajustarlas)` : 'Indique qué columna es cada dato'),
        h('div', { class: 'ap-grid' }, sels),
        saved ? null : h('div', { class: 'ap-save' }, h('label', { class: 'i18-chk', for: 'ap-fsave' }, saveChk, ' Guardar estas columnas como formato para la próxima vez'), h('label', { for: 'ap-fname' }, 'Nombre del formato', saveName))));
    }
    const columnsNow = () => { const c = {}; for (const [k] of FIELDS) if (selects[k]?.value) c[k] = selects[k].value; return c; };
    function objectRows(cols) {
      const hd = table_[hi].map((x) => String(x).trim());
      return table_.slice(hi + 1).filter((r) => r.some((c) => String(c ?? '').trim())).map((r) => {
        const o = {}; hd.forEach((name, i) => { if (name) o[name] = String(r[i] ?? '').trim(); });
        if (cols.fecha && o[cols.fecha] != null) o[cols.fecha] = excelDate(o[cols.fecha]);
        return o;
      });
    }

    async function run(commit) {
      out.replaceChildren();
      if (!arsSel.value) return out.replaceChildren(note('Elija la ARS que hizo el pago.', 'error'));
      if (!table_) return out.replaceChildren(note('Elija el archivo de la relación de pago (.xlsx o .csv).', 'error'));
      const cols = columnsNow(); const rows = objectRows(cols);
      const saved = formats.find((f) => f.id === fmtSel.value);
      const sameAsSaved = saved && JSON.stringify(Object.entries(saved.columns).sort()) === JSON.stringify(Object.entries(cols).sort());
      let fmtId = sameAsSaved ? saved.id : null;
      try {
        if (commit && saveChk && saveChk.checked && !sameAsSaved) { fmtId = await rpc('payment_format_save', { p_org: orgSel.value, p_ars: arsSel.value, p_name: saveName.value, p_columns: cols }); }
        const args = { p_org: orgSel.value, p_ars: arsSel.value, p_rows: rows, p_format: fmtId, p_columns: fmtId ? null : cols, p_reference: ref.value || null,
          p_paid_on: paidOn.value || null, p_declared_total: total.value === '' ? null : Number(total.value), p_commit: commit, p_file: file.files[0].name };
        const r = await rpc('remittance_import', args);
        if (r.already_imported) {
          out.replaceChildren(note(`Este archivo ya se cargó como la relación ${r.existing_folio}. No se duplicó nada.`, 'ok'));
          if (commit && r.remittance) { openId = r.remittance; tab = 'segura'; offset = 0; await loadAll(); drawDetail(); }
          return;
        }
        if (!commit) { preview(r); return; }
        out.replaceChildren(); table_ = null; file.value = ''; ref.value = '';
        openId = r.remittance; tab = 'segura'; offset = 0; await loadAll(); drawDetail();
        say(`Relación cargada: ${r.valid} fila(s)${r.duplicates_in_file + r.duplicates_previous ? `, ${r.duplicates_in_file + r.duplicates_previous} repetida(s) sin aplicar` : ''}.`);
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
    }
    review.addEventListener('click', () => run(false));

    function preview(r) {
      const go = h('button', { class: 'i18-btn', type: 'button', id: 'ap-commit', disabled: r.errors.length > 0 || !r.valid }, `Confirmar: cargar ${r.valid} fila(s)`);
      go.addEventListener('click', () => { go.disabled = true; run(true); });
      out.replaceChildren(
        h('div', { class: 'ac-sum ap-sum' }, h('span', { class: 'ac-pill st-prep' }, `${r.valid} filas válidas`), h('span', { class: 'ac-pill st-none' }, `${r.duplicates_in_file + r.duplicates_previous} repetidas (no se aplicarán)`),
          h('span', { class: `ac-pill ${r.errors.length ? 'st-bad' : 'st-ok'}` }, `${r.errors.length} con error`), h('span', { class: 'ac-pill st-ok' }, `Total pagado ${money(r.total_paid)}`)),
        r.total_difference ? note(`El total declarado (${money(r.declared_total)}) difiere en ${money(r.total_difference)} de la suma del archivo. Si la ARS retuvo impuestos, es normal; si no, revise el archivo.`, 'warn') : null,
        r.errors.length ? h('div', {}, note('Corrija estas filas en el archivo y vuélvalo a cargar. No se guarda nada mientras haya errores.', 'error'),
          table([{ t: 'Fila del archivo' }, { t: 'Qué corregir' }], r.errors.map((e) => h('tr', {}, h('td', {}, String(e.row + hi + 1)), h('td', {}, e.errors.join(' · ')))))) : null,
        r.rows.length ? table([{ t: 'Fila' }, { t: 'NSS' }, { t: 'Autorización' }, { t: 'Fecha' }, { t: 'Facturado', r: 1 }, { t: 'Pagado', r: 1 }, { t: 'Estado' }],
          r.rows.slice(0, 20).map((x) => h('tr', {}, h('td', {}, String(x.row_no)), h('td', {}, x.nss_raw || '—'), h('td', {}, x.auth_raw || '—'), h('td', {}, fmtDate(x.service_date)),
            h('td', { class: 'i18-r' }, x.billed == null ? '—' : money(x.billed)), h('td', { class: 'i18-r' }, money(x.paid)), h('td', {}, x.state === 'duplicado' ? 'Repetida' : x.ars_status)))) : null,
        h('div', { class: 'i18-actions' }, go));
    }

    upload.replaceChildren(h('section', { class: 'i18-card' }, h('h3', {}, 'Cargar una relación de pago'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'ap-ars' }, 'ARS', arsSel), h('label', { for: 'ap-fmt' }, 'Formato guardado', fmtSel), h('label', { for: 'ap-file' }, 'Archivo (.xlsx o .csv)', file)),
      h('div', { class: 'i18-bar' }, h('label', { for: 'ap-ref' }, 'Referencia del pago de la ARS', ref), h('label', { for: 'ap-paid' }, 'Fecha del pago', paidOn), h('label', { for: 'ap-total' }, 'Total declarado (RD$)', total)),
      mapBox, h('div', { class: 'i18-actions' }, review), out));
    ars = arsSel; drawMap();
  }

  /* ───────────────────────── Detalle de una relación ───────────────────────── */
  async function drawDetail() {
    if (!openId) { detail.replaceChildren(); return; }
    // Relaciones grandes: el motor revisa por tandas lo que quedó sin revisar
    if (canManage) {
      try {
        for (let i = 0; i < 40; i++) {
          const pre = await rpc('remittance_detail', { p_remittance: openId, p_state: 'pendiente', p_limit: 1 });
          if (!num(pre.counts.pendiente)) break;
          detail.replaceChildren(note(`Revisando coincidencias… faltan ${pre.counts.pendiente} línea(s).`));
          await rpc('remittance_match', { p_remittance: openId, p_only_pending: true, p_max: REVIEW_CHUNK });
        }
      } catch (e) { return fail(e); }
    }
    const state = tab === 'hechas' ? 'aplicada' : tab;
    let d = await guarded(detail, () => rpc('remittance_detail', { p_remittance: openId, p_state: state, p_limit: 300, p_offset: offset }));
    if (!d) return;
    let lines = d.lines;
    if (tab === 'hechas') {
      const g = await rpc('remittance_detail', { p_remittance: openId, p_state: 'glosada', p_limit: 300, p_offset: 0 }).catch(() => ({ lines: [] }));
      lines = lines.concat(g.lines);
    }
    const r = d.remittance; const c = d.counts; const diff = d.differences || { lines: 0, amount: 0 };
    const tabBtns = TABS.map(([k, l]) => {
      const n = k === 'diferencia' ? num(diff.lines) : k === 'hechas' ? num(c.aplicada) + num(c.glosada) : num(c[k]);
      const b = h('button', { class: `ap-tab${k === tab ? ' ap-on' : ''}`, type: 'button', role: 'tab', 'aria-selected': k === tab ? 'true' : 'false', id: `ap-tab-${k}` }, `${l} (${n})`);
      b.addEventListener('click', () => { tab = k; offset = 0; drawDetail(); });
      return b;
    });
    const head = h('section', { class: 'i18-card ap-head' },
      h('div', { class: 'i18-bar' }, h('h3', {}, `${r.folio} · ${r.ars}`), h('span', { class: 'i18-sub' }, `Referencia ${r.reference} · pago del ${fmtDate(r.paid_on)} · ${REM_STATUS[r.status] || r.status}`),
        h('button', { class: 'i18-link', type: 'button', id: 'ap-close', onclick: () => { openId = null; detail.replaceChildren(); loadAll(); } }, 'Cerrar')),
      h('div', { class: 'i18-kpis' }, kpi('Total pagado en la relación', money(r.total_paid)), kpi('Ya aplicado', money(r.applied_amount)), kpi('Seguras por aplicar', money(r.to_apply_amount)),
        kpi('Diferencias abiertas', money(diff.amount), `${diff.lines} línea(s)`)),
      r.applications?.length ? h('p', { class: 'i18-sub' }, `Pagos registrados desde esta relación: ${r.applications.map((a) => `${a.payment || 'pago'} (${money(a.amount)})`).join(' · ')}`) : null,
      rulesBox(d.rules));
    const body = h('div', { role: 'tabpanel', 'aria-live': 'polite' });
    detail.replaceChildren(head, h('div', { class: 'ap-tabs', role: 'tablist' }, tabBtns), body);
    if (tab === 'segura') drawSeguras(body, lines, r);
    else if (tab === 'dudosa') drawDudosas(body, lines);
    else if (tab === 'sin_pareja') drawSinPareja(body, lines);
    else if (tab === 'diferencia') drawDiferencias(body, lines, diff);
    else if (tab === 'hechas') drawHechas(body, lines);
    else drawOtras(body, lines);
    if (d.lines.length >= 300 || offset > 0) {
      const prev = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: offset === 0 }, '‹ Anteriores');
      const next = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: d.lines.length < 300 }, 'Siguientes ›');
      prev.addEventListener('click', () => { offset = Math.max(0, offset - 300); drawDetail(); });
      next.addEventListener('click', () => { offset += 300; drawDetail(); });
      body.append(h('div', { class: 'i18-actions' }, prev, next));
    }
  }

  function rulesBox(rules) {
    return h('details', { class: 'ap-rulesbox' }, h('summary', {}, 'Cómo decide el motor (reglas de coincidencia)'),
      h('p', { class: 'i18-sub' }, rules.resumen),
      table([{ t: 'Regla' }, { t: 'Puntos', r: 1 }], rules.reglas.map((x) => h('tr', {}, h('td', {}, x.label), h('td', { class: 'i18-r' }, x.points ? `+${x.points}` : 'No cuenta; nunca es segura')))));
  }

  const slText = (l) => (l.service_line ? `${l.service_line.folio || ''} · ${l.service_line.patient_name} · ${fmtDate(l.service_line.service_date)}` : '—');
  const fileText = (l) => h('div', {}, h('strong', {}, l.patient_name || l.nss_raw || l.auth_raw || `Fila ${l.row_no}`), h('div', { class: 'i18-sub' }, `Fila ${l.row_no} · NSS ${l.nss_raw || '—'} · Aut. ${l.auth_raw || '—'} · ${fmtDate(l.service_date)}`));

  async function act(fn, ok) {
    try { const r = await fn(); await Promise.all([loadKpis(), loadList()]); await drawDetail(); say(typeof ok === 'function' ? ok(r) : ok); return r; }
    catch (e) { fail(e); window.scrollTo({ top: 0, behavior: 'smooth' }); return null; }
  }

  function drawSeguras(body, lines, r) {
    const toApply = lines.filter((l) => num(l.paid) > 0);
    const n = toApply.length;
    const go = h('button', { class: 'i18-btn', type: 'button', id: 'ap-apply', disabled: !canApply || !n }, `Aplicar las ${n} seguras (${money(r.to_apply_amount)})`);
    go.addEventListener('click', async () => {
      if (!window.confirm(`Se registrará el pago de las coincidencias seguras (${money(r.to_apply_amount)}) y se repartirá por reclamación. ¿Continuar?`)) return;
      go.disabled = true;
      let applied = 0; let amount = 0; const skipped = [];
      try {
        for (let i = 0; i < 60; i++) {
          const x = await rpc('remittance_apply', { p_remittance: openId, p_line_ids: null, p_max_lines: CHUNK });
          applied += num(x.applied); amount += num(x.amount); skipped.push(...(x.skipped || []));
          if (!num(x.applied) || !num(x.remaining)) break;
        }
        await Promise.all([loadKpis(), loadList()]); await drawDetail();
        say(`Aplicado: ${applied} línea(s), ${money(amount)}.${skipped.length ? ` ${skipped.length} volvieron a «dudosas» porque su saldo cambió: ${skipped[0].reason}` : ''}`, skipped.length ? 'warn' : 'ok');
      } catch (e) { fail(e); go.disabled = !canApply; }
    });
    body.append(
      canApply ? h('div', { class: 'i18-actions' }, go) : note('Aplicar el pago es del Super Admin o un Administrador. Usted puede resolver las dudosas y convertir las diferencias en glosa.'),
      table([{ t: 'Fila del archivo' }, { t: 'Reclamación' }, { t: 'Pendiente', r: 1 }, { t: 'Pagado', r: 1 }, { t: 'Confianza' }],
        lines.map((l) => h('tr', {}, h('td', {}, fileText(l)), h('td', {}, slText(l)), h('td', { class: 'i18-r' }, money(l.service_line?.pending)),
          h('td', { class: 'i18-r' }, num(l.paid) === 0 ? h('span', {}, money(0), ' ', h('span', { class: 'ac-pill st-bad' }, 'Rechazada')) : money(l.paid)),
          h('td', {}, h('details', {}, h('summary', {}, `${l.score ?? '—'} %`), rulesList(l.rules)))))));
  }

  function drawDudosas(body, lines) {
    if (!lines.length) return body.append(note('No hay líneas dudosas.', 'ok'));
    body.append(h('div', { class: 'i18-list' }, lines.map((l) => h('section', { class: 'i18-card ap-dudosa' },
      h('div', { class: 'i18-bar' }, fileText(l), h('strong', {}, `Pagado ${money(l.paid)}`)),
      note(l.reason || 'Hay que confirmar la reclamación.', 'warn'),
      h('div', { class: 'ap-cands' }, (l.candidates || []).map((cd) => candidate(l, cd))),
      h('div', { class: 'i18-actions' }, ignoreBtn(l))))));
  }

  function candidate(l, cd) {
    const pick = h('button', { class: 'i18-btn', type: 'button', disabled: !canManage || cd.excess, title: cd.excess ? 'Lo pagado es mayor que lo pendiente de esta reclamación' : '' }, canApply ? 'Aplicar a esta reclamación' : 'Elegir esta reclamación');
    pick.addEventListener('click', () => act(() => rpc('remittance_resolve', { p_line: l.id, p_service_line: cd.service_line_id, p_apply: canApply }),
      canApply ? 'Pago aplicado a la reclamación elegida.' : 'Reclamación elegida: un Administrador debe aplicarla desde «Seguras».'));
    return h('div', { class: 'ap-cand' }, h('div', {}, h('strong', {}, `${cd.folio || ''} · ${cd.patient_name}`), ` · ${fmtDate(cd.service_date)} · valor ${money(cd.amount)} · pendiente ${money(cd.pending)} · `, h('span', { class: 'ac-pill st-prep' }, `${cd.score} %`)),
      h('details', {}, h('summary', {}, 'Ver reglas'), rulesList(cd.rules)), pick);
  }

  function ignoreBtn(l) {
    const b = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !canManage }, 'Ignorar esta fila');
    b.addEventListener('click', () => {
      const why = window.prompt('¿Por qué se ignora esta fila? (por ejemplo: paciente privado, no es de esta ARS)'); if (why == null) return;
      act(() => rpc('remittance_ignore', { p_line: l.id, p_reason: why }), 'Fila ignorada.');
    });
    return b;
  }

  function drawSinPareja(body, lines) {
    if (!lines.length) return body.append(note('Todas las líneas tienen pareja.', 'ok'));
    body.append(note('Estas líneas no encontraron reclamación. Quedan a la vista hasta que las resuelva: busque la reclamación a mano o ignórelas con un motivo.'),
      h('div', { class: 'i18-list' }, lines.map((l) => {
        const q = h('input', { type: 'search', 'aria-label': `Buscar reclamación para la fila ${l.row_no}`, placeholder: 'Nombre, NSS o autorización' });
        const res = h('div', { 'aria-live': 'polite' });
        const find = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !canManage }, 'Buscar reclamación');
        find.addEventListener('click', async () => {
          try {
            const r = await rpc('remittance_search_lines', { p_remittance: openId, p_text: q.value });
            res.replaceChildren(r.length ? h('div', { class: 'ap-cands' }, r.map((cd) => candidate(l, { ...cd, score: '—', excess: num(l.paid) > num(cd.pending) + 0.005, rules: [] }))) : note('No se encontró ninguna reclamación abierta con ese dato.'));
          } catch (e) { res.replaceChildren(note(e.message, 'error')); }
        });
        return h('section', { class: 'i18-card' }, h('div', { class: 'i18-bar' }, fileText(l), h('strong', {}, `Pagado ${money(l.paid)}`)), note(l.reason || 'Sin pareja.', 'error'),
          h('div', { class: 'i18-bar' }, q, find, ignoreBtn(l)), res);
      })));
  }

  function drawDiferencias(body, lines, diff) {
    const all = h('button', { class: 'i18-btn', type: 'button', id: 'ap-glosa-all', disabled: !canManage || !diff.lines }, `Convertir todas en glosa (${diff.lines} · ${money(diff.amount)})`);
    all.addEventListener('click', () => {
      if (!window.confirm(`Se creará la glosa por ${money(diff.amount)} con la causa que dijo la ARS. ¿Continuar?`)) return;
      act(() => rpc('remittance_to_glosa', { p_remittance: openId, p_line_ids: null }), (x) => `Glosa creada: ${x.lines} línea(s), ${money(x.amount)}.${(x.skipped || []).length ? ` ${x.skipped.length} no se pudieron convertir: ${x.skipped[0].reason}` : ''}`);
    });
    body.append(note('Diferencias: lo que la ARS pagó de menos y lo que rechazó. Con un clic se convierten en glosa de la radicación, con la referencia de esta relación.'),
      canManage ? h('div', { class: 'i18-actions' }, all) : null,
      table([{ t: 'Fila del archivo' }, { t: 'Reclamación' }, { t: 'Pagado', r: 1 }, { t: 'Diferencia', r: 1 }, { t: 'Causa que dijo la ARS' }, { t: '' }],
        lines.map((l) => {
          const b = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !canManage }, 'Convertir en glosa');
          b.addEventListener('click', () => act(() => rpc('remittance_to_glosa', { p_remittance: openId, p_line_ids: [l.id] }), (x) => `Glosa creada por ${money(x.amount)}.`));
          return h('tr', {}, h('td', {}, fileText(l)), h('td', {}, slText(l)), h('td', { class: 'i18-r' }, money(l.applied_amount || l.paid)), h('td', { class: 'i18-r' }, money(l.difference)), h('td', {}, l.ars_reason || (num(l.paid) === 0 ? 'Rechazada' : 'Pago menor')), h('td', {}, b));
        })));
  }

  function drawHechas(body, lines) {
    body.append(table([{ t: 'Fila del archivo' }, { t: 'Reclamación' }, { t: 'Estado' }, { t: 'Aplicado', r: 1 }, { t: 'Cómo' }, { t: 'Glosa', r: 1 }],
      lines.map((l) => h('tr', {}, h('td', {}, fileText(l)), h('td', {}, slText(l)), h('td', {}, pill(l.state)), h('td', { class: 'i18-r' }, money(l.applied_amount)),
        h('td', {}, l.applied_how === 'automatica' ? 'Automática' : l.applied_how === 'manual' ? 'Resuelta a mano' : '—'), h('td', { class: 'i18-r' }, l.glosa_amount ? money(l.glosa_amount) : '—')))));
  }

  function drawOtras(body, lines) {
    body.append(table([{ t: 'Fila del archivo' }, { t: 'Pagado', r: 1 }, { t: 'Motivo' }, { t: '' }],
      lines.map((l) => {
        const b = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !canManage }, l.state === 'duplicado' ? 'No es duplicado' : 'Reabrir');
        b.addEventListener('click', () => {
          let why = null;
          if (l.state === 'duplicado') { why = window.prompt('¿Por qué no es un duplicado? (por ejemplo: segundo pago parcial real de la misma autorización)'); if (why == null) return; }
          act(() => rpc('remittance_reopen', { p_line: l.id, p_reason: why }), 'Línea reabierta: el motor la volvió a revisar.');
        });
        return h('tr', {}, h('td', {}, fileText(l)), h('td', { class: 'i18-r' }, money(l.paid)), h('td', {}, l.state === 'duplicado' ? l.reason : (l.note || '—')), h('td', {}, b));
      })));
  }

  await loadAll();
}
export default render;
