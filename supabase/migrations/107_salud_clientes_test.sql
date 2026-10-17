-- 107 · Suite de la 106 (salud de los clientes). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_salud_clientes();
create or replace function app.qa_run_tests_salud_clientes()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int;
  v_ars uuid; v_proc uuid;
  v_oA constant uuid := 'b7000000-0000-4000-8000-000000000129';
  v_oB constant uuid := 'b7000000-0000-4000-8000-00000000012a';
  v_oC constant uuid := 'b7000000-0000-4000-8000-00000000012b';
  v_pA constant uuid := 'c7000000-0000-4000-8000-000000000129';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_adm constant text := 'a7000000-0000-4000-8000-000000000129';
  v_fact constant text := 'a7000000-0000-4000-8000-00000000012a';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    select id into v_ars from public.ars where code = 'humano';
    select id into v_proc from public.procedures where internal_code = 'SOFA-P07';
    insert into auth.users (id, email, encrypted_password) values (v_adm::uuid,'qa.sc.adm@sofa.test','x'),(v_fact::uuid,'qa.sc.fact@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.sc.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_oA, 'client', v_op, 'QA SC Sano', '00000000261', 'Médico independiente', 'activo', current_date - 200, '8095550019'),
      (v_oB, 'client', v_op, 'QA SC Riesgo', '00000000262', 'Médico independiente', 'activo', current_date - 200, '8095550020'),
      (v_oC, 'client', v_op, 'QA SC Nuevo', '00000000263', 'Médico independiente', 'incorporacion', current_date - 10, '8095550021');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_pA, v_oA, 'Dr. SC', 'Medicina General QA');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_op, v_adm::uuid, 'admin'), (v_op, v_fact::uuid, 'billing');
    insert into public.sofa_invoices (organization_id, folio, period, issued_on, due_on, total, status)
      values (v_oB, 'QA-SC-1', date_trunc('month', current_date - 70)::date, current_date - 70, current_date - 40, 5000, 'emitida');
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.create_contract_tariff(v_pA, v_ars, v_proc, 1000, current_date - 100, null, 'CT-SC');
    perform public.capture_claim(v_pA, v_ars, v_proc, current_date - 1, 'Paciente SC A', 'NSS-SC-1', 'AUT-SC-1', null, null, 1, 'ambulatorio');
    perform public.capture_claim(v_pA, v_ars, v_proc, current_date - 1, 'Paciente SC B', 'NSS-SC-2', 'AUT-SC-2', null, null, 1, 'ambulatorio');

    v_x := public.client_health();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Cliente activo con actividad: verde (85, solo le resta no haber entrado)','ok',(select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oA)->>'level' = 'verde' and ((select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oA)->>'score')::int = 85,'d',(select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oA)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Cliente sin actividad, con deuda vencida de 40 días y sin accesos: rojo (25)','ok',(select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oB)->>'level' = 'rojo' and ((select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oB)->>'score')::int = 25,'d',(select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oB)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Los motivos del rojo están en español y mencionan la deuda','ok',exists (select 1 from jsonb_array_elements_text((select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oB)->'reasons') r where r like 'Debe RD$ 5,000.00 a SOFA con 40 días%'),'d',((select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oB)->'reasons')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · En incorporación no se penaliza la falta de actividad','ok',((select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oC)->>'score')::int = 85 and exists (select 1 from jsonb_array_elements_text((select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oC)->'reasons') r where r like 'En incorporación%'),'d',(select e from jsonb_array_elements(v_x) e where (e->>'id')::uuid = v_oC)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Ordenado del más débil al más sano','ok',(select (e->>'score')::int from jsonb_array_elements(v_x) e limit 1) <= (select min((e->>'score')::int) from jsonb_array_elements(v_x) e) ,'d',null));
    v_x := public.client_health(v_oA);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Filtrar por un cliente devuelve solo ese','ok',jsonb_array_length(v_x) = 1,'d',null));
    perform set_config('request.jwt.claims', json_build_object('sub', v_fact, 'role', 'authenticated')::text, true);
    begin
      perform public.client_health();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Facturación no ve la salud de clientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Facturación no ve la salud de clientes','ok',sqlerrm like 'Solo el personal de SOFA%','d',left(sqlerrm,110)));
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
