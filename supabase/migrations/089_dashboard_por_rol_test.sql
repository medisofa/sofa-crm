-- 089 · Suite de la 088 (dashboard según el rol). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_dashboard_rol();
create or replace function app.qa_run_tests_dashboard_rol()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000000b1';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000000b1';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_cli constant text := 'a7000000-0000-4000-8000-0000000000b1';
  v_sec constant text := 'a7000000-0000-4000-8000-0000000000b2';
  v_fact constant text := 'a7000000-0000-4000-8000-0000000000b3';
  v_adm constant text := 'a7000000-0000-4000-8000-0000000000b4';
  v_glo constant text := 'a7000000-0000-4000-8000-0000000000b5';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_cli::uuid,'qa.db.cli@sofa.test','x'),(v_sec::uuid,'qa.db.sec@sofa.test','x'),
      (v_fact::uuid,'qa.db.fact@sofa.test','x'),(v_adm::uuid,'qa.db.adm@sofa.test','x'),(v_glo::uuid,'qa.db.glo@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.db.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
      values (v_org, 'client', v_op, 'QA DB', '00000000191', 'Médico independiente', 'activo', current_date - 90, '8095550008');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. DB', 'Pediatría');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_cli::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'),
      (v_op, v_fact::uuid, 'billing'), (v_op, v_adm::uuid, 'admin'), (v_op, v_glo::uuid, 'glosas');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_prov, v_org, true, true);
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, phone, payer_type, status) values
      (v_org, v_prov, current_date, '09:00', 'Paciente DB Hoy 1', '8095551111', 'privado', 'programada'),
      (v_org, v_prov, current_date, '10:00', 'Paciente DB Hoy 2', '8095551112', 'privado', 'confirmada'),
      (v_org, v_prov, current_date + 1, '10:00', 'Paciente DB Mañana', '8095551113', 'privado', 'programada');

    -- CT-01 · Médico
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.my_dashboard();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · El médico solo ve la sección Mi consultorio','ok',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e) = array['medico'],'d',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Citas de hoy = 2','ok',(select (k->>'value')::numeric from jsonb_array_elements((select e from jsonb_array_elements(v_x->'sections') e where e->>'code' = 'medico')->'kpis') k where k->>'code' = 'citas_hoy') = 2,'d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Deuda con SOFA en cero y sin alerta','ok',(select (k->>'value')::numeric from jsonb_array_elements((select e from jsonb_array_elements(v_x->'sections') e where e->>'code' = 'medico')->'kpis') k where k->>'code' = 'deuda_sofa') = 0 and (select e from jsonb_array_elements(v_x->'sections') e where e->>'code' = 'medico')->'alert' = 'null'::jsonb,'d',null));

    -- CT-04 · Secretaria
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_x := public.my_dashboard();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · La secretaria solo ve Agenda del día','ok',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e) = array['secretaria'],'d',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Citas de mañana sin confirmar = 1 y citas de hoy = 2','ok',(select (k->>'value')::numeric from jsonb_array_elements((select e from jsonb_array_elements(v_x->'sections') e where e->>'code' = 'secretaria')->'kpis') k where k->>'code' = 'sin_confirmar') = 1 and (select (k->>'value')::numeric from jsonb_array_elements((select e from jsonb_array_elements(v_x->'sections') e where e->>'code' = 'secretaria')->'kpis') k where k->>'code' = 'citas_hoy') = 2,'d',null));

    -- CT-06 · Facturación
    perform set_config('request.jwt.claims', json_build_object('sub', v_fact, 'role', 'authenticated')::text, true);
    v_x := public.my_dashboard();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Facturación ve solo su sección','ok',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e) = array['facturacion'],'d',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e)::text));

    -- CT-07 · Glosas
    perform set_config('request.jwt.claims', json_build_object('sub', v_glo, 'role', 'authenticated')::text, true);
    v_x := public.my_dashboard();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Glosas ve solo su sección','ok',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e) = array['glosas'],'d',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e)::text));

    -- CT-08 · Administrador
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.my_dashboard();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · El Administrador ve Dirección SOFA','ok',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e) @> array['direccion'],'d',(select array_agg(e->>'code' order by e->>'code') from jsonb_array_elements(v_x->'sections') e)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Cada indicador trae etiqueta, valor y nivel','ok',not exists (select 1 from jsonb_array_elements((select e from jsonb_array_elements(v_x->'sections') e where e->>'code' = 'direccion')->'kpis') k where k->>'label' is null or k->'value' is null or k->>'level' is null),'d',null));

    -- CT-10 · Sin sesión
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.my_dashboard();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Sin sesión no hay dashboard','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Sin sesión no hay dashboard','ok',sqlerrm like 'Inicie sesión%','d',left(sqlerrm,110)));
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
