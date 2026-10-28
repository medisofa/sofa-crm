# Gestión de accesos, soporte y novedades

Estado: especificación de implementación; no desplegada ni validada contra base real.

## Alcance aprobado
Una cuenta con accesos separados por organización. Super Admin puede editar, suspender, reactivar o retirar asociaciones bajo autorización del servidor. Retirar conserva evidencia e historial; no elimina auth.users. Operaciones sensibles requieren MFA, motivo y confirmación. No permitir cambio propio sensible ni retirar al último Super Admin operativo. Controlar concurrencia y registrar antes/después en la misma transacción.

## Vista de soporte del cliente
Selector de organización y de cuenta objetivo autorizadas. Mostrar siempre actor real, cuenta y organización observadas, modo soporte y botón Salir. Consulta de solo lectura de las mismas proyecciones financieras que consume el cliente, con filtros efectivos del destinatario calculados en servidor. No sustituir JWT, contraseña ni auth.uid del actor. La bitácora identifica actor y objetivo por separado. Exportación y escrituras deshabilitadas en soporte inicial. Cambiar organización cancela solicitudes pendientes y limpia datos anteriores. Las respuestas tardías de otro cliente se descartan.

## Historia clínica
Denegar por defecto el acceso clínico del soporte, incluyendo RPC, documentos/Storage, búsquedas, exportaciones e importaciones. Un permiso administrativo general no equivale a autorización clínica. Decisión confirmada: autorización temporal por caso, iniciada o aprobada por el médico responsable y revocable por él. Definir actor destinatario, pacientes/documentos permitidos, propósito y vencimiento. Revocación por médico; validar vigencia y alcance en cada lectura. Auditar aprobación y cada acceso. La aprobación no reemplaza otras obligaciones de consentimiento. Nada de contenido clínico en notificaciones, logs técnicos o noticias.

## Novedades
Reutilizar componentes visuales de noticias, no asumir que sus permisos o categorías sirven al médico. Especialidad desde el perfil autorizado; noticias con título, fuente, enlace HTTPS y fecha. Preferencias individuales por médico, temas de especialidad y salud general. Decisión confirmada: el médico activa temas y puede ocultar noticias individuales; las preferencias deben persistirse por médico en servidor. No publicar noticias inventadas ni usar datos de pacientes para personalización. Ingesta separada en servidor, fuentes verificadas y HTML saneado. Enlaces externos con protección de apertura. Mostrar fuente y fecha, no consejo clínico personalizado.

## Carga inicial SeNaSa
Requiere cliente, detalle de dos radicaciones, fechas originales, importes y soporte de liquidación. Carga idempotente por organización y referencia, conciliación de pago parcial/total, glosas y retenciones. No reenviar radicaciones históricas. Entregar acceso solo después de comprobar saldos y aislamiento.

## Pruebas de aceptación obligatorias
- Super Admin fuera del operador, usuario sin MFA y cambio propio: denegados.
- Suspender/retirar un acceso deja intactos los demás; cuenta y acceso muestran estados separados.
- Dos cambios concurrentes no sobrescriben revisión obsoleta; no se elimina último Super Admin.
- Soporte ve únicamente el conjunto visible al cliente; no adquiere permisos de escritura.
- Solicitud clínica pendiente, caducada, revocada o para otro paciente: denegada incluso con llamadas directas.
- Cambio rápido entre clientes no muestra respuestas del anterior.
- Preferencias de noticias de un médico no afectan otro; rechazos persistentes y sin contenido clínico.

## Dependencias y límites actuales
Backend real sin conexión disponible en esta sesión. El SQL de corrección anterior es candidato específico, no solución general de gestión de roles. Hay que verificar constraints, triggers, RLS y autorización clínica existentes en copia aislada antes de preparar migraciones compatibles. No activar funcionalidades mediante botones que llamen funciones ausentes.
