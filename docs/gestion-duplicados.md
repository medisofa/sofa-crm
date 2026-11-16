# Gestión guiada de coincidencias · 5.39.0

Un duplicado confirmado puede tener revisión registrada y continuar bloqueando la radicación. El estado de la interfaz prioriza ese bloqueo y no presenta la revisión como una resolución completada.

Desde Reclamaciones o el detalle del lote, «Gestionar coincidencia» permite:

- Comparar los folios y abrir la ficha correspondiente para corregir datos mediante las acciones existentes.
- Consultar las solicitudes de exclusión del par y abrir su lote.
- Solicitar exclusión, únicamente con una decisión previa de duplicado confirmado y bloqueo vigente. El usuario selecciona explícitamente cuál conservar, escribe un motivo mínimo de diez caracteres y confirma ambos folios.
- Volver a comprobar el par; el estado se obtiene del servidor.

Las solicitudes no excluyen ni eliminan reclamaciones, no cambian importes ni decisiones y no levantan bloqueos. Quedan pendientes hasta que un responsable gestione el caso con las acciones autorizadas. Esta entrega no incorpora una autorización o exclusión automática. «Marcar retirada» sigue significando retiro físico, no exclusión de duplicados.

Pueden solicitar Administración, Super Admin, Operaciones y Facturación con acceso al cliente. El modo soporte no puede solicitar. El historial privado preserva selección, motivo, autor, fecha y lote; las solicitudes repetidas para la misma selección son idempotentes y una selección contraria no sobrescribe la original.

Infraestructura aplicada: claim_duplicate_resolution_requests_private_api y claim_duplicate_request_status_batch. Los SQL y pruebas transaccionales se conservan fuera del repositorio público conforme a README.md.

Verificado con usuario QA y datos ficticios en una transacción revertida: aislamiento por organización/rol, soporte, motivo, idempotencia, historial y auditoría, conservación de las reclamaciones y del lote y continuidad del bloqueo. Sin cuentas QA persistentes ni solicitudes sobre pacientes reales. Pruebas Chromium de comparación, solicitud, corrección, confirmación, reconsulta y ficha de radicación; servicio con estados por par en una consulta en lote.

## Estado al 16/11/2026 (5.41.0)

- Esta entrega pone al día la gestión trazable contra `main` (5.40.0). No agrega la ejecución de la exclusión.
- En producción existe `public.cancel_duplicate_line(p_cancel_id, p_keep_id)`: solo Administración o Super Admin, siempre sobre una solicitud pendiente; deja la reclamación en `anulada_duplicado` y la solicitud en `ejecutada`. **Está deshabilitada** (sin `EXECUTE` para `authenticated`).
- Motivo: la reclamación anulada sigue perteneciendo a su lote. Al radicar, `app.sync_claims_from_submission` la pasaría a `radicada`, y los totales por lote la seguirían contando. No se debe rehabilitar ni exponer en pantalla hasta excluir `anulada_duplicado` de esa sincronización y de los totales por lote, o hasta decidir otra forma de sacar la reclamación del lote.
- `CLAIM_STATUS` ya refleja `anulada_duplicado` para que el estado se lea bien si aparece.
