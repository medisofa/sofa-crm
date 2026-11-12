/** SOFA · 5.7.0 · I68a · «Hospitalización»: el médico reporta, por paciente hospitalizado, los servicios que dio,
 *  cobrados según SU tarifario, en cualquiera de los centros de su ficha. La base valida todo (centro de su ficha,
 *  precio del tarifario, reporte en firme al enviar). Ocultar un botón aquí no es un control. */
import { rpc, h, note, guarded, money, fmtDate } from '../services/iter18.js';
import { confirmDialog } from '../utils/ui.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';
import { canSee } from '../utils/permissions.js';

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
    const doc = h('input', { type: 'text', 'aria-label': 'Documento del paciente', placeholder: 'Documento (opcional)', maxlength: '40', value: r?.patient_doc || '' });
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
      field('Centro', centerSel), field('Paciente', pac), field('Documento (opcional)', doc), field('Teléfono (opcional)', phone), field('ARS', ars), field('Ingreso', adm), field('Alta', discharge), field('Observaciones', notes), save, out));
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
    const lines = (r.lineas || []).map((l) => h('tr', {},
      h('td', {}, fmtDate(l.service_date)), h('td', {}, `${l.servicio || l.codigo}`),
      h('td', { class: 'num' }, String(l.quantity)), h('td', { class: 'num' }, money(l.unit_amount)),
      h('td', { class: 'num' }, money(l.amount)),
      h('td', {}, r.puede_editar ? delBtn(l.id) : '')));
    const table = h('table', { class: 'hosp-tbl' },
      h('thead', {}, h('tr', {}, h('th', {}, 'Fecha'), h('th', {}, 'Servicio'), h('th', {}, 'Cant.'), h('th', {}, 'Precio'), h('th', {}, 'Monto'), h('th', {}, ''))),
      h('tbody', {}, lines.length ? lines : h('tr', {}, h('td', { colspan: '6', class: 'hosp-mut' }, 'Sin servicios todavía.'))));
    const foot = h('div', { class: 'hosp-foot' }, h('b', {}, `Total: ${money(r.total)}`),
      h('span', { class: 'hosp-mut' }, `  ${r.patient_name} · ${r.centro} · ${r.status}`));
    detailBox.replaceChildren(h('div', { class: 'hosp-detail' },
      h('h3', {}, `Reporte · ${r.patient_name}`), h('p', { class: 'i18-sub' }, `Ingreso ${fmtDate(r.admission_date)} · Alta ${fmtDate(r.discharge_date)} · ${r.ars || 'Privado / sin ARS'}${r.patient_phone ? ' · Tel. ' + r.patient_phone : ''}`),
      r.puede_editar ? caseForm(r) : null, table, foot,
      r.puede_editar ? addLineForm(r) : note('Reporte enviado: ya no se edita.', 'info'),
      r.puede_editar ? sendBtn(r) : printBtn(r), out));

    function delBtn(lineId) { const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Quitar'); b.addEventListener('click', async () => { try { const rr = await rpc('hospital_report_line_remove', { p_line: lineId }); drawReport(rr); await loadList(); } catch (e) { out.replaceChildren(note(e.message, 'error')); } }); return b; }
    function sendBtn(rep) { const b = h('button', { class: 'i18-btn', type: 'button' }, 'Enviar y avisar a SoFa'); b.addEventListener('click', async () => { if (!rep.admission_date) { out.replaceChildren(note('Indica la fecha de ingreso antes de enviar el reporte.', 'warn')); return; } if (!await confirmDialog('Enviar reporte', '¿Enviar el reporte y avisar al equipo de SoFa? Después no se edita.', 'Enviar', true)) return; try { const rr = await rpc('hospital_report_submit', { p_report: rep.id }); await loadList(); drawReport(rr); } catch (e) { out.replaceChildren(note(e.message, 'error')); } }); return b; }
    function printBtn(rep) {
      const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Imprimir');
      b.addEventListener('click', () => {
        const w = openPrint();
        if (!w) return;
        const fecha = new Date().toLocaleDateString('es-DO', { year: 'numeric', month: 'long', day: 'numeric' });
        fillPrint(w, `Reporte de hospitalización · ${rep.patient_name}`, `${rep.centro} · Generado el ${fecha}`, [
          { table: { head: ['Fecha', 'Servicio', 'Cant.', 'Precio unit.', 'Monto'],
              rows: (rep.lineas || []).map((l) => [fmtDate(l.service_date), l.servicio || l.codigo, String(l.quantity), money(l.unit_amount), money(l.amount)]),
              right: [2, 3, 4] } },
          { big: `Total: ${money(rep.total)}` },
        ]);
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
      const lines = r.lineas || [];
      detail.replaceChildren(h('section', { class: 'hosp-detail hosp-support-detail' },
        h('h3', {}, `Reporte · ${r.patient_name}`),
        h('p', { class: 'i18-sub' }, `${r.centro} · ${r.status} · Ingreso ${fmtDate(r.admission_date)}`),
        h('div', { class: 'i18-table-wrap' }, h('table', { class: 'hosp-tbl' },
          h('thead', {}, h('tr', {}, ...['Fecha', 'Servicio', 'Cant.', 'Precio', 'Monto'].map((label) => h('th', {}, label)))),
          h('tbody', {}, ...(lines.length ? lines.map((l) => h('tr', {}, h('td', {}, fmtDate(l.service_date)), h('td', {}, l.servicio || l.codigo),
            h('td', { class: 'num' }, String(l.quantity)), h('td', { class: 'num' }, money(l.unit_amount)), h('td', { class: 'num' }, money(l.amount))))
            : [h('tr', {}, h('td', { colspan: '5' }, 'Sin servicios registrados.'))])))),
        h('div', { class: 'hosp-foot' }, h('b', {}, `Total: ${money(r.total)}`)),
        note('Solo lectura en modo soporte.', 'info')));
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
  const doc = h('input', { type: 'text', placeholder: 'Documento (opcional)', maxlength: '40' });
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
      field('Centro', centerSel), field('Paciente', pac), field('Documento (opcional)', doc),
      field('Teléfono (opcional)', phone), field('ARS', ars), field('Ingreso', adm),
      field('Alta', discharge), field('Observaciones', notes), save));
}

/** Supervisión operativa: reportes enviados, lectura autorizada en el servidor. */
async function renderStaff(root, context) {
  const wrap = h('div', { class: 'i18-wrap hosp-wrap hosp-staff' }); root.replaceChildren(wrap);
  wrap.append(h('header', { class: 'hosp-header' }, h('div', {}, h('h2', {}, 'Hospitalización'), h('p', { class: 'i18-sub' }, 'Reportes enviados por los médicos para revisión del equipo de SoFa.')),
    canSee('centros', context.role) ? h('a', { class: 'i18-btn i18-sec', href: '#/centros' }, 'Gestionar centros') : null));
  const output = h('div', { 'aria-live': 'polite' }); wrap.append(output);
  const data = await guarded(output, () => rpc('hospital_staff_context', { p_report: context.arg || null }));
  if (!data || !wrap.isConnected) return;
  const detail = h('div', { 'aria-live': 'polite' });
  const rows = data.reportes || [];
  let sequence = 0;
  const list = h('section', {}, h('h3', {}, 'Reportes recibidos'), h('p', { class: 'i18-sub' }, `Mostrando ${rows.length} de ${data.report_count ?? rows.length} reporte(s) dentro de tu acceso.`),
    rows.length ? h('div', { class: 'hosp-list' }, ...rows.map((r) => h('button', { type: 'button', class: 'hosp-row', onclick: () => open(r.id) },
      h('span', {}, `${r.patient_name} · ${r.centro}`), h('span', { class: 'hosp-mut' }, `${r.medico} · ${r.status} · ${money(r.total)}`)))) : note('No hay reportes enviados visibles en tu ámbito.', 'info'));
  output.replaceChildren(note('Supervisión de solo lectura. La creación y edición corresponden al médico.', 'info'), h('div', { class: 'hosp-overviewgrid' }, list, detail));
  if (data.report) detail.append(readOnlyReport(data.report));
  async function open(id) {
    const my = ++sequence; detail.replaceChildren(note('Consultando reporte…', 'info'));
    try {
      const result = await rpc('hospital_staff_context', { p_report: id });
      if (my !== sequence || !wrap.isConnected) return;
      if (!result.report || result.report.id !== id) throw new Error('Reporte no disponible.');
      detail.replaceChildren(readOnlyReport(result.report));
    } catch(e) { if (my === sequence && wrap.isConnected) detail.replaceChildren(note(e.message, 'error')); }
  }
}

function readOnlyReport(r) {
  return h('section', { class: 'hosp-detail hosp-staff-detail' }, h('h3', {}, `Reporte · ${r.patient_name}`),
    h('p', { class: 'i18-sub' }, `${r.medico || ''} · ${r.centro} · ${r.status}`),
    h('p', {}, `Ingreso ${fmtDate(r.admission_date)} · Alta ${fmtDate(r.discharge_date)} · ${r.ars || 'Privado / sin ARS'}${r.patient_phone ? ' · Tel. ' + r.patient_phone : ''}`),
    h('div', { class: 'i18-table-wrap' }, h('table', { class: 'hosp-tbl' },
      h('thead', {}, h('tr', {}, ...['Fecha', 'Servicio', 'Cantidad', 'Unitario', 'Monto'].map((v) => h('th', {}, v)))),
      h('tbody', {}, ...(r.lineas || []).map((l) => h('tr', {}, h('td', {}, fmtDate(l.service_date)), h('td', {}, l.servicio || l.codigo), h('td', { class: 'num' }, String(l.quantity)), h('td', { class: 'num' }, money(l.unit_amount)), h('td', { class: 'num' }, money(l.amount))))))),
    h('div', { class: 'hosp-foot' }, h('strong', {}, `Total: ${money(r.total)}`)), note('Solo lectura para el equipo de seguimiento.', 'info'));
}
