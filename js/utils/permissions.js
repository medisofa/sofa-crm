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
  client: { name: 'Cliente / PSS', staff: false }
});
const ALL = Object.keys(ROLES);
const STAFF = ALL.filter((r) => ROLES[r].staff);
const OPS = ['super_admin', 'admin', 'billing', 'glosas', 'assistant'];

/**
 * Menú (§33). iteration = cuándo llega el módulo completo.
 * ready = ya funciona en esta iteración (con los permisos de la base de datos).
 */
export const NAV = [
  { group: 'Operación', items: [
    { route: 'inicio', label: 'Inicio', roles: ALL, ready: true },
    { route: 'hoy', label: 'Trabajo de hoy', roles: ALL, ready: true },
    { route: 'dashboard', label: 'Dashboard', roles: [...STAFF, 'client'], ready: true }
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
    { route: 'honorarios', label: 'Honorarios SOFA', roles: ['super_admin', 'admin', 'auditor', 'client'], ready: true },
    { route: 'aging', label: 'Aging', roles: ['super_admin', 'admin', 'billing', 'glosas', 'auditor', 'client'], ready: true }
  ]},
  { group: 'Habilitación', items: [
    { route: 'habilitacion', label: 'Habilitación MISPAS', roles: ['super_admin', 'admin', 'assistant', 'billing', 'auditor', 'client'], ready: true }
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
    { route: 'perfil', label: 'Mi perfil', roles: ALL, ready: true },
    { route: 'diagnostico', label: 'Diagnóstico', roles: ALL, ready: true }
  ]}
];

export const allRoutes = () => NAV.flatMap((g) => g.items);
export const findRoute = (r) => allRoutes().find((i) => i.route === r) || null;
export const canSee = (route, role) => !!findRoute(route)?.roles.includes(role);
export const visibleNav = (role) => NAV.map((g) => ({ ...g, items: g.items.filter((i) => i.roles.includes(role)) })).filter((g) => g.items.length);
export const isStaff = (role) => !!ROLES[role]?.staff;
/** Acciones de interfaz (espejo de la matriz de permisos de 003_rls.sql) */
const ACTIONS = {
  'settings.edit': ['super_admin'],
  'users.toggle': ['super_admin'],
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
  'hab.catalog': ['super_admin', 'admin']
};
export const can = (action, role) => !!ACTIONS[action]?.includes(role);
