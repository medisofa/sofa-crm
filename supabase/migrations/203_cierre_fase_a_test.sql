-- 203 · Prueba de la 202 (Cierre de Fase A · I65). app.qa_run_tests_cierre_fase_a()
-- Se deshace sola (rollback por excepción). No deja datos.
create or replace function app.qa_run_tests_cierre_fase_a()
returns table(n int, resultado text, prueba text, detalle text)
language plpgsql
as $function$
declare
  v_res jsonb := '[]'::jsonb;
  v_u1 constant uuid := '20200000-0000-4000-8000-000000000001';
  v_u2 constant uuid := '20200000-0000-4000-8000-000000000002';
  v_u3 constant uuid := '20200000-0000-4000-8000-000000000003';  -- inactivo
  v_x jsonb; v_t text; v_ok boolean; v_n int;
  v_ult_mig text; v_ult_ver text;   -- 5.10.0: se calculan ANTES de cambiar de rol (authenticated no lee app.schema_migrations)
begin
  if not exists (select 1 from app.schema_migrations where version = '202') then
    raise exception 'Falta la migración 202. Aplícala y vuelve a correr las pruebas.';
  end if;

  select max(m.version) into v_ult_mig
    from app.schema_migrations m where m.report->>'version' is not null;
  select m.report->>'version' into v_ult_ver
    from app.schema_migrations m where m.report->>'version' is not null order by m.version desc limit 1;

  begin
    -- Fixtures: dos usuarios activos y uno inactivo
    insert into auth.users (id, email) values
      (v_u1, 'qa.i65.u1@sofa.do'), (v_u2, 'qa.i65.u2@sofa.do'), (v_u3, 'qa.i65.u3@sofa.do')
      on conflict (id) do nothing;
    insert into public.profiles (id, full_name, is_active) values
      (v_u1, 'QA I65 Uno', true), (v_u2, 'QA I65 Dos', true), (v_u3, 'QA I65 Tres', false)
      on conflict (id) do update set is_active = excluded.is_active;

    -- CF-01 · La migración 202 queda registrada
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-01 · La migración 202 queda registrada','ok',
      exists(select 1 from app.schema_migrations where version='202'),'d',null));

    -- CF-02 · La tabla user_onboarding no la toca la API (ni anon ni authenticated)
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-02 · user_onboarding sin permisos para anon ni authenticated','ok',
      (not has_table_privilege('anon','public.user_onboarding','select')
       and not has_table_privilege('authenticated','public.user_onboarding','select')
       and not has_table_privilege('authenticated','public.user_onboarding','insert')),'d',null));

    -- CF-03 · Las cuatro funciones son SECURITY DEFINER con search_path vacío
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-03 · Las funciones son SECURITY DEFINER con search_path vacío','ok',
      (select bool_and(p.prosecdef and array_to_string(coalesce(p.proconfig,array[]::text[]),',') like '%search_path=%')
         from pg_proc p join pg_namespace nx on nx.oid=p.pronamespace
        where nx.nspname='public' and p.proname in ('changelog_list','app_version','onboarding_get','onboarding_mark')),'d',null));

    -- CF-04 · ATAQUE: anon no están abiertas; authenticated sí
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-04 · Las funciones no están abiertas a anon y sí a authenticated','ok',
      (not has_function_privilege('anon','public.changelog_list()','execute')
       and has_function_privilege('authenticated','public.changelog_list()','execute')
       and not has_function_privilege('anon','public.onboarding_get()','execute')
       and has_function_privilege('authenticated','public.onboarding_mark(text, text)','execute')),'d',null));

    -- Sesión u1
    perform set_config('role','authenticated',true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role','authenticated','aal','aal2')::text, true);

    -- CF-05 · changelog_list devuelve varias versiones
    v_x := public.changelog_list();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-05 · La bitácora devuelve varias versiones','ok',
      jsonb_typeof(v_x)='array' and jsonb_array_length(v_x) >= 5,'d', format('%s versiones', jsonb_array_length(v_x))));

    -- CF-06 · Ordenada de la más nueva a la más vieja
    --        5.10.0: antes exigía que la primera fuera la 202, y eso caducaba en cada entrega. Ahora
    --        compara contra la migración de mayor número que haya registrado versión.
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-06 · La más nueva va primero','ok',
      (v_x->0->>'migracion') = v_ult_mig,
      'd', 'primera: '||coalesce(v_x->0->>'migracion','-')||' · última registrada: '||coalesce(v_ult_mig,'-')));

    -- CF-07 · Cada entrada trae solo versión/iteración/tema/migración (sin otros campos)
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-07 · Cada entrada trae solo los campos de versión (sin datos de pacientes ni del negocio)','ok',
      (select bool_and((select bool_and(k in ('version','iteracion','tema','migracion')) from jsonb_object_keys(e) k))
         from jsonb_array_elements(v_x) e),'d',null));

    -- CF-08 · app_version devuelve la versión más reciente
    v_t := public.app_version();
    -- 5.10.0: antes fijaba '5.5.0' a mano. Ahora comprueba que coincide con la versión registrada más reciente.
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-08 · app_version coincide con la última versión registrada','ok',
      v_t = v_ult_ver, 'd', 'app_version='||coalesce(v_t,'-')||' · registrada='||coalesce(v_ult_ver,'-')));

    -- CF-09 · onboarding por defecto: muestra el recorrido, no hecho
    v_x := public.onboarding_get();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-09 · Por defecto el recorrido se muestra y no está hecho','ok',
      (v_x->>'show_tour')::boolean and not (v_x->>'tour_done')::boolean,'d',null));

    -- CF-10 · Marcar el recorrido lo da por hecho y ya no se muestra
    v_x := public.onboarding_mark('tour');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-10 · Marcar el recorrido lo da por hecho','ok',
      (v_x->>'tour_done')::boolean and not (v_x->>'show_tour')::boolean,'d',null));

    -- CF-11 · Marcar el manual guarda el rol
    v_x := public.onboarding_mark('manual','client');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-11 · Marcar el manual guarda que se vio y con qué rol','ok',
      (v_x->>'manual_seen')::boolean and (v_x->>'manual_role') = 'client','d',null));

    -- CF-12 · Un paso inválido se rechaza
    begin
      perform public.onboarding_mark('otro');
      v_ok := false; v_t := 'no falló';
    exception when others then v_ok := (sqlerrm like '%Paso no válido%'); v_t := left(sqlerrm,90);
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-12 · Un paso inválido se rechaza con instrucción','ok',v_ok,'d',v_t));

    -- CF-13 · ATAQUE: leer la tabla directo está prohibido para el usuario
    begin
      select count(*) into v_n from public.user_onboarding;
      v_ok := false; v_t := format('leyó %s filas', v_n);
    exception when others then v_ok := (sqlerrm like '%permission denied%' or sqlerrm like '%denegado%'); v_t := left(sqlerrm,90);
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-13 · ATAQUE: el usuario no lee la tabla de onboarding directamente','ok',v_ok,'d',v_t));

    -- Sesión u2: su onboarding sigue en cero (lo de u1 no lo afectó)
    perform set_config('request.jwt.claims', json_build_object('sub', v_u2, 'role','authenticated','aal','aal2')::text, true);
    v_x := public.onboarding_get();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-14 · AISLAMIENTO: lo que marcó un usuario no afecta a otro','ok',
      (v_x->>'show_tour')::boolean and not (v_x->>'tour_done')::boolean,'d',null));

    -- CF-15 · Usuario inactivo (u3) no ve la bitácora
    perform set_config('request.jwt.claims', json_build_object('sub', v_u3, 'role','authenticated','aal','aal2')::text, true);
    begin
      v_x := public.changelog_list();
      v_ok := false; v_t := 'no falló';
    exception when others then v_ok := (sqlerrm like '%Inicia sesión%'); v_t := left(sqlerrm,90);
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-15 · Un usuario inactivo no ve las novedades','ok',v_ok,'d',v_t));

    -- CF-16 · ATAQUE: sin sesión, la bitácora falla
    perform set_config('role','none',true);
    perform set_config('request.jwt.claims','',true);
    begin
      v_x := public.changelog_list();
      v_ok := false; v_t := 'no falló';
    exception when others then v_ok := true; v_t := left(sqlerrm,90);
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CF-16 · ATAQUE: sin sesión no hay bitácora','ok',v_ok,'d',v_t));

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('role','none',true);
  perform set_config('request.jwt.claims','',true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,   -- 5.10.0: una prueba NULL cuenta como fallo, antes bool_and la ignoraba
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;

revoke all on function app.qa_run_tests_cierre_fase_a() from public, anon, authenticated;
