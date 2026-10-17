-- 099 · Suite de la 098 (analítica de glosas). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_analitica_glosas();
create or replace function app.qa_run_tests_analitica_glosas()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_ars uuid; v_proc uuid; v_a jsonb; v_b jsonb; v_lote uuid; v_g uuid; v_d date := date_trunc('month', current_date)::date;
  v_org constant uuid := 'b7000000-0000-4000-8000-000000000109';
  v_org2 constant uuid := 'b7000000-0000-4000-8000-00000000010a';
  v_prov constant uuid := 'c7000000-0000-4000-8000-000000000109';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_adm constant text := 'a7000000-0000-4000-8000-000000000109';
  v_cli constant text := 'a7000000-0000-4000-8000-00000000010a';
  v_otro constant text := 'a7000000-0000-4000-8000-00000000010b';
  v_fact constant text := 'a7000000-0000-4000-8000-00000000010c';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    select id into v_ars from public.ars where code = 'humano';
    select id into v_proc from public.procedures where internal_code = 'SOFA-P07';
    update public.app_settings set require_delivery_evidence = false where operator_id = v_op;
    insert into auth.users (id, email, encrypted_password) values (v_adm::uuid,'qa.gl.adm@sofa.test','x'),(v_cli::uuid,'qa.gl.cli@sofa.test','x'),
      (v_otro::uuid,'qa.gl.otro@sofa.test','x'),(v_fact::uuid,'qa.gl.fact@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.gl.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_org, 'client', v_op, 'QA GL A', '00000000241', 'Médico independiente', 'activo', current_date - 200, '8095550016'),
      (v_org2, 'client', v_op, 'QA GL B', '00000000242', 'Médico independiente', 'activo', current_date - 200, '8095550017');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. GL', 'Medicina General QA');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_op, v_adm::uuid, 'admin'), (v_org, v_cli::uuid, 'client'),
      (v_org2, v_otro::uuid, 'client'), (v_op, v_fact::uuid, 'billing');
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.create_contract_tariff(v_prov, v_ars, v_proc, 1000, v_d - 100, null, 'CT-GL');
    v_a := public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente GL A', 'NSS-GL-1', 'AUT-GL-1', null, null, 1, 'ambulatorio');
    v_b := public.capture_claim(v_prov, v_ars, v_proc, v_d, 'Paciente GL B', 'NSS-GL-2', 'AUT-GL-2', null, null, 1, 'ambulatorio');
    v_lote := (v_a->>'submission_id')::uuid;
    update public.submissions set ncf = 'B0100000901', invoice_date = current_date where id = v_lote;
    perform public.change_submission_status(v_lote, 'recibida');
    perform public.change_submission_status(v_lote, 'en_depuracion');
    perform public.change_submission_status(v_lote, 'lista_para_radicar', null, 'QA: lote de prueba autorizado por administración');
    update public.submissions set fiscal_invoice_number = 'F-B0100000901', accountant_name = 'Lic. QA', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_lote) where id = v_lote;
    perform public.change_submission_status(v_lote, 'radicada', null, null, current_date, 'R-GL-1', 'fisico', 'LOTE-GL-1');
    v_g := public.register_glosa(v_lote, current_date, jsonb_build_array(
      jsonb_build_object('service_line_id', v_a->>'id', 'amount', 600, 'reason_code', 'sin_autorizacion'),
      jsonb_build_object('service_line_id', v_b->>'id', 'amount', 400, 'reason_code', 'documentacion')));
    perform set_config('role', 'none', true);
    update public.glosa_items set recovered_amount = 300, accepted_amount = 100 where glosa_id = v_g and reason_code = 'sin_autorizacion';
    update public.glosas set auditor_name = 'Dra. Auditora QA' where id = v_g;

    -- CT-01 · El médico ve sus glosas
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.glosa_analytics(v_org, v_d, current_date);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Glosado 1,000; recuperado 300; aceptado 100','ok',(v_x->'totals'->>'glosado')::numeric = 1000 and (v_x->'totals'->>'recuperado')::numeric = 300 and (v_x->'totals'->>'aceptado')::numeric = 100,'d',(v_x->'totals')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · % de glosa sobre lo radicado = 50 %','ok',(v_x->'rates'->>'glosa_pct')::numeric = 50,'d',(v_x->'rates')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · % de recuperación = 300/(300+100) = 75 %','ok',(v_x->'rates'->>'recuperacion_pct')::numeric = 75,'d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Motivo principal: falta de autorización, con recomendación','ok',v_x->'by_reason'->0->>'code' = 'sin_autorizacion' and length(v_x->'by_reason'->0->>'tip') > 20,'d',(v_x->'by_reason')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Por ARS y por auditor','ok',jsonb_array_length(v_x->'by_ars') = 1 and v_x->'by_auditor'->0->>'auditor' = 'Dra. Auditora QA','d',(v_x->'by_auditor')::text));
    begin
      perform public.glosa_analytics(null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El médico no ve la analítica de todos los clientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El médico no ve la analítica de todos los clientes','ok',sqlerrm like 'Elija el cliente%','d',left(sqlerrm,110)));
    end;

    -- CT-07 · Otro médico y Facturación
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.glosa_analytics(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro médico no ve glosas ajenas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro médico no ve glosas ajenas','ok',sqlerrm like 'Sin acceso a las glosas%','d',left(sqlerrm,110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_fact, 'role', 'authenticated')::text, true);
    begin
      perform public.glosa_analytics(null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no ve la analítica global','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no ve la analítica global','ok',sqlerrm like 'Elija el cliente%','d',left(sqlerrm,110)));
    end;

    -- CT-09 · El Administrador ve todos
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.glosa_analytics(null, v_d, current_date);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · El Administrador ve la analítica global (incluye la glosa de prueba)','ok',(v_x->'totals'->>'glosado')::numeric >= 1000,'d',(v_x->'totals')::text));

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
