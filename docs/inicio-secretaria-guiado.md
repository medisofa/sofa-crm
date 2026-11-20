# Inicio guiado de secretaría · 5.40.1

Sobre el inicio clínico existente, el rol `capturer` ve tres acciones principales: Agendar cita (abre Agenda), Buscar paciente (abre Pacientes) y Ver pendientes (enfoca la tarjeta de pendientes). La guía desplegable explica cómo crear una cita real; no contiene simulación ni genera registros. Otra ayuda explica los estados.

Se mantienen el consultorio activo, los médicos de cada cita y el alcance según asignación. El resumen puede incluir varios médicos: no presenta uno como activo sin una selección. Médico, asistente y administración conservan su composición. En soporte no se muestra la guía de secretaría. Los enlaces usan `canSee`; no se modifican servicios, RPC, permisos ni base de datos. La actualización del service worker acompaña la versión del frontend.

Validación con datos ficticios: inicio clínico por organización/fecha, ausencia de consultas en soporte individual, ausencia de escrituras, rutas permitidas, guía mediante teclado, foco en pendientes, errores y vacíos, 320/390/1440 px y temas claro/oscuro. No acredita aislamiento real de base de datos ni despliegue.

El test histórico `tests/navigation-permissions.test.mjs` falla por un hash de rutas desactualizado: se reprodujo el mismo fallo usando exclusivamente archivos de origin/main fc4d496. No se alteró ese baseline para ocultar la discrepancia.
