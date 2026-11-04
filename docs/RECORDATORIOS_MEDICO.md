# Recordatorios personales del médico · 5.26.0

Ubicación: Mi Día → Seguimiento de hoy → Mis notas y cuentas por pagar.

## Uso

- Crear y editar una nota, con detalle y fecha opcionales.
- Registrar una cuenta por pagar en RD$, con monto positivo y vencimiento obligatorio.
- Completar o marcar como pagada, reabrir y filtrar pendientes, completados o todos.
- No ejecuta pagos, modifica tarifas ni crea movimientos contables.
- Hasta 500 registros por usuario/consultorio; la vista muestra hasta 200, priorizando pendientes.

## Privacidad y autorización

La nueva RPC `public.physician_reminders_v1` comprueba `auth.uid()` y `app.can(org, ['client'])`. Cada lectura y escritura se restringe al propietario y consultorio. No acepta un usuario propietario enviado por el navegador. El personal operativo y los demás médicos no tienen acceso. Las tres tablas nuevas están en `app`, tienen RLS activado y no conceden acceso directo a `anon` ni `authenticated`.

La RPC usa SECURITY DEFINER, search_path vacío y referencias calificadas; solo authenticated tiene EXECUTE. Este permiso está protegido por las comprobaciones internas. El registro de eventos guarda actor, entidad, organización, acción y versión, sin copiar el texto personal.

El contenido se mantiene en memoria de la pantalla y en la base; no se usa localStorage, sessionStorage ni caché de datos. Para información de pacientes se utiliza la Historia clínica existente.

## Concurrencia y reintentos

El navegador conserva el UUID de un intento fallido. El servidor serializa escrituras por usuario/consultorio y verifica la versión antes de modificar. Un reintento con el mismo UUID y contenido devuelve la fila existente sin un evento adicional. Una edición desactualizada con contenido diferente se rechaza; el formulario conserva el texto para que el médico pueda revisarlo.

## Activación y reversión

La migración crea `app.physician_reminder_settings.enabled = false`. Tras comprobar permisos, aplicar pruebas y publicar el frontend se activa explícitamente la única fila. Para suspender el módulo, volver a false; el servidor deja de devolver contenido y rechaza guardar sin modificar las notas existentes. Para volver al frontend anterior, publicar con un identificador de caché nuevo. No eliminar tablas con datos.

## Validación

- PostgreSQL 17 aislado: denegación a anónimos, otro médico, otro consultorio y rol billing; sin acceso directo; valores inválidos; reintentos, versiones y eventos.
- Dos sesiones PostgreSQL concurrentes: una edición aceptada y otra rechazada.
- Chromium con servicios simulados: crear, editar, completar/reabrir, cuentas por pagar, conflicto, pérdida de respuesta, reintento con el mismo UUID, móvil y flag apagado.
- Regresión de ambas distribuciones del menú y del Plan del día.
- En producción: metadatos de permisos, RLS y rechazo de llamada sin usuario. No se crean notas de prueba ni se suplanta a usuarios reales.

Los avisos nuevos del analizador corresponden a la función privilegiada autenticada con autorización interna, la tabla privada de configuración sin políticas ni permisos directos, y los índices recién creados aún sin uso. No se añaden permisos anónimos, relaciones sin índice ni índices duplicados.

## Caché de la aplicación

La revisión automática bloqueó la regla anterior del service worker por interceptar cualquier GET del mismo origen. Esta entrega la sustituye por una lista positiva de páginas estáticas conocidas y recursos dentro de js/css/vendor/assets. Quedan fuera las APIs, documentos de usuario, peticiones Authorization, parámetros de datos, respuestas privadas/no-store y tipos de contenido inesperados. Se verificó con Chromium que esas respuestas no aparecen en CacheStorage y que los recursos estáticos sí se recuperan sin conexión. La prueba de actualización desde un worker antiguo conserva sesión y elimina únicamente cachés SoFa anteriores.
