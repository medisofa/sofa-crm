-- 115 · Suite de la 114 (códigos ARS en 6 estados, tarifario y documentos del cliente). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_ficha_cliente();
create or replace function app.qa_run_tests_ficha_cliente()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_ars uuid; v_ars2 uuid; v_nars int; v_row jsonb; v_proc boolean;
  v_org  constant uuid := 'b7000000-0000-4000-8000-0000000001d1';
  v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000001d2';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000001d1';
  v_op   constant uuid := '00000000-0000-4000-8000-000000000001';
  v_med  constant text := 'a7000000-0000-4000-8000-0000000001d1';
  v_sec  constant text := 'a7000000-0000-4000-8000-0000000001d2';
  v_otro constant text := 'a7000000-0000-4000-8000-0000000001d3';
  v_com  constant text := 'a7000000-0000-4000-8000-0000000001d4';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    select id into v_ars from public.ars where is_active order by name limit 1;
    select id into v_ars2 from public.ars where is_active and id <> v_ars order by name limit 1;
    select count(*) into v_nars from public.ars where is_active;
    v_proc := exists (select 1 from public.procedures);
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.fc.med@sofa.test','x'),(v_sec::uuid,'qa.fc.sec@sofa.test','x'),
      (v_otro::uuid,'qa.fc.otro@sofa.test','x'),(v_com::uuid,'qa.fc.com@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.fc.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_org, 'client', v_op, 'QA FC A', '00000000601', 'Médico independiente', 'activo', current_date - 90, '8095550061'),
      (v_org2, 'client', v_op, 'QA FC B', '00000000602', 'Médico independiente', 'activo', current_date - 90, '8095550062');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. FC', 'Pediatría');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'),
      (v_org2, v_otro::uuid, 'client'), (v_op, v_com::uuid, 'assistant');
    perform set_config('role', 'authenticated', true);

    -- CT-01 · Matriz con todas las ARS
    perform set_config('request.jwt.claims', json_build_object('sub', v_com, 'role', 'authenticated')::text, true);
    v_x := public.client_ars_matrix(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · La ficha muestra todas las ARS activas del prestador','ok',
      jsonb_array_length(v_x->'providers'->0->'rows') = v_nars and (v_x->'providers'->0->'rows'->0->>'status') = 'sin_codigo','d',v_nars::text || ' ARS'));

    -- CT-02..05 · Comercial avanza los estados
    perform public.set_ars_code_status(v_prov, v_ars, 'en_preparacion', null, null, 'Reuniendo exequátur');
    perform public.set_ars_code_status(v_prov, v_ars, 'solicitado', null, 'SOL-123', null, current_date - 40);
    v_x := public.client_ars_matrix(v_org);
    select r into v_row from jsonb_array_elements(v_x->'providers'->0->'rows') r where r->>'ars_id' = v_ars::text;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Solicitado con número y alerta a los 40 días','ok',
      v_row->>'status' = 'solicitado' and v_row->>'request_number' = 'SOL-123' and (v_row->>'alert')::boolean,'d',v_row::text));
    begin
      perform public.set_ars_code_status(v_prov, v_ars, 'codificado');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Codificado exige el código','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Codificado exige el código','ok',sqlerrm like 'Escriba el código%','d',left(sqlerrm,100)));
    end;
    begin
      perform public.set_ars_code_status(v_prov, v_ars2, 'rechazado');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Rechazado exige el motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Rechazado exige el motivo','ok',sqlerrm like 'Escriba el motivo del rechazo%','d',left(sqlerrm,100)));
    end;
    -- CT-05 · El Médico marca la respuesta y el código
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    perform public.set_ars_code_status(v_prov, v_ars, 'pendiente_respuesta', null, null, 'La ARS pidió esperar');
    perform public.set_ars_code_status(v_prov, v_ars, 'codificado', 'PSS-99887');
    v_x := public.client_ars_matrix(v_org);
    select r into v_row from jsonb_array_elements(v_x->'providers'->0->'rows') r where r->>'ars_id' = v_ars::text;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · El Médico registra el código asignado','ok',
      v_row->>'status' = 'codificado' and v_row->>'code' = 'PSS-99887' and not (v_row->>'alert')::boolean and v_row->>'granted_on' is not null,'d',v_row::text));
    v_x := public.ars_code_history(v_prov, v_ars);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El historial guarda los 4 cambios','ok',jsonb_array_length(v_x) = 4,'d',jsonb_array_length(v_x)::text));

    -- CT-07/08 · Secretaria y otro médico no actualizan
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.set_ars_code_status(v_prov, v_ars2, 'solicitado');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · La Secretaria no actualiza códigos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · La Secretaria no actualiza códigos','ok',sqlerrm like 'Su rol no puede actualizar%','d',left(sqlerrm,100)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.client_ars_matrix(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Otro médico no ve la ficha ajena','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Otro médico no ve la ficha ajena','ok',sqlerrm like 'Sin acceso a este cliente%','d',left(sqlerrm,100)));
    end;

    -- CT-09 · Tarifario y documentos
    perform set_config('role', 'none', true);
    insert into public.tariffs (ars_id, organization_id, procedure_id, amount, valid_during, contract_ref, provider_id)
    select v_ars, v_org, id, 1000, daterange(current_date - 10, current_date + 300), 'CT-QA-1', v_prov from public.procedures limit 1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.client_tariff_summary(v_org);
    select r into v_row from jsonb_array_elements(v_x) r where r->>'ars_id' = v_ars::text;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Tarifario por ARS: negociadas, contrato y código','ok',
      (v_row->>'negotiated')::int >= case when v_proc then 1 else 0 end and (v_row->>'codes')::int = 1,'d',v_row::text));
    v_x := public.client_documents(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Documentos del cliente responde','ok',v_x ? 'files' and v_x ? 'commercial','d',null));

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
