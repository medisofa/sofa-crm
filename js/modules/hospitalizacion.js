/** SOFA · 5.7.0 · I68a · «Hospitalización»: el médico reporta, por paciente hospitalizado, los servicios que dio,
 *  cobrados según SU tarifario, en cualquiera de los centros de su ficha. La base valida todo (centro de su ficha,
 *  precio del tarifario, reporte en firme al enviar). Ocultar un botón aquí no es un control. */
import { rpc, h, note, guarded, money, fmtDate } from '../services/iter18.js';
import { confirmDialog } from '../utils/ui.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';
import { canSee } from '../utils/permissions.js';

/** 5.35.9 · Tabla de líneas de un reporte. Un único helper DRY para las tres vistas
 *  (médico/soporte/staff). Cuando `rowAction` está presente se agrega una columna extra
 *  de acciones; si no, la tabla usa solo los 5 encabezados declarados. */
function reportLinesTable(lineas, {
  headers = ['Fecha', 'Servicio', 'Cant.', 'Precio', 'Monto', '%', 'Proy.'],
  empty = 'Sin servicios registrados.',
  rowAction = null,
} = {}) {
  const hasAction = rowAction != null;
  const ths = headers.map((t) => h('th', {}, t));
  if (hasAction) ths.push(h('th', {}, ''));
  const rows = (lineas || []).map((l) => {
    const pctClass = l.projected_pct === 50 ? 'num hosp-pct50' : 'num';
    const cells = [
      h('td', {}, fmtDate(l.service_date)),
      h('td', {}, l.servicio || l.codigo),
      h('td', { class: 'num' }, String(l.quantity)),
      h('td', { class: 'num' }, money(l.unit_amount)),
      h('td', { class: 'num' }, money(l.amount)),
      h('td', { class: pctClass }, l.projected_pct != null ? `${l.projected_pct}%` : ''),
      h('td', { class: pctClass }, l.projected_amount != null ? money(l.projected_amount) : ''),
    ];
    if (hasAction) cells.push(h('td', {}, rowAction(l) || ''));
    return h('tr', {}, ...cells);
  });
  const colspan = String(headers.length + (hasAction ? 1 : 0));
  const body = rows.length ? rows : [h('tr', {}, h('td', { colspan, class: 'hosp-mut' }, empty))];
  return h('table', { class: 'hosp-tbl' },
    h('thead', {}, h('tr', {}, ...ths)),
    h('tbody', {}, ...body));
}

/** 5.35.9 · Pie total del reporte. `extra` añade una línea gris a la derecha; `strong` usa
 *  <strong> en lugar de <b> (match con la vista de staff). */
function reportFoot(r, { strong = false, extra = null } = {}) {
  const totalEl = strong ? h('strong', {}, `Total: ${money(r.total)}`) : h('b', {}, `Total: ${money(r.total)}`);
  const children = [totalEl];
  if (r.projected_total != null && r.projected_total !== r.total) {
    const projEl = h('span', { class: 'hosp-proj-total' }, `Proyectado ARS: ${money(r.projected_total)}`);
    children.push(projEl);
  }
  if (extra) children.push(h('span', { class: 'hosp-mut' }, extra));
  return h('div', { class: 'hosp-foot' }, ...children);
}

export async function render(root, context = {}) {
  if (context.viewAs) return renderSupport(root, context);
  if (['super_admin','admin','operations','billing'].includes(context.role)) return renderStaff(root, context);
  root.replaceChildren();
  const wrap = h('div', { class: 'i18-wrap hosp-wrap' });
  root.append(wrap);
  const ctx = await guarded(wrap, () => rpc('hospital_centers_mine'));
  if (!ctx) return;
  if (!ctx.soy_medico) {
    wrap.append(h('header', { class: 'hosp-header' }, h('div', {}, h('h2', {}, 'Hospitalización'), h('p', { class: 'i18-sub' }, 'Reporta y revisa los servicios de cada hospitalización.')), canSee('centros', context.role) ? h('a', { class: 'i18-btn i18-sec', href: '#/centros' }, 'Gestionar centros') : null), note('Esta pantalla es para el médico. Tu usuario no está ligado a un médico en SOFA.', 'info'));
    return;
  }
  const centros = ctx.centros || [];
  const arsCatalog = await rpc('ars_catalog', { p_include_inactive: false }).catch(() => []);
  if (!wrap.isConnected) return;
  const status = h('div', { 'aria-live': 'polite' });
  const listBox = h('div', { 'aria-live': 'polite' });
  const detailBox = h('div', { 'aria-live': 'polite' });
  wrap.append(h('h2', {}, 'Hospitalización'),
    h('p', { class: 'i18-sub' }, 'Reporta los servicios que diste a cada paciente hospitalizado. El precio sale de tu tarifario; puedes ajustarlo. Al enviar, el reporte queda en firme y se avisa al equipo de SoFa para su revisión.'),
    status, newReportForm(), h('div', { class: 'hosp-overviewgrid' }, h('section', {}, h('h3', {}, 'Mis reportes'), listBox), detailBox));

  async function loadList() {
    const data = await guarded(listBox, () => rpc('hospital_report_list'));
    if (!data) return;
    if (!data.length) { listBox.replaceChildren(note('Aún no tienes reportes.', 'info')); return; }
    listBox.replaceChildren(h('div', { class: 'hosp-list' }, data.map((r) =>
      h('button', { class: 'hosp-row', type: 'button', onclick: () => openReport(r.id) },
        h('span', {}, `${r.patient_name} · ${r.centro}`),
        h('span', { class: 'hosp-mut' }, `${r.status} · ${money(r.total)}`)))));
  }

  function caseForm(r = null) {
    const box = h('details', { class: 'hosp-new', open: !!r });
    const centerSel = h('select', { 'aria-label': 'Centro', required: true }, centros.map((c) => h('option', { value: c.center_id }, c.nombre + (c.principal ? ' (principal)' : ''))));
    if (r) centerSel.value = r.center_id || '';
    const pac = h('input', { type: 'text', 'aria-label': 'Nombre del paciente', placeholder: 'Nombre del paciente', maxlength: '160', value: r?.patient_name || '', required: true });
    const doc = h('input', { type: 'text', 'aria-label': 'Cédula del paciente', placeholder: 'Cédula (opcional)', maxlength: '40', value: r?.patient_doc || '' });
    const phone = h('input', { type: 'tel', 'aria-label': 'Teléfono del paciente', placeholder: 'Teléfono (opcional)', maxlength: '20', value: r?.patient_phone || '' });
    const ars = h('select', { 'aria-label': 'ARS del paciente' }, h('option', { value: '' }, 'Privado / sin ARS'), (arsCatalog || []).map((a) => h('option', { value: a.id }, a.name)));
    if (r?.ars_id && !(arsCatalog || []).some((a) => a.id === r.ars_id)) ars.append(h('option', { value: r.ars_id }, r.ars || 'ARS registrada'));
    if (r) ars.value = r.ars_id || '';
    const adm = h('input', { type: 'date', 'aria-label': 'Fecha de ingreso', value: r?.admission_date || '' });
    const discharge = h('input', { type: 'date', 'aria-label': 'Fecha de alta', value: r?.discharge_date || '' });
    const notes = h('textarea', { 'aria-label': 'Observaciones del reporte', placeholder: 'Observaciones administrativas', maxlength: '1000', rows: '2' }, r?.notes || '');
    const out = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, r ? 'Guardar datos del reporte' : 'Crear reporte');
    save.addEventListener('click', async () => {
      if (!centros.length) { out.replaceChildren(note('No tienes centros en tu ficha. Solicita que agreguen el centro.', 'warn')); return; }
      if (!pac.value.trim()) { out.replaceChildren(note('Escribe el nombre del paciente.', 'warn')); return; }
      if (adm.value && discharge.value && discharge.value < adm.value) { out.replaceChildren(note('El alta no puede ser anterior al ingreso.', 'warn')); return; }
      save.disabled = true;
      try {
        const report = await rpc('hospital_report_save_contact', { p_center: centerSel.value, p_patient_name: pac.value.trim(), p_patient_doc: doc.value.trim() || null, p_phone: phone.value.trim() || null,
          p_ars: ars.value || null, p_admission: adm.value || null, p_discharge: discharge.value || null, p_notes: notes.value.trim() || null, p_id: r?.id || null });
        out.replaceChildren(); box.open = false; await loadList(); drawReport(report);
        if (!r) { pac.value = ''; doc.value = ''; phone.value = ''; notes.value = ''; adm.value = ''; discharge.value = ''; ars.value = ''; }
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
      finally { save.disabled = false; }
    });
    const field = (label, input) => h('label', {}, label, input);
    box.append(h('summary', {}, r ? 'Datos del paciente y la hospitalización' : 'Nuevo reporte'), h('div', { class: 'hosp-form hosp-case-form' },
      field('Centro', centerSel), field('Paciente', pac), field('Cédula (opcional)', doc), field('Teléfono (opcional)', phone), field('ARS', ars), field('Ingreso', adm), field('Alta', discharge), field('Observaciones', notes), save, out));
    return box;
  }
  function newReportForm() { return caseForm(); }

  async function openReport(id) {
    const r = await guarded(detailBox, () => rpc('hospital_report_get', { p_report: id }));
    if (!r) return;
    drawReport(r);
  }

  async function drawReport(r) {
    const out = h('div', { 'aria-live': 'polite' });
    const table = reportLinesTable(r.lineas, {
      empty: 'Sin servicios todavía.',
      rowAction: r.puede_editar ? (l) => delBtn(l.id) : null,
    });
    const foot = reportFoot(r, { extra: `  ${r.patient_name} · ${r.centro} · ${r.status}` });
    detailBox.replaceChildren(h('div', { class: 'hosp-detail' },
      h('h3', {}, `Reporte · ${r.patient_name}`), h('p', { class: 'i18-sub' }, `Ingreso ${fmtDate(r.admission_date)} · Alta ${fmtDate(r.discharge_date)} · ${r.ars || 'Privado / sin ARS'}${r.patient_phone ? ' · Tel. ' + r.patient_phone : ''}`),
      r.puede_editar ? caseForm(r) : null, table, foot,
      r.puede_editar ? addLineForm(r) : note('Reporte enviado: ya no se edita.', 'info'),
      r.puede_editar ? sendBtn(r) : printBtn(r), out,
      bitacoraBlock(r.id)));

    function delBtn(lineId) { const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Quitar'); b.addEventListener('click', async () => { try { const rr = await rpc('hospital_report_line_remove', { p_line: lineId }); drawReport(rr); await loadList(); } catch (e) { out.replaceChildren(note(e.message, 'error')); } }); return b; }
    function sendBtn(rep) { const b = h('button', { class: 'i18-btn', type: 'button' }, 'Enviar y avisar a SoFa'); b.addEventListener('click', async () => { if (!rep.admission_date) { out.replaceChildren(note('Indica la fecha de ingreso antes de enviar el reporte.', 'warn')); return; } if (!await confirmDialog('Enviar reporte', '¿Enviar el reporte y avisar al equipo de SoFa? Después no se edita.', 'Enviar', true)) return; try { const rr = await rpc('hospital_report_submit', { p_report: rep.id }); await loadList(); drawReport(rr); } catch (e) { out.replaceChildren(note(e.message, 'error')); } }); return b; }
    function printBtn(rep) {
      const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Imprimir');
      b.addEventListener('click', () => {
        const w = openPrint();
        if (!w) return;
        const fecha = new Date().toLocaleDateString('es-DO', { year: 'numeric', month: 'long', day: 'numeric' });
        const printSections = [
          { table: { head: ['Fecha', 'Servicio', 'Cant.', 'Precio', 'Monto', '%', 'Proy.'],
              rows: (rep.lineas || []).map((l) => [fmtDate(l.service_date), l.servicio || l.codigo, String(l.quantity), money(l.unit_amount), money(l.amount), l.projected_pct != null ? `${l.projected_pct}%` : '', l.projected_amount != null ? money(l.projected_amount) : '']),
              right: [2, 3, 4, 5, 6] } },
          { big: `Total: ${money(rep.total)}` },
        ];
        if (rep.projected_total != null && rep.projected_total !== rep.total) {
          printSections.push({ big: `Proyectado ARS: ${money(rep.projected_total)}` });
        }
        fillPrint(w, `Reporte de hospitalización · ${rep.patient_name}`, `${rep.centro} · Generado el ${fecha}`, printSections);
      });
      return b;
    }
  }

  function addLineForm(r) {
    const out = h('div', { 'aria-live': 'polite' });
    const box = h('details', { class: 'hosp-addline', open: true });
    const servSel = h('select', { 'aria-label': 'Servicio del tarifario' }, [h('option', { value: '' }, 'Elige un servicio de tu tarifario…')]);
    const fecha = h('input', { type: 'date', 'aria-label': 'Fecha del servicio', value: (r.admission_date || '') });
    const cant = h('input', { type: 'number', min: '0.01', step: '1', value: '1', 'aria-label': 'Cantidad' });
    const precio = h('input', { type: 'number', min: '0', step: '0.01', placeholder: 'Precio (auto del tarifario)', 'aria-label': 'Precio' });
    const add = h('button', { class: 'i18-btn', type: 'button' }, 'Agregar servicio');
    let tariffSequence = 0;
    async function loadTariff() {
      const my = ++tariffSequence; servSel.disabled = true; precio.value = '';
      try { const tar = await rpc('hospital_my_tariff', { p_date: fecha.value || null });
        if (my !== tariffSequence || !box.isConnected) return;
        servSel.replaceChildren(h('option', { value: '' }, 'Elige un servicio de tu tarifario…'), ...(tar || []).map((t) => h('option', { value: t.procedure_id, 'data-amount': t.amount }, `${t.codigo} · ${t.servicio} · ${money(t.amount)}`)));
      } catch(e) { if (my === tariffSequence) out.replaceChildren(note(e.message, 'error')); }
      finally { if (my === tariffSequence) servSel.disabled = false; }
    }
    fecha.addEventListener('change', loadTariff);
    queueMicrotask(loadTariff);
    servSel.addEventListener('change', () => { const o = servSel.selectedOptions[0]; if (o && o.dataset.amount) precio.value = o.dataset.amount; });
    add.addEventListener('click', async () => {
      if (!servSel.value) { out.replaceChildren(note('Elige un servicio.', 'warn')); return; }
      if (!fecha.value) { out.replaceChildren(note('Indica la fecha del servicio.', 'warn')); return; }
      try {
        const rr = await rpc('hospital_report_line_add', { p_report: r.id, p_procedure: servSel.value, p_service_date: fecha.value, p_quantity: Number(cant.value || 1), p_unit_amount: precio.value ? Number(precio.value) : null });
        out.replaceChildren(); drawReport(rr); await loadList();
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
    });
    box.append(h('summary', {}, 'Agregar un servicio'), h('div', { class: 'hosp-form' }, servSel, fecha, cant, precio, add, out));
    return box;
  }

  await loadList();
  if (context.arg) await openReport(context.arg);
}


/** Soporte conserva la identidad administrativa: usar exclusivamente el lector
 * acotado al consultorio activo, nunca las funciones «mine» del usuario real. */
async function renderSupport(root, context) {
  const wrap = h('div', { class: 'i18-wrap hosp-wrap hosp-support' });
  root.replaceChildren(wrap);
  wrap.append(h('h2', {}, 'Hospitalización'), note('Modo soporte · consulta de reportes, solo lectura.', 'info'));
  const organizationId = context.viewAs?.orgId || context.membership?.organization_id;
  if (context.role !== 'client' || context.viewAs?.targetName) {
    wrap.append(note('Esta pantalla no muestra reportes individuales en modo soporte. Abre el soporte general del consultorio.', 'info'));
    return;
  }
  if (!organizationId) {
    wrap.append(note('No se encontró el consultorio del modo soporte. Sal y vuelve a abrirlo.', 'info'));
    return;
  }
  const initial = h('div', { 'aria-live': 'polite' }); wrap.append(initial);
  const [first, arsCatalog] = await Promise.all([
    guarded(initial, () => rpc('hospital_support_context', { p_org: organizationId })),
    rpc('ars_catalog', { p_include_inactive: false }).catch(() => [])
  ]);
  if (!first || !wrap.isConnected) return;
  initial.replaceChildren();
  const providers = first.providers || [];
  if (!providers.length) { initial.append(note('Este consultorio no tiene médicos activos registrados.', 'info')); return; }
  let provider = first.provider_id || '';
  let sequence = 0;
  let reportIds = new Set();
  const select = h('select', { id: 'hosp-support-provider', 'aria-label': 'Médico del consultorio' },
    h('option', { value: '' }, 'Selecciona un médico…'), providers.map((p) => h('option', { value: p.id }, p.full_name)));
  select.value = provider;
  const centers = h('p', { class: 'i18-sub hosp-support-centers' });
  // 5.31.1 · Vista previa del formulario que ve el médico. Fieldset disabled bloquea entrada,
  // y Task 1 ya intercepta submit globalmente en modo soporte. El soporte entiende qué pediría
  // el médico sin crear ni editar nada.
  const formPreview = h('div', { 'aria-live': 'polite' });
  const list = h('div', { 'aria-live': 'polite' });
  const detail = h('div', { 'aria-live': 'polite' });
  initial.append(providers.length > 1 ? h('label', { for: 'hosp-support-provider' }, 'Médico del consultorio', select)
    : h('p', {}, h('strong', {}, providers[0].full_name)), centers, formPreview, h('h3', {}, 'Reportes del médico'), list, detail);
  select.addEventListener('change', async () => {
    const my = ++sequence;
    provider = select.value; reportIds = new Set(); detail.replaceChildren(); centers.textContent = '';
    if (!provider) { list.replaceChildren(note('Selecciona un médico para consultar sus reportes.', 'info')); return; }
    list.replaceChildren(note('Consultando reportes…', 'info'));
    try {
      const data = await rpc('hospital_support_context', { p_org: organizationId, p_provider: provider });
      if (my !== sequence || !wrap.isConnected) return;
      drawList(data);
    } catch (e) { if (my === sequence && wrap.isConnected) list.replaceChildren(note(e.message, 'error')); }
  });
  function drawList(data) {
    const rows = data.reportes || [];
    reportIds = new Set(rows.map((r) => r.id));
    const centros = data.centros || [];
    centers.textContent = centros.length ? 'Centros visibles: ' + centros.map((c) => c.nombre).join(' · ') : 'Sin centros visibles en este consultorio.';
    // 5.31.1 · Dibuja la vista previa del formulario de «Nuevo reporte» que ve el médico.
    // Todo dentro de un fieldset disabled: no se puede escribir ni enviar. Task 1 difumina PII.
    formPreview.replaceChildren(provider ? disabledNewReportForm(centros, arsCatalog) : document.createDocumentFragment());
    if (!provider) { list.replaceChildren(note('Selecciona un médico para consultar sus reportes.', 'info')); return; }
    if (!rows.length) { list.replaceChildren(note('Este médico aún no tiene reportes visibles en el consultorio.', 'info')); return; }
    list.replaceChildren(h('p', { class: 'i18-sub' }, `Mostrando ${rows.length} de ${data.report_count ?? rows.length} reporte(s).`),
      h('div', { class: 'hosp-list' }, ...rows.map((r) => h('button', { class: 'hosp-row', type: 'button', onclick: () => openReport(r.id) },
        h('span', {}, `${r.patient_name} · ${r.centro}`), h('span', { class: 'hosp-mut' }, `${r.status} · ${money(r.total)}`)))));
  }
  async function openReport(id) {
    if (!provider || !reportIds.has(id)) return;
    const my = ++sequence; const selectedProvider = provider;
    detail.replaceChildren(note('Consultando detalle…', 'info'));
    try {
      const data = await rpc('hospital_support_context', { p_org: organizationId, p_provider: selectedProvider, p_report: id });
      if (my !== sequence || selectedProvider !== provider || !wrap.isConnected) return;
      const r = data.report;
      if (!r || r.id !== id || r.provider_id !== selectedProvider) throw new Error('Reporte no disponible para el médico seleccionado.');
      detail.replaceChildren(h('section', { class: 'hosp-detail hosp-support-detail' },
        h('h3', {}, `Reporte · ${r.patient_name}`),
        h('p', { class: 'i18-sub' }, `${r.centro} · ${r.status} · Ingreso ${fmtDate(r.admission_date)}`),
        h('div', { class: 'i18-table-wrap' }, reportLinesTable(r.lineas)),
        reportFoot(r),
        note('Solo lectura en modo soporte.', 'info'),
        bitacoraBlock(r.id)));
    } catch (e) { if (my === sequence && wrap.isConnected) detail.replaceChildren(note(e.message, 'error')); }
  }
  drawList(first);
}

/** 5.31.1 · Vista previa del formulario «Nuevo reporte» que ve el médico, para que el soporte
 *  entienda la pantalla sin poder crear ni editar nada. Todo dentro de un fieldset disabled;
 *  Task 1 también intercepta submit globalmente en modo soporte. */
function disabledNewReportForm(centros, arsCatalog) {
  const field = (label, input) => h('label', {}, label, input);
  const centerSel = h('select', { 'aria-label': 'Centro' },
    centros.length ? centros.map((c) => h('option', { value: c.center_id }, c.nombre + (c.principal ? ' (principal)' : '')))
                   : [h('option', {}, 'Sin centros en la ficha del médico')]);
  const pac = h('input', { type: 'text', placeholder: 'Nombre del paciente', maxlength: '160' });
  const doc = h('input', { type: 'text', placeholder: 'Cédula (opcional)', maxlength: '40' });
  const phone = h('input', { type: 'tel', placeholder: 'Teléfono (opcional)', maxlength: '20' });
  const ars = h('select', { 'aria-label': 'ARS' },
    h('option', { value: '' }, 'Privado / sin ARS'), (arsCatalog || []).map((a) => h('option', { value: a.id }, a.name)));
  const adm = h('input', { type: 'date' });
  const discharge = h('input', { type: 'date' });
  const notes = h('textarea', { rows: '2', placeholder: 'Observaciones administrativas', maxlength: '1000' });
  const save = h('button', { class: 'i18-btn', type: 'button' }, 'Crear reporte');
  return h('details', { class: 'hosp-new', open: false },
    h('summary', {}, 'Nuevo reporte (vista previa en soporte)'),
    note('Modo soporte: puedes ver el formulario que utiliza el médico, pero no se pueden crear ni editar reportes.', 'info'),
    h('fieldset', { disabled: 'disabled', class: 'hosp-form hosp-case-form', style: 'border:0;padding:0' },
      field('Centro', centerSel), field('Paciente', pac), field('Cédula (opcional)', doc),
      field('Teléfono (opcional)', phone), field('ARS', ars), field('Ingreso', adm),
      field('Alta', discharge), field('Observaciones', notes), save));
}

/** 5.38.0 · Normaliza fechas provenientes de Excel: Date JS, ISO string, DD/MM/YYYY, serial Excel. */
function normalizeDate(raw) {
  if (!raw) return null;
  if (raw instanceof Date) { const d = raw; return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10); }
  const s = String(raw).trim();
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  const dmy = s.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/);
  if (dmy) return `${dmy[3]}-${dmy[2].padStart(2, '0')}-${dmy[1].padStart(2, '0')}`;
  const num = Number(s);
  if (num > 25000 && num < 60000) { const d = new Date((num - 25569) * 86400000); return d.toISOString().slice(0, 10); }
  return null;
}

/** 5.38.0 · Carga de hospitalización por personal SoFa (manual + Excel + borradores).
 *  billing ve solo la pestaña Recibidos (lectura). super_admin/admin/operations ven las 4 pestañas. */
async function renderStaff(root, context) {
  const canLoad = ['super_admin', 'admin', 'operations'].includes(context.role);
  const wrap = h('div', { class: 'i18-wrap hosp-wrap hosp-staff' });
  root.replaceChildren(wrap);
  wrap.append(h('header', { class: 'hosp-header' },
    h('div', {},
      h('h2', {}, 'Hospitalización'),
      h('p', { class: 'i18-sub' }, canLoad
        ? 'Carga y seguimiento de reportes de hospitalización.'
        : 'Reportes enviados por los médicos para revisión del equipo de SoFa.')),
    canSee('centros', context.role) ? h('a', { class: 'i18-btn i18-sec', href: '#/centros' }, 'Gestionar centros') : null));

  const output = h('div', { 'aria-live': 'polite' });
  wrap.append(output);

  /* ── billing: solo lectura, sin tabs ── */
  if (!canLoad) {
    const data = await guarded(output, () => rpc('hospital_staff_context', { p_report: context.arg || null }));
    if (!data || !wrap.isConnected) return;
    const detail = h('div', { 'aria-live': 'polite' });
    const rows = data.reportes || [];
    let seq = 0;
    output.replaceChildren(
      note('Supervisión de solo lectura. La creación y edición corresponden al médico.', 'info'),
      h('div', { class: 'hosp-overviewgrid' },
        h('section', {},
          h('h3', {}, 'Reportes recibidos'),
          h('p', { class: 'i18-sub' }, `Mostrando ${rows.length} de ${data.report_count ?? rows.length} reporte(s) dentro de tu acceso.`),
          rows.length
            ? h('div', { class: 'hosp-list' }, ...rows.map((r) =>
                h('button', { type: 'button', class: 'hosp-row', onclick: () => openRec(r.id) },
                  h('span', {}, `${r.patient_name} · ${r.centro}`),
                  h('span', { class: 'hosp-mut' }, `${r.medico} · ${r.status} · ${money(r.total)}`))))
            : note('No hay reportes enviados visibles en tu ámbito.', 'info')),
        detail));
    if (data.report) detail.append(readOnlyReport(data.report));
    async function openRec(id) {
      const my = ++seq; detail.replaceChildren(note('Consultando reporte…', 'info'));
      try {
        const result = await rpc('hospital_staff_context', { p_report: id });
        if (my !== seq || !wrap.isConnected) return;
        if (!result.report || result.report.id !== id) throw new Error('Reporte no disponible.');
        detail.replaceChildren(readOnlyReport(result.report));
      } catch (e) { if (my === seq && wrap.isConnected) detail.replaceChildren(note(e.message, 'error')); }
    }
    return;
  }

  /* ── super_admin / admin / operations: carga paralela de datos iniciales ── */
  let targets, arsCatalog, staffCtx;
  try {
    [targets, arsCatalog, staffCtx] = await Promise.all([
      rpc('hospital_staff_targets'),
      rpc('ars_catalog', { p_include_inactive: false }).catch(() => []),
      rpc('hospital_staff_context', { p_report: context.arg || null }),
    ]);
  } catch (e) { output.replaceChildren(note(e.message, 'error')); return; }
  if (!wrap.isConnected) return;

  if (!targets || !targets.length) {
    output.replaceChildren(note('No hay médicos asignados para carga. Verifica que los médicos tengan centros activos en sus fichas.', 'warn'));
    return;
  }

  /* ── Sistema de tabs ── */
  const TABS = [
    { id: 'nuevo', label: 'Nuevo reporte' },
    { id: 'excel', label: 'Importar Excel' },
    { id: 'borradores', label: 'Borradores' },
    { id: 'recibidos', label: 'Recibidos' },
  ];
  let activeTab = context.arg ? 'recibidos' : 'nuevo';
  const tabBar = h('nav', { class: 'hosp-tabs', 'aria-label': 'Pestañas de hospitalización' });
  const tabContent = h('div', { 'aria-live': 'polite' });

  function drawTabs() {
    tabBar.replaceChildren(...TABS.map((t) => {
      const btn = h('button', { type: 'button', class: 'hosp-tab' + (t.id === activeTab ? ' hosp-tab-on' : '') }, t.label);
      btn.addEventListener('click', () => { if (t.id === activeTab) return; activeTab = t.id; drawTabs(); showTab(); });
      return btn;
    }));
  }
  function showTab() {
    tabContent.replaceChildren(); // limpia antes de dibujar
    if (activeTab === 'nuevo') tabNuevo();
    else if (activeTab === 'excel') tabExcel();
    else if (activeTab === 'borradores') tabBorradores();
    else tabRecibidos();
  }

  output.replaceChildren(tabBar, tabContent);
  drawTabs();
  showTab();

  /* ── Helpers compartidos ── */
  function providerOpts() {
    return [h('option', { value: '' }, 'Selecciona un médico…'),
      ...targets.map((t) => h('option', { value: t.provider_id },
        t.full_name + (t.org_name ? ` · ${t.org_name}` : '')))];
  }
  function centerOptsFor(providerId) {
    const t = targets.find((x) => x.provider_id === providerId);
    const c = t?.centros || [];
    return c.length
      ? c.map((x) => h('option', { value: x.center_id }, x.nombre + (x.principal ? ' (ppal.)' : '')))
      : [h('option', { value: '' }, 'Sin centros')];
  }
  function arsOpts(selectedId) {
    const sel = h('select', { 'aria-label': 'ARS' },
      h('option', { value: '' }, 'Privado / sin ARS'),
      ...(arsCatalog || []).map((a) => h('option', { value: a.id }, a.name)));
    if (selectedId) sel.value = selectedId;
    return sel;
  }
  const field = (label, el) => h('label', {}, label, el);

  /* ── Vista de detalle de borrador (compartida entre Nuevo y Borradores) ── */
  function drawDraft(r, container) {
    const out = h('div', { 'aria-live': 'polite' });
    const table = reportLinesTable(r.lineas, {
      empty: 'Sin servicios todavía. Agrega uno abajo.',
      rowAction: r.puede_editar ? (l) => {
        const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Quitar');
        b.addEventListener('click', async () => {
          try { const rr = await rpc('hospital_staff_line_remove', { p_line: l.id }); drawDraft(rr, container); }
          catch (e) { out.replaceChildren(note(e.message, 'error')); }
        });
        return b;
      } : null,
    });
    const foot = reportFoot(r, { strong: true, extra: `  ${r.medico} · ${r.centro} · ${r.status}` });

    /* Formulario para agregar línea */
    let addLineBox = null;
    if (r.puede_editar) {
      addLineBox = h('details', { class: 'hosp-addline', open: true });
      const servSel = h('select', { 'aria-label': 'Servicio' }, h('option', { value: '' }, 'Cargando tarifario…'));
      const fecha = h('input', { type: 'date', 'aria-label': 'Fecha del servicio', value: r.admission_date || '' });
      const cant = h('input', { type: 'number', min: '0.01', step: '1', value: '1', 'aria-label': 'Cantidad' });
      const precio = h('input', { type: 'number', min: '0', step: '0.01', placeholder: 'Precio (auto)', 'aria-label': 'Precio' });
      const addBtn = h('button', { class: 'i18-btn', type: 'button' }, 'Agregar servicio');
      const addOut = h('div', { 'aria-live': 'polite' });

      let tarSeq = 0;
      async function loadTariff() {
        const my = ++tarSeq; servSel.disabled = true;
        try {
          const tar = await rpc('hospital_staff_tariff', { p_provider: r.provider_id, p_date: fecha.value || null });
          if (my !== tarSeq || !container.isConnected) return;
          servSel.replaceChildren(h('option', { value: '' }, 'Elige un servicio…'),
            ...(tar || []).map((t) => h('option', { value: t.procedure_id, 'data-amount': t.amount },
              `${t.codigo} · ${t.servicio} · ${money(t.amount)}`)));
        } catch (e) { if (my === tarSeq) addOut.replaceChildren(note(e.message, 'error')); }
        finally { if (my === tarSeq) servSel.disabled = false; }
      }
      fecha.addEventListener('change', loadTariff);
      queueMicrotask(loadTariff);
      servSel.addEventListener('change', () => {
        const o = servSel.selectedOptions[0];
        if (o && o.dataset.amount) precio.value = o.dataset.amount;
      });
      addBtn.addEventListener('click', async () => {
        if (!servSel.value) { addOut.replaceChildren(note('Elige un servicio.', 'warn')); return; }
        if (!fecha.value) { addOut.replaceChildren(note('Indica la fecha del servicio.', 'warn')); return; }
        addBtn.disabled = true;
        try {
          const rr = await rpc('hospital_staff_line_add', {
            p_report: r.id, p_procedure: servSel.value, p_service_date: fecha.value,
            p_quantity: Number(cant.value || 1), p_unit_amount: precio.value ? Number(precio.value) : null });
          drawDraft(rr, container);
        } catch (e) { addOut.replaceChildren(note(e.message, 'error')); }
        finally { addBtn.disabled = false; }
      });
      addLineBox.append(
        h('summary', {}, 'Agregar un servicio'),
        h('div', { class: 'hosp-form' }, servSel, fecha, cant, precio, addBtn, addOut));
    }

    /* Botón enviar */
    let submitBtn = null;
    if (r.puede_editar) {
      submitBtn = h('button', { class: 'i18-btn', type: 'button' }, 'Enviar y cerrar reporte');
      submitBtn.addEventListener('click', async () => {
        if (!await confirmDialog('Enviar reporte', '¿Enviar? Después no se edita.', 'Enviar', true)) return;
        submitBtn.disabled = true;
        try { const rr = await rpc('hospital_staff_report_submit', { p_report: r.id }); drawDraft(rr, container); }
        catch (e) { out.replaceChildren(note(e.message, 'error')); }
        finally { submitBtn.disabled = false; }
      });
    }

    container.replaceChildren(h('div', { class: 'hosp-detail' },
      h('h3', {}, `Reporte · ${r.patient_name}`),
      h('p', { class: 'i18-sub' }, [r.medico, r.centro, `Ingreso ${fmtDate(r.admission_date)}`,
        `Alta ${fmtDate(r.discharge_date)}`, r.ars || 'Privado / sin ARS',
        r.patient_phone ? `Tel. ${r.patient_phone}` : null].filter(Boolean).join(' · ')),
      h('div', { class: 'i18-table-wrap' }, table), foot,
      addLineBox, submitBtn,
      !r.puede_editar ? note('Reporte enviado: ya no se edita.', 'info') : null,
      out, bitacoraBlock(r.id)));
  }

  /* ── Tab: Nuevo reporte (manual) ── */
  function tabNuevo() {
    let selectedProvider = '';
    const provSel = h('select', { 'aria-label': 'Médico' }, ...providerOpts());
    const centerBox = h('span');
    const pac = h('input', { type: 'text', placeholder: 'Nombre del paciente', maxlength: '160', required: true, 'aria-label': 'Paciente' });
    const doc = h('input', { type: 'text', placeholder: 'Cédula (opcional)', maxlength: '40', 'aria-label': 'Cédula' });
    const phone = h('input', { type: 'tel', placeholder: 'Teléfono (opcional)', maxlength: '20', 'aria-label': 'Teléfono' });
    const ars = arsOpts();
    const adm = h('input', { type: 'date', 'aria-label': 'Ingreso' });
    const dis = h('input', { type: 'date', 'aria-label': 'Alta' });
    const out = h('div', { 'aria-live': 'polite' });
    const saveBtn = h('button', { class: 'i18-btn', type: 'button' }, 'Crear reporte');
    const detailBox = h('div', { 'aria-live': 'polite' });

    provSel.addEventListener('change', () => {
      selectedProvider = provSel.value;
      centerBox.replaceChildren(h('select', { 'aria-label': 'Centro' }, ...centerOptsFor(selectedProvider)));
    });

    saveBtn.addEventListener('click', async () => {
      if (!selectedProvider) { out.replaceChildren(note('Selecciona un médico.', 'warn')); return; }
      const cSel = centerBox.querySelector('select');
      if (!cSel?.value) { out.replaceChildren(note('Selecciona un centro.', 'warn')); return; }
      if (!pac.value.trim()) { out.replaceChildren(note('Escribe el nombre del paciente.', 'warn')); return; }
      if (adm.value && dis.value && dis.value < adm.value) { out.replaceChildren(note('El alta no puede ser anterior al ingreso.', 'warn')); return; }
      saveBtn.disabled = true;
      try {
        const report = await rpc('hospital_staff_report_save', {
          p_provider: selectedProvider, p_center: cSel.value,
          p_patient_name: pac.value.trim(), p_patient_doc: doc.value.trim() || null,
          p_phone: phone.value.trim() || null, p_ars: ars.value || null,
          p_admission: adm.value || null, p_discharge: dis.value || null });
        out.replaceChildren();
        drawDraft(report, detailBox);
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
      finally { saveBtn.disabled = false; }
    });

    tabContent.replaceChildren(
      h('div', { class: 'hosp-case-form' },
        field('Médico', provSel), field('Centro', centerBox),
        field('Paciente', pac), field('Cédula (opcional)', doc),
        field('Teléfono (opcional)', phone), field('ARS', ars),
        field('Ingreso', adm), field('Alta', dis),
        saveBtn, out),
      detailBox);
  }

  /* ── Tab: Importar Excel ── */
  function tabExcel() {
    let selectedProvider = '';
    const provSel = h('select', { 'aria-label': 'Médico' }, ...providerOpts());
    const centerBox = h('span');
    const pac = h('input', { type: 'text', placeholder: 'Nombre del paciente', maxlength: '160', 'aria-label': 'Paciente' });
    const doc = h('input', { type: 'text', placeholder: 'Cédula (opcional)', maxlength: '40', 'aria-label': 'Cédula' });
    const phone = h('input', { type: 'tel', placeholder: 'Teléfono (opcional)', maxlength: '20', 'aria-label': 'Teléfono' });
    const ars = arsOpts();
    const adm = h('input', { type: 'date', 'aria-label': 'Ingreso' });
    const dis = h('input', { type: 'date', 'aria-label': 'Alta' });
    const fileInput = h('input', { type: 'file', accept: '.xlsx,.xls,.csv', 'aria-label': 'Archivo Excel' });
    const out = h('div', { 'aria-live': 'polite' });
    const preview = h('div', { 'aria-live': 'polite' });
    const importBtn = h('button', { class: 'i18-btn', type: 'button' }, 'Importar y crear reporte');

    provSel.addEventListener('change', () => {
      selectedProvider = provSel.value;
      centerBox.replaceChildren(h('select', { 'aria-label': 'Centro' }, ...centerOptsFor(selectedProvider)));
    });

    let parsedLines = [];

    fileInput.addEventListener('change', () => {
      const file = fileInput.files[0];
      if (!file) { preview.replaceChildren(); parsedLines = []; return; }
      const reader = new FileReader();
      reader.onload = (ev) => {
        try {
          if (typeof window === 'undefined' || typeof window.XLSX === 'undefined')
            throw new Error('La librería de Excel no está disponible. Recarga la página e intenta de nuevo.');
          const wb = window.XLSX.read(new Uint8Array(ev.target.result), { type: 'array' });
          const ws = wb.Sheets[wb.SheetNames[0]];
          const rows = window.XLSX.utils.sheet_to_json(ws, { defval: '' });
          if (!rows.length) throw new Error('El archivo está vacío.');
          parsedLines = rows.map((row, i) => {
            const codigo = String(row.codigo || row.Codigo || row.CODIGO || row.code || row.Code || '').trim();
            const dateRaw = row.service_date || row.fecha_servicio || row.fecha || row.Fecha || row.FECHA || row.date || '';
            const qty = Number(row.quantity || row.cantidad || row.Cantidad || row.CANTIDAD || row.qty || 1) || 1;
            const amt = row.unit_amount || row.precio_unitario || row.precio || row.Precio || row.PRECIO || row.price || null;
            if (!codigo) throw new Error(`Fila ${i + 1}: falta el código del servicio (columna "codigo").`);
            return { codigo, service_date: normalizeDate(dateRaw), quantity: qty, unit_amount: amt ? Number(amt) : null };
          });
          preview.replaceChildren(
            h('p', { class: 'hosp-preview-count' }, `${parsedLines.length} línea(s) detectada(s). Revisa y confirma abajo.`),
            h('div', { class: 'i18-table-wrap' },
              h('table', { class: 'hosp-tbl' },
                h('thead', {}, h('tr', {},
                  h('th', {}, '#'), h('th', {}, 'Código'), h('th', {}, 'Fecha'),
                  h('th', { class: 'num' }, 'Cant.'), h('th', { class: 'num' }, 'Precio'))),
                h('tbody', {}, ...parsedLines.map((l, i) => h('tr', {},
                  h('td', {}, String(i + 1)), h('td', {}, l.codigo), h('td', {}, l.service_date || '—'),
                  h('td', { class: 'num' }, String(l.quantity)),
                  h('td', { class: 'num' }, l.unit_amount != null ? money(l.unit_amount) : 'Tarifario')))))),
            importBtn);
        } catch (e) { preview.replaceChildren(note(e.message, 'error')); parsedLines = []; }
      };
      reader.readAsArrayBuffer(file);
    });

    importBtn.addEventListener('click', async () => {
      if (!selectedProvider) { out.replaceChildren(note('Selecciona un médico.', 'warn')); return; }
      const cSel = centerBox.querySelector('select');
      if (!cSel?.value) { out.replaceChildren(note('Selecciona un centro.', 'warn')); return; }
      if (!pac.value.trim()) { out.replaceChildren(note('Escribe el nombre del paciente.', 'warn')); return; }
      if (!parsedLines.length) { out.replaceChildren(note('Carga un archivo Excel primero.', 'warn')); return; }
      if (adm.value && dis.value && dis.value < adm.value) { out.replaceChildren(note('El alta no puede ser anterior al ingreso.', 'warn')); return; }
      importBtn.disabled = true;
      try {
        const report = await rpc('hospital_staff_import', {
          p_provider: selectedProvider, p_center: cSel.value,
          p_patient_name: pac.value.trim(), p_patient_doc: doc.value.trim() || null,
          p_phone: phone.value.trim() || null, p_ars: ars.value || null,
          p_admission: adm.value || null, p_discharge: dis.value || null,
          p_lines: parsedLines });
        out.replaceChildren(note(`Reporte creado con ${(report.lineas || []).length} servicio(s). Revisa y envía abajo.`, 'ok'));
        preview.replaceChildren(); fileInput.value = ''; parsedLines = [];
        const detailBox = h('div', { 'aria-live': 'polite' });
        tabContent.append(detailBox);
        drawDraft(report, detailBox);
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
      finally { importBtn.disabled = false; }
    });

    tabContent.replaceChildren(
      h('div', { class: 'hosp-case-form' },
        field('Médico', provSel), field('Centro', centerBox),
        field('Paciente', pac), field('Cédula (opcional)', doc),
        field('Teléfono (opcional)', phone), field('ARS', ars),
        field('Ingreso', adm), field('Alta', dis),
        field('Archivo Excel (.xlsx)', fileInput),
        h('p', { class: 'hosp-excel-hint' },
          'Columnas esperadas: codigo, fecha_servicio (o fecha), cantidad (o quantity), precio_unitario (o unit_amount). El precio es opcional (se usa el tarifario).'),
        out),
      preview);
  }

  /* ── Tab: Borradores ── */
  async function tabBorradores() {
    tabContent.replaceChildren(note('Cargando borradores…', 'info'));
    try {
      const drafts = await rpc('hospital_staff_drafts');
      if (!wrap.isConnected) return;
      if (!drafts.length) { tabContent.replaceChildren(note('No hay borradores pendientes.', 'info')); return; }
      const detailBox = h('div', { 'aria-live': 'polite' });
      tabContent.replaceChildren(
        h('div', { class: 'hosp-list' }, ...drafts.map((d) => {
          const btn = h('button', { type: 'button', class: 'hosp-row' },
            h('span', {}, `${d.patient_name} · ${d.centro}`),
            h('span', { class: 'hosp-mut' }, `${d.medico} · ${money(d.total)}`));
          btn.addEventListener('click', () => openDraft(d.id));
          return btn;
        })),
        detailBox);

      async function openDraft(id) {
        detailBox.replaceChildren(note('Cargando reporte…', 'info'));
        try {
          const r = await rpc('hospital_staff_payload', { p_report: id });
          if (!wrap.isConnected) return;
          drawDraft(r, detailBox);
        } catch (e) { detailBox.replaceChildren(note(e.message, 'error')); }
      }
    } catch (e) { tabContent.replaceChildren(note(e.message, 'error')); }
  }

  /* ── Tab: Recibidos (solo lectura, equivale al renderStaff original) ── */
  function tabRecibidos() {
    const data = staffCtx;
    const rows = data?.reportes || [];
    const detail = h('div', { 'aria-live': 'polite' });
    let seq = 0;
    tabContent.replaceChildren(
      h('p', { class: 'i18-sub' }, `Mostrando ${rows.length} de ${data?.report_count ?? rows.length} reporte(s) dentro de tu acceso.`),
      rows.length
        ? h('div', { class: 'hosp-overviewgrid' },
            h('section', {},
              h('div', { class: 'hosp-list' }, ...rows.map((r) => {
                const btn = h('button', { type: 'button', class: 'hosp-row' },
                  h('span', {}, `${r.patient_name} · ${r.centro}`),
                  h('span', { class: 'hosp-mut' }, `${r.medico} · ${r.status} · ${money(r.total)}`));
                btn.addEventListener('click', () => openRec(r.id));
                return btn;
              }))),
            detail)
        : note('No hay reportes enviados visibles en tu ámbito.', 'info'));

    if (data?.report) detail.replaceChildren(readOnlyReport(data.report));

    async function openRec(id) {
      const my = ++seq; detail.replaceChildren(note('Consultando reporte…', 'info'));
      try {
        const result = await rpc('hospital_staff_context', { p_report: id });
        if (my !== seq || !wrap.isConnected) return;
        if (!result.report) throw new Error('Reporte no disponible.');
        detail.replaceChildren(readOnlyReport(result.report));
      } catch (e) { if (my === seq && wrap.isConnected) detail.replaceChildren(note(e.message, 'error')); }
    }
  }
}

function readOnlyReport(r) {
  return h('section', { class: 'hosp-detail hosp-staff-detail' },
    h('h3', {}, `Reporte · ${r.patient_name}`),
    h('p', { class: 'i18-sub' }, `${r.medico || ''} · ${r.centro} · ${r.status}`),
    h('p', {}, `Ingreso ${fmtDate(r.admission_date)} · Alta ${fmtDate(r.discharge_date)} · ${r.ars || 'Privado / sin ARS'}${r.patient_phone ? ' · Tel. ' + r.patient_phone : ''}`),
    h('div', { class: 'i18-table-wrap' }, reportLinesTable(r.lineas, { headers: ['Fecha', 'Servicio', 'Cantidad', 'Unitario', 'Monto', '%', 'Proy.'] })),
    reportFoot(r, { strong: true }),
    note('Solo lectura para el equipo de seguimiento.', 'info'),
    bitacoraBlock(r.id));
}

/** SOFA · 5.35.1 · Bitácora de hospitalización: procesos, hallazgos y observaciones.
 *  Append-only (el backend protege con trigger). Cada entrada se marca con shared_with_admin
 *  para que el super_admin/admin del cliente la vea; por defecto queda solo para el autor y el
 *  staff de SOFA. Reutilizable en las tres vistas (médico, soporte, staff). */
const BITACORA_KIND_LABEL = { proceso: 'Proceso', hallazgo: 'Hallazgo', observacion: 'Observación' };

function bitacoraBlock(reportId) {
  const section = h('section', { class: 'hosp-bita', 'data-report': reportId });
  const title = h('h4', {}, 'Bitácora interna');
  const subtitle = h('p', { class: 'i18-sub' }, 'Procesos, hallazgos y observaciones para el seguimiento interno del reporte. Puedes marcar «compartir con administración» para que el super admin y el admin del cliente lo vean.');
  const list = h('div', { class: 'hosp-bita-list', 'aria-live': 'polite' }, note('Cargando bitácora…', 'info'));
  const formSlot = h('div');
  section.append(title, subtitle, list, formSlot);

  async function reload() {
    try {
      const data = await rpc('hospital_log_list', { p_report: reportId });
      const entries = data?.entries || [];
      if (!entries.length) list.replaceChildren(note('Aún no hay entradas en la bitácora.', 'info'));
      else list.replaceChildren(...entries.map(renderEntry));
      formSlot.replaceChildren(data?.can_write ? renderForm() : document.createDocumentFragment());
    } catch (e) { list.replaceChildren(note(e.message, 'error')); }
  }

  function renderEntry(e) {
    const kind = BITACORA_KIND_LABEL[e.kind] || e.kind;
    const when = e.created_at ? new Date(e.created_at).toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) : '';
    return h('article', { class: `hosp-bita-item hosp-bita-${e.kind}` },
      h('header', { class: 'hosp-bita-head' },
        h('span', { class: `hosp-bita-tag hosp-bita-tag-${e.kind}` }, kind),
        h('span', { class: 'hosp-mut' }, `${e.author_name || '—'} · ${when}`),
        e.shared_with_admin ? h('span', { class: 'hosp-bita-share hosp-bita-share-on' }, 'Visible a administración') : h('span', { class: 'hosp-bita-share hosp-mut' }, 'Interno SOFA')),
      h('p', { class: 'hosp-bita-body' }, e.content));
  }

  function renderForm() {
    const kindSel = h('select', { 'aria-label': 'Tipo de entrada' },
      h('option', { value: 'proceso' }, 'Proceso'),
      h('option', { value: 'hallazgo' }, 'Hallazgo'),
      h('option', { value: 'observacion' }, 'Observación'));
    const content = h('textarea', { rows: '3', maxlength: '4000', 'aria-label': 'Contenido', placeholder: 'Describe el proceso, hallazgo u observación…' });
    const share = h('input', { type: 'checkbox', id: `hosp-bita-share-${reportId}` });
    const shareLabel = h('label', { for: `hosp-bita-share-${reportId}`, class: 'hosp-bita-sharelabel' }, share, ' Compartir con administración (super admin y admin del cliente)');
    const out = h('div', { 'aria-live': 'polite' });
    const btn = h('button', { class: 'i18-btn', type: 'button' }, 'Agregar entrada');
    btn.addEventListener('click', async () => {
      const text = content.value.trim();
      if (!text) { out.replaceChildren(note('Escribe el contenido antes de guardar.', 'warn')); return; }
      btn.disabled = true;
      try {
        await rpc('hospital_log_add', { p_report: reportId, p_kind: kindSel.value, p_content: text, p_shared_with_admin: share.checked });
        content.value = ''; share.checked = false; out.replaceChildren();
        await reload();
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
      finally { btn.disabled = false; }
    });
    return h('div', { class: 'hosp-bita-form' },
      h('label', {}, 'Tipo', kindSel),
      h('label', {}, 'Contenido', content),
      shareLabel, btn, out);
  }

  queueMicrotask(reload);
  return section;
}
