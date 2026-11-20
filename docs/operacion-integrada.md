# Operación integrada · 5.41.0

Las mejoras se incorporan a los módulos existentes y conservan sus rutas y permisos.

- **Mi bandeja:** próxima acción, responsable, vencimiento y filtros. Los indicadores del servidor se distinguen de la muestra cargada (hasta 300 tareas).
- **Pre-radicación:** vistas por reclamación y lote, con causas pendientes y límites visibles de 1,000 reclamaciones / 500 lotes. Preparación completa requiere comprobar las validaciones del lote.
- **Conciliación:** separa depósito–pago ARS de pago–reclamaciones. Mantiene importaciones, registro manual, reversión y reportes. Confirmación explícita y motivo para diferencias. Consulta por autorización/folio de solo lectura, hasta 100 resultados del cliente autorizado.
- **Calidad del lote:** distingue fuentes comprobadas, no aplicables y no disponibles. No interpreta un error de consulta como ausencia de duplicados, documentos o pagos. Reconsultar conserva formularios y archivos pendientes. Una respuesta fiscal con `ok: null` representa una comprobación no superada; una respuesta completa nula representa una fuente no disponible.
- **Autorización:** comparación antes/después, confirmación e historial para administrador y superusuario. El modo soporte sigue siendo de solo lectura.

Incluye el flujo previamente preparado en #142: solicitar corrección de duplicados registra una petición y no elimina reclamaciones ni levanta bloqueos por sí sola.

## Backend

La migración `operational_workspace_read_models` añade las consultas `claim_authorization_history` y `bank_workspace_claims`. Se aplicaron controles de usuario activo, cliente, rol y modo soporte; se mantiene el permiso bancario existente del auditor. Las pruebas SQL usan registros aislados y revierten la transacción. El SQL interno permanece fuera del repositorio público según sus reglas.

## Validación

Pruebas de navegador con datos ficticios para bandeja, preparación, conciliación, calidad, factura, edición e historial de autorización y duplicados. Pruebas unitarias de contratos de los servicios de lectura. Integración desde main 556ebb9 para conservar las actualizaciones publicadas por otras sesiones.

El test histórico `navigation-permissions.test.mjs` conserva una instantánea antigua que ya no coincide con main; esta entrega no modifica `js/utils/permissions.js` ni rutas.
