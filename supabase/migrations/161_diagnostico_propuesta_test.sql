-- 161 · Suite de la 160 (diagnóstico de fugas y propuesta con ROI). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_propuesta_roi();
create or replace function app.qa_run_tests_propuesta_roi()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_as constant text := '01610000-0000-4000-8000-000000000011'; v_ops constant text := '01610000-0000-4000-8000-000000000012'; v_lead uuid; v_diag uuid; v_prop uuid; v_prop2 uuid; v_opp uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_as::uuid,'qa.pr.as@sofa.test','x'),(v_ops::uuid,'qa.pr.ops@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.pr.%@sofa.test' on conflict (id) do nothing;
    insert into public.organization_users (organization_id, user_id, role_code) values ('00000000-0000-4000-8000-000000000001'::uuid, v_as::uuid, 'assistant'), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations');
    insert into public.leads (operator_id, company, contact_name, source, specialty) values ('00000000-0000-4000-8000-000000000001'::uuid, 'QA PR Clínica Prospecto', 'Dra. Prospecto', 'Otro', 'Pediatría') returning id into v_lead;
    insert into public.opportunities (operator_id, lead_id, service_code, stage) values ('00000000-0000-4000-8000-000000000001'::uuid, v_lead, 'facturacion', 'propuesta') returning id into v_opp;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    begin
      perform public.leak_diagnostic_create(v_lead, 100000, 20, 50, 120);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-01 · Operaciones no hace diagnósticos comerciales','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-01 · Operaciones no hace diagnósticos comerciales','ok',sqlerrm like 'Solo el equipo comercial%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_as, 'role', 'authenticated')::text, true);
    begin
      perform public.leak_diagnostic_create(v_lead, 0, 20, 50, 120);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-02 · Facturación cero: pide el monto aproximado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-02 · Facturación cero: pide el monto aproximado','ok',sqlerrm like 'Indique cuánto factura al mes%','d',left(sqlerrm,120)));
    end;
    v_diag := public.leak_diagnostic_create(v_lead, 100000, 20, 50, 120);
    v_x := public.leak_proposal_create(v_diag, 5000);
    v_prop := (v_x->>'id')::uuid;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-03 · Propuesta: recuperable 10,000 + glosa evitada 7,500 = 17,500 al mes; ROI 3.5 por cada RD$1','ok',coalesce(((v_x->'math'->>'recoverable_monthly')::numeric = 10000 and (v_x->'math'->>'gain_monthly')::numeric = 17500 and (v_x->'math'->>'roi')::numeric = 3.5 and v_x->>'folio' like 'PRO-%'), false),'d',(v_x->>'math')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-04 · Dinero atrapado por cobrar después de 60 días: RD$ 200,000','ok',coalesce(((v_x->'math'->>'cash_release')::numeric = 200000), false),'d',(null)::text));
    begin
      perform public.leak_proposal_create(v_diag, 5000, 0, array['nada']);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-05 · Servicio inexistente: pide elegir de la lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-05 · Servicio inexistente: pide elegir de la lista','ok',sqlerrm like 'Elija al menos un servicio%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.leak_proposal_set_status(v_prop, 'rechazada', '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-06 · Rechazo sin motivo: lo pide','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-06 · Rechazo sin motivo: lo pide','ok',sqlerrm like 'Anote el motivo del rechazo%','d',left(sqlerrm,120)));
    end;
    perform public.leak_proposal_set_status(v_prop, 'enviada');
    perform public.leak_proposal_set_status(v_prop, 'aceptada');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-07 · Aceptada: la oportunidad pasa a «acuerdo»','ok',coalesce(((select stage from public.opportunities where id = v_opp) = 'acuerdo' and (select status from public.leak_proposals where id = v_prop) = 'aceptada'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_as, 'role', 'authenticated')::text, true);
    begin
      perform public.leak_proposal_set_status(v_prop, 'rechazada', 'Muy cara para el cliente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-08 · Una propuesta decidida no cambia','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-08 · Una propuesta decidida no cambia','ok',sqlerrm like 'La propuesta ya fue aceptada%','d',left(sqlerrm,120)));
    end;
    v_prop2 := (public.leak_proposal_create(v_diag, 4000, 0, array['facturacion'], 1)->>'id')::uuid;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.leak_proposals set valid_until = current_date - 1 where id = v_prop2;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_as, 'role', 'authenticated')::text, true);
    begin
      perform public.leak_proposal_set_status(v_prop2, 'aceptada');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-09 · No se acepta una propuesta vencida','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-09 · No se acepta una propuesta vencida','ok',sqlerrm like 'La propuesta venció%','d',left(sqlerrm,120)));
    end;
    v_x := public.leak_pipeline();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-10 · Tablero comercial con el diagnóstico, sus propuestas y la vencida marcada','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'diagnostics') d where (d->>'id')::uuid = v_diag and jsonb_array_length(d->'proposals') = 2 and exists (select 1 from jsonb_array_elements(d->'proposals') p where (p->>'expired')::boolean))), false),'d',(left(v_x::text, 300))::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PR-11 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.leak_proposals', 'select') and not has_function_privilege('anon', 'public.leak_pipeline()', 'execute')), false),'d',(null)::text));

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
