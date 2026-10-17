-- 069 · Suite de la 068 (resumen semanal y recordatorios). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_resumen_semanal();
create or replace function app.qa_run_tests_resumen_semanal()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_a jsonb; v_x jsonb; v_ok boolean; v_n int; v_n2 int; v_id uuid; v_ap1 uuid; v_ap2 uuid; v_ap3 uuid; v_ap4 uuid; v_msg text; v_k int;
  v_week date := date_trunc('week', current_date)::date;
  v_orgA constant uuid := 'b8000000-0000-4000-8000-0000000000c1';
  v_orgB constant uuid := 'b8000000-0000-4000-8000-0000000000c2';
  v_pA constant uuid := 'c8000000-0000-4000-8000-0000000000c1';
  v_pB constant uuid := 'c8000000-0000-4000-8000-0000000000c2';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_admin constant text := 'a8000000-0000-4000-8000-0000000000c1';
  v_fact constant text := 'a8000000-0000-4000-8000-0000000000c2';
  v_cliA constant text := 'a8000000-0000-4000-8000-0000000000c3';
  v_cliB constant text := 'a8000000-0000-4000-8000-0000000000c4';
  v_cap constant text := 'a8000000-0000-4000-8000-0000000000c5';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email) values (v_admin::uuid,'qa.rs.admin@sofa.test'), (v_fact::uuid,'qa.rs.fact@sofa.test'), (v_cliA::uuid,'qa.rs.cliA@sofa.test'), (v_cliB::uuid,'qa.rs.cliB@sofa.test'), (v_cap::uuid,'qa.rs.cap@sofa.test');
    insert into public.profiles (id, full_name) select id, replace(email, '@sofa.test', '') from auth.users where email like 'qa.rs.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_orgA, 'client', v_op, 'QA RS A', '00000000121', 'Centro médico', 'activo', current_date - 90, '8095550001'),
      (v_orgB, 'client', v_op, 'QA RS B', '00000000122', 'Consultorio',   'activo', current_date - 90, '8295550002');
    update public.organizations set ecf_required_from = date '2099-12-31' where kind = 'client' and ecf_required_from is distinct from date '2099-12-31';
    insert into public.providers (id, organization_id, full_name) values (v_pA, v_orgA, 'Dr. Médico RS A'), (v_pB, v_orgB, 'Dr. Médico RS B');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (v_op, v_admin::uuid, 'admin'), (v_op, v_fact::uuid, 'billing'), (v_orgA, v_cliA::uuid, 'client'), (v_orgB, v_cliB::uuid, 'client'), (v_orgA, v_cap::uuid, 'capturer');

    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.set_capturer_scope(v_cap::uuid, array[v_pA]::uuid[]);
    perform public.create_contract_tariff(v_pA, (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), 1200, v_week - 100, null, 'CT-RS');
    -- Reclamación de la semana pasada (entra en el resumen)
    v_a := public.capture_claim(v_pA, (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), v_week - 3, 'Paciente RS A', 'NSS-RS-1', 'AUT-RS-1', null, null, 1, 'ambulatorio');
    -- Citas del médico A: mañana con teléfono (genera), mañana sin teléfono, mañana cancelada, y dentro de 3 días con teléfono
    v_ap1 := public.save_appointment(null, v_pA, current_date + 1, time '09:30', 'Paciente Cita Uno', '00100000001', 'NSS-RS-C1', '(809) 555-1234', 'ars', (select id from public.ars where code='humano'), 'AUT-C1', 'Consulta', null);
    v_ap2 := public.save_appointment(null, v_pA, current_date + 1, time '10:30', 'Paciente Sin Telefono', '00100000002', null, null, 'privado', null, null, 'Consulta', null);
    v_ap3 := public.save_appointment(null, v_pA, current_date + 1, time '11:30', 'Paciente Cancelada', '00100000003', null, '8095559999', 'privado', null, null, 'Consulta', null);
    v_ap4 := public.save_appointment(null, v_pA, current_date + 3, time '08:00', 'Paciente En Tres Dias', '00100000004', null, '8095558888', 'privado', null, null, 'Consulta', null);
    perform public.set_appointment_status(v_ap3, 'cancelada', 'QA');
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-01 · Recordatorios de mañana: solo la cita con teléfono y no cancelada
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_n := public.generate_appointment_reminders(1);
    select count(*) into v_n2 from public.message_queue where kind = 'recordatorio_cita' and provider_id = v_pA;
    select body into v_msg from public.message_queue where kind = 'recordatorio_cita' and provider_id = v_pA limit 1;
    v_ok := v_n = 1 and v_n2 = 1 and v_msg like 'Hola Paciente Cita Uno%' and v_msg like '%09:30 AM%' and v_msg like '%carnet de la ARS%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Recordatorio solo para la cita de mañana con teléfono, sin canceladas','ok',v_ok,'d',v_n || ' · ' || coalesce(v_msg, 'sin mensaje')));

    -- CT-02 · Idempotente: correrlo otra vez no duplica
    v_n := public.generate_appointment_reminders(1);
    select count(*) into v_n2 from public.message_queue where kind = 'recordatorio_cita' and provider_id = v_pA;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Segunda corrida no duplica recordatorios','ok',v_n = 0 and v_n2 = 1,'d',v_n || ' nuevos, ' || v_n2 || ' en cola'));

    -- CT-03 · Días fuera de rango
    begin
      perform public.generate_appointment_reminders(9);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Anticipación fuera de 0 a 7 días se rechaza','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Anticipación fuera de 0 a 7 días se rechaza','ok',sqlerrm like 'Los días de anticipación%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    -- CT-04 · Resumen del médico A: la reclamación de la semana pasada cuenta y las citas de la próxima semana coinciden con la tabla
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.weekly_summary(v_pA, v_week);
    select count(*) into v_n from public.appointments where provider_id = v_pA and status <> 'cancelada' and appointment_date >= v_week and appointment_date < v_week + 7;
    v_ok := (v_x->'claims'->>'count')::int = 1 and (v_x->'claims'->>'claimed')::numeric = 1200 and (v_x->'next_week'->>'appointments')::int = v_n
            and (v_x->>'text') like 'Resumen de la semana del%Dr. Médico RS A%Reclamaciones capturadas: 1 por RD$ 1,200%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · El médico ve su resumen: 1 reclamación por RD$ 1,200 y las citas de la próxima semana','ok',v_ok,'d',v_x->>'text'));

    -- CT-05 · Otro médico no ve el resumen ajeno; Facturación y la secretaria tampoco
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    begin
      perform public.weekly_summary(v_pA, v_week);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05a · Otro cliente no ve el resumen ajeno','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05a · Otro cliente no ve el resumen ajeno','ok',sqlerrm like 'Sin acceso al resumen semanal%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub',v_fact,'role','authenticated')::text, true);
    begin
      perform public.weekly_summary(v_pA, v_week);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05b · Facturación no ve el resumen (trae cobros)','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05b · Facturación no ve el resumen (trae cobros)','ok',sqlerrm like 'Sin acceso al resumen semanal%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub',v_cap,'role','authenticated')::text, true);
    begin
      perform public.weekly_summary(v_pA, v_week);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05c · La secretaria no ve el resumen (trae cobros)','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05c · La secretaria no ve el resumen (trae cobros)','ok',sqlerrm like 'Sin acceso al resumen semanal%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    -- CT-06 · Generar los resúmenes: cola + notificación al usuario médico, sin duplicar
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    v_n := public.generate_weekly_summaries(v_week);
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    select count(*) into v_n2 from public.notifications where user_id = v_cliA::uuid and title like 'Resumen semanal%';
    v_ok := v_n >= 2 and v_n2 = 1 and exists (select 1 from public.message_queue where kind = 'resumen_semanal' and provider_id = v_pA and scheduled_for = v_week and to_phone = '8095550001');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Resúmenes: mensaje en cola con el WhatsApp del cliente y 1 notificación al médico','ok',v_ok,'d',v_n || ' resúmenes, ' || v_n2 || ' notificación(es)'));
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_n := public.generate_weekly_summaries(v_week);
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    select count(*) into v_n2 from public.notifications where user_id = v_cliA::uuid and title like 'Resumen semanal%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Segunda corrida de resúmenes no duplica nada','ok',v_n = 0 and v_n2 = 1,'d',v_n || ' nuevos, ' || v_n2 || ' notificación(es)'));

    -- CT-08 · Lectura de la cola según rol (RLS): el médico ve su resumen; el otro médico no ve los de A; la secretaria ve recordatorios pero no resúmenes
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    select count(*) into v_n from public.message_queue where provider_id = v_pA;
    perform set_config('request.jwt.claims', json_build_object('sub',v_cap,'role','authenticated')::text, true);
    select count(*) filter (where kind = 'recordatorio_cita'), count(*) filter (where kind = 'resumen_semanal') into v_n2, v_k from public.message_queue where provider_id = v_pA;
    v_ok := v_n = 0 and v_n2 = 1 and v_k = 0;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · RLS: otro cliente ve 0 de A; la secretaria ve 1 recordatorio y 0 resúmenes','ok',v_ok,'d','otro cliente: ' || v_n || ', secretaria: ' || v_n2 || ' recordatorio(s) y ' || v_k || ' resumen(es)'));

    -- CT-09 · La interfaz no escribe directo en la cola
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    begin
      update public.message_queue set status = 'enviado' where provider_id = v_pA;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Un usuario no actualiza la cola directo','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Un usuario no actualiza la cola directo','ok',sqlerrm like 'permission denied%' or sqlerrm like '%row-level security%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    -- CT-10 · La secretaria marca el recordatorio como enviado y queda quién y cuándo
    perform set_config('request.jwt.claims', json_build_object('sub',v_cap,'role','authenticated')::text, true);
    select id into v_id from public.message_queue where kind = 'recordatorio_cita' and provider_id = v_pA limit 1;
    perform public.mark_message(v_id, 'enviado');
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    v_ok := exists (select 1 from public.message_queue where id = v_id and status = 'enviado' and sent_by = v_cap::uuid and sent_at is not null);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · La secretaria marca enviado; queda quién y cuándo','ok',v_ok,'d',null));

    -- CT-11 · Otro cliente no marca mensajes ajenos; el estado inválido se rechaza
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.mark_message(v_id, 'omitido');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11a · Otro cliente no marca mensajes ajenos','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11a · Otro cliente no marca mensajes ajenos','ok',sqlerrm like 'Sin acceso para marcar%' or sqlerrm like 'El mensaje no existe%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    begin
      perform public.mark_message(v_id, 'borrado');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11b · Estado no válido se rechaza','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11b · Estado no válido se rechaza','ok',sqlerrm like 'Estado no válido%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-12 · anon no ejecuta ni lee nada de esto
    v_ok := not has_function_privilege('anon', 'public.weekly_summary(uuid,date)', 'EXECUTE')
        and not has_function_privilege('anon', 'public.generate_weekly_summaries(date)', 'EXECUTE')
        and not has_function_privilege('anon', 'public.generate_appointment_reminders(integer,uuid)', 'EXECUTE')
        and not has_function_privilege('anon', 'public.mark_message(uuid,text)', 'EXECUTE')
        and not has_table_privilege('anon', 'public.message_queue', 'SELECT')
        and not has_function_privilege('authenticated', 'app.weekly_summary_data(uuid,date)', 'EXECUTE');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · anon no ejecuta ni lee; la función interna está cerrada','ok',v_ok,'d',null));

    -- CT-13 · Tareas programadas registradas (si pg_cron está instalado)
    v_ok := not exists (select 1 from pg_extension where extname = 'pg_cron')
            or (select count(*) from cron.job where jobname in ('sofa_resumen_semanal', 'sofa_recordatorios_citas') and active) = 2;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-13 · Las dos tareas programadas existen y están activas','ok',v_ok,'d',null));

    -- CT-14 · search_path fijo en todas las funciones
    select coalesce(bool_and(exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')), false) into v_ok
      from pg_catalog.pg_proc p where p.oid in ('app.weekly_summary_data(uuid,date)'::regprocedure, 'app.weekly_summary_text(jsonb)'::regprocedure,
        'public.weekly_summary(uuid,date)'::regprocedure, 'public.generate_weekly_summaries(date)'::regprocedure,
        'public.generate_appointment_reminders(integer,uuid)'::regprocedure, 'public.mark_message(uuid,text)'::regprocedure);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14 · Las seis funciones tienen search_path fijo','ok',v_ok,'d',null));

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
