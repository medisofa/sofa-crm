# Recepción en oficina

Disponible en **Retiros y recepción → Recepción en oficina** (`#/retiros/oficina`).

1. Registrar el cliente, médico opcional, fecha, quién entrega y quién recibe.
2. Añadir una línea por ARS y tipo de servicio, con cantidad de reclamaciones y monto declarado.
3. Guardar el lote. Su folio `ROF` identifica la recepción y permite descargar o compartir el acuse PNG.
4. Adjuntar fotos o PDF desde el detalle del lote. Los archivos son privados y los enlaces de lectura son temporales.
5. Capturar las reclamaciones en el módulo habitual. Volver a la recepción y vincular las reclamaciones reales a cada línea.
6. Comparar cantidades y montos declarados con los capturados. «Conciliada» exige coincidencia de ambos; no equivale a validación ni radicación.

Un lote recibido no crea reclamaciones, pagos ni cuentas por cobrar. Una reclamación solo puede vincularse a una línea de recepción. Vincularla no altera su estado operativo.

Administración, Operaciones, Facturación y Comercial/Onboarding pueden registrar y conciliar en los clientes a los que tienen acceso. Auditor y Médico/Cliente consultan los registros permitidos. La base de datos valida estos permisos.

Una recepción registrada no se sobrescribe. Para corregir datos declarados, anularla con justificación y registrar el lote correcto. La anulación conserva el registro y la evidencia, libera las vinculaciones y no elimina las reclamaciones. Las acciones quedan en la bitácora.

Si se interrumpe la respuesta al guardar, reintentar el mismo formulario. Se conserva el identificador del intento para evitar duplicarlo.

La migración SQL y sus pruebas se conservan fuera del repositorio público, conforme a las instrucciones del proyecto. Migración aplicada: `20261109144540_office_reception_batches`.
