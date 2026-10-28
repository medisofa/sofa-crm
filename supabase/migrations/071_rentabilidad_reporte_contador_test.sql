-- 071 · Suite de la 070 (rentabilidad y reporte para el contador). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_rentabilidad();
create or replace function app.qa_run_tests_rentabilidad()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_a jsonb; v_x jsonb; v_ok boolean; v_lote uuid; v_proc2 uuid; v_from date; v_pay_date date; v_msg text;
  v_orgA constant uuid := 'b8000000-0000-4000-8000-0000000000d1';
  v_orgB constant uuid := 'b8000000-0000-4000-8000-0000000000d2';
  v_pA constant uuid := 'c8000000-0000-4000-8000-0000000000d1';
  v_pB constant uuid := 'c8000000-0000-4000-8000-0000000000d2';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_admin constant text := 'a8000000-0000-4000-8000-0000000000d1';
  v_fact constant text := 'a8000000-0000-4000-8000-0000000000d2';
  v_cliA constant text := 'a8000000-0000-4000-8000-0000000000d3';
  v_cliB constant text := 'a8000000-0000-4000-8000-0000000000d4';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    v_from := (date_trunc('month', current_date) - interval '1 month')::date;
    insert into auth.users (id, email) values (v_admin::uuid,'qa.rt.admin@sofa.test'), (v_fact::uuid,'qa.rt.fact@sofa.test'), (v_cliA::uuid,'qa.rt.cliA@sofa.test'), (v_cliB::uuid,'qa.rt.cliB@sofa.test');
    insert into public.profiles (id, full_name) select id, replace(email, '@sofa.test', '') from auth.users where email like 'qa.rt.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on) values
      (v_orgA, 'client', v_op, 'QA RT A', '00000000131', 'Centro médico', 'activo', current_date - 120),
      (v_orgB, 'client', v_op, 'QA RT B', '00000000132', 'Consultorio',   'activo', current_date - 120);
    update public.organizations set ecf_required_from = date '2099-12-31' where kind = 'client' and ecf_required_from is distinct from date '2099-12-31';
    -- La configuración de producción puede exigir evidencia de entrega para radicar; dentro de la prueba se desactiva (se deshace sola)
    update public.app_settings set require_delivery_evidence = false where operator_id = v_op;
    insert into public.providers (id, organization_id, full_name) values (v_pA, v_orgA, 'Dr. Médico RT A'), (v_pB, v_orgB, 'Dr. Médico RT B');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (v_op, v_admin::uuid, 'admin'), (v_op, v_fact::uuid, 'billing'), (v_orgA, v_cliA::uuid, 'client'), (v_orgB, v_cliB::uuid, 'client');
    select id into v_proc2 from public.procedures where internal_code <> 'SOFA-P07' and is_active order by internal_code limit 1;

    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.create_contract_tariff(v_pA, (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), 1200, v_from - 100, null, 'CT-RT');
    perform public.create_contract_tariff(v_pA, (select id from public.ars where code='humano'), v_proc2, 800, v_from - 100, null, 'CT-RT2');
    v_a := public.capture_claim(v_pA, (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), v_from, 'Paciente RT 1', 'NSS-RT-1', 'AUT-RT-1', null, null, 1, 'ambulatorio');
    perform public.capture_claim(v_pA, (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), v_from, 'Paciente RT 2', 'NSS-RT-2', 'AUT-RT-2', null, null, 1, 'ambulatorio');
    perform public.capture_claim(v_pA, (select id from public.ars where code='humano'), v_proc2, v_from, 'Paciente RT 3', 'NSS-RT-3', 'AUT-RT-3', null, null, 1, 'ambulatorio');
    v_lote := (v_a->>'submission_id')::uuid;
    update public.submissions set ncf = 'B0100001001', invoice_date = current_date where id = v_lote;
    perform public.change_submission_status(v_lote, 'recibida');
    perform public.change_submission_status(v_lote, 'en_depuracion');
    perform public.change_submission_status(v_lote, 'lista_para_radicar', null, 'QA: lote de prueba autorizado por administración');
    update public.submissions set fiscal_invoice_number = 'F-RT-1', accountant_name = 'Lic. QA', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_lote) where id = v_lote;
    perform public.change_submission_status(v_lote, 'radicada', null, null, current_date - 20, 'R-RT-1', 'fisico', 'LOTE-RT-1');
    v_pay_date := current_date - 8;
    perform public.register_payment(v_orgA, (select id from public.ars where code='humano'), v_pay_date, 2000, 'transferencia', 'TRF-RT-1', jsonb_build_array(jsonb_build_object('submission_id', v_lote, 'amount', 2000)));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-01 · Por ARS: una fila con lo reclamado, lo cobrado y los días de cobro
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.profitability(v_orgA, v_from, current_date, 'ars');
    v_ok := jsonb_array_length(v_x->'rows') = 1 and v_x->'rows'->0->>'ars' = 'ARS Humano' and (v_x->'rows'->0->>'lines')::int = 3
            and (v_x->'rows'->0->>'claimed')::numeric = 3200 and (v_x->'rows'->0->>'paid')::numeric = 2000 and (v_x->'rows'->0->>'pending')::numeric = 1200
            and (v_x->'rows'->0->>'collected_pct')::numeric = 62.5 and (v_x->'rows'->0->>'avg_days_to_pay')::numeric = 12;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Por ARS: 3 reclamaciones, RD$ 3,200 reclamados, 2,000 cobrados, 62.5 %, 12 días','ok',v_ok,'d',(v_x->'rows')::text));

    -- CT-02 · Por procedimiento: dos filas que suman lo mismo
    v_x := public.profitability(v_orgA, v_from, current_date, 'procedimiento');
    v_ok := jsonb_array_length(v_x->'rows') = 2 and (select sum((e->>'claimed')::numeric) from jsonb_array_elements(v_x->'rows') e) = 3200
            and exists (select 1 from jsonb_array_elements(v_x->'rows') e where e->>'procedure' like 'SOFA-P07%' and (e->>'claimed')::numeric = 2400 and (e->>'lines')::int = 2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Por procedimiento: 2 filas, SOFA-P07 con 2 reclamaciones por RD$ 2,400','ok',v_ok,'d',(select string_agg(e->>'procedure' || '=' || (e->>'claimed'), ' · ') from jsonb_array_elements(v_x->'rows') e)));

    -- CT-03 · ARS y procedimiento a la vez
    v_x := public.profitability(v_orgA, v_from, current_date, 'ars_procedimiento');
    v_ok := jsonb_array_length(v_x->'rows') = 2 and not exists (select 1 from jsonb_array_elements(v_x->'rows') e where e->>'ars' is null or e->>'procedure' is null);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · ARS por procedimiento: 2 filas con ambas columnas','ok',v_ok,'d',null));

    -- CT-04 · Totales sin glosas
    v_ok := (v_x->'totals'->>'claimed')::numeric = 3200 and (v_x->'totals'->>'paid')::numeric = 2000 and (v_x->'totals'->>'glosa_rate_pct')::numeric = 0 and (v_x->'totals'->>'lines')::int = 3;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Totales: 3,200 reclamado, 2,000 cobrado, 0 % de glosa','ok',v_ok,'d',(v_x->'totals')::text));

    -- CT-05 · Parámetros inválidos
    begin
      perform public.profitability(v_orgA, v_from, current_date, 'medico');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05a · Agrupación no válida se rechaza','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05a · Agrupación no válida se rechaza','ok',sqlerrm like 'Agrupación no válida%','d','Bloqueado: ' || left(sqlerrm, 100)));
    end;
    begin
      perform public.profitability(v_orgA, current_date, v_from, 'ars');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05b · Fecha inicial posterior a la final se rechaza','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05b · Fecha inicial posterior a la final se rechaza','ok',sqlerrm like 'El rango de fechas no es válido%','d','Bloqueado: ' || left(sqlerrm, 100)));
    end;
    begin
      perform public.profitability(v_orgA, current_date - 800, current_date, 'ars');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05c · Rango de más de 24 meses se rechaza','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05c · Rango de más de 24 meses se rechaza','ok',sqlerrm like 'El rango no puede pasar%','d','Bloqueado: ' || left(sqlerrm, 100)));
    end;

    -- CT-06 · Permisos de la rentabilidad: el médico la ve; otro cliente y Facturación no
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    begin
      v_x := public.profitability(v_orgA, v_from, current_date, 'ars');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06a · El médico ve su rentabilidad','ok',(v_x->'totals'->>'claimed')::numeric = 3200,'d',null));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06a · El médico ve su rentabilidad','ok',false,'d',left(sqlerrm, 150)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    begin
      perform public.profitability(v_orgA, v_from, current_date, 'ars');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06b · Otro cliente no ve la rentabilidad ajena','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06b · Otro cliente no ve la rentabilidad ajena','ok',sqlerrm like 'Sin acceso a la rentabilidad%','d','Bloqueado: ' || left(sqlerrm, 100)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub',v_fact,'role','authenticated')::text, true);
    begin
      perform public.profitability(v_orgA, v_from, current_date, 'ars');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06c · Facturación no ve la rentabilidad (trae cobros)','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06c · Facturación no ve la rentabilidad (trae cobros)','ok',sqlerrm like 'Sin acceso a la rentabilidad%','d','Bloqueado: ' || left(sqlerrm, 100)));
    end;

    -- CT-07 · Reporte del contador del mes del pago
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    v_x := public.accountant_report(v_orgA, date_trunc('month', v_pay_date)::date);
    v_ok := jsonb_array_length(v_x->'ars_payments') = 1 and (v_x->>'ars_total')::numeric = 2000 and v_x->'ars_payments'->0->>'reference' = 'TRF-RT-1'
            and (v_x->'ars_payments'->0->>'paid_on')::date = v_pay_date and (v_x->'summary'->>'income_total')::numeric = 2000 and (v_x->>'glosas_accepted_total')::numeric = 0;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Reporte del contador: 1 pago de RD$ 2,000 con su referencia','ok',v_ok,'d',(v_x->'summary')::text));

    -- CT-08 · El reporte no lleva nombres de pacientes
    v_msg := v_x::text;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · El reporte del contador no incluye nombres de pacientes','ok',v_msg not like '%Paciente RT%' and v_msg not like '%NSS-RT%','d',null));

    -- CT-09 · Permisos del reporte: el médico lo ve; otro cliente y Facturación no
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    begin
      v_x := public.accountant_report(v_orgA, v_pay_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09a · El médico ve su reporte del contador','ok',(v_x->>'ars_total')::numeric = 2000,'d',null));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09a · El médico ve su reporte del contador','ok',false,'d',left(sqlerrm, 150)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    begin
      perform public.accountant_report(v_orgA, v_pay_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09b · Otro cliente no ve el reporte ajeno','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09b · Otro cliente no ve el reporte ajeno','ok',sqlerrm like 'Sin acceso al reporte del contador%','d','Bloqueado: ' || left(sqlerrm, 100)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub',v_fact,'role','authenticated')::text, true);
    begin
      perform public.accountant_report(v_orgA, v_pay_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09c · Facturación no ve el reporte del contador','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09c · Facturación no ve el reporte del contador','ok',sqlerrm like 'Sin acceso al reporte del contador%','d','Bloqueado: ' || left(sqlerrm, 100)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-10 · anon no ejecuta y las funciones tienen search_path fijo
    v_ok := not has_function_privilege('anon', 'public.profitability(uuid,date,date,text)', 'EXECUTE')
        and not has_function_privilege('anon', 'public.accountant_report(uuid,date)', 'EXECUTE');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10a · El rol anon no tiene permiso de ejecución','ok',v_ok,'d',null));
    select coalesce(bool_and(p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')), false) into v_ok
      from pg_catalog.pg_proc p where p.oid in ('public.profitability(uuid,date,date,text)'::regprocedure, 'public.accountant_report(uuid,date)'::regprocedure);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10b · Las funciones son security definer con search_path fijo','ok',v_ok,'d',null));

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
