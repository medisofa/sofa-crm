-- 119 · Suite de la 118 (seguimiento automático de códigos ARS). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_seguimiento_codigos();
create or replace function app.qa_run_tests_seguimiento_codigos()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000002b1';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000002b1';
  v_med constant text := 'a7000000-0000-4000-8000-0000000002b1'; v_com constant text := 'a7000000-0000-4000-8000-0000000002b2';
  v_ars uuid; v_ars2 uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.sc.med@sofa.test','x'),(v_com::uuid,'qa.sc.com@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.sc.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA SC A', '00000000711', 'Médico independiente', 'activo', current_date - 90, '8095550711');
    insert into public.providers (id, organization_id, full_name, specialty, exequatur) values (v_prov, v_org, 'Dr. SC', 'Cardiología', 'EXQ-123');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_com::uuid, 'assistant');
    select id into v_ars from public.ars where is_active order by name limit 1;
    select id into v_ars2 from public.ars where is_active and id <> v_ars order by name limit 1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_com, 'role', 'authenticated')::text, true);
    perform public.set_ars_code_status(v_prov, v_ars, 'solicitado', null, 'SOL-QA-1', null, current_date - 45);
    perform public.set_ars_code_status(v_prov, v_ars2, 'solicitado', null, null, null, current_date - 5);
    v_x := public.ars_code_letter(v_prov, v_ars);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Datos de la carta de solicitud','ok',coalesce((v_x->'provider'->>'exequatur' = 'EXQ-123' and v_x->>'request_number' = 'SOL-QA-1' and v_x->'organization'->>'name' = 'QA SC A'), false),'d',(null)::text));
    v_x := public.ars_codes_followup(30, 7);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Crea 1 tarea solo para la solicitud de 45 días','ok',coalesce(((v_x->>'tasks_created')::int >= 1 and (select count(*) from public.tasks where organization_id = v_org and title like 'Seguimiento código%') = 1), false),'d',(v_x::text)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_com, 'role', 'authenticated')::text, true);
    v_x := public.ars_codes_followup(30, 7);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · No repite la tarea antes de 7 días','ok',coalesce(((select count(*) from public.tasks where organization_id = v_org and title like 'Seguimiento código%') = 1), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_com, 'role', 'authenticated')::text, true);
    v_x := public.ars_codes_board(30);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · El tablero lista el atrasado','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'overdue') o where o->>'client' = 'QA SC A' and (o->>'days')::int = 45)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.ars_codes_board(30);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · El médico no ve el tablero global','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · El médico no ve el tablero global','ok',sqlerrm like 'El tablero de códigos es para el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.ars_codes_followup();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El médico no genera recordatorios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El médico no genera recordatorios','ok',sqlerrm like 'Solo el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · «Trabajo de hoy» ya describe los estados nuevos','ok',coalesce((to_regprocedure('public.work_queue()') is null or position('pendiente_respuesta' in pg_get_functiondef('public.work_queue()'::regprocedure)) > 0), false),'d',(null)::text));

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
