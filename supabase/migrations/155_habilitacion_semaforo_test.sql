-- 155 · Suite de la 154 (habilitación: vista del cliente, simulacro y vencimientos). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_habilitacion_cliente();
create or replace function app.qa_run_tests_habilitacion_cliente()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01550000-0000-4000-8000-000000000001'; v_org2 constant uuid := '01550000-0000-4000-8000-000000000002';
  v_med constant text := '01550000-0000-4000-8000-000000000011'; v_otro constant text := '01550000-0000-4000-8000-000000000012'; v_as constant text := '01550000-0000-4000-8000-000000000013'; v_adm constant text := '01550000-0000-4000-8000-000000000014';
  v_case uuid; v_case2 uuid; v_item uuid; v_req uuid; v_cnt int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.hb.med@sofa.test','x'),(v_otro::uuid,'qa.hb.otro@sofa.test','x'),(v_as::uuid,'qa.hb.as@sofa.test','x'),(v_adm::uuid,'qa.hb.adm@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.hb.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA HB Centro', '00000000871', 'Médico independiente', 'activo', current_date - 90, '8095550871');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA HB Otro', '00000000872', 'Médico independiente', 'activo', current_date - 90, '8095550872');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org2, v_otro::uuid, 'client'),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_as::uuid, 'assistant'), ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin');
    insert into public.habilitation_cases (operator_id, organization_id, establishment_name, establishment_type, case_kind, stage)
    values ('00000000-0000-4000-8000-000000000001'::uuid, v_org, 'QA Centro Habilitación', 'Consultorio', 'apertura', 'diagnostico') returning id into v_case;
    insert into public.habilitation_items (case_id, area, requirement_id, requirement, is_critical, sort_order, status)
    select v_case, r.area, r.id, r.requirement, r.is_critical, r.sort_order, 'pendiente' from public.habilitation_requirements r where r.is_active and 'Consultorio' = any (r.applies_to);
    update public.habilitation_items set status = 'verde' where case_id = v_case and sort_order = (select min(sort_order) from public.habilitation_items where case_id = v_case);
    select id into v_item from public.habilitation_items where case_id = v_case and status = 'pendiente' and is_critical order by sort_order limit 1;
    insert into public.habilitation_cases (operator_id, organization_id, establishment_name, establishment_type, case_kind, stage, license_valid_until, stage_changed_at)
    values ('00000000-0000-4000-8000-000000000001'::uuid, v_org, 'QA Centro Habilitado', 'Consultorio', 'apertura', 'diagnostico', current_date + 20, now()) returning id into v_case2;
    update public.habilitation_cases set stage = 'habilitado', stage_changed_at = now() + interval '1 second' where id = v_case2;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.client_habilitation(v_org);
    select c into v_x from jsonb_array_elements(v_x) c where (c->>'id')::uuid = v_case;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-01 · El cliente ve su caso con el semáforo por área y qué debe entregar','ok',coalesce(((v_x->'counts'->>'verde')::int = 1 and (v_x->'counts'->>'critical_open')::int >= 1 and jsonb_array_length(v_x->'areas') >= 1 and v_x->'areas'->0->'items'->0 ? 'hint'), false),'d',(v_x->>'counts')::text));
    begin
      perform public.habilitation_item_submit(v_item, '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-02 · Entrega sin explicar: pide contar qué entregó','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-02 · Entrega sin explicar: pide contar qué entregó','ok',sqlerrm like 'Cuente qué entregó%','d',left(sqlerrm,120)));
    end;
    perform public.habilitation_item_submit(v_item, 'Copia del exequátur enviada por WhatsApp');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-03 · Queda la nota del cliente y una tarea para SOFA','ok',coalesce(((select client_note from public.habilitation_items where id = v_item) like 'Copia del exequátur%' and exists (select 1 from public.tasks where entity_type = 'habilitation' and entity_id = v_case and title like 'Revisar entrega de habilitación%')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.client_habilitation(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-04 · Otro cliente no ve este caso','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-04 · Otro cliente no ve este caso','ok',sqlerrm like 'Sin acceso a la habilitación%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.habilitation_item_submit(v_item, 'Algo entregado aquí');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-05 · Otro cliente no entrega en este caso','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-05 · Otro cliente no entrega en este caso','ok',sqlerrm like 'Sin acceso a este caso%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_as, 'role', 'authenticated')::text, true);
    v_x := public.habilitation_mock_inspection(v_case);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-06 · Simulacro de inspección: lo crítico primero y aviso de catálogo sin confirmar','ok',coalesce(((v_x->'items'->0->>'critical')::boolean and (v_x->>'unconfirmed_catalog')::boolean), false),'d',(v_x->>'items')::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_cnt := app.habilitation_followup();
    v_cnt := app.habilitation_followup();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-07 · Licencia que vence en 20 días: tarea de renovación (una sola)','ok',coalesce(((select count(*) from public.tasks where entity_id = v_case2 and title like 'Renovar habilitación%') = 1), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-08 · Habilitado sin código PSS: tarea para tramitarlo','ok',coalesce((exists (select 1 from public.tasks where entity_id = v_case2 and title like 'Tramitar código PSS%')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_as, 'role', 'authenticated')::text, true);
    begin
      perform public.habilitation_requirement_confirm((select id from public.habilitation_requirements limit 1), true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-09 · Comercial no confirma el catálogo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-09 · Comercial no confirma el catálogo','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select id into v_req from public.habilitation_requirements order by sort_order limit 1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform public.habilitation_requirement_confirm(v_req, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-10 · El Administrador confirma un requisito con el MISPAS','ok',coalesce(((select confirmed_with_mispas from public.habilitation_requirements where id = v_req)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HB-11 · Sin sesión no se usa','ok',coalesce((not has_function_privilege('anon', 'public.client_habilitation(uuid)', 'execute')), false),'d',(null)::text));

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
