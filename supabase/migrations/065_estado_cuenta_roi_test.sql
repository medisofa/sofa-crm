-- 065 · Suite de la 064 (estado de cuenta con ROI). Se deshace sola: no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_estado_cuenta();
create or replace function app.qa_run_tests_estado_cuenta()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_a jsonb; v_b jsonb; v_x jsonb; v_lote uuid; v_ok boolean; v_fee numeric;
  v_org constant uuid := 'b8000000-0000-4000-8000-0000000000a1';
  v_org2 constant uuid := 'b8000000-0000-4000-8000-0000000000a2';
  v_prov constant uuid := 'c8000000-0000-4000-8000-0000000000a1';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email) values
      ('a8000000-0000-4000-8000-0000000000a1','qa.ec.admin@sofa.test'), ('a8000000-0000-4000-8000-0000000000a2','qa.ec.fact@sofa.test'),
      ('a8000000-0000-4000-8000-0000000000a3','qa.ec.cliA@sofa.test'),  ('a8000000-0000-4000-8000-0000000000a4','qa.ec.cliB@sofa.test'),
      ('a8000000-0000-4000-8000-0000000000a5','qa.ec.capA@sofa.test');
    insert into public.profiles (id, full_name) select id, replace(email, '@sofa.test', '') from auth.users where email like 'qa.ec.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on) values
      (v_org,  'client', v_op, 'QA EC A', '00000000101', 'Centro médico', 'activo', current_date - 90),
      (v_org2, 'client', v_op, 'QA EC B', '00000000102', 'Consultorio',   'activo', current_date - 90);
    update public.organizations set ecf_required_from = date '2099-12-31' where kind = 'client' and ecf_required_from is distinct from date '2099-12-31';
    -- La configuración de producción puede exigir evidencia de entrega para radicar; dentro de la prueba se desactiva (se deshace sola)
    update public.app_settings set require_delivery_evidence = false where operator_id = v_op;
    insert into public.providers (id, organization_id, full_name) values (v_prov, v_org, 'Dr. Médico EC QA'), ('c8000000-0000-4000-8000-0000000000a2', v_org2, 'Dr. Otro EC QA');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (v_op, 'a8000000-0000-4000-8000-0000000000a1', 'admin'), (v_op, 'a8000000-0000-4000-8000-0000000000a2', 'billing'),
      (v_org, 'a8000000-0000-4000-8000-0000000000a3', 'client'), (v_org2, 'a8000000-0000-4000-8000-0000000000a4', 'client'),
      (v_org, 'a8000000-0000-4000-8000-0000000000a5', 'capturer');

    -- Datos: dos reclamaciones del mes, lote radicado, un pago de una de ellas y esquema de honorarios 10 %
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-0000000000a1','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.create_contract_tariff(v_prov, (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), 1200, date_trunc('month', current_date)::date - 100, null, 'CT-EC');
    v_a := public.capture_claim(v_prov, (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), date_trunc('month', current_date)::date, 'Paciente EC A', 'NSS-EC-1', 'AUT-EC-1', null, null, 1, 'ambulatorio');
    v_b := public.capture_claim(v_prov, (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), date_trunc('month', current_date)::date, 'Paciente EC B', 'NSS-EC-2', 'AUT-EC-2', null, null, 1, 'ambulatorio');
    v_lote := (v_a->>'submission_id')::uuid;
    perform public.set_fee_scheme(v_org, 'porcentaje', null, 10, date_trunc('month', current_date)::date - 100);
    update public.submissions set ncf = 'B0100000701', invoice_date = current_date where id = v_lote;
    perform public.change_submission_status(v_lote, 'recibida');
    perform public.change_submission_status(v_lote, 'en_depuracion');
    perform public.change_submission_status(v_lote, 'lista_para_radicar', null, 'QA: lote de prueba autorizado por administración');
    update public.submissions set fiscal_invoice_number = 'F-B0100000701', accountant_name = 'Lic. QA', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_lote) where id = v_lote;
    perform public.change_submission_status(v_lote, 'radicada', null, null, current_date, 'R-EC-1', 'fisico', 'LOTE-EC-1');
    perform public.register_payment(v_org, (select id from public.ars where code='humano'), current_date, 1200, 'transferencia', 'TRF-EC-1', jsonb_build_array(jsonb_build_object('submission_id', v_lote, 'amount', 1200)));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    select coalesce(sum(amount), 0) into v_fee from public.sofa_fees where organization_id = v_org;

    -- CT-01 · El Admin ve la producción del mes
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-0000000000a1','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.account_statement(v_org, current_date);
    v_ok := (v_x->'production'->>'lines')::int = 2 and (v_x->'production'->>'claimed')::numeric = 2400 and (v_x->>'period')::date = date_trunc('month', current_date)::date;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Producción del mes: 2 reclamaciones por RD$ 2,400','ok',v_ok,'d',(v_x->'production')::text));

    -- CT-02 · Lo cobrado en el mes y lo que queda por ARS
    v_ok := (v_x->'cash'->>'collected')::numeric = 1200 and (v_x->'cash'->>'payments')::int = 1
            and (v_x->'by_ars'->0->>'paid')::numeric = 1200 and (v_x->'by_ars'->0->>'balance')::numeric = 1200;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Cobrado RD$ 1,200 en 1 pago; saldo pendiente RD$ 1,200','ok',v_ok,'d',(v_x->'cash')::text || ' ' || (v_x->'by_ars')::text));

    -- CT-03 · Los honorarios del estado salen de sofa_fees y el ROI se calcula con ellos
    v_ok := (v_x->'fees'->>'accrued')::numeric = v_fee and v_fee > 0
            and (v_x->'roi'->>'return_x')::numeric = round(1200 / v_fee, 1)
            and (v_x->'roi'->>'roi_pct')::numeric = round((1200 - v_fee) / v_fee * 100, 1);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Honorarios y ROI coinciden con sofa_fees (honorarios RD$ ' || v_fee || ')','ok',v_ok,'d',(v_x->'roi')::text));

    -- CT-04 · Sin honorarios devengados no hay ROI (no divide entre cero)
    v_x := public.account_statement(v_org, (date_trunc('month', current_date) - interval '1 month')::date);
    v_ok := (v_x->'production'->>'lines')::int = 0 and (v_x->'roi'->>'return_x') is null and (v_x->'roi'->>'roi_pct') is null
            and (v_x->'previous'->>'claimed')::numeric = 0;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Mes sin honorarios: ROI nulo y sin división entre cero','ok',v_ok,'d',(v_x->'roi')::text));

    -- CT-05 · El mes siguiente ve el mes de trabajo como "mes anterior"
    v_x := public.account_statement(v_org, (date_trunc('month', current_date) + interval '1 month')::date);
    v_ok := (v_x->'previous'->>'claimed')::numeric = 2400 and (v_x->'previous'->>'collected')::numeric = 1200;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Tendencia: el mes anterior trae reclamado 2,400 y cobrado 1,200','ok',v_ok,'d',(v_x->'previous')::text));

    -- CT-06 · El médico ve su propio estado
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-0000000000a3','role','authenticated')::text, true);
    begin
      v_x := public.account_statement(v_org, current_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El médico (cliente) ve su propio estado de cuenta','ok',(v_x->'cash'->>'collected')::numeric = 1200,'d',null));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El médico (cliente) ve su propio estado de cuenta','ok',false,'d',left(sqlerrm, 200)));
    end;

    -- CT-07 · Otro cliente no ve el estado ajeno
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-0000000000a4','role','authenticated')::text, true);
    begin
      perform public.account_statement(v_org, current_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro cliente no ve el estado de cuenta ajeno','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro cliente no ve el estado de cuenta ajeno','ok',sqlerrm like 'Sin acceso al estado de cuenta%','d','Bloqueado: ' || left(sqlerrm, 120)));
    end;

    -- CT-08 · Facturación no ve cobros (decisión 01/10/2026)
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-0000000000a2','role','authenticated')::text, true);
    begin
      perform public.account_statement(v_org, current_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no accede al estado de cuenta','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no accede al estado de cuenta','ok',sqlerrm like 'Sin acceso al estado de cuenta%','d','Bloqueado: ' || left(sqlerrm, 120)));
    end;

    -- CT-09 · La secretaria tampoco
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-0000000000a5','role','authenticated')::text, true);
    begin
      perform public.account_statement(v_org, current_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · La secretaria no accede al estado de cuenta','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · La secretaria no accede al estado de cuenta','ok',sqlerrm like 'Sin acceso al estado de cuenta%','d','Bloqueado: ' || left(sqlerrm, 120)));
    end;

    -- CT-10 · El Admin pide el estado de una organización que no es cliente
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-0000000000a1','role','authenticated')::text, true);
    begin
      perform public.account_statement(v_op, current_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · La organización operadora no es un cliente','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · La organización operadora no es un cliente','ok',sqlerrm like 'El cliente no existe o no es un cliente%' or sqlerrm like 'Sin acceso al estado de cuenta%','d','Bloqueado: ' || left(sqlerrm, 120)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-11 · Sin sesión (anon) no puede ejecutarla
    select not has_function_privilege('anon', 'public.account_statement(uuid,date)', 'EXECUTE') into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · El rol anon no tiene permiso de ejecución','ok',v_ok,'d',null));

    -- CT-12 · search_path fijo y security definer
    select coalesce((select p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
                       from pg_catalog.pg_proc p where p.oid = 'public.account_statement(uuid,date)'::regprocedure), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · La función es security definer con search_path fijo','ok',v_ok,'d',null));

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
