# Carga externa de reclamaciones · 5.27.0

## Flujo

1. Seleccionar el CSV y revisar. Todas las filas comienzan En revisión; no se importan automáticamente.
2. Completar/editar, consultar los valores originales y resolver los errores.
3. Verificar duplicadas dentro del CSV y contra las reclamaciones existentes de SoFa.
4. Excluir/eliminar del lote con motivo; la fila sigue visible y se puede restaurar con motivo.
5. Aprobar cada fila o las filas sin observaciones. Esta decisión queda en bitácora y todavía no crea reclamaciones.
6. Confirmar e importar únicamente las aprobadas. Las demás quedan fuera de esa importación.

El número de fila corresponde a su ubicación original en el CSV, incluso con líneas vacías o campos multilínea. El archivo del equipo no se modifica. Hasta 1,000 filas por carga.

## Precios y autorización

- El monto del archivo es unitario; el total es cantidad por monto. Se muestran tarifa, monto, cantidad y total.
- Vacío significa usar la tarifa contractual; ya no se interpreta como cero.
- Un monto diferente exige motivo de al menos diez caracteres y autorización de Administración o Facturación (super_admin/admin/billing).
- El monto y el motivo se envían realmente a capture_claim_dx. El flujo anterior omitía el monto al importar.
- Nueva vigencia tarifario reutiliza el formulario contractual, con motivo obligatorio y permisos existentes. Una RPC SECURITY INVOKER ejecuta la creación y el registro de la revisión en una sola transacción, conservando RLS.
- No se sobrescribe la tarifa anterior. Tras un cambio contractual se invalidan las aprobaciones y se vuelve a revisar.
- El servidor compara la tarifa mostrada al aprobar con la vigente al importar; si cambió, exige una nueva validación.

## Duplicadas y reintentos

El archivo compara organización, ARS, afiliado/fecha/servicio y autorización. El servidor vuelve a comprobar las coincidencias al confirmar, con el criterio de captura existente para radicaciones activas (no rechazada/cerrada). No existe un botón que ignore el bloqueo de duplicadas en esta carga.

Cada fila tiene un identificador estable de lote/fila. El servidor guarda una relación privada con la reclamación creada, el usuario, la organización y una huella de la solicitud. Reintentar la misma confirmación devuelve el resultado anterior. Si se perdió la respuesta, Verificar duplicadas recupera el resultado de esa fila sin crear otra reclamación. Una fila nueva de otro lote vuelve a pasar por la comprobación de duplicadas.

Las importaciones que usan este nuevo flujo se serializan por organización/ARS. Se mantienen las comprobaciones finales del capturador existente; no se modifica su API ni se concede la excepción de duplicada.

## Bitácora y eliminación

- Las correcciones, exclusiones, restauraciones y aprobaciones se guardan con el usuario autenticado antes de aplicar el nuevo estado en pantalla. Si falla la bitácora, no se confirma ese cambio.
- Crear la reclamación, registrar la importación y guardar su relación de origen constituyen una única transacción. Si falla la bitácora, se revierte la creación.
- La confirmación guarda los datos de precio relevantes y enlaza el resultado con la reclamación, cuyo registro existente también audita sus valores definitivos. No copia columnas desconocidas del CSV a la bitácora de confirmación.
- Los administradores y Facturación pueden solicitar Eliminar reclamación desde una fila ya importada por esa carga. Exige motivo y usa remove_service_line, conservando las restricciones existentes de rol, radicación, pagos, glosas y reenvíos.
- Si ya tiene documentos se remite al flujo de radicación para gestionar su trazabilidad documental. No se borran objetos de Storage desde esta pantalla.
- La eliminación y su bitácora son atómicas; la relación de origen permanece como eliminada y un reintento no recrea la reclamación.

## Seguridad

Las nuevas RPC no tienen EXECUTE para anon ni PUBLIC. La revisión exige personal autorizado, usuario activo/MFA mediante los controles existentes, acceso visible a la organización y acceso al médico. La tabla app.google_intake_commits tiene RLS, índices para sus claves externas y ningún permiso directo para anon/authenticated. No hay clave externa a la reclamación: no se bloquea el mecanismo existente de eliminación autorizada.

La nueva RPC tarifaria usa SECURITY INVOKER para conservar los permisos de las tablas y funciones existentes. El motivo se comprueba también en el servidor.

## Validación y límites

PostgreSQL 17 aislado con funciones de captura/auditoría simuladas: revisión obligatoria, tarifa desactualizada, permiso por organización, permisos anónimos, monto enviado, reintento, recuperación de respuesta, duplicadas, eliminación protegida, fallo de auditoría en creación/eliminación/tarifa y dos importaciones concurrentes. Las funciones reales existentes de captura, eliminación y tarifario se inspeccionaron antes de reutilizarlas.

Chromium con servicios simulados: CSV, edición, texto original, XSS, exclusión bloqueada si falla la bitácora, revisión/aprobación, importe real y cantidad, pérdida de respuesta, eliminación protegida, nueva vigencia con motivo y rol, móvil y filas originales. Regresión de actualización del service worker y exclusión de datos de CacheStorage.

En producción solo se comprueban metadatos, ausencia de acceso anónimo/directo, rechazo de solicitudes sin sesión y archivos publicados. No se importan, editan ni eliminan reclamaciones reales para probar.

Los borradores de revisión permanecen en memoria de la pestaña; las acciones auditadas son persistentes y las reclamaciones confirmadas quedan en la base. La reversión de frontend debe publicarse con una versión de caché nueva y conservar las tablas y bitácoras.
