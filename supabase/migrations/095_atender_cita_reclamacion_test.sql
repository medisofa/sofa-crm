-- 095 · Suite de la 094 (atender cita y crear su reclamación). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_atender_cita();
create or replace function app.qa_run_tests_atender_cita()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_ars uuid; v_proc uuid;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000000e9';
  v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000000ea';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000000e9';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_adm constant text := 'a7000000-0000-4000-8000-0000000000e9';
  v_cli constant text := 'a7000000-0000-4000-8000-0000000000ea';
  v_otro constant text := 'a7000000-0000-4000-8000-0000000000eb';
  v_pat constant uuid := 'e7000000-0000-4000-8000-0000000000e9';
  v_a_priv constant uuid := 'f7000000-0000-4000-8000-0000000000e1';
  v_a_auto constant uuid := 'f7000000-0000-4000-8000-0000000000e2';
  v_a_sinm constant uuid := 'f7000000-0000-4000-8000-0000000000e3';
  v_a_expl constant uuid := 'f7000000-0000-4000-8000-0000000000e4';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    select id into v_ars from public.ars where code = 'humano';
    select id into v_proc from public.procedures where internal_code = 'SOFA-P07';
    update public.app_settings set require_delivery_evidence = false where operator_id = v_op;
    insert into auth.users (id, email, encrypted_password) values (v_adm::uuid,'qa.at.adm@sofa.test','x'),(v_cli::uuid,'qa.at.cli@sofa.test','x'),(v_otro::uuid,'qa.at.otro@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.at.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_org, 'client', v_op, 'QA AT A', '00000000221', 'Médico independiente', 'activo', current_date - 90, '8095550012'),
      (v_org2, 'client', v_op, 'QA AT B', '00000000222', 'Médico independiente', 'activo', current_date - 90, '8095550013');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. AT', 'Medicina General QA');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_op, v_adm::uuid, 'admin'), (v_org, v_cli::uuid, 'client'), (v_org2, v_otro::uuid, 'client');
    insert into public.patients (id, organization_id, full_name, doc_number, phone) values (v_pat, v_org, 'Paciente AT Auto', '00100000221', '8095550301');
    insert into public.appointments (id, organization_id, provider_id, patient_id, appointment_date, appointment_time, patient_name, patient_doc, member_number, phone, payer_type, ars_id, authorization_number, reason, status) values
      (v_a_priv, v_org, v_prov, null, current_date, '08:00', 'Paciente AT Privado', null, null, '8095550300', 'privado', null, null, 'Consulta primera vez', 'programada'),
      (v_a_auto, v_org, v_prov, v_pat, current_date, '09:00', 'Paciente AT Auto', '001-0000022-1', 'NSS-AT-1', '8095550301', 'ars', v_ars, 'AUT-AT-1', 'Consulta Ambulatoria', 'en_espera'),
      (v_a_sinm, v_org, v_prov, null, current_date, '10:00', 'Paciente AT Sin Motivo', null, 'NSS-AT-2', '8095550302', 'ars', v_ars, 'AUT-AT-2', 'Consulta de seguimiento', 'confirmada'),
      (v_a_expl, v_org, v_prov, null, current_date, '11:00', 'Paciente AT Explícito', null, 'NSS-AT-3', '8095550303', 'ars', v_ars, 'AUT-AT-3', null, 'programada');
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.create_contract_tariff(v_prov, v_ars, v_proc, 1300, current_date - 30, null, 'CT-AT');

    -- CT-01 · Cita privada
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.attend_appointment(v_a_priv);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Cita privada no crea reclamación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Cita privada no crea reclamación','ok',sqlerrm like 'La cita es de pago privado%','d',left(sqlerrm,110)));
    end;

    -- CT-02 · Motivo que no es un servicio contratado
    begin
      perform public.attend_appointment(v_a_sinm);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Sin servicio y con Motivo genérico pide el servicio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Sin servicio y con Motivo genérico pide el servicio','ok',sqlerrm like 'Indique el servicio%','d',left(sqlerrm,110)));
    end;

    -- CT-03/04 · Motivo = servicio contratado: crea, enlaza y copia el paciente
    v_x := public.attend_appointment(v_a_auto);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Crea la reclamación y la cita queda atendida y enlazada','ok',(select status = 'atendida' and service_line_id = (v_x->>'id')::uuid from public.appointments where id = v_a_auto),'d',v_x::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · La reclamación toma la tarifa y el paciente del registro','ok',(select patient_id = v_pat and amount = 1300 from public.service_lines where id = (v_x->>'id')::uuid),'d',null));
    begin
      perform public.attend_appointment(v_a_auto);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · No se atiende dos veces','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · No se atiende dos veces','ok',sqlerrm like 'La cita ya fue atendida%','d',left(sqlerrm,110)));
    end;

    -- CT-06 · Servicio indicado explícitamente
    v_x := public.attend_appointment(v_a_expl, v_proc);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Con el servicio indicado también la crea','ok',(v_x->>'procedure_id')::uuid = v_proc and (v_x->>'id') is not null,'d',v_x::text));

    -- CT-07 · Otro médico no puede
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.attend_appointment(v_a_sinm, v_proc);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro médico no atiende citas ajenas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro médico no atiende citas ajenas','ok',sqlerrm like 'Sin acceso a la agenda%','d',left(sqlerrm,110)));
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
