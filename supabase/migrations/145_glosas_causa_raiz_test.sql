-- 145 · Suite de la 144 (plazo de respuesta y causa raíz de glosas). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_glosas_causa_raiz();
create or replace function app.qa_run_tests_glosas_causa_raiz()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01450000-0000-4000-8000-000000000001'; v_prov constant uuid := '01450000-0000-4000-8000-000000000003';
  v_gl constant text := '01450000-0000-4000-8000-000000000011'; v_adm constant text := '01450000-0000-4000-8000-000000000012'; v_med constant text := '01450000-0000-4000-8000-000000000013'; v_ops constant text := '01450000-0000-4000-8000-000000000014';
  v_ars uuid; v_p1 uuid; v_s uuid; v_l1 uuid; v_l2 uuid; v_g1 uuid; v_g2 uuid; v_g3 uuid; v_act uuid; v_per date; v_cnt int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_gl::uuid,'qa.gr.gl@sofa.test','x'),(v_adm::uuid,'qa.gr.adm@sofa.test','x'),(v_med::uuid,'qa.gr.med@sofa.test','x'),(v_ops::uuid,'qa.gr.ops@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.gr.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA GR Consultorio', '00000000821', 'Médico independiente', 'activo', current_date - 90, '8095550821');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. Glosa', 'Ginecología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_gl::uuid, 'glosas'),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin'), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_gr_ars', 'QA ARS Glosas', 'Contributivo', true) returning id into v_ars;
    select p.id into v_p1 from public.procedures p where p.is_active order by p.internal_code limit 1;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status) values (v_ars, v_org, v_prov, v_p1, 1000, daterange(current_date - 400, null), 'vigente');
    v_per := date_trunc('month', current_date - 25)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_ars, v_per, 1, 'borrador', current_date - 22) returning id into v_s;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s, v_org, v_per + 1, 'Paciente Uno GR', '300100', 'A1', v_p1, 1, 1000) returning id into v_l1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s, v_org, v_per + 2, 'Paciente Dos GR', '300101', 'A2', v_p1, 1, 1000) returning id into v_l2;
    insert into public.glosas (organization_id, submission_id, notified_on) values (v_org, v_s, current_date - 20) returning id into v_g1;
    insert into public.glosas (organization_id, submission_id, notified_on) values (v_org, v_s, current_date) returning id into v_g2;
    insert into public.glosas (organization_id, submission_id, notified_on) values (v_org, v_s, current_date - 10) returning id into v_g3;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values
      (v_g1, v_org, v_l1, 'sin_autorizacion', 500), (v_g2, v_org, v_l2, 'documentacion', 100), (v_g3, v_org, v_l1, 'sin_autorizacion', 200);
    insert into public.glosa_appeals (glosa_id, organization_id, submitted_on, argument) values (v_g3, v_org, current_date - 8, 'Se adjunta la autorización');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-01 · Días hábiles: saltan el fin de semana y Navidad (24/12/2026 + 1 = 28/12/2026)','ok',coalesce((app.add_business_days('2026-12-24', 1) = '2026-12-28' and app.add_business_days('2026-04-02', 1) = '2026-04-06'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated')::text, true);
    v_x := public.glosa_response_board(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-02 · Glosa vieja sin responder: roja; la de hoy: verde','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'open') g where (g->>'id')::uuid = v_g1 and g->>'light' = 'rojo') and exists (select 1 from jsonb_array_elements(v_x->'open') g where (g->>'id')::uuid = v_g2 and g->>'light' = 'verde' and (g->>'days_left')::int = 7)), false),'d',(v_x->>'open')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-03 · La glosa apelada sale de pendientes y cuenta como respondida a tiempo','ok',coalesce((not exists (select 1 from jsonb_array_elements(v_x->'open') g where (g->>'id')::uuid = v_g3) and (v_x->'last90'->>'on_time')::int = 1 and (v_x->'last90'->>'pct_on_time')::numeric = 100), false),'d',(v_x->>'last90')::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_cnt := app.glosa_response_followup();
    v_cnt := app.glosa_response_followup();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-04 · Tarea «Responder glosa» para la vencida, una sola vez','ok',coalesce(((select count(*) from public.tasks where entity_type = 'glosa' and entity_id = v_g1 and status = 'abierta') = 1 and not exists (select 1 from public.tasks where entity_type = 'glosa' and entity_id = v_g2)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated')::text, true);
    v_x := public.glosa_root_pareto(v_org, current_date - 30, current_date);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-05 · Pareto: «Falta de autorización» es el 87.5 % y es causa vital; documentación no','ok',coalesce((v_x->'causes'->0->>'reason_code' = 'sin_autorizacion' and (v_x->'causes'->0->>'pct')::numeric = 87.5 and (v_x->'causes'->0->>'vital')::boolean and not (v_x->'causes'->1->>'vital')::boolean), false),'d',(v_x->>'causes')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-06 · Cada causa trae su regla de prevención','ok',coalesce((v_x->'causes'->0->>'tip' like 'Verificar y registrar la autorización%'), false),'d',(null)::text));
    begin
      perform public.glosa_root_action_save('sin_autorizacion', 'corto', v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-07 · Acción sin descripción: pide explicar el cambio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-07 · Acción sin descripción: pide explicar el cambio','ok',sqlerrm like 'Describa la acción correctiva%','d',left(sqlerrm,120)));
    end;
    v_act := public.glosa_root_action_save('sin_autorizacion', 'La secretaria registra la autorización antes de atender', v_org, v_ars, null, null, current_date + 10);
    v_x := public.glosa_root_actions_list('abierta');
    select a into v_x from jsonb_array_elements(v_x) a where (a->>'id')::uuid = v_act;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-08 · La acción guarda la línea base: 2 glosas por RD$ 700 en los 60 días previos','ok',coalesce(((v_x->'before'->>'items')::int = 2 and (v_x->'before'->>'amount')::numeric = 700), false),'d',(v_x->>'before')::text));
    begin
      perform public.glosa_root_action_close(v_act, 'descartada', '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-09 · Descartar exige el motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-09 · Descartar exige el motivo','ok',sqlerrm like 'Explique por qué se descarta%','d',left(sqlerrm,120)));
    end;
    perform public.glosa_root_action_close(v_act, 'hecha', 'Capacitada la secretaria');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-10 · Al cerrarla queda «hecha» y se medirá a los 60 días','ok',coalesce((exists (select 1 from jsonb_array_elements(public.glosa_root_actions_list('hecha')) a where (a->>'id')::uuid = v_act and not (a->>'measurable')::boolean and a ? 'after')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.glosa_root_pareto();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-11 · El Médico no ve el Pareto de toda la cartera','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-11 · El Médico no ve el Pareto de toda la cartera','ok',sqlerrm like 'El análisis de causas raíz es del equipo SOFA%','d',left(sqlerrm,120)));
    end;
    v_x := public.my_glosa_causes(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-12 · El Médico ve sus causas más frecuentes con cómo evitarlas','ok',coalesce((v_x->0->>'reason_code' = 'sin_autorizacion' and (v_x->0->>'amount')::numeric = 700 and v_x->0->>'tip' like 'Verificar%'), false),'d',(v_x::text)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    begin
      perform public.glosa_root_action_save('documentacion', 'Lista de verificación de documentos', v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-13 · Operaciones no registra acciones correctivas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-13 · Operaciones no registra acciones correctivas','ok',sqlerrm like 'Solo el Super Admin, el Administrador o Glosas%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.holiday_save('2026-11-09', 'Día de la Constitución');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-14 · Operaciones no cambia feriados','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-14 · Operaciones no cambia feriados','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform public.holiday_save('2030-11-11', 'Feriado QA');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-15 · El Administrador agrega un feriado y cuenta como no hábil','ok',coalesce((not app.is_business_day('2030-11-11') and exists (select 1 from jsonb_array_elements(public.holidays_list(2030)) h where h->>'name' = 'Feriado QA')), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GR-16 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.glosa_root_actions', 'select') and not has_function_privilege('anon', 'public.glosa_response_board(uuid)', 'execute')), false),'d',(null)::text));

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
