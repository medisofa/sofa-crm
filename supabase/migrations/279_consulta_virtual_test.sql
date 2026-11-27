-- PENDIENTE de aplicar en producción. No fusionar así.
-- 279 · Suite de la 278 (consulta virtual). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_consulta_virtual();
create or replace function app.qa_run_tests_consulta_virtual()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql set search_path = '' as $function$
declare
  v_res jsonb := '[]'::jsonb; v_msg text; v_t text; v_n int; v_id uuid; v_a public.appointments; v_x jsonb; v_d date := current_date + 3;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_doc constant uuid := '27900000-0000-4000-8000-000000000001';
  v_otro constant uuid := '27900000-0000-4000-8000-000000000002';
  v_org constant uuid := '27900000-0000-4000-8000-0000000000a1';
  v_p constant uuid := '27900000-0000-4000-8000-0000000000b1';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_doc,'qa.cv.a@sofa.test','x'), (v_otro,'qa.cv.b@sofa.test','x');
    insert into public.profiles (id, full_name) values (v_doc,'qa.cv.a'), (v_otro,'qa.cv.b') on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', v_sofa, 'QA CV Clinica', '00000027901', 'Médico independiente', 'activo', current_date - 200, '8095552791');
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values (v_org, v_doc, 'client', true);
    insert into public.providers (id, organization_id, full_name, specialty, is_active, user_id) values (v_p, v_org, 'Dr. CV', 'Cardiología', true, v_doc);

    perform set_config('request.jwt.claims', json_build_object('sub', v_doc, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('role', 'authenticated', true);
    v_id := public.save_appointment_modality(null, v_p, v_d, '09:00', 'Paciente CV', null, null, null, 'privado', null, null, null, null, null, 30, 'virtual', 'https://meet.example.com/qa');
    select * into v_a from public.appointments where id = v_id;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CV-01 · Se agenda una consulta virtual con enlace','ok',coalesce(v_a.modality = 'virtual' and v_a.virtual_link = 'https://meet.example.com/qa', false),'d',v_a.modality));
    v_x := public.agenda_week(v_p, null, v_d, 1);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CV-02 · La semana trae modalidad y enlace','ok',coalesce(v_x#>>'{appointments,0,modality}' = 'virtual' and v_x#>>'{appointments,0,virtual_link}' is not null, false),'d',coalesce(v_x#>>'{appointments,0,modality}','sin cita')));
    perform public.save_appointment_modality(v_id, v_p, v_d, '09:00', 'Paciente CV', null, null, null, 'privado', null, null, null, null, null, 30, 'presencial', 'https://meet.example.com/qa');
    select * into v_a from public.appointments where id = v_id;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CV-03 · Al pasarla a presencial se quita el enlace','ok',coalesce(v_a.modality = 'presencial' and v_a.virtual_link is null, false),'d',coalesce(v_a.virtual_link,'sin enlace')));
    v_t := 'sin error';
    begin perform public.save_appointment_modality(null, v_p, v_d, '11:00', 'Paciente Malo', null, null, null, 'privado', null, null, null, null, null, 30, 'virtual', 'javascript:alert(1)'); exception when others then v_t := sqlstate; end;
    select count(*) into v_n from public.appointments where provider_id = v_p;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CV-04 · Un enlace que no es https se rechaza y no crea la cita','ok',v_t = '22023' and v_n = 1,'d',format('%s, %s cita(s)', v_t, v_n)));
    v_id := public.save_appointment(null, v_p, v_d, '10:00', 'Paciente Normal', null, null, null, 'privado', null, null, null);
    select * into v_a from public.appointments where id = v_id;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CV-05 · La forma anterior de agendar sigue creando presenciales','ok',coalesce(v_a.modality = 'presencial', false),'d',v_a.modality));

    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_t := 'sin error';
    begin perform public.save_appointment_modality(v_id, v_p, v_d, '10:00', 'Intruso', null, null, null, 'privado', null, null, null, null, null, 30, 'virtual', null); exception when others then v_t := sqlstate; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CV-06 · Un usuario sin acceso no puede cambiarla','ok',v_t = '42501','d',v_t));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CV-07 · Sin sesión no se puede ejecutar','ok',not has_function_privilege('anon','public.save_appointment_modality(uuid,uuid,date,time,text,text,text,text,text,uuid,text,text,text,uuid,integer,text,text)','execute'),'d','anon'));
    raise exception 'qa_rollback';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    if v_msg <> 'qa_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error general de la suite','ok',false,'d',v_msg)); end if;
  end;
  return query select t.ord::int, case when (t.e->>'ok')::boolean then 'OK' else 'FALLA' end, t.e->>'p', t.e->>'d'
    from jsonb_array_elements(v_res) with ordinality as t(e, ord);
end $function$;
revoke all on function app.qa_run_tests_consulta_virtual() from public, anon, authenticated;
delete from app.schema_migrations where version = '279';
insert into app.schema_migrations (version, report) values ('279', jsonb_build_object('tema', 'suite consulta virtual'));
