import { html, \$ } from '../utils/dom.js';
import { toast, friendlyError } from '../utils/ui.js';
import { sb } from '../supabase.js';

export async function render(container, ctx) {
  ctx.setTitle('Gestión de Reclamaciones');

  // Inyección limpia del componente de carga masiva usando SheetJS (XLSX)
  container.innerHTML = '';
  const importCard = html`
    <div class="card" style="background: #f8f9fa; padding: 20px; border-radius: 6px; margin-bottom: 20px; border: 2px dashed #3498db;">
      <h3 style="margin-top:0; color:#2c3e50;">Importador Masivo de Reclamaciones (.xlsx)</h3>
      <p class="small muted">Selecciona un archivo de Excel para mapear e inyectar registros directamente a la base de datos.</p>
      <input type="file" id="excelFile" accept=".xlsx, .xls" style="margin-bottom:10px;" />
      <div id="importFeedback" style="font-size:13px; font-weight:bold; margin-bottom:10px;"></div>
      <button class="btn primary" id="btnUploadBulk" disabled>Cargar Registros a Supabase</button>
    </div>
    <div class="card" style="margin-top: 15px;">
      <h2>Listado Operativo</h2>
      <p class="small muted">Utiliza la barra superior o las opciones de fila para auditar los expedientes médicos.</p>
      <div id="claimsListTable"></div>
    </div>
  `;

  container.appendChild(importCard);

  let workbookRows = null;

  // Lógica de escucha y lectura asíncrona del archivo Excel
  \$('#excelFile').onchange = (e) => {
    const file = e.target.files[0];
    if (!file) return;

    \$('#importFeedback').textContent = `Procesando: ${file.name}...`;
    const reader = new FileReader();

    reader.onload = (evt) => {
      try {
        const data = new Uint8Array(evt.target.result);
        const workbook = window.XLSX.read(data, { type: 'array' });
        const sheetName = workbook.SheetNames[0];
        const worksheet = workbook.Sheets[sheetName];
        
        workbookRows = window.XLSX.utils.sheet_to_json(worksheet);

        if (workbookRows && workbookRows.length > 0) {
          \$('#importFeedback').innerHTML = `<span style="color:#27ae60;">✔ Archivo listo: ${workbookRows.length} filas detectadas.</span>`;
          \$('#btnUploadBulk').disabled = false;
        } else {
          throw new Error('La primera hoja del archivo Excel no contiene registros.');
        }
      } catch (err) {
        \$('#importFeedback').innerHTML = `<span style="color:#c0392b;">❌ Error al leer el archivo: ${err.message}</span>`;
        \$('#btnUploadBulk').disabled = true;
        workbookRows = null;
      }
    };
    reader.readAsArrayBuffer(file);
  };

  // Despacho masivo por lotes hacia Supabase en la tabla operativa de SOFA
  \$('#btnUploadBulk').onclick = async () => {
    if (!workbookRows) return;
    try {
      \$('#btnUploadBulk').disabled = true;
      \$('#btnUploadBulk').textContent = 'Escribiendo en base de datos...';
      
      const { error } = await sb()
        .from('service_lines')
        .insert(workbookRows);

      if (error) throw error;
      
      toast('¡Carga masiva completada con éxito!', 'ok');
      \$('#excelFile').value = '';
      \$('#importFeedback').innerHTML = '';
      \$('#btnUploadBulk').disabled = true;
    } catch (err) {
      alert('Error de inserción en lote: ' + friendlyError(err));
      \$('#btnUploadBulk').disabled = false;
      \$('#btnUploadBulk').textContent = 'Cargar Registros a Supabase';
    }
  };
}
