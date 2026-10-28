-- 137 · Suite de la 136 (avisos al paciente con su portal). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_avisos_portal();
create or replace function app.qa_run_tests_avisos_portal()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000003f1'; v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000003f2';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000003f1';
  v_med constant text := 'a7000000-0000-4000-8000-0000000003f1'; v_sec constant text := 'a7000000-0000-4000-8000-0000000003f2';
  v_otro constant text := 'a7000000-0000-4000-8000-0000000003f3';
  v_pat uuid; v_apt uuid; v_proc uuid; v_msg uuid; v_tok text; v_req uuid; v_cnt int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.ap.med@sofa.test','x'),(v_sec::uuid,'qa.ap.sec@sofa.test','x'),(v_otro::uuid,'qa.ap.otro@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ap.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA AP Consultorio', '00000000781', 'Médico independiente', 'activo', current_date - 90, '8095550781');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA AP Otro', '00000000782', 'Médico independiente', 'activo', current_date - 90, '8095550782');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. Avisos', 'Medicina Interna');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'), (v_org2, v_otro::uuid, 'client');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_prov, v_org, true, false);
    insert into public.clinical_settings (organization_id, mode) values (v_org, 'prueba');
    insert into public.patients (organization_id, full_name, doc_number, phone) values (v_org, 'Lucía Ficticia Avisos', '402-0000078-1', '8095550781') returning id into v_pat;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, phone, payer_type, status, patient_id)
    values (v_org, v_prov, current_date + 1, '08:30', 'Lucía Ficticia Avisos', '8095550781', 'privado', 'programada', v_pat) returning id into v_apt;
    insert into public.private_charges (organization_id, provider_id, charge_date, patient_name, patient_doc, procedure_id, service_name, quantity, unit_amount, payment_method, status)
    values (v_org, v_prov, current_date - 20, 'Lucía Ficticia Avisos', '40200000781', v_proc, 'Consulta', 1, 1800, 'pendiente', 'pendiente');
    -- Recordatorio de cita como lo genera la tarea nocturna (sin paciente ni enlace)
    insert into public.message_queue (organization_id, provider_id, kind, appointment_id, to_phone, subject, body, scheduled_for)
    values (v_org, v_prov, 'recordatorio_cita', v_apt, '8095550781', 'Recordatorio de cita', 'Hola Lucía, le recordamos su cita.', current_date + 1);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.patient_notice_settings_get(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-01 · Preferencias por defecto: enlace en los mensajes sí, pago automático no','ok',coalesce(((v_x->>'portal_in_messages')::boolean and not (v_x->>'balance_auto')::boolean and (v_x->>'can_edit')::boolean), false),'d',(v_x::text)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.patient_notice_settings_save(v_org, true, true, 1000, 15);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-02 · La Secretaria no cambia las preferencias','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-02 · La Secretaria no cambia las preferencias','ok',sqlerrm like 'Solo el Médico o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.patient_notice_settings_save(v_org, true, true, 1000, 3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-03 · Frecuencia fuera de rango: dice el rango','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-03 · Frecuencia fuera de rango: dice el rango','ok',sqlerrm like 'Repita el recordatorio de pago cada 7 a 90 días%','d',left(sqlerrm,120)));
    end;
    perform public.patient_notice_settings_save(v_org, true, true, 1000, 15);
    v_cnt := public.generate_balance_reminders(v_org);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-04 · Recordatorio de pago automático con la marca {enlace} y el paciente','ok',coalesce((v_cnt = 1 and exists (select 1 from public.message_queue where organization_id = v_org and kind = 'cobro_pendiente' and patient_id = v_pat and has_portal_link and body like '%{enlace}%' and body like '%1,800.00%')), false),'d',(v_cnt)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_cnt := public.generate_balance_reminders(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-05 · No repite el recordatorio de pago antes de 15 días','ok',coalesce((v_cnt = 0), false),'d',(v_cnt)::text));
    v_cnt := public.portal_enrich_messages(v_org);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-06 · El recordatorio de cita recibe el enlace y el paciente','ok',coalesce((v_cnt = 1 and exists (select 1 from public.message_queue where appointment_id = v_apt and patient_id = v_pat and has_portal_link and body like '%{enlace}%')), false),'d',(v_cnt)::text));
    select id into v_msg from public.message_queue where appointment_id = v_apt;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.message_portal_link(v_msg);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-07 · Sin permiso de WhatsApp la Secretaria no crea el enlace','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-07 · Sin permiso de WhatsApp la Secretaria no crea el enlace','ok',sqlerrm like 'Sin acceso para enviar este mensaje%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.capturer_scopes set can_whatsapp = true where user_id = v_sec::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_tok := public.message_portal_link(v_msg)->>'token';
    v_tok := public.message_portal_link(v_msg)->>'token';
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-08 · Al enviar se crea el enlace en ese momento (uno vigente; la clave no queda en el mensaje)','ok',coalesce((length(v_tok) >= 30 and (select count(*) from public.patient_portal_links where patient_id = v_pat and revoked_at is null) = 1 and not exists (select 1 from public.message_queue where body like '%' || v_tok || '%')), false),'d',(null)::text));
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    v_x := public.portal_view(v_tok);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-09 · El portal muestra la cita con su identificador','ok',coalesce(((v_x->'appointments'->0->>'id')::uuid = v_apt and not (v_x->'appointments'->0->>'change_requested')::boolean), false),'d',(v_x->>'appointments')::text));
    v_x := public.portal_appointment_action(v_tok, v_apt, 'confirmar');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-10 · El paciente confirma su cita desde el portal','ok',coalesce(((select status from public.appointments where id = v_apt) = 'confirmada'), false),'d',(v_x::text)::text));
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    begin
      perform public.portal_appointment_action(v_tok, v_apt, 'cambio_cita', '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-11 · Pedir cambio exige decir qué le conviene','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-11 · Pedir cambio exige decir qué le conviene','ok',sqlerrm like 'Escriba qué día u hora le conviene%','d',left(sqlerrm,120)));
    end;
    perform public.portal_appointment_action(v_tok, v_apt, 'cambio_cita', 'Mejor el jueves en la tarde');
    begin
      perform public.portal_appointment_action(v_tok, v_apt, 'cambio_cita', 'Otra vez');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-12 · No repite el pedido de cambio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-12 · No repite el pedido de cambio','ok',sqlerrm like 'Ya pidió un cambio%','d',left(sqlerrm,120)));
    end;
    v_x := public.portal_view(v_tok);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-13 · El portal muestra que el cambio está pedido','ok',coalesce(((v_x->'appointments'->0->>'change_requested')::boolean), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_x := public.portal_requests_list(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-14 · El consultorio ve el pedido con la nota del paciente','ok',coalesce((jsonb_array_length(v_x) = 1 and v_x->0->>'note' = 'Mejor el jueves en la tarde' and v_x->0->>'phone' = '8095550781'), false),'d',(v_x::text)::text));
    v_req := (v_x->0->>'id')::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-15 · Otro consultorio no ve los pedidos','ok',coalesce((jsonb_array_length(public.portal_requests_list(null)) = 0), false),'d',(null)::text));
    begin
      perform public.portal_request_done(v_req);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-16 · Otro consultorio no los marca','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-16 · Otro consultorio no los marca','ok',sqlerrm like 'Sin acceso a este pedido%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    perform public.portal_request_done(v_req, 'Se cambió al jueves 3:00 p. m.');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-17 · La Secretaria marca el pedido atendido','ok',coalesce((jsonb_array_length(public.portal_requests_list(v_org)) = 0 and jsonb_array_length(public.portal_requests_list(v_org, 'atendida')) = 2), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    perform public.patient_notice_settings_save(v_org, false, true, 1000, 15);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.message_portal_link(v_msg);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-18 · Si el médico quita el enlace, el mensaje sale sin enlace','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-18 · Si el médico quita el enlace, el mensaje sale sin enlace','ok',sqlerrm like 'El portal del paciente no está activo%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-19 · Sin sesión solo se ve el portal y se confirma o pide cambio','ok',coalesce((has_function_privilege('anon', 'public.portal_appointment_action(text,uuid,text,text)', 'execute') and not has_function_privilege('anon', 'public.message_portal_link(uuid)', 'execute') and not has_table_privilege('authenticated', 'public.patient_portal_requests', 'select')), false),'d',(null)::text));

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
