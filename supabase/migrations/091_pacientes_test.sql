-- 091 · Suite de la 090 (registro de pacientes). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_pacientes();
create or replace function app.qa_run_tests_pacientes()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_ars uuid; v_p uuid;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000000c9';
  v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000000ca';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000000c9';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_cli constant text := 'a7000000-0000-4000-8000-0000000000c9';
  v_sec constant text := 'a7000000-0000-4000-8000-0000000000ca';
  v_otro constant text := 'a7000000-0000-4000-8000-0000000000cb';
  v_fact constant text := 'a7000000-0000-4000-8000-0000000000cc';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    select id into v_ars from public.ars where code = 'humano';
    insert into auth.users (id, email, encrypted_password) values (v_cli::uuid,'qa.px.cli@sofa.test','x'),(v_sec::uuid,'qa.px.sec@sofa.test','x'),
      (v_otro::uuid,'qa.px.otro@sofa.test','x'),(v_fact::uuid,'qa.px.fact@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.px.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_org, 'client', v_op, 'QA PX A', '00000000201', 'Médico independiente', 'activo', current_date - 90, '8095550009'),
      (v_org2, 'client', v_op, 'QA PX B', '00000000202', 'Médico independiente', 'activo', current_date - 90, '8095550010');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. PX', 'Medicina Interna');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_cli::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'),
      (v_org2, v_otro::uuid, 'client'), (v_op, v_fact::uuid, 'billing');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_prov, v_org, true, false);
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, patient_doc, member_number, phone, payer_type, ars_id, status) values
      (v_org, v_prov, current_date - 3, '09:00', 'Paciente PX Uno', '001-1234567-8', null, '8095551111', 'privado', null, 'atendida'),
      (v_org, v_prov, current_date - 2, '09:00', 'Paciente PX Dos', null, 'NSS-PX-2', '8095551112', 'ars', v_ars, 'atendida'),
      (v_org, v_prov, current_date - 1, '09:00', 'Paciente PX Manual', '00199999999', null, '8095551113', 'privado', null, 'atendida');

    -- CT-01 · El médico crea una ficha (documento normalizado)
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_p := public.save_patient(null, v_org, 'Paciente PX Manual', '001-9999999-9', date '1980-05-01', 'F', '8095551113');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · El médico crea la ficha y el documento queda sin guiones','ok',(select doc_number from public.patients where id = v_p) = '00199999999','d',null));
    begin
      perform public.save_patient(null, v_org, 'Otro Nombre', '00199999999');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Documento repetido se rechaza con indicación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Documento repetido se rechaza con indicación','ok',sqlerrm like 'Ya existe un paciente con el documento%','d',left(sqlerrm,110)));
    end;
    begin
      perform public.save_patient(null, v_org, 'Paciente PX Tres', null, null, 'Z');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Sexo no válido se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Sexo no válido se rechaza','ok',sqlerrm like 'Sexo no válido%','d',left(sqlerrm,110)));
    end;
    begin
      perform public.search_patients(v_org, 'P');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Búsqueda de menos de 2 caracteres','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Búsqueda de menos de 2 caracteres','ok',sqlerrm like 'Escriba al menos 2%','d',left(sqlerrm,110)));
    end;

    -- CT-05 · La secretaria del médico busca
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_x := public.search_patients(v_org, 'px man');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · La secretaria encuentra la ficha por nombre','ok',jsonb_array_length(v_x) = 1,'d',v_x::text));

    -- CT-06/07 · Otro médico y Facturación no acceden
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.search_patients(v_org, 'PX');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Otro médico no ve los pacientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Otro médico no ve los pacientes','ok',sqlerrm like 'Sin acceso a los pacientes%','d',left(sqlerrm,110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_fact, 'role', 'authenticated')::text, true);
    begin
      perform public.search_patients(v_org, 'PX');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Facturación no ve el registro de pacientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Facturación no ve el registro de pacientes','ok',sqlerrm like 'Sin acceso a los pacientes%','d',left(sqlerrm,110)));
    end;
    select count(*) into v_n from public.patients where organization_id = v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no lee la tabla directamente','ok',v_n = 0,'d',v_n::text));

    -- CT-09 · Vincular el historial
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    v_x := public.link_patients(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Crea 2 fichas nuevas y vincula las 3 citas','ok',(v_x->>'created')::int = 2 and (v_x->>'linked_appointments')::int = 3,'d',v_x::text));
    v_x := public.link_patients(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Volver a correr no duplica','ok',(v_x->>'created')::int = 0 and (v_x->>'linked_appointments')::int = 0,'d',v_x::text));

    -- CT-11 · Ficha con historial y bitácora
    v_x := public.patient_card(v_p);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · La ficha trae su cita','ok',jsonb_array_length(v_x->'appointments') = 1,'d',(v_x->'appointments')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · Abrir la ficha queda en la bitácora','ok',exists (select 1 from public.patient_access_log where patient_id = v_p and action = 'ver' and user_id = v_cli::uuid),'d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-13 · La ficha no tiene campos clínicos','ok',not (v_x->'patient' ?| array['diagnosis','diagnostico','clinical_notes']),'d',null));

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
