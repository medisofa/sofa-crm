# SOFA — EJECUCIÓN DEL GATE GO/NO-GO (evidencia de producción)
Fecha: 2026-10-18
Proyecto auditado: Supabase bpwjhgpzhzhiocoxrvzq; solo lectura.
Decisión: NO-GO; no modificar producción, no contratar rama Supabase, no copiar PHI a Neon.

## Paso 1: respaldo restaurable
Consulta real: public.backup_drills tiene dos registros done_on=2026-10-09, kind=respaldo_descargado, result=ok, sin notas de restauración.
Resultado: FALLA EVIDENCIA. No se verificó artefacto íntegro reciente ni restauración aislada de Postgres+Auth+Storage. No afirmar que backup existe o es recuperable por este registro. Sin restauración, detener migraciones.

## Paso 2: política real
Consulta de app.visible_org_ids() en producción confirma que primera rama concede organizaciones por membership activo y perfil válido, sin vencimiento de excepción externa. Existe al menos un usuario con múltiples membresías de cliente (4 filas de membresía para usuarios multicliente).
Resultado: BLOQUEANTE CONFIRMADO para política un cliente por defecto y excepciones temporales. Propuestas de SQL existentes NO desplegables sin integración en app.can, capturer, RPC, Storage y Edge, y staging fiel.

## Paso 3: autenticación y API
Supabase lista Edge Functions: crear-usuario (verify_jwt=true), admin-users (false), restablecer-clave (true), market-intel (false), enviar-correos (true).
Código inspeccionado: admin-users obtiene JWT de cabecera, verifica sesión con admin.auth.getUser(jwt), y delega autorización a RPC admin_assign_role; market-intel acepta JWT + isAllowed o x-cron-secret. verify_jwt=false no prueba bypass por sí solo, pero es superficie crítica para pruebas de denegación, MFA, replay, autorización de RPC y cron secret. No se hicieron llamadas mutantes ni autenticadas a producción.
Resultado: PENDIENTE. No hay JWT de usuarios de ensayo ni staging Supabase disponible en el contexto.

## Paso 4: flujo operacional
Tablas existentes incluyen claim_status_history, claim_transitions, claim_resubmissions, glosas, payments, payment_allocations, documents, service_lines. Presencia de tablas no demuestra proceso funcional completo. No crear reclamación ficticia en producción.
Resultado: NO CERTIFICADO.

## Paso 5: dictamen y firma
Dictamen técnico: NO-GO, pendiente de aprobación por responsable autorizado.
No se ha firmado en nombre del usuario.

## Requisitos para reanudar cambios de manera segura
A. Backup actual con artefactos verificables de Postgres/Auth/Storage y restore drill documentado en ambiente aislado.
B. Staging compatible con Supabase Auth/Storage/Edge y datos 100% ficticios, sin costo nuevo autorizado.
C. Migración integral con revisión de SECURITY DEFINER, RLS, staff MFA, excepciones expiradas/revocadas, capturer y controles de escritura.
D. Matriz de pruebas autenticadas y flujo ARS completo con rollback y auditoría.
E. Firma GO por responsable SOFA una vez todos los criterios estén PASS.

Se evita expresamente aplicar migraciones sobre producción sin backup verificable y autorización nueva. No usar la rama Supabase de pago previamente rechazada.
