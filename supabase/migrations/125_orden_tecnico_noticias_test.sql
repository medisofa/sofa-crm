-- 125 · Suite de la 124 (noticias y revisión general). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_orden_tecnico();
create or replace function app.qa_run_tests_orden_tecnico()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_cmd text;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · La clave de las tareas está en el Vault','ok',coalesce((exists (select 1 from vault.secrets where name = 'sofa_cron_secret')), false),'d',(null)::text));
    v_ok := true;
    if to_regclass('cron.job') is not null then
      execute $q$select exists (select 1 from cron.job where jobname = 'sofa_noticias_diarias' and command like '%app.call_market_intel%' and command not like '%TU-PROYECTO%')$q$ into v_ok;
    end if;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · La tarea de noticias ya no tiene datos de ejemplo','ok',coalesce((v_ok), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Nadie con sesión llama la tarea de noticias','ok',coalesce((not has_function_privilege('authenticated', 'app.call_market_intel()', 'execute')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · La revisión general existe y no se llama a sí misma','ok',coalesce((to_regprocedure('app.qa_run_all()') is not null), false),'d',(null)::text));

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,   -- 5.10.0: una prueba sin resultado (NULL) cuenta como fallo; antes bool_and la ignoraba
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;
