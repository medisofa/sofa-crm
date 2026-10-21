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

const VIEW_META = {
  operativo: { label: 'Operativo', hint: 'Pendientes, acciones y accesos directos.' },
  ejecutivo: { label: 'Ejecutivo', hint: 'Indicadores y alertas para tomar decisiones.' },
  visual: { label: 'Visual', hint: 'Tarjetas amplias y lectura rápida del estado.' }
};

const defaultView = (role) => role === 'client' ? 'visual' : (['super_admin','admin'].includes(role) ? 'ejecutivo' : 'operativo');

function kpiNode(k, role, cls = '') {
  const nav = kpiRoute(k, role);
  const route = nav?.[0];
  const title = nav?.[1];
  const kids = [
    route ? h('span', { class: 'dashboard-kpi-go', 'aria-hidden': 'true' }, '↗') : null,
    h('div', { class: 'i18-kpi-v' }, fmt(k)),
    h('div', { class: 'i18-kpi-l' }, k.label)
  ];
  return route
    ? h('a', { class: `i18-kpi i18-lvl-${k.level} dashboard-kpi dashboard-kpi-link ${cls}`.trim(), href: `#/${route}`, title, 'aria-label': `${k.label}. ${title}` }, ...kids)
    : h('div', { class: `i18-kpi i18-lvl-${k.level} dashboard-kpi ${cls}`.trim() }, ...kids);
}

function viewSelector(current, onChange) {
  return h('section', { class: 'dash-viewbar', 'aria-label': 'Vista del dashboard' },
    h('div', { class: 'dash-viewbar-copy' },
      h('strong', {}, 'Vista del dashboard'),
      h('span', {}, VIEW_META[current]?.hint || 'Elige cómo quieres ver la información.')),
    h('div', { class: 'dash-view-switch', role: 'group', 'aria-label': 'Seleccionar vista' },
      ...Object.entries(VIEW_META).map(([key, meta]) => h('button', {
        class: `dash-view-btn ${current === key ? 'is-active' : ''}`.trim(),
        type: 'button',
        'aria-pressed': String(current === key),
        onclick: () => onChange(key)
      }, meta.label))));
}

function renderOperative(data, role, onOpen) {
  const wrap = h('div', { class: 'dash-layout dash-layout-operativo' });
  for (const s of data.sections) {
    const card = h('section', { class: 'i18-card', 'aria-label': s.title }, h('h3', {}, s.title));
    if (s.alert) card.append(note(s.alert.message, s.alert.level === 'vencido' ? 'error' : 'info'));
    card.append(h('div', { class: 'i18-kpis' }, ...s.kpis.map((k) => kpiNode(k, role)));
    if (s.shortcuts?.length && typeof onOpen === 'function') {
      card.append(h('div', { class: 'i18-actions', role: 'group', 'aria-label': 'Accesos directos' },
        ...s.shortcuts.map((code) => h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => onOpen(code) }, LABEL[code] || code))));
    }
    wrap.append(card);
  }
  return wrap;
}

function renderExecutive(data, role, onOpen) {
  const wrap = h('div', { class: 'dash-layout dash-layout-ejecutivo' });
  const all = data.sections.flatMap((s) => s.kpis.map((k) => ({ ...k, section: s.title })));
  const alerts = data.sections.filter((s) => s.alert);
  const hero = h('section', { class: 'i18-card dash-exec-hero' },
    h('div', { class: 'dash-section-head' },
      h('div', {}, h('h3', {}, 'Resumen ejecutivo'), h('p', { class: 'dash-sub' }, 'Indicadores consolidados de las áreas que puedes gestionar.'))),
    h('div', { class: 'dash-exec-kpis' }, ...all.map((k) => kpiNode(k, role, 'dash-exec-kpi'))));
  wrap.append(hero);
  if (alerts.length) {
    wrap.append(h('section', { class: 'i18-card dash-alerts' }, h('h3', {}, 'Atención prioritaria'),
      ...alerts.map((s) => note(`${s.title}: ${s.alert.message}`, s.alert.level === 'vencido' ? 'error' : 'info'))));
  }
  wrap.append(h('section', { class: 'dash-exec-sections', 'aria-label': 'Lectura por área' },
    ...data.sections.map((s) => h('article', { class: 'i18-card dash-exec-area' },
      h('h4', {}, s.title),
      h('div', { class: 'dash-exec-mini' }, ...s.kpis.map((k) => h('div', {}, h('strong', {}, fmt(k)), h('span', {}, k.label)))),
      s.shortcuts?.length && typeof onOpen === 'function' ? h('div', { class: 'i18-actions' },
        ...s.shortcuts.map((code) => h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => onOpen(code) }, LABEL[code] || code))) : null))));
  return wrap;
}

function renderVisual(data, role, onOpen) {
  const wrap = h('div', { class: 'dash-layout dash-layout-visual' });
  wrap.append(h('section', { class: 'dash-visual-intro' },
    h('div', {}, h('span', { class: 'dash-eyebrow' }, 'SOFA · Vista visual'), h('h2', {}, 'Tu operación, de un vistazo'),
      h('p', {}, 'Cada tarjeta abre directamente el módulo donde puedes actuar.'))));
  const grid = h('section', { class: 'dash-visual-grid', 'aria-label': 'Resumen visual' });
  data.sections.forEach((s, idx) => {
    const card = h('article', { class: `dash-visual-card ${idx === 0 ? 'dash-visual-featured' : ''}`.trim() },
      h('div', { class: 'dash-visual-card-head' }, h('span', { class: 'dash-visual-index' }, String(idx + 1).padStart(2, '0')), h('h3', {}, s.title)));
    if (s.alert) card.append(note(s.alert.message, s.alert.level === 'vencido' ? 'error' : 'info'));
    const kp = h('div', { class: 'dash-visual-kpis' });
    s.kpis.forEach((k, i) => kp.append(kpiNode(k, role, i === 0 ? 'dash-visual-primary' : 'dash-visual-secondary')));
    card.append(kp);
    if (s.shortcuts?.length && typeof onOpen === 'function') card.append(h('div', { class: 'i18-actions dash-visual-actions' },
      ...s.shortcuts.map((code) => h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => onOpen(code) }, LABEL[code] || code))));
    grid.append(card);
  });
  wrap.append(grid);
  return wrap;
}

export async function render(root, { onOpen = goTo, role = null } = {}) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite', class: 'dash-root' });
  root.append(box);
  const data = await guarded(box, () => rpc('my_dashboard'));
  if (!data) { if (role) box.append(launcher(role)); return; }
  if (!data.sections || !data.sections.length) {
    box.replaceChildren(note('Su usuario todavía no tiene un rol asignado. Pida al Administrador que se lo asigne.'));
    return;
  }

  let view = await rpc('my_dashboard_view').catch(() => null);
  if (!VIEW_META[view]) view = defaultView(role);

  const draw = () => {
    box.replaceChildren();
    box.append(viewSelector(view, async (next) => {
      if (next === view || !VIEW_META[next]) return;
      try {
        await rpc('set_my_dashboard_view', { p_view: next });
        view = next;
        draw();
      } catch (err) {
        box.prepend(note(err.message || 'No se pudo guardar la vista del dashboard.', 'error'));
      }
    }));
    if (view === 'ejecutivo') box.append(renderExecutive(data, role, onOpen));
    else if (view === 'visual') box.append(renderVisual(data, role, onOpen));
    else box.append(renderOperative(data, role, onOpen));
    if (role) box.append(launcher(role));
  };

  draw();
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
