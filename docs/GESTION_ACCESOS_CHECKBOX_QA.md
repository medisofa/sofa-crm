# Gestión de accesos seleccionados: candidato para QA

Interfaz: js/modules/user-access-revoke.js. Backend: docs/sql/PROPOSED_revoke_selected_accesses.sql.
No enlazada al menú publicado. Requiere validar e instalar RPC antes de integrar la acción en Usuarios.

## Comportamiento
Super Admin selecciona organizaciones mediante casillas, revisa el alcance y confirma con motivo. Se conservan identidad, perfil, roles históricos y accesos no seleccionados. Se desactiva únicamente organization_users.is_active. No crea ni eleva roles; usar el flujo de asignación autorizado después de revisar la revocación.

## Verificación realizada
- PostgreSQL 17 sintético: 10 aserciones y 11 denegaciones esperadas (incluida organización con kind NULL y operador válido).
- Dos solicitudes concurrentes: un éxito, un rechazo, una auditoría.
- Navegador con RPC simuladas: selección obligatoria, alcance exacto, motivo, confirmación, fallo mantiene formulario y éxito recarga.
- La vista previa rechaza cambios de rol anteriores a la confirmación.

Reproducir: bash scripts/run_access_revocation_qa.sh
Navegador: SOFA_PLAYWRIGHT_MODULE=/workspace/.sofa-tools/browser/node_modules/playwright/index.mjs node tests/browser/access-revoke.mjs

## Pendientes antes de producción
Probar en copia aislada con esquema completo, triggers y RLS actuales. Comprobar los permisos efectivos tras revocar la asignación directa, con llamadas directas y sesiones ya abiertas, incluidas funciones clínicas y Storage. Un permiso concedido por otro rol puede seguir vigente; no prometer una denegación universal. Revisar dependencias de médico/capturista y datos actuales de la cuenta objetivo. Se bloquean de forma conservadora cuentas vinculadas a providers.user_id, cuenta propia y cualquier cuenta con rol Super Admin. No ejecutar el fixture sintético sobre una base con datos reales.

La contraseña temporal segura y menú Gestión SOFA pertenecen a la entrega frontend 5.22.9; este candidato no está habilitado por esa entrega.

## Alcance real de revocación
La evidencia histórica `/workspace/.sofa-tools/restore-evidence/app.visible_org_ids.sql` muestra una unión entre asociaciones directas activas y acceso derivado de un rol interno activo en el operador. La segunda rama admite consultorios del operador cuando no hay asignaciones explícitas en `staff_client_access`, cuando el rol es `super_admin`/`admin`, o cuando existe asignación explícita al consultorio. Exige además perfil activo sin cambio obligatorio de contraseña pendiente y `app.mfa_ok()`.

Por tanto, retirar la asociación directa de un cliente **no garantiza perder todo acceso a ese cliente** si permanece un rol interno que lo autoriza. Esta operación revoca asignaciones directas; no crea una política de denegación que prevalezca sobre otros roles. La evidencia procede de un respaldo anterior, no certifica la definición vigente de producción. Antes de instalar, revisar la función actual y mostrar en la confirmación los accesos derivados que sobreviven. Si el objetivo es quitar todo acceso al consultorio, también debe revisarse el alcance del rol interno mediante su flujo autorizado.

## Iteración: alcance efectivo y validación del esquema
La evidencia histórica de app.visible_org_ids muestra que un rol interno de SOFA puede otorgar visibilidad por operador, aun sin membresía directa en el cliente. La interfaz habla de asignaciones directas; no promete una prohibición universal de acceso. Para limitar permisos derivados se necesita revisar también el rol interno y staff_client_access.

Se rechaza una organización de tipo desconocido, incluido NULL. La vista previa también rechaza roles cambiados antes de confirmar. Navegador probado a 390px en ambos temas.

Ejecutar docs/sql/access_revocation_schema_readonly.sql sobre SOFA-restore-isolated obtiene exclusivamente estructura, políticas y definiciones necesarias para revisar compatibilidad. No instala el candidato ni modifica datos. No usar el fixture sintético en esa base restaurada.
