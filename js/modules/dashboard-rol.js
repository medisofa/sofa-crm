/** SOFA · 21-B · Dashboard según el rol. Primera página para todos los usuarios.
 *  Muestra una sección por cada rol del usuario (lo decide la base con my_dashboard) y accesos a sus módulos.
 *  onOpen(code) lo provee el router para abrir un módulo desde un acceso directo. */
import { rpc, h, money, num, note, guarded } from '../services/iter18.js';
import { visibleNav } from '../utils/permissions.js';

const LABEL = { agenda: 'Agenda', captura_rapida: 'Captura rápida', reclamaciones: 'Reclamaciones', trabajo_hoy: 'Trabajo de hoy',
  nueva_cita: 'Nueva cita', retiros_fisicos: 'Retiros físicos', radicacion: 'Radicación' };
const fmt = (k) => (k.unit === 'RD$' ? money(k.value) : num(k.value));

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
    card.append(h('div', { class: 'i18-kpis' }, s.kpis.map((k) =>
      h('div', { class: `i18-kpi i18-lvl-${k.level}` }, h('div', { class: 'i18-kpi-v' }, fmt(k)), h('div', { class: 'i18-kpi-l' }, k.label)))));
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
