-- Restaura security_invoker=true en vistas que lo perdieron al ser reemplazadas
-- con CREATE OR REPLACE VIEW sin cláusula WITH.
ALTER VIEW IF EXISTS public.v_submissions SET (security_invoker = true);
ALTER VIEW IF EXISTS public.v_growth_monthly_real SET (security_invoker = true);
ALTER VIEW IF EXISTS public.v_mrr_real SET (security_invoker = true);
ALTER VIEW IF EXISTS public.v_stage_times_real SET (security_invoker = true);
