# Hotfix producción — admin-users / confirmación de correo
Fecha: 2026-10-19

## Alcance
Se modificó únicamente la Edge Function `admin-users` en Supabase producción `bpwjhgpzhzhiocoxrvzq`.
No se ejecutaron migraciones ni cambios de datos.

## Rollback
Snapshot previo guardado:
`docs/backups/admin-users-prod-v3-2026-10-19.ts`

Versión previa:
- admin-users v3
- ACTIVE
- verify_jwt=false

## Hotfix
Versión desplegada:
- admin-users v5
- ACTIVE
- verify_jwt=true
- sha256: `59a3d291097a9e938096b553624fbd9ffa1baac03160deb718593fde05e5bfd0`

Cambios:
1. Roles asignables alineados con el modelo operativo.
2. Prospecto queda fuera de organization_users.
3. AUTH_REDIRECT_URL soportado.
4. Compatibilidad dual de redirección:
   - GitHub Pages / app estática → `/login.html`
   - Next.js / dominio moderno → `/login`
5. La función conserva validación interna del Bearer token y ahora además exige JWT en gateway.
6. Se corrigió un literal `\\n` que podía dejar comentada la declaración `ASSIGNABLE_ROLES`. La corrección fue desplegada inmediatamente como v5.

## Validación previa
CI #42: SUCCESS.

## Validación posterior
CI #43: SUCCESS.

Controles de producción antes/después:
- roles: 10 → 10
- organization_users: 19 → 19
- profiles: 16 → 16
- organizations: 6 → 6
- service_lines: 240 → 240
- payments: 2 → 2
- glosa_items: 6 → 6
- audit_log: 2498 → 2498

Otras Edge Functions no cambiaron:
- crear-usuario v9 ACTIVE
- restablecer-clave v4 ACTIVE
- market-intel v3 ACTIVE
- enviar-correos v1 ACTIVE

## Compatibilidad con frontend actual
El frontend de producción llama `supabase.functions.invoke('admin-users', ...)`, por lo que envía la sesión actual. Esto es compatible con `verify_jwt=true`.

Los logs previos muestran llamadas autenticadas POST 200 a admin-users desde el frontend y preflight OPTIONS 200. Después del despliegue aún no había una nueva llamada de usuario a v5 en el corte de validación.

## Estado
HOTFIX PRODUCCIÓN: APLICADO.
DB: SIN CAMBIOS.
ROLLBACK: DISPONIBLE.
CI: VERDE.
PRINCIPAL PENDIENTE: ejecutar Reenviar invitación / Enviar acceso para el usuario afectado y confirmar en logs que v5 responde POST 200 y que el correo llega.
