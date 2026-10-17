-- 165 · Suite de la 164 (informe estratégico trimestral). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_informe_trimestral();
create or replace function app.qa_run_tests_informe_trimestral()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01650000-0000-4000-8000-000000000001'; v_org2 constant uuid := '01650000-0000-4000-8000-000000000002'; v_prov constant uuid := '01650000-0000-4000-8000-000000000003';
  v_med constant text := '01650000-0000-4000-8000-000000000011'; v_sec constant text := '01650000-0000-4000-8000-000000000012'; v_ops constant text := '01650000-0000-4000-8000-000000000013'; v_otro constant text := '01650000-0000-4000-8000-000000000014';
  v_a1 uuid; v_a2 uuid; v_p1 uuid; v_q date; v_s1 uuid; v_s2 uuid; v_pay uuid; v_l uuid; v_g uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.it.med@sofa.test','x'),(v_sec::uuid,'qa.it.sec@sofa.test','x'),(v_ops::uuid,'qa.it.ops@sofa.test','x'),(v_otro::uuid,'qa.it.otro@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.it.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA IT Consultorio', '00000000911', 'Médico independiente', 'activo', current_date - 90, '8095550911');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA IT Otro', '00000000912', 'Médico independiente', 'activo', current_date - 90, '8095550912');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. Trimestre', 'Ortopedia');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'), (v_org2, v_otro::uuid, 'client'),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_it_a', 'QA ARS Buena', 'Contributivo', true) returning id into v_a1;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_it_b', 'QA ARS Lenta', 'Contributivo', true) returning id into v_a2;
    select p.id into v_p1 from public.procedures p where p.is_active order by p.internal_code limit 1;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status) values
      (v_a1, v_org, v_prov, v_p1, 2000, daterange(current_date - 600, null), 'vigente'), (v_a2, v_org, v_prov, v_p1, 1500, daterange(current_date - 600, null), 'vigente');
    v_q := date_trunc('quarter', current_date)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_a1, v_q, 1, 'borrador', v_q) returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_a2, v_q, 2, 'borrador', v_q) returning id into v_s2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_q, 'Paciente IT 1', v_p1, 5, 2000);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_s2, v_org, v_q, 'Paciente IT 2', v_p1, 4, 1500) returning id into v_l;
    insert into public.payments (organization_id, ars_id, paid_on, amount, method, reference) values (v_org, v_a1, least(v_q + 20, current_date), 10000, 'transferencia', 'QA-IT') returning id into v_pay;
    insert into public.payment_allocations (payment_id, organization_id, submission_id, amount) values (v_pay, v_org, v_s1, 10000);
    insert into public.glosas (organization_id, submission_id, notified_on) values (v_org, v_s2, least(v_q + 5, current_date)) returning id into v_g;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_g, v_org, v_l, 'sin_autorizacion', 1200);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.quarterly_report(v_org, v_q, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-01 · Por ARS: la buena cobra 100 %; la lenta 0 % con 20 % de glosa','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'by_ars') a where a->>'ars' = 'QA ARS Buena' and (a->>'net_rate')::numeric = 100) and exists (select 1 from jsonb_array_elements(v_x->'by_ars') a where a->>'ars' = 'QA ARS Lenta' and (a->>'glosa_pct')::numeric = 20)), false),'d',(v_x->>'by_ars')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-02 · Recomienda priorizar la buena, bajar la glosa de la lenta y renegociar','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'recommendations') r where r->>'kind' = 'priorizar' and r->>'ars' = 'QA ARS Buena') and exists (select 1 from jsonb_array_elements(v_x->'recommendations') r where r->>'kind' = 'glosa' and r->>'ars' = 'QA ARS Lenta') and exists (select 1 from jsonb_array_elements(v_x->'recommendations') r where r->>'kind' = 'renegociar' and r->>'ars' = 'QA ARS Lenta')), false),'d',(v_x->>'recommendations')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-03 · Recomienda atacar la causa principal de glosa','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'recommendations') r where r->>'kind' = 'causa' and r->>'text' like '%Falta de autorización%')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-04 · Totales del trimestre y comparación con el anterior','ok',coalesce(((v_x->'totals'->>'claimed')::numeric = 16000 and v_x ? 'prev_totals'), false),'d',(v_x->>'totals')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-05 · El informe queda guardado','ok',coalesce((jsonb_array_length(public.quarterly_reports_list(v_org)) = 1), false),'d',(null)::text));
    begin
      perform public.quarterly_report(v_org, (v_q + interval '6 months')::date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-06 · Trimestre futuro: lo rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-06 · Trimestre futuro: lo rechaza','ok',sqlerrm like 'Elija un trimestre que ya empezó%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.quarterly_report(v_org, v_q);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-07 · La Secretaria no ve el informe','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-07 · La Secretaria no ve el informe','ok',sqlerrm like 'Sin acceso al informe%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.quarterly_reports_list(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-08 · Otro cliente no lo ve','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-08 · Otro cliente no lo ve','ok',sqlerrm like 'Sin acceso a los informes%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-09 · Operaciones de SOFA lo genera para la reunión','ok',coalesce((public.quarterly_report(v_org, v_q) ? 'by_ars'), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IT-10 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.quarterly_reports', 'select')), false),'d',(null)::text));

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
