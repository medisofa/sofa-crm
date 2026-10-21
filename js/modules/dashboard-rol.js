/** SOFA · 21-B · Dashboard según el rol. Primera página para todos los usuarios.
 *  Muestra una sección por cada rol del usuario (lo decide la base con my_dashboard) y accesos a sus módulos.
 *  onOpen(code) lo provee el router para abrir un módulo desde un acceso directo. */
import { rpc, h, money, num, note, guarded } from '../services/iter18.js';
import { visibleNav, canSee } from '../utils/permissions.js';

const LABEL = { agenda: 'Agenda', captura_rapida: 'Captura rápida', reclamaciones: 'Reclamaciones', trabajo_hoy: 'Trabajo de hoy',
  nueva_cita: 'Nueva cita', retiros_fisicos: 'Retiros físicos', radicacion: 'Radicación' };
const fmt = (k) => (k.unit === 'RD$' ? money(k.value) : num(k.value));

const KPI_ROUTE = {
  citas_hoy: ['agenda', 'Abrir Agenda'],
  atendidas_mes: ['pacientes', 'Abrir Pacientes'],
  reclamado_mes: ['reclamaciones', 'Abrir Reclamaciones'],
  por_cobrar: ['mi-dinero', 'Abrir Mi dinero'],
  deuda_sofa: ['mi-cuenta-sofa', 'Abrir Mi cuenta con SOFA'],

  citas_manana: ['agenda', 'Abrir Agenda'],
  sin_confirmar: ['verificacion', 'Abrir Verificación de mañana'],
  whatsapp_pendientes: ['mensajes', 'Abrir Mensajes'],

  borradores: ['radicaciones', 'Abrir Radicaciones'],
  en_depuracion: ['reclamaciones', 'Abrir Reclamaciones'],
  pendiente_documentos: ['expediente', 'Abrir Expediente digital'],
  listos_radicar: ['radicaciones', 'Abrir Radicaciones'],

  abiertas: ['glosas', 'Abrir Glosas'],
  vencen_7d: ['reconsideracion', 'Abrir Reconsideración de glosas'],
  vencidas: ['reconsideracion', 'Abrir Reconsideración de glosas'],
  arbitraje: ['glosas', 'Abrir Glosas'],

  oportunidades: ['oportunidades', 'Abrir Oportunidades'],
  pipeline_ponderado: ['oportunidades', 'Abrir Oportunidades'],
  acciones_vencidas: ['oportunidades', 'Abrir Oportunidades'],
  prospectos_30d: ['prospectos', 'Abrir Prospectos'],

  cartera_ars: ['cartera', 'Abrir Cartera'],
  honorarios_vencidos: ['honorarios', 'Abrir Honorarios SOFA'],
  clientes_activos: ['clientes', 'Abrir Clientes'],
  alertas_abiertas: ['mi-bandeja', 'Abrir Mi bandeja']
};
const kpiRoute = (k, role) => {
  const nav = KPI_ROUTE[k?.code];
  return nav && canSee(nav[0], role) ? nav : null;
};

// Código del módulo (base de datos) → ruta del menú (js/router.js)
const ROUTE = { agenda: 'agenda', captura_rapida: 'captura', reclamaciones: 'reclamaciones', trabajo_hoy: 'hoy',
  nueva_cita: 'agenda', retiros_fisicos: 'retiros', radicacion: 'radicaciones' };
const goTo = (c) => { location.hash = `#/${ROUTE[c] || c}`; };

export async function render(root, { onOpen = goTo, role = null } = {}) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  root.append(box);   // el título «Mi dashboard» ya lo muestra la barra superior
  const data = await guarded(box, () => rpc('my_dashboard'));
  if (!data) { if (role) box.append(launcher(role)); return; }   // aunque fallen las cifras, los módulos siguen a mano
  if (!data.sections || !data.sections.length) {
    box.replaceChildren(note('Su usuario todavía no tiene un rol asignado. Pida al Administrador que se lo asigne.'));
    return;
  }
  for (const s of data.sections) {
    const card = h('section', { class: 'i18-card', 'aria-label': s.title }, h('h3', {}, s.title));
    if (s.alert) card.append(note(s.alert.message, s.alert.level === 'vencido' ? 'error' : 'info'));
    card.append(h('div', { class: 'i18-kpis' }, s.kpis.map((k) => {
      const nav = kpiRoute(k, role);
      const route = nav?.[0];
      const title = nav?.[1];
      const children = [
        route ? h('span', { class: 'dashboard-kpi-go', 'aria-hidden': 'true' }, '↗') : null,
        h('div', { class: 'i18-kpi-v' }, fmt(k)),
        h('div', { class: 'i18-kpi-l' }, k.label)
      ];
      return route
        ? h('a', { class: `i18-kpi i18-lvl-${k.level} dashboard-kpi dashboard-kpi-link`, href: `#/${route}`, title, 'aria-label': `${k.label}. ${title}` }, ...children)
        : h('div', { class: `i18-kpi i18-lvl-${k.level} dashboard-kpi` }, ...children);
    })));
    if (s.shortcuts && s.shortcuts.length && typeof onOpen === 'function') {
      card.append(h('div', { class: 'i18-actions', role: 'group', 'aria-label': 'Accesos directos' }, s.shortcuts.map((c) =>
        h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => onOpen(c) }, LABEL[c] || c))));
    }
    box.append(card);
  }
  if (role) box.append(launcher(role));
}

/** 2.0 · «Mis módulos»: los grupos del menú del rol como tarjetas, para abrir cualquier módulo con un toque. */
function launcher(role) {
  const groups = visibleNav(role).filter((g) => g.group !== 'Mi cuenta')
    .map((g) => ({ ...g, items: g.items.filter((i) => i.route !== 'mi-dashboard') })).filter((g) => g.items.length);
  return h('section', { class: 'v2-launcher', 'aria-label': 'Mis módulos' },
    h('h3', {}, 'Mis módulos'),
    h('div', { class: 'v2-launch-grid' }, groups.map((g) =>
      h('div', { class: 'v2-launch-card' }, h('h4', {}, g.group),
        h('ul', {}, g.items.map((i) => h('li', {}, h('a', { href: `#/${i.route}` }, i.label))))))));
}
