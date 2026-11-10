/** Preferencias locales de navegación. Nunca concede permisos ni guarda datos de pacientes. */
const PREFIX = 'sofa.nav.favoritos.v1';
const keyFor = ({ userId, organizationId, role } = {}) => userId && organizationId && role
  ? `${PREFIX}.${[userId, organizationId, role].map(encodeURIComponent).join('.')}` : null;
/** Solo devuelve rutas que el usuario todavía puede encontrar en el menú o buscador. */
export function readNavFavorites(scope, allowedRoutes, storage) {
  const key = keyFor(scope); if (!key) return [];
  try {
    const saved = JSON.parse((storage || globalThis.localStorage).getItem(key) || '[]');
    return Array.isArray(saved) ? [...new Set(saved.filter((r) => typeof r === 'string' && allowedRoutes.includes(r)))].slice(0, 12) : [];
  } catch (_) { return []; }
}
/** Un cambio explícito depura favoritos revocados; leer nunca modifica preferencias. */
export function toggleNavFavorite(scope, route, allowedRoutes, storage) {
  const key = keyFor(scope);
  if (!key || !allowedRoutes.includes(route)) throw new Error('Este módulo no está disponible en tu contexto actual.');
  const saved = readNavFavorites(scope, allowedRoutes, storage);
  const next = saved.includes(route) ? saved.filter((r) => r !== route) : [...saved, route];
  if (next.length > 12) throw new Error('Puedes guardar hasta 12 favoritos. Quita uno para agregar otro.');
  try { (storage || globalThis.localStorage).setItem(key, JSON.stringify(next)); }
  catch (_) { throw new Error('No se pudieron guardar los favoritos en este navegador.'); }
  return next;
}
