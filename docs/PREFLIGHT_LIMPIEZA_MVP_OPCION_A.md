# SOFA — Preflight obligatorio para limpieza MVP (Opción A)

Fecha: 2026-10-18. Proyecto exclusivo: `bpwjhgpzhzhiocoxrvzq`.

## Autorización
El usuario autorizó: **respaldar y verificar primero**, después eliminar usuarios externos de prueba y datos operativos de prueba, conservar cuentas administrativas SOFA, configuración y estructura, aplicar mínimo privilegio y certificar aislamiento.

## Inventario de producción verificado (antes de modificar)
- `auth.users`: 16; `public.profiles`: 16.
- `public.organization_users`: 19 membresías, de ellas 12 activas en organizaciones cliente.
- `public.organizations`: 6; `service_lines`: 240; `documents`: 1; `payments`: 2; `audit_log`: 2,493.
- Hay una identidad externa con 4 organizaciones cliente activas.
- `backup_drills`: dos registros del 2026-10-09 marcados `respaldo_descargado / ok`, pero **no demuestran respaldo íntegro y restaurable del estado actual**.
- `app.reset_scope_tables` existe, pero su alcance `clientes` incluye `profiles` y `organizations`; **no usarlo** para opción A sin adaptar y revisar dependencias.

## Bloqueador de ejecución
No hay un respaldo **actual y restaurado de prueba** verificable mediante los conectores disponibles. No borrar datos ni identidades hasta completar:
1. Backup lógico completo de Postgres (incluyendo `auth`, `public`, esquemas auxiliares pertinentes y políticas); inventario de objetos de Storage y descarga de sus bytes.
2. Copia externa cifrada, checksum y verificación de lectura.
3. Restauración en proyecto aislado y cotejo de tablas, conteos, funciones, RLS, Storage y autenticación.
4. Confirmar qué usuarios internos retener, qué organizaciones son de prueba, y que los registros operativos a borrar no correspondan a clientes reales.
5. Preparar manifiesto explícito de IDs y dependencias; ejecutar transacción controlada y procedimiento de borrado de Auth por interfaz administrativa autorizada.
6. Implementar política de membresía externa única con excepciones registradas; conservar acceso interno SOFA por rol, MFA y asignación.
7. Ejecutar pruebas A/B con identidades reales y datos sintéticos, SELECT/INSERT/UPDATE/DELETE, Storage y Edge Functions; publicar evidencias antes del MVP.

## Estado
**Solo auditoría de lectura. Cero registros eliminados. Cero migraciones desplegadas. MVP NO certificado.**
