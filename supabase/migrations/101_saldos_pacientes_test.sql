-- 101 · Suite de la 100 (saldos pendientes de pacientes). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_saldos_pacientes();
create or replace function app.qa_run_tests_saldos_pacientes()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_proc uuid; v_m uuid;
  v_org constant uuid := 'b7000000-0000-4000-8000-000000000119';
  v_prov constant uuid := 'c7000000-0000-4000-8000-000000000119';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_cli constant text := 'a7000000-0000-4000-8000-000000000119';
  v_sec constant text := 'a7000000-0000-4000-8000-00000000011a';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    select id into v_proc from public.procedures where internal_code = 'SOFA-P07';
    insert into auth.users (id, email, encrypted_password) values (v_cli::uuid,'qa.sp.cli@sofa.test','x'),(v_sec::uuid,'qa.sp.sec@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.sp.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
      values (v_org, 'client', v_op, 'QA SP', '00000000251', 'Médico independiente', 'activo', current_date - 200, '8095550018');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. SP', 'Dermatología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_cli::uuid, 'client'), (v_org, v_sec::uuid, 'capturer');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_prov, v_org, true, false);
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, patient_doc, phone, payer_type, status) values
      (v_org, v_prov, current_date - 20, '09:00', 'Paciente SP Uno', '001-0000025-1', '8095550501', 'privado', 'atendida');
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.create_private_tariff(v_prov, v_proc, 2000, current_date - 60, null);
    perform public.register_private_charge(v_prov, current_date - 20, 'Paciente SP Uno', '001-0000025-1', v_proc, 1, 'pendiente', null, 0, null, null);
    perform public.register_private_charge(v_prov, current_date - 5,  'Paciente SP Uno', '00100000251', v_proc, 1, 'pendiente', null, 0, null, null);
    perform public.register_private_charge(v_prov, current_date - 3,  'Paciente SP Pagó', null, v_proc, 1, 'efectivo', null, 0, null, null);
    perform public.register_private_charge(v_prov, current_date - 2,  'Paciente SP Sin Tel', null, v_proc, 1, 'pendiente', null, 0, null, null);

    v_x := public.patient_balances(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Dos pacientes con saldo (el que pagó no aparece)','ok',jsonb_array_length(v_x) = 2,'d',v_x::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Los dos cobros del mismo documento (con y sin guiones) se agrupan: RD$ 4,000, 20 días','ok',exists (select 1 from jsonb_array_elements(v_x) e where (e->>'amount')::numeric = 4000 and (e->>'charges')::int = 2 and (e->>'days')::int = 20 and e->>'phone' = '8095550501'),'d',v_x::text));

    v_m := public.queue_balance_reminder(v_prov, '00100000251', 'Paciente SP Uno');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Prepara el recordatorio con el monto y la fecha','ok',(select body like '%RD$ 4,000.00%' and body like '%2 servicio%' and to_phone = '8095550501' from public.message_queue where id = v_m),'d',(select body from public.message_queue where id = v_m)));
    begin
      perform public.queue_balance_reminder(v_prov, '00100000251', 'Paciente SP Uno');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · No se prepara dos veces el mismo día','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · No se prepara dos veces el mismo día','ok',sqlerrm like 'Ya se preparó hoy%','d',left(sqlerrm,110)));
    end;
    begin
      perform public.queue_balance_reminder(v_prov, null, 'Paciente SP Sin Tel');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Sin teléfono pide registrarlo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Sin teléfono pide registrarlo','ok',sqlerrm like 'No hay un teléfono%','d',left(sqlerrm,110)));
    end;
    begin
      perform public.queue_balance_reminder(v_prov, null, 'Paciente SP Pagó');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Paciente sin saldo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Paciente sin saldo','ok',sqlerrm like 'Este paciente no tiene cobros pendientes%','d',left(sqlerrm,110)));
    end;
    perform public.mark_message(v_m, 'enviado');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · El médico lo marca como enviado','ok',(select status from public.message_queue where id = v_m) = 'enviado','d',null));

    -- Secretaria sin WhatsApp
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_x := public.patient_balances(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · La secretaria ve los saldos','ok',jsonb_array_length(v_x) = 2,'d',null));
    begin
      perform public.queue_balance_reminder(v_prov, null, 'Paciente SP Sin Tel');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Sin WhatsApp activado no prepara recordatorios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Sin WhatsApp activado no prepara recordatorios','ok',sqlerrm like 'Sin acceso para preparar mensajes%','d',left(sqlerrm,110)));
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
