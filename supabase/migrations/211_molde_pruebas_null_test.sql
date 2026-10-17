-- 211 · Prueba de la 210 (El molde de las pruebas · I70). app.qa_run_tests_molde()
-- Se deshace sola (rollback por excepción). No deja datos.
create or replace function app.qa_run_tests_molde()
returns table(n int, resultado text, prueba text, detalle text)
language plpgsql
as $function$
declare
  v_res jsonb := '[]'::jsonb;
  v_ok boolean; v_n int; v_t text; v_lista text;
begin
  if not exists (select 1 from app.schema_migrations where version = '210') then
    raise exception 'Falta la migración 210. Aplícala y vuelve a correr las pruebas.';
  end if;

  begin
    -- MO-01 · La migración 210 queda registrada
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','MO-01 · La migración 210 queda registrada','ok',
      exists(select 1 from app.schema_migrations where version='210'),'d',null));

    -- MO-02 · Ninguna suite conserva el veredicto viejo (bool_and sin coalesce)
    select count(*), string_agg(p.proname, ', ' order by p.proname) into v_n, v_lista
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='app' and p.proname like 'qa\_run\_tests\_%'
       and p.proname <> 'qa_run_tests_molde'   -- esta suite contiene el molde viejo a propósito, como contraste (MO-08)
       and pg_get_functiondef(p.oid) like '%bool_and((e->>''ok'')::boolean)%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','MO-02 · Ninguna suite conserva el veredicto viejo','ok',
      v_n = 0,'d', case when v_n = 0 then 'todas al día' else v_n||' pendientes: '||left(v_lista,200) end));

    -- MO-03 · Ninguna suite conserva el conteo viejo
    select count(*), string_agg(p.proname, ', ' order by p.proname) into v_n, v_lista
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='app' and p.proname like 'qa\_run\_tests\_%'
       and p.proname <> 'qa_run_tests_molde'   -- esta suite contiene el molde viejo a propósito, como contraste (MO-08)
       and pg_get_functiondef(p.oid) like '%filter (where (e->>''ok'')::boolean)%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','MO-03 · Ninguna suite conserva el conteo viejo','ok',
      v_n = 0,'d', case when v_n = 0 then 'todas al día' else v_n||' pendientes: '||left(v_lista,200) end));

    -- MO-04 · Todas las suites quedaron con el molde nuevo (y hay al menos 60, no se perdió ninguna)
    select count(*) into v_n
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='app' and p.proname like 'qa\_run\_tests\_%'
       and pg_get_functiondef(p.oid) like '%coalesce((e->>''ok'')::boolean, false)%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','MO-04 · Todas las suites tienen el molde nuevo','ok',
      v_n >= 60,'d', v_n||' suites con coalesce'));

    -- MO-05 · Las suites siguen devolviendo las cuatro columnas de siempre
    select count(*) into v_n
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='app' and p.proname like 'qa\_run\_tests\_%'
       and pg_get_function_result(p.oid) = 'TABLE(n integer, resultado text, prueba text, detalle text)';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','MO-05 · Las suites conservan sus cuatro columnas','ok',
      v_n >= 60,'d', v_n||' suites con la firma correcta'));

    -- MO-06 · ATAQUE: ninguna suite quedó abierta a la API tras reescribirla
    select count(*), string_agg(p.proname, ', ' order by p.proname) into v_n, v_lista
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='app' and p.proname like 'qa\_run\_tests\_%'
       and (has_function_privilege('anon', p.oid, 'execute')
         or has_function_privilege('authenticated', p.oid, 'execute'));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','MO-06 · ATAQUE: ninguna suite se puede llamar desde la API','ok',
      v_n = 0,'d', case when v_n = 0 then 'todas cerradas' else v_n||' abiertas: '||left(v_lista,200) end));

    -- MO-07 · COMPORTAMIENTO: con el molde nuevo, una prueba NULL da REVISAR
    create or replace function app.qa_molde_demo_nuevo()
    returns table(n int, resultado text, prueba text, detalle text) language plpgsql as $demo$
    declare v jsonb := '[]'::jsonb;
    begin
      v := v || jsonb_build_array(jsonb_build_object('p','pasa','ok',true,'d',null));
      v := v || jsonb_build_array(jsonb_build_object('p','devuelve NULL','ok',(null::text = 'x'),'d',null));
      return query select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,
             format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
        from jsonb_array_elements(v) e;
    end $demo$;
    select d.resultado into v_t from app.qa_molde_demo_nuevo() d;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','MO-07 · Con el molde nuevo, una prueba NULL da REVISAR','ok',
      v_t = 'REVISAR','d','veredicto: '||coalesce(v_t,'(null)')));

    -- MO-08 · COMPORTAMIENTO: el molde viejo sí la ocultaba (demuestra que la corrección hace algo)
    create or replace function app.qa_molde_demo_viejo()
    returns table(n int, resultado text, prueba text, detalle text) language plpgsql as $demo$
    declare v jsonb := '[]'::jsonb;
    begin
      v := v || jsonb_build_array(jsonb_build_object('p','pasa','ok',true,'d',null));
      v := v || jsonb_build_array(jsonb_build_object('p','devuelve NULL','ok',(null::text = 'x'),'d',null));
      return query select 0, case when bool_and((e->>'ok')::boolean) then 'TODO OK' else 'REVISAR' end,
             format('%s de %s pruebas aprobadas', count(*) filter (where (e->>'ok')::boolean), count(*)), null::text
        from jsonb_array_elements(v) e;
    end $demo$;
    select d.resultado into v_t from app.qa_molde_demo_viejo() d;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','MO-08 · El molde viejo sí ocultaba el fallo (contraste)','ok',
      v_t = 'TODO OK','d','el molde viejo decía: '||coalesce(v_t,'(null)')));

    drop function if exists app.qa_molde_demo_nuevo();
    drop function if exists app.qa_molde_demo_viejo();

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('role','none',true);
  perform set_config('request.jwt.claims','',true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when coalesce((x.e->>'ok')::boolean, false) then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;

revoke all on function app.qa_run_tests_molde() from public, anon, authenticated;
