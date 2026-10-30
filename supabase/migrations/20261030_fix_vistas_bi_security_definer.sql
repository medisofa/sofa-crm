-- 30/10/2026: v_mrr_real, v_growth_monthly_real, v_stage_times_real y v_habilitation_cases son
-- SECURITY DEFINER (el valor por defecto de las vistas) y tenían SELECT otorgado a `authenticated`
-- en general, no solo a personal de SOFA. Como SECURITY DEFINER ejecuta la vista con los permisos
-- del dueño en vez de los de quien consulta, esto significa que CUALQUIER usuario con sesión
-- -un médico, una secretaria- podía leer estas vistas directo por PostgREST
-- (ej. /rest/v1/v_mrr_real) y ver ingresos y métricas agregadas de SOFA de TODOS los clientes,
-- sin pasar por ningún control de rol. Detectado al revisar los avisos de seguridad del
-- linter de Supabase.
--
-- Las tablas base (organizations, sofa_fees, fee_rules, habilitation_cases) ya tienen RLS
-- correcta por rol/organización; el problema es que la vista las consultaba con el dueño de
-- la vista (sin RLS) en vez de con el rol de quien pregunta.
--
-- Arreglo recomendado por el propio linter de Supabase: pasar las vistas a SECURITY INVOKER
-- (Postgres 15+), para que respeten la RLS de las tablas base según quien consulta, en vez de
-- quitar permisos (lo que rompería el acceso legítimo del personal de SOFA, que sí las usa
-- desde js/services/bi.js y js/services/habilitation.js).
--
-- Ya aplicado en producción (Supabase bpwjhgpzhzhiocoxrvzq); esta migración lo deja registrado.
alter view public.v_mrr_real set (security_invoker = true);
alter view public.v_growth_monthly_real set (security_invoker = true);
alter view public.v_stage_times_real set (security_invoker = true);
alter view public.v_habilitation_cases set (security_invoker = true);
