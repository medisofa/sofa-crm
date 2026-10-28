-- 081 · Suite de la 080 (módulos por rol y orden por uso). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_modulos();
create or replace function app.qa_run_tests_modulos()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_orgA constant uuid := 'b7000000-0000-4000-8000-0000000000c1';
  v_pA constant uuid := 'c7000000-0000-4000-8000-0000000000c1';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_admin constant text := 'a7000000-0000-4000-8000-0000000000c1';
  v_fact constant text := 'a7000000-0000-4000-8000-0000000000c2';
  v_sec constant text := 'a7000000-0000-4000-8000-0000000000c3';
  v_aud constant text := 'a7000000-0000-4000-8000-0000000000c4';
  v_mix constant text := 'a7000000-0000-4000-8000-0000000000c5';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_admin::uuid,'qa.mo.admin@sofa.test','x'),(v_fact::uuid,'qa.mo.fact@sofa.test','x'),(v_sec::uuid,'qa.mo.sec@sofa.test','x'),(v_aud::uuid,'qa.mo.aud@sofa.test','x'),(v_mix::uuid,'qa.mo.mix@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.mo.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
      values (v_orgA, 'client', v_op, 'QA MO A', '00000000171', 'Médico independiente', 'activo', current_date - 90, '8095550006');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_pA, v_orgA, 'Dr. MO A', 'Cardiología');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (v_op, v_admin::uuid, 'admin'), (v_op, v_fact::uuid, 'billing'), (v_orgA, v_sec::uuid, 'capturer'), (v_op, v_aud::uuid, 'auditor'),
      (v_op, v_mix::uuid, 'billing'), (v_orgA, v_mix::uuid, 'client');

    -- CT-01 · Facturación ve exactamente sus 5 módulos
    perform set_config('request.jwt.claims', json_build_object('sub', v_fact, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.my_modules();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Facturación ve sus 5 módulos y está restringida','ok',(v_x->>'restricted')::boolean and jsonb_array_length(v_x->'modules') = 5 and v_x->'modules'->0->>'code' = 'dashboard','d',v_x::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Facturación no ve Radicación','ok',not exists (select 1 from jsonb_array_elements(v_x->'modules') e where e->>'code' = 'radicacion'),'d',null));

    -- CT-03 · Secretaria: Dashboard, Trabajo de hoy, Nueva cita
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_x := public.my_modules();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Secretaria ve solo Dashboard, Trabajo de hoy y Nueva cita','ok',jsonb_array_length(v_x->'modules') = 3 and exists (select 1 from jsonb_array_elements(v_x->'modules') e where e->>'code' = 'nueva_cita'),'d',v_x::text));

    -- CT-04 · Rol sin matriz (auditor) no se restringe
    perform set_config('request.jwt.claims', json_build_object('sub', v_aud, 'role', 'authenticated')::text, true);
    v_x := public.my_modules();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Un rol sin matriz no se restringe (ve todo el catálogo)','ok',not (v_x->>'restricted')::boolean and jsonb_array_length(v_x->'modules') = (select count(*) from public.app_modules),'d',null));

    -- CT-05 · Dos roles, uno sin matriz: no se restringe
    perform set_config('request.jwt.claims', json_build_object('sub', v_mix, 'role', 'authenticated')::text, true);
    v_x := public.my_modules();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Con un rol sin matriz entre sus roles, no se restringe','ok',not (v_x->>'restricted')::boolean,'d',null));

    -- CT-06 · El menú se ordena por clics; el Dashboard sigue primero
    perform set_config('request.jwt.claims', json_build_object('sub', v_fact, 'role', 'authenticated')::text, true);
    perform public.track_module_use('reclamaciones'); perform public.track_module_use('reclamaciones'); perform public.track_module_use('retiros_fisicos');
    v_x := public.my_modules();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Orden por uso: Dashboard, luego Reclamaciones (2 clics), luego Retiros (1)','ok',v_x->'modules'->0->>'code' = 'dashboard' and v_x->'modules'->1->>'code' = 'reclamaciones' and v_x->'modules'->2->>'code' = 'retiros_fisicos','d',(v_x->'modules')::text));

    -- CT-07 · Módulo desconocido da mensaje de acción
    begin
      perform public.track_module_use('no_existe');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Módulo desconocido se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Módulo desconocido se rechaza','ok',sqlerrm like 'Módulo desconocido%','d',left(sqlerrm,90)));
    end;

    -- CT-08 · Facturación no puede cambiar la matriz
    begin
      perform public.set_role_modules('billing', array['dashboard']);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no cambia la matriz','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no cambia la matriz','ok',sqlerrm like 'Solo el Super Admin%','d',left(sqlerrm,90)));
    end;

    -- CT-09 · El Administrador cambia la matriz y siempre queda el Dashboard
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    perform public.set_role_modules('auditor', array['reclamaciones']);
    perform set_config('request.jwt.claims', json_build_object('sub', v_aud, 'role', 'authenticated')::text, true);
    v_x := public.my_modules();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Auditor ahora ve Dashboard + Reclamaciones','ok',(v_x->>'restricted')::boolean and jsonb_array_length(v_x->'modules') = 2,'d',(v_x->'modules')::text));

    -- CT-10 · Lista vacía quita la restricción del rol
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    perform public.set_role_modules('auditor', array[]::text[]);
    perform set_config('request.jwt.claims', json_build_object('sub', v_aud, 'role', 'authenticated')::text, true);
    v_x := public.my_modules();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Lista vacía deja el rol sin restricción','ok',not (v_x->>'restricted')::boolean,'d',null));

    -- CT-11 · Rol inexistente
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    begin
      perform public.set_role_modules('inventado', array['dashboard']);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · Rol inexistente se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · Rol inexistente se rechaza','ok',sqlerrm like 'El rol%no existe%','d',left(sqlerrm,90)));
    end;

    -- CT-12 · module_usage no se lee directo: con RLS y sin política, el usuario ve 0 filas aunque existan datos
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    perform public.track_module_use('reclamaciones');
    begin
      select count(*) into v_n from public.module_usage;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · module_usage no se lee directo (0 filas visibles)','ok',v_n = 0,'d',v_n::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · module_usage no se lee directo (0 filas visibles)','ok',true,'d',left(sqlerrm,90)));
    end;

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
