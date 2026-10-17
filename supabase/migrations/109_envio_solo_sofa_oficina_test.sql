-- 109 · Prueba de la 108 (solo revisa la función; no cambia datos)
-- Ejecutar:  select * from app.qa_run_tests_envio_oficina();
create or replace function app.qa_run_tests_envio_oficina()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare v_src text; v_res jsonb := '[]'::jsonb;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname = 'mark_submission_sent';
  v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Facturación ya no registra el envío','ok', v_src like '%array[''super_admin'',''admin'',''operations'']%' and v_src not like '%''billing''%','d',null));
  v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · El mensaje indica a quién pedirlo','ok', v_src like '%Pida a Operaciones que lo registre%','d',null));
  v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Se conservan las validaciones fiscales y de fecha','ok', v_src like '%fiscal_check%' and v_src like '%no futura%','d',null));
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
