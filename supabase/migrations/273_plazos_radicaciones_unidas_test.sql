-- PENDIENTE de aplicar en producción. No fusionar así.
-- 273 · Suite de la 272 (plazos de radicaciones unidas). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_plazos_unidas();
create or replace function app.qa_run_tests_plazos_unidas()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql set search_path = '' as $function$
declare
  v_res jsonb := '[]'::jsonb; v_msg text; v_t text; v_before boolean; v_after boolean; v_d date; v_exp date; v_win int;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_ad   constant uuid := '27200000-0000-4000-8000-000000000002';
  v_org  constant uuid := '27200000-0000-4000-8000-0000000000a1';
  v_prov constant uuid := '27200000-0000-4000-8000-0000000000b1';
  v_ars uuid; v_p uuid; v_old uuid; v_new uuid; v_vacio uuid; v_m0 date; v_m1 date; v_n int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    v_m1 := (date_trunc('month', current_date) - interval '1 month')::date;
    v_m0 := (v_m1 - interval '3 month')::date;
    select coalesce(max(st.submission_window_days), 30) into v_win from public.app_settings st where st.operator_id = v_sofa;
    v_exp := (v_m0 + interval '1 month')::date - 1 + v_win;
    insert into auth.users (id, email, encrypted_password) values (v_ad,'qa.pu.ad@sofa.test','x');
    insert into public.profiles (id, full_name) values (v_ad, 'qa.pu.ad') on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', v_sofa, 'QA PU Consultorio', '00000027201', 'Médico independiente', 'activo', current_date - 200, '8095552721');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_prov, v_org, 'Dr. PU QA', 'Cardiología', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values (v_sofa, v_ad, 'admin', true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa272_ars', 'ARS QA Plazos Ficticia', 'Contributivo', true) returning id into v_ars;
    insert into public.procedures (internal_code, description, service_type_code, is_active)
    values ('QA272-P1', 'SERVICIO QA PLAZOS', (select service_type_code from public.procedures where is_active limit 1), true) returning id into v_p;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status, contract_ref)
    values (v_ars, v_org, v_prov, v_p, 750, daterange(current_date - 400, null), 'vigente', 'QA-PU-1');
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_prov, v_ars, v_m0, 1, 'borrador') returning id into v_old;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_prov, v_ars, v_m1, 1, 'borrador') returning id into v_new;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_prov, v_ars, (v_m1 - interval '1 month')::date, 1, 'borrador') returning id into v_vacio;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_old, v_org, v_m0 + 5, 'Paciente PU Uno', '100272001', v_p, 1, 750), (v_new, v_org, v_m1 + 5, 'Paciente PU Dos', '100272002', v_p, 1, 750);

    v_before := app.preaudit_lot(v_new)::text like '%window%';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.merge_submissions(v_new, array[v_old], 'motivo de prueba QA');
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    v_after := app.preaudit_lot(v_new)::text like '%window%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · La preauditoría marca el plazo vencido solo después de unir','ok',coalesce(not v_before and v_after, false),'d',format('%s %s', v_before, v_after)));

    perform public.refresh_alerts();
    select a.due_on, a.title into v_d, v_t from public.alerts a where a.rule_code = 'ventana_radicacion' and a.entity_id = v_new and a.status <> 'completada';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · La alerta diaria usa el mes más antiguo','ok',coalesce(v_d = v_exp, false),'d',coalesce(v_t, 'sin alerta')));
    select count(*) into v_n from public.alerts a where a.entity_id = v_old and a.status <> 'completada';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · El lote vaciado no genera alertas','ok',v_n = 0,'d',v_n::text));

    select t.due_on into v_d from app.inbox_tasks(current_date) t where t.entity_id = v_new and t.task_type = 'captura_incompleta';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · La bandeja fecha las capturas incompletas desde el mes más antiguo','ok',coalesce(v_d = (v_m0 + interval '1 month')::date - 1, false),'d',v_d::text));

    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select w.due_on into v_d from public.work_queue() w where w.kind = 'ventana' and w.entity_id = v_new;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · La cola de trabajo usa el mes más antiguo','ok',coalesce(v_d = v_exp, false),'d',coalesce(v_d::text, 'sin fila') || ' · esperado ' || v_exp));
    select count(*) into v_n from public.work_queue() w where w.entity_id = v_old;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El lote vaciado no aparece en la cola de trabajo','ok',v_n = 0,'d',v_n::text));
    select count(*) into v_n from public.work_queue() w where w.entity_id = v_vacio and w.kind = 'borrador';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Un lote vacío que no vino de una unión sigue apareciendo','ok',v_n = 1,'d',v_n::text));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_old, v_org, v_m0 + 6, 'Paciente PU Tres', '100272003', v_p, 1, 750);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Si el lote vaciado recibe reclamaciones, vuelve a contar','ok',coalesce(not app.merged_away(v_old, (select s.notes from public.submissions s where s.id = v_old)), false),'d',null));
    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;
revoke execute on function app.qa_run_tests_plazos_unidas() from public, anon, authenticated;

delete from app.schema_migrations where version = '273';
insert into app.schema_migrations (version, report) values ('273', jsonb_build_object('tema', 'suite de la 272'));
