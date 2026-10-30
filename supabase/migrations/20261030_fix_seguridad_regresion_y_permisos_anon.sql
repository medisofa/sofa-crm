-- Ya aplicado en producción (30/10/2026). Hallazgo del auditor de seguridad de Supabase
-- (mcp__Supabase__get_advisors), revisado tras fusionar los PR #93 y #96.

-- 1) [CRÍTICO] Regresión real: la migración de renewal_of_case_id/renewal_seq (PR #93) recreó
-- v_habilitation_cases con CREATE OR REPLACE VIEW sin conservar security_invoker=true,
-- revirtiendo silenciosamente la corrección de PR #89 (4 vistas BI con privilegios de owner que
-- dejaban a cualquier usuario autenticado consultar datos cruzados entre clientes). El auditor lo
-- marcó como ERROR ("Security Definer View").
alter view public.v_habilitation_cases set (security_invoker = true);

-- 2) [Higiene] Funciones nuevas de los PR #93 y #96 quedaron con EXECUTE abierto a PUBLIC/anon
-- por el default de Postgres. Cada una ya valida auth.uid()/el rol internamente (un anónimo solo
-- recibe un rechazo limpio, no hay fuga de datos), pero no deben quedar ejecutables sin sesión;
-- mismo criterio que la limpieza previa "corrige permisos de anon en funciones nuevas".
revoke execute on function public.create_habilitation_case(text, text, uuid, uuid, text, numeric, date, text, text, uuid) from public, anon;
revoke execute on function public.habilitation_cases_for_lead(uuid) from public, anon;
revoke execute on function public.patient_payment_add(uuid, uuid, text, text, numeric, text, date, uuid, text) from public, anon;
revoke execute on function public.patient_payment_void(uuid, text) from public, anon;
revoke execute on function public.patient_payments_board(uuid) from public, anon;
revoke execute on function app.payments_read_ok(uuid) from public;
revoke execute on function app.payments_write_ok(uuid) from public;
revoke execute on function public.set_assistant_permissions(uuid, uuid, boolean, boolean, boolean) from public, anon;
revoke execute on function public.set_capturer_payments(uuid, uuid, boolean) from public, anon;
revoke execute on function public.supply_movement_add(uuid, uuid, text, numeric, date, text, text) from public, anon;
revoke execute on function public.supply_save(uuid, uuid, text, text, text, numeric, boolean, uuid, boolean, numeric) from public, anon;

grant execute on function public.create_habilitation_case(text, text, uuid, uuid, text, numeric, date, text, text, uuid) to authenticated;
grant execute on function public.habilitation_cases_for_lead(uuid) to authenticated;
grant execute on function public.patient_payment_add(uuid, uuid, text, text, numeric, text, date, uuid, text) to authenticated;
grant execute on function public.patient_payment_void(uuid, text) to authenticated;
grant execute on function public.patient_payments_board(uuid) to authenticated;
grant execute on function app.payments_read_ok(uuid) to authenticated;
grant execute on function app.payments_write_ok(uuid) to authenticated;
grant execute on function public.set_assistant_permissions(uuid, uuid, boolean, boolean, boolean) to authenticated;
grant execute on function public.set_capturer_payments(uuid, uuid, boolean) to authenticated;
grant execute on function public.supply_movement_add(uuid, uuid, text, numeric, date, text, text) to authenticated;
grant execute on function public.supply_save(uuid, uuid, text, text, text, numeric, boolean, uuid, boolean, numeric) to authenticated;
