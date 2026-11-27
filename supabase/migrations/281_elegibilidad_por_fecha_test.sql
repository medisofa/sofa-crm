-- PENDIENTE de aplicar en producción. No fusionar así.
-- 281 · Suite de la 280. Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_elegibilidad_fecha();
create or replace function app.qa_run_tests_elegibilidad_fecha()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql set search_path = '' as $function$
declare
  v_res jsonb := '[]'::jsonb; v_msg text; v_id uuid; v_ars uuid; v_ars2 uuid; v_a public.appointments; v_d date := current_date + 3;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_doc constant uuid := '28100000-0000-4000-8000-000000000001';
  v_org constant uuid := '28100000-0000-4000-8000-0000000000a1';
  v_p constant uuid := '28100000-0000-4000-8000-0000000000b1';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    select id into v_ars from public.ars order by id limit 1;
    select id into v_ars2 from public.ars where id <> v_ars order by id limit 1;
    insert into auth.users (id, email, encrypted_password) values (v_doc,'qa.ef.a@sofa.test','x');
    insert into public.profiles (id, full_name) values (v_doc,'qa.ef.a') on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', v_sofa, 'QA EF Clinica', '00000028101', 'Médico independiente', 'activo', current_date - 200, '8095552811');
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values (v_org, v_doc, 'client', true);
    insert into public.providers (id, organization_id, full_name, specialty, is_active, user_id) values (v_p, v_org, 'Dr. EF', 'Cardiología', true, v_doc);

    perform set_config('request.jwt.claims', json_build_object('sub', v_doc, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('role', 'authenticated', true);
    v_id := public.save_appointment(null, v_p, v_d, '09:00', 'Paciente EF', null, 'NSS1', null, 'ars', v_ars, 'AUT-1', null);
    perform public.set_eligibility(v_id, 'verificada', 'portal_ars', 'REF-123', current_date);

    perform public.save_appointment(v_id, v_p, v_d, '10:00', 'Paciente EF', null, 'NSS1', null, 'ars', v_ars, 'AUT-1', null);
    select * into v_a from public.appointments where id = v_id;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EF-01 · Cambiar solo la hora conserva la verificación','ok',coalesce(v_a.eligibility_status = 'verificada', false),'d',v_a.eligibility_status));

    perform public.save_appointment(v_id, v_p, v_d + 1, '10:00', 'Paciente EF', null, 'NSS1', null, 'ars', v_ars, 'AUT-1', null);
    select * into v_a from public.appointments where id = v_id;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EF-02 · Mover de día la anula','ok',coalesce(v_a.eligibility_status = 'no_verificada' and v_a.eligibility_reference is null and v_a.eligibility_checked_at is null, false),'d',v_a.eligibility_status));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EF-03 · La autorización y su fecha se conservan','ok',coalesce(v_a.authorization_number = 'AUT-1' and v_a.authorization_date = current_date, false),'d',coalesce(v_a.authorization_number,'sin autorización')));

    perform public.set_eligibility(v_id, 'verificada', 'portal_ars', 'REF-456', null);
    select * into v_a from public.appointments where id = v_id;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EF-04 · Se puede verificar de nuevo','ok',coalesce(v_a.eligibility_status = 'verificada', false),'d',v_a.eligibility_status));

    perform public.save_appointment(v_id, v_p, v_d + 1, '10:00', 'Paciente EF', null, 'NSS1', null, 'ars', v_ars2, 'AUT-1', null);
    select * into v_a from public.appointments where id = v_id;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EF-06 · Cambiar la ARS la anula','ok',coalesce(v_a.eligibility_status = 'no_verificada' and v_a.eligibility_reference is null, false),'d',v_a.eligibility_status));
    perform public.set_eligibility(v_id, 'verificada', 'portal_ars', 'REF-789', null);

    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    update public.appointments set status = 'atendida' where id = v_id;
    update public.appointments set appointment_date = v_d + 2, ars_id = v_ars where id = v_id;
    select * into v_a from public.appointments where id = v_id;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EF-05 · Una cita atendida conserva su registro','ok',coalesce(v_a.eligibility_status = 'verificada', false),'d',v_a.eligibility_status));
    raise exception 'qa_rollback';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    if v_msg <> 'qa_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error general de la suite','ok',false,'d',v_msg)); end if;
  end;
  return query select t.ord::int, case when (t.e->>'ok')::boolean then 'OK' else 'FALLA' end, t.e->>'p', t.e->>'d'
    from jsonb_array_elements(v_res) with ordinality as t(e, ord);
end $function$;
revoke all on function app.qa_run_tests_elegibilidad_fecha() from public, anon, authenticated;
delete from app.schema_migrations where version = '281';
insert into app.schema_migrations (version, report) values ('281', jsonb_build_object('tema', 'suite elegibilidad por fecha'));
