# SOFA — Iteraciones 26–40: bitácora de ejecución y aceptación

Proyecto objetivo: `medisofa/sofa-crm`, Supabase `bpwjhgpzhzhiocoxrvzq`. Excluye HemoCura.

**Regla de estado:** "preparado" significa código o documento en GitHub sin despliegue; "pendiente" no equivale a implementado. Ningún envío real autorizado ni realizado.

| # | Iteración | Entregable y aceptación | Estado al crear esta bitácora |
|---|---|---|---|
| 26 | Auditar cola real | Contar por estado y conservar mensajes existentes | **Verificado: 6 pendientes**, lectura SQL |
| 27 | Bloqueo de procesamiento | No consumir cola con modo de prueba activo | **Código preparado** en PR #36 |
| 28 | Control de errores RPC | No contar éxito si `email_mark_sent` / `email_mark_failed` responde error | **Código preparado** en PR #36 |
| 29 | Validar MIME | UTF-8, cabeceras, texto/html y mensajes largos con pruebas | Pendiente de pruebas |
| 30 | Validar OAuth | Scope gmail.send, expiración y refresh token válido | Pendiente de credenciales seguras |
| 31 | Validar respuestas Gmail | Casos 400, 401, 403, 429, 5xx y timeout | Pendiente de pruebas |
| 32 | Riesgo de duplicación | Revisar reclamación/lease, reintentos y reconciliación de envíos inciertos | Pendiente |
| 33 | Seguridad de pruebas | JWT, x-sofa-secreto, bandera y allowlist en función aislada | Código preparado; pruebas pendientes |
| 34 | Seguridad de secretos | Confirmar secretos solo en Supabase, nunca frontend/GitHub | Pendiente de verificación |
| 35 | Despliegue seguro | Revisión de PR, backup, deploy sin activar procesamiento | Pendiente de aprobación y tests |
| 36 | Primer envío controlado | 1 destinatario consentido, prueba aislada sin tocar cola | Pendiente de OAuth y autorización |
| 37 | Auditoría de captura | Mapear campos actuales, validaciones, errores y duplicados | Pendiente |
| 38 | Auditoría de retiros | Comprobar formulario, trazabilidad, responsables y reporte | Pendiente |
| 39 | Auditoría de glosas/pagos | Relación reclamación, glosa, conciliación y honorarios | Pendiente |
| 40 | Informe de liberación | Checklist de regresión, rollback, riesgos y evidencias | Pendiente |

## Riesgos detectados
- **R1:** la cola de producción tiene seis mensajes pendientes; no activar procesamiento sin revisión individual.
- **R2:** el proveedor Gmail API puede entregar el correo aunque la respuesta HTTP se pierda; reintentar podría duplicar mensajes. El bloqueo de cola sigue obligatorio hasta definir mitigación.
- **R3:** el adaptador Gmail y la prueba aislada están en rama de desarrollo; faltan pruebas automatizadas, compilación y credenciales OAuth confirmadas.
- **R4:** el código de prueba requiere JWT y secreto; verificar configuración del gateway antes de exponerlo.
- **R5:** el usuario no dispone de dominio propio; Resend queda sin activar.

## Puertas de salida
1. Revisión de seguridad y compilación.
2. Validación OAuth sin exponer credenciales.
3. Prueba aislada aprobada con un solo destinatario.
4. Revisión y aceptación de los seis correos pendientes.
5. Habilitación de cola únicamente mediante autorización explícita y plan de reversión.

**Esta bitácora no certifica la ejecución de las 15 iteraciones.** Diferencia los tres avances verificables del resto de trabajos necesarios.
