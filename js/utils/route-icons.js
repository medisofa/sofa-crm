/** SOFA · Íconos por ruta del menú (SVG de línea, sin archivos externos).
 *  Un ícono distinto y reconocible por cada ruta de js/utils/permissions.js, para que el menú
 *  —muy largo en el super_admin— se pueda escanear de un vistazo. Mismo lenguaje visual que los
 *  íconos de familia de app.js (FAMILY_ICONS). Los 15 de la familia «Pacientes y atención» salen
 *  del set ya diseñado en docs/SOFA_habilitacion_revision_prototipo_e_iconos.html.
 *
 *  Uso:  import { icon } from './utils/route-icons.js';  raw(icon(route))  →  '<svg …>…</svg>'
 *  ROUTE_ICON mapea route → contenido interno del <svg> (paths); icon() lo envuelve. */

const SVG = (d) => `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;

/** Ícono genérico de respaldo (módulo) para una ruta sin ícono propio. */
const FALLBACK = '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M9 12h6"/>';

export const ROUTE_ICON = {
  // ── Familia «Pacientes y atención» (set ya diseñado) ──
  'flujo-pacientes': '<path d="M3 5h18M6 12h12M10 19h4"/>',
  pacientes: '<circle cx="12" cy="8" r="3.2"/><path d="M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6"/>',
  'historia-clinica': '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 3.5h6v3H9z"/><path d="M12 10v5M9.5 12.5h5"/>',
  hospitalizacion: '<path d="M3 18V9m0 9h18M3 13h11a4 4 0 014 4v1"/><circle cx="7.5" cy="11.5" r="1.6"/>',
  centros: '<rect x="4" y="7" width="16" height="13" rx="1.5"/><path d="M9 20v-4h6v4M12 4v3M10.5 5.5h3"/>',
  practica: '<path d="M6 3v6a4 4 0 008 0V3M10 3v1.5M6 3v1.5"/><path d="M10 13v2.5a4.5 4.5 0 009 0V15"/><circle cx="19" cy="13" r="1.8"/>',
  mensajes: '<path d="M4 5h16v11H9l-5 4z"/><path d="M8 10h8M8 13h5"/>',
  'indicadores-agenda': '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9h16M8 3v4M16 3v4"/><path d="M8 16l2.5-3 2 2 3-4"/>',
  seguimiento: '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9h16M8 3v4M16 3v4"/><path d="M9.5 14.5l2 2 4-4"/>',
  'avisos-pacientes': '<path d="M6 10a6 6 0 1112 0c0 5 2 6 2 6H4s2-1 2-6z"/><path d="M10 20a2 2 0 004 0"/>',
  'mis-secretarias': '<circle cx="12" cy="8" r="3"/><path d="M6 20c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5"/><path d="M15.5 8.5a3.5 3.5 0 004-1.5"/>',
  'mis-asistentes': '<circle cx="9" cy="8" r="2.8"/><path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5"/><circle cx="17" cy="9" r="2.3"/><path d="M15 14.5c2.6.2 5 2 5 4.5"/>',
  clinica: '<path d="M4 20V8l8-4 8 4v12"/><path d="M4 20h16M10 20v-4h4v4M12 9v3M10.5 10.5h3"/>',
  habilitacion: '<path d="M12 3l7 3v5c0 5-3.5 8-7 10-3.5-2-7-5-7-10V6z"/><path d="M9 12l2 2 4-4"/>',
  'mi-habilitacion': '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 11h6M8 14h4"/><path d="M12.5 17l1.5 1.5 3-3.2"/>',

  // ── Mi día / inicio ──
  'mi-dashboard': '<path d="M4 11l8-6 8 6M6 10v9h12v-9"/><path d="M9 16a3 3 0 016 0"/>',
  autoentrenamiento: '<path d="M3 9l9-4 9 4-9 4z"/><path d="M7 11v4c0 1.3 2.2 2.5 5 2.5s5-1.2 5-2.5v-4M21 9v5"/>',
  inicio: '<path d="M4 11l8-6 8 6M6 10v9h12v-9"/><path d="M10 19v-5h4v5"/>',
  hoy: '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9h16M8 3v4M16 3v4"/><circle cx="12" cy="14" r="2.4"/>',
  'mi-bandeja': '<path d="M4 13l2.5-7h11L20 13v5a1 1 0 01-1 1H5a1 1 0 01-1-1z"/><path d="M4 13h4l1.5 2h5L16 13h4"/>',
  'seguimiento-hoy': '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9h16M8 3v4M16 3v4"/><path d="M14 13h-3v3M11 13l-1.6-1.4"/>',
  agenda: '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9h16M8 3v4M16 3v4"/><path d="M12 12v2.5l1.6 1"/>',
  tareas: '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M7 9l1.4 1.4L11 8M7 15l1.4 1.4L11 14M14 9.5h3M14 15.5h3"/>',

  // ── Mi práctica / dinero del médico ──
  'tarifas-privadas': '<path d="M4 12l8-8 8 8-8 8z"/><circle cx="9" cy="9" r="1.4"/><path d="M11 13l3 3"/>',
  'pagos-privados': '<circle cx="8" cy="9" r="3"/><path d="M3 19c.5-2.7 2.4-4 5-4"/><circle cx="17" cy="14.5" r="4"/><path d="M17 12.5v4M15.6 13.8h2.1a.9.9 0 010 1.8H16"/>',
  dashboard: '<path d="M4 13a8 8 0 0116 0"/><path d="M12 13l4-3"/><path d="M4 13h2M18 13h2M12 5v2"/>',
  'mi-ficha': '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 9h8M8 13h5"/><circle cx="16" cy="15" r="1.8"/>',
  'documentos-consultorio': '<path d="M4 7a2 2 0 012-2h4l2 2h6a2 2 0 012 2v8a2 2 0 01-2 2H6a2 2 0 01-2-2z"/><path d="M9 12h6M9 15h4"/>',
  'mi-incorporacion': '<path d="M5 20c0-6 4-9 7-9s7 3 7 9"/><circle cx="12" cy="6" r="2.5"/><path d="M9 14l2 2 4-4"/>',
  'saldos-pacientes': '<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19c.6-2.8 2.5-4.2 5.5-4.2"/><circle cx="16.5" cy="14.5" r="4"/><path d="M16.5 12.5v4M15.1 13.8h2.1a.9.9 0 010 1.8H16"/>',
  'mi-dinero': '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M16 11h4v4h-4a2 2 0 010-4z"/><path d="M16.5 13h.01"/>',
  'mis-glosas': '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8"/><path d="M15 12l-6 6M10 13.5h.01M14 16.5h.01"/>',
  'mi-productividad': '<path d="M4 20h16"/><path d="M4 16l4-4 3 2 5-6 4 3"/>',
  'reporte-contador': '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7h8"/><path d="M8 11h3M8 14h3M8 17h3"/><path d="M14 11l4 4M18 11l-4 4"/>',
  'estado-cuenta': '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 16h8"/><path d="M8 13l2-2 2 1 3-3"/>',
  'calendario-cobros': '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9h16M8 3v4M16 3v4"/><circle cx="12" cy="14" r="2.4"/><path d="M12 12.5v3"/>',
  rentabilidad: '<path d="M4 20h16"/><path d="M5 16l5-5 3 2 6-7"/><path d="M17 6h3v3"/>',
  'analitica-glosas': '<path d="M4 20h7"/><rect x="5" y="12" width="2.4" height="6"/><rect x="9" y="9" width="2.4" height="9"/><circle cx="16" cy="11" r="3.6"/><path d="M18.6 13.6L21 16"/>',

  // ── Facturación y radicación ──
  captura: '<path d="M4 20l4-1 9.5-9.5-3-3L5 16z"/><path d="M14 6l3 3"/>',
  reclamaciones: '<path d="M7 4h9l3 3v13H7z"/><path d="M4 7v12.5" opacity=".5"/><path d="M10 11h6M10 14h4"/>',
  retiros: '<path d="M4 8l8-4 8 4-8 4z"/><path d="M4 8v8l8 4 8-4V8"/><path d="M12 10.5v5.5m-2-2l2 2 2-2"/>',
  preradicacion: '<path d="M4 14l2-8h12l2 8"/><path d="M4 14v4a1 1 0 001 1h14a1 1 0 001-1v-4h-5l-1 2h-4l-1-2z"/><path d="M12 4v4m-2-2l2-2 2 2"/>',
  radicaciones: '<rect x="4" y="9" width="16" height="11" rx="2"/><path d="M8 9V6.5a4 4 0 018 0V9"/><path d="M12 12v5m-2-2l2 2 2-2"/>',
  codificacion: '<path d="M8 8l-4 4 4 4M16 8l4 4-4 4M13.5 6l-3 12"/>',
  ecf: '<path d="M6 3h12v18l-2-1.3L14 21l-2-1.3L10 21l-2-1.3L6 21z"/><path d="M9 8h6M9 11h6"/><path d="M12.5 13.5l-1.5 2.5h2.5l-1.5 2.5"/>',
  preauditoria: '<rect x="5" y="3" width="12" height="16" rx="2"/><path d="M8 8l1.3 1.3L12 7M8 13h5"/><circle cx="16" cy="17" r="3"/><path d="M18 19l2.5 2.5"/>',
  'calidad-captura': '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10h.01M11 10h.01M15 10h.01M7 14h5"/><path d="M15 14.5l1.3 1.3L19 13"/>',
  'carga-google': '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M4 9h16M9 4v16M14 4v16" opacity=".4"/><path d="M12 16v-5m-2.2 2.2L12 11l2.2 2.2"/>',
  expediente: '<path d="M5 4h9l5 5v11a1 1 0 01-1 1H5a1 1 0 01-1-1V5a1 1 0 011-1z"/><path d="M14 4v5h5"/><path d="M8 13h8M8 16h5"/>',
  'puesta-al-dia': '<path d="M4 6h10M4 12h7M4 18h10"/><path d="M20 7.5a4 4 0 10.4 5.8"/><path d="M20.5 6.5V10h-3.4"/>',

  // ── ARS y contratos ──
  contratos: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 12h8"/><path d="M8 16c1-1 2-1 3 0s2 1 3 0"/>',
  requisitos: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8l1.3 1.3L11.5 7M8 13l1.3 1.3L11.5 12M14 8h2M14 13h2"/>',
  vencimientos: '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9h16M8 3v4M16 3v4"/><path d="M12 12v3M12 17.5v.01"/>',
  'codigos-ars': '<rect x="4" y="5" width="16" height="14" rx="2"/><path d="M4 10h16M10 5v14"/>',
  ars: '<path d="M12 3l7 2v6c0 4-3 7-7 9-4-2-7-5-7-9V5z"/><path d="M9 11h6M12 8v6"/>',
  'tarifas-versiones': '<path d="M4 10l7-7 7 7-7 7z"/><circle cx="8" cy="8" r="1.3"/><path d="M20 12l-6 6M20 15.5l-4 4"/>',
  'brechas-tarifa': '<path d="M4 7h6M14 7h6M4 12h4M16 12h4M4 17h6M14 17h6"/><path d="M12 4v16" stroke-dasharray="2 2.5"/>',
  'senasa-certificados': '<rect x="4" y="3" width="16" height="13" rx="2"/><path d="M8 7h8M8 10h5"/><circle cx="12" cy="18" r="3"/><path d="M10.5 20l1.5-1 1.5 1"/>',

  // ── Cobros y finanzas ──
  glosas: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 12h8"/><circle cx="16.5" cy="17" r="3.2"/><path d="M15 17h3"/>',
  pagos: '<rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 9v.01M18 15v.01"/>',
  conciliacion: '<path d="M12 4v16M6 8h12M6 8l-2.3 5a3 3 0 005 0zM18 8l-2.3 5a3 3 0 005 0z"/>',
  'aplicar-pago': '<rect x="3" y="7" width="18" height="11" rx="2"/><circle cx="12" cy="12.5" r="2.5"/><path d="M12 2v4m-1.6-1.6L12 6l1.6-1.6"/>',
  honorarios: '<circle cx="12" cy="12" r="8"/><path d="M9 9l6 6M9.6 9.6h.01M14.4 14.4h.01"/>',
  aging: '<path d="M7 3h10M7 21h10M8 3c0 4 8 5 8 9s-8 5-8 9M16 3c0 4-8 5-8 9s8 5 8 9"/>',
  reconsideracion: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 16h5"/><path d="M14 12H9m2-2l-2 2 2 2"/>',
  'casos-servicio': '<path d="M4 7h16v3a2 2 0 000 4v3H4v-3a2 2 0 000-4z"/><path d="M12 7v10" stroke-dasharray="2 2.5"/>',
  'causas-glosa': '<circle cx="12" cy="5" r="2"/><path d="M12 7v3M12 10H7v3M12 10h5v3"/><circle cx="7" cy="15" r="2"/><circle cx="17" cy="15" r="2"/>',
  cartera: '<path d="M4 18h4v-3H4zM10 18h4v-7h-4zM16 18h4V8h-4z"/><path d="M3 20h18"/>',

  // ── Comercial / crecimiento ──
  oportunidades: '<path d="M4 5h16l-6 7v6l-4 2v-8z"/>',
  prospectos: '<circle cx="10" cy="9" r="4"/><path d="M4 20c.7-3.3 3-5 6-5"/><circle cx="17" cy="15" r="3"/><path d="M19.2 17.2L21.5 19.5"/>',
  solicitudes: '<path d="M5 4h14v16l-3-2-2 2-2-2-2 2-2-2-3 2z"/><path d="M8 9h8M8 12h5"/>',
  clientes: '<path d="M4 20V6l6-2v16M10 20V9l10-3v14M4 20h16"/><path d="M13 10v.01M16 10v.01M13 13v.01M16 13v.01"/>',
  'salud-clientes': '<path d="M12 20s-7-4-7-9a4 4 0 017-2 4 4 0 017 2c0 5-7 9-7 9z"/><path d="M8 11h2l1-2 1.5 4 1-2h2"/>',
  medicos: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="2.5"/><path d="M7.5 17c.6-2 2.3-3 4.5-3s3.9 1 4.5 3"/>',
  contactos: '<rect x="5" y="3" width="14" height="18" rx="2"/><circle cx="12" cy="10" r="2.4"/><path d="M8.5 16c.6-1.8 1.9-2.5 3.5-2.5s2.9.7 3.5 2.5M3 7h2M3 12h2M3 17h2"/>',
  aliados: '<circle cx="6" cy="12" r="2.3"/><circle cx="18" cy="6" r="2.3"/><circle cx="18" cy="18" r="2.3"/><path d="M8.1 11l7.8-3.7M8.1 13l7.8 3.7"/>',

  // ── Marketing y comunicación ──
  mercadeo: '<path d="M3 10v4h4l9 4V6L7 10z"/><path d="M7 14l1.5 5"/>',
  mercado: '<circle cx="11" cy="11" r="6"/><path d="M5 11h12M11 5c3 2 3 10 0 12M11 5c-3 2-3 10 0 12"/><path d="M15.5 15.5L20 20"/>',
  recomendar: '<path d="M12 20s-6.5-4-6.5-8.5A3.5 3.5 0 0112 9a3.5 3.5 0 016.5 2.5c0 1.3-.6 2.5-1.4 3.6"/><path d="M16 15.5h5M18.5 13v5"/>',
  'casos-exito': '<path d="M8 4h8v3a4 4 0 01-8 0zM6 5H4v2a3 3 0 003 3M18 5h2v2a3 3 0 01-3 3M10 12.5h4V16h-4zM8 20h8M9.5 16h5l.5 4H9z"/>',
  guias: '<path d="M5 4h11a2 2 0 012 2v14H7a2 2 0 01-2-2z"/><path d="M8 4v14M11 9h5M11 12h5"/>',
  novedades: '<path d="M12 3l1.8 4.2L18 9l-4.2 1.8L12 15l-1.8-4.2L6 9l4.2-1.8z"/><path d="M18 14.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"/>',
  actualidades: '<path d="M4 5h13v14H5a1 1 0 01-1-1z"/><path d="M17 8h3v9a2 2 0 01-2 2M7 8h6M7 11h6M7 14h4"/>',
  'mis-avisos': '<path d="M6 10a6 6 0 1112 0c0 5 2 6 2 6H4s2-1 2-6z"/><path d="M10 20a2 2 0 004 0"/><circle cx="17.5" cy="6.5" r="2.2" fill="currentColor" stroke="none"/>',
  'cola-correos': '<rect x="3" y="6" width="14" height="10" rx="1.5"/><path d="M3 7.5l7 5 7-5"/><path d="M20 9v8a2 2 0 01-2 2H8"/>',

  // ── Inteligencia y resultados ──
  direccion: '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M7 20h10M12 17v3"/><path d="M7 12l3-3 2 2 4-4"/>',
  'informe-trimestral': '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 13v4M12 10v7M16 7v10"/>',
  rendimiento: '<circle cx="12" cy="9" r="5"/><path d="M9 13l-1 7 4-2 4 2-1-7"/><path d="M12 7v2l1.5 1"/>',
  reportes: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6"/><path d="M9 12v4M12 10v6M15 13v3"/>',
  fugas: '<path d="M12 3s6 7 6 11a6 6 0 01-12 0c0-1.5.8-3.3 2-5"/><path d="M5 4l15 15"/>',
  propuestas: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 11h8"/><path d="M12 14a2.4 2.4 0 00-1.5 4.3V19h3v-.7A2.4 2.4 0 0012 14z"/>',
  verificacion: '<circle cx="12" cy="12" r="8"/><path d="M8.5 12l2.5 2.5L16 9"/>',
  revision: '<circle cx="12" cy="12" r="9"/><path d="M8 12l3 3 5-6"/>',
  insumos: '<path d="M3 8l9-4 9 4-9 4z"/><path d="M3 8v8l9 4 9-4V8M12 12v8"/>',
  'auditoria-expedientes': '<path d="M4 7a2 2 0 012-2h4l2 2h6a2 2 0 012 2v8a2 2 0 01-2 2H6a2 2 0 01-2-2z"/><path d="M9 13l2 2 3.5-3.5"/>',
  'salud-sistema': '<path d="M12 3l7 3v5c0 5-3.5 8-7 10-3.5-2-7-5-7-10V6z"/><path d="M8 11h2l1-2 1.5 4 1-2h2"/>',
  historial: '<path d="M3.5 12a8.5 8.5 0 108.5-8.5A8.5 8.5 0 004.5 7"/><path d="M3.5 4v3h3"/><path d="M12 8v4l3 2"/>',
  'hc-control': '<path d="M3 12h4l2-4 3 8 2-5 2 1h5"/>',

  // ── Crecimiento del cliente ──
  'mi-puesta-en-marcha': '<path d="M12 3c3 1 5 4 5 8l-2 4h-6l-2-4c0-4 2-7 5-8z"/><circle cx="12" cy="9" r="1.5"/><path d="M9 17l-2 3M15 17l2 3"/>',
  'puesta-en-marcha': '<path d="M13 3c3 2 4 5 3 9l-4 3-4-3c-1-4 0-7 3-9z"/><circle cx="12" cy="8" r="1.4"/><path d="M8 17l-2 3M16 17l2 3"/>',
  'mis-30-dias': '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 9h16M8 3v4M16 3v4"/><circle cx="12" cy="13" r="1.6"/><path d="M9.5 17c.4-1.3 1.3-2 2.5-2s2.1.7 2.5 2"/>',
  'onboarding-30': '<circle cx="9" cy="8" r="3"/><path d="M3.5 19c.6-3 2.8-4.5 5.5-4.5"/><path d="M14 15.5l2 2 4-4"/>',
  diagnostico: '<rect x="6" y="4" width="12" height="16" rx="2"/><path d="M9 4h6v2H9z"/><circle cx="11" cy="12" r="2.4"/><path d="M12.8 13.8l2 2"/>',

  // ── Cuenta / suscripción / incorporación ──
  perfil: '<circle cx="12" cy="8" r="4"/><path d="M4 20c1-4 4-6 8-6s7 2 8 6"/>',
  'mi-cuenta-sofa': '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M3 10h18M7 15h4"/>',
  'mi-plan': '<path d="M6 4h9l4 4v12H6z"/><path d="M14 4v4h4M9 12h6M9 15h4"/>',
  'mi-suscripcion': '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M3 10h18"/><path d="M14.5 15a2.5 2.5 0 10.6-1.6"/><path d="M15 12v1.6h1.6"/>',
  'cambio-clave': '<circle cx="8" cy="10" r="3.6"/><path d="M11 10h9M18 10v2.5M20.5 10v2"/><path d="M4.5 5.5A6 6 0 017 4" stroke-dasharray="2 2"/>',
  seguridad: '<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V8a4 4 0 018 0v2"/><circle cx="12" cy="15" r="1.5"/>',
  'mis-horas': '<circle cx="12" cy="12" r="8"/><path d="M12 7v5l3 2"/>',
  'mi-panel': '<rect x="4" y="4" width="7" height="7" rx="1"/><rect x="13" y="4" width="7" height="7" rx="1"/><rect x="4" y="13" width="7" height="7" rx="1"/><rect x="13" y="13" width="7" height="7" rx="1"/>',

  // ── Administración (super_admin) ──
  usuarios: '<circle cx="9" cy="8" r="3.2"/><path d="M3 19c.6-3 2.8-4.5 6-4.5"/><circle cx="16" cy="10" r="2.6"/><path d="M14 15c2.5.2 4.5 1.8 5 4"/>',
  'alta-usuarios': '<circle cx="9" cy="8" r="3.4"/><path d="M3 20c.7-3.3 3-5.2 6-5.2 1 0 2 .2 2.8.6"/><path d="M18 13.5v6M15 16.5h6"/>',
  permisos: '<path d="M12 3l7 3v5c0 5-3.5 8-7 10-3.5-2-7-5-7-10V6z"/><circle cx="12" cy="10" r="1.8"/><path d="M12 11.8V15"/>',
  parametros: '<path d="M4 7h8M18 7h2M4 12h2M10 12h10M4 17h7M15 17h5"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="12" r="2"/><circle cx="13" cy="17" r="2"/>',
  planes: '<path d="M12 4l8 4-8 4-8-4z"/><path d="M4 12l8 4 8-4M4 16l8 4 8-4"/>',
  suscripciones: '<rect x="3" y="7" width="14" height="10" rx="2"/><path d="M7 5h12a2 2 0 012 2v9"/><path d="M3 11h14"/>',
  documentos: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>',
};

/** Devuelve el <svg> del ícono de una ruta (o el genérico si no tiene uno propio). */
export function icon(route) {
  return SVG(ROUTE_ICON[route] || FALLBACK);
}

export default icon;
