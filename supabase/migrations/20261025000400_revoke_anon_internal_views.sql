-- anon no debe consultar vistas internas de facturación y negocio.
-- Los permisos por defecto de Supabase se lo concedían.
DO $mig$
DECLARE v text;
BEGIN
  FOREACH v IN ARRAY ARRAY['v_submissions','v_payments','v_growth_monthly_real','v_mrr_real','v_stage_times_real','v_pipeline_real'] LOOP
    IF to_regclass('public.' || v) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon', v);
      RAISE NOTICE 'Revocado anon: %', v;
    END IF;
  END LOOP;
END
$mig$;
