# Auditoría y corrección de roles SOFA — 2026-10-19

## Hallazgo sobre admin-users
La guía de Iteración 10 está desactualizada: la Edge Function `admin-users` está publicada y ACTIVE en producción, versión 3. También aparece copiada en la development branch.

Problema real: está desplegada con `verify_jwt=false`. La función sí valida el Bearer token dentro del código con `auth.getUser(jwt)`, pero para el próximo despliegue se recomienda `verify_jwt=true` y mantener la validación interna como defensa adicional.

## Roles actuales detectados
- super_admin
- admin
- operations
- billing
- glosas
- assistant
- auditor
- client
- prospect
- capturer

## Correcciones de definición
- billing → **Facturación y Radicación**
- glosas → **Cobros, Conciliación y Glosas**
- assistant → **Comercial / Onboarding**
- auditor → **Auditor de Expedientes**
- client → **Médico / Cliente**
- capturer → **Secretaria / Capturista**

Los códigos no se cambian para no romper RLS, funciones, rutas ni datos existentes.

## Inconsistencias encontradas
1. Facturación no tenía `radicaciones` en su tope de rutas aunque su trabajo debe culminar en radicación.
2. La UI permitía `payments.create` a Facturación, pero funciones recientes de conciliación indican que Cobros/Glosas debe administrar pagos.
3. `role_modules` solo tenía filas para billing y capturer; el resto dependía de fallback de código.
4. Secretaria/Capturista tenía Dashboard, Nueva cita y Trabajo de hoy en `role_modules`, pero faltaban Captura rápida, Reclamaciones y Agenda.
5. Prospecto existe en `roles`, pero el modelo real lo resuelve con `lead_users`; no debe asignarse como membresía en `organization_users`.
6. Hay al menos una cuenta con membresías externas mixtas en varias organizaciones y roles distintos. No se modifica automáticamente porque requiere confirmar identidad/función del usuario.

## Matriz operativa corregida
| Rol | Responsabilidad principal |
|---|---|
| super_admin | Gobierno, seguridad y administración crítica |
| admin | Administración general y supervisión |
| operations | Recepción, validación, pre-radicación y calidad |
| billing | Facturación y radicación |
| glosas | Pagos ARS, conciliación, glosas y recuperación |
| assistant | Comercial, CRM y onboarding |
| auditor | Auditoría y consulta |
| client | Médico / dueño de práctica |
| capturer | Secretaria / captura |
| prospect | Incorporación; no miembro operativo |

## Estado de aplicación
- Código de permisos en la rama `architecture/mvp-production-v1`: corregido.
- SQL de producción: preparado como PENDING y termina en ROLLBACK para impedir ejecución accidental.
- Producción: NO modificada.
- admin-users producción: ACTIVE v3, no requiere “publicación” inicial; requiere hardening en un despliegue posterior.
