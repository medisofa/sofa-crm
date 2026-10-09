/**
 * SOFA · Enrutador por hash (#/ruta/parametro). Compatible con GitHub Pages
 * sin configuración de servidor.
 */
import { findRoute, canSee } from './utils/permissions.js';

export const MODULES = {
  inicio: 'home.js', clientes: 'clients.js', codificacion: 'coding.js', ars: 'ars.js',
  usuarios: 'users.js', parametros: 'settings.js', perfil: 'profile.js', diagnostico: 'diagnostics.js',
  oportunidades: 'pipeline.js', prospectos: 'leads.js', contactos: 'contacts.js', aliados: 'partners.js', tareas: 'tasks.js',
  radicaciones: 'submissions.js', documentos: 'documents.js',
  glosas: 'glosas.js', pagos: 'payments.js', honorarios: 'fees.js', medicos: 'provider360.js', agenda: 'agenda.js', practica: 'practice.js', 'tarifas-privadas': 'private-tariffs.js',
  hoy: 'today.js', dashboard: 'dashboard.js', aging: 'aging.js', reportes: 'reports.js',
  habilitacion: 'habilitation.js', mercado: 'market.js', guias: 'guides.js',
  captura: 'capture.js', reclamaciones: 'claims.js', retiros: 'pickups.js', contratos: 'contracts.js',
  preradicacion: 'prerad.js', requisitos: 'requirements.js',
  // Iteraciones 18 a 28 (SOFA 1.9.0)
  'mi-dashboard': 'dashboard-rol.js',
  'estado-cuenta': 'statement.js', 'calendario-cobros': 'collections-calendar.js', mensajes: 'weekly.js', rentabilidad: 'profitability.js',
  pacientes: 'pacientes.js', 'saldos-pacientes': 'saldos-pacientes.js', 'indicadores-agenda': 'indicadores-agenda.js',
  seguimiento: 'seguimiento.js', 'avisos-pacientes': 'avisos-pacientes.js', 'mis-secretarias': 'mis-secretarias.js',
  centros: 'centros.js', 'alta-usuarios': 'usuarios.js', 'cambio-clave': 'cambio-clave.js',
  'analitica-glosas': 'analitica-glosas.js', 'salud-clientes': 'salud-clientes.js',
  // 2.0 · Iteración 29
  'historia-clinica': 'historia-clinica.js', 'hc-control': 'hc-control.js', seguridad: 'seguridad.js',
  // 2.1 · Iteraciones 30 y 31
  'mi-ficha': 'mi-ficha.js', 'mi-incorporacion': 'mi-incorporacion.js',
  // 2.2 a 2.6 · Iteraciones 32 a 36
  vencimientos: 'vencimientos.js', 'codigos-ars': 'codigos-ars.js', revision: 'revision.js'
};
export const DEFAULT_ROUTE = 'inicio';

export function parseHash() {
  const h = decodeURIComponent(location.hash.replace(/^#\/?/, ''));
  const [route, ...rest] = h.split('/').filter(Boolean);
  return { route: route || DEFAULT_ROUTE, arg: rest.join('/') || null };
}

/** Resuelve qué módulo mostrar según la ruta y el rol */
export async function resolve(role) {
  const { route, arg } = parseHash();
  const def = findRoute(route);
  if (!def) return { kind: 'notfound', route };
  if (!canSee(route, role)) return { kind: 'forbidden', def };
  if (!def.ready) {
    const mod = await import('./modules/placeholder.js');
    return { kind: 'module', def, mod, arg };
  }
  const mod = await import(`./modules/${MODULES[route]}`);
  return { kind: 'module', def, mod, arg };
}
