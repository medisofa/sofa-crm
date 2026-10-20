/**
 * SOFA · Roles y navegación.
 * IMPORTANTE: esto solo decide qué se muestra. La seguridad real está en
 * PostgreSQL (RLS y funciones). Ocultar un menú no es un control de acceso.
 */
export const ROLES = Object.freeze({   // nombres según la tabla de roles (auditoría Fase 1, sección 9) · 1.6.1
  super_admin: { name: 'Super Admin SOFA', staff: true, desc: 'Todo el sistema, incluidos usuarios, parámetros y datos fiscales.' },
  admin: { name: 'Administrador SOFA', staff: true, desc: 'Operación completa de SOFA: radicación, pagos, glosas, honorarios, tarifarios y usuarios.' },
  operations: { name: 'Operaciones SOFA', staff: true, desc: 'Retiro físico, validación, onboarding y bandejas; sin honorarios.' },
  billing: { name: 'Facturación y Radicación', staff: true, desc: 'Prepara, valida y radica reclamaciones; no registra pagos ARS ni administra glosas.' },
  glosas: { name: 'Cobros, Conciliación y Glosas', staff: true, desc: 'Registra pagos ARS, concilia, distribuye pagos y gestiona glosas y recuperaciones.' },
  assistant: { name: 'Comercial / Onboarding', staff: true, desc: 'Prospectos, CRM, propuestas, onboarding y seguimiento comercial; sin operación financiera ARS.' },
  auditor: { name: 'Auditor de Expedientes', staff: true, desc: 'Audita expedientes, trazabilidad y controles; acceso preferentemente de lectura.' },
  client: { name: 'Médico / Cliente', staff: false, desc: 'Dueño de la práctica: su consultorio completo (agenda, reclamaciones, cobros, Mi práctica y sus honorarios SOFA).' },
  capturer: { name: 'Secretaria / Capturista', staff: false, desc: 'Agenda, captura, cobros a privados y cuadre de los médicos que se le asignan; sin pagos de ARS, glosas ni honorarios.' },
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
export const BILLING_ROUTES = ['autoentrenamiento', 'mi-dashboard', 'hoy', 'dashboard', 'captura', 'reclamaciones', 'retiros', 'radicaciones', 'perfil', 'diagnostico', 'cambio-clave', 'seguridad', 'mi-bandeja', 'reconsideracion', 'expediente', 'mis-avisos', 'novedades'];   // 4.9 · I59: + Mi bandeja · 5.0 · I60/I62/I63: + Reconsideración, Expediente digital y Mis avisos // 2.0: + cambiar contraseña y seguridad (antes «Cambiar contraseña» le daba «Sin acceso»)

/**
 * Menú (§33). iteration = cuándo llega el módulo completo.
 * ready = ya funciona en esta iteración (con los permisos de la base de datos).
 * hidden = la ruta existe pero no se muestra en el menú (se abre desde otra pantalla).
 */
export const NAV = [
  { group: 'Operación', items: [
    { route: 'mi-dashboard', label: 'Inicio', roles: [...ALL, 'capturer'], ready: true },
    { route: 'autoentrenamiento', label: 'Mi autoentrenamiento', roles: Object.keys(ROLES), ready: true },   // 1.9 · primera página según el rol · 2.0: se llama «Inicio»
    { route: 'inicio', label: 'Panel SOFA', roles: STAFF, ready: true },   // 2.0: el panel general queda para el personal de SOFA
    { route: 'hoy', label: 'Trabajo de hoy', roles: [...ALL, 'capturer'], ready: true },
    { route: 'mi-bandeja', label: 'Mi bandeja', roles: ['super_admin', 'admin', 'operations', 'billing'], ready: true },   // 4.9 · I59
    { route: 'agenda', label: 'Agenda del consultorio', roles: ['super_admin', 'admin', 'assistant', 'operations', 'client', 'capturer'], ready: true },   // 1.6
    { route: 'practica', label: 'Mi práctica', roles: ['super_admin', 'admin', 'assistant', 'operations', 'client'], ready: true },
    { route: 'hospitalizacion', label: 'Hospitalización', roles: ['client', 'super_admin', 'admin', 'operations'], ready: true },   // 5.7 · I68a
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
    { route: 'mi-dinero', label: 'Mi dinero', roles: ['client', 'super_admin', 'admin', 'operations'], ready: true },   // 5.8
    { route: 'mis-glosas', label: 'Mis glosas', roles: ['client', 'super_admin', 'admin', 'operations'], ready: true },   // 5.8
    { route: 'mi-productividad', label: 'Mi productividad', roles: ['client', 'super_admin', 'admin', 'operations'], ready: true },   // 5.9
    { route: 'reporte-contador', label: 'Reporte para mi contador', roles: ['client', 'super_admin', 'admin'], ready: true },   // 5.12 · espejo de accountant_report
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
    { route: 'solicitudes', label: 'Solicitudes', roles: ['super_admin', 'admin', 'assistant', 'operations'], ready: true },   // 5.15.0 · I72: lo que entra por el enlace público
    { route: 'clientes', label: 'Clientes (ficha)', roles: ALL, ready: true },
    { route: 'salud-clientes', label: 'Salud de los clientes', roles: ['super_admin', 'admin', 'assistant', 'operations'], ready: true },   // 1.9 · Iteración 28
    { route: 'medicos', label: 'Médicos 360', roles: ALL, ready: true },
    { route: 'contactos', label: 'Contactos', roles: ['super_admin', 'admin', 'assistant', 'auditor'], ready: true },
    { route: 'aliados', label: 'Aliados referidores', roles: ['super_admin', 'admin', 'auditor'], ready: true }
  ]},
  { group: 'Facturación y Radicación', items: [
    { route: 'carga-google', label: 'Carga Google Sheets / Form', roles: ['super_admin','admin','operations','billing'], ready: true },
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
    { route: 'salud-sistema', label: 'Seguridad y salud del sistema', roles: ['super_admin'], ready: true },
    // 4.1 a 4.5 · Iteraciones 51 a 55 (espejo de los permisos de las migraciones 160 a 168)
    { route: 'propuestas', label: 'Diagnóstico y propuestas', roles: ['super_admin', 'admin', 'assistant'], ready: true },
    { route: 'fugas', label: 'Auditoría de Fugas', roles: ['super_admin', 'admin', 'assistant'], ready: true },
    { route: 'verificacion', label: 'Verificación de mañana', roles: ['super_admin', 'admin', 'assistant', 'operations', 'client', 'capturer'], ready: true },
    { route: 'informe-trimestral', label: 'Informe trimestral', roles: ['super_admin', 'admin', 'assistant', 'operations', 'glosas', 'auditor', 'client'], ready: true },
    { route: 'casos-exito', label: 'Casos de éxito y referidos', roles: ['super_admin', 'admin', 'assistant', 'auditor'], ready: true },
    { route: 'recomendar', label: 'Recomendar a un colega', roles: ['client'], ready: true },
    { route: 'onboarding-30', label: 'Onboarding 30 días', roles: ['super_admin', 'admin', 'assistant', 'operations'], ready: true },
    { route: 'mis-30-dias', label: 'Mis primeros 30 días', roles: ['client'], ready: true },
    { route: 'tarifas-versiones', label: 'Versiones de tarifario', roles: ['super_admin', 'admin', 'operations', 'assistant', 'auditor', 'glosas'], ready: true },   // 4.9 · I57 (no Facturación)
    { route: 'aplicar-pago', label: 'Aplicar pago de la ARS', roles: ['super_admin', 'admin', 'glosas'], ready: true },   // 4.9 · I58
    // 5.0.0 · I60 a I62 (espejo de los permisos de las migraciones 192, 194 y 196)
    { route: 'reconsideracion', label: 'Reconsideración de glosas', roles: ['super_admin', 'admin', 'glosas', 'billing', 'client'], ready: true },   // I60 (Facturación y Médico en solo lectura)
    { route: 'calidad-captura', label: 'Calidad de captura', roles: ['super_admin', 'admin', 'operations', 'capturer'], ready: true },   // I61 (no Facturación)
    { route: 'expediente', label: 'Expediente digital', roles: ['super_admin', 'admin', 'operations', 'billing', 'glosas', 'assistant', 'auditor', 'client', 'capturer'], ready: true }   // I62
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
    { route: 'permisos', label: 'Permisos y menús', roles: ['super_admin', 'admin'], ready: true },   // 5.17.0 · I73
    { route: 'alta-usuarios', label: 'Crear o solicitar usuario', roles: ['super_admin', 'admin', 'client'], ready: true },   // 2.6.1: el consultorio solicita y el Super Admin aprueba   // 1.9 · el médico crea a sus secretarias
    { route: 'parametros', label: 'Parámetros', roles: ['super_admin', 'admin', 'auditor'], ready: true },
    { route: 'hc-control', label: 'Historia clínica: control', roles: ['super_admin'], ready: true },   // 2.0 · modo, MFA, bitácora
    { route: 'revision', label: 'Revisión del sistema', roles: ['super_admin'], ready: true },   // 2.6 · Iteración 36
    { route: 'planes', label: 'Planes de los clientes', roles: ['super_admin', 'admin'], ready: true },   // 4.8 · P1: asignar planes y bloqueo por plan
    { route: 'suscripciones', label: 'Suscripciones y pre-facturas', roles: ['super_admin', 'admin'], ready: true },   // 4.9 · P2
    { route: 'puesta-en-marcha', label: 'Puesta en marcha de clientes', roles: ['super_admin', 'admin', 'operations'], ready: true },   // 4.9 · I56
    { route: 'cola-correos', label: 'Cola de correos', roles: ['super_admin', 'admin'], ready: true },   // 5.0 · I63
    { route: 'rendimiento', label: 'Rendimiento y archivo', roles: ['super_admin', 'admin', 'operations'], ready: true }   // 5.0 · I64 (Operaciones solo consulta)
  ]},
  { group: 'Mi cuenta', items: [
    { route: 'mi-cuenta-sofa', label: 'Mi cuenta con SOFA', roles: ['client'], ready: true },   // 3.0 · Iteración 40
    { route: 'clinica', label: 'Mi clínica', roles: ['client', 'super_admin', 'admin', 'operations'], ready: true },   // 5.6 · I66
    { route: 'mi-plan', label: 'Mi plan', roles: ['client', 'super_admin', 'admin', 'operations', 'assistant'], ready: true },   // 4.8 · P1: consumo y límites del plan
    { route: 'mi-suscripcion', label: 'Mi suscripción', roles: ['client', 'super_admin', 'admin'], ready: true },   // 4.9 · P2
    { route: 'mi-puesta-en-marcha', label: 'Mi puesta en marcha', roles: ['client'], ready: true },   // 4.9 · I56
    { route: 'mis-avisos', label: 'Mis avisos por correo', roles: ['client', 'super_admin', 'admin', 'operations', 'billing', 'glosas'], ready: true },   // 5.0 · I63
    { route: 'novedades', label: 'Novedades', roles: [...ALL, 'capturer', 'prospect'], ready: true },   // 5.5.0 · I65
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
 * 5.10.0 · Decisión 16/10/2026: el menú se arma desde las FUNCIONES de cada rol.
 * Generaliza lo que ya hacían BILLING_ROUTES y CLIENT_HIDDEN, en una sola tabla.
 *
 *   menu  = lo que el rol usa para trabajar. Es lo único que se muestra en el menú.
 *   extra = lo que puede abrir por enlace o por URL, pero no ocupa espacio en el menú:
 *           configuración que se toca una vez, o el detalle al que se llega desde otra pantalla.
 *
 * Lo que no esté en ninguna de las dos listas se le RETIRA al rol: no lo ve y no lo puede abrir.
 * Un rol que no aparezca en esta tabla conserva el menú completo (hoy: super_admin y admin).
 *
 * Recordatorio: esto es presentación y alcance de interfaz. El control real sigue en RLS.
 */
export const ESENCIALES = {

  // Médico · atiende, registra lo que hizo, cobra al privado y sabe cuánto gana.
  // 16/10/2026: ningún médico usaba las pantallas del equipo de facturación. Las sustituyen
  // Mi dinero, Mis glosas y Mi productividad, que dicen lo mismo en su idioma.
  client: {
    menu: ['mi-dashboard', 'agenda', 'pacientes', 'historia-clinica', 'saldos-pacientes',
           'captura', 'hospitalizacion',
           'mi-dinero', 'mis-glosas', 'mi-productividad', 'reporte-contador',
           'mi-ficha', 'tarifas-privadas', 'mis-secretarias', 'centros',
           'mi-cuenta-sofa', 'novedades', 'perfil', 'seguridad'],
    // 18/10/2026: estas cinco vuelven, pero SOLO en «extra»: alcanzables desde un botón de
    // «Mi dinero» o «Mis glosas», sin llenarle el menú. Sin esto, el PDF del estado de cuenta
    // y las fechas de cobro quedaban construidos y fuera del alcance del médico, y tres notas
    // de la propia aplicación lo mandaban a «Sin acceso».
    extra: ['hoy', 'verificacion', 'reclamaciones', 'expediente', 'retiros',
            'mensajes', 'seguimiento', 'avisos-pacientes', 'indicadores-agenda', 'practica',
            'insumos', 'clinica', 'habilitacion', 'mi-habilitacion', 'alta-usuarios',
            'mi-plan', 'mi-suscripcion', 'mis-avisos', 'mi-puesta-en-marcha', 'mis-30-dias',
            'recomendar', 'diagnostico', 'cambio-clave',
            'estado-cuenta', 'calendario-cobros', 'rentabilidad', 'analitica-glosas', 'reconsideracion']
  },

  // Secretaria · agenda, captura y cobro al paciente privado. Ya estaba bien dimensionado.
  capturer: {
    menu: ['mi-dashboard', 'agenda', 'verificacion', 'pacientes', 'captura', 'reclamaciones',
           'expediente', 'saldos-pacientes', 'mensajes', 'perfil', 'seguridad'],
    extra: ['hoy', 'calidad-captura', 'insumos', 'novedades', 'diagnostico', 'cambio-clave']
  },

  // Facturación · perfil de referencia desde el 01/10/2026. BILLING_ROUTES sigue siendo su tope.
  billing: {
    menu: ['mi-dashboard', 'hoy', 'mi-bandeja', 'captura', 'carga-google', 'reclamaciones', 'expediente',
           'retiros', 'radicaciones', 'reconsideracion', 'perfil', 'seguridad'],
    extra: ['dashboard', 'mis-avisos', 'novedades', 'diagnostico', 'cambio-clave']
  },

  // Cobros · aplicar el pago de la ARS, repartirlo, conciliar el banco y pelear la glosa.
  // La pre-radicación y los catálogos son de Operaciones.
  glosas: {
    menu: ['mi-dashboard', 'hoy', 'reclamaciones',
           'glosas', 'reconsideracion', 'causas-glosa', 'analitica-glosas',
           'pagos', 'aplicar-pago', 'conciliacion', 'aging', 'cartera', 'calendario-cobros',
           'perfil', 'seguridad'],
    extra: ['inicio', 'expediente', 'contratos', 'radicaciones', 'preauditoria', 'tareas',
            'mis-horas', 'documentos', 'clientes', 'medicos', 'casos-servicio', 'insumos',
            'dashboard', 'reportes', 'informe-trimestral', 'auditoria-expedientes', 'guias',
            'mis-avisos', 'novedades', 'diagnostico', 'cambio-clave']
  },

  // Comercial · conseguir el cliente, proponerle, incorporarlo y mantenerlo sano.
  // No opera la línea ARS; sí hace los documentos A–E y persigue los códigos con la ARS.
  assistant: {
    menu: ['mi-dashboard', 'hoy', 'tareas',
           'solicitudes', 'oportunidades', 'prospectos', 'contactos', 'clientes', 'propuestas', 'fugas',
           'onboarding-30', 'salud-clientes', 'casos-exito', 'medicos', 'mercado',
           'habilitacion', 'codigos-ars', 'perfil', 'seguridad'],
    extra: ['inicio', 'mis-horas', 'casos-servicio', 'mi-habilitacion', 'radicaciones',
            'expediente', 'ecf',   // conserva dossier.upload y ecf.steps en la matriz de acciones
            'mi-plan', 'guias', 'reportes', 'dashboard', 'informe-trimestral', 'documentos',
            'novedades', 'diagnostico', 'cambio-clave']
  },

  // Auditor · decide si el expediente está completo y deja constancia.
  // 16/10/2026: pierde Usuarios y roles y Parámetros — son del Administrador y del Super Admin.
  // Su "consulta todo" se conserva en `extra`: puede abrirlo, pero no le llena el menú diario.
  auditor: {
    menu: ['mi-dashboard', 'hoy', 'auditoria-expedientes', 'expediente', 'reclamaciones',
           'requisitos', 'preauditoria', 'glosas', 'reportes', 'perfil', 'seguridad'],
    extra: ['inicio', 'tareas', 'mis-horas', 'contratos', 'causas-glosa', 'analitica-glosas',
            'pagos', 'conciliacion', 'aging', 'cartera', 'calendario-cobros', 'honorarios',
            'estado-cuenta', 'rentabilidad', 'dashboard', 'informe-trimestral', 'guias',
            'documentos', 'clientes', 'medicos', 'casos-servicio', 'radicaciones',
            'codificacion', 'ars', 'preradicacion', 'ecf', 'retiros', 'vencimientos',
            'brechas-tarifa', 'codigos-ars', 'tarifas-versiones', 'habilitacion',
            'mi-habilitacion', 'insumos', 'mercado', 'oportunidades', 'prospectos',
            'contactos', 'aliados', 'casos-exito', 'novedades', 'diagnostico', 'cambio-clave']
  },

  // Operaciones · retiro físico, validación, radicación, calidad de captura y puesta en marcha.
  // 16/10/2026: es una función interna de SOFA. No ve información privada del cliente —
  // ni su agenda, ni sus mensajes a pacientes, ni su dinero, ni su clínica.
  operations: {
    menu: ['mi-dashboard', 'hoy', 'mi-bandeja', 'tareas',
           'clientes', 'salud-clientes', 'puesta-en-marcha', 'onboarding-30',
           'retiros', 'preradicacion', 'radicaciones', 'preauditoria', 'ecf',
           'requisitos', 'reclamaciones', 'expediente', 'calidad-captura',
           'perfil', 'seguridad'],
    extra: ['inicio', 'captura',   // conserva claims.capture en la matriz de acciones
            'solicitudes',             // 5.15.0: puede abrirla por enlace; no es su trabajo diario
            'medicos', 'casos-servicio', 'contratos', 'vencimientos',
            'brechas-tarifa', 'codigos-ars', 'codificacion', 'ars', 'tarifas-versiones',
            'causas-glosa', 'analitica-glosas', 'auditoria-expedientes', 'insumos',
            'mi-habilitacion', 'documentos', 'rendimiento', 'informe-trimestral', 'reportes',
            'mis-horas', 'mis-avisos', 'novedades', 'diagnostico', 'cambio-clave']
  },

  // Administrador · administra SOFA como empresa. extra:'*' = NO se le retira nada;
  // solo se acorta el menú diario. Todo lo demás sigue a un clic desde el buscador.
  admin: {
    menu: ['mi-dashboard', 'inicio', 'hoy', 'mi-bandeja', 'clientes', 'salud-clientes', 'direccion',
           'usuarios', 'permisos', 'alta-usuarios', 'parametros', 'planes', 'suscripciones', 'puesta-en-marcha',
           'cola-correos', 'rendimiento', 'solicitudes', 'perfil', 'seguridad'],
    extra: '*'
  },

  // Super Admin · lo del Administrador más el control del sistema. También extra:'*'.
  super_admin: {
    menu: ['mi-dashboard', 'inicio', 'hoy', 'mi-bandeja', 'clientes', 'salud-clientes', 'direccion',
           'usuarios', 'permisos', 'alta-usuarios', 'parametros', 'planes', 'suscripciones', 'puesta-en-marcha',
           'cola-correos', 'rendimiento', 'salud-sistema', 'revision', 'hc-control', 'solicitudes', 'perfil', 'seguridad'],
    extra: '*'
  },

  // Prospecto · solo el avance de su incorporación.
  prospect: {
    menu: ['mi-incorporacion', 'perfil', 'seguridad'],
    extra: ['novedades', 'diagnostico', 'cambio-clave']
  }
};

// Autoentrenamiento es personal y obligatorio para todos los roles. Se agrega aquí para que
// los perfiles reducidos no lo pierdan cuando ESENCIALES recorta su alcance.
Object.values(ESENCIALES).forEach((def) => {
  if (Array.isArray(def.menu) && !def.menu.includes('autoentrenamiento')) def.menu.push('autoentrenamiento');
});

// 1) Alcance: lo que no está en menu+extra se le retira al rol (no lo ve y no lo puede abrir).
Object.entries(ESENCIALES).forEach(([rol, def]) => {
  if (def.extra === '*') return;   // 5.11.0: '*' significa «no le quites nada»; solo se acorta su menú
  const permitido = new Set([...def.menu, ...def.extra]);
  NAV.forEach((g) => g.items.forEach((i) => {
    if (!permitido.has(i.route)) i.roles = i.roles.filter((r) => r !== rol);
  }));
});

/** 5.10.0 · ¿esta ruta va en el menú de este rol? (`extra` se abre por enlace, no se lista)
 *  5.16.1 · Corrección: a los roles con `extra: '*'` —Administrador y Super Admin— se les acortó
 *  el menú a 21 de 96 módulos, dejando 75 solo por el buscador. Nunca se les quitó un acceso,
 *  pero el menú ES el mapa del sistema para quien tiene que supervisarlo todo, y sin él la
 *  herramienta se siente rota. `extra: '*'` ya significaba «no le quites nada»: ahora también
 *  significa «no le escondas nada». Su `menu` sigue sirviendo para destacar lo del día a día. */
export const enMenu = (role, route) => {
  const o = OVERRIDE[role] && OVERRIDE[role][route];
  if (o) return o.en_menu !== false;      // 5.17.0 · lo que el Super Admin dejó configurado
  const def = ESENCIALES[role];
  if (!def) return true;
  if (def.extra === '*') return true;
  return def.menu.includes(route);
};

/* ── 5.17.0 · I73 · El menú configurable desde «Permisos y menús» ────────────────────────────────
 *
 *  ESTO SOLO DECIDE QUÉ SE LISTA. Es deliberado y es la propiedad que hace seguro el panel:
 *  `OVERRIDE` alimenta ÚNICAMENTE a `enMenu()`, que dice si una ruta sale en la barra izquierda.
 *  No lo tocan `canSee()` ni `canOpen()`, que son los que dejan entrar a una pantalla, ni tiene
 *  nada que ver con las políticas RLS, que son las que de verdad protegen los datos.
 *
 *  Por construcción, lo peor que puede hacer una configuración equivocada aquí es ensuciar el
 *  menú de alguien. No abre ni una fila de datos que la base no le abriría de todos modos.
 *
 *  Y si no se aplica nada —la base no responde, la tabla está vacía, el usuario no tiene
 *  permiso para leerla— mandan los valores del código, que son los de siempre. */
let OVERRIDE = {};

/** La llama app.js al arrancar, con lo que devuelve role_menu_get(). Si algo viene raro,
 *  no se aplica nada: es preferible el menú de siempre a un menú a medias. */
export function aplicarMenu(config) {
  if (!config || typeof config !== 'object' || Array.isArray(config)) { OVERRIDE = {}; return 0; }
  const limpio = {};
  let n = 0;
  for (const [rol, rutas] of Object.entries(config)) {
    if (!ROLES[rol] || !rutas || typeof rutas !== 'object') continue;
    if (rol === 'super_admin') continue;   // su menú no se configura: siempre lo ve todo
    const r = {};
    for (const [ruta, def] of Object.entries(rutas)) {
      // Una ruta que este rol no puede ver NO entra al menú por estar configurada aquí.
      if (!findRoute(ruta) || !canSee(ruta, rol)) continue;
      // Las obligatorias nunca se apagan, pase lo que pase en la configuración.
      const obligatoria = OBLIGATORIAS.includes(ruta);
      r[ruta] = { en_menu: obligatoria ? true : def.en_menu !== false,
                  familia: def.familia || null,
                  orden: Number.isFinite(Number(def.orden)) ? Number(def.orden) : 100 };
      n += 1;
    }
    if (Object.keys(r).length) limpio[rol] = r;
  }
  OVERRIDE = limpio;
  return n;
}

/** Sin red o sin permiso: se vuelve a los valores del código. */
export const olvidarMenu = () => { OVERRIDE = {}; };

/** Lo que el panel necesita saber sin consultar la base: qué puede ver cada rol de verdad. */
export const rutasDelRol = (role) => allRoutes()
  .filter((i) => i && !i.hidden && i.roles.includes(role))
  .map((i) => ({ route: i.route, label: i.label, familia: familiaDe(i.route, role),
                 en_menu: enMenu(role, i.route), obligatoria: OBLIGATORIAS.includes(i.route) }));

const OBLIGATORIAS = ['autoentrenamiento', 'perfil', 'seguridad'];

/** En qué familia cae hoy una ruta, para ese rol. */
function familiaDe(route, role) {
  const fams = FAMILIAS_ROL[role] || FAMILIES;
  const f = fams.find((x) => x.routes.includes(route));
  return f ? f.key : null;
}


/**
 * 2.1 · Menú por FAMILIAS (decisión 08/10/2026): las mismas familias, en el mismo orden y con el mismo ícono para todos.
 * Cada rol ve solo las familias y módulos a los que tiene acceso (NAV.roles). Lo que un rol pueda abrir y no esté
 * en una familia aparece al final en «Más», para que nada se pierda.
 */
export const FAMILIES = [
  { key: 'dia', group: 'Mi día', routes: ['mi-dashboard', 'mi-incorporacion', 'inicio', 'hoy', 'mi-bandeja', 'agenda', 'verificacion', 'tareas', 'mis-horas'] },
  { key: 'clientes', group: 'Clientes y ventas', routes: ['clientes', 'onboarding-30', 'casos-servicio', 'propuestas', 'fugas', 'casos-exito', 'salud-clientes', 'oportunidades', 'solicitudes', 'prospectos', 'contactos', 'aliados', 'medicos', 'mercado'] },
  { key: 'facturacion', group: 'Facturación y Radicación', routes: ['captura', 'carga-google', 'calidad-captura', 'reclamaciones', 'expediente', 'preradicacion', 'preauditoria', 'ecf', 'radicaciones', 'retiros', 'requisitos', 'contratos', 'vencimientos', 'brechas-tarifa', 'codigos-ars', 'codificacion', 'ars', 'tarifas-versiones'] },
  { key: 'cobros', group: 'Cobros, Conciliación y Glosas', routes: ['glosas', 'reconsideracion', 'causas-glosa', 'pagos', 'aplicar-pago', 'conciliacion', 'aging', 'cartera', 'calendario-cobros', 'analitica-glosas', 'honorarios'] },
  { key: 'consultorio', group: 'Consultorio', routes: ['mi-ficha', 'pacientes', 'historia-clinica', 'saldos-pacientes', 'seguimiento', 'avisos-pacientes', 'mensajes', 'indicadores-agenda', 'practica', 'hospitalizacion', 'tarifas-privadas', 'insumos', 'mis-secretarias', 'centros', 'clinica', 'habilitacion', 'mi-habilitacion'] },
  { key: 'resultados', group: 'Resultados', routes: ['mi-dinero', 'mis-glosas', 'mi-productividad', 'reporte-contador', 'direccion', 'dashboard', 'estado-cuenta', 'informe-trimestral', 'rentabilidad', 'auditoria-expedientes', 'reportes', 'guias'] },
  { key: 'admin', group: 'Administración', routes: ['usuarios', 'permisos', 'alta-usuarios', 'parametros', 'hc-control', 'revision', 'salud-sistema', 'rendimiento', 'cola-correos', 'documentos', 'planes', 'suscripciones', 'puesta-en-marcha'] },
  { key: 'cuenta', group: 'Mi cuenta', routes: ['autoentrenamiento', 'mi-cuenta-sofa', 'mi-plan', 'mi-suscripcion', 'mis-avisos', 'mi-puesta-en-marcha', 'mis-30-dias', 'recomendar', 'novedades', 'perfil', 'cambio-clave', 'seguridad', 'diagnostico'] }
];

/**
 * 5.10.0 · Familias propias para los perfiles que no hablan el idioma interno de SOFA.
 * Los roles que no estén aquí usan FAMILIES, que sigue siendo la estructura común del equipo.
 */
export const FAMILIAS_ROL = {
  client: [
    { key: 'dia',         group: 'Mi día',        routes: ['mi-dashboard', 'agenda'] },
    { key: 'pacientes',   group: 'Mis pacientes', routes: ['pacientes', 'historia-clinica', 'saldos-pacientes'] },
    { key: 'trabajo',     group: 'Mi trabajo',    routes: ['captura', 'hospitalizacion'] },
    { key: 'dinero',      group: 'Mi dinero',     routes: ['mi-dinero', 'mis-glosas', 'mi-productividad', 'reporte-contador'] },
    { key: 'consultorio', group: 'Mi consultorio',routes: ['mi-ficha', 'tarifas-privadas', 'mis-secretarias', 'centros', 'clinica'] },
    { key: 'cuenta',      group: 'Mi cuenta',     routes: ['autoentrenamiento', 'mi-cuenta-sofa', 'novedades', 'perfil', 'seguridad'] }
  ]
};

export const allRoutes = () => NAV.flatMap((g) => g.items);
export const findRoute = (r) => allRoutes().find((i) => i.route === r) || null;
export const canSee = (route, role) => !!findRoute(route)?.roles.includes(role);
export const visibleNav = (role) => {
  const ok = (i) => i && !i.hidden && i.roles.includes(role) && enMenu(role, i.route);   // 5.10.0 · el menú solo lista lo esencial del rol
  const used = new Set();
  const groups = (FAMILIAS_ROL[role] || FAMILIES).map((f) => ({ key: f.key, group: f.group, items: f.routes.map(findRoute).filter((i) => ok(i) && !used.has(i.route) && used.add(i.route)) }));
  const rest = allRoutes().filter((i) => ok(i) && !used.has(i.route));
  if (rest.length) groups.push({ key: 'mas', group: 'Más', items: rest });
  return groups.filter((g) => g.items.length);
};
/**
 * 5.11.0 · Lo que este rol PUEDE abrir pero no está en su menú.
 * Es lo que alimenta el buscador: sin esto, `extra` sería accesible pero invisible.
 * Respeta `hidden` igual que visibleNav (esas rutas se abren desde otra pantalla, no se listan).
 */
export const extraNav = (role) => allRoutes().filter(
  (i) => i && !i.hidden && i.roles.includes(role) && !enMenu(role, i.route)
);

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
  'payments.create': ['super_admin', 'admin', 'glosas'],
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
  'claims.google_import': ['super_admin','admin','operations','billing'],
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
  'security.admin': ['super_admin'],                                                                 // 4.0 · app.sa_require (158)
  'sales.proposals': ['super_admin', 'admin', 'assistant'],                                          // 4.1 · app.sales_require (160)
  'success.edit': ['super_admin', 'admin', 'assistant'],                                             // 4.4 · casos de éxito (166)
  'onboarding.review': ['super_admin', 'admin', 'assistant', 'operations']                           // 4.5 · onboarding_review_add (168)
};
export const can = (action, role) => !!ACTIONS[action]?.includes(role);
/** Funciones visibles para el autoentrenamiento y otras vistas por rol. */
export const accionesDelRol = (role) => Object.entries(ACTIONS).filter(([, roles]) => roles.includes(role)).map(([action]) => action).sort();
