/** Inicio del equipo clínico: agenda, estado del día y accesos permitidos. */
import { h, num, note } from '../services/iter18.js';
import { canSee } from '../utils/permissions.js';
import { loadClinicalDashboard, coverageAlert } from '../services/clinical-dashboard.js';

const STATUS = { programada: ['Por confirmar', 'warn'], confirmada: ['Confirmada', 'info'], en_espera: ['En sala', 'warn'], en_consulta: ['En consulta', 'info'], atendida: ['Atendida', 'ok'], no_asistio: ['No asistió', 'bad'] };
const shortDate = (iso) => new Intl.DateTimeFormat('es-DO', { timeZone: 'America/Santo_Domingo', weekday: 'long', day: 'numeric', month: 'long' }).format(new Date(`${iso}T12:00:00-04:00`));
const routeLink = (role, route, label, cls = 'btn') => canSee(route, role) ? h('a', { class: cls, href: `#/${route}` }, label) : null;
const value = (n) => n == null ? '—' : num(n);

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const shell = h('section', { class: 'clinical-home', 'aria-label': 'Inicio del consultorio' });
  root.append(shell);
  const allModules = () => typeof ctx.renderLauncher === 'function'
    ? h('details', { class: 'clinical-modules' }, h('summary', {}, 'Todos mis módulos'), ctx.renderLauncher()) : null;
  let sequence = 0;
  let focusRefresh = false;
  async function draw() {
    const my = ++sequence;
    shell.setAttribute('aria-busy', 'true');
    if (!shell.children.length) shell.append(h('p', { class: 'clinical-empty', role: 'status' }, 'Consultando la agenda de hoy…'));
    let data;
    try { data = await loadClinicalDashboard(ctx); }
    catch (_) {
      if (my !== sequence || !shell.isConnected) return;
      shell.replaceChildren(note('No se pudo consultar el inicio del consultorio. Intenta actualizar.', 'error'), h('button', { type: 'button', class: 'btn', onclick: draw }, 'Reintentar'));
      shell.setAttribute('aria-busy', 'false');
      return;
    }
    if (my !== sequence || !shell.isConnected) return;
    const refreshing = focusRefresh; focusRefresh = false;
    const refresh = h('button', { type: 'button', id: 'clinical-refresh', class: 'btn', onclick: () => { focusRefresh = true; refresh.disabled = true; draw(); } }, 'Actualizar');
    shell.replaceChildren(h('header', { class: 'clinical-head' },
      h('div', { class: 'clinical-heading' }, h('h2', {}, 'Tu consultorio, hoy'),
        h('p', { class: 'clinical-summary' }, `${shortDate(data.date)} · ${ctx.viewAs?.orgName || ctx.membership?.organization || 'Consultorio activo'}`),
        h('p', { class: 'clinical-scope' }, data.scopeLabel)),
      h('div', { class: 'clinical-head-actions' }, routeLink(ctx.role, 'agenda', 'Abrir agenda', 'btn primary'), refresh)));
    if (data.unavailable) {
      shell.append(note(data.unavailable, 'info'), shortcuts(ctx.role), allModules());
      shell.setAttribute('aria-busy', 'false');
      if (refreshing) refresh.focus();
      return;
    }
    const metricDefs = [
      ['Citas de hoy', data.metrics.total, 'Excluye las canceladas', 'agenda'],
      ['En sala de espera', data.metrics.waiting, 'Pacientes que ya llegaron', 'flujo-pacientes'],
      ['En consulta', data.metrics.inConsultation, 'Atención en curso', 'flujo-pacientes'],
      ['Atendidas hoy', data.metrics.attended, 'Citas marcadas como atendidas', 'agenda']
    ];
    shell.append(h('div', { class: 'clinical-kpis', 'aria-label': 'Resumen de hoy' }, ...metricDefs.map(([label, count, hint, route]) => {
      const attrs = { class: 'clinical-kpi', 'aria-label': `${label}: ${count == null ? 'No disponible' : count}` };
      const kids = [h('strong', {}, value(count)), h('span', {}, label), h('small', {}, count == null ? 'No disponible' : hint)];
      return canSee(route, ctx.role) ? h('a', { ...attrs, href: `#/${route}` }, ...kids) : h('div', attrs, ...kids);
    })));
    const agenda = h('section', { class: 'card clinical-agenda', 'aria-labelledby': 'clinical-agenda-title' },
      h('div', { class: 'clinical-section-head' }, h('h3', { id: 'clinical-agenda-title' }, 'Agenda de hoy'), h('span', { class: 'small muted' }, `${value(data.totalAppointments)} cita(s)`)));
    if (data.errors.agenda) agenda.append(h('p', { class: 'clinical-empty', role: 'status' }, 'Agenda no disponible. Actualiza para volver a consultar.'));
    else if (!data.appointments.length) agenda.append(h('p', { class: 'clinical-empty' }, 'No hay citas registradas para hoy dentro de tu acceso.'));
    else {
      agenda.append(h('ol', { class: 'clinical-list', 'aria-label': 'Citas de hoy' }, ...data.appointments.map((a) => {
        const [label, tone] = STATUS[a.status] || [a.status || 'Sin estado', ''];
        return h('li', { class: 'clinical-row' },
          h('time', { class: 'clinical-time', datetime: a.appointment_time ? `${data.date}T${a.appointment_time}` : data.date }, a.appointment_time ? String(a.appointment_time).slice(0, 5) : 'Sin hora'),
          h('div', { class: 'clinical-person' }, h('strong', {}, a.patient_name || 'Paciente'), h('small', {}, a.providers?.full_name || 'Médico del consultorio')),
          h('span', { class: `pill clinical-status ${tone}` }, label));
      })));
      agenda.append(h('p', { class: 'small muted' }, `Mostrando ${data.appointments.length} de ${data.totalAppointments} citas de hoy, en orden de horario.`));
    }
    agenda.append(routeLink(ctx.role, 'agenda', 'Ver agenda completa', 'btn'));
    const nextCard = buildNextCard(data, ctx.role);
    const pending = h('section', { class: 'card clinical-pending', 'aria-labelledby': 'clinical-pending-title' },
      h('h3', { id: 'clinical-pending-title' }, 'Pendientes de hoy'),
      h('p', {}, data.metrics.pendingConfirmation == null ? 'Confirmaciones no disponibles.' : `${num(data.metrics.pendingConfirmation)} cita(s) por confirmar.`),
      h('p', { class: 'small muted' }, 'Revisa las citas programadas y el flujo de pacientes antes de continuar.'),
      routeLink(ctx.role, 'agenda', 'Revisar citas'), routeLink(ctx.role, 'flujo-pacientes', 'Ver plan del día'));
    shell.append(h('div', { class: 'clinical-grid' }, agenda, h('aside', { class: 'clinical-side', 'aria-label': 'Pendientes y accesos' }, nextCard, pending, shortcuts(ctx.role))));
    shell.append(allModules());
    if (Object.keys(data.errors).length) shell.append(h('p', { class: 'clinical-empty', role: 'status' }, 'Algunos datos no están disponibles. Los guiones indican información pendiente de consultar.'));
    shell.setAttribute('aria-busy', 'false');
    if (refreshing) refresh.focus();
  }
  await draw();
}

function buildNextCard(data, role) {
  const a = data.nextAppointment;
  if (!a && !data.errors.next) return null;
  const card = h('section', { class: 'card clinical-next', 'aria-labelledby': 'clinical-next-title' },
    h('h3', { id: 'clinical-next-title' }, 'Siguiente cita'));
  if (data.errors.next || !a) {
    card.append(h('p', { class: 'clinical-empty' }, data.errors.next || 'No hay citas pendientes por atender hoy.'));
    return card;
  }
  const time = a.appointment_time ? String(a.appointment_time).slice(0, 5) : 'Sin hora';
  const [label, tone] = STATUS[a.status] || [a.status || 'Sin estado', ''];
  const alert = coverageAlert(a);
  card.append(
    h('div', { class: 'clinical-next-body' },
      h('time', { class: 'clinical-next-time' }, time),
      h('div', { class: 'clinical-next-info' },
        h('strong', {}, a.patient_name || 'Paciente'),
        h('small', {}, a.providers?.full_name || 'Médico del consultorio'),
        h('span', { class: `pill clinical-status ${tone}` }, label))));
  if (alert) card.append(h('p', { class: `clinical-next-alert ${alert.tone}`, role: 'status' }, alert.text));
  card.append(routeLink(role, 'agenda', 'Abrir agenda', 'btn'));
  return card;
}

function shortcuts(role) {
  const defs = [['pacientes', 'Pacientes'], ['historia-clinica', 'Historia clínica'], ['captura', 'Captura rápida'], ['seguimiento-hoy', 'Seguimiento de hoy'], ['flujo-pacientes', 'Plan del día'], ['mi-panel', 'Mi panel de cobros']];
  return h('section', { class: 'card clinical-access', 'aria-label': 'Accesos rápidos' }, h('h3', {}, 'Accesos rápidos'),
    h('div', { class: 'clinical-shortcuts' }, ...defs.map(([route, label]) => routeLink(role, route, label))));
}
