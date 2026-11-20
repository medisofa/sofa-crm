/** Preferencias locales de navegación: frecuencia de uso de los módulos.
 *  Igual que los favoritos (nav-favorites.js), es estado por visor guardado en localStorage:
 *  nunca concede permisos ni guarda datos de pacientes. Cada visita envejece un poco lo anterior,
 *  así la lista refleja lo que usas últimamente y no se congela con lo de hace meses. */
const PREFIX = 'sofa.nav.frecuencia.v1';
const DECAY = 0.995;     // cada visita resta peso a lo previo → gana lo reciente
const FLOOR = 0.2;       // por debajo de esto una ruta se olvida
const MAX_ROUTES = 24;   // el almacén no crece sin límite
const MIN_SCORE = 2;     // aparece recién tras un par de usos, para que la lista no parpadee

const keyFor = ({ userId, organizationId, role } = {}) => userId && organizationId && role
  ? `${PREFIX}.${[userId, organizationId, role].map(encodeURIComponent).join('.')}` : null;

function readRaw(key, storage) {
  try {
    const o = JSON.parse((storage || globalThis.localStorage).getItem(key) || '{}');
    return o && typeof o === 'object' && !Array.isArray(o) ? o : {};
  } catch (_) { return {}; }
}

/** Registra una visita a `route` y envejece el resto. Devuelve el mapa actualizado, o null
 *  si no hay dónde guardar (contexto incompleto o navegador sin almacenamiento). */
export function recordNavVisit(scope, route, storage) {
  const key = keyFor(scope);
  if (!key || typeof route !== 'string' || !route) return null;
  const store = storage || globalThis.localStorage;
  const counts = readRaw(key, store);
  const next = {};
  for (const [r, v] of Object.entries(counts)) {
    const n = Number(v) * DECAY;
    if (typeof r === 'string' && Number.isFinite(n) && n > FLOOR) next[r] = n;
  }
  next[route] = (Number(next[route]) || 0) + 1;
  const trimmed = Object.fromEntries(
    Object.entries(next).sort((a, b) => b[1] - a[1]).slice(0, MAX_ROUTES));
  try { store.setItem(key, JSON.stringify(trimmed)); return trimmed; } catch (_) { return null; }
}

/** Rutas más usadas, de mayor a menor, acotadas a las que el usuario todavía puede abrir.
 *  `exclude` (array o Set) y las rutas por debajo del umbral quedan fuera; nunca entrega
 *  una ruta que el rol ya no tenga. */
export function topNavRoutes(scope, allowedRoutes, { exclude = [], limit = 6, storage } = {}) {
  const key = keyFor(scope); if (!key) return [];
  const allowed = new Set(allowedRoutes || []);
  const skip = exclude instanceof Set ? exclude : new Set(exclude || []);
  const counts = readRaw(key, storage);
  return Object.entries(counts)
    .filter(([r, v]) => allowed.has(r) && !skip.has(r) && Number(v) >= MIN_SCORE)
    .sort((a, b) => Number(b[1]) - Number(a[1]))
    .slice(0, Math.max(0, limit))
    .map(([r]) => r);
}
