-- 205 · Prueba de la 204 (Modo clínica · I66). app.qa_run_tests_modo_clinica()
-- Se deshace sola (rollback por excepción). No deja datos.
create or replace function app.qa_run_tests_modo_clinica()
returns table(n int, resultado text, prueba text, detalle text)
language plpgsql
as $function$
declare
  v_res jsonb := '[]'::jsonb;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_sa  constant uuid := '20600000-0000-4000-8000-000000000001';  -- super admin de SOFA
  v_dir constant uuid := '20600000-0000-4000-8000-000000000002';  -- director de la clínica (rol client)
  v_cli constant uuid := '20600000-0000-4000-8000-0000000000a1';  -- Centro médico
  v_cli2 constant uuid := '20600000-0000-4000-8000-0000000000a2'; -- otro Centro médico
  v_indep constant uuid := '20600000-0000-4000-8000-0000000000a3';-- Médico independiente
  v_p1 constant uuid := '20600000-0000-4000-8000-0000000000b1';
  v_p2 constant uuid := '20600000-0000-4000-8000-0000000000b2';
  v_p3 constant uuid := '20600000-0000-4000-8000-0000000000b3';
  v_x jsonb; v_dep uuid; v_dep2 uuid; v_ok boolean; v_t text;
begin
  if not exists (select 1 from app.schema_migrations where version = '204') then
    raise exception 'Falta la migración 204. Aplícala y vuelve a correr las pruebas.';
  end if;

  begin
    -- Fixtures
    insert into public.organizations (id, kind, operator_id, legal_name, org_type, status, started_on) values
      (v_cli,  'client', v_sofa, 'QA I66 Clínica Uno', 'Centro médico', 'activo', current_date - 100),
      (v_cli2, 'client', v_sofa, 'QA I66 Clínica Dos', 'Centro médico', 'activo', current_date - 100),
      (v_indep,'client', v_sofa, 'QA I66 Médico Indep', 'Médico independiente', 'activo', current_date - 100)
      on conflict (id) do nothing;
    insert into auth.users (id, email) values (v_sa,'qa.i66.sa@sofa.do'), (v_dir,'qa.i66.dir@sofa.do') on conflict (id) do nothing;
    insert into public.profiles (id, full_name, is_active) values (v_sa,'QA I66 SA', true), (v_dir,'QA I66 Director', true)
      on conflict (id) do update set is_active = true;
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      (v_sofa, v_sa, 'super_admin', true), (v_cli, v_dir, 'client', true) on conflict do nothing;
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values
      (v_p1, v_cli, 'Dr. QA Uno', 'Cardiología', true),
      (v_p2, v_cli, 'Dra. QA Dos', 'Imágenes', true),
      (v_p3, v_cli, 'Dr. QA Tres', 'Pediatría', true) on conflict (id) do nothing;

    -- CL-01 · migración registrada
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-01 · La migración 204 queda registrada','ok',
      exists(select 1 from app.schema_migrations where version='204'),'d',null));
    -- CL-02 · tabla sin permisos API
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-02 · clinic_departments sin permisos para anon ni authenticated','ok',
      (not has_table_privilege('authenticated','public.clinic_departments','select')
       and not has_table_privilege('authenticated','public.clinic_departments','insert')),'d',null));
    -- CL-03 · funciones security definer con search_path vacío
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-03 · Las funciones son SECURITY DEFINER con search_path vacío','ok',
      (select bool_and(p.prosecdef and array_to_string(coalesce(p.proconfig,array[]::text[]),',') like '%search_path=%')
         from pg_proc p join pg_namespace nx on nx.oid=p.pronamespace
        where nx.nspname='public' and p.proname in ('clinic_departments_list','clinic_department_save','clinic_department_set_active','clinic_provider_assign','clinic_overview')),'d',null));
    -- CL-04 · grants
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-04 · Las funciones no están abiertas a anon y sí a authenticated','ok',
      (not has_function_privilege('anon','public.clinic_overview(uuid)','execute')
       and has_function_privilege('authenticated','public.clinic_overview(uuid)','execute')),'d',null));

    -- Sesión Super Admin
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role','authenticated','aal','aal2')::text, true);

    -- CL-05 · crear departamento
    v_x := public.clinic_department_save(v_cli, 'Cardiología');
    select id into v_dep from public.clinic_departments where organization_id = v_cli and lower(name)='cardiología' and is_active;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-05 · El Super Admin crea un departamento','ok',
      v_dep is not null and (v_x->>'can_manage')::boolean,'d',null));
    perform public.clinic_department_save(v_cli, 'Imágenes');
    select id into v_dep2 from public.clinic_departments where organization_id = v_cli and lower(name)='imágenes' and is_active;

    -- CL-06 · nombre duplicado
    begin perform public.clinic_department_save(v_cli, 'cardiología'); v_ok:=false; v_t:='no falló';
    exception when others then v_ok:=(sqlerrm like '%Ya hay un departamento%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-06 · Un departamento con nombre repetido se rechaza','ok',v_ok,'d',v_t));

    -- CL-07 · renombrar
    perform public.clinic_department_save(v_cli, 'Imagenología', v_dep2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-07 · Renombrar un departamento funciona','ok',
      exists(select 1 from public.clinic_departments where id=v_dep2 and name='Imagenología'),'d',null));

    -- CL-08 · asignar médico a depto de su clínica
    perform public.clinic_provider_assign(v_p1, v_dep);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-08 · Asignar un médico a un departamento de su clínica','ok',
      (select department_id from public.providers where id=v_p1) = v_dep,'d',null));

    -- CL-09 · ATAQUE: depto de otra clínica
    perform public.clinic_department_save(v_cli2, 'Laboratorio');
    begin
      perform public.clinic_provider_assign(v_p2, (select id from public.clinic_departments where organization_id=v_cli2 and is_active limit 1));
      v_ok:=false; v_t:='no falló';
    exception when others then v_ok:=(sqlerrm like '%otra clínica%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-09 · ATAQUE: no se asigna un médico a un departamento de otra clínica','ok',v_ok,'d',v_t));

    -- CL-10 · lista cuenta médicos por depto y sin departamento
    perform public.clinic_provider_assign(v_p2, v_dep);
    v_x := public.clinic_departments_list(v_cli);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-10 · La lista cuenta médicos por departamento y los que no tienen','ok',
      (v_x->>'sin_departamento')::int = 1
      and (select (e->>'medicos')::int from jsonb_array_elements(v_x->'departments') e where e->>'name'='Cardiología') = 2,'d',
      format('sin depto=%s', v_x->>'sin_departamento')));

    -- CL-11 · desactivar departamento deja a sus médicos sin departamento
    perform public.clinic_department_set_active(v_dep, false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-11 · Desactivar un departamento deja a sus médicos sin departamento','ok',
      (select count(*) from public.providers where department_id = v_dep) = 0
      and not exists(select 1 from public.clinic_departments where id=v_dep and is_active),'d',null));

    -- CL-13 · overview: médicos y caja del mes (numérica, 0 sin cobros)
    v_x := public.clinic_overview(v_cli);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-13 · El resumen de la clínica trae médicos activos y la caja del mes','ok',
      (v_x->>'medicos_activos')::int = 3 and (v_x->>'caja_mes')::numeric = 0,'d', format('médicos=%s', v_x->>'medicos_activos')));

    -- CL-15 · ATAQUE: un Médico independiente no entra al modo clínica
    begin v_x := public.clinic_departments_list(v_indep); v_ok:=false; v_t:='no falló';
    exception when others then v_ok:=(sqlerrm like '%Centro médico%' or sqlerrm like '%sin acceso%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-15 · ATAQUE: un Médico independiente no entra al modo clínica','ok',v_ok,'d',v_t));

    -- Sesión director de la clínica (rol client)
    perform set_config('request.jwt.claims', json_build_object('sub', v_dir, 'role','authenticated','aal','aal2')::text, true);
    -- CL-12 · el director ve pero no administra
    v_x := public.clinic_departments_list(v_cli);
    v_ok := not (v_x->>'can_manage')::boolean;
    begin perform public.clinic_department_save(v_cli, 'Odontología'); v_ok := false; v_t:='no falló';
    exception when others then v_ok := v_ok and (sqlerrm like '%administran%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-12 · El director de la clínica ve los departamentos pero no los crea','ok',v_ok,'d',v_t));

    -- CL-14 · AISLAMIENTO: el director no ve otra clínica
    begin v_x := public.clinic_departments_list(v_cli2); v_ok:=false; v_t:='no falló';
    exception when others then v_ok:=(sqlerrm like '%sin acceso%' or sqlerrm like '%no encontrada%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-14 · AISLAMIENTO: el director de una clínica no ve otra','ok',v_ok,'d',v_t));

    -- CL-16 · ATAQUE: sin sesión
    perform set_config('request.jwt.claims','',true);
    begin v_x := public.clinic_overview(v_cli); v_ok:=false; v_t:='no falló';
    exception when others then v_ok:=true; v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CL-16 · ATAQUE: sin sesión no hay resumen de clínica','ok',v_ok,'d',v_t));

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('request.jwt.claims','',true);
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

revoke all on function app.qa_run_tests_modo_clinica() from public, anon, authenticated;
