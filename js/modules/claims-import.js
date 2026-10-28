/**
 * SOFA 1.7.5 · Módulo de Importación y Carga Masiva desde Excel
 * Integra el procesamiento local de SheetJS (.xlsx) directamente en el navegador.
 * Las filas se validan y se insertan vía la RPC import_service_lines (organization_id
 * y validación de tarifa/duplicados los fija el servidor a partir de la radicación elegida;
 * nunca se insertan columnas crudas del Excel directo en service_lines).
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError } from '../utils/ui.js';
import { listSubmissions, importLines } from '../services/submissions.js';

export async function render(container, ctx) {
  ctx.setTitle('Carga Masiva de Reclamaciones');

  const { data: submissions } = await listSubmissions({ group: 'preparacion', size: 100 });

  paint(container, html`
    <div class="page-card" style="max-width: 800px; margin: 20px auto; padding: 25px;">
      <div class="card-header" style="margin-bottom: 20px;">
        <h2 style="color: #1c7ed6; margin: 0 0 10px 0;">Importador de Archivos Excel (.xlsx)</h2>
        <p class="text-muted small">Carga líneas de servicio masivamente dentro de una radicación en preparación. Columnas esperadas: codigo, fecha (DD/MM/AAAA), cantidad, monto, cedula, nss, autorizacion, afiliado.</p>
      </div>

      <div style="margin-bottom: 15px;">
        <label for="submissionSelect" style="display:block; font-weight:bold; margin-bottom:6px;">Radicación destino</label>
        <select id="submissionSelect" class="input" style="width:100%">
          <option value="">Seleccione una radicación en preparación…</option>
          ${(submissions || []).map((s) => html`<option value="${s.id}">${s.folio || s.id} · ${s.provider_name || ''} · ${s.ars_name || ''}</option>`)}
        </select>
      </div>

      <div class="upload-zone" style="border: 2px dashed #3498db; padding: 30px; text-align: center; background: #f8f9fa; border-radius: 8px;">
        <input type="file" id="excelFile" accept=".xlsx, .xls" style="display: none;" />
        <button class="btn secondary" id="btnSelectFile">Seleccionar Archivo de Excel</button>
        <div id="fileInfo" style="margin-top: 15px; font-weight: bold; color: #2b2b2b;"></div>
      </div>

      <div id="importResult" style="margin-top: 15px;"></div>

      <div class="actions-bar" style="margin-top: 25px; display: flex; justify-content: flex-end; gap: 10px;">
        <button class="btn" id="btnCancelImport" style="background: #e0e0e0;">Limpiar</button>
        <button class="btn primary" id="btnExecuteBulkInsert" disabled>Procesar e Insertar</button>
      </div>
    </div>
  `);

  let rawRows = null;

  $('#btnSelectFile').onclick = () => $('#excelFile').click();

  $('#excelFile').onchange = (e) => {
    const file = e.target.files[0];
    if (!file) return;

    $('#fileInfo').textContent = `Cargando: ${file.name}...`;
    const reader = new FileReader();

    reader.onload = (evt) => {
      try {
        const data = new Uint8Array(evt.target.result);
        const workbook = window.XLSX.read(data, { type: 'array' });
        const sheetName = workbook.SheetNames[0];
        const worksheet = workbook.Sheets[sheetName];

        rawRows = window.XLSX.utils.sheet_to_json(worksheet);

        if (rawRows && rawRows.length > 0) {
          paint($('#fileInfo'), html`<span style="color: #2b8a3e;">✔ ${file.name} listo (${rawRows.length} registros detectados)</span>`);
          $('#btnExecuteBulkInsert').disabled = false;
        } else {
          throw new Error('La primera hoja del archivo no contiene datos o faltan los encabezados.');
        }
      } catch (err) {
        paint($('#fileInfo'), html`<span style="color: #c92a2a;">❌ Error: ${err.message}</span>`);
        $('#btnExecuteBulkInsert').disabled = true;
        rawRows = null;
      }
    };
    reader.readAsArrayBuffer(file);
  };

  $('#btnCancelImport').onclick = () => {
    $('#excelFile').value = '';
    $('#fileInfo').textContent = '';
    $('#importResult').replaceChildren();
    $('#btnExecuteBulkInsert').disabled = true;
    rawRows = null;
  };

  $('#btnExecuteBulkInsert').onclick = async () => {
    if (!rawRows || rawRows.length === 0) return;
    const submissionId = $('#submissionSelect').value;
    if (!submissionId) { toast('Seleccione la radicación destino antes de importar.', 'bad'); return; }

    try {
      $('#btnExecuteBulkInsert').disabled = true;
      $('#btnExecuteBulkInsert').textContent = 'Subiendo bloques...';

      const result = await importLines(submissionId, rawRows, true);

      paint($('#importResult'), html`<div class="note ${result.errors > 0 ? 'warn' : 'ok'}">
        Insertadas: ${result.inserted} · Duplicados omitidos: ${result.duplicates} · Con error: ${result.errors}
        ${result.errors > 0 ? html`<ul>${(result.rows || []).filter((r) => !r.ok).slice(0, 20).map((r) => html`<li>Fila ${r.row}: ${r.error}</li>`)}</ul>` : ''}
      </div>`);

      toast(`Carga procesada: ${result.inserted} insertadas, ${result.duplicates} duplicadas, ${result.errors} con error.`);
      $('#excelFile').value = '';
      $('#fileInfo').textContent = '';
      rawRows = null;
    } catch (error) {
      alert(`Fallo en la carga masiva: ${friendlyError(error)}`);
    } finally {
      $('#btnExecuteBulkInsert').disabled = false;
      $('#btnExecuteBulkInsert').textContent = 'Procesar e Insertar';
    }
  };
}
