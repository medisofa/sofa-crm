/**
 * SOFA · Roles y navegación.
 * IMPORTANTE: esto solo decide qué se muestra. La seguridad real está en
 * PostgreSQL (RLS y funciones). Ocultar un menú no es un control de acceso.
 */
export const ROLES = Object.freeze({
  super_admin: { name: 'Super Admin SOFA', staff: true },
  admin: { name: 'Administrador SOFA', staff: true },
  billing: { name: 'Facturación', staff: true },
  glosas: { name: 'Analista de glosas', staff: true },
  assistant: { name: 'Asistente', staff: true },
  auditor: { name: 'Auditor', staff: true },
  operations: { name: 'Operaciones SOFA', staff: true },
  client: { name: 'Cliente / PSS', staff: false },
  capturer: { name: 'Capturador / Secretaria', staff: false }
});
/** ALL = roles con acceso general. El Capturador (D3, mínimo privilegio) NO está aquí: solo ve lo que se le asigna explícitamente. */
const ALL = Object.keys(ROLES).filter((r) => r !== 'capturer');
const STAFF = ALL.filter((r) => ROLES[r].staff);
const OPS = ['super_admin', 'admin', 'billing', 'glosas', 'assistant', 'operations'];
const CAPTURE = ['super_admin', 'admin', 'billing', 'assistant', 'operations', 'client', 'capturer'];
const CLAIMS = [...CAPTURE, 'glosas', 'auditor'];
const NO_OPS = (list) => list.filter((r) => r !== 'operations');

/**
 * Menú (§33). iteration = cuándo llega el módulo completo.
 * ready = ya funciona en esta iteración (con los permisos de la base de datos).
 */
export const NAV = [
  { group: 'Operación', items: [
    { route: 'inicio', label: 'Inicio', roles: ALL, ready: true },
    { route: 'hoy', label: 'Trabajo de hoy', roles: ALL, ready: true },
    { route: 'dashboard', label: 'Dashboard', roles: [...NO_OPS(STAFF), 'client'], ready: true }
  ]},
  { group: 'Reclamaciones', items: [
    { route: 'captura', label: 'Captura rápida', roles: CAPTURE, ready: true },
    { route: 'reclamaciones', label: 'Reclamaciones', roles: CLAIMS, ready: true },
    { route: 'retiros', label: 'Retiros físicos', roles: ['super_admin', 'admin', 'billing', 'assistant', 'operations', 'auditor', 'client'], ready: true },
    { route: 'contratos', label: 'Tarifario contractual', roles: ['super_admin', 'admin', 'billing', 'glosas', 'auditor', 'operations', 'client'], ready: true }
  ]},
  { group: 'CRM', items: [
    { route: 'oportunidades', label: 'Pipeline', roles: ['super_admin', 'admin', 'assistant', 'auditor'], ready: true },
    { route: 'prospectos', label: 'Prospectos', roles: ['super_admin', 'admin', 'assistant', 'auditor'], ready: true },
    { route: 'clientes', label: 'Clientes PSS', roles: ALL, ready: true },
    { route: 'contactos', label: 'Contactos', roles: ['super_admin', 'admin', 'assistant', 'auditor'], ready: true },
    { route: 'aliados', label: 'Aliados referidores', roles: ['super_admin', 'admin', 'auditor'], ready: true }
  ]},
  { group: 'Facturación', items: [
    { route: 'radicaciones', label: 'Radicaciones', roles: ALL, ready: true },
    { route: 'codificacion', label: 'Codificación y tarifas', roles: ALL, ready: true },
    { route: 'glosas', label: 'Glosas', roles: [...STAFF.filter((r) => r !== 'assistant'), 'client'], ready: true },
    { route: 'pagos', label: 'Pagos y conciliación', roles: ['super_admin', 'admin', 'billing', 'glosas', 'auditor', 'client'], ready: true },
    { route: 'honorarios', label: 'Honorarios SOFA', roles: ['super_admin', 'admin', 'auditor', 'client'], ready: true },   // nunca operations ni capturer
    { route: 'aging', label: 'Aging', roles: ['super_admin', 'admin', 'billing', 'glosas', 'auditor', 'client'], ready: true }
  ]},
  { group: 'Habilitación', items: [
    { route: 'habilitacion', label: 'Habilitación MISPAS', roles: ['super_admin', 'admin', 'assistant', 'billing', 'auditor', 'client'], ready: true }
  ]},
  { group: 'Inteligencia', items: [
    { route: 'mercado', label: 'Inteligencia de mercado', roles: ['super_admin', 'admin', 'auditor', 'assistant'], ready: true },
    { route: 'guias', label: 'Buenas prácticas', roles: ['super_admin', 'admin', 'billing', 'glosas', 'assistant', 'auditor'], ready: true }
  ]},
  { group: 'Catálogos', items: [
    { route: 'ars', label: 'ARS', roles: ALL, ready: true }
  ]},
  { group: 'Gestión', items: [
    { route: 'tareas', label: 'Tareas', roles: [...OPS, 'auditor'], ready: true },
    { route: 'documentos', label: 'Documentos', roles: ALL, ready: true },
    { route: 'reportes', label: 'Reportes', roles: [...STAFF, 'client'], ready: true }
  ]},
  { group: 'Configuración', items: [
    { route: 'usuarios', label: 'Usuarios y roles', roles: ['super_admin', 'admin', 'auditor'], ready: true },
    { route: 'parametros', label: 'Parámetros', roles: ['super_admin', 'admin', 'auditor'], ready: true }
  ]},
  { group: 'Mi cuenta', items: [
    { route: 'perfil', label: 'Mi perfil', roles: [...ALL, 'capturer'], ready: true },
    { route: 'diagnostico', label: 'Diagnóstico', roles: [...ALL, 'capturer'], ready: true }
  ]}
];

export const allRoutes = () => NAV.flatMap((g) => g.items);
export const findRoute = (r) => allRoutes().find((i) => i.route === r) || null;
export const canSee = (route, role) => !!findRoute(route)?.roles.includes(role);
export const visibleNav = (role) => NAV.map((g) => ({ ...g, items: g.items.filter((i) => i.roles.includes(role)) })).filter((g) => g.items.length);
export const isStaff = (role) => !!ROLES[role]?.staff;
/** Ruta inicial por rol: el Capturador entra directo a la captura */
export const homeRoute = (role) => (role === 'capturer' ? 'captura' : 'inicio');
/** Acciones de interfaz (espejo de la matriz de permisos de 003_rls.sql) */
const ACTIONS = {
  'settings.edit': ['super_admin'],
  'users.toggle': ['super_admin'],
  'users.invite': ['super_admin', 'admin'],
  'milestones.edit': ['super_admin', 'admin'],
  'fees.view': ['super_admin', 'admin', 'auditor', 'client'],
  'crm.edit': ['super_admin', 'admin', 'assistant'],
  'crm.convert': ['super_admin', 'admin'],
  'clients.create': ['super_admin', 'admin'],
  'clients.edit': ['super_admin', 'admin'],
  'codes.edit': ['super_admin', 'admin', 'billing'],
  'tasks.edit': ['super_admin', 'admin', 'billing', 'glosas', 'assistant'],
  'contacts.delete': ['super_admin', 'admin'],
  'partners.edit': ['super_admin', 'admin'],
  'subs.create': ['super_admin', 'admin', 'billing', 'assistant', 'client'],
  'subs.edit': ['super_admin', 'admin', 'billing', 'assistant', 'client'],
  'subs.delete': ['super_admin', 'admin'],
  'docs.upload': ['super_admin', 'admin', 'billing', 'glosas', 'assistant', 'client'],
  'docs.delete': ['super_admin', 'admin'],
  'glosas.edit': ['super_admin', 'admin', 'glosas'],
  'payments.create': ['super_admin', 'admin', 'billing'],
  'payments.void': ['super_admin'],
  'fees.manage': ['super_admin', 'admin'],
  'tariffs.edit': ['super_admin', 'admin', 'billing'],
  'hab.edit': ['super_admin', 'admin', 'assistant'],
  'hab.catalog': ['super_admin', 'admin'],
  'intel.view': ['super_admin', 'admin', 'auditor', 'assistant'],
  'intel.edit': ['super_admin', 'admin', 'assistant'],
  'intel.admin': ['super_admin', 'admin'],
  // Iteración 12 · reclamaciones (espejo de 026_reclamaciones.sql)
  'claims.capture': CAPTURE,
  'claims.money': ['super_admin', 'admin', 'billing', 'glosas', 'auditor', 'client'],          // ver pagado/saldo por reclamación
  'claims.move': ['super_admin', 'admin', 'billing', 'assistant', 'operations', 'glosas', 'auditor', 'client', 'capturer'],
  'claims.audit': ['super_admin', 'admin', 'auditor'],
  'claims.override': ['super_admin', 'admin'],
  'claims.recheck': ['super_admin', 'admin', 'billing', 'operations'],
  'claims.discrepancy': ['super_admin', 'admin', 'billing'],
  'claims.exception': ['super_admin', 'admin'],                                                   // servicio no contratado
  'claims.duplicate': ['super_admin', 'admin', 'billing'],
  'pickups.manage': ['super_admin', 'admin', 'billing', 'assistant', 'operations'],
  'contracts.edit': ['super_admin', 'admin', 'billing'],
  'fiscal.edit': ['super_admin', 'admin', 'billing'],
  'fiscal.exception': ['super_admin', 'admin'],
  'payments.distribute': ['super_admin', 'admin', 'billing', 'glosas'],
  'capturers.assign': ['super_admin', 'admin']
};
export const can = (action, role) => !!ACTIONS[action]?.includes(role);
