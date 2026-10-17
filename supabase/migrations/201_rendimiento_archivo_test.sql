-- 201 · Suite de la 200 (rendimiento con 50 clientes y archivo histórico, I64). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_rendimiento();
create or replace function app.qa_run_tests_rendimiento()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_oa constant uuid := '02000000-0000-4000-8000-000000000001'; v_ob constant uuid := '02000000-0000-4000-8000-000000000002'; v_ox constant uuid := '02000000-0000-4000-8000-000000000003'; v_op2 constant uuid := '02000000-0000-4000-8000-000000000004';
  v_pa constant uuid := '02000000-0000-4000-8000-000000000011'; v_pb constant uuid := '02000000-0000-4000-8000-000000000012'; v_px constant uuid := '02000000-0000-4000-8000-000000000013';
  v_sa constant text := '02000000-0000-4000-8000-000000000021'; v_ad constant text := '02000000-0000-4000-8000-000000000022'; v_ops constant text := '02000000-0000-4000-8000-000000000023'; v_b1 constant text := '02000000-0000-4000-8000-000000000024'; v_au constant text := '02000000-0000-4000-8000-000000000025';
  v_ma constant text := '02000000-0000-4000-8000-000000000026'; v_mb constant text := '02000000-0000-4000-8000-000000000027'; v_ax constant text := '02000000-0000-4000-8000-000000000028'; v_cp constant text := '02000000-0000-4000-8000-000000000029';
  v_ars uuid; v_ars2 uuid; v_proc uuid; v_reason text; v_m0 date; v_m1 date; v_m6 date; v_m7 date; v_m8 date; v_m9 date; v_m10 date;
  v_s1 uuid; v_s1b uuid; v_s2 uuid; v_s3 uuid; v_s4 uuid; v_s5 uuid; v_s6 uuid; v_s7 uuid; v_sb1 uuid; v_sx1 uuid;
  v_l1 uuid; v_l1b uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid; v_l5 uuid; v_l6 uuid; v_l7 uuid; v_lb uuid; v_lx uuid; v_g3 uuid; v_g5 uuid; v_gi5 uuid; v_pay uuid; v_al uuid;
  v_r jsonb; v_r2 jsonb; v_n2 int; v_id uuid; v_rl text; v_p text; v_ids text; v_ids2 text; v_cur jsonb; v_plan text;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '200') then
    raise exception 'Falta la migración 200. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    v_m0 := date_trunc('month', current_date)::date; v_m1 := (v_m0 - interval '1 month')::date; v_m6 := (v_m0 - interval '6 months')::date; v_m7 := (v_m0 - interval '7 months')::date;
    v_m8 := (v_m0 - interval '8 months')::date; v_m9 := (v_m0 - interval '9 months')::date; v_m10 := (v_m0 - interval '10 months')::date;
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.ra.sa@sofa.test','x'),(v_ad::uuid,'qa.ra.ad@sofa.test','x'),(v_ops::uuid,'qa.ra.ops@sofa.test','x'),(v_b1::uuid,'qa.ra.b1@sofa.test','x'),(v_au::uuid,'qa.ra.au@sofa.test','x'),(v_ma::uuid,'qa.ra.ma@sofa.test','x'),(v_mb::uuid,'qa.ra.mb@sofa.test','x'),(v_ax::uuid,'qa.ra.ax@sofa.test','x'),(v_cp::uuid,'qa.ra.cp@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ra.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_oa, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I64 A', '00000020001', 'Médico independiente', 'activo', current_date - 90, '8095550001');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_ob, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I64 B', '00000020002', 'Médico independiente', 'activo', current_date - 90, '8095550002');
    insert into public.organizations (id, kind, legal_name, tax_id, org_type, status, started_on) values (v_op2, 'operator', 'QA I64 Operador Dos', '00000020009', 'Operador', 'activo', current_date - 90);
    -- Folio de reclamación único en toda la base (índice service_lines_claim_folio_uq de producción) pero contador por operador: se adelanta el del segundo operador para que no choque con el primero.
    insert into public.folio_counters (scope_id, kind, year, last_value) select v_op2, k, extract(year from current_date)::smallint, 900000 from unnest(array['REC','GLO','RAD','FAC','CON','PAG','PRV','REL','RET','SRV','HAB']) as k on conflict (scope_id, kind, year) do update set last_value = 900000;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_ox, 'client', v_op2, 'QA I64 X', '00000020003', 'Médico independiente', 'activo', current_date - 90, '8095550003');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_oa, 'Dr. A QA', 'Cardiología', true), (v_pb, v_ob, 'Dr. B QA', 'Ortopedia', true), (v_px, v_ox, 'Dr. X QA', 'Pediatría', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_b1::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_au::uuid, 'auditor', true),
      (v_oa, v_ma::uuid, 'client', true), (v_ob, v_mb::uuid, 'client', true), (v_op2, v_ax::uuid, 'admin', true), (v_oa, v_cp::uuid, 'capturer', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_cp::uuid, v_pa, v_oa, true, true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_ra_ars', 'ARS QA Archivo', 'Contributivo', true) returning id into v_ars;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_ra_ars2', 'ARS QA Archivo 2', 'Contributivo', true) returning id into v_ars2;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    select code into v_reason from public.glosa_reasons order by code limit 1;
    -- Cliente A: mes -6 (un lote cerrado y uno pagado: se puede archivar), -7 (radicado: no), -8 (pagado con glosa abierta: no), -9 (cerrado con glosa cerrada y un pago), -10 (pagado), mes pasado (cerrado pero reciente) y este mes (borrador)
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars, v_m6, 1, 'borrador') returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars2, v_m6, 2, 'borrador') returning id into v_s1b;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars, v_m7, 1, 'borrador') returning id into v_s2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars, v_m8, 1, 'borrador') returning id into v_s3;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars, v_m0, 1, 'borrador') returning id into v_s4;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars, v_m9, 1, 'borrador') returning id into v_s5;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars, v_m10, 1, 'borrador') returning id into v_s6;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_ars, v_m1, 1, 'borrador') returning id into v_s7;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_ob, v_pb, v_ars, v_m6, 1, 'borrador') returning id into v_sb1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_ox, v_px, v_ars, v_m6, 1, 'borrador') returning id into v_sx1;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s1, v_oa, v_m6 + 3, 'Paciente Archivo 1', v_proc, 1, 1000, 'MA001', 'AA001') returning id into v_l1;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s1b, v_oa, v_m6 + 4, 'Paciente Archivo 2', v_proc, 1, 500, 'MA002', 'AA002') returning id into v_l1b;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s2, v_oa, v_m7 + 3, 'Paciente Archivo 3', v_proc, 1, 100, 'MA003', 'AA003') returning id into v_l2;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s3, v_oa, v_m8 + 3, 'Paciente Archivo 4', v_proc, 1, 300, 'MA004', 'AA004') returning id into v_l3;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s4, v_oa, current_date, 'Paciente Archivo 5', v_proc, 1, 250, 'MA005', 'AA005') returning id into v_l4;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s5, v_oa, v_m9 + 3, 'Paciente Archivo 6', v_proc, 1, 700, 'MA006', 'AA006') returning id into v_l5;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s6, v_oa, v_m10 + 3, 'Paciente Archivo 7', v_proc, 1, 100, 'MA007', 'AA007') returning id into v_l6;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s7, v_oa, v_m1 + 3, 'Paciente Archivo 8', v_proc, 1, 100, 'MA008', 'AA008') returning id into v_l7;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_sb1, v_ob, v_m6 + 3, 'Paciente Archivo 9', v_proc, 1, 100, 'MA009', 'AA009') returning id into v_lb;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_sx1, v_ox, v_m6 + 3, 'Paciente Archivo 10', v_proc, 1, 100, 'MA010', 'AA010') returning id into v_lx;
    perform set_config('app.contract_override', '', true);
    -- Más reclamaciones del mes -6 para probar la paginación de la búsqueda (5 en total en el cliente A ese mes)
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s1, v_oa, v_m6 + 5, 'Paciente Archivo 11', v_proc, 1, 100, 'MA011', 'AA011') returning id into v_id;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s1, v_oa, v_m6 + 6, 'Paciente Archivo 12', v_proc, 1, 100, 'MA012', 'AA012') returning id into v_id;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_s1, v_oa, v_m6 + 7, 'Paciente Archivo 13', v_proc, 1, 100, 'MA013', 'AA013') returning id into v_id;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.status_change', 'on', true);
    update public.submissions set status = 'cerrada', submitted_on = v_m6 + 40, ncf = 'B0100002001', ars_receipt_number = 'RA1' where id = v_s1;
    update public.submissions set status = 'pagada', submitted_on = v_m6 + 41, ncf = 'B0100002002', ars_receipt_number = 'RA2' where id = v_s1b;
    update public.submissions set status = 'radicada', submitted_on = v_m7 + 40, ncf = 'B0100002003', ars_receipt_number = 'RA3' where id = v_s2;
    update public.submissions set status = 'pagada', submitted_on = v_m8 + 40, ncf = 'B0100002004', ars_receipt_number = 'RA4' where id = v_s3;
    update public.submissions set status = 'radicada', submitted_on = v_m9 + 40, ncf = 'B0100002005', ars_receipt_number = 'RA5' where id = v_s5;
    update public.submissions set status = 'pagada', submitted_on = v_m10 + 40, ncf = 'B0100002006', ars_receipt_number = 'RA6' where id = v_s6;
    update public.submissions set status = 'cerrada', submitted_on = v_m1 + 20, ncf = 'B0100002007', ars_receipt_number = 'RA7' where id = v_s7;
    update public.submissions set status = 'cerrada', submitted_on = v_m6 + 40, ncf = 'B0100002008', ars_receipt_number = 'RA8' where id = v_sb1;
    update public.submissions set status = 'cerrada', submitted_on = v_m6 + 40, ncf = 'B0100002009', ars_receipt_number = 'RA9' where id = v_sx1;
    perform set_config('app.status_change', '', true);
    -- Glosas: una abierta en el mes -8 y una cerrada en el mes -9
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_s3, v_m8 + 50, 'GLO-QA-RA1') returning id into v_g3;
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_s5, v_m9 + 50, 'GLO-QA-RA2') returning id into v_g5;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_g3, v_oa, v_l3, v_reason, 100);
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_g5, v_oa, v_l5, v_reason, 200) returning id into v_gi5;
    perform set_config('app.glosa_change', 'on', true);
    update public.glosas set status = 'cerrada' where id = v_g5;
    perform set_config('app.glosa_change', '', true);
    -- Un pago aplicado al lote del mes -9 (para probar que las asignaciones también quedan bloqueadas)
    insert into public.payments (organization_id, ars_id, paid_on, amount, reference) values (v_oa, v_ars, current_date - 30, 500, 'PAGO-QA-RA1') returning id into v_pay;
    insert into public.payment_allocations (payment_id, organization_id, submission_id, amount) values (v_pay, v_oa, v_s5, 500) returning id into v_al;
    perform set_config('app.status_change', 'on', true);
    update public.submissions set status = 'cerrada' where id = v_s5;
    perform set_config('app.status_change', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-01 · La migración 200 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '200')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-02 · Las cinco tablas nuevas no se tocan por la API: ni anon ni authenticated tienen permisos y tienen RLS','ok',coalesce((not exists (select 1 from unnest(array['perf_params','perf_metrics','perf_throttle','perf_size_log','period_archives']) t where has_table_privilege('authenticated', 'public.' || t, 'select') or has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update') or has_table_privilege('authenticated', 'public.' || t, 'delete') or has_table_privilege('anon', 'public.' || t, 'select') or not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-03 · Las funciones públicas no están abiertas a anon y sí a authenticated','ok',coalesce((not has_function_privilege('anon', 'public.archive_period(uuid,date,text)', 'execute') and not has_function_privilege('anon', 'public.history_search(uuid,text,uuid,uuid,date,date,text,numeric,numeric,boolean,integer,jsonb)', 'execute') and not has_function_privilege('anon', 'public.perf_record(text,integer)', 'execute') and not has_function_privilege('anon', 'public.perf_report(integer)', 'execute') and not has_function_privilege('anon', 'public.perf_db_overview()', 'execute') and has_function_privilege('authenticated', 'public.archive_period(uuid,date,text)', 'execute') and has_function_privilege('authenticated', 'public.perf_record(text,integer)', 'execute') and has_function_privilege('authenticated', 'public.history_search(uuid,text,uuid,uuid,date,date,text,numeric,numeric,boolean,integer,jsonb)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-04 · Las funciones internas no se llaman desde la API (ni authenticated ni anon)','ok',coalesce((not exists (select 1 from pg_proc p where p.pronamespace = 'app'::regnamespace and p.proname in ('perf_ensure_index','perf_operator','perf_param','perf_purge','perf_size_snapshot','period_archived','archive_blockers','archive_guard','period_archives_guard') and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-05 · Todas las funciones nuevas son SECURITY DEFINER con search_path vacío','ok',coalesce((not exists (select 1 from pg_proc p where ((p.pronamespace = 'public'::regnamespace and p.proname in ('archive_period','archive_periods_until','restore_period','archives_list','archive_candidates','history_search','perf_record','perf_report','perf_db_overview','perf_params_get','perf_params_set')) or (p.pronamespace = 'app'::regnamespace and p.proname in ('perf_ensure_index','perf_operator','perf_param','perf_purge','perf_size_snapshot','period_archived','archive_blockers','archive_guard','period_archives_guard'))) and (not p.prosecdef or p.proconfig is null or not ('search_path=""' = any (p.proconfig) or 'search_path=' = any (p.proconfig))))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-06 · El guardián de archivo está en las seis tablas y se llama a0_ (se evalúa primero)','ok',coalesce(((select count(*) from pg_trigger t where t.tgname = 'a0_archive_guard' and not t.tgisinternal and t.tgrelid in ('public.submissions'::regclass, 'public.service_lines'::regclass, 'public.payment_allocations'::regclass, 'public.payment_line_allocations'::regclass, 'public.glosas'::regclass, 'public.glosa_items'::regclass)) = 6), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-07 · Los parámetros por defecto: límite 8 GB, meta p95 2 s, conservar 90 días, esperar 60 días para archivar, 30 registros por minuto','ok',coalesce((exists (select 1 from public.perf_params where operator_id = '00000000-0000-4000-8000-000000000001'::uuid and db_limit_bytes = 8589934592 and p95_target_ms = 2000 and retention_days = 90 and archive_min_days = 60 and rate_per_minute = 30)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-08 · Se puede archivar un mes cuando todo está Pagado o Cerrado: el mes -6 (lote cerrado y lote pagado) no tiene impedimentos','ok',coalesce((cardinality(app.archive_blockers(v_oa, v_m6)) = 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-09 · Un lote Radicado impide archivar (mes -7)','ok',coalesce((app.archive_blockers(v_oa, v_m7)::text like '%no están Pagadas, Cerradas ni Rechazadas%'), false),'d',(app.archive_blockers(v_oa, v_m7)::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-10 · Una glosa abierta impide archivar aunque el lote esté Pagado (mes -8)','ok',coalesce((app.archive_blockers(v_oa, v_m8)::text like '%glosa(s) siguen abiertas%'), false),'d',(app.archive_blockers(v_oa, v_m8)::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-11 · Un mes que terminó hace menos de 60 días impide archivar (mes pasado) y dice hasta cuándo esperar','ok',coalesce((app.archive_blockers(v_oa, v_m1)::text like '%terminó hace menos de 60 días: espere hasta el%'), false),'d',(app.archive_blockers(v_oa, v_m1)::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-12 · El mes en curso nunca se puede archivar','ok',coalesce((cardinality(app.archive_blockers(v_oa, v_m0)) >= 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-13 · Un mes sin radicaciones no se archiva','ok',coalesce((app.archive_blockers(v_oa, (v_m0 - interval '30 months')::date)::text like '%No hay radicaciones en ese periodo%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-14 · Una glosa cerrada no impide archivar (mes -9)','ok',coalesce((cardinality(app.archive_blockers(v_oa, v_m9)) = 0), false),'d',(app.archive_blockers(v_oa, v_m9)::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_period(v_oa, v_m6, 'intento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-15 · ATAQUE: Operaciones no archiva periodos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-15 · ATAQUE: Operaciones no archiva periodos','ok',sqlerrm like 'Solo el Super Admin o el Administrador archivan periodos%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_period(v_oa, v_m6, 'intento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-16 · ATAQUE: Facturación no archiva periodos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-16 · ATAQUE: Facturación no archiva periodos','ok',sqlerrm like 'Solo el Super Admin o el Administrador archivan periodos%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_period(v_oa, v_m6, 'intento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-17 · ATAQUE: El Auditor no archiva periodos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-17 · ATAQUE: El Auditor no archiva periodos','ok',sqlerrm like 'Solo el Super Admin o el Administrador archivan periodos%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_period(v_oa, v_m6, 'intento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-18 · ATAQUE: El Médico no archiva periodos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-18 · ATAQUE: El Médico no archiva periodos','ok',sqlerrm like 'Solo el Super Admin o el Administrador archivan periodos%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_period(v_oa, v_m6, 'intento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-19 · ATAQUE: el Administrador de otro operador no archiva periodos de un cliente ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-19 · ATAQUE: el Administrador de otro operador no archiva periodos de un cliente ajeno','ok',sqlerrm like 'Ese cliente no existe o no está entre los que usted puede ver%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_period(v_oa, v_m7, 'intento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-20 · Un periodo con impedimentos no se archiva y el error dice qué falta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-20 · Un periodo con impedimentos no se archiva y el error dice qué falta','ok',sqlerrm like 'No se puede archivar %: 1 radicación(es) todavía no están Pagadas, Cerradas ni Rechazadas.%Cierre lo pendiente%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.archive_period(null, v_m6, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-21 · Faltan datos: se pide el cliente y el mes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-21 · Faltan datos: se pide el cliente y el mes','ok',sqlerrm like 'Indique el cliente y el mes que quiere archivar%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.archive_period(v_oa, v_m6, repeat('x', 301));
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-22 · El motivo no pasa de 300 caracteres','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-22 · El motivo no pasa de 300 caracteres','ok',sqlerrm like 'El motivo no puede pasar de 300 caracteres%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.archive_period(v_oa, v_m6, 'Cierre anual de prueba');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-23 · El Administrador archiva el mes -6: queda activo y con su motivo','ok',coalesce(((v_r->>'archived')::boolean and exists (select 1 from public.period_archives where organization_id = v_oa and period = v_m6 and restored_at is null and reason = 'Cierre anual de prueba' and archived_by = v_ad::uuid)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.archive_period(v_oa, v_m6, 'otra vez');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-24 · Archivar dos veces el mismo mes se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-24 · Archivar dos veces el mismo mes se rechaza','ok',sqlerrm like 'No se puede archivar %El periodo ya está archivado%','d',left(sqlerrm,120)));
    end;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-25 · El archivo queda en la bitácora de auditoría','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'period_archives' and organization_id = v_oa and operation = 'INSERT')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      update public.submissions set notes = 'cambio' where id = v_s1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-26 · ATAQUE: Facturación no cambia una radicación de un periodo archivado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-26 · ATAQUE: Facturación no cambia una radicación de un periodo archivado','ok',sqlerrm like 'El periodo % de este cliente está archivado (solo lectura): no se puede cambiar en sus radicaciones%Reabrir periodo%','d',left(sqlerrm,120)));
    end;
    begin
      update public.service_lines set notes = 'cambio' where id = v_l1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-27 · ATAQUE: Facturación no cambia una reclamación de un periodo archivado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-27 · ATAQUE: Facturación no cambia una reclamación de un periodo archivado','ok',sqlerrm like 'El periodo % de este cliente está archivado (solo lectura): no se puede cambiar en sus reclamaciones%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_s1, v_oa, v_m6 + 8, 'Paciente Nuevo', v_proc, 1, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-28 · ATAQUE: Facturación no agrega reclamaciones a un lote de un periodo archivado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-28 · ATAQUE: Facturación no agrega reclamaciones a un lote de un periodo archivado','ok',sqlerrm like 'El periodo % de este cliente está archivado (solo lectura): no se puede agregar en sus reclamaciones%','d',left(sqlerrm,120)));
    end;
    begin
      delete from public.service_lines where id = v_l1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-29 · ATAQUE: Facturación no borra reclamaciones de un periodo archivado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-29 · ATAQUE: Facturación no borra reclamaciones de un periodo archivado','ok',sqlerrm like 'El periodo % de este cliente está archivado (solo lectura): no se puede borrar en sus reclamaciones%','d',left(sqlerrm,120)));
    end;
    begin
      update public.service_lines set submission_id = v_s4 where id = v_l1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-30 · ATAQUE: no se mueve una reclamación archivada a un lote de otro mes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-30 · ATAQUE: no se mueve una reclamación archivada a un lote de otro mes','ok',sqlerrm like 'El periodo % de este cliente está archivado%','d',left(sqlerrm,120)));
    end;
    begin
      update public.service_lines set submission_id = v_s1 where id = v_l4;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-31 · ATAQUE: no se mueve una reclamación abierta a un lote de un periodo archivado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-31 · ATAQUE: no se mueve una reclamación abierta a un lote de un periodo archivado','ok',sqlerrm like 'El periodo % de este cliente está archivado%','d',left(sqlerrm,120)));
    end;
    begin
      update public.submissions set period = v_m0 where id = v_s1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-32 · ATAQUE: no se saca un lote del periodo archivado cambiando su mes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-32 · ATAQUE: no se saca un lote del periodo archivado cambiando su mes','ok',sqlerrm like 'El periodo % de este cliente está archivado%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      update public.service_lines set notes = 'cambio' where id = v_l1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-33 · ATAQUE: el Médico no toca su propio periodo archivado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-33 · ATAQUE: el Médico no toca su propio periodo archivado','ok',sqlerrm like 'El periodo % de este cliente está archivado%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      delete from public.submissions where id = v_s1;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-34 · ATAQUE: ni el Administrador borra un lote de un periodo archivado (la política de borrado ya solo deja borradores; el lote sigue ahí)','ok',coalesce((exists (select 1 from public.submissions where id = v_s1)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-34 · ATAQUE: ni el Administrador borra un lote de un periodo archivado (la política de borrado ya solo deja borradores; el lote sigue ahí)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.archive_period(v_oa, v_m9, null);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.change_glosa_status(v_g5, 'apelada', 'intento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-35 · ATAQUE: una glosa cerrada de un periodo archivado no se vuelve a abrir (ni por el flujo de glosas)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-35 · ATAQUE: una glosa cerrada de un periodo archivado no se vuelve a abrir (ni por el flujo de glosas)','ok',sqlerrm like 'Transición de glosa no permitida%','d',left(sqlerrm,120)));
    end;
    begin
      update public.glosa_items set notes = 'cambio' where id = v_gi5;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-36 · ATAQUE: no se cambian los ítems de una glosa de un periodo archivado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-36 · ATAQUE: no se cambian los ítems de una glosa de un periodo archivado','ok',sqlerrm like 'El periodo % de este cliente está archivado (solo lectura): no se puede cambiar en los ítems de sus glosas%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.payment_allocations (payment_id, organization_id, submission_id, amount) values (v_pay, v_oa, v_s5, 10);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-37 · ATAQUE: no se aplica un pago a un lote de un periodo archivado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-37 · ATAQUE: no se aplica un pago a un lote de un periodo archivado','ok',sqlerrm like 'El periodo % de este cliente está archivado (solo lectura): no se puede agregar en los pagos aplicados%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      delete from public.payment_allocations where id = v_al;
      update public.payment_allocations set amount = 400 where id = v_al;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-38 · ATAQUE: ni el Administrador borra ni cambia la asignación de un pago de un periodo archivado (la política no se lo permite y la asignación sigue intacta)','ok',coalesce(((select amount from public.payment_allocations where id = v_al) = 500), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-38 · ATAQUE: ni el Administrador borra ni cambia la asignación de un pago de un periodo archivado (la política no se lo permite y la asignación sigue intacta)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      delete from public.payment_allocations where id = v_al;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-39 · El Super Admin sí puede borrar la asignación de un periodo archivado y queda la excepción en la bitácora','ok',coalesce((not exists (select 1 from public.payment_allocations where id = v_al) and exists (select 1 from public.audit_log where table_name = 'payment_allocations' and organization_id = v_oa and new_values ? 'excepcion_periodo_archivado')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-39 · El Super Admin sí puede borrar la asignación de un periodo archivado y queda la excepción en la bitácora','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      update public.submissions set notes = 'cambio permitido' where id = v_s4;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-40 · Facturación cambia una radicación de un periodo NO archivado (mes en curso) sin problema','ok',coalesce(((select notes from public.submissions where id = v_s4) = 'cambio permitido'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-40 · Facturación cambia una radicación de un periodo NO archivado (mes en curso) sin problema','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      update public.service_lines set notes = 'cambio permitido' where id = v_l4;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-41 · Facturación cambia una reclamación de un periodo NO archivado sin problema','ok',coalesce(((select notes from public.service_lines where id = v_l4) = 'cambio permitido'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-41 · Facturación cambia una reclamación de un periodo NO archivado sin problema','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      update public.submissions set notes = 'cambio permitido' where id = v_sb1;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-42 · El archivo de un cliente no afecta a otro: el cliente B edita su propio periodo del mismo mes','ok',coalesce(((select notes from public.submissions where id = v_sb1) = 'cambio permitido'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-42 · El archivo de un cliente no afecta a otro: el cliente B edita su propio periodo del mismo mes','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      update public.submissions set notes = 'corrección del Super Admin' where id = v_s1;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-43 · El Super Admin sí puede corregir un periodo archivado y la excepción queda en la bitácora','ok',coalesce(((select notes from public.submissions where id = v_s1) = 'corrección del Super Admin' and exists (select 1 from public.audit_log where table_name = 'submissions' and organization_id = v_oa and new_values ? 'excepcion_periodo_archivado' and user_id = v_sa::uuid)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-43 · El Super Admin sí puede corregir un periodo archivado y la excepción queda en la bitácora','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.submissions set notes = 'ajuste de mantenimiento' where id = v_s1;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-44 · El SQL Editor (sin usuario) no queda bloqueado, igual que el resto de los guardas de SOFA','ok',coalesce(((select notes from public.submissions where id = v_s1) = 'ajuste de mantenimiento'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-44 · El SQL Editor (sin usuario) no queda bloqueado, igual que el resto de los guardas de SOFA','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.restore_period(v_oa, v_m6, 'Necesito corregir una reclamación');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-45 · ATAQUE: el Administrador no reabre periodos (solo el Super Admin)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-45 · ATAQUE: el Administrador no reabre periodos (solo el Super Admin)','ok',sqlerrm like 'Solo el Super Admin reabre un periodo archivado%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.restore_period(v_oa, v_m6, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-46 · Reabrir exige un motivo de al menos 10 caracteres','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-46 · Reabrir exige un motivo de al menos 10 caracteres','ok',sqlerrm like 'Escriba el motivo para reabrir el periodo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.restore_period(v_oa, v_m6, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-47 · Reabrir exige un motivo no vacío','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-47 · Reabrir exige un motivo no vacío','ok',sqlerrm like 'Escriba el motivo para reabrir el periodo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.restore_period(v_oa, v_m7, 'Motivo suficientemente largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-48 · Reabrir un mes que no está archivado se rechaza con indicación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-48 · Reabrir un mes que no está archivado se rechaza con indicación','ok',sqlerrm like 'Ese periodo no está archivado%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.restore_period(v_ox, v_m6, 'Motivo suficientemente largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-49 · El Super Admin de otro operador no se ve afectado: un cliente ajeno no se reabre','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-49 · El Super Admin de otro operador no se ve afectado: un cliente ajeno no se reabre','ok',sqlerrm like 'Ese cliente no existe o no está entre los que usted puede ver%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.restore_period(v_oa, v_m6, 'Corregir una reclamación mal capturada');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      update public.submissions set notes = 'ya se puede' where id = v_s1;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-50 · El Super Admin reabre el mes -6 con motivo: queda la historia y se puede volver a editar','ok',coalesce(((v_r->>'restored')::boolean and exists (select 1 from public.period_archives where organization_id = v_oa and period = v_m6 and restored_at is not null and restored_by = v_sa::uuid and restore_reason = 'Corregir una reclamación mal capturada') and (select notes from public.submissions where id = v_s1) = 'ya se puede'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-50 · El Super Admin reabre el mes -6 con motivo: queda la historia y se puede volver a editar','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.restore_period(v_oa, v_m6, 'Corregir una reclamación mal capturada');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.archive_period(v_oa, v_m6, 'Segundo cierre');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-51 · Después de reabrir se puede archivar de nuevo (nueva fila; la anterior se conserva)','ok',coalesce(((select count(*) from public.period_archives where organization_id = v_oa and period = v_m6) = 2 and (select count(*) from public.period_archives where organization_id = v_oa and period = v_m6 and restored_at is null) = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-51 · Después de reabrir se puede archivar de nuevo (nueva fila; la anterior se conserva)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.restore_period(v_oa, v_m6, 'Corregir una reclamación mal capturada');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-52 · Reabrir deja huella en la bitácora de auditoría (UPDATE de period_archives)','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'period_archives' and organization_id = v_oa and operation = 'UPDATE' and new_values ? 'restored_at')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-52 · Reabrir deja huella en la bitácora de auditoría (UPDATE de period_archives)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      delete from public.period_archives where organization_id = v_oa and period = v_m6;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-53 · El registro de un archivo no se borra (ni siquiera desde el SQL Editor)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-53 · El registro de un archivo no se borra (ni siquiera desde el SQL Editor)','ok',sqlerrm like 'El registro de un periodo archivado no se borra%','d',left(sqlerrm,120)));
    end;
    begin
      update public.period_archives set period = v_m7 where organization_id = v_oa and period = v_m6;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-54 · El mes y el cliente de un archivo no se reescriben','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-54 · El mes y el cliente de un archivo no se reescriben','ok',sqlerrm like 'Un periodo archivado solo cambia al reabrirlo%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.period_archives (organization_id, period) values (v_oa, v_m6);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-55 · Dos archivos activos del mismo mes no existen (índice único)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-55 · Dos archivos activos del mismo mes no existen (índice único)','ok',sqlerrm like '%duplicate key%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.period_archives (organization_id, period) values (v_oa, v_m7 + 4);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-56 · El periodo debe ser el primer día del mes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-56 · El periodo debe ser el primer día del mes','ok',sqlerrm like '%period_archives_period_check%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.archive_periods_until(v_oa, v_m1, 'Cierre por lote');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-57 · Archivar hasta un mes: archiva los que se pueden, salta los que no y dice por qué','ok',coalesce(((v_r->>'archived_count')::int = 1 and v_r->'archived' = jsonb_build_array(v_m10::text) and jsonb_array_length(v_r->'skipped') = 3 and exists (select 1 from jsonb_array_elements(v_r->'skipped') e where (e->>'period')::date = v_m7 and e->>'motivos' like '%no están Pagadas%') and exists (select 1 from jsonb_array_elements(v_r->'skipped') e where (e->>'period')::date = v_m8 and e->>'motivos' like '%glosa(s) siguen abiertas%') and exists (select 1 from jsonb_array_elements(v_r->'skipped') e where (e->>'period')::date = v_m1 and e->>'motivos' like '%terminó hace menos de 60 días%')), false),'d',(v_r::text)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-57 · Archivar hasta un mes: archiva los que se pueden, salta los que no y dice por qué','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_periods_until(v_oa, v_m1, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-58 · ATAQUE: Facturación no archiva varios meses','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-58 · ATAQUE: Facturación no archiva varios meses','ok',sqlerrm like 'Solo el Super Admin o el Administrador archivan periodos%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_periods_until(v_oa, v_m1, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-59 · ATAQUE: el Administrador de otro operador no archiva varios meses de un cliente ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-59 · ATAQUE: el Administrador de otro operador no archiva varios meses de un cliente ajeno','ok',sqlerrm like 'Ese cliente no existe o no está entre los que usted puede ver%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.archives_list(v_oa);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-60 · La lista de periodos archivados trae el cliente, el mes, el estado y los lotes','ok',coalesce((jsonb_array_length(v_r) >= 2 and exists (select 1 from jsonb_array_elements(v_r) e where (e->>'period')::date = v_m9 and (e->>'active')::boolean and (e->>'lots')::int = 1 and e->>'client' = 'QA I64 A')), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.archives_list(null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-61 · El Médico ve solo los archivos de su propio consultorio','ok',coalesce((jsonb_array_length(v_r) >= 1 and not exists (select 1 from jsonb_array_elements(v_r) e where (e->>'organization_id')::uuid <> v_oa)), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.archives_list(null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-62 · Otro cliente no ve los archivos del consultorio A','ok',coalesce((not exists (select 1 from jsonb_array_elements(v_r) e where (e->>'organization_id')::uuid = v_oa)), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.archives_list(null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-63 · Otro operador no ve ningún archivo de SOFA','ok',coalesce((jsonb_array_length(v_r) = 0), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.archive_candidates(v_oa);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-64 · Operaciones ve qué periodos se pueden archivar: mes -6 listo (ya archivado), -7 con impedimentos','ok',coalesce((exists (select 1 from jsonb_array_elements(v_r) e where (e->>'period')::date = v_m7 and not (e->>'ready')::boolean and jsonb_array_length(e->'blockers') >= 1)), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_candidates(v_oa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-65 · ATAQUE: Facturación no consulta los candidatos a archivar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-65 · ATAQUE: Facturación no consulta los candidatos a archivar','ok',sqlerrm like 'Solo el equipo de SOFA (Super Admin, Administrador u Operaciones) consulta qué periodos se pueden archivar%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_candidates(v_oa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-66 · ATAQUE: el Médico no consulta los candidatos a archivar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-66 · ATAQUE: el Médico no consulta los candidatos a archivar','ok',sqlerrm like 'Solo el equipo de SOFA (Super Admin, Administrador u Operaciones) consulta qué periodos se pueden archivar%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.archives_list(null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-67 · Sin sesión no se listan archivos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-67 · Sin sesión no se listan archivos','ok',sqlerrm like 'Inicie sesión para ver los periodos archivados%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.history_search(v_oa, null, null, null, null, null, null, null, null, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-68 · La búsqueda sin filtros trae las reclamaciones del cliente (11 en el cliente A), con total y marca de archivo','ok',coalesce(((v_r->>'count')::int = 11 and not (v_r->>'has_more')::boolean and (v_r->>'limit')::int = 50 and exists (select 1 from jsonb_array_elements(v_r->'rows') e where (e->>'archived')::boolean) and exists (select 1 from jsonb_array_elements(v_r->'rows') e where not (e->>'archived')::boolean)), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, null, null, null, null, null, null, null, false, 4, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-69 · Con tope de 4 filas: trae 4, avisa que hay más y da la marca de la siguiente página','ok',coalesce(((v_r->>'count')::int = 4 and (v_r->>'has_more')::boolean and (v_r->'next'->>'id') is not null and (v_r->'next'->>'d') is not null), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_cur := v_r->'next'; v_ids := (select string_agg(e->>'id', ',' order by e->>'id') from jsonb_array_elements(v_r->'rows') e);
    v_r2 := public.history_search(v_oa, null, null, null, null, null, null, null, null, false, 4, v_cur);
    v_ids2 := (select string_agg(e->>'id', ',' order by e->>'id') from jsonb_array_elements(v_r2->'rows') e);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-70 · La segunda página no repite filas de la primera','ok',coalesce(((v_r2->>'count')::int = 4 and not exists (select 1 from jsonb_array_elements(v_r2->'rows') e where position((e->>'id') in v_ids) > 0)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, null, null, null, null, null, null, null, false, 4, v_r2->'next');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-71 · La tercera página trae las 3 que faltan y ya no hay más','ok',coalesce(((v_r->>'count')::int = 3 and not (v_r->>'has_more')::boolean and jsonb_typeof(v_r->'next') = 'null' and not exists (select 1 from jsonb_array_elements(v_r->'rows') e where position((e->>'id') in v_ids || v_ids2) > 0)), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, null, null, null, null, null, null, null, false, 1000, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-72 · El tope máximo es 100 filas aunque se pida más','ok',coalesce(((v_r->>'limit')::int = 100), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, null, null, null, null, null, null, null, false, 0, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-73 · Un tope de 0 se corrige a 1 fila','ok',coalesce(((v_r->>'limit')::int = 1 and (v_r->>'count')::int = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, null, null, null, null, null, null, null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-74 · Sin tope pedido se usan 50','ok',coalesce(((v_r->>'limit')::int = 50), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, 'Archivo 6', null, null, null, null, null, null, null, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-75 · Búsqueda por nombre del paciente (contiene)','ok',coalesce(((v_r->>'count')::int = 1 and v_r->'rows'->0->>'patient' = 'Paciente Archivo 6'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, 'MA005', null, null, null, null, null, null, null, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-76 · Búsqueda por número de afiliado exacto','ok',coalesce(((v_r->>'count')::int = 1 and v_r->'rows'->0->>'member_number' = 'MA005'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, 'AA008', null, null, null, null, null, null, null, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-77 · Búsqueda por número de autorización exacto','ok',coalesce(((v_r->>'count')::int = 1 and v_r->'rows'->0->>'authorization_number' = 'AA008'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, v_ars2, null, null, null, null, null, null, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-78 · Filtro por ARS: solo el lote de la segunda ARS (1 reclamación)','ok',coalesce(((v_r->>'count')::int = 1 and (v_r->'rows'->0->>'ars_id')::uuid = v_ars2), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, null, null, v_m6, v_m6 + 29, null, null, null, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-79 · Filtro por fechas: las reclamaciones del mes -6 (5 en total)','ok',coalesce(((v_r->>'count')::int = 5), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, null, null, null, null, 'capturada', null, null, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-80 · Filtro por estado de la reclamación','ok',coalesce(((v_r->>'count')::int >= 1 and not exists (select 1 from jsonb_array_elements(v_r->'rows') e where e->>'claim_status' <> 'capturada')), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, null, null, null, null, null, 700, 1000, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-81 · Filtro por monto entre 700 y 1000','ok',coalesce(((v_r->>'count')::int >= 2 and not exists (select 1 from jsonb_array_elements(v_r->'rows') e where (e->>'amount')::numeric not between 700 and 1000)), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, null, null, null, null, null, null, null, null, true, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-82 · Solo periodos archivados: todas las filas vienen marcadas','ok',coalesce(((v_r->>'count')::int >= 1 and not exists (select 1 from jsonb_array_elements(v_r->'rows') e where not (e->>'archived')::boolean)), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, '%%%', null, null, null, null, null, null, null, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-83 · Los comodines de la búsqueda se tratan como texto (no devuelven todo)','ok',coalesce(((v_r->>'count')::int = 0), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    v_r := public.history_search(v_oa, '___', null, null, null, null, null, null, null, false, 50, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-84 · El guion bajo tampoco es comodín','ok',coalesce(((v_r->>'count')::int = 0), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.history_search(v_oa, 'ab', null, null, null, null, null, null, null, false, 50, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-85 · Una búsqueda de menos de 3 caracteres se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-85 · Una búsqueda de menos de 3 caracteres se rechaza','ok',sqlerrm like 'Escriba al menos 3 caracteres para buscar%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.history_search(v_oa, repeat('a', 81), null, null, null, null, null, null, null, false, 50, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-86 · Una búsqueda de más de 80 caracteres se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-86 · Una búsqueda de más de 80 caracteres se rechaza','ok',sqlerrm like 'La búsqueda no puede pasar de 80 caracteres%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.history_search(v_oa, null, null, null, current_date, current_date - 5, null, null, null, false, 50, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-87 · Un rango de fechas al revés se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-87 · Un rango de fechas al revés se rechaza','ok',sqlerrm like 'La fecha final no puede ser anterior a la inicial%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.history_search(v_oa, null, null, null, current_date - 4000, current_date, null, null, null, false, 50, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-88 · Un rango de más de 10 años se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-88 · Un rango de más de 10 años se rechaza','ok',sqlerrm like 'El rango de fechas no puede pasar de 10 años%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.history_search(v_oa, null, null, null, null, null, null, 500, 100, false, 50, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-89 · Un monto máximo menor que el mínimo se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-89 · Un monto máximo menor que el mínimo se rechaza','ok',sqlerrm like 'El monto máximo no puede ser menor que el mínimo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.history_search(v_oa, null, null, null, null, null, 'inventado', null, null, false, 50, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-90 · Un estado desconocido se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-90 · Un estado desconocido se rechaza','ok',sqlerrm like 'Estado de reclamación desconocido%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.history_search(v_oa, null, null, null, null, null, null, null, null, false, 50, '{"d": "no-es-fecha", "id": "x"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-91 · Una marca de página inválida se rechaza con indicación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-91 · Una marca de página inválida se rechaza con indicación','ok',sqlerrm like 'La marca de página no es válida%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.history_search(null, null, null, null, null, null, null, null, null, false, 100, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-92 · El Médico (cliente A) busca sin indicar cliente y solo ve lo suyo','ok',coalesce(((v_r->>'count')::int = 11 and not exists (select 1 from jsonb_array_elements(v_r->'rows') e where (e->>'organization_id')::uuid <> v_oa)), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.history_search(v_ob, null, null, null, null, null, null, null, null, false, 50, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-93 · ATAQUE: el Médico no busca en el histórico de otro consultorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-93 · ATAQUE: el Médico no busca en el histórico de otro consultorio','ok',sqlerrm like 'Ese cliente no existe o no está entre los que usted puede ver%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.history_search(null, null, null, null, null, null, null, null, null, false, 100, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-94 · El otro operador solo ve sus datos (1 reclamación del cliente X), nada de SOFA','ok',coalesce(((v_r->>'count')::int = 1 and (v_r->'rows'->0->>'organization_id')::uuid = v_ox), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.history_search(v_oa, null, null, null, null, null, null, null, null, false, 50, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-95 · ATAQUE: el otro operador no busca en el cliente A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-95 · ATAQUE: el otro operador no busca en el cliente A','ok',sqlerrm like 'Ese cliente no existe o no está entre los que usted puede ver%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_cp, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.history_search(null, null, null, null, null, null, null, null, null, false, 100, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-96 · La Secretaria (capturista) no busca en el histórico: no tiene clientes visibles','ok',coalesce(((v_r->>'count')::int = 0), false),'d',(v_r->>'count')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.history_search(null, null, null, null, null, null, null, null, null, false, 50, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-97 · Sin sesión no se busca en el histórico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-97 · Sin sesión no se busca en el histórico','ok',sqlerrm like 'Inicie sesión para buscar en el histórico%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.perf_record('cartera', 850);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-98 · Registrar un tiempo válido: devuelve verdadero y guarda solo operador, ruta, milisegundos y fecha','ok',coalesce((exists (select 1 from public.perf_metrics where route = 'cartera' and ms = 850 and operator_id = '00000000-0000-4000-8000-000000000001'::uuid) and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'perf_metrics' and column_name in ('user_id','created_by','email','org','organization_id'))), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-98 · Registrar un tiempo válido: devuelve verdadero y guarda solo operador, ruta, milisegundos y fecha','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.perf_record(' Cartera ', 900);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-99 · Una ruta en mayúsculas se guarda en minúsculas','ok',coalesce((exists (select 1 from public.perf_metrics where route = 'cartera' and ms = 900)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-99 · Una ruta en mayúsculas se guarda en minúsculas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record('cartera/8d3c5a3e-1111-4222-8333-444455556666', 100) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-100 · Una ruta con un identificador no se registra (devuelve falso)','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where ms = 100)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-100 · Una ruta con un identificador no se registra (devuelve falso)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record('ana@correo.com', 100) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-101 · Una ruta con un correo no se registra (devuelve falso)','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where ms = 100)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-101 · Una ruta con un correo no se registra (devuelve falso)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record('doc-40212345678', 100) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-102 · Una ruta con un número largo no se registra (devuelve falso)','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where ms = 100)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-102 · Una ruta con un número largo no se registra (devuelve falso)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record('', 100) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-103 · Una ruta vacía no se registra (devuelve falso)','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where ms = 100)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-103 · Una ruta vacía no se registra (devuelve falso)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record(repeat('a', 41), 100) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-104 · Una ruta demasiado larga no se registra (devuelve falso)','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where ms = 100)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-104 · Una ruta demasiado larga no se registra (devuelve falso)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record('cartera?q=juan', 100) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-105 · Una ruta con parámetros no se registra (devuelve falso)','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where ms = 100)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-105 · Una ruta con parámetros no se registra (devuelve falso)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record('../admin', 100) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-106 · Una ruta con barras no se registra (devuelve falso)','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where ms = 100)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-106 · Una ruta con barras no se registra (devuelve falso)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record('cartera', -1) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-107 · Un tiempo negativo no se registra','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where route = 'cartera')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-107 · Un tiempo negativo no se registra','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record('cartera', 600001) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-108 · Un tiempo mayor de 10 minutos no se registra','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where route = 'cartera')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-108 · Un tiempo mayor de 10 minutos no se registra','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select case when public.perf_record('cartera', null) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-109 · Un tiempo vacío no se registra','ok',coalesce((v_n = 0 and not exists (select 1 from public.perf_metrics where route = 'cartera')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-109 · Un tiempo vacío no se registra','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.perf_params set rate_per_minute = 3 where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n := (select count(*) from generate_series(1, 6) g where public.perf_record('glosas', 100 + g));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-110 · Tope de frecuencia: con 3 por minuto, el cuarto registro se ignora (devuelve falso) y no estorba','ok',coalesce((v_n = 3 and (select count(*) from public.perf_metrics where route = 'glosas') = 3), false),'d',(v_n::text)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-110 · Tope de frecuencia: con 3 por minuto, el cuarto registro se ignora (devuelve falso) y no estorba','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.perf_params set rate_per_minute = 2 where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.perf_record('glosas', 100); perform public.perf_record('glosas', 101); v_n := (select case when public.perf_record('glosas', 102) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.perf_throttle set window_start = now() - interval '2 minutes' where user_id = v_b1::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n2 := (select case when public.perf_record('glosas', 103) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-111 · Pasado el minuto, el tope se reinicia','ok',coalesce((v_n = 0 and v_n2 = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-111 · Pasado el minuto, el tope se reinicia','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.perf_params set rate_per_minute = 1 where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.perf_record('glosas', 100); v_n := (select case when public.perf_record('glosas', 101) then 1 else 0 end);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_n2 := (select case when public.perf_record('glosas', 102) then 1 else 0 end);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-112 · El tope es por usuario: otro usuario sigue registrando aunque Facturación llegó al suyo','ok',coalesce((v_n = 0 and v_n2 = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-112 · El tope es por usuario: otro usuario sigue registrando aunque Facturación llegó al suyo','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.perf_record('cartera', 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-113 · Sin sesión no se registran tiempos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-113 · Sin sesión no se registran tiempos','ok',sqlerrm like 'Inicie sesión para registrar tiempos de carga%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.perf_metrics where id > 0;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'lenta', 500 + g * 100, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'rapida', 100 + g, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'poca', 9000, now() - interval '1 hour' from generate_series(1, 2) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'vieja', 50000, now() - interval '40 days' from generate_series(1, 5) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select v_op2, 'ajena', 70000, now() - interval '1 hour' from generate_series(1, 9) g;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.perf_report(7);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-114 · El informe calcula p50, p95 y máximo por pantalla: «lenta» 600..2500 ms tiene p95 de 2405 ms (fuera de la meta de 2 s) y «rapida» queda dentro','ok',coalesce(((select (e->>'p95')::int from jsonb_array_elements(v_r->'routes') e where e->>'route' = 'lenta') = 2405 and (select (e->>'p50')::int from jsonb_array_elements(v_r->'routes') e where e->>'route' = 'lenta') = 1550 and (select (e->>'max')::int from jsonb_array_elements(v_r->'routes') e where e->>'route' = 'lenta') = 2500 and not (select (e->>'ok')::boolean from jsonb_array_elements(v_r->'routes') e where e->>'route' = 'lenta') and (select (e->>'ok')::boolean from jsonb_array_elements(v_r->'routes') e where e->>'route' = 'rapida')), false),'d',(v_r->'routes')::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-114 · El informe calcula p50, p95 y máximo por pantalla: «lenta» 600..2500 ms tiene p95 de 2405 ms (fuera de la meta de 2 s) y «rapida» queda dentro','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.perf_metrics where id > 0;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'lenta', 500 + g * 100, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'rapida', 100 + g, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'poca', 9000, now() - interval '1 hour' from generate_series(1, 2) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'vieja', 50000, now() - interval '40 days' from generate_series(1, 5) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select v_op2, 'ajena', 70000, now() - interval '1 hour' from generate_series(1, 9) g;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.perf_report(7);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-115 · El informe marca «pocos datos» (menos de 5), ignora lo de hace más de 7 días y no mezcla otro operador','ok',coalesce((not (select (e->>'enough')::boolean from jsonb_array_elements(v_r->'routes') e where e->>'route' = 'poca') and not exists (select 1 from jsonb_array_elements(v_r->'routes') e where e->>'route' in ('vieja','ajena')) and (v_r->'overall'->>'n')::int = 42), false),'d',(v_r->'overall')::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-115 · El informe marca «pocos datos» (menos de 5), ignora lo de hace más de 7 días y no mezcla otro operador','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.perf_metrics where id > 0;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'lenta', 500 + g * 100, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'rapida', 100 + g, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'poca', 9000, now() - interval '1 hour' from generate_series(1, 2) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'vieja', 50000, now() - interval '40 days' from generate_series(1, 5) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select v_op2, 'ajena', 70000, now() - interval '1 hour' from generate_series(1, 9) g;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.perf_report(90);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-116 · El informe de 90 días sí incluye lo de hace 40 días','ok',coalesce((exists (select 1 from jsonb_array_elements(v_r->'routes') e where e->>'route' = 'vieja') and (v_r->>'days')::int = 90), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-116 · El informe de 90 días sí incluye lo de hace 40 días','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.perf_report(5000);
      v_r2 := public.perf_report(-4);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-117 · Los días del informe se limitan entre 1 y 90','ok',coalesce(((v_r->>'days')::int = 90 and (v_r2->>'days')::int = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-117 · Los días del informe se limitan entre 1 y 90','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.perf_metrics where id > 0;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'lenta', 500 + g * 100, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'rapida', 100 + g, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'poca', 9000, now() - interval '1 hour' from generate_series(1, 2) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'vieja', 50000, now() - interval '40 days' from generate_series(1, 5) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select v_op2, 'ajena', 70000, now() - interval '1 hour' from generate_series(1, 9) g;
      update public.perf_params set p95_target_ms = 3000 where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.perf_report(7);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-118 · Con la meta en 3 s, «lenta» pasa a estar dentro de la meta','ok',coalesce(((select (e->>'ok')::boolean from jsonb_array_elements(v_r->'routes') e where e->>'route' = 'lenta') and (v_r->>'target_ms')::int = 3000), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-118 · Con la meta en 3 s, «lenta» pasa a estar dentro de la meta','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.perf_metrics where id > 0;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'lenta', 500 + g * 100, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'rapida', 100 + g, now() - interval '1 hour' from generate_series(1, 20) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'poca', 9000, now() - interval '1 hour' from generate_series(1, 2) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select '00000000-0000-4000-8000-000000000001'::uuid, 'vieja', 50000, now() - interval '40 days' from generate_series(1, 5) g;
      insert into public.perf_metrics (operator_id, route, ms, at) select v_op2, 'ajena', 70000, now() - interval '1 hour' from generate_series(1, 9) g;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.perf_report(7);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-119 · El otro operador ve solo lo suyo en el informe','ok',coalesce(((v_r->'overall'->>'n')::int = 9 and jsonb_array_length(v_r->'routes') = 1 and v_r->'routes'->0->>'route' = 'ajena'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-119 · El otro operador ve solo lo suyo en el informe','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.perf_report(7);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-120 · Operaciones consulta el informe de tiempos','ok',coalesce((v_r ? 'overall'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.perf_report(7);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-121 · ATAQUE: Facturación no ve los tiempos de carga','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-121 · ATAQUE: Facturación no ve los tiempos de carga','ok',sqlerrm like 'Solo el equipo de SOFA (Super Admin, Administrador u Operaciones) ve los tiempos de carga%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.perf_report(7);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-122 · ATAQUE: el Médico no ve los tiempos de carga','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-122 · ATAQUE: el Médico no ve los tiempos de carga','ok',sqlerrm like 'Solo el equipo de SOFA (Super Admin, Administrador u Operaciones) ve los tiempos de carga%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.perf_db_overview();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-123 · El tamaño de la base trae uso, límite, ritmo, fecha de llenado y la proyección a 50 clientes','ok',coalesce(((v_r->>'size_bytes')::bigint > 0 and (v_r->>'limit_bytes')::bigint = 8589934592 and v_r ? 'growth_bytes_per_day' and v_r ? 'days_to_limit' and v_r ? 'limit_date' and (v_r->>'projected_50_clients_bytes')::bigint >= (v_r->>'size_bytes')::bigint * 0 and v_r->>'state' in ('ok','atencion','critico') and jsonb_array_length(v_r->'biggest_tables') between 1 and 8 and v_r ? 'advice' and v_r ? 'method'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-124 · La consulta del tamaño deja la foto de hoy (una por día)','ok',coalesce(((select count(*) from public.perf_size_log where day = current_date) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.perf_params set db_limit_bytes = 104857600 where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      insert into public.perf_size_log (day, bytes) values (current_date - 10, 1) on conflict (day) do nothing;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.perf_db_overview();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-125 · Con el límite al mínimo (100 MB) y un crecimiento rápido, el estado es crítico y el consejo dice qué hacer','ok',coalesce((v_r->>'state' = 'critico' and v_r->>'advice' like 'Suba de plan%'), false),'d',(v_r::text)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-125 · Con el límite al mínimo (100 MB) y un crecimiento rápido, el estado es crítico y el consejo dice qué hacer','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.perf_params set db_limit_bytes = greatest(pg_database_size(current_database()) + 50 * 1048576, 104857600) where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      insert into public.perf_size_log (day, bytes) values (current_date - 10, pg_database_size(current_database()) - 10 * 1048576) on conflict (day) do nothing;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.perf_db_overview();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-126 · Con fotos de tamaño de hace 10 días el ritmo sale de las fotos: 1 MB por día y se llena en el número de días esperado','ok',coalesce((v_r->>'method' = 'fotos diarias del tamaño' and abs((v_r->>'growth_bytes_per_day')::bigint - 1048576) < 262144 and abs((v_r->>'days_to_limit')::int - ((v_r->>'limit_bytes')::bigint - (v_r->>'size_bytes')::bigint) / 1048576) <= 3), false),'d',(v_r::text)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-126 · Con fotos de tamaño de hace 10 días el ritmo sale de las fotos: 1 MB por día y se llena en el número de días esperado','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.perf_db_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-127 · ATAQUE: Operaciones no ve el tamaño de la base','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-127 · ATAQUE: Operaciones no ve el tamaño de la base','ok',sqlerrm like 'Solo el Super Admin o el Administrador ven el tamaño de la base y su proyección%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.perf_db_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-128 · ATAQUE: Facturación no ve el tamaño de la base','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-128 · ATAQUE: Facturación no ve el tamaño de la base','ok',sqlerrm like 'Solo el Super Admin o el Administrador ven el tamaño de la base y su proyección%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.perf_params_get();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-129 · Operaciones ve los parámetros pero no los edita','ok',coalesce(((v_r->>'p95_target_ms')::int = 2000 and not (v_r->>'can_edit')::boolean), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.perf_params_set(null, 1000, null, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-130 · ATAQUE: Operaciones no cambia los parámetros','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-130 · ATAQUE: Operaciones no cambia los parámetros','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian los parámetros de rendimiento%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.perf_params_set(1000, null, null, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-131 · Un límite de base menor de 100 MB se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-131 · Un límite de base menor de 100 MB se rechaza','ok',sqlerrm like 'El límite de la base no puede ser menor de 100 MB%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.perf_params_set(null, 100, null, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-132 · Una meta fuera de 200 a 60000 ms se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-132 · Una meta fuera de 200 a 60000 ms se rechaza','ok',sqlerrm like 'La meta de tiempo va de 200 a 60000 milisegundos%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.perf_params_set(null, null, 3, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-133 · Una conservación fuera de 7 a 730 días se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-133 · Una conservación fuera de 7 a 730 días se rechaza','ok',sqlerrm like 'Los días de conservación de las métricas van de 7 a 730%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.perf_params_set(null, null, null, -1, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-134 · Una espera para archivar fuera de 0 a 3650 días se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-134 · Una espera para archivar fuera de 0 a 3650 días se rechaza','ok',sqlerrm like 'Los días de espera para archivar van de 0 a 3650%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.perf_params_set(null, null, null, null, 0);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-135 · Un tope por minuto fuera de 1 a 600 se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-135 · Un tope por minuto fuera de 1 a 600 se rechaza','ok',sqlerrm like 'El tope de registros por minuto va de 1 a 600%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.perf_params_set(17179869184, 1500, null, 30, null);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-136 · El Administrador cambia los parámetros (límite 16 GB, meta 1,5 s) y quedan en la bitácora','ok',coalesce(((v_r->>'db_limit_bytes')::bigint = 17179869184 and (v_r->>'p95_target_ms')::int = 1500 and (select archive_min_days from public.perf_params where operator_id = '00000000-0000-4000-8000-000000000001'::uuid) = 30 and exists (select 1 from public.audit_log where table_name = 'perf_params' and operation = 'UPDATE' and new_values->>'p95_target_ms' = '1500')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-136 · El Administrador cambia los parámetros (límite 16 GB, meta 1,5 s) y quedan en la bitácora','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.perf_params set archive_min_days = 0 where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-137 · Con la espera en 0 días, un mes recién terminado ya se puede archivar','ok',coalesce((cardinality(app.archive_blockers(v_oa, v_m1)) = 0), false),'d',(app.archive_blockers(v_oa, v_m1)::text)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-137 · Con la espera en 0 días, un mes recién terminado ya se puede archivar','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.perf_metrics where id > 0;
      insert into public.perf_metrics (operator_id, route, ms, at) values ('00000000-0000-4000-8000-000000000001'::uuid, 'vieja', 100, now() - interval '100 days'), ('00000000-0000-4000-8000-000000000001'::uuid, 'nueva', 100, now() - interval '2 days');
      v_n := app.perf_purge();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-138 · La limpieza borra las métricas más viejas que la conservación (90 días) y deja las recientes','ok',coalesce((v_n = 1 and not exists (select 1 from public.perf_metrics where route = 'vieja') and exists (select 1 from public.perf_metrics where route = 'nueva')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-138 · La limpieza borra las métricas más viejas que la conservación (90 días) y deja las recientes','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.perf_metrics where id > 0;
      update public.perf_params set retention_days = 7 where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      insert into public.perf_metrics (operator_id, route, ms, at) values ('00000000-0000-4000-8000-000000000001'::uuid, 'vieja', 100, now() - interval '10 days'), ('00000000-0000-4000-8000-000000000001'::uuid, 'nueva', 100, now() - interval '2 days');
      v_n := app.perf_purge();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-139 · La limpieza respeta una conservación distinta (7 días)','ok',coalesce((v_n = 1 and exists (select 1 from public.perf_metrics where route = 'nueva')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-139 · La limpieza respeta una conservación distinta (7 días)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.perf_throttle (user_id, window_start, n) values (v_b1::uuid, now() - interval '3 days', 5);
      v_n := app.perf_purge();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-140 · La limpieza borra las filas de tope de frecuencia de más de un día','ok',coalesce((not exists (select 1 from public.perf_throttle where user_id = v_b1::uuid)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-140 · La limpieza borra las filas de tope de frecuencia de más de un día','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform app.perf_size_snapshot(); perform app.perf_size_snapshot();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-141 · La foto de tamaño es una por día (repetirla no duplica)','ok',coalesce(((select count(*) from public.perf_size_log where day = current_date) = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-141 · La foto de tamaño es una por día (repetirla no duplica)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      create table public.qa_ra_idx (a int, b int, c int);
      create index qa_ra_idx_a_b on public.qa_ra_idx (a, b);
      v_p := app.perf_ensure_index('qa_ra_idx_nuevo', 'public.qa_ra_idx'::regclass, array['a'], 'create index qa_ra_idx_nuevo on public.qa_ra_idx (a)');
      v_plan := app.perf_ensure_index('qa_ra_idx_c', 'public.qa_ra_idx'::regclass, array['c'], 'create index qa_ra_idx_c on public.qa_ra_idx (c)');
      v_n := (select count(*) from pg_indexes where tablename = 'qa_ra_idx');
      v_id := null;
      v_cur := to_jsonb(app.perf_ensure_index('qa_ra_idx_c', 'public.qa_ra_idx'::regclass, array['c'], 'create index qa_ra_idx_c on public.qa_ra_idx (c)'));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-142 · perf_ensure_index no crea un índice si ya existe uno equivalente con otro nombre, y no duplica','ok',coalesce((v_p like 'omitido qa_ra_idx_nuevo: ya existe qa_ra_idx_a_b' and v_plan = 'creado qa_ra_idx_c' and v_n = 2 and v_cur #>> '{}' = 'ya existe qa_ra_idx_c'), false),'d',(v_p || ' / ' || v_plan)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-142 · perf_ensure_index no crea un índice si ya existe uno equivalente con otro nombre, y no duplica','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      create table public.qa_ra_idx2 (a int, b boolean);
      create index qa_ra_idx2_p on public.qa_ra_idx2 (a) where b;
      v_p := app.perf_ensure_index('qa_ra_idx2_full', 'public.qa_ra_idx2'::regclass, array['a'], 'create index qa_ra_idx2_full on public.qa_ra_idx2 (a)');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-143 · Un índice parcial no cuenta como equivalente de uno completo (se crea el completo)','ok',coalesce((v_p = 'creado qa_ra_idx2_full'), false),'d',(v_p)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-143 · Un índice parcial no cuenta como equivalente de uno completo (se crea el completo)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-144 · Hay índices perf64_ nuevos o ya existían equivalentes: para cada llave medida existe un índice válido que empieza por esas columnas','ok',coalesce((not exists (select 1 from (values ('public.payment_line_allocations'::regclass, array['service_line_id']), ('public.claim_status_history'::regclass, array['service_line_id']), ('public.tariff_discrepancies'::regclass, array['service_line_id']), ('public.claim_dossier_exceptions'::regclass, array['service_line_id'])) k(t, cols) where not exists (select 1 from pg_index i where i.indrelid = k.t and i.indisvalid and (select array_agg(a.attname::text order by x.ord) from unnest(i.indkey::int2[]) with ordinality x(attnum, ord) join pg_attribute a on a.attrelid = i.indrelid and a.attnum = x.attnum where x.ord <= cardinality(k.cols)) = k.cols))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-145 · No hay índices duplicados entre los perf64_ (ni dos con las mismas columnas y condición en la misma tabla)','ok',coalesce((not exists (select 1 from pg_index i1 join pg_index i2 on i1.indrelid = i2.indrelid and i1.indexrelid < i2.indexrelid and i1.indkey::text = i2.indkey::text and coalesce(pg_get_expr(i1.indpred, i1.indrelid), '') = coalesce(pg_get_expr(i2.indpred, i2.indrelid), '') join pg_class c1 on c1.oid = i1.indexrelid join pg_class c2 on c2.oid = i2.indexrelid where c1.relname like 'perf64\_%' or c2.relname like 'perf64\_%')), false),'d',((select string_agg(c1.relname || '=' || c2.relname, ', ') from pg_index i1 join pg_index i2 on i1.indrelid = i2.indrelid and i1.indexrelid < i2.indexrelid and i1.indkey::text = i2.indkey::text join pg_class c1 on c1.oid = i1.indexrelid join pg_class c2 on c2.oid = i2.indexrelid where c1.relname like 'perf64\_%' or c2.relname like 'perf64\_%'))::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-146 · Los índices perf64_ son válidos y no están a medio crear','ok',coalesce((not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname like 'perf64\_%' and (not i.indisvalid or not i.indisready))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      set local enable_seqscan = off;
      set local enable_bitmapscan = off;
      for v_p in execute 'explain (format text) select coalesce(sum(amount), 0) from public.payment_line_allocations where service_line_id = ''00000000-0000-4000-8000-000000000001'' and superseded_at is null' loop v_plan := coalesce(v_plan, '') || v_p || E'\n'; end loop;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-147 · Plan: las asignaciones de pago de una reclamación se buscan por índice (no recorren toda la tabla)','ok',coalesce((v_plan ~ 'Index (Only )?Scan using [a-z0-9_]+ on payment_line_allocations'), false),'d',(v_plan)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-147 · Plan: las asignaciones de pago de una reclamación se buscan por índice (no recorren toda la tabla)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      set local enable_seqscan = off;
      set local enable_bitmapscan = off;
      for v_p in execute 'explain (format text) select h.comment from public.claim_status_history h where h.service_line_id = ''00000000-0000-4000-8000-000000000001'' order by h.changed_at desc, h.id desc limit 1' loop v_plan := coalesce(v_plan, '') || v_p || E'\n'; end loop;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-148 · Plan: el último movimiento de una reclamación se busca por índice','ok',coalesce((v_plan ~ 'Index (Only )?Scan( Backward)? using [a-z0-9_]+ on claim_status_history'), false),'d',(v_plan)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-148 · Plan: el último movimiento de una reclamación se busca por índice','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      set local enable_seqscan = off;
      set local enable_bitmapscan = off;
      for v_p in execute 'explain (format text) select d.status from public.tariff_discrepancies d where d.service_line_id = ''00000000-0000-4000-8000-000000000001'' order by d.created_at desc limit 1' loop v_plan := coalesce(v_plan, '') || v_p || E'\n'; end loop;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-149 · Plan: las discrepancias de tarifa de una reclamación se buscan por índice','ok',coalesce((v_plan ~ 'Index (Only )?Scan( Backward)? using [a-z0-9_]+ on tariff_discrepancies'), false),'d',(v_plan)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-149 · Plan: las discrepancias de tarifa de una reclamación se buscan por índice','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      set local enable_seqscan = off;
      set local enable_bitmapscan = off;
      for v_p in execute 'explain (format text) select 1 from public.claim_dossier_exceptions e where e.service_line_id = ''00000000-0000-4000-8000-000000000001'' and e.revoked_at is null' loop v_plan := coalesce(v_plan, '') || v_p || E'\n'; end loop;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-150 · Plan: las excepciones de expediente de una reclamación se buscan por índice','ok',coalesce((v_plan ~ 'Index (Only )?Scan using [a-z0-9_]+ on claim_dossier_exceptions'), false),'d',(v_plan)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-150 · Plan: las excepciones de expediente de una reclamación se buscan por índice','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-151 · Las políticas de lectura de la secretaria evalúan primero si el usuario es secretaria (una sola vez) antes de revisar fila por fila','ok',coalesce(((select count(*) from pg_policies where schemaname = 'public' and ((tablename = 'service_lines' and policyname = 'service_lines_select_capturer') or (tablename = 'documents' and policyname = 'documents_select_capturer') or (tablename = 'line_document_checks' and policyname = 'line_document_checks_select_capturer') or (tablename = 'claim_dossier_exceptions' and policyname = 'claim_dossier_exceptions_select_capturer') or (tablename = 'claim_resubmissions' and policyname = 'claim_resubmissions_select_capturer')) and qual like '%capturer_any%') = 5), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-152 · Las políticas de lectura de historial, auditorías y diferencias de tarifa también evalúan primero si el usuario es secretaria','ok',coalesce(((select count(*) from pg_policies where schemaname = 'public' and policyname in ('claim_status_history_select','claim_audits_select','tariff_discrepancies_select') and qual like '%capturer_any%') = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_cp, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.service_lines;
    select count(*) into v_n2 from public.submissions;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-153 · La Secretaria sigue viendo las reclamaciones y los lotes de sus médicos asignados (11 reclamaciones del cliente A y 8 lotes), nada del cliente B','ok',coalesce((v_n = 11 and v_n2 = 8), false),'d',(v_n || ' / ' || v_n2)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_cp, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      if exists (select 1 from public.service_lines where id = v_lb) then raise exception 'Se vio'; end if; raise exception 'No se ve';
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-154 · ATAQUE: la Secretaria no ve reclamaciones de otro consultorio por id','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-154 · ATAQUE: la Secretaria no ve reclamaciones de otro consultorio por id','ok',sqlerrm like 'No se ve','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.service_lines;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-155 · El Médico (cliente) sigue viendo todas las reclamaciones de su consultorio (11)','ok',coalesce((v_n = 11), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.service_lines;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-156 · El otro operador solo ve sus reclamaciones (1)','ok',coalesce((v_n = 1), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from (select o.id from public.organizations o where app.can(o.id, array['super_admin','admin','billing','glosas','auditor','client']) except select app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client'])) x;
    select count(*) into v_n2 from (select app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client']) except select o.id from public.organizations o where app.can(o.id, array['super_admin','admin','billing','glosas','auditor','client'])) x;
    select count(*)::text into v_ids from app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client']);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-157 · can_orgs devuelve exactamente las organizaciones donde app.can da verdadero para el Administrador','ok',coalesce((v_n = 0 and v_n2 = 0 and v_ids::int >= 1), false),'d',(v_n || ' / ' || v_n2 || ' de ' || v_ids)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from (select o.id from public.organizations o where app.can(o.id, array['super_admin','admin','billing','glosas','auditor','client']) except select app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client'])) x;
    select count(*) into v_n2 from (select app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client']) except select o.id from public.organizations o where app.can(o.id, array['super_admin','admin','billing','glosas','auditor','client'])) x;
    select count(*)::text into v_ids from app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client']);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-158 · can_orgs devuelve exactamente las organizaciones donde app.can da verdadero para Facturación','ok',coalesce((v_n = 0 and v_n2 = 0 and v_ids::int >= 1), false),'d',(v_n || ' / ' || v_n2 || ' de ' || v_ids)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from (select o.id from public.organizations o where app.can(o.id, array['super_admin','admin','billing','glosas','auditor','client']) except select app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client'])) x;
    select count(*) into v_n2 from (select app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client']) except select o.id from public.organizations o where app.can(o.id, array['super_admin','admin','billing','glosas','auditor','client'])) x;
    select count(*)::text into v_ids from app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client']);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-159 · can_orgs devuelve exactamente las organizaciones donde app.can da verdadero para el Médico del cliente A','ok',coalesce((v_n = 0 and v_n2 = 0 and v_ids::int >= 1), false),'d',(v_n || ' / ' || v_n2 || ' de ' || v_ids)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from (select o.id from public.organizations o where app.can(o.id, array['super_admin','admin','billing','glosas','auditor','client']) except select app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client'])) x;
    select count(*) into v_n2 from (select app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client']) except select o.id from public.organizations o where app.can(o.id, array['super_admin','admin','billing','glosas','auditor','client'])) x;
    select count(*)::text into v_ids from app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client']);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-160 · can_orgs devuelve exactamente las organizaciones donde app.can da verdadero para el Administrador de otro operador','ok',coalesce((v_n = 0 and v_n2 = 0 and v_ids::int >= 1), false),'d',(v_n || ' / ' || v_n2 || ' de ' || v_ids)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from app.can_orgs(null);
    select count(*) into v_n2 from public.organizations o where app.can(o.id, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-161 · can_orgs sin lista de roles (cualquier rol) coincide con app.can sin roles','ok',coalesce((v_n = v_n2 and v_n >= 1), false),'d',(v_n || ' / ' || v_n2)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_cp, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from app.can_orgs(array['super_admin','admin','billing','glosas','auditor','client']);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-162 · ATAQUE: la Secretaria (capturer) no obtiene ninguna organización de can_orgs con los roles de gestión','ok',coalesce((v_n = 0), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select count(*) into v_n from app.can_orgs(null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-163 · ATAQUE: sin sesión (SQL Editor, sin usuario) can_orgs no devuelve nada','ok',coalesce((v_n = 0), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-164 · ATAQUE: anon no puede ejecutar can_orgs, capturer_any ni submission_docs; authenticated sí','ok',coalesce((not has_function_privilege('anon', 'app.can_orgs(text[])', 'execute') and not has_function_privilege('anon', 'app.capturer_any()', 'execute') and not has_function_privilege('anon', 'app.submission_docs(uuid)', 'execute') and has_function_privilege('authenticated', 'app.can_orgs(text[])', 'execute') and has_function_privilege('authenticated', 'app.capturer_any()', 'execute') and has_function_privilege('authenticated', 'app.submission_docs(uuid)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from (select d.pct, d.complete_lines from app.submission_docs(v_s1) d except select coalesce(round(avg(c.pct)), 0), count(*) filter (where c.complete) from public.v_line_checklist c where c.submission_id = v_s1) x;
    select count(*) into v_n2 from public.v_line_checklist c where c.submission_id = v_s1;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-165 · submission_docs da lo mismo que el cálculo original por reclamación (el Administrador)','ok',coalesce((v_n = 0 and v_n2 >= 1), false),'d',(v_n || ' / ' || v_n2)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from (select d.pct, d.complete_lines from app.submission_docs(v_s1) d except select coalesce(round(avg(c.pct)), 0), count(*) filter (where c.complete) from public.v_line_checklist c where c.submission_id = v_s1) x;
    select count(*) into v_n2 from public.v_line_checklist c where c.submission_id = v_s1;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-166 · submission_docs da lo mismo que el cálculo original por reclamación (el Médico)','ok',coalesce((v_n = 0 and v_n2 >= 1), false),'d',(v_n || ' / ' || v_n2)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_cp, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from (select d.pct, d.complete_lines from app.submission_docs(v_s4) d except select coalesce(round(avg(c.pct)), 0), count(*) filter (where c.complete) from public.v_line_checklist c where c.submission_id = v_s4) x;
    select count(*) into v_n2 from public.v_line_checklist c where c.submission_id = v_s4;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-167 · submission_docs da lo mismo que el cálculo original por reclamación (la Secretaria)','ok',coalesce((v_n = 0 and v_n2 >= 1), false),'d',(v_n || ' / ' || v_n2)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select d.complete_lines into v_n from app.submission_docs(v_sb1) d;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-168 · ATAQUE: el Médico del cliente A no obtiene cifras de un lote del cliente B (0 reclamaciones visibles)','ok',coalesce((v_n = 0), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.v_submissions v where v.id = v_s1 and v.docs_pct = (select coalesce(round(avg(c.pct)), 0) from public.v_line_checklist c where c.submission_id = v.id) and v.complete_lines = (select count(*) filter (where c.complete) from public.v_line_checklist c where c.submission_id = v.id);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-169 · v_submissions trae el mismo porcentaje de expediente y reclamaciones completas que antes','ok',coalesce((v_n = 1), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.v_stage_times where ars_id is null and claims = (select count(*) from public.v_claim_milestones where m01_capturada >= now() - interval '365 days');
    select (select sum(claims) from public.v_stage_times where ars_id is not null) = (select claims from public.v_stage_times where ars_id is null) into v_ok;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-170 · v_stage_times: el total (todas las ARS) coincide con las reclamaciones del año y con la suma por ARS','ok',coalesce((v_n = 1 and v_ok), false),'d',(v_n || ' / ' || v_ok::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select app.claim_paid_visible(v_l5) = (select coalesce(sum(amount), 0) from public.payment_line_allocations where service_line_id = v_l5 and superseded_at is null) into v_ok;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-171 · claim_paid_visible da lo pagado a quien ve el cobro (Administrador)','ok',coalesce((v_ok), false),'d',(v_ok::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_cp, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select app.claim_paid_visible(v_l1) is null into v_ok;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-172 · ATAQUE: la Secretaria no ve lo pagado de una reclamación (claim_paid_visible devuelve nulo)','ok',coalesce((v_ok), false),'d',(v_ok::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select app.claim_paid_visible(v_lb) is null into v_ok;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-173 · ATAQUE: el Médico del cliente A no ve lo pagado de una reclamación del cliente B','ok',coalesce((v_ok), false),'d',(v_ok::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-174 · Las funciones de seguridad convertidas (visible_org_ids, role_for_org, can, is_staff, is_active_user, capturer_providers, claim_access_role) siguen siendo SECURITY DEFINER con search_path vacío','ok',coalesce((not exists (select 1 from pg_proc p where p.pronamespace = 'app'::regnamespace and p.proname in ('visible_org_ids','role_for_org','can','is_staff','is_active_user','capturer_providers','claim_access_role','capturer_any','can_orgs','claim_paid','claim_paid_visible') and (not p.prosecdef or not (p.proconfig @> array['search_path=""']) or p.prolang <> (select oid from pg_language where lanname = 'plpgsql')))), false),'d',((select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'app'::regnamespace and p.proname in ('visible_org_ids','role_for_org','can','is_staff','is_active_user','capturer_providers','claim_access_role','capturer_any','can_orgs','claim_paid','claim_paid_visible') and (not p.prosecdef or not (p.proconfig @> array['search_path=""']))))::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-175 · Las funciones del expediente convertidas (required_docs, claim_dossier_items, claim_missing_docs, claim_dossier_ok, submission_docs) siguen con permisos de quien llama (no SECURITY DEFINER)','ok',coalesce((not exists (select 1 from pg_proc p where p.pronamespace = 'app'::regnamespace and p.proname in ('required_docs','claim_dossier_items','claim_missing_docs','claim_dossier_ok','submission_docs') and p.prosecdef)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-176 · Las dos pantallas pesadas y la búsqueda del histórico llevan jit apagado; la búsqueda también plan por llamada (filtros opcionales)','ok',coalesce(((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('practice_dashboard','work_queue','history_search') and p.proconfig @> array['jit=off']) = 3 and (select p.proconfig @> array['plan_cache_mode=force_custom_plan'] from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'history_search')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-177 · Las copias para revertir existen: 13 o más funciones/vistas y 60 o más políticas, incluidas v_submissions y v_stage_times','ok',coalesce(((select count(*) from public.perf_func_backup) >= 13 and (select count(*) from public.perf_policy_backup) >= 60 and exists (select 1 from public.perf_func_backup where clave = 'public.v_submissions' and tipo = 'vista') and exists (select 1 from public.perf_func_backup where clave = 'public.v_stage_times' and tipo = 'vista')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-178 · Las copias guardadas son las originales: la vista v_submissions guardada usa v_submission_checklist y la función visible_org_ids guardada es de lenguaje sql','ok',coalesce(((select definicion from public.perf_func_backup where clave = 'public.v_submissions') like '%v_submission_checklist%' and (select definicion from public.perf_func_backup where clave = 'app.visible_org_ids()') like '%LANGUAGE sql%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-179 · Las tablas de copias no se tocan por la API (sin permisos para anon ni authenticated y con RLS)','ok',coalesce((not exists (select 1 from unnest(array['perf_func_backup','perf_policy_backup']) t where has_table_privilege('authenticated', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'select') or not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.payment_line_allocations;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select count(*) into v_n2 from public.payment_line_allocations where organization_id = v_oa;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-180 · Las asignaciones de pago por reclamación las ve el Médico del cliente A igual que antes (solo las de su consultorio)','ok',coalesce((v_n = v_n2), false),'d',(v_n || ' / ' || v_n2)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.payment_line_allocations where organization_id = v_oa;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-181 · ATAQUE: el Médico del cliente B no ve las asignaciones de pago del cliente A','ok',coalesce((v_n = 0), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.payment_line_allocations where organization_id = v_oa;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-182 · ATAQUE: el Administrador de otro operador no ve las asignaciones de pago del cliente A','ok',coalesce((v_n = 0), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_cp, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.payment_line_allocations;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-183 · ATAQUE: la Secretaria no ve ninguna asignación de pago','ok',coalesce((v_n = 0), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.profiles set is_active = false where id = v_ma::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      select count(*) into v_n from public.procedures;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-184 · ATAQUE: un usuario desactivado ya no lee los catálogos (is_active_user envuelto sigue funcionando)','ok',coalesce((v_n = 0), false),'d',(v_n::text)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas: RA-184 · ATAQUE: un usuario desactivado ya no lee los catálogos (is_active_user envuelto sigue funcionando)','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.procedures;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-185 · Un usuario activo sí lee los catálogos','ok',coalesce((v_n > 0), false),'d',(v_n::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_cp, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.archive_period(v_oa, v_m6, 'intento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-186 · ATAQUE: la Secretaria no archiva periodos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-186 · ATAQUE: la Secretaria no archiva periodos','ok',sqlerrm like '%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_n := 0;
    for v_n2 in 1..8 loop
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.history_search(v_oa, null, null, null, null, null, null, null, null, false, 5, null);
      v_n := v_n + (v_r->>'count')::int;
      v_r := public.history_search(null, 'Archivo', null, null, null, null, null, null, null, false, 5, null);
      v_n := v_n + (v_r->>'count')::int;
    end loop;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RA-187 · La búsqueda da el mismo resultado en 8 llamadas seguidas de la misma sesión (sin plan genérico que cambie el resultado)','ok',coalesce((v_n = 8 * 10), false),'d',(v_n::text)::text));
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

revoke all on function app.qa_run_tests_rendimiento() from public, anon, authenticated;
