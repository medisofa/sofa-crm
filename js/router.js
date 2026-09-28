/**
 * SOFA · Enrutador por hash (#/ruta/parametro). Compatible con GitHub Pages
 * sin configuración de servidor.
 */
import { findRoute, canSee } from './utils/permissions.js';

const MODULES = {
  inicio: 'home.js', clientes: 'clients.js', codificacion: 'coding.js', ars: 'ars.js',
  usuarios: 'users.js', parametros: 'settings.js', perfil: 'profile.js', diagnostico: 'diagnostics.js',
  oportunidades: 'pipeline.js', prospectos: 'leads.js', contactos: 'contacts.js', aliados: 'partners.js', tareas: 'tasks.js',
  radicaciones: 'submissions.js', documentos: 'documents.js',
  glosas: 'glosas.js', pagos: 'payments.js', honorarios: 'fees.js'
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
