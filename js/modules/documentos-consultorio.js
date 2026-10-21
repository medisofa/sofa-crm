/**
 * SOFA · Documentos del consultorio para Secretaria/Capturista.
 * Acceso limitado exclusivamente al flujo A–E. No expone finanzas, tarifas, glosas ni honorarios.
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { emptyView, friendlyError } from '../utils/ui.js';
import { sb } from '../supabase.js';
import { renderCommercialDocs } from './client-commercial.js';

export async function render(main, ctx) {
  const orgId = ctx.membership?.organization_id;
  ctx.setTitle('Documentos del consultorio');

  paint(main, html`
    <div class="page-head">
      <div class="t">
        <h2>Documentos del consultorio</h2>
        <p>Descarga los modelos A–E, completa o firma cuando corresponda y sube la versión del consultorio para revisión de SOFA.</p>
      </div>
    </div>
    <div class="note info">
      <b>Acceso limitado de Secretaria / Capturista.</b><br>
      Esta pantalla solo permite gestionar documentación contractual y operativa A–E. No muestra pagos de ARS, glosas, honorarios, saldos ni tarifarios financieros.
    </div>
    <div class="card" style="margin-top:14px">
      <h2>Documentos A–E</h2>
      <div id="clientDocsPortal"></div>
    </div>`);

  if (!orgId) {
    $('#clientDocsPortal', main).replaceChildren(emptyView('Sin consultorio asignado', 'Tu usuario no tiene una organización activa.'));
    return;
  }

  const { data: org, error } = await sb().rpc('client_document_portal_context', { p_org: orgId });
  if (error || !org) {
    $('#clientDocsPortal', main).replaceChildren(emptyView('No se pudo abrir el portal documental', friendlyError(error || new Error('Consultorio no encontrado.'))));
    return;
  }

  renderCommercialDocs($('#clientDocsPortal', main), org, ctx, []);
}
