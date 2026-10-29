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

const ICO = {
  clasica: 'M4 20V10M12 20V4M20 20v-7',
  pulso: 'M2 12h4l2-6 3 12 2-9 2 5h7',
  grilla: 'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z',
  corazon: 'M12 20s-7-4.4-7-9.8C5 7 7.2 5 9.6 5 11 5 12 5.8 12 5.8S13 5 14.4 5C16.8 5 19 7 19 10.2 19 15.6 12 20 12 20z',
  recibo: 'M6 3h12v17l-2.5-1.5L13 20l-2.5-1.5L8 20l-2-1.5zM8.5 8h7M8.5 11.5h7M8.5 15h4.5',
  columnas: 'M3 4h18v16H3zM13 4v16M13 11h8',
  linea: 'M5 12h14',
  carpeta: 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  vidrio: 'M9 12a6.5 6.5 0 1 0 0 0zM15 12a6.5 6.5 0 1 0 0 0z',
  bloques: 'M3 5h7v14H3zM12 5h4.5v14H12zM18 5h3v14h-3z'
};
// 28/10/2026: diez direcciones visuales adicionales, elegidas con el cliente a partir de un
// catálogo de propuestas. Se suman a las 3 ya existentes; no las reemplazan. Cada una reusa
// las mismas data.sections/kpis — solo cambia la composición visual, nunca el cálculo.
const VIEW_META = {
  operativo: { label: 'Vista general', hint: 'Pendientes, acciones y accesos directos.', icon: ICO.clasica },
  ejecutivo: { label: 'Ejecutivo', hint: 'Indicadores y alertas para tomar decisiones.', icon: ICO.clasica },
  visual: { label: 'Visual', hint: 'Tarjetas amplias y lectura rápida del estado.', icon: ICO.clasica },
  clinico: { label: 'Clínico', hint: 'El pulso del logo como hilo conductor.', icon: ICO.pulso, nuevo: true },
  informe: { label: 'Informe', hint: 'Autoridad por tipografía, sin degradados.', icon: ICO.grilla, nuevo: true },
  operaciones: { label: 'Operaciones', hint: 'Retícula técnica, un solo tema oscuro.', icon: ICO.grilla, nuevo: true },
  cercano: { label: 'Cercano', hint: 'Anillos de progreso y tono cálido.', icon: ICO.corazon, nuevo: true },
  recibo: { label: 'Recibo', hint: 'Vocabulario de factura dominicana.', icon: ICO.recibo, nuevo: true },
  editorial: { label: 'Editorial', hint: 'Se siente a landing de producto.', icon: ICO.columnas, nuevo: true },
  minimal: { label: 'Minimalista', hint: 'Casi sin color, cifras grandes.', icon: ICO.linea, nuevo: true },
  carpeta: { label: 'Carpeta clínica', hint: 'Metáfora de expediente físico.', icon: ICO.carpeta, nuevo: true },
  vidrio: { label: 'Vidrio esmerilado', hint: 'Tarjetas translúcidas sobre degradado.', icon: ICO.vidrio, nuevo: true },
  bloques: { label: 'Bloques', hint: 'Color sólido, muy legible de lejos.', icon: ICO.bloques, nuevo: true }
};

const defaultView = (role) => role === 'client' ? 'visual' : (['super_admin','admin'].includes(role) ? 'ejecutivo' : 'operativo');

/** Hasta 4 KPI y hasta 2 accesos directos de todas las secciones, para las vistas compactas. */
function topKpisAndShortcuts(data, n = 4) {
  const kpis = data.sections.flatMap((s) => s.kpis).slice(0, n);
  const shortcuts = [...new Set(data.sections.flatMap((s) => s.shortcuts || []))].slice(0, 2);
  return { kpis, shortcuts };
}
function shortcutButtons(shortcuts, onOpen, cls = 'i18-btn i18-sec') {
  if (!shortcuts.length || typeof onOpen !== 'function') return null;
  return h('div', { class: 'i18-actions dash-new-sh' },
    ...shortcuts.map((code) => h('button', { class: cls, type: 'button', onclick: () => onOpen(code) }, LABEL[code] || code)));
}
function traceSvg() {
  const NS = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('class', 'dn-trace'); svg.setAttribute('viewBox', '0 0 400 34');
  svg.setAttribute('preserveAspectRatio', 'none'); svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS(NS, 'path');
  path.setAttribute('d', 'M0,17 L80,17 L92,4 L104,30 L116,17 L200,17 L212,9 L224,25 L236,17 L400,17');
  svg.append(path);
  return svg;
}
function brandmark(variant = 'color') {
  const src = variant === 'white' ? 'assets/brand/sofa-logo-white.png' : variant === 'symbol' ? 'assets/brand/sofa-symbol.png' : 'assets/brand/sofa-logo.png';
  return h('img', { class: 'dash-new-brand', src, alt: 'SOFA', loading: 'lazy' });
}

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

function iconSvg(d) {
  const NS = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('fill', 'none');
  svg.setAttribute('stroke-width', '1.8'); svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round');
  const path = document.createElementNS(NS, 'path'); path.setAttribute('d', d);
  svg.append(path);
  return svg;
}

/** 28/10/2026: el selector pasó de 3 a 13 vistas. Para que no ocupe espacio permanente en
 *  celular, tablet ni PC, abre colapsado (muestra solo la vista activa) y se expande al tocar;
 *  al elegir una vista se vuelve a colapsar solo. `open` vive en el cierre de render(), no aquí,
 *  para sobrevivir a los redibujados de draw(). */
function viewSelector(current, open, onToggle, onChange) {
  const meta = VIEW_META[current];
  const bar = h('section', { class: 'dash-viewbar', 'aria-label': 'Vista del dashboard' },
    h('button', { class: 'dash-viewbar-toggle', type: 'button', 'aria-expanded': String(open), onclick: onToggle },
      iconSvg(meta?.icon || ICO.clasica),
      h('span', { class: 'dash-viewbar-copy' }, h('strong', {}, meta?.label || 'Vista'), h('span', {}, meta?.hint || '')),
      h('span', { class: `dash-viewbar-chevron ${open ? 'is-open' : ''}`.trim(), 'aria-hidden': 'true' }, '▾')));
  if (open) {
    bar.append(h('div', { class: 'dash-view-switch', role: 'group', 'aria-label': 'Seleccionar vista' },
      ...Object.entries(VIEW_META).map(([key, m]) => h('button', {
        class: `dash-view-btn ${current === key ? 'is-active' : ''}`.trim(),
        type: 'button',
        'aria-pressed': String(current === key),
        onclick: () => onChange(key)
      }, iconSvg(m.icon), h('span', { class: 'dash-view-btn-lbl' }, m.label)))));
  }
  return bar;
}

function renderOperative(data, role, onOpen) {
  const wrap = h('div', { class: 'dash-layout dash-layout-operativo' });
  for (const s of data.sections) {
    const card = h('section', { class: 'i18-card', 'aria-label': s.title }, h('h3', {}, s.title));
    if (s.alert) card.append(note(s.alert.message, s.alert.level === 'vencido' ? 'error' : 'info'));
    card.append(h('div', { class: 'i18-kpis' }, ...s.kpis.map((k) => kpiNode(k, role))));
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

function renderClinico(data, role, onOpen) {
  const { kpis, shortcuts } = topKpisAndShortcuts(data);
  return h('div', { class: 'dash-new dash-new-clinico' },
    h('div', { class: 'dn-hero' },
      brandmark('white'),
      h('span', { class: 'dn-eyebrow' }, 'Tu consultorio, hoy'),
      h('h3', {}, 'Buenos días'),
      traceSvg()),
    h('div', { class: 'dn-body' },
      h('div', { class: 'dn-grid-4' }, ...kpis.map((k) => kpiNode(k, role, 'dn-card'))),
      shortcutButtons(shortcuts, onOpen)));
}

function renderInforme(data, role, onOpen) {
  const { kpis, shortcuts } = topKpisAndShortcuts(data);
  return h('div', { class: 'dash-new dash-new-informe' },
    brandmark('color'),
    h('h3', {}, 'Resumen operativo del día'),
    h('p', { class: 'dn-lede' }, 'Lectura rápida para quien decide.'),
    h('div', { class: 'dn-rule' }),
    h('div', { class: 'dn-cells' }, ...kpis.map((k, i) => h('div', { class: 'dn-cell' },
      h('div', { class: 'dn-idx' }, `0${i + 1} · ${k.label}`),
      kpiNode(k, role, 'dn-cell-v')))),
    shortcutButtons(shortcuts, onOpen));
}

function renderOperaciones(data, role, onOpen) {
  const { kpis, shortcuts } = topKpisAndShortcuts(data);
  return h('div', { class: 'dash-new dash-new-operaciones' },
    brandmark('white'),
    h('div', { class: 'dn-eyebrow2' }, h('span', { class: 'dn-dot', 'aria-hidden': 'true' }), 'Sistema en vivo'),
    h('h3', {}, 'Telemetría de tu operación'),
    h('div', { class: 'dn-grid-4' }, ...kpis.map((k) => kpiNode(k, role, 'dn-tile'))),
    shortcutButtons(shortcuts, onOpen));
}

function renderCercano(data, role, onOpen) {
  const { kpis, shortcuts } = topKpisAndShortcuts(data);
  return h('div', { class: 'dash-new dash-new-cercano' },
    h('div', { class: 'dn-glow', 'aria-hidden': 'true' }),
    h('div', { class: 'dn-in' },
      brandmark('color'),
      h('div', { class: 'dn-greet' }, 'Buenos días'),
      h('h3', {}, 'Tu consultorio, al pulso del día'),
      h('div', { class: 'dn-rings' }, ...kpis.map((k) => {
        const nav = kpiRoute(k, role);
        const glyph = k.level === 'bad' ? '!' : k.level === 'warn' ? '•' : '✓';
        const row = h('div', { class: `dn-ring-row dn-lvl-${k.level}` },
          h('div', { class: 'dn-ring' }, h('span', { 'aria-hidden': 'true' }, glyph)),
          h('div', { class: 'dn-ring-main' }, h('b', {}, k.label)),
          h('div', { class: 'dn-ring-v' }, fmt(k)));
        return nav ? h('a', { href: `#/${nav[0]}`, title: nav[1], class: 'dn-ring-link' }, row) : row;
      })),
      shortcutButtons(shortcuts, onOpen, 'i18-btn i18-sec dn-pill')));
}

function renderRecibo(data) {
  const { kpis } = topKpisAndShortcuts(data);
  const hoy = new Date().toLocaleDateString('es-DO', { day: '2-digit', month: '2-digit', year: 'numeric' });
  return h('div', { class: 'dash-new dash-new-recibo' },
    h('div', { class: 'dn-rhead' },
      h('div', {}, h('h3', {}, 'Resumen del día'), h('div', { class: 'dn-folio' }, `FOLIO DSH · ${hoy}`)),
      h('div', { class: 'dn-stamp' }, brandmark('symbol'), 'SOFA')),
    h('div', { class: 'dn-rrows' }, ...kpis.map((k) => h('div', { class: `dn-rrow dn-lvl-${k.level}` },
      h('span', { class: 'dn-rl' }, k.label), h('span', { class: 'dn-rv' }, fmt(k))))));
}

function renderEditorial(data, role, onOpen) {
  const { kpis, shortcuts } = topKpisAndShortcuts(data);
  const [lead, ...rest] = kpis;
  return h('div', { class: 'dash-new dash-new-editorial' },
    h('div', { class: 'dn-egrid' },
      h('div', { class: 'dn-elead' },
        h('div', {}, brandmark('white'), h('div', { class: 'dn-eyebrow' }, 'Resumen de hoy'),
          h('h3', {}, 'Tu consultorio en una mirada')),
        lead ? h('div', { class: 'dn-ebig' }, fmt(lead), h('small', {}, lead.label)) : null),
      h('div', { class: 'dn-eside' }, ...rest.map((k) => h('div', { class: 'dn-ecell' },
        h('b', {}, k.label), kpiNode(k, role, 'dn-ecell-v'))))),
    shortcutButtons(shortcuts, onOpen));
}

function renderMinimal(data, role, onOpen) {
  const { kpis, shortcuts } = topKpisAndShortcuts(data);
  return h('div', { class: 'dash-new dash-new-minimal' },
    brandmark('color'),
    h('div', { class: 'dn-eyebrow3' }, 'Resumen de hoy'),
    ...kpis.map((k) => h('div', { class: `dn-mrow dn-lvl-${k.level}` }, h('span', {}, k.label), kpiNode(k, role, 'dn-mv'))),
    shortcutButtons(shortcuts, onOpen));
}

function renderCarpeta(data, role, onOpen) {
  const { kpis, shortcuts } = topKpisAndShortcuts(data);
  const hoy = new Date().toLocaleDateString('es-DO', { day: 'numeric', month: 'long', year: 'numeric' });
  return h('div', { class: 'dash-new dash-new-carpeta' },
    h('div', { class: 'dn-tab' }, brandmark('symbol'), 'EXPEDIENTE DEL DÍA'),
    h('div', { class: 'dn-cin' },
      h('h3', {}, 'Consultorio — resumen'), h('div', { class: 'dn-sub' }, hoy),
      h('div', { class: 'dn-grid-4' }, ...kpis.map((k) => kpiNode(k, role, 'dn-ccell'))),
      shortcutButtons(shortcuts, onOpen)));
}

function renderVidrio(data, role, onOpen) {
  const { kpis, shortcuts } = topKpisAndShortcuts(data);
  return h('div', { class: 'dash-new dash-new-vidrio' },
    h('div', { class: 'dn-mesh', 'aria-hidden': 'true' }),
    h('div', { class: 'dn-vin' },
      brandmark('white'), h('div', { class: 'dn-eyebrow' }, 'Resumen de hoy'),
      h('h3', {}, 'Tu consultorio, de un vistazo'),
      h('div', { class: 'dn-grid-4' }, ...kpis.map((k) => kpiNode(k, role, 'dn-vcard'))),
      shortcutButtons(shortcuts, onOpen, 'i18-btn i18-sec dn-ghost')));
}

function renderBloques(data, role) {
  const { kpis } = topKpisAndShortcuts(data);
  return h('div', { class: 'dash-new dash-new-bloques' }, ...kpis.map((k, i) => {
    const nav = kpiRoute(k, role);
    const cls = `dn-block dn-lvl-${k.level}`;
    const kids = [i === 0 ? brandmark('white') : null, h('b', {}, k.label), h('div', { class: 'dn-block-v' }, fmt(k))];
    return nav ? h('a', { href: `#/${nav[0]}`, title: nav[1], class: cls }, ...kids) : h('div', { class: cls }, ...kids);
  }));
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
  let selectorOpen = false;

  const RENDERERS = {
    ejecutivo: renderExecutive, visual: renderVisual, operativo: renderOperative,
    clinico: renderClinico, informe: renderInforme, operaciones: renderOperaciones,
    cercano: renderCercano, recibo: renderRecibo, editorial: renderEditorial,
    minimal: renderMinimal, carpeta: renderCarpeta, vidrio: renderVidrio, bloques: renderBloques
  };

  const draw = () => {
    box.replaceChildren();
    box.append(viewSelector(view, selectorOpen, () => { selectorOpen = !selectorOpen; draw(); }, async (next) => {
      selectorOpen = false;
      if (next === view || !VIEW_META[next]) { draw(); return; }
      try {
        await rpc('set_my_dashboard_view', { p_view: next });
        view = next;
        draw();
      } catch (err) {
        draw();
        box.prepend(note(err.message || 'No se pudo guardar la vista del dashboard.', 'error'));
      }
    }));
    box.append((RENDERERS[view] || renderOperative)(data, role, onOpen));
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
