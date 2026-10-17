-- 097 · Suite de la 096 (indicadores de agenda). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_indicadores_agenda();
create or replace function app.qa_run_tests_indicadores_agenda()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_d1 date := date_trunc('month', current_date)::date;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000000f9';
  v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000000fa';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000000f9';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_cli constant text := 'a7000000-0000-4000-8000-0000000000f9';
  v_otro constant text := 'a7000000-0000-4000-8000-0000000000fa';
  v_p1 constant uuid := 'e7000000-0000-4000-8000-0000000000f1';
  v_p2 constant uuid := 'e7000000-0000-4000-8000-0000000000f2';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_cli::uuid,'qa.ag.cli@sofa.test','x'),(v_otro::uuid,'qa.ag.otro@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ag.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_org, 'client', v_op, 'QA AG A', '00000000231', 'Médico independiente', 'activo', current_date - 400, '8095550014'),
      (v_org2, 'client', v_op, 'QA AG B', '00000000232', 'Médico independiente', 'activo', current_date - 400, '8095550015');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. AG', 'Cardiología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_cli::uuid, 'client'), (v_org2, v_otro::uuid, 'client');
    insert into public.patients (id, organization_id, full_name, doc_number) values (v_p1, v_org, 'Paciente AG Viejo', '00100000231'), (v_p2, v_org, 'Paciente AG Nuevo', '00100000232');
    -- P1 ya vino antes del período (recurrente); P2 viene por primera vez en el período (nuevo)
    insert into public.appointments (organization_id, provider_id, patient_id, appointment_date, appointment_time, patient_name, phone, payer_type, status, reason) values
      (v_org, v_prov, v_p1, v_d1 - 60, '09:00', 'Paciente AG Viejo', '8095550401', 'privado', 'atendida', 'Control'),
      (v_org, v_prov, v_p1, v_d1, '09:00', 'Paciente AG Viejo', '8095550401', 'privado', 'atendida', 'Control'),
      (v_org, v_prov, v_p2, v_d1, '10:00', 'Paciente AG Nuevo', '8095550402', 'privado', 'atendida', 'Primera vez'),
      (v_org, v_prov, null, v_d1, '11:00', 'Paciente AG Faltó', '8095550403', 'privado', 'no_asistio', 'Control'),
      (v_org, v_prov, null, v_d1, '15:00', 'Paciente AG Canceló', '8095550404', 'privado', 'cancelada', 'Control');

    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.agenda_indicators(v_prov, v_d1, v_d1);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Totales: 4 citas, 2 atendidas, 1 no asistió, 1 cancelada','ok',(v_x->'totals'->>'citas')::int = 4 and (v_x->'totals'->>'atendidas')::int = 2 and (v_x->'totals'->>'no_asistio')::int = 1 and (v_x->'totals'->>'canceladas')::int = 1,'d',(v_x->'totals')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Inasistencia = 1 de 3 = 33.3 %','ok',(v_x->'rates'->>'inasistencia_pct')::numeric = 33.3,'d',(v_x->'rates')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Pacientes: 2 atendidos, 1 nuevo y 1 recurrente','ok',(v_x->'patients'->>'nuevos')::int = 1 and (v_x->'patients'->>'recurrentes')::int = 1,'d',(v_x->'patients')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Motivo más frecuente: Control (sin contar la cancelada)','ok',v_x->'top_reasons'->0->>'reason' = 'Control' and (v_x->'top_reasons'->0->>'citas')::int = 2,'d',(v_x->'top_reasons')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Por hora no cuenta la cancelada (3 horas)','ok',jsonb_array_length(v_x->'by_hour') = 3,'d',(v_x->'by_hour')::text));
    begin
      perform public.agenda_indicators(v_prov, v_d1, v_d1 - 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Período invertido se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Período invertido se rechaza','ok',sqlerrm like 'Revise el período%','d',left(sqlerrm,110)));
    end;
    begin
      perform public.agenda_indicators(v_prov, v_d1 - 400, v_d1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Más de un año se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Más de un año se rechaza','ok',sqlerrm like 'El período no puede pasar de un año%','d',left(sqlerrm,110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.agenda_indicators(v_prov);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Otro médico no ve la agenda','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Otro médico no ve la agenda','ok',sqlerrm like 'Sin acceso a la agenda%','d',left(sqlerrm,110)));
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
