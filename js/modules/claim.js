import { html, render, \$ } from '../utils/dom.js';
import { loadingView, emptyView, errorView, toast, friendlyError } from '../utils/ui.js';
import { date, money } from '../utils/formatters.js';
import { claimStatus } from '../utils/constants.js';
import { sb } from '../supabase.js';

export async function render(main, ctx) {
  ctx.setTitle('Reclamaciones');
  render(main, html`<div id="claims-container">${loadingView(4)}</div>`);
  
  const box = \$('#claims-container', main);

  async function loadClaims() {
    const { data, error } = await sb()
      .from('service_lines')
      .select('*')
      .order('created_at', { ascending: false });
      
    if (error) throw error;
    return data;
  }

  async function refresh() {
    try {
      const claims = await loadClaims();
      if (!claims || claims.length === 0) {
        render(box, emptyView('No hay reclamaciones', 'No se encontraron registros en el sistema.'));
        return;
      }
      
      render(box, html`
        <div class="table-wrap">
          <table class="t">
            <thead>
              <tr>
                <th>Folio</th>
                <th>Paciente</th>
                <th>Servicio</th>
                <th>ARS</th>
                <th>Fecha</th>
                <th class="n">Monto</th>
                <th>Estado</th>
              </tr>
            </thead>
            <tbody>
              ${claims.map(c => {
                const [lbl, cls] = claimStatus(c.claim_status || 'capturada');
                return html`
                  <tr>
                    <td><a href="#/reclamaciones/\({c.id}" class="mono">\){c.folio || '—'}</a></td>
                    <td><b>\${c.patient_name || '—'}</b><div class="small muted">\${c.patient_doc || ''}</div></td>
                    <td>\${c.service_name || '—'}</td>
                    <td>\${c.ars_name || '—'}</td>
                    <td>\${date(c.service_date)}</td>
                    <td class="n font-mono">\${money(c.claimed || 0)}</td>
                    <td><span class="pill \({cls}">\){lbl}</span></td>
                  </tr>
                `;
              })}
            </tbody>
          </table>
        </div>
      `);
    } catch (err) {
      console.error(err);
      render(box, errorView(err));
    }
  }

  refresh();
}
