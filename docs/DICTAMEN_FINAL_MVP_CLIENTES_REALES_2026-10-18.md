# SOFA — DICTAMEN DE ACEPTACIÓN MVP PARA CLIENTES REALES
Fecha: 2026-10-18
Proyecto Supabase SOFA: bpwjhgpzhzhiocoxrvzq (NO HemoCura)
Estado: NO-GO para alta de clientes externos reales. Evaluación cerrada; no se autoriza despliegue.
Modalidad: auditoría read-only, sin cambios en producción ni gastos adicionales.

## Evidencia verificada en Supabase
- auth.users 16, profiles 16, organization_users activas 19, organizations 6, service_lines 240, audit_log 2493.
- 4 filas de membresías de clientes correspondientes a usuario(s) con más de una membresía activa de cliente.
- app.visible_org_ids() sigue incluyendo organizaciones de membresía activa sin comprobar expiración de excepción de acceso externo; la función de ensayo de Neon NO está desplegada aquí.
- Security Advisor: 98 tablas con RLS habilitado sin políticas. Pueden estar cerradas intencionalmente; revisar relevancia y necesidad de acceso por cliente.
- Ensayo Neon: roles separados, políticas RLS sintéticas y controles de aislamiento funcionales; NO equivalen a autenticación real Supabase.
- Scripts HTTP/JWT sintéticos y GitHub Actions creados; no hay prueba HTTP end-to-end confirmada contra Supabase.

## Puertas obligatorias de aceptación (criterios verificables)
G1. BACKUP: copia íntegra y reciente de Postgres + Auth + Storage, integridad y restauración comprobada en entorno aislado. Estado: NO DEMOSTRADO.
G2. IDENTIDAD: cuentas externas reales de prueba en entorno aislado, MFA staff, JWT válidos/expirados/revocados; denegación de privilegios. Estado: NO DEMOSTRADO.
G3. MULTITENANT: cada usuario externo una organización por defecto; excepción temporal autorizada con vencimiento y revocación efectivos en lectura/escritura; staff alcance explícito + MFA. Estado: NO CUMPLE (función actual no verifica caducidad).
G4. RLS END-TO-END: controles positivos y negativos con usuarios autenticados para SELECT/INSERT/UPDATE/DELETE sobre service_lines, documents, payments y tablas MVP; RPC, Storage y Edge Functions; cero acceso cruzado. Estado: NO DEMOSTRADO.
G5. OPERACIÓN: prueba completa prospecto→contrato→captura→retiro→validación→radicación→pago/glosa, trazabilidad por reclamación y reconciliación; perfiles médico/secretaria/SOFA. Estado: NO DEMOSTRADO.
G6. SEGURIDAD Y AUDITORÍA: revisar grants EXECUTE a funciones SECURITY DEFINER, advisor findings, secretos, bitácora, permisos de exportación, protección de credenciales y políticas de retención. Estado: PENDIENTE.
G7. CONTINUIDAD: prueba de recuperación, errores, rollback y soporte antes de alta de clientes. Estado: NO DEMOSTRADO.

## Cierre de evaluación
NO-GO. No afirmar que SOFA está listo para datos reales de pacientes. No eliminar usuarios ni datos; no ejecutar reset_scope_tables; no migrar SQL a producción sin backup restaurable y autorización expresa. No confundir 15 pruebas Neon con certificación del sistema real.

## Ruta mínima para cambiar a GO
1. Obtener y verificar backup restaurable sin alterar producción.
2. Corregir de forma controlada la política real de excepción expirada y rutas de autorización relacionadas; probar en staging fiel a Supabase.
3. Ejecutar matriz real con JWT autenticados, SELECT/INSERT/UPDATE/DELETE, Storage/RPC/Edge, staff MFA y casos positivos.
4. Validar 1 flujo de reclamación completo, reversión y registro de auditoría.
5. Documentar resultados reproducibles y firmar GO/NO-GO por responsable.

La próxima actividad no es crear más simulaciones: es remediación + validación real con las garantías previas. No existe evidencia suficiente para certificar GO en el estado actual.
