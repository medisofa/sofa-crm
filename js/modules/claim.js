import { html, \$ } from '../utils/dom.js';
import { toast, friendlyError } from '../utils/ui.js';
import { insertBulkClaims } from '../services/claims.js';

export async function render(container, ctx) {
  ctx.setTitle('Gestión de Reclamaciones');

  const importComponent = html`
    <div class="card-import" style="background: #f8f9fa; padding: 20px; border-radius: 6px; margin-bottom: 20px; border: 2px dashed #3498db;">
      <h3 style="margin-top:0; color:#2c3e50;">Importador Masivo de Reclamaciones (.xlsx)</h3>
      <input type="file" id="excelFile" accept=".xlsx, .xls" style="margin-bottom:10px;" />
      <div id="importFeedback" style="font-size:13px; font-weight:bold; margin-bottom:10px;"></div>
      <button class="btn primary" id="btnUploadBulk" disabled>Cargar Registros a Supabase</button>
    </div>
  `;

  container.innerHTML = '';
  container.appendChild(importComponent);

  let workbookRows = null;

  \$('#excelFile').onchange = (e) => {
    const file = e.target.files;
    if (!file) return;

    \$('#importFeedback').textContent = `Cargando: ${file.name}...`;
    const reader = new FileReader();

    reader.onload = (evt) => {
      try {
        const data = new Uint8Array(evt.target.result);
        const workbook = window.XLSX.read(data, { type: 'array' });
        const sheetName = workbook.SheetNames;
        const worksheet = workbook.Sheets[sheetName];
        
        workbookRows = window.XLSX.utils.sheet_to_json(worksheet);

        if (workbookRows && workbookRows.length > 0) {
          \$('#importFeedback').innerHTML = `<span style="color:#27ae60;">✔ Archivo listo: ${workbookRows.length} reclamaciones detectadas.</span>`;
          \$('#btnUploadBulk').disabled = false;
        } else {
          throw new Error('La primera hoja del archivo no contiene filas válidas.');
        }
      } catch (err) {
        \$('#importFeedback').innerHTML = `<span style="color:#c0392b;">❌ Error al procesar: ${err.message}</span>`;
        \$('#btnUploadBulk').disabled = true;
        workbookRows = null;
      }
    };
    reader.readAsArrayBuffer(file);
  };

  \$('#btnUploadBulk').onclick = async () => {
    if (!workbookRows) return;
    try {
      \$('#btnUploadBulk').disabled = true;
      \$('#btnUploadBulk').textContent = 'Escribiendo en Supabase...';
      
      await insertBulkClaims(workbookRows);
      
      toast('¡Carga masiva completada con éxito!');
      \$('#excelFile').value = '';
      \$('#importFeedback').innerHTML = '';
    } catch (err) {
      alert('Error de persistencia: ' + friendlyError(err));
      \$('#btnUploadBulk').disabled = false;
      \$('#btnUploadBulk').textContent = 'Cargar Registros a Supabase';
    }
  };
}
