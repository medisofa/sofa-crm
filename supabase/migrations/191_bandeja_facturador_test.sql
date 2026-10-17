-- 191 · Suite de la 190 (bandeja única de trabajo del facturador, I59). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_bandeja();
create or replace function app.qa_run_tests_bandeja()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_oa constant uuid := '01900000-0000-4000-8000-000000000001'; v_ob constant uuid := '01900000-0000-4000-8000-000000000002'; v_oc constant uuid := '01900000-0000-4000-8000-000000000003'; v_ox constant uuid := '01900000-0000-4000-8000-000000000004'; v_op2 constant uuid := '01900000-0000-4000-8000-000000000005';
  v_pa constant uuid := '01900000-0000-4000-8000-000000000011'; v_pb constant uuid := '01900000-0000-4000-8000-000000000012'; v_pc constant uuid := '01900000-0000-4000-8000-000000000013'; v_px constant uuid := '01900000-0000-4000-8000-000000000014';
  v_sa constant text := '01900000-0000-4000-8000-000000000021'; v_ad constant text := '01900000-0000-4000-8000-000000000022'; v_ops constant text := '01900000-0000-4000-8000-000000000023'; v_b1 constant text := '01900000-0000-4000-8000-000000000024'; v_b2 constant text := '01900000-0000-4000-8000-000000000025'; v_b3 constant text := '01900000-0000-4000-8000-000000000026';
  v_gl constant text := '01900000-0000-4000-8000-000000000027'; v_au constant text := '01900000-0000-4000-8000-000000000028'; v_co constant text := '01900000-0000-4000-8000-000000000029'; v_ma constant text := '01900000-0000-4000-8000-000000000031'; v_sec constant text := '01900000-0000-4000-8000-000000000032'; v_mb constant text := '01900000-0000-4000-8000-000000000033';
  v_ax constant text := '01900000-0000-4000-8000-000000000034'; v_bx constant text := '01900000-0000-4000-8000-000000000035';
  v_ars uuid; v_proc uuid; v_t date; v_per date; v_old date; v_reason text;
  v_sa1 uuid; v_sa2 uuid; v_sa3 uuid; v_sa4 uuid; v_sa5 uuid; v_sb1 uuid; v_sb2 uuid; v_sc1 uuid; v_sx1 uuid; v_ga1 uuid; v_ga2 uuid; v_ga3 uuid; v_gb1 uuid; v_la3 uuid; v_la4 uuid; v_lb2 uuid; v_l uuid;
  v_r jsonb; v_n2 int; v_id uuid; v_rl text; v_d date;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '190') then
    raise exception 'Falta la migración 190. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    v_t := app.inbox_today(); v_per := date_trunc('month', v_t)::date; v_old := date_trunc('month', v_t - 100)::date;
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.ib.sa@sofa.test','x'),(v_ad::uuid,'qa.ib.ad@sofa.test','x'),(v_ops::uuid,'qa.ib.ops@sofa.test','x'),(v_b1::uuid,'qa.ib.b1@sofa.test','x'),(v_b2::uuid,'qa.ib.b2@sofa.test','x'),(v_b3::uuid,'qa.ib.b3@sofa.test','x'),(v_gl::uuid,'qa.ib.gl@sofa.test','x'),(v_au::uuid,'qa.ib.au@sofa.test','x'),(v_co::uuid,'qa.ib.co@sofa.test','x'),(v_ma::uuid,'qa.ib.ma@sofa.test','x'),(v_sec::uuid,'qa.ib.sec@sofa.test','x'),(v_mb::uuid,'qa.ib.mb@sofa.test','x'),(v_ax::uuid,'qa.ib.ax@sofa.test','x'),(v_bx::uuid,'qa.ib.bx@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ib.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_oa, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I59 A', '00000019001', 'Médico independiente', 'activo', current_date - 90, '8095559001');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_ob, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I59 B', '00000019002', 'Médico independiente', 'activo', current_date - 90, '8095559002');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_oc, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I59 C', '00000019003', 'Médico independiente', 'activo', current_date - 90, '8095559003');
    insert into public.organizations (id, kind, legal_name, tax_id, org_type, status, started_on) values (v_op2, 'operator', 'QA I59 Operador Dos', '00000019009', 'Operador', 'activo', current_date - 90);
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_ox, 'client', v_op2, 'QA I59 X', '00000019004', 'Médico independiente', 'activo', current_date - 90, '8095550004');
    -- El folio de reclamación es único en toda la base (índice service_lines_claim_folio_uq de producción) pero el contador es por operador: el segundo operador de la prueba arrancaría en el mismo número. Se adelanta su contador.
    insert into public.folio_counters (scope_id, kind, year, last_value) select v_op2, k, extract(year from current_date)::smallint, 900000 from unnest(array['REC','GLO','RAD','FAC','CON','PAG','PRV','REL','RET','SRV','HAB']) as k on conflict (scope_id, kind, year) do update set last_value = 900000;
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_oa, 'Dr. A QA', 'Cardiología', true), (v_pb, v_ob, 'Dr. B QA', 'Ortopedia', true),
      (v_pc, v_oc, 'Dr. C QA', 'Urología', true), (v_px, v_ox, 'Dr. X QA', 'Pediatría', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_b1::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_b2::uuid, 'billing', true),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_b3::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_gl::uuid, 'glosas', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_au::uuid, 'auditor', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_co::uuid, 'assistant', true),
      (v_oa, v_ma::uuid, 'client', true), (v_oa, v_sec::uuid, 'capturer', true), (v_ob, v_mb::uuid, 'client', true),
      (v_op2, v_ax::uuid, 'admin', true), (v_op2, v_bx::uuid, 'billing', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_pa, v_oa, true, true);
    insert into public.staff_client_access (user_id, client_org_id) values (v_b3::uuid, v_oa);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_ib_ars', 'ARS QA Bandeja', 'Contributivo', true) returning id into v_ars;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    select code into v_reason from public.glosa_reasons order by code limit 1;
    -- Lotes del cliente A: borrador con capturas incompletas, lote listo, dos radicados con saldo (70 y 35 días), uno cerrado
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars, v_per, 1, 'borrador') returning id into v_sa1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars, v_per, 2, 'borrador') returning id into v_sa2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_oa, v_pa, v_ars, v_old, 3, 'borrador', v_t - 70, 'RQA1', 'B0100000901') returning id into v_sa3;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_oa, v_pa, v_ars, v_old, 4, 'borrador', v_t - 35, 'RQA2', 'B0100000902') returning id into v_sa4;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_oa, v_pa, v_ars, v_old, 5, 'borrador', v_t - 120, 'RQA3', 'B0100000903') returning id into v_sa5;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_ob, v_pb, v_ars, v_per, 1, 'borrador') returning id into v_sb1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_ob, v_pb, v_ars, v_old, 2, 'borrador', v_t - 5, 'RQB1', 'B0100000904') returning id into v_sb2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oc, v_pc, v_ars, v_per, 1, 'borrador') returning id into v_sc1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_ox, v_px, v_ars, v_per, 1, 'borrador') returning id into v_sx1;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sa1, v_oa, v_per, 'Paciente QA 1', v_proc, 1, 100, null, 'AU1') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sa1, v_oa, v_per, 'Paciente QA 2', v_proc, 1, 100, 'M2', 'AU2') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    perform set_config('app.claim_change', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number, claim_status) values (v_sa1, v_oa, v_per, 'Paciente QA 3', v_proc, 1, 100, 'M3', 'AU3', 'con_inconsistencia') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sa2, v_oa, v_per, 'Paciente QA 4', v_proc, 1, 100, 'M4', 'AU4') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sa2, v_oa, v_per, 'Paciente QA 5', v_proc, 1, 100, 'M5', 'AU5') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sa3, v_oa, v_old, 'Paciente QA 6', v_proc, 1, 1000, 'M6', 'AU6') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    v_la3 := v_l;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sa4, v_oa, v_old, 'Paciente QA 7', v_proc, 1, 2000, 'M7', 'AU7') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    v_la4 := v_l;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sa5, v_oa, v_old, 'Paciente QA 8', v_proc, 1, 900, 'M8', 'AU8') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sb1, v_ob, v_per, 'Paciente QA 9', v_proc, 1, 100, 'M9', 'AU9') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sb2, v_ob, v_old, 'Paciente QA 10', v_proc, 1, 500, 'M10', 'AU10') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    v_lb2 := v_l;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sc1, v_oc, v_per, 'Paciente QA 11', v_proc, 1, 100, null, 'AU11') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sx1, v_ox, v_per, 'Paciente QA 12', v_proc, 1, 100, 'M12', 'AU12') returning id into v_l;
    perform set_config('app.contract_override', '', true); perform set_config('app.claim_change', '', true);
    perform set_config('app.status_change', 'on', true);
    update public.submissions set status = 'lista_para_radicar' where id in (v_sa2, v_sb1, v_sx1);
    update public.submissions set status = 'cerrada' where id = v_sa5;
    perform set_config('app.status_change', '', true);
    -- Glosas: A vencida (hace 20 días), A de hoy (800), A ya apelada, B vencida
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_sa3, v_t - 20, 'GLO-QA-IB1') returning id into v_ga1;
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_sa4, v_t, 'GLO-QA-IB2') returning id into v_ga2;
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_sa4, v_t - 3, 'GLO-QA-IB3') returning id into v_ga3;
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_ob, v_sb2, v_t - 12, 'GLO-QA-IB4') returning id into v_gb1;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_ga1, v_oa, v_la3, v_reason, 300), (v_ga2, v_oa, v_la4, v_reason, 800),
      (v_ga3, v_oa, v_la4, v_reason, 100), (v_gb1, v_ob, v_lb2, v_reason, 500);
    perform set_config('app.glosa_change', 'on', true);
    update public.glosas set status = 'analizada' where id = v_ga2;
    update public.glosas set status = 'apelada' where id = v_ga3;
    perform set_config('app.glosa_change', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-01 · La migración 190 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '190')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-02 · Las cuatro tablas de la bandeja no se tocan por la API: ni anon ni authenticated tienen permisos','ok',coalesce((not has_table_privilege('authenticated', 'public.inbox_assignments', 'select') and not has_table_privilege('authenticated', 'public.inbox_assignments', 'insert') and not has_table_privilege('authenticated', 'public.inbox_absences', 'update') and not has_table_privilege('authenticated', 'public.inbox_daily_close', 'delete') and not has_table_privilege('authenticated', 'public.inbox_params', 'update') and not has_table_privilege('anon', 'public.inbox_assignments', 'select') and not has_table_privilege('anon', 'public.inbox_daily_close', 'select')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-03 · Las funciones públicas de la bandeja no están abiertas a anon y sí a authenticated','ok',coalesce((not has_function_privilege('anon', 'public.inbox_my(text)', 'execute') and not has_function_privilege('anon', 'public.inbox_supervisor()', 'execute') and not has_function_privilege('anon', 'public.inbox_assignment_save(uuid,uuid,text,text)', 'execute') and not has_function_privilege('anon', 'public.inbox_overdue_report(date,date)', 'execute') and has_function_privilege('authenticated', 'public.inbox_my(text)', 'execute') and has_function_privilege('authenticated', 'public.inbox_absence_save(uuid,date,date,uuid,text)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-04 · Las funciones internas (cola, resolución, cierre) no se llaman desde la API','ok',coalesce((not has_function_privilege('authenticated', 'app.inbox_tasks(date)', 'execute') and not has_function_privilege('authenticated', 'app.inbox_effective(uuid,text,date)', 'execute') and not has_function_privilege('authenticated', 'app.inbox_close_day(date)', 'execute') and not has_function_privilege('anon', 'app.inbox_role()', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-05 · Todas las funciones de la bandeja son SECURITY DEFINER con search_path vacío (salvo las de formato)','ok',coalesce((not exists (select 1 from pg_proc p where p.pronamespace in ('app'::regnamespace, 'public'::regnamespace) and p.proname like 'inbox\_%' and p.proname not in ('inbox_today','inbox_types','inbox_type_label') and (not p.prosecdef or p.proconfig is null or not ('search_path=' = any (p.proconfig) or 'search_path=""' = any (p.proconfig))))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-06 · La fecha de hoy es la de República Dominicana (no la del servidor en UTC)','ok',coalesce((app.inbox_today() = (now() at time zone 'America/Santo_Domingo')::date), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-07 · Cliente A: 6 tareas (1 captura incompleta, 1 lote por radicar, 2 cobros y 2 glosas); la glosa ya apelada y el lote cerrado no cuentan','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa) = 6 and (select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.task_type = 'captura_incompleta') = 1 and (select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.task_type = 'lote_por_radicar') = 1 and (select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.task_type = 'cobro_escalar') = 2 and (select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.task_type = 'glosa_responder') = 2 and not exists (select 1 from app.inbox_tasks() t where t.entity_id in (v_ga3, v_sa5))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-08 · Captura incompleta: cuenta solo las 2 reclamaciones con problema (sin afiliado y con inconsistencia), con el detalle y el monto','ok',coalesce((exists (select 1 from app.inbox_tasks() t where t.entity_id = v_sa1 and t.task_type = 'captura_incompleta' and t.detail = 'Faltan datos en 2 captura(s): 1 sin afiliado, 1 con inconsistencia' and t.amount = 200)), false),'d',((select t.detail from app.inbox_tasks() t where t.entity_id = v_sa1))::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-09 · Un lote con todas sus capturas completas no aparece como captura incompleta','ok',coalesce((not exists (select 1 from app.inbox_tasks() t where t.entity_id = v_sa2 and t.task_type = 'captura_incompleta')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-10 · Lote por radicar: el lote «Lista para radicar» sale con sus 2 servicios y su monto','ok',coalesce((exists (select 1 from app.inbox_tasks() t where t.entity_id = v_sa2 and t.task_type = 'lote_por_radicar' and t.detail like 'Lista para radicar · 2 servicio(s)%' and t.amount = 200)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-11 · El vencimiento de captura y de lote es el fin del período más la ventana de radicación','ok',coalesce(((select t.due_on from app.inbox_tasks() t where t.entity_id = v_sa1) = (v_per + interval '1 month')::date - 1 + coalesce((select submission_window_days from public.app_settings where operator_id = '00000000-0000-4000-8000-000000000001'::uuid), 30)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-12 · Glosa sin responder: vence a los 7 días hábiles de notificada (plazo de la 144) y la de hace 20 días ya está vencida y crítica','ok',coalesce(((select t.due_on from app.inbox_tasks() t where t.entity_id = v_ga1) = app.add_business_days(v_t - 20, 7) and (select t.priority from app.inbox_tasks() t where t.entity_id = v_ga1) = 'critica' and (select t.days_late from app.inbox_tasks() t where t.entity_id = v_ga1) = v_t - app.add_business_days(v_t - 20, 7) and (select t.amount from app.inbox_tasks() t where t.entity_id = v_ga1) = 300), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-13 · Glosa notificada hoy: no vence todavía y queda en prioridad normal','ok',coalesce(((select t.priority from app.inbox_tasks() t where t.entity_id = v_ga2) = 'normal' and (select t.days_late from app.inbox_tasks() t where t.entity_id = v_ga2) < 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_d := app.add_business_days(v_t, 7);
      insert into public.holidays (day, name) values (v_d, 'Feriado de prueba QA') on conflict (day) do nothing;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-14 · El plazo cuenta días hábiles con feriados: un feriado justo en la fecha de vencimiento la corre un día hábil','ok',coalesce(((select t.due_on from app.inbox_tasks() t where t.entity_id = v_ga2) = app.add_business_days(v_t, 7) and (select t.due_on from app.inbox_tasks() t where t.entity_id = v_ga2) > v_d), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-15 · Cobro a 70 días sin escalar: toca escalamiento, vence a los 61 días más 5 de gracia y ya está vencido (crítico)','ok',coalesce((exists (select 1 from app.inbox_tasks() t where t.entity_id = v_sa3 and t.task_type = 'cobro_escalar' and t.due_on = v_t - 70 + 61 + 5 and t.days_late = 4 and t.priority = 'critica' and t.amount = 1000 and t.detail like '70 días%Escalamiento a la gerencia de red%')), false),'d',((select t.detail from app.inbox_tasks() t where t.entity_id = v_sa3))::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-16 · Cobro a 35 días: toca la reclamación formal y, por vencer mañana, queda en prioridad alta','ok',coalesce((exists (select 1 from app.inbox_tasks() t where t.entity_id = v_sa4 and t.due_on = v_t + 1 and t.priority = 'alta' and t.amount = 2000 and t.detail like '%Reclamación formal%')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-17 · Un lote radicado hace 5 días (seguimiento) y el lote cerrado no generan cobro por escalar','ok',coalesce((not exists (select 1 from app.inbox_tasks() t where t.entity_id in (v_sb2, v_sa5) and t.task_type = 'cobro_escalar')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.collection_actions (organization_id, ars_id, submission_ids, kind) values (v_oa, v_ars, array[v_sa3], 'reclamacion_formal');
      select count(*) into v_n from app.inbox_tasks() t where t.entity_id = v_sa3 and t.task_type = 'cobro_escalar';
      insert into public.collection_actions (organization_id, ars_id, submission_ids, kind) values (v_oa, v_ars, array[v_sa3], 'escalamiento');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-18 · Al registrar la gestión de la etapa (146), el cobro sale de la bandeja; una gestión de otra etapa no lo saca','ok',coalesce((v_n = 1 and not exists (select 1 from app.inbox_tasks() t where t.entity_id = v_sa3 and t.task_type = 'cobro_escalar')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform set_config('app.glosa_change', 'on', true); update public.glosas set status = 'apelada' where id = v_ga1; perform set_config('app.glosa_change', '', true);
      update public.service_lines set member_number = 'M-ARREGLADO' where submission_id = v_sa1 and member_number is null;
      perform set_config('app.claim_change', 'on', true); update public.service_lines set claim_status = 'capturada' where submission_id = v_sa1 and claim_status = 'con_inconsistencia'; perform set_config('app.claim_change', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-19 · Al responder la glosa (queda apelada) sale de la bandeja y al completar la captura el lote deja de ser captura incompleta','ok',coalesce((not exists (select 1 from app.inbox_tasks() t where t.entity_id in (v_ga1, v_sa1))), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-20 · Orden: crítica primero (la más vencida arriba), luego alta, luego normal','ok',coalesce(((select array_agg(t.entity_id order by t.prio_rank, t.due_on, t.amount desc) from app.inbox_tasks() t where t.organization_id = v_oa and t.task_type in ('glosa_responder','cobro_escalar'))[1:3] = array[v_ga1, v_sa3, v_sa4]), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.inbox_params_set(5, 2, 500);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-21 · Monto alto: una glosa normal pasa a prioridad alta cuando el monto llega al umbral del parámetro','ok',coalesce(((select t.priority from app.inbox_tasks() t where t.entity_id = v_ga2) = 'alta' and (select t.priority from app.inbox_tasks() t where t.entity_id = v_ga1) = 'critica'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.inbox_params_set(0, 2, 50000);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-22 · Los días de gracia del cobro son un parámetro: con 0 días el escalamiento vence a los 61 días justos','ok',coalesce(((select t.due_on from app.inbox_tasks() t where t.entity_id = v_sa3) = v_t - 70 + 61 and (select t.days_late from app.inbox_tasks() t where t.entity_id = v_sa3) = 9), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.inbox_params_set(5, 0, 50000);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-23 · Los días de «vence pronto» son un parámetro: con 0 días el cobro que vence mañana vuelve a prioridad normal','ok',coalesce(((select t.priority from app.inbox_tasks() t where t.entity_id = v_sa4) = 'normal'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.organizations set status = 'inactivo' where id = v_oc;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-24 · Un cliente inactivo no genera tareas','ok',coalesce((not exists (select 1 from app.inbox_tasks() t where t.organization_id = v_oc)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-25 · Los clientes sin asignación dejan sus tareas «sin responsable» con la causa','ok',coalesce((exists (select 1 from app.inbox_tasks() t where t.organization_id = v_oc and t.assignee_id is null and t.unassigned_reason = 'sin_asignacion')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_my();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-26 · ATAQUE: El Médico no abre la bandeja','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-26 · ATAQUE: El Médico no abre la bandeja','ok',sqlerrm like 'La bandeja de trabajo es del equipo de Facturación%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_my();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-27 · ATAQUE: El Médico de otro consultorio no abre la bandeja','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-27 · ATAQUE: El Médico de otro consultorio no abre la bandeja','ok',sqlerrm like 'La bandeja de trabajo es del equipo de Facturación%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_my();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-28 · ATAQUE: La Secretaria no abre la bandeja','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-28 · ATAQUE: La Secretaria no abre la bandeja','ok',sqlerrm like 'La bandeja de trabajo es del equipo de Facturación%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_my();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-29 · ATAQUE: Cobros, conciliación y glosas no abre la bandeja','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-29 · ATAQUE: Cobros, conciliación y glosas no abre la bandeja','ok',sqlerrm like 'La bandeja de trabajo es del equipo de Facturación%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_my();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-30 · ATAQUE: Auditoría no abre la bandeja','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-30 · ATAQUE: Auditoría no abre la bandeja','ok',sqlerrm like 'La bandeja de trabajo es del equipo de Facturación%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_my();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-31 · ATAQUE: El Comercial no abre la bandeja','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-31 · ATAQUE: El Comercial no abre la bandeja','ok',sqlerrm like 'La bandeja de trabajo es del equipo de Facturación%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_supervisor();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-32 · ATAQUE: el Médico no ve la carga por persona','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-32 · ATAQUE: el Médico no ve la carga por persona','ok',sqlerrm like 'La carga por persona la ven%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_overdue_report();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-33 · ATAQUE: el Médico no ve el indicador de vencidas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-33 · ATAQUE: el Médico no ve el indicador de vencidas','ok',sqlerrm like 'El indicador de tareas vencidas es del equipo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignments_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-34 · ATAQUE: el Médico no ve las asignaciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-34 · ATAQUE: el Médico no ve las asignaciones','ok',sqlerrm like 'Las asignaciones las ven%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_supervisor();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-35 · ATAQUE: Facturación no ve la carga por persona de los demás','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-35 · ATAQUE: Facturación no ve la carga por persona de los demás','ok',sqlerrm like 'La carga por persona la ven%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignments_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-36 · ATAQUE: Facturación no ve la lista de asignaciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-36 · ATAQUE: Facturación no ve la lista de asignaciones','ok',sqlerrm like 'Las asignaciones las ven%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absences_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-37 · ATAQUE: Facturación no ve las ausencias de los demás','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-37 · ATAQUE: Facturación no ve las ausencias de los demás','ok',sqlerrm like 'Las ausencias las ven%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_params_get();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-38 · ATAQUE: Facturación no ve los parámetros','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-38 · ATAQUE: Facturación no ve los parámetros','ok',sqlerrm like 'Los parámetros de la bandeja los ven%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignment_save(v_oa, v_b1::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-39 · ATAQUE: Facturación no se asigna clientes a sí misma','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-39 · ATAQUE: Facturación no se asigna clientes a sí misma','ok',sqlerrm like 'Solo el Super Admin, el Administrador u Operaciones asignan clientes%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_b1::uuid, v_t, v_t + 1, v_b2::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-40 · ATAQUE: Facturación no registra ausencias ni las suyas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-40 · ATAQUE: Facturación no registra ausencias ni las suyas','ok',sqlerrm like 'Solo el Super Admin, el Administrador u Operaciones registran ausencias%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_close_day_now();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-41 · ATAQUE: Facturación no cierra el día de la bandeja','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-41 · ATAQUE: Facturación no cierra el día de la bandeja','ok',sqlerrm like 'Solo el Super Admin o el Administrador cierran el día%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.inbox_assignments (organization_id, assignee_id) values (v_oc, v_b1::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-42 · ATAQUE: la API no deja insertar asignaciones directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-42 · ATAQUE: la API no deja insertar asignaciones directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      delete from public.inbox_absences where true;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-43 · ATAQUE: la API no deja borrar ausencias directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-43 · ATAQUE: la API no deja borrar ausencias directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      update public.inbox_params set high_amount = 1 where true;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-44 · ATAQUE: la API no deja cambiar los parámetros directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-44 · ATAQUE: la API no deja cambiar los parámetros directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_assignment_save(v_oa, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-45 · Asignar sin elegir persona dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-45 · Asignar sin elegir persona dice qué hacer','ok',sqlerrm like 'Elija a la persona de Facturación%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignment_save(v_oa, v_b1::uuid, 'tipo_raro');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-46 · Asignar un tipo de tarea inválido lo rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-46 · Asignar un tipo de tarea inválido lo rechaza','ok',sqlerrm like 'Tipo de tarea no válido%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignment_save(v_oa, v_gl::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-47 · ATAQUE: no se asigna a alguien que no es de Facturación (rol Glosas)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-47 · ATAQUE: no se asigna a alguien que no es de Facturación (rol Glosas)','ok',sqlerrm like 'La persona elegida no es de Facturación activa%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignment_save(v_oa, v_ma::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-48 · ATAQUE: no se asigna al Médico del cliente como responsable','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-48 · ATAQUE: no se asigna al Médico del cliente como responsable','ok',sqlerrm like 'La persona elegida no es de Facturación activa%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignment_save(v_oa, v_bx::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-49 · ATAQUE: no se asigna a un facturador de otro operador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-49 · ATAQUE: no se asigna a un facturador de otro operador','ok',sqlerrm like 'La persona elegida no es de Facturación activa%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignment_save('00000000-0000-4000-8000-000000000001'::uuid, v_b1::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-50 · ATAQUE: no se asigna la organización de SOFA como si fuera un cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-50 · ATAQUE: no se asigna la organización de SOFA como si fuera un cliente','ok',sqlerrm like 'Cliente no encontrado o sin acceso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignment_save(v_ox, v_b1::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-51 · ATAQUE: un cliente de otro operador no se asigna (el Administrador de SOFA no lo ve)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-51 · ATAQUE: un cliente de otro operador no se asigna (el Administrador de SOFA no lo ve)','ok',sqlerrm like 'Cliente no encontrado o sin acceso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignment_save(v_ob, v_b3::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-52 · ATAQUE: no se asigna a una persona cuyo acceso está limitado a otros clientes, y dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-52 · ATAQUE: no se asigna a una persona cuyo acceso está limitado a otros clientes, y dice qué hacer','ok',sqlerrm like 'Esa persona no tiene acceso a ese cliente%','d',left(sqlerrm,120)));
    end;
    v_r := public.inbox_assignment_save(v_oa, v_b1::uuid, null, 'Cliente fijo de Facturación 1');
    perform public.inbox_assignment_save(v_oa, v_b2::uuid, 'glosa_responder', 'Las glosas de este cliente las lleva la segunda');
    perform public.inbox_assignment_save(v_ob, v_b2::uuid);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-53 · Cliente fijo: el cliente A queda asignado a Facturación 1 (todos los tipos) y su respuesta no trae asignación previa','ok',coalesce((v_r->>'assignee_id' = v_b1 and v_r->>'previous_assignee' is null and (select count(*) from public.inbox_assignments where organization_id = v_oa and is_active) = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-54 · El tipo manda sobre el cliente: las glosas de A van a Facturación 2 y lo demás de A a Facturación 1','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id = v_b2::uuid and t.task_type = 'glosa_responder') = 2 and (select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id = v_b1::uuid and t.task_type <> 'glosa_responder') = 4 and (select count(*) from app.inbox_tasks() t where t.organization_id = v_ob and t.assignee_id = v_b2::uuid) = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_assignment_save(v_oa, v_b1::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-55 · Repetir la misma asignación no hace nada y lo dice','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-55 · Repetir la misma asignación no hace nada y lo dice','ok',sqlerrm like 'Ese cliente ya está asignado a esa persona%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      insert into public.inbox_assignments (organization_id, assignee_id, task_type) values (v_oa, v_b2::uuid, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-56 · ATAQUE: dos asignaciones activas del mismo cliente y tipo no caben (inserción directa del SQL Editor)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-56 · ATAQUE: dos asignaciones activas del mismo cliente y tipo no caben (inserción directa del SQL Editor)','ok',sqlerrm like '%duplicate key%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.inbox_assignments (organization_id, assignee_id, task_type) values (v_oc, v_gl::uuid, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-57 · ATAQUE: inserción directa con alguien que no es de Facturación se rechaza en la base','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-57 · ATAQUE: inserción directa con alguien que no es de Facturación se rechaza en la base','ok',sqlerrm like 'La persona elegida no es de Facturación activa%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.inbox_assignments (organization_id, assignee_id) values ('00000000-0000-4000-8000-000000000001'::uuid, v_b1::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-58 · ATAQUE: inserción directa para la organización de SOFA se rechaza en la base','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-58 · ATAQUE: inserción directa para la organización de SOFA se rechaza en la base','ok',sqlerrm like 'La bandeja se asigna por cliente%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.inbox_assignment_save(v_oa, v_b2::uuid, null, 'Reasignado por carga de trabajo');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-59 · Reasignar un cliente: la asignación anterior queda cerrada (historial) y solo hay una activa','ok',coalesce((v_r->>'previous_assignee' = v_b1 and (select count(*) from public.inbox_assignments where organization_id = v_oa and task_type is null and is_active) = 1 and exists (select 1 from public.inbox_assignments where organization_id = v_oa and task_type is null and not is_active and assignee_id = v_b1::uuid and ended_at is not null) and (select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id = v_b2::uuid) = 6), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      select id into v_id from public.inbox_assignments where organization_id = v_oa and task_type = 'glosa_responder' and is_active;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.inbox_assignment_remove(v_id);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-60 · Operaciones también asigna; quitar la asignación del tipo devuelve las glosas al responsable general del cliente','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id = v_b1::uuid) = 6 and not (select is_active from public.inbox_assignments where id = v_id)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      select id into v_id from public.inbox_assignments where organization_id = v_ob and is_active;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.inbox_assignment_remove(v_id);
      begin perform public.inbox_assignment_remove(v_id); v_n := 0; exception when others then v_n := case when sqlerrm like 'Asignación no encontrada o ya quitada%' then 1 else 0 end; end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-61 · Quitar una asignación que ya se quitó dice que actualice la lista','ok',coalesce((v_n = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.organization_users set is_active = false where user_id = v_b1::uuid and organization_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-62 · Una persona dada de baja deja sus tareas «sin responsable» con la causa (no se pierden)','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id is null and t.unassigned_reason = 'persona_no_disponible' and t.task_type <> 'glosa_responder') = 4 and not exists (select 1 from app.inbox_tasks() t where t.assignee_id = v_b1::uuid)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.inbox_assignments set is_active = false where organization_id = v_oa and is_active;
      insert into public.inbox_assignments (organization_id, assignee_id) values (v_oa, v_b3::uuid);
      update public.staff_client_access set client_org_id = v_ob where user_id = v_b3::uuid;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-63 · Si a la persona le limitan el acceso a otros clientes, lo que atendía queda «sin responsable»','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.unassigned_reason = 'persona_no_disponible') = 6), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.inbox_my();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-64 · Facturación 1 ve solo lo suyo: 4 tareas del cliente A (sin las glosas, que van a Facturación 2, ni lo de B ni lo sin asignar)','ok',coalesce((v_r->>'view' = 'propia' and (v_r->'totals'->>'total')::int = 4 and not exists (select 1 from jsonb_array_elements(v_r->'tasks') x where x->>'client' <> 'QA I59 A') and not exists (select 1 from jsonb_array_elements(v_r->'tasks') x where x->>'type' = 'glosa_responder')), false),'d',(v_r->'totals')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-65 · Mi bandeja trae los contadores de los 4 tipos con totales y vencidas','ok',coalesce((jsonb_array_length(v_r->'counts') = 4 and (select (c->>'total')::int from jsonb_array_elements(v_r->'counts') c where c->>'type' = 'captura_incompleta') = 1 and (select (c->>'total')::int from jsonb_array_elements(v_r->'counts') c where c->>'type' = 'cobro_escalar') = 2 and (select (c->>'overdue')::int from jsonb_array_elements(v_r->'counts') c where c->>'type' = 'cobro_escalar') = 1 and (select (c->>'total')::int from jsonb_array_elements(v_r->'counts') c where c->>'type' = 'glosa_responder') = 0 and (v_r->'totals'->>'overdue')::int = 1), false),'d',(v_r->'counts')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-66 · Las tareas vienen ordenadas: la crítica (cobro vencido) primero, luego la alta y luego las normales','ok',coalesce((v_r->'tasks'->0->>'priority' = 'critica' and v_r->'tasks'->0->>'entity_id' = v_sa3::text and v_r->'tasks'->1->>'priority' = 'alta' and v_r->'tasks'->2->>'priority' = 'normal'), false),'d',(v_r->'tasks'->>0)::text));
    perform set_config('role', v_rl, true);
    v_r := public.inbox_my('cobro_escalar');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-67 · Filtrar por tipo muestra solo ese tipo, y los contadores siguen completos','ok',coalesce((jsonb_array_length(v_r->'tasks') = 2 and not exists (select 1 from jsonb_array_elements(v_r->'tasks') x where x->>'type' <> 'cobro_escalar') and (v_r->'totals'->>'total')::int = 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.inbox_my('cualquier_cosa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-68 · Un tipo inválido dice cuáles hay','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-68 · Un tipo inválido dice cuáles hay','ok',sqlerrm like 'Tipo de tarea no válido%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b2, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.inbox_my();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-69 · Facturación 2 ve sus 4 tareas: las 2 glosas de A (por tipo) y las 2 del cliente B, y nada de lo de Facturación 1','ok',coalesce(((v_r->'totals'->>'total')::int = 4 and (select count(*) from jsonb_array_elements(v_r->'tasks') x where x->>'client' = 'QA I59 B') = 2 and (select count(*) from jsonb_array_elements(v_r->'tasks') x where x->>'type' = 'glosa_responder' and x->>'client' = 'QA I59 A') = 2 and (v_r->'totals'->>'overdue')::int = 2), false),'d',(v_r->'totals')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b3, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.inbox_my();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-70 · Facturación 3 (sin clientes asignados) ve la bandeja vacía, aunque haya miles de tareas de otros','ok',coalesce(((v_r->'totals'->>'total')::int = 0 and jsonb_array_length(v_r->'tasks') = 0 and jsonb_array_length(v_r->'counts') = 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.inbox_my();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-71 · El Administrador ve todo (vista «todo»): tareas de A, B y C de la prueba, con las de C sin responsable, y ninguna del otro operador','ok',coalesce((v_r->>'view' = 'todo' and exists (select 1 from jsonb_array_elements(v_r->'tasks') x where x->>'client' = 'QA I59 C' and x->>'assignee' is null and x->>'unassigned_reason' = 'sin_asignacion') and (select count(*) from jsonb_array_elements(v_r->'tasks') x where x->>'client' in ('QA I59 A','QA I59 B')) = 8 and not exists (select 1 from jsonb_array_elements(v_r->'tasks') x where x->>'client' = 'QA I59 X')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.inbox_my();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-72 · El Super Admin ve lo mismo que el Administrador','ok',coalesce((v_r->>'view' = 'todo' and (select count(*) from jsonb_array_elements(v_r->'tasks') x where x->>'client' like 'QA I59%') = 9), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.inbox_my();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-73 · Operaciones ve todo','ok',coalesce((v_r->>'view' = 'todo' and (select count(*) from jsonb_array_elements(v_r->'tasks') x where x->>'client' like 'QA I59%') = 9 and not (v_r->'totals'->>'total')::int < 9), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.staff_client_access (user_id, client_org_id) values (v_ops::uuid, v_ob);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.inbox_my();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-74 · Operaciones con acceso limitado a un solo cliente ve solo ese cliente (nada de los demás)','ok',coalesce(((v_r->'totals'->>'total')::int = 2 and not exists (select 1 from jsonb_array_elements(v_r->'tasks') x where x->>'client' <> 'QA I59 B')), false),'d',(v_r->'totals')::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.inbox_assignment_save(v_ox, v_bx::uuid, null, 'Cliente fijo del segundo operador');
    v_x := public.inbox_my();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-75 · El Administrador del otro operador asigna y ve solo su cliente (nada del A, B ni C)','ok',coalesce((v_r->>'assignee_id' = v_bx and (v_x->'totals'->>'total')::int = 1 and v_x->'tasks'->0->>'client' = 'QA I59 X'), false),'d',(v_x->'totals')::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.inbox_assignment_save(v_oa, v_bx::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-76 · ATAQUE: el Administrador del otro operador no asigna clientes de SOFA','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-76 · ATAQUE: el Administrador del otro operador no asigna clientes de SOFA','ok',sqlerrm like 'Cliente no encontrado o sin acceso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_assignment_save(v_ox, v_b1::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-77 · ATAQUE: no asigna a un facturador del operador de SOFA a su cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-77 · ATAQUE: no asigna a un facturador del operador de SOFA a su cliente','ok',sqlerrm like 'La persona elegida no es de Facturación activa%','d',left(sqlerrm,120)));
    end;
    v_x := public.inbox_assignments_list();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-78 · La lista de asignaciones del otro operador no muestra las de SOFA y sus facturadores son los suyos','ok',coalesce((jsonb_array_length(v_x->'assignments') = 1 and v_x->'assignments'->0->>'client' = 'QA I59 X' and jsonb_array_length(v_x->'billers') = 1 and v_x->'billers'->0->>'user_id' = v_bx), false),'d',(v_x)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bx, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.inbox_my();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-79 · El facturador del otro operador ve su tarea y nada del operador de SOFA','ok',coalesce(((v_x->'totals'->>'total')::int = 1 and v_x->'tasks'->0->>'entity_id' = v_sx1::text), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.inbox_assignments_list();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-80 · La lista de asignaciones de SOFA muestra las suyas, no la del otro operador, y marca el cliente C como sin cubrir','ok',coalesce((not exists (select 1 from jsonb_array_elements(v_x->'assignments') a where a->>'client' = 'QA I59 X') and exists (select 1 from jsonb_array_elements(v_x->'assignments') a where a->>'client' = 'QA I59 A' and a->>'task_type' = 'glosa_responder') and exists (select 1 from jsonb_array_elements(v_x->'uncovered') u where u->>'client' = 'QA I59 C' and jsonb_array_length(u->'missing') = 4) and not exists (select 1 from jsonb_array_elements(v_x->'uncovered') u where u->>'client' = 'QA I59 A')), false),'d',(v_x->'uncovered')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_absence_save(v_b1::uuid, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-81 · Ausencia sin fechas dice qué indicar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-81 · Ausencia sin fechas dice qué indicar','ok',sqlerrm like 'Indique la fecha en que empieza%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_b1::uuid, v_t + 3, v_t + 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-82 · Fechas invertidas: pide corregirlas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-82 · Fechas invertidas: pide corregirlas','ok',sqlerrm like 'La fecha final no puede ser anterior%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_b1::uuid, v_t - 10, v_t - 3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-83 · Una ausencia que ya terminó no se registra','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-83 · Una ausencia que ya terminó no se registra','ok',sqlerrm like 'Esa ausencia ya terminó%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_b1::uuid, v_t, v_t + 200);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-84 · Una ausencia no pasa de 180 días','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-84 · Una ausencia no pasa de 180 días','ok',sqlerrm like 'Una ausencia no puede pasar de 180 días%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_b1::uuid, v_t, v_t + 2, v_b1::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-85 · ATAQUE: la persona no puede ser su propio suplente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-85 · ATAQUE: la persona no puede ser su propio suplente','ok',sqlerrm like 'La persona no puede ser su propio suplente%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_b1::uuid, v_t, v_t + 2, v_gl::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-86 · ATAQUE: el suplente debe ser de Facturación (no el rol Glosas)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-86 · ATAQUE: el suplente debe ser de Facturación (no el rol Glosas)','ok',sqlerrm like 'El suplente debe ser una persona de Facturación%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_gl::uuid, v_t, v_t + 2, v_b2::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-87 · ATAQUE: no se registra ausencia a alguien que no es de Facturación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-87 · ATAQUE: no se registra ausencia a alguien que no es de Facturación','ok',sqlerrm like 'Persona no encontrada o sin acceso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_bx::uuid, v_t, v_t + 2, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-88 · ATAQUE: no se registra ausencia a un facturador de otro operador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-88 · ATAQUE: no se registra ausencia a un facturador de otro operador','ok',sqlerrm like 'Persona no encontrada o sin acceso%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      insert into public.inbox_absences (user_id, starts_on, ends_on) values (v_gl::uuid, v_t, v_t + 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-89 · ATAQUE: inserción directa de una ausencia de alguien que no es de Facturación se rechaza en la base','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-89 · ATAQUE: inserción directa de una ausencia de alguien que no es de Facturación se rechaza en la base','ok',sqlerrm like 'Las ausencias se registran para personas de Facturación%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.inbox_absence_save(v_b1::uuid, v_t, v_t + 3, v_b2::uuid, 'Vacaciones de prueba');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-90 · Ausencia con suplente: el registro dice cuántas tareas se mueven (4) y no trae advertencias','ok',coalesce(((v_r->>'tasks_now')::int = 4 and jsonb_array_length(v_r->'warnings') = 0), false),'d',(v_r::text)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-91 · Mientras Facturación 1 falta, sus 4 tareas las atiende Facturación 2 como suplente (la glosa ya era suya por tipo)','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id = v_b2::uuid and t.substituted) = 4 and (select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id = v_b2::uuid) = 6 and not exists (select 1 from app.inbox_tasks() t where t.assignee_id = v_b1::uuid) and (select count(distinct t.assigned_to) from app.inbox_tasks() t where t.organization_id = v_oa and t.substituted) = 1), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_my();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-92 · El ausente abre su bandeja: vacía, y le avisa su ausencia con el nombre del suplente','ok',coalesce(((v_x->'totals'->>'total')::int = 0 and (v_x->'my_absence'->>'in_progress')::boolean and v_x->'my_absence'->>'backup' like '%b2%'), false),'d',(v_x->'my_absence')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b2, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_my();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-93 · El suplente ve lo del ausente marcado como «cubriendo» y la lista de a quién cubre','ok',coalesce(((v_x->'totals'->>'total')::int = 8 and (select count(*) from jsonb_array_elements(v_x->'tasks') t where (t->>'covering')::boolean) = 4 and jsonb_array_length(v_x->'covering') = 1 and v_x->'covering'->0->>'name' like '%b1%'), false),'d',(v_x->'covering')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_supervisor();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-94 · La vista del supervisor muestra al ausente con su suplente y al suplente con la carga que cubre','ok',coalesce(((select p->'absent'->>'backup' from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b1) like '%b2%' and (select (p->>'total')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b1) = 0 and (select (p->>'covering_tasks')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b2) = 4 and jsonb_array_length((select p->'covers' from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b2)) = 1), false),'d',(null)::text));
    begin
      perform public.inbox_absence_save(v_b1::uuid, v_t + 1, v_t + 5, v_b3::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-95 · Una segunda ausencia que se traslapa con la primera se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-95 · Una segunda ausencia que se traslapa con la primera se rechaza','ok',sqlerrm like 'Esa persona ya tiene una ausencia registrada que se traslapa%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_b2::uuid, v_t + 1, v_t + 2, v_b3::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-96 · ATAQUE: el suplente no puede ausentarse mientras cubre a otro (hay que cambiar primero la suplencia)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-96 · ATAQUE: el suplente no puede ausentarse mientras cubre a otro (hay que cambiar primero la suplencia)','ok',sqlerrm like 'Esa persona cubre la ausencia de%Cambie primero esa suplencia%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_absence_save(v_b3::uuid, v_t + 1, v_t + 2, v_b1::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-97 · ATAQUE: no se nombra suplente a alguien que también estará ausente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-97 · ATAQUE: no se nombra suplente a alguien que también estará ausente','ok',sqlerrm like '%también estará ausente en esas fechas%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-98 · Pasado el último día de la ausencia todo vuelve solo a su responsable (sin tocar nada)','ok',coalesce(((select r_effective from app.inbox_effective(v_oa, 'cobro_escalar', v_t + 4)) = v_b1::uuid and (select r_effective from app.inbox_effective(v_oa, 'cobro_escalar', v_t + 3)) = v_b2::uuid and (select r_effective from app.inbox_effective(v_oa, 'cobro_escalar', v_t - 1)) = v_b1::uuid), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_absences_list();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-99 · La lista de ausencias muestra la ausencia «en curso» con su suplente','ok',coalesce((jsonb_array_length(v_x) >= 1 and exists (select 1 from jsonb_array_elements(v_x) a where a->>'status' = 'en_curso' and a->>'user_id' = v_b1 and a->>'backup' like '%b2%')), false),'d',(v_x::text)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      select id into v_id from public.inbox_absences where user_id = v_b1::uuid and is_active;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.inbox_absence_cancel(v_id);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-100 · Cancelar la ausencia devuelve el trabajo a su responsable de inmediato','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id = v_b1::uuid) = 4 and not exists (select 1 from app.inbox_tasks() t where t.substituted)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_absence_cancel(v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-101 · Cancelar dos veces dice que actualice la lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-101 · Cancelar dos veces dice que actualice la lista','ok',sqlerrm like 'Ausencia no encontrada o ya cancelada%','d',left(sqlerrm,120)));
    end;
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.inbox_absence_save(v_b1::uuid, v_t, v_t + 2);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-102 · Ausencia SIN suplente: sus tareas quedan «sin responsable» por ausencia y el registro lo advierte','ok',coalesce((jsonb_array_length(v_r->'warnings') = 1 and v_r->'warnings'->>0 like 'Sin suplente%' and (select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.unassigned_reason = 'ausente_sin_suplente') = 4 and not exists (select 1 from app.inbox_tasks() t where t.assignee_id = v_b1::uuid)), false),'d',(v_r::text)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.inbox_absences (user_id, starts_on, ends_on, backup_id) values (v_b1::uuid, v_t, v_t + 2, v_b2::uuid);
      update public.organization_users set is_active = false where user_id = v_b2::uuid and organization_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-103 · Si el suplente deja de estar activo, lo del ausente queda «sin responsable» (no se pierde)','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.unassigned_reason = 'ausente_sin_suplente' and t.task_type <> 'glosa_responder') = 4), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.inbox_absences (user_id, starts_on, ends_on, backup_id) values (v_b1::uuid, v_t + 1, v_t + 5, v_b2::uuid);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-104 · Una ausencia que empieza mañana no cambia nada hoy','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id = v_b1::uuid) = 4 and (select r_effective from app.inbox_effective(v_oa, 'cobro_escalar', v_t + 1)) = v_b2::uuid), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.inbox_absences (user_id, starts_on, ends_on, backup_id) values (v_b1::uuid, v_t - 6, v_t - 1, v_b2::uuid);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-105 · Una ausencia que ya terminó (registrada en la base) no cambia nada','ok',coalesce(((select count(*) from app.inbox_tasks() t where t.organization_id = v_oa and t.assignee_id = v_b1::uuid) = 4), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.inbox_supervisor();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-106 · Carga por persona: Facturación 1 con 4 tareas (1 vencida) y Facturación 2 con 4 (2 vencidas); Facturación 3 aparece con cero','ok',coalesce(((select (p->>'total')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b1) = 4 and (select (p->>'overdue')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b1) = 1 and (select (p->>'total')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b2) = 4 and (select (p->>'overdue')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b2) = 2 and (select (p->>'total')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b3) = 0 and not exists (select 1 from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_bx)), false),'d',(v_x->'people')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-107 · Lo atrasado: monto vencido y el peor atraso de cada persona (Facturación 1: cobro de RD$ 1,000 con 4 días)','ok',coalesce(((select (p->>'overdue_amount')::numeric from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b1) = 1000 and (select (p->>'worst_late')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b1) = 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-108 · Cada persona trae su carga por tipo','ok',coalesce(((select (p->'by_type'->>'cobro_escalar')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b1) = 2 and (select (p->'by_type'->>'glosa_responder')::int from jsonb_array_elements(v_x->'people') p where p->>'user_id' = v_b2) = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-109 · Sin responsable: el cliente C (y los de demostración) con su causa; el total de la cola cuadra con la suma de personas y los sin responsable','ok',coalesce(((v_x->'unassigned'->'by_reason'->>'sin_asignacion')::int >= 1 and exists (select 1 from jsonb_array_elements(v_x->'unassigned'->'clients') c where c->>'client' = 'QA I59 C' and c->>'reason' = 'sin_asignacion') and (v_x->'totals'->>'total')::int = (select sum((p->>'total')::int) from jsonb_array_elements(v_x->'people') p) + (v_x->'unassigned'->>'total')::int and jsonb_array_length(v_x->'by_type') = 4), false),'d',(v_x->'unassigned'->'by_reason')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_supervisor();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-110 · ATAQUE: Facturación no ve la carga por persona (vista del supervisor)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-110 · ATAQUE: Facturación no ve la carga por persona (vista del supervisor)','ok',sqlerrm like 'La carga por persona la ven%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      select (select count(*) from public.inbox_daily_close) + (select count(*) from public.inbox_assignments) + (select count(*) from public.inbox_absences) into v_n;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_my();
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_supervisor();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      select (select count(*) from public.inbox_daily_close) + (select count(*) from public.inbox_assignments) + (select count(*) from public.inbox_absences) into v_n2;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-111 · Leer la bandeja no guarda nada: ninguna tabla de la bandeja cambia al consultar','ok',coalesce((v_n = v_n2), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.inbox_close_day_now();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-112 · El cierre del día guarda una fila por cliente y tipo con tareas, y dice cuántas','ok',coalesce(((select count(*) from public.inbox_daily_close where day = v_t and organization_id in (v_oa, v_ob, v_oc, v_ox)) = 8 and (v_x->>'rows')::int >= 8 and (v_x->>'rows')::int = (select count(*) from public.inbox_daily_close where day = v_t) and (v_x->>'day')::date = v_t), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-113 · Las filas del cierre guardan las vencidas por persona: Facturación 1 con 1 vencida (RD$ 1,000) en el cobro del cliente A','ok',coalesce(((select sum(overdue_tasks) from public.inbox_daily_close where day = v_t and assignee_id = v_b1::uuid) = 1 and (select sum(overdue_amount) from public.inbox_daily_close where day = v_t and assignee_id = v_b1::uuid) = 1000), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    select count(*) into v_n from public.inbox_daily_close where day = v_t;
    perform app.inbox_close_day();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-114 · Cerrar dos veces el mismo día no duplica nada','ok',coalesce(((select count(*) from public.inbox_daily_close where day = v_t) = v_n), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform app.inbox_close_day(v_t - 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-115 · El cierre solo se hace con la fecha de hoy','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-115 · El cierre solo se hace con la fecha de hoy','ok',sqlerrm like 'El cierre solo se puede hacer con la fecha de hoy%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.inbox_daily_close (day, operator_id, organization_id, task_type, assignee_id, assignee_name, open_tasks, overdue_tasks, overdue_amount) values
        (v_t - 1, '00000000-0000-4000-8000-000000000001'::uuid, v_oa, 'cobro_escalar', v_b1::uuid, 'qa.ib.b1', 3, 2, 3000), (v_t - 1, '00000000-0000-4000-8000-000000000001'::uuid, v_oa, 'captura_incompleta', v_b1::uuid, 'qa.ib.b1', 2, 1, 200),
        (v_t - 1, '00000000-0000-4000-8000-000000000001'::uuid, v_ob, 'glosa_responder', v_b2::uuid, 'qa.ib.b2', 2, 2, 800), (v_t - 1, '00000000-0000-4000-8000-000000000001'::uuid, v_oc, 'captura_incompleta', null, null, 1, 1, 50),
        (v_t - 2, '00000000-0000-4000-8000-000000000001'::uuid, v_oa, 'cobro_escalar', v_b1::uuid, 'qa.ib.b1', 3, 0, 0);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_overdue_report(v_t - 2, v_t);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-116 · Indicador del supervisor: por día y por persona; ayer Facturación 1 cerró con 3 vencidas (suma de sus dos tipos) y hoy sale en vivo','ok',coalesce(((select (r->>'overdue')::int from jsonb_array_elements(v_x->'rows') r where r->>'day' = (v_t - 1)::text and r->>'assignee_id' = v_b1) = 3 and (select (r->>'overdue_amount')::numeric from jsonb_array_elements(v_x->'rows') r where r->>'day' = (v_t - 1)::text and r->>'assignee_id' = v_b1) = 3200 and (select (r->>'overdue')::int from jsonb_array_elements(v_x->'rows') r where r->>'day' = v_t::text and r->>'assignee_id' = v_b1 and (r->>'live')::boolean) = 1 and (select (r->>'overdue')::int from jsonb_array_elements(v_x->'rows') r where r->>'day' = (v_t - 2)::text and r->>'assignee_id' = v_b1) = 0), false),'d',(v_x->'rows')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-117 · El indicador separa las tareas sin responsable y las muestra con ese nombre','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'day' = (v_t - 1)::text and r->>'assignee_id' is null and r->>'assignee' = 'Sin responsable' and (r->>'overdue')::int = 1)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-118 · El resumen por persona trae días con vencidas, máximo y promedio','ok',coalesce(((select (z->>'days_with_overdue')::int from jsonb_array_elements(v_x->'by_person') z where z->>'assignee_id' = v_b1) = 2 and (select (z->>'max_overdue')::int from jsonb_array_elements(v_x->'by_person') z where z->>'assignee_id' = v_b1) = 3), false),'d',(v_x->'by_person')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_overdue_report(v_t - 2, v_t);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-119 · Facturación 1 ve solo su propio indicador (nada de Facturación 2 ni de lo sin responsable)','ok',coalesce((jsonb_array_length(v_x->'rows') >= 3 and not exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'assignee_id' is distinct from v_b1)), false),'d',(v_x->'rows')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b2, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_overdue_report(v_t - 2, v_t);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-120 · Facturación 2 ve el suyo: ayer 2 vencidas de la glosa del cliente B','ok',coalesce((not exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'assignee_id' is distinct from v_b2) and (select (r->>'overdue')::int from jsonb_array_elements(v_x->'rows') r where r->>'day' = (v_t - 1)::text) = 2), false),'d',(v_x->'rows')::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.staff_client_access (user_id, client_org_id) values (v_ops::uuid, v_ob);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_overdue_report(v_t - 2, v_t);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-121 · Operaciones con acceso limitado al cliente B solo ve en el indicador lo de ese cliente','ok',coalesce((not exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'assignee_id' = v_b1) and exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'assignee_id' = v_b2)), false),'d',(v_x->'rows')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_x := public.inbox_overdue_report(v_t - 2, v_t);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-122 · El otro operador no ve en su indicador nada de los facturadores de SOFA','ok',coalesce((not exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'assignee_id' in (v_b1, v_b2) or r->>'assignee_id' is null and (r->>'day')::date < v_t)), false),'d',(v_x->'rows')::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_overdue_report(v_t, v_t - 3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-123 · Un rango al revés se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-123 · Un rango al revés se rechaza','ok',sqlerrm like 'La fecha final no puede ser anterior%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_overdue_report(v_t - 200, v_t);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-124 · Un rango de más de 93 días se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-124 · Un rango de más de 93 días se rechaza','ok',sqlerrm like 'El indicador se consulta hasta por 93 días%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_close_day_now();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-125 · ATAQUE: el Médico no cierra el día','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-125 · ATAQUE: el Médico no cierra el día','ok',sqlerrm like 'Solo el Super Admin o el Administrador cierran el día%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_close_day_now();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-126 · Operaciones consulta pero no cierra el día','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-126 · Operaciones consulta pero no cierra el día','ok',sqlerrm like 'Solo el Super Admin o el Administrador cierran el día%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.inbox_params_get();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-127 · Operaciones ve los parámetros (5 días de gracia, 2 de «vence pronto», monto alto RD$ 50,000) pero no los edita','ok',coalesce(((v_x->>'collection_grace_days')::int = 5 and (v_x->>'soon_days')::int = 2 and (v_x->>'high_amount')::numeric = 50000 and not (v_x->>'can_edit')::boolean), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.inbox_params_set(3, 2, 1000);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-128 · ATAQUE: Operaciones no cambia los parámetros','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-128 · ATAQUE: Operaciones no cambia los parámetros','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian los parámetros%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.inbox_params_set(45, 2, 1000);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-129 · Días de gracia fuera de 0 a 30 se rechazan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-129 · Días de gracia fuera de 0 a 30 se rechazan','ok',sqlerrm like 'Los días de gracia del cobro van de 0 a 30%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_params_set(5, 11, 1000);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-130 · Días de «vence pronto» fuera de 0 a 10 se rechazan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-130 · Días de «vence pronto» fuera de 0 a 10 se rechazan','ok',sqlerrm like 'Los días de «vence pronto» van de 0 a 10%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.inbox_params_set(5, 2, -1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-131 · Un monto alto negativo se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-131 · Un monto alto negativo se rechaza','ok',sqlerrm like 'El monto alto no puede ser negativo%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.inbox_params_set(7, 3, 75000);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-132 · El Administrador cambia los parámetros y quedan en la bitácora','ok',coalesce(((select collection_grace_days from public.inbox_params where operator_id = '00000000-0000-4000-8000-000000000001'::uuid) = 7 and exists (select 1 from public.audit_log where table_name = 'inbox_params' and operation = 'UPDATE' and new_values->>'high_amount' = '75000.00')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IB-133 · Las asignaciones y ausencias dejan huella en la bitácora de auditoría','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'inbox_assignments' and organization_id = v_oa and operation = 'INSERT')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);

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

revoke all on function app.qa_run_tests_bandeja() from public, anon, authenticated;
