# SOFA — Auditoría de aislamiento entre clientes (RLS)
Fecha: 2026-10-18. Proyecto verificado: `bpwjhgpzhzhiocoxrvzq`. **Solo lectura**, sin alterar usuarios ni datos.

## Evidencia observada
- `organizations`, `service_lines`, `payments`, `documents`, `submissions`: `relrowsecurity=true`, `relforcerowsecurity=false`.
- SELECT de `service_lines`, `payments`, `documents`, `submissions`: organización incluida en `app.visible_org_ids()`.
- `organizations`: además de organizaciones visibles, muestra operadores del usuario y scopes de capturador.
- `app.visible_org_ids()`: usa `auth.uid()`, membresías activas, perfil activo, restricciones MFA para personal; personal de operador puede ver organizaciones clientes del operador (por diseño). Administradores y superadministradores pueden ver todas las organizaciones cliente de su operador, incluso con `staff_client_access` definida.
- Políticas adicionales de `capturer` usan `capturer_scopes` y el `provider_id` autorizado para limitar reclamaciones/radicaciones/documentos.
- Storage `claim-documents`: SELECT comprueba el primer segmento de ruta como organization_id visible; capturer usa `app.capturer_storage_ok`.
- Storage `intake`: SELECT autoriza a cualquier personal del operador (`app.is_staff()`) y **no restringe por organización** en esa política. Revisar si el bucket guarda documentos sensibles de múltiples clientes y si esta amplitud es intencional.
- `service_role` y `postgres` tienen `rolbypassrls=true`; jamás exponer sus claves al frontend. Una consulta ejecutada como service_role no demuestra aislamiento.
- Se detecta `service_lines_delete` permitiendo roles `assistant` y `client`, aunque es autorización de eliminación y no de lectura; revisar con producto y auditoría antes de cambiar.
- **Limitación crítica:** no se ejecutaron peticiones autenticadas con dos usuarios reales distintos. Por tanto el aislamiento efectivo NO está certificado.

## Matriz de pruebas de integración obligatorias (staging, datos sintéticos)
Crear organizaciones A y B, usuario médico A (rol client), médico B (client), capturador A con provider scope limitado y personal SOFA con MFA según configuración. Usar tokens de sesión reales de cada identidad; nunca JWT fabricado ni `service_role` para demostrar RLS.

| Caso | Identidad | Operación | Resultado esperado |
|---|---|---|---|
| RLS-01 | médico A | SELECT service_lines de A | Acceso a sus registros |
| RLS-02 | médico A | SELECT service_lines de B | 0 filas |
| RLS-03 | médico A | SELECT payments de B | 0 filas |
| RLS-04 | médico A | SELECT documents de B | 0 filas |
| RLS-05 | médico A | SELECT submissions de B | 0 filas |
| RLS-06 | médico B | SELECT de registros de A en las 4 tablas | 0 filas |
| RLS-07 | capturador A | SELECT service_lines de B sin provider scope | 0 filas |
| RLS-08 | capturador A | SELECT submission y documento dentro de su provider scope | Acceso esperado |
| RLS-09 | médico A | descargar signed URL de Storage claim-documents de B | Denegado al solicitar nueva URL |
| RLS-10 | médico A | SELECT storage.objects de B | 0 filas |
| RLS-11 | médico A | UPDATE/DELETE service_lines de B | Denegado / 0 filas |
| RLS-12 | médico A | INSERT service_lines con organization_id B | Denegado |
| RLS-13 | usuario sin sesión | SELECT documentos y pagos | 0 filas / denegado |
| RLS-14 | personal SOFA | Verificar acceso multi-cliente autorizado y MFA | Solo según política comercial definida |
| RLS-15 | personal SOFA | Acceso a bucket intake de otro cliente | Evaluar política de mínimo privilegio; posible acceso autorizado amplio |
| RLS-16 | médico A | Abrir signed URL previamente emitida para B | Las URLs firmadas son bearer: evaluar expiración y revocación, no asumir protección por RLS tras emisión |

## Reglas de ejecución
1. No ejecutar pruebas destructivas en producción.
2. Crear staging independiente y datos sintéticos para A/B.
3. Ejecutar peticiones REST con token de cada usuario real y clave pública/anon.
4. Capturar HTTP status, número de filas, organización esperada, tiempo, identidad de prueba y fecha; no guardar tokens ni datos sensibles.
5. Si hay filtración cruzada: detener liberación, revisar la función/política concreta y proponer migración con rollback.
6. Auditar específicamente funciones SECURITY DEFINER, vistas y Edge Functions que usen service_role y puedan omitir RLS.
7. Evaluar Storage `intake` con criterio de necesidad operativa, sin modificar reglas hasta revisar sus usos.

## Conclusión
**Diseño de aislamiento por organización identificado, pero prueba con identidades A/B pendiente.** No declarar 100 % seguro ni modificar RLS sin validar alcance de personal y capturadores.
