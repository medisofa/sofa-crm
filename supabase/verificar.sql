-- 1.7.7 · Después de aplicar 060 y 061
select * from app.qa_run_tests_estabilizacion();   -- debe decir TODO OK (incluye la regresión de las 21 suites)
select version, applied_at from app.schema_migrations where version in ('058','060') order by 1;
select count(*) as facturas_sofa_sin_ncf from public.work_queue() where kind = 'sofa_ncf';
