# Gestión de accesos seleccionados: candidato para QA

Interfaz: js/modules/user-access-revoke.js. Backend: docs/sql/PROPOSED_revoke_selected_accesses.sql.
No enlazada al menú publicado. Requiere validar e instalar RPC antes de integrar la acción en Usuarios.

## Comportamiento
Super Admin selecciona organizaciones mediante casillas, revisa el alcance y confirma con motivo. Se conservan identidad, perfil, roles históricos y accesos no seleccionados. Se desactiva únicamente organization_users.is_active. No crea ni eleva roles; usar el flujo de asignación autorizado después de revisar la revocación.

## Verificación realizada
- PostgreSQL 17 sintético: 10 aserciones y 10 denegaciones esperadas.
- Dos solicitudes concurrentes: un éxito, un rechazo, una auditoría.
- Navegador con RPC simuladas: selección obligatoria, alcance exacto, motivo, confirmación, fallo mantiene formulario y éxito recarga.
- La vista previa rechaza cambios de rol anteriores a la confirmación.

Reproducir: bash scripts/run_access_revocation_qa.sh
Navegador: SOFA_PLAYWRIGHT_MODULE=/workspace/.sofa-tools/browser/node_modules/playwright/index.mjs node tests/browser/access-revoke.mjs

## Pendientes antes de producción
Probar en copia aislada con esquema completo, triggers y RLS actuales. Confirmar que revocación deniega inmediatamente llamadas directas y sesiones ya abiertas, incluidas funciones clínicas y Storage. Revisar dependencias de médico/capturista y datos actuales de la cuenta objetivo. Se bloquean de forma conservadora cuentas vinculadas a providers.user_id, cuenta propia y cualquier cuenta con rol Super Admin. No ejecutar el fixture sintético sobre una base con datos reales.

La contraseña temporal segura y menú Gestión SOFA pertenecen a la entrega frontend 5.22.9; este candidato no está habilitado por esa entrega.
