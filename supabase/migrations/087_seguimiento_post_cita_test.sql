-- 087 · Suite de la 086 (seguimiento post-cita por WhatsApp). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_seguimiento();
create or replace function app.qa_run_tests_seguimiento()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000000a1';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000000a1';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_cli constant text := 'a7000000-0000-4000-8000-0000000000a1';
  v_sec constant text := 'a7000000-0000-4000-8000-0000000000a2';
  v_a1 constant uuid := 'f7000000-0000-4000-8000-0000000000a1';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_cli::uuid,'qa.sg.cli@sofa.test','x'),(v_sec::uuid,'qa.sg.sec@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.sg.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
      values (v_org, 'client', v_op, 'QA SG', '00000000181', 'Médico independiente', 'activo', current_date - 90, '8095550007');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. SG', 'Cardiología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_cli::uuid, 'client'), (v_org, v_sec::uuid, 'capturer');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_prov, v_org, true, false);
    insert into public.appointments (id, organization_id, provider_id, appointment_date, appointment_time, patient_name, phone, payer_type, status) values
      (v_a1, v_org, v_prov, current_date - 2, '09:00', 'Paciente SG Uno', '8095551111', 'privado', 'atendida');
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, phone, payer_type, status) values
      (v_org, v_prov, current_date - 2, '10:00', 'Paciente SG Cancelado', '8095552222', 'privado', 'cancelada'),
      (v_org, v_prov, current_date - 1, '10:00', 'Paciente SG Ayer', '8095553333', 'privado', 'atendida'),
      (v_org, v_prov, current_date - 2, '11:00', 'Paciente SG Sin Tel', null, 'privado', 'atendida');

    -- CT-01 · Sin activar, no se genera nada
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.followup_settings(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Por defecto el seguimiento está apagado','ok',not (v_x->>'enabled')::boolean,'d',v_x::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Apagado no genera mensajes','ok',public.generate_followups(v_prov) = 0,'d',null));

    -- CT-03 · El médico lo activa a 2 días
    perform public.set_followup_settings(v_prov, true, 2, null);
    v_n := public.generate_followups(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Genera 1 mensaje (solo la cita atendida hace 2 días con teléfono)','ok',v_n = 1,'d',v_n::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · No duplica si se corre otra vez','ok',public.generate_followups(v_prov) = 0,'d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · El texto por defecto lleva el nombre del paciente y del médico','ok',exists (select 1 from public.message_queue where appointment_id = v_a1 and kind = 'seguimiento_cita' and body like '%Paciente SG Uno%' and body like '%Dr. SG%'),'d',null));

    -- CT-06 · Texto propio con marcadores
    perform set_config('role', 'none', true);
    delete from public.message_queue where appointment_id = v_a1 and kind = 'seguimiento_cita';
    perform set_config('role', 'authenticated', true);
    perform public.set_followup_settings(v_prov, true, 2, 'Saludos {paciente}, gracias por visitar a {medico}.');
    perform public.generate_followups(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Texto propio con marcadores de paciente y médico reemplazados','ok',exists (select 1 from public.message_queue where appointment_id = v_a1 and kind = 'seguimiento_cita' and body = 'Saludos Paciente SG Uno, gracias por visitar a Dr. SG.'),'d',null));

    -- CT-07 · Días fuera de rango
    begin
      perform public.set_followup_settings(v_prov, true, 30, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Días fuera de 1 a 14 se rechazan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Días fuera de 1 a 14 se rechazan','ok',sqlerrm like 'Los días después de la cita%','d',left(sqlerrm,110)));
    end;

    -- CT-08 · El médico ve y marca el mensaje
    select count(*) into v_n from public.message_queue where kind = 'seguimiento_cita' and provider_id = v_prov;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · El médico ve el mensaje de seguimiento','ok',v_n = 1,'d',v_n::text));
    perform public.mark_message((select id from public.message_queue where appointment_id = v_a1 and kind = 'seguimiento_cita'), 'enviado');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · El médico lo marca como enviado','ok',(select status from public.message_queue where appointment_id = v_a1 and kind = 'seguimiento_cita') = 'enviado','d',null));

    -- CT-10 · La secretaria sin WhatsApp no lo ve ni configura
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    select count(*) into v_n from public.message_queue where kind = 'seguimiento_cita' and provider_id = v_prov;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Secretaria sin WhatsApp no ve el seguimiento','ok',v_n = 0,'d',v_n::text));
    begin
      perform public.set_followup_settings(v_prov, false, 2, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · La secretaria no cambia la configuración','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · La secretaria no cambia la configuración','ok',sqlerrm like 'Solo el médico o el Administrador%','d',left(sqlerrm,110)));
    end;

    -- CT-12 · Con WhatsApp activado por el médico, sí lo ve
    perform set_config('role', 'none', true);
    update public.capturer_scopes set can_whatsapp = true where user_id = v_sec::uuid and provider_id = v_prov;
    perform set_config('role', 'authenticated', true);
    select count(*) into v_n from public.message_queue where kind = 'seguimiento_cita' and provider_id = v_prov;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · Con WhatsApp activado la secretaria sí lo ve','ok',v_n = 1,'d',v_n::text));

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
