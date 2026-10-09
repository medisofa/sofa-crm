/** SOFA · 2.5 · Iteración 35 · Importar historias clínicas de otro sistema (Excel o CSV).
 *  2.6.1: lo usa solo el Super Admin desde «Historia clínica: control»; las notas quedan a nombre del médico elegido (opts.author).
 *  Una fila por consulta: Documento, Nombre, Fecha, Texto y, si hay, Diagnósticos, Fecha de nacimiento y Sexo.
 *  Vista previa sin guardar nada; al confirmar cada fila queda como nota «Historia importada», cifrada y firmada por quien importa. */
import { h, fmtDate, note } from '../services/iter18.js';
import { readTable, excelDate, detectColumns } from '../utils/xlsx-lite.js';

const ALIASES = {
  documento: ['documento', 'cedula', 'cedula pasaporte', 'identificacion', 'id paciente', 'dni', 'pasaporte'],
  nombre: ['nombre', 'paciente', 'nombre completo', 'nombre paciente'],
  fecha: ['fecha', 'fecha consulta', 'fecha de consulta', 'fecha atencion', 'fecha visita'],
  texto: ['texto', 'nota', 'evolucion', 'consulta', 'historia', 'observaciones', 'descripcion', 'contenido'],
  diagnosticos: ['diagnosticos', 'diagnostico', 'cie10', 'cie 10', 'dx'],
  fecha_nacimiento: ['fecha nacimiento', 'fecha de nacimiento', 'nacimiento'], sexo: ['sexo', 'genero']
};

export function importPanel(main, org, rpc, opts = {}) {
  const author = opts.author || null;
  const src = h('input', { id: 'im-src', placeholder: 'Ej.: Sistema anterior del consultorio', maxlength: '80' });
  const file = h('input', { id: 'im-file', type: 'file', accept: '.xlsx,.csv,.txt' });
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Revisar el archivo');
  const out = h('div', { 'aria-live': 'polite' });
  let rows = null; let fname = '';
  main.replaceChildren(h('section', { class: 'i18-card hc-form' },
    h('h3', { style: 'margin-top:0' }, 'Importar historias de otro sistema'),
    note(`Archivo con una fila por consulta. Columnas: Documento, Nombre, Fecha, Texto (obligatorias) y Diagnósticos, Fecha de nacimiento, Sexo (opcionales). Si el paciente no existe se crea su ficha. Nada se guarda hasta que confirme. Máximo 1,000 filas por archivo.${opts.authorName ? ` Las notas quedarán a nombre de ${opts.authorName}.` : ''}`),
    h('label', { for: 'im-src' }, 'Sistema de origen', src), h('label', { for: 'im-file' }, 'Archivo (.xlsx o .csv)', file),
    h('div', { class: 'i18-actions' }, go), out));
  go.addEventListener('click', async () => {
    out.replaceChildren();
    if (!file.files[0]) return out.replaceChildren(note('Elija el archivo.', 'error'));
    go.disabled = true;
    try {
      const t = await readTable(file.files[0]); fname = file.files[0].name;
      if (t.length < 2) throw new Error('El archivo no tiene filas debajo de los encabezados.');
      const map = detectColumns(t[0], ALIASES);
      const miss = ['documento', 'fecha', 'texto'].filter((k) => map[k] == null);
      if (miss.length) throw new Error(`No se reconocieron las columnas: ${miss.join(', ')}. La primera fila debe tener encabezados como «Documento», «Nombre», «Fecha» y «Texto».`);
      rows = t.slice(1).map((r) => Object.fromEntries(Object.entries(map).map(([k, i]) => [k, k.startsWith('fecha') ? excelDate(r[i]) : (r[i] || '')])));
      const rep = await rpc('clinical_import', { p_org: org, p_rows: rows, p_source: src.value, p_commit: false, p_file: fname, p_author: author });
      preview(rep);
    } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { go.disabled = false; }
  });
  function preview(rep) {
    const save = h('button', { class: 'i18-btn', type: 'button', disabled: rep.errors.length > 0 || !rep.valid }, `Confirmar: importar ${rep.valid} consulta(s)`);
    save.addEventListener('click', async () => {
      if (!confirm(`Las historias importadas quedan a nombre de ${opts.authorName || 'el médico'}, con el sello «Importada por SOFA», y no se pueden borrar. ¿Importar ahora?`)) return;
      save.disabled = true;
      try { const r = await rpc('clinical_import', { p_org: org, p_rows: rows, p_source: src.value, p_commit: true, p_file: fname, p_author: author });
        out.replaceChildren(note(`Listo: ${r.imported} consulta(s) importadas y ${r.patients_created} paciente(s) nuevo(s). El médico las verá en su historia clínica.`, 'ok')); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); }
    });
    out.replaceChildren(
      h('div', { class: 'ac-sum', style: 'margin:10px 0' }, h('span', { class: 'ac-pill st-ok' }, `${rep.valid} válidas`),
        h('span', { class: 'ac-pill st-prep' }, `${rep.new_patients} de pacientes nuevos`), h('span', { class: `ac-pill ${rep.errors.length ? 'st-bad' : 'st-none'}` }, `${rep.errors.length} con error`)),
      rep.errors.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, h('th', {}, 'Fila'), h('th', {}, 'Paciente'), h('th', {}, 'Problema'))),
        h('tbody', {}, rep.errors.map((e) => h('tr', {}, h('td', {}, String(e.row + 1)), h('td', {}, e.name || e.doc || '—'), h('td', {}, e.errors.join(' · '))))))) : '',
      rep.rows.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Paciente', 'Documento', 'Fecha', 'Texto', 'Diagnósticos'].map((x) => h('th', {}, x)))),
        h('tbody', {}, rep.rows.slice(0, 50).map((r) => h('tr', {}, h('td', {}, r.name, r.new_patient ? h('span', { class: 'ac-pill st-prep', style: 'margin-left:6px' }, 'nuevo') : ''),
          h('td', {}, r.doc), h('td', {}, fmtDate(r.date)), h('td', {}, `${r.chars} caracteres`), h('td', {}, r.dx || '—')))))) : '',
      rep.rows.length > 50 ? h('p', { class: 'i18-sub' }, `Se muestran 50 de ${rep.rows.length}.`) : '',
      h('div', { class: 'i18-actions' }, save));
  }
}
