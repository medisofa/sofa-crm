/** Historical ARS operations: audit baseline, with no new claims, deposits or automatic SOFA fees. */
import { rpc, h, money, fmtDate, note, clientOptions, clientName, downloadCsv, todayIso } from '../services/iter18.js';
import { readTable, excelDate, normHead } from '../utils/xlsx-lite.js';

export const OPENING_ROLES = ['super_admin', 'admin', 'billing', 'auditor', 'glosas', 'client'];
const PAYMENT_STATUS = { sin_datos_pago: 'Pago no informado', exceso: 'Exceso / crédito por revisar', pagada_total: 'Pagada total', cerrada_por_ajustes: 'Cerrada por ajustes', pago_parcial: 'Pago parcial', sin_pago: 'Sin pago informado (0)' };
const AUDIT_STATUS = { pendiente: 'Pendiente de auditoría', conforme: 'Saldo cotejado', observado: 'Con hallazgos', ya_en_sofa: 'Ya registrada en SOFA' };
const FIELDS = [
  ['tipo', 'Tipo', ['tipo', 'tipo fila', 'tipo registro']], ['radicacion', 'Radicación', ['radicacion', 'folio radicacion', 'lote', 'factura', 'numero factura', 'ncf']],
  ['reclamacion', 'Reclamación', ['reclamacion', 'folio reclamacion', 'referencia reclamacion', 'id reclamacion']],
  ['fecha_radicacion', 'Fecha radicación', ['fecha radicacion', 'fecha de radicacion', 'fecha factura']],
  ['fecha_servicio', 'Fecha servicio', ['fecha servicio', 'fecha de servicio', 'fecha atencion']],
  ['servicio', 'Servicio / Descripción', ['servicio descripcion', 'servicio', 'descripcion', 'procedimiento', 'codigo servicio']],
  ['simon', 'SIMON', ['simon', 'codigo simon']], ['cups', 'CUPS', ['cups', 'codigo cups']],
  ['nss', 'NSS', ['nss', 'afiliado', 'numero afiliado', 'numero de afiliado', 'no afiliado']], ['autorizacion', 'Autorización', ['autorizacion', 'numero autorizacion', 'numero de autorizacion', 'no autorizacion', 'aut']],
  ['facturado', 'Facturado', ['facturado', 'monto facturado', 'reclamado', 'total facturado']],
  ['pagado', 'Pagado', ['pagado', 'monto pagado', 'pagado acumulado', 'total pagado']],
  ['retencion', 'Retención', ['retencion', 'retenciones', 'isr']], ['glosa_aceptada', 'Glosa aceptada', ['glosa aceptada', 'glosa aceptada monto']],
  ['referencia_pago', 'Referencia pago', ['referencia pago', 'referencia', 'transferencia', 'comprobante pago']],
  ['fecha_pago', 'Fecha pago', ['fecha pago', 'fecha de pago', 'fecha deposito']],
  ['codigo_prestador', 'Código prestador', ['codigo prestador', 'codigo medico']]
];
const table = (labels, values) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table oh-table' },
  h('thead', {}, h('tr', {}, labels.map((label) => h('th', {}, label)))),
  h('tbody', {}, values.map((row) => h('tr', {}, row.map((cell, i) => h('td', { 'data-l': labels[i] }, cell ?? '—')))))));
const types = (value) => ({ radicacion: 'resumen', total: 'resumen', detalle: 'reclamacion', abono: 'pago' }[normHead(value)] || normHead(value));
const safeCell = (v) => /^\s*[=+@-]/.test(String(v ?? '')) ? "'" + v : v;
const csv = (name, rows) => downloadCsv(name, rows.map((row) => row.map(safeCell)));
const location = (row, index) => `${row._file || 'Archivo'} · fila ${row._line || index + 2}`;

export async function mountOpeningHistoryPicker(root, ctx = {}) {
  root.replaceChildren();
  if (!OPENING_ROLES.includes(ctx.role)) return root.append(note('La cartera anterior contiene datos financieros de acceso restringido.'));
  if (ctx.role === 'client') return mountOpeningHistory(root, { orgId: ctx.membership?.organization_id, role: ctx.role });
  try {
    const clients = await clientOptions();
    if (!clients.length) return root.append(note('No hay clientes accesibles.'));
    const selector = h('select', { 'aria-label': 'Cliente de la cartera anterior' }, clients.map((c) => h('option', { value: c.id }, clientName(c))));
    const pane = h('div');
    const load = () => { const fresh = h('div'); pane.replaceChildren(fresh); mountOpeningHistory(fresh, { orgId: selector.value, role: ctx.role }); };
    root.append(h('div', { class: 'i18-bar' }, h('label', {}, 'Cliente', selector)), pane);
    selector.addEventListener('change', load); load();
  } catch (e) { root.append(note(e.message, 'error')); }
}

export async function mountOpeningHistory(root, { orgId, role, onCommitted = () => {} } = {}) {
  root.replaceChildren();
  if (!orgId || !OPENING_ROLES.includes(role)) return root.append(note('Seleccione un cliente con acceso a su cartera anterior.'));
  const message = h('div', { 'aria-live': 'polite' });
  const upload = h('div'); const board = h('div'); const detail = h('div');
  root.append(h('section', { class: 'i18-wrap oh-wrap' }, h('h3', {}, 'Operación previa: reclamaciones y pagos de ARS'),
    h('p', {}, 'Cartera anterior al inicio de SOFA, con su código de prestador ya otorgado. Los antecedentes se registran como saldos de apertura para auditoría, con pagos parciales o totales y fechas originales.'),
    note('Esta carga no crea reclamaciones nuevas, no vuelve a radicar lotes ni registra depósitos u honorarios SOFA. Los cobros posteriores se documentan aquí tras auditar el saldo; sus honorarios deben revisarse conforme al contrato.'), message, upload, board, detail));
  let context;
  try { context = await rpc('opening_history_context', { p_org: orgId }); }
  catch (e) { message.replaceChildren(note(e.message, 'error')); return; }
  let offset = 0; const limit = 100; let detailGeneration = 0;
  const status = h('select', { 'aria-label': 'Estado de auditoría histórica' }, h('option', { value: '' }, 'Toda la cartera anterior'),
    Object.entries(AUDIT_STATUS).map(([key, label]) => h('option', { value: key }, label)));
  const filterBar = h('div', { class: 'i18-bar' }, h('label', {}, 'Auditoría', status));
  board.before(filterBar); status.addEventListener('change', () => { offset = 0; loadBoard(); });
  if (context.can_prepare) drawUpload();
  await loadBoard();

  async function loadBoard() {
    try {
      const data = await rpc('opening_history_board', { p_org: orgId, p_offset: offset, p_limit: limit, p_status: status.value || null });
      const s = data.summary;
      const prev = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: offset === 0 }, 'Anteriores');
      const next = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: offset + limit >= data.count }, 'Siguientes');
      prev.addEventListener('click', () => { offset = Math.max(0, offset - limit); loadBoard(); });
      next.addEventListener('click', () => { offset += limit; loadBoard(); });
      board.replaceChildren(h('div', { class: 'i18-kpis' },
        ...[['Radicaciones anteriores', s.radicaciones], ['Facturado informado', money(s.facturado)], ['Pagado al corte', money(s.pagado_inicial)],
          ['Cobros posteriores documentados', money(s.recuperado)], ['Saldo cotejado para seguimiento', money(s.saldo_confirmado)], ['Pendientes de auditoría', s.pendientes_auditoria]]
          .map(([label, value]) => h('div', { class: 'i18-kpi' }, h('div', { class: 'i18-kpi-v' }, String(value)), h('div', { class: 'i18-kpi-l' }, label)))),
        h('p', { class: 'i18-sub' }, `${s.sin_desglose} sin desglose completo · ${s.sin_datos_pago} sin acumulado pagado · ${s.posibles_duplicados} con posibles coincidencias en SOFA. Las cifras de apertura se muestran separadas de la operación nueva; «ya registrada en SOFA» se excluye de sus totales.`),
        data.items.length ? table(['Radicación original', 'Médico / ARS', 'Facturado', 'Pagado / Retención / Glosa aceptada', 'Saldo actual', 'Estado de pago', 'Auditoría', 'Detalle', ''], data.items.map((i) => {
          const open = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Abrir auditoría'); open.addEventListener('click', () => openItem(i.id));
          return [i.external_ref, `${i.provider} · ${i.ars}`, money(i.billed), `${money(i.paid)} / ${money(i.retained)} / ${money(i.accepted_glosa)}`, money(i.balance), PAYMENT_STATUS[i.payment_status], AUDIT_STATUS[i.audit_status], `${i.claims_count} reclamaciones · ${i.detail_level}`, open];
        })) : note('No hay antecedentes cargados con este filtro.'), h('div', { class: 'i18-actions' }, prev, `${Math.min(offset + 1, data.count)}–${Math.min(offset + limit, data.count)} de ${data.count}`, next));
    } catch (e) { board.replaceChildren(note(e.message, 'error')); }
  }

  function drawUpload() {
    const provider = h('select', { 'aria-label': 'Médico de la carga histórica' }, context.providers.map((p) => h('option', { value: p.id }, p.name)));
    const ars = h('select', { 'aria-label': 'ARS de la carga histórica' }, h('option', { value: '' }, 'Elija la ARS'), context.ars.map((a) => h('option', { value: a.id }, a.name)));
    const code = h('input', { maxlength: '120', 'aria-label': 'Código de prestador existente', placeholder: 'Código ya otorgado por esta ARS' });
    const start = h('input', { type: 'date', value: context.start || '', max: todayIso(), 'aria-label': 'Inicio de gestión SOFA' });
    const asof = h('input', { type: 'date', value: todayIso(), max: todayIso(), 'aria-label': 'Corte de los saldos iniciales' });
    const file = h('input', { type: 'file', accept: '.xlsx,.csv,.txt', multiple: true, 'aria-label': 'Archivos de cartera anterior' });
    const selected = h('p', { class: 'i18-sub' });
    const review = h('button', { class: 'i18-btn', type: 'button' }, 'Revisar cartera anterior');
    const template = h('button', { class: 'i18-link', type: 'button' }, 'Descargar plantilla de apertura');
    const out = h('div', { 'aria-live': 'polite' });
    let rows = null, rep = null, authorization = null, validated = false, busy = false;
    let save = null; let authorizationButton = null; const locks = new Map();
    const feedback = h('p', { role: 'status' });
    const setBusy = (value) => {
      if (busy === value) return; busy = value;
      if (value) upload.querySelectorAll('button,input,select,textarea').forEach((el) => { locks.set(el, el.disabled); el.disabled = true; });
      else { locks.forEach((disabled, el) => { if (el.isConnected) el.disabled = disabled; }); locks.clear(); }
    };
    const params = () => ({ p_org: orgId, p_provider: provider.value, p_ars: ars.value, p_start: start.value || null, p_asof: asof.value || null, p_code: code.value.trim(), p_rows: rows });
    const dirty = () => { authorization = null; validated = false; if (save) save.disabled = true; if (authorizationButton) authorizationButton.disabled = true;
      feedback.textContent = 'Hay cambios pendientes: vuelva a revisar y autorizar la carga antes de guardarla.'; };
    const reset = () => { rows = null; rep = null; dirty(); out.replaceChildren(note('La selección cambió. Revise los archivos con los datos actuales.')); };
    const fillCode = () => { const found = context.codes.find((c) => c.provider === provider.value && c.ars === ars.value); code.value = found?.code || ''; reset(); };
    provider.addEventListener('change', fillCode); ars.addEventListener('change', fillCode);
    [code, start, asof].forEach((el) => el.addEventListener('input', reset));
    file.addEventListener('change', () => { selected.textContent = [...file.files].map((f) => f.name).join(' · '); reset(); });
    function exportRows(name = 'cartera_anterior_corregida.csv') { if (rows) csv(name, [FIELDS.map((f) => f[1]), ...rows.map((r) => FIELDS.map(([key]) => r[key] || ''))]); }
    template.addEventListener('click', () => {
      const base = new Date((start.value || todayIso()) + 'T12:00:00Z'); const daysBefore = (n) => { const d = new Date(base); d.setUTCDate(d.getUTCDate() - n); return d.toISOString().slice(0, 10).split('-').reverse().join('/'); };
      const line = (r) => FIELDS.map(([key]) => r[key] || '');
      csv('plantilla_apertura_ars.csv', [FIELDS.map((f) => f[1]),
        line({ tipo: 'resumen', radicacion: 'RAD-ANT-001', fecha_radicacion: daysBefore(60), facturado: '1000.00', pagado: '500.00', retencion: '0', glosa_aceptada: '0' }),
        line({ tipo: 'reclamacion', radicacion: 'RAD-ANT-001', reclamacion: 'REC-001', fecha_servicio: daysBefore(70), servicio: 'Descripción del servicio', facturado: '1000.00', pagado: '500.00', retencion: '0', glosa_aceptada: '0' }),
        line({ tipo: 'pago', radicacion: 'RAD-ANT-001', reclamacion: 'REC-001', pagado: '500.00', referencia_pago: 'TRANSFERENCIA-001', fecha_pago: daysBefore(30) })]);
    });
    review.addEventListener('click', async () => {
      if (busy) return; dirty(); out.replaceChildren(); setBusy(true);
      try {
        const nextRows = []; const failures = [];
        for (const f of [...file.files]) {
          try {
            const t = await readTable(f); if (t.length < 2) throw Error('No hay filas debajo de los encabezados.');
            const headers = t[0].map(normHead); const mapping = Object.fromEntries(FIELDS.map(([key, , aliases]) => [key, headers.findIndex((v) => aliases.includes(v))]));
            if (mapping.radicacion < 0 && mapping.tipo < 0) throw Error('Falta Radicación o Tipo. Use la plantilla de apertura.');
            for (let i = 1; i < t.length; i++) {
              const r = Object.fromEntries(FIELDS.map(([key]) => [key, mapping[key] >= 0 ? String(t[i][mapping[key]] ?? '') : '']));
              if (!FIELDS.some(([key]) => r[key])) continue;
              r.tipo = types(r.tipo || (r.facturado ? ((r.reclamacion || (r.nss && r.autorizacion && r.fecha_servicio)) ? 'reclamacion' : 'resumen') : (r.referencia_pago ? 'pago' : 'codigo')));
              for (const key of ['fecha_radicacion', 'fecha_servicio', 'fecha_pago']) r[key] = excelDate(r[key]);
              r._file = f.name; r._line = t[i].sourceRow || i + 1; Object.defineProperty(r, '_original', { value: { ...r } }); nextRows.push(r);
            }
          } catch (e) { failures.push(`${f.name}: ${e.message}`); }
        }
        if (failures.length) throw Error(failures.join('\n'));
        if (!nextRows.length || nextRows.length > 5000) throw Error('Seleccione entre 1 y 5,000 filas de antecedentes. No se cargará un lote parcial.');
        if (!code.value.trim()) { const codes = [...new Set(nextRows.map((r) => r.codigo_prestador.trim()).filter(Boolean))]; if (codes.length === 1) code.value = codes[0]; }
        rows = nextRows; rep = await rpc('opening_history_preview', params()); drawPreview();
      } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { setBusy(false); }
    });
    async function validateCorrections() {
      if (busy || !rows) return;
      dirty(); setBusy(true);
      try { rep = await rpc('opening_history_preview', params()); drawPreview(); }
      catch (e) { out.append(note(e.message, 'error')); } finally { setBusy(false); }
    }
    function drawPreview(errorOffset = 0) {
      const recheck = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Volver a revisar correcciones'); recheck.addEventListener('click', validateCorrections);
      const copy = h('button', { class: 'i18-link', type: 'button' }, 'Descargar copia corregida'); copy.addEventListener('click', () => exportRows());
      feedback.textContent = rep.errors.length ? 'Corrija las filas señaladas; se conserva el valor original junto al editor.' : 'Revise los saldos y las alertas. Administración debe autorizar antes de validar y guardar.';
      const corrections = rep.errors.slice(errorOffset, errorOffset + 50).map((error) => {
        const index = Number(error.row) - 1; const row = rows[index]; if (!row) return note(error.errors.join(' · '), 'error');
        const original = row._original || { ...row };
        return h('details', { class: 'i18-card ti-error-card', open: true }, h('summary', {}, location(row, index)),
          h('ul', { class: 'ti-problems' }, error.errors.map((msg) => h('li', {}, msg))),
          h('div', { class: 'hc-grid i18-form', style: 'max-width:none' }, FIELDS.map(([key, label]) => {
            const input = h(key === 'servicio' ? 'textarea' : 'input', { rows: key === 'servicio' ? '2' : null, value: row[key] || '', 'aria-label': `${label} · ${location(row, index)}` });
            input.addEventListener('input', () => { row[key] = key === 'tipo' ? types(input.value) : input.value;
              row._corrections ||= {}; row._corrections[key] = { from: original[key] || '', to: row[key] }; dirty(); });
            return h('label', {}, label, input, h('span', { class: 'i18-sub' }, `Original: ${original[key] || '(vacío)'}`));
          })));
      });
      const more = h('button', { class: 'i18-link', type: 'button', disabled: rep.errors.length <= errorOffset + 50 }, 'Ver más errores');
      more.addEventListener('click', () => drawPreview(errorOffset + 50));
      const previous = h('button', { class: 'i18-link', type: 'button', disabled: !errorOffset }, 'Errores anteriores');
      previous.addEventListener('click', () => drawPreview(Math.max(0, errorOffset - 50)));
      const reason = h('textarea', { rows: '2', maxlength: '1000', 'aria-label': 'Soporte de la autorización histórica', placeholder: 'Contrato, fecha de inicio y estado de cuenta utilizados para verificar esta carga.' });
      const check = h('input', { type: 'checkbox' });
      authorizationButton = h('button', { class: 'i18-btn', type: 'button', disabled: true }, 'Autorizar carga de apertura');
      const finalCheck = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: true }, 'Validar autorización antes de guardar');
      save = h('button', { class: 'i18-btn', type: 'button', disabled: true }, 'Guardar cartera anterior');
      const authReady = () => { authorization = null; validated = false; save.disabled = true; finalCheck.disabled = true;
        authorizationButton.disabled = !context.can_authorize || rep.errors.length > 0 || !check.checked || reason.value.trim().length < 10; };
      check.addEventListener('change', authReady); reason.addEventListener('input', authReady);
      authorizationButton.addEventListener('click', async () => {
        if (busy || authorizationButton.disabled || !check.checked) return; setBusy(true);
        try { authorization = await rpc('opening_history_authorize', { ...params(), p_expected: rep.hash, p_reason: reason.value.trim() });
          feedback.textContent = 'Carga autorizada. Aún no se ha registrado ningún saldo ni código. Valide la autorización para habilitar el guardado.'; finalCheck.disabled = false;
        } catch (e) { out.append(note(e.message, 'error')); } finally { setBusy(false); finalCheck.disabled = !authorization; }
      });
      finalCheck.addEventListener('click', async () => {
        if (busy || !authorization) return; setBusy(true);
        try { const latest = await rpc('opening_history_preview', params());
          if (latest.errors.length || latest.hash !== authorization.hash) { dirty(); throw Error('La carga o sus coincidencias cambió. Revise nuevamente y autorice la versión actual.'); }
          validated = true; feedback.textContent = 'Autorización y saldos validados. Puede confirmar el guardado.';
        } catch (e) { validated = false; out.append(note(e.message, 'error')); } finally { setBusy(false); save.disabled = !validated || !authorization; }
      });
      save.addEventListener('click', async () => {
        if (busy || !authorization || !validated) return; setBusy(true);
        try { const result = await rpc('opening_history_commit', { p_authorization: authorization.id });
          out.replaceChildren(note(`Carga completada: ${result.imported} radicación(es) anteriores en auditoría. El código de prestador quedó reconocido. No se generaron honorarios.`, 'ok'));
          rows = null; authorization = null; validated = false; file.value = ''; selected.textContent = ''; await loadBoard(); onCommitted();
        } catch (e) { out.append(note(e.message, 'error')); } finally { setBusy(false); }
      });
      out.replaceChildren(feedback, h('p', {}, `${rep.total} filas · ${rep.groups.length} radicación(es) · ${rep.errors.length} fila(s)/grupo(s) con error`),
        ...corrections, rep.errors.length > 50 ? h('div', { class: 'i18-actions' }, previous, more) : '',
        h('div', { class: 'i18-actions' }, recheck, copy),
        rep.groups.length ? table(['Radicación', 'Facturado', 'Pagado al corte', 'Retención', 'Glosa aceptada', 'Saldo', 'Estado', 'Alertas'], rep.groups.map((g) =>
          [g.external_ref, money(g.billed), money(g.paid), money(g.retained), money(g.accepted_glosa), money(g.balance), PAYMENT_STATUS[g.status], (g.flags || []).join(' · ') || 'Sin alertas'])) : '',
        h('fieldset', { class: 'i18-fs' }, h('legend', {}, 'Autorización y guardado'),
          context.can_authorize ? h('label', { class: 'oh-field' }, 'Soporte y motivo', reason) : note('Puede preparar la carga. Administración debe revisarla y autorizarla para guardar.'),
          context.can_authorize ? h('label', { class: 'i18-chk' }, check, ' Verifiqué el código existente, el inicio SOFA y los saldos informados; autorizo esta carga histórica para auditoría.') : '',
          h('div', { class: 'i18-actions' }, authorizationButton, finalCheck, save)));
    }
    upload.append(h('details', { class: 'i18-card oh-upload' }, h('summary', {}, 'Cargar códigos existentes, reclamaciones y pagos anteriores'),
      h('p', {}, 'Puede combinar varios Excel o CSV para el mismo médico y ARS. Use Tipo=resumen para totales, reclamacion para el detalle (referencia original o NSS + autorización + fecha + servicio/código), pago para abonos identificados o codigo si solo acredita el código. Resumen y detalle se cotejan: no se suman dos veces.'),
      h('p', {}, 'En resumen/reclamacion, Pagado es el acumulado al corte; en pago es el importe de ese abono. Use 0 si confirma que no hubo pagos; vacío significa desconocido. Retención y Glosa aceptada van separadas. Las diferencias no se convierten automáticamente en glosa.'),
      h('div', { class: 'hc-grid i18-form', style: 'max-width:none' }, h('label', {}, 'Médico', provider), h('label', {}, 'ARS', ars), h('label', {}, 'Código de prestador ya otorgado', code),
        h('label', {}, 'Inicio de gestión SOFA', start), h('label', {}, 'Corte de saldos iniciales', asof), h('label', { class: 'hc-wide' }, 'Archivos', file)), selected,
      h('div', { class: 'i18-actions' }, review, template), out));
  }

  async function openItem(id) {
    const generation = ++detailGeneration; detail.replaceChildren(note('Cargando auditoría…'));
    try {
      const data = await rpc('opening_history_item', { p_item: id });
      if (generation !== detailGeneration || !root.isConnected) return;
      const item = data.item;
      const result = h('div', { 'aria-live': 'polite' });
      const originals = item.details.rows;
      const exportDetail = h('button', { class: 'i18-link', type: 'button' }, 'Descargar detalle original');
      exportDetail.addEventListener('click', () => csv('antecedente_original.csv', [['Archivo', 'Fila', ...FIELDS.map((f) => f[1])], ...originals.map((r) => [r.source._file, r.source._line, ...FIELDS.map(([key]) => r.source._corrections?.[key]?.from ?? r.source[key] ?? '')])]));
      const content = [h('h4', {}, `Auditoría de ${item.external_ref}`),
        h('p', {}, `Radicada el ${fmtDate(item.submitted_on)} · inicio SOFA ${fmtDate(item.service_start)} · corte ${fmtDate(item.as_of)}`),
        h('p', {}, `Cifras vigentes: facturado ${money(item.billed)} · pagado al corte ${money(item.paid)} · retención ${money(item.retained)} · glosa aceptada ${money(item.accepted_glosa)} · cobros posteriores ${money(item.recovered)}`),
        item.review_note ? note(item.review_note) : '', h('ul', {}, item.flags.map((flag) => h('li', {}, flag))),
        item.details.native_candidates.length ? h('p', {}, 'Posibles coincidencias: ', ...item.details.native_candidates.map((sub) => h('a', { href: `#/radicaciones/${sub}`, style: 'margin-right:8px' }, 'Ver radicación SOFA'))) : '',
        exportDetail, table(['Origen', 'Tipo', 'Reclamación', 'Servicio', 'Facturado', 'Pagado informado', 'Fecha / referencia pago', 'Correcciones antes de autorizar'], originals.slice(0, 200).map((r) =>
          [location(r.source), r.type, r.claim || 'Total radicación', r.source.servicio || '—', money(r.billed), money(r.paid), `${fmtDate(r.paid_on)} · ${r.reference || '—'}`, Object.entries(r.source._corrections || {}).map(([key, change]) => `${key}: ${change.from || '(vacío)'} → ${change.to || '(vacío)'}`).join(' · ') || '—'])),
        originals.length > 200 ? note(`Se muestran 200 de ${originals.length} filas. Descargue el detalle para consultar todas.`) : '',
        data.recoveries.length ? table(['Cobro posterior', 'Referencia', 'Monto', 'Soporte'], data.recoveries.map((r) => [fmtDate(r.paid_on), r.reference, money(r.amount), r.note])) : '', result];
      if (context.can_review) {
        const decision = h('select', { 'aria-label': 'Resultado de auditoría histórica' }, ['conforme', 'observado', 'ya_en_sofa'].map((s) => h('option', { value: s }, AUDIT_STATUS[s])));
        const text = h('textarea', { rows: '2', maxlength: '2000', 'aria-label': 'Hallazgo o soporte de auditoría' });
        const review = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar auditoría histórica');
        review.addEventListener('click', async () => {
          review.disabled = true;
          try { await rpc('opening_history_review', { p_item: id, p_status: decision.value, p_note: text.value.trim(), p_expected_revision: item.revision }); await loadBoard(); if (generation === detailGeneration) await openItem(id); }
          catch (e) { result.replaceChildren(note(e.message, 'error')); } finally { review.disabled = false; }
        });
        content.push(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Revisar pagos y reclamos anteriores'),
          h('label', {}, 'Resultado', decision), h('label', {}, 'Soporte, hallazgo y comprobación de duplicados', text), review));
      }
      if (context.can_authorize) {
        const inputs = [['billed', 'Facturado'], ['paid', 'Pagado al corte'], ['retained', 'Retención'], ['accepted_glosa', 'Glosa aceptada']].map(([key, label]) => ({ key, label,
          input: h('input', { type: 'number', min: '0', step: '0.01', value: item[key] == null ? '' : String(item[key]), 'aria-label': `Rectificar ${label}` }) }));
        const why = h('textarea', { rows: '2', maxlength: '2000', 'aria-label': 'Soporte de rectificación de apertura' });
        const rectify = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Autorizar rectificación de saldos');
        rectify.addEventListener('click', async () => {
          if (inputs.some(({ input }) => input.value === '')) return result.replaceChildren(note('Complete todas las cifras; use 0 solo si está confirmado.', 'error'));
          rectify.disabled = true;
          try { const v = Object.fromEntries(inputs.map(({ key, input }) => [key, Number(input.value)]));
            await rpc('opening_history_rectify', { p_item: id, p_billed: v.billed, p_paid: v.paid, p_retained: v.retained, p_glosa: v.accepted_glosa, p_reason: why.value.trim(), p_expected_revision: item.revision });
            await loadBoard(); if (generation === detailGeneration) await openItem(id);
          } catch (e) { result.replaceChildren(note(e.message, 'error')); } finally { rectify.disabled = false; }
        });
        content.push(h('details', { class: 'i18-card' }, h('summary', {}, 'Rectificar saldos iniciales con soporte'),
          note('Se conservan las filas originales y se registra la rectificación. Después deberá repetirse la auditoría.'),
          h('div', { class: 'hc-grid i18-form', style: 'max-width:none' }, inputs.map(({ label, input }) => h('label', {}, label, input)), h('label', {}, 'Soporte de la corrección', why), rectify)));
        const amount = h('input', { type: 'number', min: '0.01', step: '0.01', 'aria-label': 'Monto de cobro posterior' });
        const paid = h('input', { type: 'date', value: todayIso(), max: todayIso(), 'aria-label': 'Fecha de cobro posterior' });
        const ref = h('input', { maxlength: '120', 'aria-label': 'Referencia de cobro posterior' });
        const support = h('textarea', { rows: '2', maxlength: '2000', 'aria-label': 'Soporte de cobro posterior' });
        const check = h('input', { type: 'checkbox' });
        const recover = h('button', { class: 'i18-btn', type: 'button', disabled: true }, 'Registrar cobro posterior de cartera anterior');
        check.addEventListener('change', () => { recover.disabled = !check.checked || item.audit_status !== 'conforme'; });
        recover.addEventListener('click', async () => {
          if (!check.checked || item.audit_status !== 'conforme') return; recover.disabled = true;
          try { await rpc('opening_history_recovery_add', { p_item: id, p_amount: Number(amount.value), p_reference: ref.value.trim(), p_paid_on: paid.value || null, p_note: support.value.trim() }); await loadBoard(); if (generation === detailGeneration) await openItem(id); }
          catch (e) { result.replaceChildren(note(e.message, 'error')); } finally { recover.disabled = !check.checked; }
        });
        content.push(h('details', { class: 'i18-card' }, h('summary', {}, 'Documentar un cobro recibido después del corte'),
          note('Solo sobre saldo auditado y con fecha posterior al corte. Verifique que el pago no figure en Pagos de SOFA. Este registro actualiza la cartera anterior; los honorarios se revisan por contrato.'),
          h('div', { class: 'hc-grid i18-form', style: 'max-width:none' }, h('label', {}, 'Monto', amount), h('label', {}, 'Fecha', paid), h('label', {}, 'Referencia', ref), h('label', {}, 'Soporte', support)),
          h('label', { class: 'i18-chk' }, check, ' Confirmo que este cobro no está incluido en el corte inicial ni registrado en Pagos SOFA.'), recover));
      }
      detail.replaceChildren(h('section', { class: 'i18-card oh-detail' }, ...content));
      detail.scrollIntoView?.({ block: 'nearest' });
    } catch (e) { if (generation === detailGeneration) detail.replaceChildren(note(e.message, 'error')); }
  }
}
