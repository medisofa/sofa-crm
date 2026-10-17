-- 073 · Suite de la 072 (permisos de la Secretaria). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_permisos_secretaria();
create or replace function app.qa_run_tests_permisos_secretaria()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_ok boolean; v_n int; v_x jsonb; v_ap uuid; v_mid uuid;
  v_orgA constant uuid := 'b9000000-0000-4000-8000-0000000000d1';
  v_orgB constant uuid := 'b9000000-0000-4000-8000-0000000000d2';
  v_pA constant uuid := 'c9000000-0000-4000-8000-0000000000d1';
  v_pB constant uuid := 'c9000000-0000-4000-8000-0000000000d2';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_admin constant text := 'a9000000-0000-4000-8000-0000000000d1';
  v_cliA constant text := 'a9000000-0000-4000-8000-0000000000d2';
  v_cliB constant text := 'a9000000-0000-4000-8000-0000000000d3';
  v_cap constant text := 'a9000000-0000-4000-8000-0000000000d4';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email) values (v_admin::uuid,'qa.ps.admin@sofa.test'), (v_cliA::uuid,'qa.ps.cliA@sofa.test'), (v_cliB::uuid,'qa.ps.cliB@sofa.test'), (v_cap::uuid,'qa.ps.cap@sofa.test');
    insert into public.profiles (id, full_name) select id, replace(email, '@sofa.test', '') from auth.users where email like 'qa.ps.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_orgA, 'client', v_op, 'QA PS A', '00000000131', 'Consultorio', 'activo', current_date - 90, '8095550001'),
      (v_orgB, 'client', v_op, 'QA PS B', '00000000132', 'Consultorio', 'activo', current_date - 90, '8295550002');
    update public.organizations set ecf_required_from = date '2099-12-31' where kind = 'client' and ecf_required_from is distinct from date '2099-12-31';
    insert into public.providers (id, organization_id, full_name) values (v_pA, v_orgA, 'Dr. PS A'), (v_pB, v_orgB, 'Dr. PS B');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (v_op, v_admin::uuid, 'admin'), (v_orgA, v_cliA::uuid, 'client'), (v_orgB, v_cliB::uuid, 'client'), (v_orgA, v_cap::uuid, 'capturer');
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.set_capturer_scope(v_cap::uuid, array[v_pA]::uuid[]);
    -- Cita de mañana con teléfono, creada por el Administrador, para generar un recordatorio
    v_ap := public.save_appointment(null, v_pA, current_date + 1, time '09:00', 'Paciente PS Uno', '00100000011', null, '8095551111', 'privado', null, null, 'Consulta', null);
    perform public.generate_appointment_reminders(1);
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-01 · Por defecto la Secretaria puede dar citas
    perform set_config('request.jwt.claims', json_build_object('sub',v_cap,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.save_appointment(null, v_pA, current_date + 2, time '10:00', 'Paciente PS Dos', '00100000012', null, '8095552222', 'privado', null, null, 'Consulta', null);
      v_ok := true;
    exception when others then v_ok := false; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Por defecto la Secretaria puede dar citas','ok',v_ok,'d',null));

    -- CT-02 · Por defecto la Secretaria NO ve los mensajes de WhatsApp
    select count(*) into v_n from public.message_queue where provider_id = v_pA;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Por defecto la Secretaria no ve los mensajes','ok',v_n = 0,'d',v_n || ' visibles'));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-03 · El médico ve a su secretaria con los permisos por defecto
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.list_assistants(v_pA);
    v_ok := jsonb_array_length(v_x) = 1 and (v_x->0->>'can_book')::boolean and not (v_x->0->>'can_whatsapp')::boolean;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · El médico lista a su secretaria: citas sí, WhatsApp no','ok',v_ok,'d',v_x::text));

    -- CT-04 · El médico activa WhatsApp y quita citas
    perform public.set_assistant_permissions(v_cap::uuid, v_pA, false, true);
    v_x := public.list_assistants(v_pA);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · El médico cambia los permisos y quedan guardados','ok',not (v_x->0->>'can_book')::boolean and (v_x->0->>'can_whatsapp')::boolean,'d',v_x::text));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-05 · Sin permiso de citas, la Secretaria no puede crear ni editar
    perform set_config('request.jwt.claims', json_build_object('sub',v_cap,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.save_appointment(null, v_pA, current_date + 2, time '11:00', 'Paciente PS Tres', '00100000013', null, '8095553333', 'privado', null, null, 'Consulta', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Sin permiso de citas se bloquea','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Sin permiso de citas se bloquea','ok',sqlerrm like 'El médico no le ha autorizado dar o cambiar citas%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    -- CT-06 · Con WhatsApp activado la Secretaria ve el recordatorio y lo puede marcar
    select count(*), min(id::text)::uuid into v_n, v_mid from public.message_queue where provider_id = v_pA and kind = 'recordatorio_cita';
    begin
      perform public.mark_message(v_mid, 'enviado'); v_ok := v_n = 1;
    exception when others then v_ok := false; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Con WhatsApp activado la Secretaria ve y marca el mensaje','ok',v_ok,'d',v_n || ' visibles'));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-07 · El médico apaga WhatsApp: ya no lo ve ni lo marca
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.set_assistant_permissions(v_cap::uuid, v_pA, true, false);
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claims', json_build_object('sub',v_cap,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    select count(*) into v_n from public.message_queue where provider_id = v_pA;
    begin
      perform public.mark_message(v_mid, 'omitido');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Con WhatsApp apagado no ve ni marca','ok',false,'d','Se permitió marcar'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Con WhatsApp apagado no ve ni marca','ok',v_n = 0 and sqlerrm like 'Sin acceso para marcar este mensaje%','d',v_n || ' visibles · ' || left(sqlerrm, 100)));
    end;

    -- CT-08 · La Secretaria no puede cambiarse los permisos ni ver la lista
    begin
      perform public.set_assistant_permissions(v_cap::uuid, v_pA, true, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · La Secretaria no cambia sus propios permisos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · La Secretaria no cambia sus propios permisos','ok',sqlerrm like 'Solo el médico o el Administrador%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-09 · Otro médico no puede tocar la secretaria de este
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.set_assistant_permissions(v_cap::uuid, v_pA, false, false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Un médico de otro cliente no cambia permisos ajenos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Un médico de otro cliente no cambia permisos ajenos','ok',sqlerrm like 'Solo el médico o el Administrador%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-10 · Secretaria no asignada a ese médico
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.set_assistant_permissions(v_cap::uuid, v_pB, true, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · No se dan permisos a una secretaria no asignada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · No se dan permisos a una secretaria no asignada','ok',sqlerrm like 'Esa secretaria no está asignada%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-11 · El médico y el Administrador conservan su acceso a citas
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.save_appointment(null, v_pA, current_date + 4, time '12:00', 'Paciente PS Cuatro', '00100000014', null, '8095554444', 'privado', null, null, 'Consulta', null);
      v_ok := true;
    exception when others then v_ok := false; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · El médico sigue pudiendo dar citas','ok',v_ok,'d',null));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-12 · anon sin acceso y search_path fijo
    v_ok := not has_function_privilege('anon', 'public.set_assistant_permissions(uuid,uuid,boolean,boolean)'::regprocedure, 'EXECUTE')
        and not has_function_privilege('anon', 'public.list_assistants(uuid)'::regprocedure, 'EXECUTE')
        and has_function_privilege('authenticated', 'app.capturer_can(uuid,text)'::regprocedure, 'EXECUTE')  -- la política de mensajes la necesita (084)
        and (select bool_and(coalesce(p.proconfig::text, '') like '%search_path%') from pg_proc p
              where p.oid in ('public.set_assistant_permissions(uuid,uuid,boolean,boolean)'::regprocedure, 'public.list_assistants(uuid)'::regprocedure,
                              'app.capturer_can(uuid,text)'::regprocedure, 'app.is_capturer_only(uuid)'::regprocedure, 'public.save_appointment(uuid,uuid,date,time,text,text,text,text,text,uuid,text,text,text)'::regprocedure));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · Sin acceso anónimo y con search_path fijo','ok',v_ok,'d',null));

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
