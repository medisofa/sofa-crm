# SOFA — Pruebas y preparación sin costo (sin tocar producción)
Fecha 2026-10-18. Proyecto exclusivo: `bpwjhgpzhzhiocoxrvzq`.

## Hechos comprobados
- 9 identidades externas con membresía cliente activa; 1 tiene más de una organización activa.
- Esquema de `organization_users`: `organization_id`, `user_id`, `role_code`, `is_active`, `created_at`, `created_by`.
- `staff_client_access` define asociaciones de personal interno con clientes.
- Sin rama de desarrollo en Supabase. Creación de rama cuesta US$0.01344/h y **no fue autorizada**.
- No hay evidencia de respaldo actual íntegro y restaurado; por tanto no borrar usuarios, Auth ni datos.
- Se añadió un borrador SQL en `docs/sql/PROPOSED_external_single_org_guard.sql`; **no aplicado**.

## Revisión requerida del borrador antes de aplicar
1. Revisar el modelo de excepción: la excepción debe ser autorizada para cada vínculo adicional y comprobada tanto en el momento de asignación como en las políticas de lectura; la excepción no debe permitir que una membresía caducada siga otorgando visibilidad.
2. Asegurar que la detección de personal SOFA dependa de roles internos validados y no de una membresía autoconcedida.
3. Revisar privilegios de INSERT/UPDATE de `organization_users`, `external_multi_org_exceptions` y funciones RPC con SECURITY DEFINER.
4. Añadir prueba de carrera concurrente para altas simultáneas; revisar que las funciones SECURITY DEFINER no se expongan a usuarios externos.
5. Considerar cuentas con múltiples roles y organización de operador; asegurar que la restricción no afecte staff legítimo.

## Matriz de certificación en entorno de ensayo (pendiente)
| Escenario | Identidad | Resultado esperado |
|---|---|---|
| Leer reclamaciones propias | Médico A | 200, filas de A |
| Leer reclamaciones B | Médico A | 0 filas / 403 |
| Crear reclamación en B | Médico A | 403 / RLS |
| Actualizar o eliminar reclamación B | Médico A | 403 / 0 filas |
| Leer/cargar/descargar documento B | Secretaria A | Denegado |
| Leer/cargar documentos de A autorizados | Secretaria A | Permitido por scope |
| Crear segunda membresía sin excepción | Externo A | Denegado |
| Crear segunda membresía con excepción vigente | Externo A | Permitido |
| Caducar excepción | Externo A | Sin acceso adicional |
| Acceso a A y B según asignación | Staff SOFA con MFA | Permitido |
| Acceso a B sin asignación | Staff SOFA limitado | Denegado |
| Anónimo o JWT inválido | Sin sesión | Denegado |
| RPC SECURITY DEFINER de datos de B | Externo A | Denegado |
| Edge Function con service_role | Externo A | Denegado salvo ámbito legítimo |

## Próxima ejecución permitida sin costo
- Revisar código y SQL en GitHub, preparar pruebas automatizadas que puedan ejecutarse en un Postgres local o CI sin secretos de producción.
- Crear manifiesto de usuarios de prueba y datos dependientes sin exportar información sensible al repositorio.
- Pedir al responsable de infraestructura que genere backup completo cifrado y haga una restauración comprobada en un entorno ya disponible sin costo.
- Una vez exista backup restaurado y ambiente seguro, ejecutar limpieza y pruebas; **no certificar antes**.

## Estado
Sin cambios de datos, políticas, Auth, Storage ni Edge Functions en producción. Sin cargo adicional. No certificado para clientes reales.
