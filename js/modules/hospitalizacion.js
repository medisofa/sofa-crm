/** SOFA · 5.7.0 · I68a · «Hospitalización»: el médico reporta, por paciente hospitalizado, los servicios que dio,
 *  cobrados según SU tarifario, en cualquiera de los centros de su ficha. La base valida todo (centro de su ficha,
 *  precio del tarifario, reporte en firme al enviar). Ocultar un botón aquí no es un control. */
import { rpc, h, note, guarded, money, fmtDate } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const wrap = h('div', { class: 'i18-wrap hosp-wrap' });
  root.append(wrap);
  const ctx = await guarded(wrap, () => rpc('hospital_centers_mine'));
  if (!ctx) return;
  if (!ctx.soy_medico) {
    wrap.append(h('h2', {}, 'Hospitalización'), note('Esta pantalla es para el médico. Tu usuario no está ligado a un médico en SOFA.', 'info'));
    return;
  }
  const centros = ctx.centros || [];
  const status = h('div', { 'aria-live': 'polite' });
  const listBox = h('div', { 'aria-live': 'polite' });
  const detailBox = h('div', { 'aria-live': 'polite' });
  wrap.append(h('h2', {}, 'Hospitalización'),
    h('p', { class: 'i18-sub' }, 'Reporta los servicios que diste a cada paciente hospitalizado. El precio sale de tu tarifario; puedes ajustarlo. Al enviar, el reporte queda en firme.'),
    status, newReportForm(), h('h3', {}, 'Mis reportes'), listBox, detailBox);

  async function loadList() {
    const data = await guarded(listBox, () => rpc('hospital_report_list'));
    if (!data) return;
    if (!data.length) { listBox.replaceChildren(note('Aún no tienes reportes.', 'info')); return; }
    listBox.replaceChildren(h('div', { class: 'hosp-list' }, data.map((r) =>
      h('button', { class: 'hosp-row', type: 'button', onclick: () => openReport(r.id) },
        h('span', {}, `${r.patient_name} · ${r.centro}`),
        h('span', { class: 'hosp-mut' }, `${r.status} · ${money(r.total)}`)))));
  }

  function newReportForm() {
    const box = h('details', { class: 'hosp-new' });
    const centerSel = h('select', { 'aria-label': 'Centro' }, centros.map((c) => h('option', { value: c.center_id }, c.nombre + (c.principal ? ' (principal)' : ''))));
    const pac = h('input', { type: 'text', placeholder: 'Nombre del paciente', maxlength: '160' });
    const doc = h('input', { type: 'text', placeholder: 'Documento (opcional)', maxlength: '40' });
    const adm = h('input', { type: 'date', 'aria-label': 'Fecha de ingreso' });
    const out = h('div', { 'aria-live': 'polite' });
    const crear = h('button', { class: 'i18-btn', type: 'button' }, 'Crear reporte');
    crear.addEventListener('click', async () => {
      if (!centros.length) { out.replaceChildren(note('No tienes centros en tu ficha. Pide que te agreguen a un centro.', 'warn')); return; }
      if (!pac.value.trim()) { out.replaceChildren(note('Escribe el nombre del paciente.', 'warn')); return; }
      try {
        const r = await rpc('hospital_report_save', { p_center: centerSel.value, p_patient_name: pac.value.trim(), p_patient_doc: doc.value.trim() || null, p_admission: adm.value || null });
        pac.value = ''; doc.value = ''; out.replaceChildren(); box.open = false;
        await loadList(); openReport(r.id);
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
    });
    box.append(h('summary', {}, 'Nuevo reporte'), h('div', { class: 'hosp-form' }, centerSel, pac, doc, adm, crear, out));
    return box;
  }

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
      h('h3', {}, `Reporte · ${r.patient_name}`), table, foot,
      r.puede_editar ? addLineForm(r) : note('Reporte enviado: ya no se edita.', 'info'),
      r.puede_editar ? sendBtn(r) : printBtn(r), out));

    function delBtn(lineId) { const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Quitar'); b.addEventListener('click', async () => { try { const rr = await rpc('hospital_report_line_remove', { p_line: lineId }); drawReport(rr); } catch (e) { out.replaceChildren(note(e.message, 'error')); } }); return b; }
    function sendBtn(rep) { const b = h('button', { class: 'i18-btn', type: 'button' }, 'Enviar (dejar en firme)'); b.addEventListener('click', async () => { if (!confirm('¿Enviar el reporte? Después no se edita.')) return; try { const rr = await rpc('hospital_report_submit', { p_report: rep.id }); await loadList(); drawReport(rr); } catch (e) { out.replaceChildren(note(e.message, 'error')); } }); return b; }
    function printBtn(rep) { const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Imprimir'); b.addEventListener('click', () => window.print()); return b; }
  }

  function addLineForm(r) {
    const out = h('div', { 'aria-live': 'polite' });
    const box = h('details', { class: 'hosp-addline', open: true });
    const servSel = h('select', { 'aria-label': 'Servicio del tarifario' }, [h('option', { value: '' }, 'Elige un servicio de tu tarifario…')]);
    const fecha = h('input', { type: 'date', 'aria-label': 'Fecha del servicio', value: (r.admission_date || '') });
    const cant = h('input', { type: 'number', min: '0.01', step: '1', value: '1', 'aria-label': 'Cantidad' });
    const precio = h('input', { type: 'number', min: '0', step: '0.01', placeholder: 'Precio (auto del tarifario)', 'aria-label': 'Precio' });
    const add = h('button', { class: 'i18-btn', type: 'button' }, 'Agregar servicio');
    rpc('hospital_my_tariff', { p_date: fecha.value || null }).then((tar) => {
      (tar || []).forEach((t) => servSel.append(h('option', { value: t.procedure_id, 'data-amount': t.amount }, `${t.codigo} · ${t.servicio} · ${money(t.amount)}`)));
    }).catch(() => {});
    servSel.addEventListener('change', () => { const o = servSel.selectedOptions[0]; if (o && o.dataset.amount) precio.value = o.dataset.amount; });
    add.addEventListener('click', async () => {
      if (!servSel.value) { out.replaceChildren(note('Elige un servicio.', 'warn')); return; }
      if (!fecha.value) { out.replaceChildren(note('Indica la fecha del servicio.', 'warn')); return; }
      try {
        const rr = await rpc('hospital_report_line_add', { p_report: r.id, p_procedure: servSel.value, p_service_date: fecha.value, p_quantity: Number(cant.value || 1), p_unit_amount: precio.value ? Number(precio.value) : null });
        out.replaceChildren(); drawReport(rr);
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
    });
    box.append(h('summary', {}, 'Agregar un servicio'), h('div', { class: 'hosp-form' }, servSel, fecha, cant, precio, add, out));
    return box;
  }

  await loadList();
}
