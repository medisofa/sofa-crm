/**
 * SOFA · Roles y navegación.
 * IMPORTANTE: esto solo decide qué se muestra. La seguridad real está en
 * PostgreSQL (RLS y funciones). Ocultar un menú no es un control de acceso.
 */
export const ROLES = Object.freeze({   // nombres según la tabla de roles (auditoría Fase 1, sección 9) · 1.6.1
  super_admin: { name: 'Super Admin SOFA', staff: true, desc: 'Todo el sistema, incluidos usuarios, parámetros y datos fiscales.' },
  admin: { name: 'Administrador SOFA', staff: true, desc: 'Operación completa de SOFA: radicación, pagos, glosas, honorarios, tarifarios y usuarios.' },
  operations: { name: 'Operaciones SOFA', staff: true, desc: 'Retiro físico, validación, onboarding y bandejas; sin honorarios.' },
  billing: { name: 'Facturación', staff: true, desc: 'Trabajo de hoy, Dashboard, Captura rápida, Reclamaciones y Retiros físicos.' },
  glosas: { name: 'Cobros, conciliación y glosas', staff: true, desc: 'Pagos de las ARS, reparto por reclamación y gestión de glosas.' },
  assistant: { name: 'Comercial', staff: true, desc: 'Prospectos, pipeline, documentos A–E, onboarding y CRM.' },
  auditor: { name: 'Auditor', staff: true, desc: 'Valida expedientes (completo o incompleto) y consulta todo.' },
  client: { name: 'Médico', staff: false, desc: 'Dueño de la práctica: su consultorio completo (agenda, reclamaciones, cobros, Mi práctica y sus honorarios SOFA).' },
  capturer: { name: 'Secretaria', staff: false, desc: 'Agenda, captura, cobros a privados y cuadre de los médicos que se le asignan; sin pagos de ARS, glosas ni honorarios.' },
  prospect: { name: 'Prospecto', staff: false, desc: 'Futuro cliente: solo ve el avance de su incorporación. Al convertirse en cliente pasa a Médico.' }   // 2.1 · Iteración 30
});
/** ALL = roles con acceso general. El Capturador (D3, mínimo privilegio) NO está aquí: solo ve lo que se le asigna explícitamente. */
const ALL = Object.keys(ROLES).filter((r) => r !== 'capturer' && r !== 'prospect');   // 2.1: el Prospecto tampoco tiene acceso general
const STAFF = ALL.filter((r) => ROLES[r].staff);
const OPS = ['super_admin', 'admin', 'billing', 'glosas', 'assistant', 'operations'];
const CAPTURE = ['super_admin', 'admin', 'billing', 'assistant', 'operations', 'client', 'capturer'];
const CLAIMS = [...CAPTURE, 'glosas', 'auditor'];
const NO_OPS = (list) => list.filter((r) => r !== 'operations');
/**
 * Facturación (decisión 01/10/2026): solo trabaja en Trabajo de hoy, Dashboard, Captura rápida,
 * Reclamaciones y Retiros físicos (más Mi perfil y Diagnóstico). Todo lo demás se le oculta aquí.
 * BILLING_ROUTES es la única lista que hay que tocar para cambiar su alcance.
 * 1.9.0: se agrega «Mi dashboard» (primera página de todos los roles).
 */
export const BILLING_ROUTES = ['mi-dashboard', 'hoy', 'dashboard', 'captura', 'reclamaciones', 'retiros', 'perfil', 'diagnostico', 'cambio-clave', 'seguridad'];   // 2.0: + cambiar contraseña y seguridad (antes «Cambiar contraseña» le daba «Sin acceso»)

/**
 * Menú (§33). iteration = cuándo llega el módulo completo.
 * ready = ya funciona en esta iteración (con los permisos de la base de datos).
 * hidden = la ruta existe pero no se muestra en el menú (se abre desde otra pantalla).
 */
export const NAV = [
  { group: 'Operación', items: [
    { route: 'mi-dashboard', label: 'Inicio', roles: [...ALL, 'capturer'], ready: true },   // 1.9 · primera página según el rol · 2.0: se llama «Inicio»
    { route: 'inicio', label: 'Panel SOFA', roles: STAFF, ready: true },   // 2.0: el panel general queda para el personal de SOFA
    { route: 'hoy', label: 'Trabajo de hoy', roles: [...ALL, 'capturer'], ready: true },
    { route: 'agenda', label: 'Agenda del consultorio', roles: ['super_admin', 'admin', 'assistant', 'operations', 'client', 'capturer'], ready: true },   // 1.6
    { route: 'practica', label: 'Mi práctica', roles: ['super_admin', 'admin', 'assistant', 'operations', 'client'], ready: true },
    { route: 'tarifas-privadas', label: 'Tarifas privadas', roles: ['super_admin', 'admin', 'assistant', 'client'], ready: true },
    { route: 'dashboard', label: 'Dashboard BI', roles: [...NO_OPS(STAFF), 'client'], ready: true }
  ]},
  { group: 'Mi consultorio', items: [   // 1.9 · Iteraciones 19 a 27
    { route: 'pacientes', label: 'Pacientes', roles: ['super_admin', 'admin', 'client', 'capturer'], ready: true },
    { route: 'historia-clinica', label: 'Historia clínica', roles: ['client', 'super_admin'], ready: true },
    { route: 'mi-ficha', label: 'Mi ficha (ARS y tarifas)', roles: ['client'], ready: true },   // 2.1 · Iteración 31
    { route: 'mi-incorporacion', label: 'Mi incorporación', roles: ['prospect'], ready: true },   // 2.1 · Iteración 30   // 2.0 · Iteración 29 (Super Admin solo con acceso de emergencia)
    { route: 'saldos-pacientes', label: 'Saldos de pacientes', roles: ['super_admin', 'admin', 'client', 'capturer'], ready: true },
    { route: 'mensajes', label: 'Mensajes (WhatsApp)', roles: ['super_admin', 'admin', 'assistant', 'operations', 'client', 'capturer'], ready: true },
    { route: 'indicadores-agenda', label: 'Indicadores de la agenda', roles: ['super_admin', 'admin', 'client'], ready: true },
    { route: 'seguimiento', label: 'Seguimiento después de la cita', roles: ['super_admin', 'admin', 'client'], ready: true },
    { route: 'avisos-pacientes', label: 'Avisos a pacientes', roles: ['super_admin', 'admin', 'client'], ready: true },
    { route: 'mis-secretarias', label: 'Mis secretarias', roles: ['super_admin', 'admin', 'client'], ready: true },
    { route: 'centros', label: 'Centros de salud', roles: ['super_admin', 'admin', 'client'], ready: true }
  ]},
  { group: 'Mis resultados', items: [   // 1.9 · Iteraciones 18 y 26
    { route: 'estado-cuenta', label: 'Estado de cuenta (ROI)', roles: ['super_admin', 'admin', 'auditor', 'client'], ready: true },
    { route: 'calendario-cobros', label: 'Calendario de cobros', roles: ['super_admin', 'admin', 'glosas', 'auditor', 'client'], ready: true },
    { route: 'rentabilidad', label: 'Rentabilidad por ARS', roles: ['super_admin', 'admin', 'auditor', 'client'], ready: true },
    { route: 'analitica-glosas', label: 'Analítica de glosas', roles: ['super_admin', 'admin', 'glosas', 'auditor', 'operations', 'client'], ready: true }
  ]},
  { group: 'Reclamaciones', items: [
    { route: 'captura', label: 'Captura rápida', roles: CAPTURE, ready: true },
    { route: 'reclamaciones', label: 'Reclamaciones', roles: CLAIMS, ready: true },
    { route: 'retiros', label: 'Retiros físicos', roles: ['super_admin', 'admin', 'billing', 'assistant', 'operations', 'auditor', 'client'], ready: true },
    { route: 'preradicacion', label: 'Pre-radicación', roles: ['super_admin', 'admin', 'billing', 'operations', 'auditor', 'assistant'], ready: true },
    { route: 'contratos', label: 'Tarifario contractual', roles: ['super_admin', 'admin', 'billing', 'glosas', 'auditor', 'operations', 'client'], ready: true },
    { route: 'requisitos', label: 'Requisitos documentales', roles: ['super_admin', 'admin', 'billing', 'auditor', 'operations', 'assistant'], ready: true },
    { route: 'vencimientos', label: 'Renegociación de tarifarios', roles: ['super_admin', 'admin', 'glosas', 'auditor', 'operations', 'assistant'], ready: true },   // 2.2 · 2.6.1: solo SOFA
    { route: 'codigos-ars', label: 'Códigos ARS (tablero)', roles: ['super_admin', 'admin', 'assistant', 'operations', 'auditor'], ready: true }   // 2.3 · Iteración 33
  ]},
  { group: 'CRM', items: [
    { route: 'oportunidades', label: 'Pipeline', roles: ['super_admin', 'admin', 'assistant', 'auditor'], ready: true },
    { route: 'prospectos', label: 'Prospectos', roles: ['super_admin', 'admin', 'assistant', 'auditor'], ready: true },
    { route: 'clientes', label: 'Clientes (ficha)', roles: ALL, ready: true },
    { route: 'salud-clientes', label: 'Salud de los clientes', roles: ['super_admin', 'admin', 'assistant', 'operations'], ready: true },   // 1.9 · Iteración 28
    { route: 'medicos', label: 'Médicos 360', roles: ALL, ready: true },
    { route: 'contactos', label: 'Contactos', roles: ['super_admin', 'admin', 'assistant', 'auditor'], ready: true },
    { route: 'aliados', label: 'Aliados referidores', roles: ['super_admin', 'admin', 'auditor'], ready: true }
  ]},
  { group: 'Facturación', items: [
    { route: 'radicaciones', label: 'Radicaciones', roles: ALL, ready: true },
    { route: 'codificacion', label: 'Codificación y tarifas', roles: ALL, ready: true },
    { route: 'glosas', label: 'Glosas', roles: [...STAFF.filter((r) => r !== 'assistant'), 'client'], ready: true },
    { route: 'pagos', label: 'Pagos y conciliación', roles: ['super_admin', 'admin', 'billing', 'glosas', 'auditor', 'client'], ready: true },
    { route: 'honorarios', label: 'Honorarios SOFA', roles: ['super_admin', 'admin', 'auditor', 'client'], ready: true },   // nunca operations ni capturer
    { route: 'aging', label: 'Aging', roles: ['super_admin', 'admin', 'billing', 'glosas', 'auditor', 'client'], ready: true },
    { route: 'conciliacion', label: 'Conciliación bancaria', roles: ['super_admin', 'admin', 'glosas', 'auditor'], ready: true },   // 2.7 · Iteración 37
    { route: 'casos-servicio', label: 'Casos de servicio', roles: ['super_admin', 'admin', 'assistant', 'operations', 'auditor', 'glosas'], ready: true },   // 3.0 · Iteración 40 (espejo de app.case_staff)
    // 3.1 a 3.5 · Iteraciones 41 a 45 (espejo de los permisos de las migraciones 140 a 148)
    { route: 'ecf', label: 'Preparación e-CF', roles: ['super_admin', 'admin', 'assistant', 'operations', 'auditor', 'glosas'], ready: true },
    { route: 'preauditoria', label: 'Pre-auditoría de lotes', roles: ['super_admin', 'admin', 'billing', 'assistant', 'operations', 'glosas', 'auditor', 'client'], ready: true },
    { route: 'causas-glosa', label: 'Glosas: plazo y causa raíz', roles: ['super_admin', 'admin', 'glosas', 'auditor', 'operations', 'client'], ready: true },
    { route: 'cartera', label: 'Cartera escalonada', roles: ['super_admin', 'admin', 'glosas', 'auditor', 'client'], ready: true },
    { route: 'brechas-tarifa', label: 'Brechas de tarifa', roles: ['super_admin', 'admin', 'assistant', 'operations', 'auditor', 'glosas', 'client'], ready: true },
    // 3.6 a 4.0 · Iteraciones 46 a 50 (espejo de los permisos de las migraciones 150 a 158)
    { route: 'auditoria-expedientes', label: 'Auditoría de expedientes', roles: ['super_admin', 'admin', 'auditor', 'glosas', 'operations', 'client'], ready: true },
    { route: 'insumos', label: 'Insumos facturables', roles: ['super_admin', 'admin', 'operations', 'glosas', 'auditor', 'client', 'capturer'], ready: true },
    { route: 'mi-habilitacion', label: 'Mi habilitación', roles: ['super_admin', 'admin', 'assistant', 'operations', 'auditor', 'client'], ready: true },
    { route: 'direccion', label: 'Tablero de dirección', roles: ['super_admin', 'admin'], ready: true },
    { route: 'mis-horas', label: 'Mis horas', roles: ['super_admin', 'admin', 'glosas', 'assistant', 'operations', 'auditor'], ready: true },
    { route: 'salud-sistema', label: 'Seguridad y salud del sistema', roles: ['super_admin'], ready: true }
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
    { route: 'documentos', label: 'Documentos de radicaciones', roles: ALL, ready: true },
    { route: 'reportes', label: 'Reportes', roles: [...STAFF, 'client'], ready: true }
  ]},
  { group: 'Configuración', items: [
    { route: 'usuarios', label: 'Usuarios y roles', roles: ['super_admin', 'admin', 'auditor'], ready: true },
    { route: 'alta-usuarios', label: 'Crear o solicitar usuario', roles: ['super_admin', 'admin', 'client'], ready: true },   // 2.6.1: el consultorio solicita y el Super Admin aprueba   // 1.9 · el médico crea a sus secretarias
    { route: 'parametros', label: 'Parámetros', roles: ['super_admin', 'admin', 'auditor'], ready: true },
    { route: 'hc-control', label: 'Historia clínica: control', roles: ['super_admin'], ready: true },   // 2.0 · modo, MFA, bitácora
    { route: 'revision', label: 'Revisión del sistema', roles: ['super_admin'], ready: true }   // 2.6 · Iteración 36
  ]},
  { group: 'Mi cuenta', items: [
    { route: 'mi-cuenta-sofa', label: 'Mi cuenta con SOFA', roles: ['client'], ready: true },   // 3.0 · Iteración 40
    { route: 'perfil', label: 'Mi perfil', roles: [...ALL, 'capturer', 'prospect'], ready: true },
    { route: 'seguridad', label: 'Seguridad (dos pasos)', roles: [...ALL, 'capturer', 'prospect'], ready: true },   // 2.0 · MFA
    { route: 'diagnostico', label: 'Diagnóstico', roles: [...ALL, 'capturer', 'prospect'], ready: true },
    { route: 'cambio-clave', label: 'Cambiar contraseña', roles: [...ALL, 'capturer', 'prospect'], ready: true, hidden: true }   // 1.9 · también se abre sola en el primer acceso
  ]}
];

// Aplica el alcance de Facturación a todo el menú (una sola regla, no ruta por ruta)
NAV.forEach((g) => g.items.forEach((i) => { if (!BILLING_ROUTES.includes(i.route)) i.roles = i.roles.filter((r) => r !== 'billing'); }));

/**
 * 2.0 · Decisión 08/10/2026: el Médico solo ve su consultorio. Estos módulos son internos de SOFA
 * (cartera de clientes, catálogos y lotes) y se le ocultan. CLIENT_HIDDEN es la única lista que hay que tocar.
 */
export const CLIENT_HIDDEN = ['clientes', 'medicos', 'radicaciones', 'codificacion', 'ars', 'documentos', 'inicio'];
NAV.forEach((g) => g.items.forEach((i) => { if (CLIENT_HIDDEN.includes(i.route)) i.roles = i.roles.filter((r) => r !== 'client'); }));

/**
 * 2.1 · Menú por FAMILIAS (decisión 08/10/2026): las mismas familias, en el mismo orden y con el mismo ícono para todos.
 * Cada rol ve solo las familias y módulos a los que tiene acceso (NAV.roles). Lo que un rol pueda abrir y no esté
 * en una familia aparece al final en «Más», para que nada se pierda.
 */
export const FAMILIES = [
  { key: 'dia', group: 'Mi día', routes: ['mi-dashboard', 'mi-incorporacion', 'inicio', 'hoy', 'agenda', 'tareas', 'mis-horas'] },
  { key: 'clientes', group: 'Clientes y ventas', routes: ['clientes', 'casos-servicio', 'salud-clientes', 'oportunidades', 'prospectos', 'contactos', 'aliados', 'medicos', 'mercado'] },
  { key: 'facturacion', group: 'Facturación ARS', routes: ['captura', 'reclamaciones', 'preradicacion', 'preauditoria', 'ecf', 'radicaciones', 'retiros', 'requisitos', 'contratos', 'vencimientos', 'brechas-tarifa', 'codigos-ars', 'codificacion', 'ars'] },
  { key: 'cobros', group: 'Cobros', routes: ['glosas', 'causas-glosa', 'pagos', 'conciliacion', 'aging', 'cartera', 'calendario-cobros', 'analitica-glosas', 'honorarios'] },
  { key: 'consultorio', group: 'Consultorio', routes: ['mi-ficha', 'pacientes', 'historia-clinica', 'saldos-pacientes', 'seguimiento', 'avisos-pacientes', 'mensajes', 'indicadores-agenda', 'practica', 'tarifas-privadas', 'insumos', 'mis-secretarias', 'centros', 'habilitacion', 'mi-habilitacion'] },
  { key: 'resultados', group: 'Resultados', routes: ['direccion', 'dashboard', 'estado-cuenta', 'rentabilidad', 'auditoria-expedientes', 'reportes', 'guias'] },
  { key: 'admin', group: 'Administración', routes: ['usuarios', 'alta-usuarios', 'parametros', 'hc-control', 'revision', 'salud-sistema', 'documentos'] },
  { key: 'cuenta', group: 'Mi cuenta', routes: ['mi-cuenta-sofa', 'perfil', 'cambio-clave', 'seguridad', 'diagnostico'] }
];

export const allRoutes = () => NAV.flatMap((g) => g.items);
export const findRoute = (r) => allRoutes().find((i) => i.route === r) || null;
export const canSee = (route, role) => !!findRoute(route)?.roles.includes(role);
export const visibleNav = (role) => {
  const ok = (i) => i && !i.hidden && i.roles.includes(role);
  const used = new Set();
  const groups = FAMILIES.map((f) => ({ key: f.key, group: f.group, items: f.routes.map(findRoute).filter((i) => ok(i) && !used.has(i.route) && used.add(i.route)) }));
  const rest = allRoutes().filter((i) => ok(i) && !used.has(i.route));
  if (rest.length) groups.push({ key: 'mas', group: 'Más', items: rest });
  return groups.filter((g) => g.items.length);
};
export const isStaff = (role) => !!ROLES[role]?.staff;
/** ¿Puede este rol abrir el enlace? (#/radicaciones/123 → módulo "radicaciones"). Para no mostrar enlaces que llevan a "Sin acceso". */
export const canOpen = (href, role) => canSee(String(href || '').replace(/^#\/?/, '').split('/')[0], role);
/** Ruta inicial por rol. 1.9: todos entran a «Mi dashboard», que muestra las cifras de su rol y accesos a sus módulos. */
export const homeRoute = (role) => (role === 'prospect' ? 'mi-incorporacion' : canSee('mi-dashboard', role) ? 'mi-dashboard' : (role === 'capturer' || role === 'billing' ? 'hoy' : 'inicio'));
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
  'capturers.assign': ['super_admin', 'admin'],
  // Iteración 13 · expediente por reclamación (espejo de 028_expediente.sql)
  'dossier.upload': ['super_admin', 'admin', 'billing', 'glosas', 'assistant', 'operations', 'client', 'capturer'],
  'dossier.physical': ['super_admin', 'admin', 'billing', 'assistant', 'operations', 'client', 'capturer'],
  'dossier.exception': ['super_admin', 'admin', 'auditor'],
  'dossier.delete': ['super_admin', 'admin'],
  // Iteración 14
  'fees.cleanup': ['super_admin'],   // 1.7: limpieza del libro de honorarios
  'onboarding.manage': ['super_admin', 'admin', 'assistant', 'operations'],   // 1.5: documentos A–E, pasos y activación
  'onboarding.override': ['super_admin', 'admin'],                             // activar con el onboarding incompleto
  'claims.resubmit': ['super_admin', 'admin', 'billing'],                                        // reenvío en radicación complementaria
  'stages.view': ['super_admin', 'admin', 'billing', 'glosas', 'auditor', 'operations', 'assistant', 'client'],
  'rules.edit': ['super_admin', 'admin'],
  'submissions.send': ['super_admin', 'admin', 'billing', 'operations'],
  // 1.9 · Iteraciones 18 a 28
  'appointments.attend': ['super_admin', 'admin', 'assistant', 'operations', 'client', 'capturer'],   // atender cita y crear su reclamación (094)
  'users.create': ['super_admin', 'admin', 'client'],
  'users.reset': ['super_admin'],                                                                    // 2.1 · restablecer contraseña
  'users.prospect': ['super_admin', 'admin', 'assistant'],                                           // 2.1 · usuarios de prospectos
  'arscodes.edit': ['super_admin', 'admin', 'assistant', 'operations', 'billing', 'client'],         // 2.1 · espejo de app.ars_codes_can_edit (114)
  'arscodes.followup': ['super_admin', 'admin', 'assistant', 'operations'],                         // 2.3 · espejo de ars_codes_followup (118)
  'ars.edit': ['super_admin', 'admin'],                                                              // 2.6.1 · espejo de app.ars_admin_require (126)
  'users.approve': ['super_admin'],                                                                  // 2.6.1 · aprobar solicitudes de usuario (128)
  'clinical.import': ['super_admin'],                                                                // 2.6.1 · importar historias (128)
  'bank.reconcile': ['super_admin', 'admin', 'glosas'],                                              // 2.7 · espejo de app.bank_require (130)
  'bank.admin': ['super_admin', 'admin'],                                                            // 2.7 · registrar pagos y deshacer conciliaciones
  'cases.edit': ['super_admin', 'admin', 'assistant', 'operations'],                                 // 3.0 · espejo de app.case_staff(true) (138)
  'notices.edit': ['super_admin', 'admin', 'client'],                                                // 2.9 · espejo de patient_notice_settings_save (136)
  'ecf.steps': ['super_admin', 'admin', 'assistant', 'operations', 'client'],                        // 3.1 · espejo de app.ecf_require (140)
  'ecf.providers': ['super_admin', 'admin'],                                                         // 3.1 · ecf_provider_save
  'glosas.root': ['super_admin', 'admin', 'glosas'],                                                 // 3.3 · acciones correctivas (144)
  'holidays.edit': ['super_admin', 'admin'],                                                         // 3.3 · feriados
  'collections.edit': ['super_admin', 'admin', 'glosas'],                                            // 3.4 · app.collection_access (146)
  'collections.templates': ['super_admin', 'admin'],                                                 // 3.4 · cartas modelo
  'legalaudit.edit': ['super_admin', 'admin', 'auditor'],                                            // 3.6 · app.legal_audit_staff(true) (150)
  'legalaudit.settings': ['super_admin', 'admin'],                                                   // 3.6 · activar por cliente
  'supplies.admin': ['super_admin', 'admin', 'operations', 'client'],                                // 3.7 · app.supply_access 'admin' (152)
  'direction.view': ['super_admin', 'admin'],                                                        // 3.9 · app.direction_require (156)
  'direction.goals': ['super_admin'],                                                                // 3.9 · direction_settings_save
  'security.admin': ['super_admin']                                                                  // 4.0 · app.sa_require (158)
};
export const can = (action, role) => !!ACTIONS[action]?.includes(role);
