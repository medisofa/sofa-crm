-- SOFA · 5.32.3 · Advisor cleanup: revocación explícita a anon de las dos RPCs agregadas hoy.
-- El REVOKE ALL ... FROM public ya las deja inaccesibles al rol anon en la práctica, pero el
-- advisor `anon_security_definer_function_executable` solo pasa cuando la revocación es explícita.
--
-- Ya aplicado en producción (mcp__Supabase__apply_migration 12/11/2026).
revoke execute on function public.admin_update_user_profile(uuid, text, text) from anon;
revoke execute on function public.client_account_detail(uuid) from anon;
