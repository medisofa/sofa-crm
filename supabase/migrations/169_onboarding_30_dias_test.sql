-- 169 · Suite de la 168 (onboarding del cliente nuevo en 30 días). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_onboarding_30();
create or replace function app.qa_run_tests_onboarding_30()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01690000-0000-4000-8000-000000000001'; v_prov constant uuid := '01690000-0000-4000-8000-000000000003';
  v_as constant text := '01690000-0000-4000-8000-000000000011'; v_med constant text := '01690000-0000-4000-8000-000000000012'; v_sec constant text := '01690000-0000-4000-8000-000000000013';
  v_lead uuid; v_cnt int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_as::uuid,'qa.ob.as@sofa.test','x'),(v_med::uuid,'qa.ob.med@sofa.test','x'),(v_sec::uuid,'qa.ob.sec@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ob.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA OB Nuevo', '00000000931', 'Médico independiente', 'activo', current_date - 90, '8095550931');
    update public.organizations set activated_at = now() - interval '10 days', status = 'activo' where id = v_org;
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. Nuevo', 'Oftalmología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'), ('00000000-0000-4000-8000-000000000001'::uuid, v_as::uuid, 'assistant');
    insert into public.onboarding_items (organization_id, step_code, done, done_at, notes) values (v_org, 'contrato', true, now(), 'QA'), (v_org, 'autorizacion', true, now(), 'QA');
    insert into public.leads (operator_id, company, contact_name, source, converted_org_id) values ('00000000-0000-4000-8000-000000000001'::uuid, 'QA OB Nuevo', 'Dr. Nuevo', 'Otro', v_org) returning id into v_lead;
    insert into public.leak_diagnostics (operator_id, lead_id, monthly_billing, glosa_pct, recoverable_pct, dso_days) values ('00000000-0000-4000-8000-000000000001'::uuid, v_lead, 80000, 25, 40, 100);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.onboarding_plan(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-01 · Día 10: el hito del día 7 está atrasado y dice qué falta','ok',coalesce(((v_x->>'day')::int = 10 and (v_x->'milestones'->0->>'late')::boolean and v_x->'milestones'->0->'missing' ? 'tarifario'), false),'d',(v_x->>'milestones')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-02 · Trae la línea base del diagnóstico (25 % de glosa)','ok',coalesce(((v_x->'baseline'->>'glosa_pct')::numeric = 25), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.onboarding_plan(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-03 · La Secretaria no ve el plan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-03 · La Secretaria no ve el plan','ok',sqlerrm like 'Sin acceso al plan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_cnt := app.onboarding_followup();
    v_cnt := app.onboarding_followup();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-04 · Tarea del hito atrasado (una sola)','ok',coalesce(((select count(*) from public.tasks where organization_id = v_org and title like 'Onboarding día 7%') = 1 and not exists (select 1 from public.tasks where organization_id = v_org and title like 'Onboarding día 30%')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_as, 'role', 'authenticated')::text, true);
    v_x := public.onboarding_board();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-05 · Tablero: el cliente nuevo aparece atrasado','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x) c where (c->>'organization_id')::uuid = v_org and (c->>'late')::boolean)), false),'d',(null)::text));
    begin
      perform public.onboarding_review_add(v_org, 5, 'Bien', 'Nada', '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-06 · Revisión sin metas: las pide','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-06 · Revisión sin metas: las pide','ok',sqlerrm like 'Anote las metas del siguiente trimestre%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.onboarding_review_add(v_org, 9, 'Bien', 'Nada', 'Bajar la glosa a 10 por ciento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-07 · Satisfacción fuera de rango','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-07 · Satisfacción fuera de rango','ok',sqlerrm like 'La satisfacción va de 1 a 5%','d',left(sqlerrm,120)));
    end;
    perform public.onboarding_review_add(v_org, 4, 'Captura diaria', 'Cartas a las ARS', 'Bajar la glosa a 10 por ciento en el trimestre');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.onboarding_plan(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-08 · La revisión queda con la foto de la línea base y lo real','ok',coalesce((jsonb_array_length(v_x->'reviews') = 1 and (v_x->'reviews'->0->>'satisfaction')::int = 4), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.onboarding_review_add(v_org, 5, 'x', 'y', 'Metas del trimestre siguiente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-09 · El Médico no registra la revisión','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-09 · El Médico no registra la revisión','ok',sqlerrm like 'La revisión de resultados la registra el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','OB-10 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.onboarding_reviews', 'select') and not has_function_privilege('anon', 'public.onboarding_plan(uuid)', 'execute')), false),'d',(null)::text));

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
