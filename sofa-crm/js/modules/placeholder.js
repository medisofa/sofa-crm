/** SOFA · Módulo planificado para una iteración futura */
import { html, render as paint } from '../utils/dom.js';
export async function render(main, { def }) {
  paint(main, html`
    <div class="page-head"><div class="t"><h2>${def.label}</h2><p>Módulo planificado</p></div></div>
    <div class="card">
      <span class="pill info">Llega en la Iteración ${def.iteration}</span>
      <p style="margin:12px 0 0">${def.about || ''}</p>
      <p class="small muted" style="margin:14px 0 0">La base de datos ya tiene las tablas, reglas y permisos de este módulo (Iteración 2). En la Iteración ${def.iteration} se construye la pantalla que los usa.</p>
    </div>`);
}
