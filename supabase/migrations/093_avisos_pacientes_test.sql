-- 093 · Suite de la 092 (avisos a pacientes). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_avisos_pacientes();
create or replace function app.qa_run_tests_avisos_pacientes()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000000d9';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000000d9';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_cli constant text := 'a7000000-0000-4000-8000-0000000000d9';
  v_sec constant text := 'a7000000-0000-4000-8000-0000000000da';
  v_p1 constant uuid := 'e7000000-0000-4000-8000-0000000000d1';
  v_p2 constant uuid := 'e7000000-0000-4000-8000-0000000000d2';
  v_p3 constant uuid := 'e7000000-0000-4000-8000-0000000000d3';
  v_p4 constant uuid := 'e7000000-0000-4000-8000-0000000000d4';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_cli::uuid,'qa.av.cli@sofa.test','x'),(v_sec::uuid,'qa.av.sec@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.av.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
      values (v_org, 'client', v_op, 'QA AV', '00000000211', 'Médico independiente', 'activo', current_date - 900, '8095550011');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. AV', 'Medicina Interna');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_cli::uuid, 'client'), (v_org, v_sec::uuid, 'capturer');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_prov, v_org, true, false);
    insert into public.patients (id, organization_id, full_name, doc_number, phone) values
      (v_p1, v_org, 'Paciente AV Control', '00100000001', '8095550101'),
      (v_p2, v_org, 'Paciente AV Con Cita', '00100000002', '8095550102'),
      (v_p3, v_org, 'Paciente AV Sin Tel', '00100000003', null),
      (v_p4, v_org, 'Paciente AV Reciente', '00100000004', '8095550104');
    insert into public.appointments (organization_id, provider_id, patient_id, appointment_date, appointment_time, patient_name, phone, payer_type, status) values
      (v_org, v_prov, v_p1, current_date - 220, '09:00', 'Paciente AV Control', '8095550101', 'privado', 'atendida'),
      (v_org, v_prov, v_p2, current_date - 240, '09:00', 'Paciente AV Con Cita', '8095550102', 'privado', 'atendida'),
      (v_org, v_prov, v_p2, current_date + 5,   '09:00', 'Paciente AV Con Cita', '8095550102', 'privado', 'programada'),
      (v_org, v_prov, v_p3, current_date - 220, '09:00', 'Paciente AV Sin Tel', null, 'privado', 'atendida'),
      (v_org, v_prov, v_p4, current_date - 60,  '09:00', 'Paciente AV Reciente', '8095550104', 'privado', 'atendida'),
      (v_org, v_prov, null, current_date - 1,   '10:00', 'Paciente AV Faltó', '8095550201', 'privado', 'no_asistio'),
      (v_org, v_prov, null, current_date - 2,   '10:00', 'Paciente AV Faltó Reagendado', '8095550202', 'privado', 'no_asistio'),
      (v_org, v_prov, null, current_date + 3,   '10:00', 'Paciente AV Faltó Reagendado', '8095550202', 'privado', 'programada'),
      (v_org, v_prov, null, current_date - 10,  '10:00', 'Paciente AV Faltó Hace Tiempo', '8095550203', 'privado', 'no_asistio');

    -- CT-01 · Apagados por defecto
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.generate_patient_notices(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Apagados: no prepara avisos','ok',(v_x->>'control')::int = 0 and (v_x->>'reprogramar')::int = 0,'d',v_x::text));

    -- CT-02 · El médico los activa
    perform public.set_patient_notice_settings(v_prov, true, 6, null, true, null);
    v_x := public.patient_notice_settings(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Configuración guardada (control a 6 meses y reprogramar)','ok',(v_x->>'control_enabled')::boolean and (v_x->>'noshow_enabled')::boolean and (v_x->>'control_months')::int = 6,'d',v_x::text));

    -- CT-03 · Prepara 1 control y 1 reprogramación
    v_x := public.generate_patient_notices(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · 1 control (sin cita futura, con teléfono, más de 6 meses) y 1 reprogramar (faltó y no reagendó)','ok',(v_x->>'control')::int = 1 and (v_x->>'reprogramar')::int = 1,'d',v_x::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · El control es para el paciente correcto con su nombre y el del médico','ok',exists (select 1 from public.message_queue where patient_id = v_p1 and kind = 'control_pendiente' and body like '%Paciente AV Control%' and body like '%Dr. AV%'),'d',null));
    v_x := public.generate_patient_notices(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Correrlo otra vez no duplica','ok',(v_x->>'control')::int = 0 and (v_x->>'reprogramar')::int = 0,'d',v_x::text));

    -- CT-06 · Validaciones
    begin
      perform public.set_patient_notice_settings(v_prov, true, 30, null, true, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Meses fuera de 1 a 24 se rechazan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Meses fuera de 1 a 24 se rechazan','ok',sqlerrm like 'Los meses para el control%','d',left(sqlerrm,110)));
    end;

    -- CT-07 · El médico ve y marca
    select count(*) into v_n from public.message_queue where provider_id = v_prov and kind in ('control_pendiente','reprogramar_cita');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · El médico ve los 2 avisos','ok',v_n = 2,'d',v_n::text));
    perform public.mark_message((select id from public.message_queue where patient_id = v_p1 and kind = 'control_pendiente'), 'enviado');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · El médico marca el control como enviado','ok',(select status from public.message_queue where patient_id = v_p1 and kind = 'control_pendiente') = 'enviado','d',null));

    -- CT-09 · Secretaria sin WhatsApp
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    select count(*) into v_n from public.message_queue where provider_id = v_prov and kind in ('control_pendiente','reprogramar_cita');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · La secretaria sin WhatsApp no ve los avisos','ok',v_n = 0,'d',v_n::text));
    begin
      perform public.set_patient_notice_settings(v_prov, false, 6, null, false, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · La secretaria no cambia la configuración','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · La secretaria no cambia la configuración','ok',sqlerrm like 'Solo el médico o el Administrador%','d',left(sqlerrm,110)));
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
