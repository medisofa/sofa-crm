/** SOFA · 2.2 · 2.6.1 · Renegociación de tarifarios (solo personal SOFA). Las ARS contratan por tiempo indefinido:
 *  cada tarifario se revisa a los 2 años de su última vigencia para ofrecer al cliente el servicio de renegociación. */
import { html, render as paint, $, updateSidebarBadges } from '../utils/dom.js';
import { rpc } from '../services/iter18.js';
import { mountExpiring } from './tarifario-import.js';

export async function render(root) {
  root.replaceChildren();
  paint(root, html`
    <div class="page-head"><div class="t">
      <h2>Alertas de vencimiento ARS</h2>
      <p>Tarifarios que cumplen 2 años o contratos próximos a vencer: oportunidades de renegociación. Solo visible para el equipo SOFA.</p>
    </div></div>
    <div class="toolbar" style="margin-bottom:12px">
      <label for="vc-days">Mostrar los que llegan a revisión en</label>
      <select class="input" id="vc-days" style="width:auto">
        ${[30, 60, 90, 120, 180, 365].map((d) => html`<option value="${d}" ${d === 120 ? html`selected` : html``}>${d} días</option>`)}
      </select>
    </div>
    <div id="vc-box"></div>`);
  const draw = () => mountExpiring($('#vc-box', root), { days: Number($('#vc-days', root).value) });
  $('#vc-days', root).addEventListener('change', draw);
  await draw();
  // Alimentar badge de sidebar con la cantidad de tarifarios próximos a vencer (30 días)
  try {
    const exp = await rpc('tariffs_expiring', { p_days: 30 });
    if (Array.isArray(exp) && exp.length > 0) updateSidebarBadges({ vencimientos: exp.length });
  } catch { /* no crítico */ }
}
