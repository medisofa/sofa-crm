# SOFA — Validación de roles y admin-users en staging
Fecha: 2026-10-19

## Estado
Ejecutado en Supabase staging `bvivlsrixbrczzrmodki`. Producción no fue modificada.

## admin-users
- staging version: 4
- status: ACTIVE
- verify_jwt: true
- source tracked at `supabase/functions/admin-users/index.ts`

## Role governance tests
Se recreó en staging el subsistema mínimo requerido por Iteración 10:
- roles
- organizations
- profiles
- organization_users
- clinical_settings
- app.clinical_mode
- admin_assign_role
- admin_user_id_by_email

Se usaron identidades sintéticas que ya existían en auth.users del staging para probar la lógica de asignación.

### Resultados
PASS:
- Super Admin puede validar/asignar Operaciones.
- Super Admin puede validar/asignar Médico / Cliente.
- Super Admin puede validar/asignar Secretaria / Capturista.
- Super Admin asignó Operaciones a un usuario sintético.
- Super Admin asignó Médico / Cliente a un usuario sintético.
- Admin puede asignar Facturación y Radicación.
- Prospecto es rechazado por admin_assign_role.
- Admin no puede asignar Super Admin.
- Una cuenta ya usada como Médico/Secretaria no puede convertirse en staff SOFA.

## CI
Run #32: SUCCESS
- npm install: PASS
- npm audit --audit-level=high: PASS
- Validate role contract: PASS
- typecheck: PASS
- build: PASS

## Lo que todavía NO está probado
No se ha ejecutado todavía una llamada HTTP real a `admin-users` con un JWT emitido por el flujo normal de Supabase Auth. El entorno de herramientas disponible no permite crear/iniciar sesión con usuarios Auth reales mediante el endpoint público ni invocar la función con cabeceras personalizadas desde navegador.

Por tanto el estado exacto es:
**ROLE GOVERNANCE STAGING PASS / EDGE FUNCTION DEPLOYMENT PASS / REAL SIGNED-JWT INVOCATION PENDING**.

## Producción
No se aplicaron cambios en producción.
