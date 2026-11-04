# Progreso persistente de la carga · 5.28.0

## Nuevas cargas

La carga guarda un borrador privado en Supabase: filas originales y corregidas, exclusiones, revisión/aprobación, relación de origen, resultados de acciones y campos de la edición pendiente. La pantalla distingue Guardando, Guardado y Error. El progreso no se almacena en localStorage, sessionStorage, IndexedDB ni en el service worker.

Después de revisar el archivo, puede recargar y continuar sin seleccionar de nuevo el CSV. Se vuelven a comprobar catálogo, tarifa y duplicadas; si cambió la tarifa o una validación, se requiere una revisión nueva. Los estados de reclamaciones creadas/eliminadas se recuperan del control de importación del servidor, no se toman como prueba desde el borrador. El identificador de origen se conserva incluso al crear una copia, para no volver a importar la misma fila.

El borrador se guarda al iniciar la revisión y antes/después de acciones. Los campos de edición se guardan con una breve espera tras escribir. Si no se pudo guardar, la pantalla avisa, conserva los cambios en memoria y bloquea la actualización solicitada hasta que se confirme el guardado. El navegador también recibe una advertencia antes de abandonar una página con cambios/acciones pendientes. No puede garantizarse guardar el último texto si se cierra a la fuerza sin conexión; el indicador Guardado es la confirmación del servidor.

## Actualización de la aplicación

El aviso no recarga automáticamente. Su botón pasa por prepareProgressForUpdate y espera el guardado; si hay una acción en curso o un guardado fallido, no actualiza. La navegación entre módulos y el cambio de distribución/organización también comprueban el progreso antes de reemplazar la pantalla. Las protecciones de autoguardado se aplican a la carga Google Sheets/Form, no implican autoguardado universal de todos los formularios de SoFa.

## Primera transición con una carga abierta en la versión anterior

La versión anterior solo tenía el estado de revisión en la pestaña; el nuevo código no puede acceder retroactivamente a esa memoria. Mantener la pestaña anterior abierta y no pulsar Recargar ahora. Guardar cualquier corrección del diálogo para registrarla en la bitácora; esto no importa la reclamación.

Abrir la nueva versión en otra pestaña, seleccionar el mismo CSV original y desplegar Recuperar una revisión anterior al autoguardado. Elegir la revisión por fecha y recuperar. Se reaplican correcciones/exclusiones auditadas solo si coinciden los valores disponibles; las discrepancias bloquean la recuperación automática. Las filas se revalidan y requieren aprobación antes de importar. Si había reclamaciones confirmadas, se consultan sus estados del servidor para no duplicarlas. Comparar la carga recuperada y esperar Guardado antes de cerrar la pestaña anterior.

No puede recuperarse remotamente texto escrito en una versión anterior que nunca se confirmó con Guardar corrección ni llegó a su bitácora. Por eso se conserva la pestaña original durante la transición.

## Pestañas y copias

El guardado usa una revisión y un bloqueo por usuario. Una pestaña antigua no sobrescribe un checkpoint más reciente. Si hay conflicto, se puede conservar una copia independiente, desde la pantalla o desde el diálogo de edición. La copia conserva el origen de las filas; no habilita una nueva importación de una reclamación ya creada.

El usuario puede reanudar otras cargas desde su lista y archivar explícitamente una revisión. Archivar no elimina reclamaciones ni bitácoras. Límites: 20 cargas activas por usuario, 1,000 filas por carga y 8 MiB por snapshot.

## Seguridad y validación

La nueva RPC exige el usuario esperado de la sesión, personal activo/MFA por las funciones existentes y acceso a las organizaciones conocidas del borrador. Solo devuelve datos del propio usuario. La tabla privada y el registro de checkpoints tienen RLS, índices y ningún permiso directo para anon/authenticated. La recuperación de bitácora limita actor, tipo de registro, origen y organizaciones visibles. Los checkpoints auditan usuario, versión y hora sin duplicar el contenido de pacientes en sus eventos.

Pruebas PostgreSQL 17 aislado: permisos, propiedad, cambio de sesión, pérdida de alcance, reintento, archivo, recuperación de bitácora y dos sesiones concurrentes. Chromium con datos simulados: recarga real con editor abierto, correcciones, exclusiones, aprobaciones, copias en conflicto, fallo de guardado, actualización bloqueada/reintentada, importación sin duplicadas y recuperación de revisión anterior. Regresión de revisión/importación, ambas navegaciones y actualización/privacidad del service worker.

No se modifican reclamaciones reales para probar. Las migraciones son aditivas; no eliminan tablas ni cambian las firmas de las RPC de importación existentes. El formato del snapshot está versionado: futuras entregas deben conservar su lectura o migrarlo explícitamente.
