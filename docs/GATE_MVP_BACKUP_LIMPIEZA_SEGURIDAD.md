# SOFA — Puerta de salida hacia MVP (18 octubre 2026)

Proyecto exclusivo: Supabase `bpwjhgpzhzhiocoxrvzq`; GitHub `medisofa/sofa-crm`. NO operar sobre HemoCura.

## Estado comprobado
- La opción A fue autorizada: respaldo verificable, eliminación selectiva de usuarios externos **de prueba** y sus datos **de prueba**, conservación de administradores y configuración, política de mínimo privilegio y certificación de aislamiento.
- No existen ramas de Supabase de desarrollo en el proyecto (consulta `list_branches`).
- Último inventario: 16 `auth.users`, 16 perfiles, 19 membresías, 6 organizaciones, 240 reclamaciones, 1 documento, 2 pagos, 2493 eventos de auditoría.
- La bitácora `backup_drills` registra dos respaldos descargados el 9 de octubre, pero **no se verificó restauración del estado actual**.
- Security Advisor: 98 tablas con RLS activado y sin política (puede ser denegación intencional), 1 función con `search_path` mutable, 5 funciones SECURITY DEFINER ejecutables por `anon`, 439 por `authenticated`, y protección de contraseñas filtradas deshabilitada. **Son hallazgos de revisión, no prueba automática de explotación.**
- Nueve identidades externas simuladas devolvieron cero filas fuera de sus membresías activas en pruebas SELECT, pero falta prueba HTTP y escritura.

## Secuencia bloqueante de implementación
1. Crear backup completo verificable (Postgres, Auth, Storage); registrar fecha, conteos, checksums, ubicación cifrada y resultado de restauración en entorno aislado. No registrar contraseñas ni claves en GitHub.
2. Obtener manifiesto de datos de prueba vs reales, ID de usuario/organización, dependencias y qué administradores SOFA se preservan. Nunca asumir que toda la producción es ficticia.
3. Crear entorno aislado y restaurar backup. Ejecutar allí limpieza selectiva y verificar integridad referencial, continuidad administrativa y ausencia de datos huérfanos.
4. Migración controlada: por defecto una organización activa por identidad externa; excepción explícita y auditable (autorizador, motivo, vigencia, organizaciones), sin impedir acceso interno SOFA por rol y MFA. No aplicar constraint indiscriminado antes de resolver la cuenta externa con cuatro membresías.
5. Auditar funciones SECURITY DEFINER expuestas por permisos EXECUTE, verificar controles `auth.uid()`, `app.can`, ámbito de organización y `search_path`; restringir solo funciones injustificadamente públicas tras comprobar consumidores.
6. Ejecutar matriz A/B: dos médicos, dos capturadoras, dos organizaciones, datos sintéticos, SELECT/INSERT/UPDATE/DELETE, Storage download/signed URLs, RPCs/Edge Functions; staff SOFA MFA positivo y negativo; probar acceso legítimo y bloqueo ajeno.
7. Registrar evidencias reproducibles; solo declarar GO si cero lecturas/escrituras ajenas, restauración probada, roles internos verificados y sin fallos críticos.

## Criterio de parada
**Sin backup restaurado y manifiesto de eliminación aprobado no ejecutar DELETE ni cambios en Auth.** Una limpieza irreversible sin respaldo incumpliría la autorización condicionada del usuario.

## Estado de esta iteración
Auditoría y plan registrados en rama de GitHub; **no se borraron usuarios ni datos, no se alteró Supabase, no se certificó MVP**.
