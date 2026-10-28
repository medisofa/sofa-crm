-- SOFA · Registro de la revisión de seguridad solicitada tras las funciones
-- agregadas en esta sesión. Ya aplicado en Supabase (bpwjhgpzhzhiocoxrvzq).
--
-- Hallazgo: el proyecto revoca EXECUTE de PUBLIC/anon por defecto en todas
-- las funciones (20261027000200_revoke_anon_default_execute.sql), dejando
-- solo un puñado de entradas públicas verificadas. Las funciones agregadas
-- en esta sesión (support_view_start/end, clinical_access_*, view_as_user)
-- se crearon con CREATE OR REPLACE sin ese REVOKE explícito, así que
-- Postgres las dejó con el EXECUTE por defecto a PUBLIC (incluye anon). Se
-- rechazan igual por sus propias validaciones internas (is_staff, auth.uid(),
-- role_for_org), pero no debían quedar expuestas.

REVOKE ALL ON FUNCTION public.support_view_start(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.support_view_start(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.support_view_end(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.support_view_end(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.clinical_access_request(uuid, int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clinical_access_request(uuid, int, text) TO authenticated;

REVOKE ALL ON FUNCTION public.clinical_access_pending(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clinical_access_pending(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.clinical_access_respond(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clinical_access_respond(uuid, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.clinical_access_active(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clinical_access_active(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.clinical_access_revoke(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clinical_access_revoke(uuid) TO authenticated;

REVOKE ALL ON FUNCTION app.view_as_user() FROM PUBLIC, anon, authenticated;
-- No se llama directo desde el cliente: solo otras funciones SECURITY
-- DEFINER del mismo dueño (capturer_providers, capturer_org_ids,
-- capturer_can, patient_access), que no necesitan grant explícito.

-- ===== Resto de la revisión (sin hallazgos que corregir) =====
-- - Las 501 tablas de public tienen RLS activa (consulta a pg_class), ninguna
--   tiene RLS deshabilitada.
-- - Ninguna política tiene USING/WITH CHECK genérico ('true') salvo SELECT en
--   tablas de catálogo público (app_modules, care_modes, habilitation_fees,
--   role_capabilities, role_modules, specialty_care_modes) — listas de
--   referencia, no datos de clientes ni financieros por organización.
-- - Ninguna función SECURITY DEFINER carece de `SET search_path` (se verificó
--   contra pg_proc.proconfig para las ~500 funciones de app/public).
-- - Solo una tabla tiene GRANT directo a anon: intake_service_defs (SELECT),
--   catálogo del formulario público de solicitud, sin datos sensibles.
-- - El uso de EXECUTE format(...) (SQL dinámico) está contenido a
--   herramientas de QA/rendimiento/reinicio de datos, todas sin EXECUTE para
--   anon.
