-- 147 · Suite de la 146 (cartera escalonada por ARS). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_cartera_escalonada();
create or replace function app.qa_run_tests_cartera_escalonada()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01470000-0000-4000-8000-000000000001'; v_org2 constant uuid := '01470000-0000-4000-8000-000000000002'; v_prov constant uuid := '01470000-0000-4000-8000-000000000003';
  v_gl constant text := '01470000-0000-4000-8000-000000000011'; v_med constant text := '01470000-0000-4000-8000-000000000012'; v_ops constant text := '01470000-0000-4000-8000-000000000013'; v_adm constant text := '01470000-0000-4000-8000-000000000014';
  v_ars uuid; v_ars2 uuid; v_p1 uuid; v_s1 uuid; v_s2 uuid; v_s3 uuid; v_s4 uuid; v_pay uuid; v_act uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_gl::uuid,'qa.ce.gl@sofa.test','x'),(v_med::uuid,'qa.ce.med@sofa.test','x'),(v_ops::uuid,'qa.ce.ops@sofa.test','x'),(v_adm::uuid,'qa.ce.adm@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ce.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA CE Consultorio', '00000000831', 'Médico independiente', 'activo', current_date - 90, '8095550831');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA CE Otro', '00000000832', 'Médico independiente', 'activo', current_date - 90, '8095550832');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. Cartera', 'Ortopedia');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_gl::uuid, 'glosas'),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations'), ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_ce_ars', 'QA ARS Cartera', 'Contributivo', true) returning id into v_ars;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_ce_ars2', 'QA ARS Cartera Dos', 'Contributivo', true) returning id into v_ars2;
    select p.id into v_p1 from public.procedures p where p.is_active order by p.internal_code limit 1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, folio) values
      (v_org, v_prov, v_ars, date_trunc('month', current_date - 150)::date, 1, 'borrador', current_date - 45, 'QA-CE-45') returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, folio) values
      (v_org, v_prov, v_ars, date_trunc('month', current_date - 150)::date, 2, 'borrador', current_date - 50, 'QA-CE-50') returning id into v_s2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, folio) values
      (v_org, v_prov, v_ars2, date_trunc('month', current_date - 150)::date, 3, 'borrador', current_date - 120, 'QA-CE-120') returning id into v_s3;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, folio) values
      (v_org, v_prov, v_ars, date_trunc('month', current_date - 150)::date, 4, 'borrador', current_date - 70, 'QA-CE-PAG') returning id into v_s4;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select x, v_org, date_trunc('month', current_date - 150)::date + 1, 'Paciente CE', v_p1, 1, 1000 from unnest(array[v_s1, v_s2, v_s3, v_s4]) x;
    insert into public.payments (organization_id, ars_id, paid_on, amount, method, reference) values (v_org, v_ars, current_date - 30, 1000, 'transferencia', 'QA-CE') returning id into v_pay;
    insert into public.payment_allocations (payment_id, organization_id, submission_id, amount) values (v_pay, v_org, v_s4, 1000);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated')::text, true);
    v_x := public.collection_board(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-01 · Saldo de 3 lotes; el pagado no aparece','ok',coalesce(((v_x->'totals'->>'lots')::int = 3 and (v_x->'totals'->>'balance')::numeric = 3000 and (v_x->'totals'->>'over_90')::numeric = 1000), false),'d',(v_x->>'totals')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-02 · Etapas: 45 días = reclamación formal; 120 días = queja SISALRIL','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'lots') l where (l->>'id')::uuid = v_s1 and l->>'stage' = 'reclamacion_formal' and (l->>'pending')::boolean) and exists (select 1 from jsonb_array_elements(v_x->'lots') l where (l->>'id')::uuid = v_s3 and l->>'stage' = 'queja_sisalril')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-03 · Días promedio de pago (DSO) de la ARS con el lote pagado: 40','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'by_ars') a where (a->>'ars_id')::uuid = v_ars and (a->>'dso')::int = 40)), false),'d',(v_x->>'by_ars')::text));
    begin
      perform public.collection_letter('reclamacion_formal', array[v_s1, v_s3]);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-04 · Una carta no mezcla ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-04 · Una carta no mezcla ARS','ok',sqlerrm like 'Una carta va a una sola ARS%','d',left(sqlerrm,120)));
    end;
    v_x := public.collection_letter('reclamacion_formal', array[v_s1, v_s2]);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-05 · La carta trae los 2 lotes, el total y el aviso de revisar el modelo','ok',coalesce((v_x->>'body' like '%QA-CE-45%' and v_x->>'body' like '%QA-CE-50%' and v_x->>'body' like '%RD$ 2,000.00%' and v_x->>'body' like '%QA ARS Cartera%' and v_x->>'warning' like 'Modelo de SOFA sin revisar%' and v_x->>'body' not like '%{%'), false),'d',(left(v_x->>'body', 300))::text));
    begin
      perform public.collection_action_add(v_org, v_ars, 'llamada', '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-06 · Llamada sin nota: pide escribir qué se habló','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-06 · Llamada sin nota: pide escribir qué se habló','ok',sqlerrm like 'Escriba qué se habló%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.collection_action_add(v_org, v_ars, 'promesa_pago', 'Dicen que pagan');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-07 · Promesa de pago sin fecha: la pide','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-07 · Promesa de pago sin fecha: la pide','ok',sqlerrm like 'Indique la fecha que prometió%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.collection_action_add(v_org, v_ars, 'carta', null, array[v_s3]);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-08 · No acepta lotes de otra ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-08 · No acepta lotes de otra ARS','ok',sqlerrm like 'Algún lote no es de ese cliente y esa ARS%','d',left(sqlerrm,120)));
    end;
    v_act := public.collection_action_add(v_org, v_ars, 'reclamacion_formal', 'Enviada por correo con acuse', array[v_s1, v_s2]);
    v_x := public.collection_board(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-09 · Registrada la reclamación, el lote deja de estar pendiente','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'lots') l where (l->>'id')::uuid = v_s1 and not (l->>'pending')::boolean and l->'last_action'->>'kind' = 'reclamacion_formal') and (v_x->'totals'->>'pending_actions')::int = 1), false),'d',(v_x->>'totals')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.collection_board(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-10 · El Médico ve su cartera pero no gestiona','ok',coalesce(((v_x->'totals'->>'lots')::int = 3 and not (v_x->>'can_edit')::boolean and jsonb_array_length(public.collection_history(v_org, v_ars)) = 1), false),'d',(null)::text));
    begin
      perform public.collection_action_add(v_org, v_ars, 'carta', 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-11 · El Médico no registra gestiones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-11 · El Médico no registra gestiones','ok',sqlerrm like 'Solo el Super Admin, el Administrador o Cobros%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.collection_board(null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-12 · El Médico no ve toda la cartera','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-12 · El Médico no ve toda la cartera','ok',sqlerrm like 'Elija su consultorio%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    begin
      perform public.collection_board(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-13 · Operaciones no ve la cartera','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-13 · Operaciones no ve la cartera','ok',sqlerrm like 'Sin acceso a la cartera%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    begin
      perform public.collection_template_save('escalamiento', 'Escalamiento', repeat('texto largo ', 10), true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-14 · La carta modelo debe incluir {lista}','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-14 · La carta modelo debe incluir {lista}','ok',sqlerrm like 'La carta debe incluir {lista}%','d',left(sqlerrm,120)));
    end;
    perform public.collection_template_save('escalamiento', 'Escalamiento revisado', 'Señores {ars}: ' || repeat('texto ', 10) || '{lista} Total {total}', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-15 · El Administrador revisa el modelo y queda sin aviso','ok',coalesce((exists (select 1 from jsonb_array_elements(public.collection_templates()) t where t->>'kind' = 'escalamiento' and (t->>'reviewed')::boolean)), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CE-16 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.collection_actions', 'select') and not has_function_privilege('anon', 'public.collection_board(uuid)', 'execute')), false),'d',(null)::text));

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
