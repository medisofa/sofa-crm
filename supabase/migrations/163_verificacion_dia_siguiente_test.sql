-- 163 · Suite de la 162 (verificación de elegibilidad y autorización del día siguiente). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_verificacion_manana();
create or replace function app.qa_run_tests_verificacion_manana()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01630000-0000-4000-8000-000000000001'; v_prov constant uuid := '01630000-0000-4000-8000-000000000003'; v_prov2 constant uuid := '01630000-0000-4000-8000-000000000004';
  v_med constant text := '01630000-0000-4000-8000-000000000011'; v_sec constant text := '01630000-0000-4000-8000-000000000012'; v_sec2 constant text := '01630000-0000-4000-8000-000000000013';
  v_ars uuid; v_a1 uuid; v_a2 uuid; v_d date; v_cnt int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.vm.med@sofa.test','x'),(v_sec::uuid,'qa.vm.sec@sofa.test','x'),(v_sec2::uuid,'qa.vm.sec2@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.vm.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA VM Consultorio', '00000000901', 'Médico independiente', 'activo', current_date - 90, '8095550901');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. Mañana', 'Medicina Familiar'), (v_prov2, v_org, 'Dr. Otro VM', 'Cardiología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'), (v_org, v_sec2::uuid, 'capturer');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_prov, v_org, true, false), (v_sec2::uuid, v_prov2, v_org, true, false);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_vm_ars', 'QA ARS Mañana', 'Contributivo', true) returning id into v_ars;
    v_d := current_date + case when extract(isodow from current_date) = 6 then 2 else 1 end;
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, phone, payer_type, ars_id, member_number, status)
    values (v_org, v_prov, v_d, '09:00', 'Paciente Sin Verificar', '8095551111', 'ars', v_ars, '123456', 'programada') returning id into v_a1;
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type, ars_id, status)
    values (v_org, v_prov2, v_d, '10:00', 'Paciente Del Otro', 'ars', v_ars, 'programada') returning id into v_a2;
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type, status)
    values (v_org, v_prov, v_d, '11:00', 'Paciente Privado', 'privado', 'programada');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_x := public.next_day_checklist(null, null);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-01 · La Secretaria ve solo las citas ARS de mañana de su médico, con lo que falta','ok',coalesce((jsonb_array_length(v_x->'items') = 1 and v_x->'items'->0->>'patient' = 'Paciente Sin Verificar' and v_x->'items'->0->'needs' ? 'elegibilidad' and v_x->'items'->0->'needs' ? 'autorizacion'), false),'d',(v_x::text)::text));
    begin
      perform public.next_day_checklist(current_date + 30);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-02 · Fecha fuera de rango: dice el rango','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-02 · Fecha fuera de rango: dice el rango','ok',sqlerrm like 'Elija una fecha entre ayer%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.set_appointment_authorization(v_a1, '1');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-03 · Autorización muy corta: pide el número','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-03 · Autorización muy corta: pide el número','ok',sqlerrm like 'Escriba el número de autorización%','d',left(sqlerrm,120)));
    end;
    perform public.set_appointment_authorization(v_a1, 'AUT-778899');
    perform public.set_eligibility(v_a1, 'verificada', 'portal_ars', 'CONF-123');
    v_x := public.next_day_checklist(null, null);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-04 · Verificada y con autorización: ya no falta nada','ok',coalesce((jsonb_array_length(v_x->'items'->0->'needs') = 0 and (v_x->>'pending')::int = 0), false),'d',(v_x->>'items')::text));
    begin
      perform public.set_appointment_authorization(v_a2, 'AUT-1234');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-05 · La Secretaria no toca citas de otro médico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-05 · La Secretaria no toca citas de otro médico','ok',sqlerrm like 'Sin acceso a la agenda%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.next_day_checklist(null, null);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-06 · El Médico ve las de sus dos médicos (1 pendiente)','ok',coalesce((jsonb_array_length(v_x->'items') = 2 and (v_x->>'pending')::int = 1), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_cnt := app.next_day_reminders();
    v_cnt := app.next_day_reminders();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-07 · Aviso al Médico y a la Secretaria del médico con pendientes (una vez al día)','ok',coalesce(((select count(*) from public.notifications where user_id = v_med::uuid and link = '#/verificacion') = 1 and (select count(*) from public.notifications where user_id = v_sec2::uuid and link = '#/verificacion') = 1 and not exists (select 1 from public.notifications where user_id = v_sec::uuid and link = '#/verificacion')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','VM-08 · Sin sesión no se usa','ok',coalesce((not has_function_privilege('anon', 'public.next_day_checklist(date,uuid)', 'execute')), false),'d',(null)::text));

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
