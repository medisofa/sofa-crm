# SOFA — Respaldo nuevo y prueba de restauración
Proyecto autorizado: bpwjhgpzhzhiocoxrvzq (medisofa's Project).
NO usar proyecto HemoCura. NO subir archivos de backup, datos de pacientes ni contraseñas a GitHub, Neon o este chat.

## Limitación actual
El conector Supabase de esta sesión permite consultas SQL y auditoría, pero no ofrece una operación para descargar un backup PostgreSQL ni objetos Storage. No existe un backup nuevo verificado en esta ejecución.

## Ejecución en estación autorizada
1. Instalar Supabase CLI y Docker según documentación oficial.
2. Abrir el panel SOFA: https://supabase.com/dashboard/project/bpwjhgpzhzhiocoxrvzq
3. En Connect, obtener la URL de conexión de Postgres; conservarla exclusivamente en gestor de secretos/variable de entorno local, nunca en chat, GitHub o capturas.
4. En carpeta local cifrada fuera del repositorio, ejecutar los tres comandos:
   supabase db dump --db-url "$SOFA_DB_URL" -f roles.sql --role-only
   supabase db dump --db-url "$SOFA_DB_URL" -f schema.sql
   supabase db dump --db-url "$SOFA_DB_URL" -f data.sql --use-copy --data-only
   NOTA: no asumir que el dump incluye todos los objetos Storage ni Edge Functions.
5. Obtener un inventario de Storage y descargar por API autorizada los objetos de cada bucket privado con un proceso local paginado, comprobando cantidad y SHA-256. Nunca usar enlaces públicos para objetos privados.
6. Respaldar por separado código/configuración de Edge Functions, configuración Auth y OAuth, y valores de secretos mediante el mecanismo seguro aprobado. No imprimir ni versionar secretos.
7. Registrar tamaño, fecha, checksum SHA-256, recuento de objetos y ruta local cifrada de cada artefacto.
8. Restaurar en instancia Supabase local aislada compatible; validar roles, tablas, funciones, RLS, auth.users y objetos de Storage. La restauración no se ejecuta sobre producción.
9. Documentar PASS/FAIL con resultados reales. No marcar PASS antes de ejecutar y observar restauración.

Fuente oficial:
https://supabase.com/docs/guides/self-hosting/restore-from-platform

## Estado
DB roles: NO DESCARGADO.
DB schema: NO DESCARGADO.
DB data/Auth: NO DESCARGADO.
Storage objects: NO DESCARGADO.
Edge Functions/Auth settings: NO RESPALDADO.
Restore drill: NO EJECUTADO.
GO gate G1: FAIL por ausencia de evidencia, no por fallo demostrado de backup.

## Bloqueo
Para completar el respaldo debe ejecutarse desde un entorno con acceso seguro a credenciales de la base y Storage. El conector actual no provee estas capacidades. No pedir que el usuario comparta la contraseña en el chat.
