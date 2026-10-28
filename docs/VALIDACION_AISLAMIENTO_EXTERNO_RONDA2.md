# SOFA — Validación de aislamiento externo, ronda 2
Fecha: 2026-10-18. Proyecto Supabase: `bpwjhgpzhzhiocoxrvzq`. Pruebas realizadas con `BEGIN READ ONLY`, `SET LOCAL ROLE authenticated`, contexto de `auth.uid()` simulado y `ROLLBACK`.

## Ejecución
- 9 identidades externas distintas con membresía activa en organizaciones cliente.
- Para cada identidad se consultaron seis superficies: `service_lines`, `payments`, `documents`, `submissions`, `storage.objects` del bucket `claim-documents`, y `app.visible_org_ids()`.
- Criterio: ningún recurso de una organización **sin membresía activa** debe aparecer.
- Resultado: **9/9 identidades con cero filas fuera de sus organizaciones asignadas** en las seis comprobaciones.
- Una identidad externa tiene **cuatro membresías cliente activas**, combinando `client` y `capturer`. El acceso multiorganización para esa cuenta es coherente con las membresías actuales; su legitimidad de negocio **no ha sido confirmada**. No se eliminó ninguna membresía.

## Personal SOFA: excepción por rol
- Se comprobó que existen membresías de personal en la organización operadora para `super_admin`, `admin`, `assistant`, `billing`, `glosas` y `auditor`.
- Se ejecutaron cuatro pruebas simuladas para admin, assistant, billing y auditor; todas devolvieron cero organizaciones visibles. Esto es **inconcluso**, no demuestra que la excepción administrativa funcione. Puede depender de perfil, MFA y estado de autenticación.
- La función `app.visible_org_ids()` contempla personal del operador y controles de MFA, por lo que no debe prohibirse indiscriminadamente la visibilidad multicliente a personal autorizado.

## Restricciones y pendientes
1. **Sin cambios de producción:** no se modificaron políticas, membresías, credenciales, tablas ni archivos.
2. Las pruebas son simulaciones SQL de lectura, no sesiones HTTP con JWT reales.
3. Falta control positivo con reclamaciones y documentos sintéticos en dos organizaciones; un resultado cero puede deberse a ausencia de registros.
4. Falta prueba negativa de INSERT/UPDATE/DELETE y de URL firmada Storage.
5. Confirmar con responsable comercial si la cuenta externa con cuatro membresías necesita realmente acceder a cuatro clientes; si no, retirar únicamente las asociaciones indebidas mediante procedimiento auditado y aprobación explícita.
6. Ejecutar pruebas de roles internos SOFA con MFA y sesiones reales antes de declarar operativa la excepción.

## Dictamen
**No se observaron lecturas fuera de membresías activas para las 9 identidades externas examinadas.** No se ha certificado aún el aislamiento extremo a extremo ni la excepción del personal SOFA. No se ha aplicado una corrección de membresías sin determinar cuál acceso es legítimo.
