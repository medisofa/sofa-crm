/**
 * SOFA 1.7.5 · Módulo de Importación y Carga Masiva desde Excel
 * Integra el procesamiento local de SheetJS (.xlsx) directamente en el navegador.
 */
import { html, \$ } from '../utils/dom.js';
import { toast, friendlyError } from '../utils/ui.js';
import { sb } from '../supabase.js';

export async function render(container, ctx) {
  ctx.setTitle('Carga Masiva de Reclamaciones');

  render(container, html`
    <div class="page-card" style="max-width: 800px; margin: 20px auto; padding: 25px;">
      <div class="card-header" style="margin-bottom: 20px;">
        <h2 style="color: #1c7ed6; margin: 0 0 10px 0;">Importador de Archivos Excel (.xlsx)</h2>
        <p class="text-muted small">Carga reclamaciones médicas masivamente en el bloque operativo del sistema.</p>
      </div>

      <div class="upload-zone" style="border: 2px dashed #3498db; padding: 30px; text-align: center; background: #f8f9fa; border-radius: 8px;">
        <input type="file" id="excelFile" accept=".xlsx, .xls" style="display: none;" />
        <button class="btn secondary" id="btnSelectFile">Seleccionar Archivo de Excel</button>
        <div id="fileInfo" style="margin-top: 15px; font-weight: bold; color: #2b2b2b;"></div>
      </div>

      <div class="actions-bar" style="margin-top: 25px; display: flex; justify-content: flex-end; gap: 10px;">
        <button class="btn" id="btnCancelImport" style="background: #e0e0e0;">Limpiar</button>
        <button class="btn primary" id="btnExecuteBulkInsert" disabled>Procesar e Insertar en Supabase</button>
      </div>
    </div>
  `);

  let rawRows = null;

  \$('#btnSelectFile').onclick = () => \$('#excelFile').click();

  \$('#excelFile').onchange = (e) => {
    const file = e.target.files[0];
    if (!file) return;

    \$('#fileInfo').textContent = `Cargando: ${file.name}...`;
    const reader = new FileReader();

    reader.onload = (evt) => {
      try {
        const data = new Uint8Array(evt.target.result);
        const workbook = window.XLSX.read(data, { type: 'array' });
        const sheetName = workbook.SheetNames[0];
        const worksheet = workbook.Sheets[sheetName];
        
        rawRows = window.XLSX.utils.sheet_to_json(worksheet);

        if (rawRows && rawRows.length > 0) {
          \$('#fileInfo').innerHTML = `<span style="color: #2b8a3e;">✔ ${file.name} listo (${rawRows.length} registros detectados)</span>`;
          \$('#btnExecuteBulkInsert').disabled = false;
        } else {
          throw new Error('La primera hoja del archivo no contiene datos o faltan los encabezados.');
        }
      } catch (err) {
        \$('#fileInfo').innerHTML = `<span style="color: #c92a2a;">❌ Error: ${err.message}</span>`;
        \$('#btnExecuteBulkInsert').disabled = true;
        rawRows = null;
      }
    };
    reader.readAsArrayBuffer(file);
  };

  \$('#btnCancelImport').onclick = () => {
    \$('#excelFile').value = '';
    \$('#fileInfo').textContent = '';
    \$('#btnExecuteBulkInsert').disabled = true;
    rawRows = null;
  };

  \$('#btnExecuteBulkInsert').onclick = async () => {
    if (!rawRows || rawRows.length === 0) return;

    try {
      \$('#btnExecuteBulkInsert').disabled = true;
      \$('#btnExecuteBulkInsert').textContent = 'Subiendo bloques...';

      // Estructuración masiva en service_lines (Tabla core de SOFA)
      const { data, error } = await sb()
        .from('service_lines')
        .insert(rawRows);

      if (error) throw error;

      toast(`¡Éxito! Se integraron ${rawRows.length} reclamaciones correctamente.`);
      \$('#btnCancelImport').click();
    } catch (error) {
      alert(`Fallo en la carga masiva: ${friendlyError(error)}`);
      \$('#btnExecuteBulkInsert').disabled = false;
      \$('#btnExecuteBulkInsert').textContent = 'Procesar e Insertar en Supabase';
    }
  };
}
