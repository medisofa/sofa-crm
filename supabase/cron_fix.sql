-- 1.7.7 · Tarea programada de noticias: hoy tiene la URL y el secreto de ejemplo, así que falla todos los días.
-- Reemplace <SU_CRON_SECRET> por el mismo valor del secreto CRON_SECRET de la Edge Function (no lo guarde en GitHub).
select cron.alter_job(
  job_id  := (select jobid from cron.job where jobname = 'sofa_noticias_diarias'),
  command := $c$ select net.http_post(
       url     := 'https://bpwjhgpzhzhiocoxrvzq.supabase.co/functions/v1/market-intel',
       headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', '<SU_CRON_SECRET>'),
       body    := '{"action":"refresh"}'::jsonb) $c$);

-- Verificación: debe mostrar la URL real y no "TU-PROYECTO"
select jobname, schedule, active, command like '%bpwjhgpzhzhiocoxrvzq%' as url_correcta, command not like '%PEGA_AQUI%' as secreto_puesto
  from cron.job where jobname = 'sofa_noticias_diarias';
