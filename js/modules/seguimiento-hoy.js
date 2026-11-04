/** Mi Día · Accesos del médico. No almacena información clínica en el navegador. */
import { html, render as paint } from '../utils/dom.js';
import { canSee } from '../utils/permissions.js';

export async function render(root, ctx = {}) {
  if (ctx.role !== 'client') {
    paint(root, html`<div class="note bad" role="alert">Esta vista está disponible para el médico.</div>`);
    return;
  }
  const links = [
    ['agenda', 'Agenda del consultorio', 'Revise las citas y seleccione el consultorio en el que va a trabajar.'],
    ['flujo-pacientes', 'Plan del día', 'Consulte los pacientes agendados, confirmados, en sala, en consulta y atendidos.'],
    ['mensajes', 'Mensajes a pacientes', 'Abra la cola de mensajes y revise su estado de envío.'],
    ['seguimiento', 'Seguimiento después de la cita', 'Configure los mensajes de seguimiento. Guardar esta configuración puede activar envíos.'],
    ['novedades', 'Novedades SoFa', 'Consulte las novedades disponibles en SoFa.']
  ].filter(([route]) => canSee(route, ctx.role));
  paint(root, html`<div class="page-head"><div class="t"><h2>Seguimiento de hoy</h2><p>Su agenda, el recorrido de los pacientes y sus herramientas de seguimiento en un solo lugar.</p></div></div>
    <div class="grid two">${links.map(([route,title,description]) => html`<section class="card"><h3>${title}</h3><p>${description}</p><a class="btn" href="#/${route}">Abrir ${title}</a></section>`)}</div>
    <section class="card" style="margin-top:16px"><h3>Próximas funciones · En construcción</h3>
      <p>Notas y recordatorios personales, cuentas por pagar elegidas por el médico y noticias filtradas por especialidad.</p>
      <p class="small muted">Estas funciones todavía no permiten registrar información ni configurar alertas.</p></section>`);
}
