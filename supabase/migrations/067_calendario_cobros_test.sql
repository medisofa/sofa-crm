-- 067 · Suite de la 066 (calendario de cobros y alerta de atraso). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_calendario_cobros();
create or replace function app.qa_run_tests_calendario_cobros()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_a jsonb; v_x jsonb; v_ok boolean; v_lots jsonb := '{}'::jsonb; v_l uuid; v_i int := 0;
  r record; v_term int; v_late int;
  v_orgA constant uuid := 'b8000000-0000-4000-8000-0000000000b1';
  v_orgB constant uuid := 'b8000000-0000-4000-8000-0000000000b2';
  v_pA constant uuid := 'c8000000-0000-4000-8000-0000000000b1';
  v_pB constant uuid := 'c8000000-0000-4000-8000-0000000000b2';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_admin constant text := 'a8000000-0000-4000-8000-0000000000b1';
  v_fact constant text := 'a8000000-0000-4000-8000-0000000000b2';
  v_cliA constant text := 'a8000000-0000-4000-8000-0000000000b3';
  v_cliB constant text := 'a8000000-0000-4000-8000-0000000000b4';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email) values (v_admin::uuid,'qa.cc.admin@sofa.test'), (v_fact::uuid,'qa.cc.fact@sofa.test'), (v_cliA::uuid,'qa.cc.cliA@sofa.test'), (v_cliB::uuid,'qa.cc.cliB@sofa.test');
    insert into public.profiles (id, full_name) select id, replace(email, '@sofa.test', '') from auth.users where email like 'qa.cc.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on) values
      (v_orgA, 'client', v_op, 'QA CC A', '00000000111', 'Centro médico', 'activo', current_date - 300),
      (v_orgB, 'client', v_op, 'QA CC B', '00000000112', 'Consultorio',   'activo', current_date - 300);
    update public.organizations set ecf_required_from = date '2099-12-31' where kind = 'client' and ecf_required_from is distinct from date '2099-12-31';
    -- La configuración de producción puede exigir evidencia de entrega para radicar; dentro de la prueba se desactiva (se deshace sola)
    update public.app_settings set require_delivery_evidence = false where operator_id = v_op;
    insert into public.providers (id, organization_id, full_name) values (v_pA, v_orgA, 'Dr. Médico CC A'), (v_pB, v_orgB, 'Dr. Médico CC B');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (v_op, v_admin::uuid, 'admin'), (v_op, v_fact::uuid, 'billing'), (v_orgA, v_cliA::uuid, 'client'), (v_orgB, v_cliB::uuid, 'client');

    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    for r in select * from (values ('A', 'humano'), ('B', 'humano'), ('B', 'universal')) t(org, ars) loop
      perform public.create_contract_tariff(case r.org when 'A' then v_pA else v_pB end, (select id from public.ars where code = r.ars),
              (select id from public.procedures where internal_code='SOFA-P07'), 1200, date_trunc('month', current_date)::date - 220, null, 'CT-CC');
    end loop;
    -- Tres lotes de A pagados completos a los 40 días (historial) + un lote de A sin pagar, y dos lotes de B sin pagar
    for r in select * from (values
        ('H3','A','humano',3,'s',10,40), ('H4','A','humano',4,'s',10,40), ('H5','A','humano',5,'s',10,40),
        ('ACT','A','humano',2,'h',45,null), ('BH','B','humano',2,'h',45,null), ('BU','B','universal',2,'h',45,null)
      ) t(k, org, ars, mo, modo, dias, pago) loop
      v_i := v_i + 1;
      v_a := public.capture_claim(case r.org when 'A' then v_pA else v_pB end, (select id from public.ars where code = r.ars),
              (select id from public.procedures where internal_code='SOFA-P07'), (date_trunc('month', current_date) - (r.mo || ' month')::interval)::date,
              'Paciente CC ' || r.k, 'NSS-CC-' || r.k, 'AUT-CC-' || r.k, null, null, 1, 'ambulatorio');
      v_l := (v_a->>'submission_id')::uuid;
      v_lots := v_lots || jsonb_build_object(r.k, v_l);
      update public.submissions set ncf = 'B01000090' || lpad(v_i::text, 2, '0'), invoice_date = current_date where id = v_l;
      perform public.change_submission_status(v_l, 'recibida');
      perform public.change_submission_status(v_l, 'en_depuracion');
      perform public.change_submission_status(v_l, 'lista_para_radicar', null, 'QA: lote de prueba autorizado por administración');
      update public.submissions set fiscal_invoice_number = 'F-CC-' || r.k, accountant_name = 'Lic. QA', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_l) where id = v_l;
      perform public.change_submission_status(v_l, 'radicada', null, null,
              case r.modo when 's' then (date_trunc('month', current_date) - (r.mo || ' month')::interval)::date + r.dias else current_date - r.dias end,
              'R-CC-' || r.k, 'fisico', 'LOTE-CC-' || r.k);
      if r.pago is not null then
        perform public.register_payment(case r.org when 'A' then v_orgA else v_orgB end, (select id from public.ars where code = r.ars),
                (select submitted_on from public.submissions where id = v_l) + r.pago, 1200, 'transferencia', 'TRF-CC-' || r.k,
                jsonb_build_array(jsonb_build_object('submission_id', v_l, 'amount', 1200)));
      end if;
    end loop;

    -- CT-01 · Con historial del cliente (3 lotes a 40 días) la fecha esperada sale del historial
    v_x := public.collection_calendar(v_orgA);
    v_ok := jsonb_array_length(v_x->'lotes') = 1 and v_x->'lotes'->0->>'basis' = 'historial_cliente' and (v_x->'lotes'->0->>'days_expected')::int = 40
            and (v_x->'lotes'->0->>'expected_on')::date = current_date - 5 and v_x->'lotes'->0->>'status' = 'atrasado' and (v_x->'lotes'->0->>'days_late')::int = 5;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Esperado a 40 días por historial del cliente: atrasado 5 días','ok',v_ok,'d',(v_x->'lotes')::text));

    -- CT-02 · Totales y desglose por ARS
    v_ok := (v_x->'totals'->>'balance')::numeric = 1200 and (v_x->'totals'->>'late_lotes')::int = 1 and (v_x->'totals'->>'late_balance')::numeric = 1200
            and jsonb_array_length(v_x->'by_ars') = 1 and v_x->'by_ars'->0->>'ars' = 'ARS Humano';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Totales: RD$ 1,200 por cobrar, todo atrasado, 1 ARS','ok',v_ok,'d',(v_x->'totals')::text));

    -- CT-03 · La alerta de atraso se crea (y no se confunde con las alertas contractuales)
    perform public.refresh_alerts();
    v_ok := exists (select 1 from public.alerts where rule_code = 'cobro_atrasado_historial' and entity_id = (v_lots->>'ACT')::uuid and status <> 'completada' and organization_id = v_orgA)
            and not exists (select 1 from public.alerts where rule_code in ('cobro_vencido','cobro_por_vencer') and entity_id = (v_lots->>'ACT')::uuid and status <> 'completada');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · refresh_alerts crea la alerta de atraso según historial','ok',v_ok,'d',(select title from public.alerts where rule_code = 'cobro_atrasado_historial' and entity_id = (v_lots->>'ACT')::uuid limit 1)));

    -- CT-04 · Otro cliente con la misma ARS sin historial propio usa el historial de la ARS; otra ARS sin historial usa el plazo contractual
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    v_x := public.collection_calendar(null);
    select coalesce(payment_term_days, 90) into v_term from public.app_settings where operator_id = v_op;
    v_term := coalesce(v_term, 90);
    v_ok := jsonb_array_length(v_x->'lotes') = 2
            and exists (select 1 from jsonb_array_elements(v_x->'lotes') e where e->>'ars' = 'ARS Humano' and e->>'basis' = 'historial_ars' and (e->>'days_expected')::int = 40)
            and exists (select 1 from jsonb_array_elements(v_x->'lotes') e where e->>'ars' <> 'ARS Humano' and e->>'basis' = 'plazo_contractual' and (e->>'days_expected')::int = v_term);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Sin historial propio: usa la ARS; sin historial de la ARS: plazo contractual (' || v_term || ' días)','ok',v_ok,'d',(select string_agg(e->>'ars' || ':' || (e->>'basis'), ', ') from jsonb_array_elements(v_x->'lotes') e)));

    -- CT-05 · Las alertas de B: solo la de historial (la de plazo contractual aún no aplica a los 45 días)
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.refresh_alerts();
    select count(*) into v_late from public.alerts where rule_code = 'cobro_atrasado_historial' and organization_id = v_orgB and status <> 'completada';
    v_ok := v_late = 1;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Solo el lote con historial genera alerta de atraso (no el de plazo contractual)','ok',v_ok,'d',v_late || ' alerta(s)'));

    -- CT-06 · Al cobrarse el lote la alerta se cierra y sale del calendario
    perform public.register_payment(v_orgA, (select id from public.ars where code='humano'), current_date, 1200, 'transferencia', 'TRF-CC-ACT', jsonb_build_array(jsonb_build_object('submission_id', (v_lots->>'ACT')::uuid, 'amount', 1200)));
    perform public.refresh_alerts();
    v_x := public.collection_calendar(v_orgA);
    v_ok := jsonb_array_length(v_x->'lotes') = 0
            and exists (select 1 from public.alerts where rule_code = 'cobro_atrasado_historial' and entity_id = (v_lots->>'ACT')::uuid and status = 'completada')
            and not exists (select 1 from public.alerts where rule_code = 'cobro_atrasado_historial' and entity_id = (v_lots->>'ACT')::uuid and status <> 'completada');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Cobrado el lote: sale del calendario y la alerta se cierra','ok',v_ok,'d',null));

    -- CT-07 · Otro cliente no ve el calendario ajeno
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    begin
      perform public.collection_calendar(v_orgA);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro cliente no ve el calendario ajeno','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro cliente no ve el calendario ajeno','ok',sqlerrm like 'Sin acceso al calendario de cobros%','d','Bloqueado: ' || left(sqlerrm, 120)));
    end;

    -- CT-08 · Facturación no ve cobros proyectados (ni con p_org nulo)
    perform set_config('request.jwt.claims', json_build_object('sub',v_fact,'role','authenticated')::text, true);
    begin
      perform public.collection_calendar(null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no ve el calendario de cobros','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no ve el calendario de cobros','ok',sqlerrm like 'Sin acceso a ningún cliente%','d','Bloqueado: ' || left(sqlerrm, 120)));
    end;

    -- CT-09 · Un cliente no puede refrescar alertas (regla ya existente que no debe romperse)
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    begin
      perform public.refresh_alerts();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Un cliente no refresca las alertas','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Un cliente no refresca las alertas','ok',sqlerrm like 'Solo Super Admin%','d','Bloqueado: ' || left(sqlerrm, 120)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-10 · La función interna no es llamable desde la API y la pública no es de anon
    v_ok := not has_function_privilege('authenticated', 'app.expected_collections()', 'EXECUTE')
        and not has_function_privilege('anon', 'app.expected_collections()', 'EXECUTE')
        and not has_function_privilege('anon', 'public.collection_calendar(uuid)', 'EXECUTE')
        and has_function_privilege('authenticated', 'public.collection_calendar(uuid)', 'EXECUTE');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Permisos de ejecución correctos (interna cerrada, pública solo authenticated)','ok',v_ok,'d',null));

    -- CT-11 · search_path fijo en las tres funciones
    select coalesce(bool_and(p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')), false) into v_ok
      from pg_catalog.pg_proc p where p.oid in ('app.expected_collections()'::regprocedure, 'public.collection_calendar(uuid)'::regprocedure, 'public.refresh_alerts()'::regprocedure);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · Las funciones son security definer con search_path fijo','ok',v_ok,'d',null));

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
