-- 077 · Suite de la 076 (centro y modalidad por especialidad en capture_claim). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_centro_modalidad();
create or replace function app.qa_run_tests_centro_modalidad()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_c1 uuid := 'd7000000-0000-4000-8000-0000000000f1'; v_c2 uuid := 'd7000000-0000-4000-8000-0000000000f2'; v_c3 uuid := 'd7000000-0000-4000-8000-0000000000f3';
  v_ars uuid; v_proc uuid; v_d date := date_trunc('month', current_date)::date;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000000f1';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000000f1';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_admin constant text := 'a7000000-0000-4000-8000-0000000000f1';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_admin::uuid, 'qa.cm.admin@sofa.test', 'x');
    insert into public.profiles (id, full_name) values (v_admin::uuid, 'qa.cm.admin') on conflict (id) do nothing;
    update public.app_settings set require_delivery_evidence = false where operator_id = v_op;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
      values (v_org, 'client', v_op, 'QA CM A', '00000000151', 'Médico independiente', 'activo', current_date - 90, '8095550003');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. CM A', 'Cirugía General');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_op, v_admin::uuid, 'admin');
    insert into public.health_centers (id, organization_id, name) values (v_c1, v_org, 'Centro QA Uno'), (v_c2, v_org, 'Centro QA Dos'), (v_c3, v_org, 'Centro QA Tres');
    select id into v_ars from public.ars where code = 'humano';
    select id into v_proc from public.procedures where internal_code = 'SOFA-P07';

    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.create_contract_tariff(v_prov, v_ars, v_proc, 1000, v_d - 100, null, 'CT-CM');

    -- CT-01 · Con un solo centro asignado, se guarda solo en la reclamación
    perform set_config('role', 'none', true);
    insert into public.provider_centers (provider_id, center_id, is_primary) values (v_prov, v_c1, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente CM 1', 'NSS-CM-1', 'AUT-CM-1', null, null, 1, 'cirugia');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Un solo centro asignado se guarda automáticamente','ok',
      (select center_id = v_c1 and clinic_name = 'Centro QA Uno' and care_mode = 'cirugia' from public.service_lines where id = (v_x->>'id')::uuid),'d',null));

    -- CT-02 · Modalidad inexistente se rechaza con mensaje de acción
    begin
      perform public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente CM 2', 'NSS-CM-2', 'AUT-CM-2', null, null, 1, 'xyz');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Modalidad inexistente se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Modalidad inexistente se rechaza','ok',sqlerrm like 'Modalidad de atención no válida%','d',left(sqlerrm,110)));
    end;

    -- CT-03 · Si la especialidad tiene lista y la modalidad no está, se rechaza
    perform set_config('role', 'none', true);
    insert into public.specialty_care_modes (specialty, care_mode) values ('cirugía general', 'consultorio'), ('cirugía general', 'cirugia');
    perform set_config('role', 'authenticated', true);
    begin
      perform public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente CM 3', 'NSS-CM-3', 'AUT-CM-3', null, null, 1, 'uci');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · UCI no habilitada para la especialidad se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · UCI no habilitada para la especialidad se rechaza','ok',sqlerrm like '%no está habilitada para la especialidad%','d',left(sqlerrm,110)));
    end;

    -- CT-04 · Modalidad habilitada se acepta
    v_x := public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente CM 4', 'NSS-CM-4', 'AUT-CM-4', null, null, 1, 'consultorio');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Modalidad habilitada se acepta','ok',(v_x->>'id') is not null,'d',null));

    -- CT-05 · Valores antiguos (ambulatorio) se siguen aceptando
    v_x := public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente CM 5', 'NSS-CM-5', 'AUT-CM-5', null, null, 1, 'ambulatorio');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · El valor antiguo ambulatorio sigue funcionando','ok',(v_x->>'id') is not null,'d',null));

    -- CT-06 · Sin modalidad sigue aceptándose (compatibilidad)
    v_x := public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente CM 6', 'NSS-CM-6', 'AUT-CM-6');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Sin modalidad se acepta (compatibilidad)','ok',(v_x->>'id') is not null,'d',null));

    -- CT-07 · Centro no asignado al médico se rechaza
    begin
      perform public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente CM 7', 'NSS-CM-7', 'AUT-CM-7', null, null, 1, 'consultorio', null, null, null, 'bloquear', null, false, v_c3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Centro no asignado al médico se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Centro no asignado al médico se rechaza','ok',sqlerrm like 'El centro de salud elegido no está asignado%','d',left(sqlerrm,110)));
    end;

    -- CT-08 · Con dos centros, el elegido se guarda; sin elegir queda vacío
    perform set_config('role', 'none', true);
    insert into public.provider_centers (provider_id, center_id) values (v_prov, v_c2);
    perform set_config('role', 'authenticated', true);
    v_x := public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente CM 8', 'NSS-CM-8', 'AUT-CM-8', null, null, 1, 'consultorio', null, null, null, 'bloquear', null, false, v_c2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08a · Con dos centros se guarda el elegido','ok',
      (select center_id = v_c2 from public.service_lines where id = (v_x->>'id')::uuid),'d',null));
    v_x := public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente CM 9', 'NSS-CM-9', 'AUT-CM-9', null, null, 1, 'consultorio');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08b · Con dos centros y sin elegir queda sin centro','ok',
      (select center_id is null from public.service_lines where id = (v_x->>'id')::uuid),'d',null));

    -- CT-09 · Existe una sola versión de capture_claim y tiene search_path fijo
    select count(*) into v_n from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname = 'capture_claim';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Una sola versión de capture_claim con search_path fijo','ok',
      v_n = 1 and (select coalesce(p.proconfig::text,'') like '%search_path%' from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname='public' and p.proname='capture_claim'),'d',v_n::text));

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
