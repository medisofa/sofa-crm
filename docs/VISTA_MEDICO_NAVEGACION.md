# Vista del médico · 5.25.0

Esta entrega conserva las rutas existentes y los colores corporativos SoFa. No modifica tablas, RPC, permisos de base de datos ni estados almacenados.

## Disponible

- Mi Día: Inicio, Agenda del consultorio y Seguimiento de hoy.
- Mis Pacientes: Pacientes, Plan del día y Saldos de pacientes.
- Historia clínica: acceso independiente, conservando su control de acceso actual.
- Plan del día: Agendados (programada), Confirmados (confirmada), En sala (en_espera), En consulta (en_consulta) y Atendidos (atendida).
- Seguimiento de hoy: accesos a agenda, tablero, mensajes a pacientes, configuración de seguimiento y novedades SoFa. Abrir la vista no activa mensajes.
- Se mantienen las opciones horizontal y en cascada y sus preferencias por usuario en cada navegador.
- Mi Dinero y Mi Consultorio conservan sus funciones.

## Pendiente de desarrollo

Las notas personales, cuentas por pagar elegidas por el médico y noticias por especialidad se identifican como «En construcción». No hay campos de captura ni persistencia local para simular su disponibilidad.

La hospitalización actual reporta servicios para facturación; el vínculo a un episodio clínico hospitalario y su seguimiento tras el alta requiere una etapa adicional con autorización por rol y auditoría. El catálogo de centros actual es por cliente y no debe presentarse como un directorio nacional completo.

## Validación

- Prueba de navegador: cinco columnas sin duplicar pacientes, transiciones existentes, selección de consultorio, escape de texto, móvil, fallo de red y denegación de la nueva vista a otro rol.
- Regresión de ambas distribuciones del menú y preferencias por usuario.
- Sintaxis JavaScript y comprobación de diferencias.

## Reversión

Para revertir esta entrega, restaurar los archivos de frontend de la revisión anterior y publicar un identificador de versión nuevo para renovar la caché. No hay cambios de datos que revertir.
