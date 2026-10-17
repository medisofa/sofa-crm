-- 197 · Suite de la 196 (expediente digital por reclamación, I62). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_expediente();
create or replace function app.qa_run_tests_expediente()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_oa constant uuid := '01960000-0000-4000-8000-000000000001'; v_ob constant uuid := '01960000-0000-4000-8000-000000000002'; v_pa constant uuid := '01960000-0000-4000-8000-000000000011'; v_pb constant uuid := '01960000-0000-4000-8000-000000000012';
  v_sa constant text := '01960000-0000-4000-8000-000000000021'; v_ad constant text := '01960000-0000-4000-8000-000000000022'; v_ops constant text := '01960000-0000-4000-8000-000000000023'; v_bil constant text := '01960000-0000-4000-8000-000000000024'; v_gl constant text := '01960000-0000-4000-8000-000000000025';
  v_au constant text := '01960000-0000-4000-8000-000000000026'; v_co constant text := '01960000-0000-4000-8000-000000000027'; v_ma constant text := '01960000-0000-4000-8000-000000000031'; v_mb constant text := '01960000-0000-4000-8000-000000000032'; v_sec constant text := '01960000-0000-4000-8000-000000000033';
  v_x1 uuid; v_x2 uuid; v_proc uuid; v_per date; v_dt text; v_dm text; v_n0 int;
  v_s1 uuid; v_sr1 uuid; v_sr2 uuid; v_sr3 uuid; v_sb1 uuid; v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid; v_l5 uuid; v_l6 uuid; v_lr1 uuid; v_lr2 uuid; v_lr3 uuid; v_lr3b uuid; v_lb1 uuid; v_l uuid;
  v_r record; v_j jsonb; v_j2 jsonb; v_rl text; v_id uuid; v_cnt1 int; v_cnt2 int; v_docs int; v_mb_total bigint;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '196') then
    raise exception 'Falta la migración 196. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    v_per := date_trunc('month', current_date)::date;
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.ex.sa@sofa.test','x'),(v_ad::uuid,'qa.ex.ad@sofa.test','x'),(v_ops::uuid,'qa.ex.ops@sofa.test','x'),(v_bil::uuid,'qa.ex.bil@sofa.test','x'),(v_gl::uuid,'qa.ex.gl@sofa.test','x'),(v_au::uuid,'qa.ex.au@sofa.test','x'),(v_co::uuid,'qa.ex.co@sofa.test','x'),(v_ma::uuid,'qa.ex.ma@sofa.test','x'),(v_mb::uuid,'qa.ex.mb@sofa.test','x'),(v_sec::uuid,'qa.ex.sec@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ex.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_oa, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I62 A', '00000019601', 'Médico independiente', 'activo', current_date - 90, '8095559601');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_ob, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I62 B', '00000019602', 'Médico independiente', 'activo', current_date - 90, '8095559602');
    update public.organizations set ecf_required_from = date '2099-12-31' where kind = 'client' and ecf_required_from is distinct from date '2099-12-31';
    update public.app_settings set require_delivery_evidence = false where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_oa, 'Dr. A QA', 'Cardiología', true), (v_pb, v_ob, 'Dr. B QA', 'Urología', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing', true),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_gl::uuid, 'glosas', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_au::uuid, 'auditor', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_co::uuid, 'assistant', true),
      (v_oa, v_ma::uuid, 'client', true), (v_ob, v_mb::uuid, 'client', true), (v_oa, v_sec::uuid, 'capturer', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_pa, v_oa, true, true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_i62_x1', 'ARS QA Uno', 'Contributivo', true) returning id into v_x1;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_i62_x2', 'ARS QA Dos', 'Contributivo', true) returning id into v_x2;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    select count(*) into v_n0 from app.required_docs(v_proc, v_x1, 'ambulatorio') where requirement = 'obligatorio';
    select t.code into v_dt from public.document_types t where t.sort_order < 20 and t.code not in (select document_type_code from app.required_docs(v_proc, v_x1, 'ambulatorio')) order by t.sort_order limit 1;
    select r.document_type_code into v_dm from app.required_docs(v_proc, v_x1, 'ambulatorio') r where r.requirement = 'obligatorio' order by r.document_type_code limit 1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_x1, v_per, 1, 'borrador') returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_x1, v_per, 2, 'borrador') returning id into v_sr1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_x1, v_per, 3, 'borrador') returning id into v_sr2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_oa, v_pa, v_x2, v_per, 4, 'borrador') returning id into v_sr3;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_ob, v_pb, v_x1, v_per, 1, 'borrador') returning id into v_sb1;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_s1, v_oa, v_per, 'Paciente QA 1', v_proc, 1, 100, 'M1', 'AU1') returning id into v_l1;
    perform set_config('app.contract_override', '', true);
    for v_r in select i.document_type_code as c from app.claim_dossier_items(v_l1) i where i.mandatory and not i.present order by i.sort_order loop
      insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
      values (v_oa, 'submission', v_s1, v_l1, v_r.c, v_oa::text || '/' || v_s1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 20000);
    end loop;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_s1, v_oa, v_per, 'Paciente QA 2', v_proc, 1, 100, 'M2', 'AU2') returning id into v_l2;
    perform set_config('app.contract_override', '', true);
    for v_r in select i.document_type_code as c from app.claim_dossier_items(v_l2) i where i.mandatory and not i.present order by i.sort_order limit 1 loop
      insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
      values (v_oa, 'submission', v_s1, v_l2, v_r.c, v_oa::text || '/' || v_s1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 20000);
    end loop;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_s1, v_oa, v_per, 'Paciente QA 3', v_proc, 1, 100, 'M3', 'AU3') returning id into v_l3;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_s1, v_oa, v_per, 'Paciente QA 4', v_proc, 1, 100, 'M4', 'AU4') returning id into v_l4;
    perform set_config('app.contract_override', '', true);
    for v_r in select i.document_type_code as c from app.claim_dossier_items(v_l4) i where i.mandatory and not i.present order by i.sort_order limit 3 loop
      insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
      values (v_oa, 'submission', v_s1, v_l4, v_r.c, v_oa::text || '/' || v_s1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 20000);
    end loop;
    select i.document_type_code into v_dm from app.claim_dossier_items(v_l4) i where i.mandatory and not i.present limit 1;
    insert into public.line_document_checks (service_line_id, organization_id, document_type_code, present) values (v_l4, v_oa, v_dm, true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_s1, v_oa, v_per, 'Paciente QA 5', v_proc, 1, 100, 'M5', 'AU5') returning id into v_l5;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number, care_mode) values (v_s1, v_oa, v_per, 'Paciente QA 6', v_proc, 1, 100, 'M6', 'AU6', 'emergencia') returning id into v_l6;
    perform set_config('app.contract_override', '', true);
    insert into public.claim_dossier_exceptions (service_line_id, organization_id, reason, missing) values (v_l5, v_oa, 'QA: excepción autorizada para la prueba', app.claim_missing_docs(v_l5));
    select r.document_type_code into v_dm from app.required_docs(v_proc, v_x1, 'ambulatorio') r where r.requirement = 'obligatorio' order by r.document_type_code limit 1;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sr1, v_oa, v_per, 'Paciente QA 11', v_proc, 1, 100, 'M11', 'AU11') returning id into v_lr1;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sr2, v_oa, v_per, 'Paciente QA 12', v_proc, 1, 100, 'M12', 'AU12') returning id into v_lr2;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sr3, v_oa, v_per, 'Paciente QA 13', v_proc, 1, 100, 'M13', 'AU13') returning id into v_lr3;
    perform set_config('app.contract_override', '', true);
    for v_r in select i.document_type_code as c from app.claim_dossier_items(v_lr3) i where i.mandatory and not i.present order by i.sort_order loop
      insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
      values (v_oa, 'submission', v_sr3, v_lr3, v_r.c, v_oa::text || '/' || v_sr3::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 20000);
    end loop;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sr3, v_oa, v_per, 'Paciente QA 14', v_proc, 1, 100, 'M14', 'AU14') returning id into v_lr3b;
    perform set_config('app.contract_override', '', true);
    for v_r in select i.document_type_code as c from app.claim_dossier_items(v_lr3b) i where i.mandatory and not i.present order by i.sort_order loop
      insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
      values (v_oa, 'submission', v_sr3, v_lr3b, v_r.c, v_oa::text || '/' || v_sr3::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 20000);
    end loop;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sb1, v_ob, v_per, 'Paciente QA 15', v_proc, 1, 100, 'M15', 'AU15') returning id into v_lb1;
    perform set_config('app.contract_override', '', true);
    for v_r in select i.document_type_code as c from app.claim_dossier_items(v_lb1) i where i.mandatory and not i.present order by i.sort_order loop
      insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
      values (v_ob, 'submission', v_sb1, v_lb1, v_r.c, v_ob::text || '/' || v_sb1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 20000);
    end loop;
    update public.submissions set ncf = 'B0100000001', invoice_date = current_date where id = v_sr1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.change_submission_status(v_sr1, 'recibida'); perform public.change_submission_status(v_sr1, 'en_depuracion');
    perform public.change_submission_status(v_sr1, 'lista_para_radicar', null, 'QA: lote de prueba autorizado por administración');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.submissions set fiscal_invoice_number = 'F-1', accountant_name = 'Lic. QA', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_sr1) where id = v_sr1;
    update public.submissions set ncf = 'B0100000002', invoice_date = current_date where id = v_sr2;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.change_submission_status(v_sr2, 'recibida'); perform public.change_submission_status(v_sr2, 'en_depuracion');
    perform public.change_submission_status(v_sr2, 'lista_para_radicar', null, 'QA: lote de prueba autorizado por administración');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.submissions set fiscal_invoice_number = 'F-2', accountant_name = 'Lic. QA', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_sr2) where id = v_sr2;
    update public.submissions set ncf = 'B0100000003', invoice_date = current_date where id = v_sr3;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.change_submission_status(v_sr3, 'recibida'); perform public.change_submission_status(v_sr3, 'en_depuracion');
    perform public.change_submission_status(v_sr3, 'lista_para_radicar', null, 'QA: lote de prueba autorizado por administración');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.submissions set fiscal_invoice_number = 'F-3', accountant_name = 'Lic. QA', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_sr3) where id = v_sr3;
    update public.submissions set ncf = 'B0100000004', invoice_date = current_date where id = v_sb1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.change_submission_status(v_sb1, 'recibida'); perform public.change_submission_status(v_sb1, 'en_depuracion');
    perform public.change_submission_status(v_sb1, 'lista_para_radicar', null, 'QA: lote de prueba autorizado por administración');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.submissions set fiscal_invoice_number = 'F-4', accountant_name = 'Lic. QA', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_sb1) where id = v_sb1;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-01 · La migración 196 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '196')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-02 · Las tres tablas nuevas no se tocan por la API: ni anon ni authenticated tienen permisos','ok',coalesce((not has_table_privilege('authenticated', 'public.dossier_params', 'select') and not has_table_privilege('authenticated', 'public.dossier_params', 'update') and not has_table_privilege('authenticated', 'public.client_storage_limits', 'insert') and not has_table_privilege('authenticated', 'public.client_storage_limits', 'select') and not has_table_privilege('authenticated', 'public.claim_dossier_snapshots', 'insert') and not has_table_privilege('authenticated', 'public.claim_dossier_snapshots', 'select') and not has_table_privilege('anon', 'public.claim_dossier_snapshots', 'select') and not has_table_privilege('anon', 'public.dossier_params', 'select')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-03 · Las funciones públicas no están abiertas a anon y sí a authenticated','ok',coalesce((not has_function_privilege('anon', 'public.dossier_list(uuid,uuid,text,integer,integer)', 'execute') and not has_function_privilege('anon', 'public.dossier_rule_set(uuid,text,text,text)', 'execute') and not has_function_privilege('anon', 'public.storage_usage_report()', 'execute') and not has_function_privilege('anon', 'public.dossier_indicator(uuid,date,date)', 'execute') and not has_function_privilege('anon', 'public.dossier_params_set(boolean,integer,integer,integer,integer)', 'execute') and not has_function_privilege('anon', 'public.client_storage_limit_set(uuid,integer,text)', 'execute') and has_function_privilege('authenticated', 'public.dossier_detail(uuid)', 'execute') and has_function_privilege('authenticated', 'public.storage_usage_org(uuid)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-04 · Las funciones internas no se llaman desde la API','ok',coalesce((not has_function_privilege('authenticated', 'app.dossier_operator(uuid)', 'execute') and not has_function_privilege('authenticated', 'app.storage_status(bigint,integer,integer)', 'execute') and not has_function_privilege('authenticated', 'app.dossier_snapshot_on_radicar()', 'execute') and not has_function_privilege('anon', 'app.storage_status(bigint,integer,integer)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-05 · Las funciones que escriben o miden son SECURITY DEFINER con search_path vacío','ok',coalesce((not exists (select 1 from pg_proc p where p.pronamespace in ('app'::regnamespace, 'public'::regnamespace) and p.proname in ('dossier_params_get','dossier_params_set','dossier_rules_for_ars','dossier_rule_set','dossier_indicator','storage_usage_report','storage_usage_org','client_storage_limit_set','dossier_operator','dossier_snapshot_on_radicar') and (not p.prosecdef or p.proconfig is null or not ('search_path=' = any (p.proconfig) or 'search_path=""' = any (p.proconfig))))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-06 · El listado y el detalle corren con los permisos de quien consulta (no son SECURITY DEFINER)','ok',coalesce(((select not prosecdef from pg_proc where oid = 'public.dossier_list(uuid,uuid,text,integer,integer)'::regprocedure) and (select not prosecdef from pg_proc where oid = 'public.dossier_detail(uuid)'::regprocedure)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-07 · La vista del semáforo corre con los permisos de quien consulta y anon no la lee','ok',coalesce((exists (select 1 from pg_class c where c.oid = 'public.v_claim_dossier_semaforo'::regclass and 'security_invoker=true' = any (c.reloptions)) and not has_table_privilege('anon', 'public.v_claim_dossier_semaforo', 'select') and has_table_privilege('authenticated', 'public.v_claim_dossier_semaforo', 'select')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-08 · Parámetros iniciales: bloqueo APAGADO, conservación 10 años, aviso 80 %, meta 95 %, sin límite general','ok',coalesce(((select not block_radicar and retention_years = 10 and warn_pct = 80 and target_pct = 95 and default_limit_mb is null from public.dossier_params where operator_id = '00000000-0000-4000-8000-000000000001'::uuid)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-09 · Hay un solo índice por cliente y fecha en documents (el nuevo) y la 196 no duplicó ninguno equivalente','ok',coalesce(((select count(*) from pg_indexes where tablename = 'documents' and indexdef like '%(organization_id, uploaded_at)%') = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-10 · Línea base: dos ARS sin reglas propias exigen lo mismo (la regla general) y hay al menos 3 obligatorios','ok',coalesce((v_n0 >= 3 and (select count(*) from app.required_docs(v_proc, v_x2, 'ambulatorio') where requirement = 'obligatorio') = v_n0), false),'d',(v_n0::text)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-11 · Regla por ARS: la ARS 1 exige un documento más y la ARS 2 sigue igual','ok',coalesce(((select count(*) from app.required_docs(v_proc, v_x1, 'ambulatorio') where requirement = 'obligatorio') = v_n0 + 1 and (select count(*) from app.required_docs(v_proc, v_x2, 'ambulatorio') where requirement = 'obligatorio') = v_n0), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-12 · La regla por ARS cambia el semáforo: la reclamación completa de la ARS 1 pasa a parcial','ok',coalesce(((select semaforo from public.v_claim_dossier_semaforo where service_line_id = v_l1) = 'parcial' and (select required from public.v_claim_dossier_semaforo where service_line_id = v_l1) = v_n0 + 1), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dossier_rule_set(v_x1, v_dm, 'no_requerido');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-13 · La regla de la ARS gana sobre la general: un obligatorio marcado «no requerido» deja de exigirse solo en esa ARS','ok',coalesce(((select count(*) from app.required_docs(v_proc, v_x1, 'ambulatorio') where requirement = 'obligatorio') = v_n0 - 1 and (select count(*) from app.required_docs(v_proc, v_x2, 'ambulatorio') where requirement = 'obligatorio') = v_n0), false),'d',(null)::text));
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
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio', 'emergencia');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-14 · Regla por modalidad: aplica a emergencia y no a ambulatorio','ok',coalesce(((select count(*) from app.required_docs(v_proc, v_x1, 'emergencia') where requirement = 'obligatorio' and document_type_code = v_dt) = 1 and (select count(*) from app.required_docs(v_proc, v_x1, 'ambulatorio') where requirement = 'obligatorio' and document_type_code = v_dt) = 0 and (select required from public.v_claim_dossier_semaforo where service_line_id = v_l3) = v_n0 and exists (select 1 from app.claim_dossier_items(v_l6) i where i.document_type_code = v_dt and i.mandatory)), false),'d',(null)::text));
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
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio'); perform public.dossier_rule_set(v_x1, v_dt, 'opcional');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-15 · Guardar dos veces el mismo tipo actualiza la regla y no la duplica','ok',coalesce(((select count(*) from public.document_rules where ars_id = v_x1 and document_type_code = v_dt and procedure_id is null and service_type_code is null and care_mode is null) = 1 and (select requirement from public.document_rules where ars_id = v_x1 and document_type_code = v_dt and procedure_id is null and care_mode is null) = 'opcional'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_rule_set(v_x1, v_dt, 'heredar');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-16 · «Heredar» quita la regla de la ARS y vuelve a regir la general','ok',coalesce(((select count(*) from public.document_rules where ars_id = v_x1 and document_type_code = v_dt) = 0 and (v_j->>'removed')::int = 1 and (select count(*) from app.required_docs(v_proc, v_x1, 'ambulatorio') where requirement = 'obligatorio') = v_n0), false),'d',(null)::text));
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
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio');
      v_j := public.dossier_rules_for_ars(v_x1);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-17 · El detalle de reglas por ARS muestra la regla propia, no incluye los documentos de contrato A–E y dice que se puede editar','ok',coalesce((jsonb_array_length(v_j->'ars_rules') = 1 and (v_j->'ars_rules'->0->>'document_type_code') = v_dt and (v_j->>'can_edit')::boolean and not exists (select 1 from jsonb_array_elements(v_j->'types') t where t->>'code' in ('contrato_sofa','carta_ars'))), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j2 := public.dossier_rules_for_ars(v_x1);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-18 · Facturación puede ver las reglas pero no editarlas (can_edit falso)','ok',coalesce((not (v_j2->>'can_edit')::boolean and jsonb_array_length(v_j2->'ars_rules') = 1), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-19 · ATAQUE: Facturación no configura documentos requeridos por ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-19 · ATAQUE: Facturación no configura documentos requeridos por ARS','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-20 · … y la regla no quedó guardada (Facturación)','ok',coalesce((not exists (select 1 from public.document_rules where ars_id = v_x1)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-21 · ATAQUE: el Médico no configura documentos requeridos por ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-21 · ATAQUE: el Médico no configura documentos requeridos por ARS','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-22 · … y la regla no quedó guardada (el Médico)','ok',coalesce((not exists (select 1 from public.document_rules where ars_id = v_x1)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-23 · ATAQUE: el Auditor no configura documentos requeridos por ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-23 · ATAQUE: el Auditor no configura documentos requeridos por ARS','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-24 · … y la regla no quedó guardada (el Auditor)','ok',coalesce((not exists (select 1 from public.document_rules where ars_id = v_x1)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-25 · ATAQUE: Comercial no configura documentos requeridos por ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-25 · ATAQUE: Comercial no configura documentos requeridos por ARS','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-26 · … y la regla no quedó guardada (Comercial)','ok',coalesce((not exists (select 1 from public.document_rules where ars_id = v_x1)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-27 · ATAQUE: la Secretaria no configura documentos requeridos por ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-27 · ATAQUE: la Secretaria no configura documentos requeridos por ARS','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-28 · … y la regla no quedó guardada (la Secretaria)','ok',coalesce((not exists (select 1 from public.document_rules where ars_id = v_x1)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-29 · ATAQUE: Glosas no configura documentos requeridos por ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-29 · ATAQUE: Glosas no configura documentos requeridos por ARS','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-30 · … y la regla no quedó guardada (Glosas)','ok',coalesce((not exists (select 1 from public.document_rules where ars_id = v_x1)), false),'d',(null)::text));
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
    begin
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-31 · ATAQUE: Operaciones no configura documentos requeridos por ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-31 · ATAQUE: Operaciones no configura documentos requeridos por ARS','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-32 · … y la regla no quedó guardada (Operaciones)','ok',coalesce((not exists (select 1 from public.document_rules where ars_id = v_x1)), false),'d',(null)::text));
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
    begin
      perform public.dossier_rule_set(v_x1, 'no_existe', 'obligatorio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-33 · Un tipo de documento inexistente se rechaza con qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-33 · Un tipo de documento inexistente se rechaza con qué hacer','ok',sqlerrm like 'El tipo de documento «no_existe» no existe. Elija%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dossier_rule_set(v_x1, v_dt, 'siempre');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-34 · Una exigencia inválida se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-34 · Una exigencia inválida se rechaza','ok',sqlerrm like 'La exigencia debe ser%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dossier_rule_set(v_x1, v_dt, 'obligatorio', 'domicilio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-35 · Una modalidad inválida se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-35 · Una modalidad inválida se rechaza','ok',sqlerrm like 'La modalidad debe ser%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dossier_rule_set(gen_random_uuid(), v_dt, 'obligatorio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-36 · Una ARS inexistente se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-36 · Una ARS inexistente se rechaza','ok',sqlerrm like 'ARS no encontrada%','d',left(sqlerrm,120)));
    end;
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-37 · Semáforo completo: todos los obligatorios con archivo, nada falta','ok',coalesce(((select semaforo = 'completo' and missing_n = 0 and present = required and required = v_n0 from public.v_claim_dossier_semaforo where service_line_id = v_l1)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-38 · Semáforo parcial: con 1 de los obligatorios falta el resto','ok',coalesce(((select semaforo = 'parcial' and present = 1 and missing_n = v_n0 - 1 and cardinality(missing) = v_n0 - 1 from public.v_claim_dossier_semaforo where service_line_id = v_l2)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-39 · Semáforo vacío: sin ningún obligatorio','ok',coalesce(((select semaforo = 'vacio' and present = 0 and missing_n = v_n0 and files = 0 from public.v_claim_dossier_semaforo where service_line_id = v_l3)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-40 · La marca de «recibido en físico» cuenta como presente (3 archivos + 1 marca = completo)','ok',coalesce(((select semaforo = 'completo' and files = 3 from public.v_claim_dossier_semaforo where service_line_id = v_l4)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-41 · El semáforo reutiliza el expediente existente: coincide con v_claim_dossier en las 5 reclamaciones','ok',coalesce(((select count(*) from public.v_claim_dossier_semaforo s join public.v_claim_dossier d on d.service_line_id = s.service_line_id where s.service_line_id in (v_l1, v_l2, v_l3, v_l4, v_l5) and (s.semaforo = 'completo') = d.complete and s.missing = d.missing) = 5), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
    values (v_oa, 'submission', v_s1, v_l3, 'otro', v_oa::text || '/' || v_s1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 5000);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-42 · Un archivo que no es un documento requerido no completa el expediente: sigue vacío','ok',coalesce(((select semaforo = 'vacio' and present = 0 from public.v_claim_dossier_semaforo where service_line_id = v_l3)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-43 · La excepción no maquilla el semáforo: sigue vacío pero marcada como con excepción, y v_claim_dossier la da por buena','ok',coalesce(((select semaforo = 'vacio' and excepted from public.v_claim_dossier_semaforo where service_line_id = v_l5) and (select ok from public.v_claim_dossier where service_line_id = v_l5)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-44 · AISLAMIENTO: el Médico de otro cliente no ve ninguna reclamación del cliente A en el semáforo','ok',coalesce(((select count(*) from public.v_claim_dossier_semaforo where organization_id = v_oa) = 0), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-45 · … y sí la suya','ok',coalesce(((select count(*) from public.v_claim_dossier_semaforo where organization_id = v_ob) = 1), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-46 · El Médico ve las 6 reclamaciones de la radicación 1 de su consultorio','ok',coalesce(((select count(*) from public.v_claim_dossier_semaforo where submission_id = v_s1) = 6), false),'d',(null)::text));
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
      v_j := public.dossier_list(v_oa, v_s1);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-47 · Listado de la radicación 1: 6 reclamaciones; 2 completas, 1 parcial y 3 vacías (la de emergencia también)','ok',coalesce(((v_j->>'total')::int = 6 and (v_j->'counts'->>'completo')::int = 2 and (v_j->'counts'->>'parcial')::int = 1 and (v_j->'counts'->>'vacio')::int = 3), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-48 · El listado pone primero las vacías y al final las completas','ok',coalesce(((v_j->'rows'->0->>'semaforo') = 'vacio' and (v_j->'rows'->5->>'semaforo') = 'completo'), false),'d',(null)::text));
      v_j2 := public.dossier_list(v_oa, v_s1, 'parcial');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-49 · El filtro por semáforo devuelve solo ese color pero los contadores siguen siendo del conjunto','ok',coalesce(((v_j2->>'total')::int = 1 and (v_j2->'rows'->0->>'service_line_id') = v_l2::text and (v_j2->'counts'->>'vacio')::int = 3), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j2 := public.dossier_list(v_oa, v_s1, null, 2, 1);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-50 · La página pide 2 desde la 2.ª y el total sigue siendo 6','ok',coalesce((jsonb_array_length(v_j2->'rows') = 2 and (v_j2->>'total')::int = 6), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_list(v_oa, v_s1, 'rojo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-51 · Un semáforo inválido en el filtro se rechaza con qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-51 · Un semáforo inválido en el filtro se rechaza con qué hacer','ok',sqlerrm like 'El semáforo debe ser%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_list(v_oa, null);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-52 · AISLAMIENTO: el listado del Médico de otro cliente pidiendo el cliente A viene vacío','ok',coalesce(((v_j->>'total')::int = 0 and jsonb_array_length(v_j->'rows') = 0), false),'d',(null)::text));
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
      v_j := public.dossier_detail(v_l2);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-53 · Detalle: cada documento requerido trae sus archivos, el semáforo y los faltantes','ok',coalesce(((v_j->>'semaforo') = 'parcial' and jsonb_array_length(v_j->'items') = v_n0 and (select count(*) from jsonb_array_elements(v_j->'items') i where jsonb_array_length(i->'documents') = 1) = 1 and jsonb_array_length(v_j->'missing') = v_n0 - 1 and (v_j->>'ars') = 'ARS QA Uno'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
    values (v_oa, 'submission', v_s1, v_l3, null, v_oa::text || '/' || v_s1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 5000);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-54 · Los archivos sueltos (sin tipo) salen aparte en el detalle','ok',coalesce((jsonb_array_length(v_j->'other_documents') = 1 and (v_j->>'semaforo') = 'vacio'), false),'d',(null)::text));
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
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-55 · Puede subir documentos en el detalle: el Administrador = true','ok',coalesce(((v_j->>'can_upload')::boolean = true), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-56 · Puede subir documentos en el detalle: el Médico = true','ok',coalesce(((v_j->>'can_upload')::boolean = true), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-57 · Puede subir documentos en el detalle: Facturación = true','ok',coalesce(((v_j->>'can_upload')::boolean = true), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-58 · Puede subir documentos en el detalle: Glosas = true','ok',coalesce(((v_j->>'can_upload')::boolean = true), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-59 · Puede subir documentos en el detalle: Comercial = true','ok',coalesce(((v_j->>'can_upload')::boolean = true), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-60 · Puede subir documentos en el detalle: el Auditor = false','ok',coalesce(((v_j->>'can_upload')::boolean = false), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-61 · Puede subir documentos en el detalle: la Secretaria asignada = true','ok',coalesce(((v_j->>'can_upload')::boolean = true), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-62 · El Auditor puede pedir la excepción de expediente; el Médico no','ok',coalesce(((v_j->>'can_exception')::boolean), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_detail(v_l3);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-63 · … el Médico ve can_exception falso','ok',coalesce((not (v_j->>'can_exception')::boolean), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_detail(v_l3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-64 · AISLAMIENTO: el Médico de otro cliente no abre el detalle de una reclamación ajena','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-64 · AISLAMIENTO: el Médico de otro cliente no abre el detalle de una reclamación ajena','ok',sqlerrm like 'Reclamación no encontrada o sin acceso%','d',left(sqlerrm,120)));
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
      select i.document_type_code into v_dm from app.claim_dossier_items(v_l3) i where i.mandatory order by i.sort_order limit 1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_id := public.register_captured_document(v_oa, v_s1, v_l3, v_dm, v_oa::text || '/' || v_s1::text || '/qa196-foto.jpg', 'foto.jpg', 'image/jpeg', 20000, encode(sha256(convert_to('qa196-1','utf8')), 'hex'), 'camara', null::jsonb);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-65 · Subir con la cámara (register_captured_document) mueve el semáforo de vacío a parcial y guarda el origen «camara»','ok',coalesce(((select semaforo = 'parcial' and present = 1 from public.v_claim_dossier_semaforo where service_line_id = v_l3) and (select capture_origin from public.documents where id = v_id) = 'camara'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.register_captured_document(v_oa, v_s1, v_l3, v_dm, v_oa::text || '/' || v_s1::text || '/qa196-foto2.jpg', 'foto.jpg', 'image/jpeg', 20000, encode(sha256(convert_to('qa196-1','utf8')), 'hex'), 'camara', null::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-66 · La misma foto no se sube dos veces (huella repetida)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-66 · La misma foto no se sube dos veces (huella repetida)','ok',sqlerrm like 'Este documento ya fue cargado antes%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.register_captured_document(v_oa, v_s1, v_l3, 'autorizacion', v_oa::text || '/' || v_s1::text || '/qa196-x.jpg', 'foto.jpg', 'image/jpeg', 20000, encode(sha256(convert_to('qa196-x','utf8')), 'hex'), 'camara', null::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-67 · ATAQUE: el Médico de otro cliente no sube documentos a una reclamación ajena','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-67 · ATAQUE: el Médico de otro cliente no sube documentos a una reclamación ajena','ok',sqlerrm like 'No tienes permiso%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.change_submission_status(v_sr1, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-1', 'fisico', 'LOTE-QA-1');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-68 · Con el bloqueo APAGADO una radicación con expediente incompleto se radica como siempre','ok',coalesce(((select status from public.submissions where id = v_sr1) = 'radicada'), false),'d',(null)::text));
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
      perform public.dossier_params_set(true, 10, null, 80, 95);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-69 · El interruptor se enciende con dossier_params_set','ok',coalesce(((select block_radicar from public.dossier_params where operator_id = '00000000-0000-4000-8000-000000000001'::uuid)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.change_submission_status(v_sr2, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-2', 'fisico', 'LOTE-QA-2');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-70 · Con el bloqueo ENCENDIDO no se radica con expediente incompleto y el mensaje dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-70 · Con el bloqueo ENCENDIDO no se radica con expediente incompleto y el mensaje dice qué hacer','ok',sqlerrm like 'No se puede radicar: 1 reclamación(es) tienen el expediente incompleto%Expediente digital%excepción de expediente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-71 · … y la radicación sigue en «Lista para radicar»','ok',coalesce(((select status from public.submissions where id = v_sr2) = 'lista_para_radicar'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      begin
      perform public.change_submission_status(v_sr2, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-2', 'fisico', 'LOTE-QA-2');
      exception when others then get stacked diagnostics v_rl = pg_exception_hint; end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-72 · El error lleva la pista «expediente_incompleto» para que la pantalla lo reconozca','ok',coalesce((v_rl = 'expediente_incompleto'), false),'d',(null)::text));
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
      perform public.dossier_params_set(true, 10, null, 80, 95);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.authorize_dossier_exception(array[v_lr2], 'QA: la ARS no exige el formulario en este caso');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.change_submission_status(v_sr2, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-2', 'fisico', 'LOTE-QA-2');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-73 · Con el bloqueo encendido, la excepción de expediente que autoriza el Auditor deja radicar','ok',coalesce(((select status from public.submissions where id = v_sr2) = 'radicada'), false),'d',(null)::text));
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
      perform public.dossier_params_set(true, 10, null, 80, 95);
      perform public.change_submission_status(v_sr3, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-3', 'fisico', 'LOTE-QA-3');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-74 · Con el bloqueo encendido una radicación con todos los expedientes completos se radica sin problema','ok',coalesce(((select status from public.submissions where id = v_sr3) = 'radicada'), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dossier_params_set(true, 10, null, 80, 95);
      perform public.dossier_params_set(false, 10, null, 80, 95);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.change_submission_status(v_sr2, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-2', 'fisico', 'LOTE-QA-2');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-75 · Apagar el bloqueo otra vez restablece el comportamiento anterior','ok',coalesce(((select status from public.submissions where id = v_sr2) = 'radicada'), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_params_set(true, 10, null, 80, 95);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-76 · ATAQUE: Facturación no enciende el bloqueo ni cambia parámetros','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-76 · ATAQUE: Facturación no enciende el bloqueo ni cambia parámetros','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian los parámetros%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-77 · … y el interruptor sigue apagado (Facturación)','ok',coalesce(((select not block_radicar from public.dossier_params where operator_id = '00000000-0000-4000-8000-000000000001'::uuid)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_params_set(true, 10, null, 80, 95);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-78 · ATAQUE: el Médico no enciende el bloqueo ni cambia parámetros','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-78 · ATAQUE: el Médico no enciende el bloqueo ni cambia parámetros','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian los parámetros%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-79 · … y el interruptor sigue apagado (el Médico)','ok',coalesce(((select not block_radicar from public.dossier_params where operator_id = '00000000-0000-4000-8000-000000000001'::uuid)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_params_set(true, 10, null, 80, 95);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-80 · ATAQUE: el Auditor no enciende el bloqueo ni cambia parámetros','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-80 · ATAQUE: el Auditor no enciende el bloqueo ni cambia parámetros','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian los parámetros%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-81 · … y el interruptor sigue apagado (el Auditor)','ok',coalesce(((select not block_radicar from public.dossier_params where operator_id = '00000000-0000-4000-8000-000000000001'::uuid)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_params_set(true, 10, null, 80, 95);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-82 · ATAQUE: la Secretaria no enciende el bloqueo ni cambia parámetros','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-82 · ATAQUE: la Secretaria no enciende el bloqueo ni cambia parámetros','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian los parámetros%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-83 · … y el interruptor sigue apagado (la Secretaria)','ok',coalesce(((select not block_radicar from public.dossier_params where operator_id = '00000000-0000-4000-8000-000000000001'::uuid)), false),'d',(null)::text));
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
    begin
      perform public.dossier_params_set(false, 0, null, 80, 95);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-84 · Parámetros inválidos: conservación 0 años','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-84 · Parámetros inválidos: conservación 0 años','ok',sqlerrm like 'Los años de conservación van de 1 a 50%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dossier_params_set(false, 10, null, 100, 95);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-85 · Parámetros inválidos: aviso 100 %','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-85 · Parámetros inválidos: aviso 100 %','ok',sqlerrm like 'El porcentaje de aviso va de 50 a 99%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dossier_params_set(false, 10, null, 80, 49);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-86 · Parámetros inválidos: meta 49 %','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-86 · Parámetros inválidos: meta 49 %','ok',sqlerrm like 'La meta de expedientes completos va de 50 a 100%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dossier_params_set(false, 10, 0, 80, 95);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-87 · Parámetros inválidos: límite 0 MB','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-87 · Parámetros inválidos: límite 0 MB','ok',sqlerrm like 'El límite de espacio va de 1 MB%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dossier_params_set(null, 10, null, 80, 95);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-88 · Parámetros inválidos: interruptor vacío','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-88 · Parámetros inválidos: interruptor vacío','ok',sqlerrm like 'Indique si el bloqueo%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_params_get(v_oa);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-89 · El Médico ve los parámetros de su cliente (bloqueo apagado, meta 95) sin poder editarlos','ok',coalesce((not (v_j->>'block_radicar')::boolean and (v_j->>'target_pct')::int = 95 and not (v_j->>'can_edit')::boolean), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_params_get(v_oa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-90 · AISLAMIENTO: el Médico de otro cliente no pide los parámetros del cliente A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-90 · AISLAMIENTO: el Médico de otro cliente no pide los parámetros del cliente A','ok',sqlerrm like 'No tiene acceso a ese cliente%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.change_submission_status(v_sr1, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-1', 'fisico', 'LOTE-QA-1');
      perform public.change_submission_status(v_sr2, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-2', 'fisico', 'LOTE-QA-2');
      perform public.change_submission_status(v_sr3, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-3', 'fisico', 'LOTE-QA-3');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-91 · Al radicar se toma una foto del expediente de cada reclamación (4 en la ARS 1 y 2, 2 completas en la ARS 2)','ok',coalesce(((select count(*) from public.claim_dossier_snapshots where submission_id in (v_sr1, v_sr2, v_sr3)) = 4 and (select count(*) from public.claim_dossier_snapshots where submission_id = v_sr3 and complete) = 2), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-92 · La foto de una reclamación incompleta guarda qué faltaba','ok',coalesce(((select not complete and cardinality(missing) = v_n0 from public.claim_dossier_snapshots where service_line_id = v_lr1)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-93 · Una radicación que no se radicó no tiene fotos','ok',coalesce(((select count(*) from public.claim_dossier_snapshots where submission_id = v_s1) = 0), false),'d',(null)::text));
    perform set_config('app.status_change', 'on', true);
    update public.submissions set status = 'rechazada' where id = v_sr1;
    update public.submissions set status = 'radicada' where id = v_sr1;
    perform set_config('app.status_change', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-94 · Radicar otra vez la misma radicación actualiza la foto y no la duplica','ok',coalesce(((select count(*) from public.claim_dossier_snapshots where service_line_id = v_lr1) = 1), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_indicator(v_oa);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-95 · Indicador del cliente A: 4 radicadas, 2 con expediente completo = 50 %, 2 incompletas','ok',coalesce(((v_j->'summary'->>'total')::int = 4 and (v_j->'summary'->>'completos')::int = 2 and (v_j->'summary'->>'pct_completo')::numeric = 50.0 and (v_j->'summary'->>'incompletos')::int = 2), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-96 · Meta 95 %: el cliente A no la cumple','ok',coalesce(((v_j->>'target_pct')::int = 95 and not (v_j->>'meets_target')::boolean), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-97 · Por ARS: la ARS 1 con 0 % sale primero y la ARS 2 con 100 %','ok',coalesce((jsonb_array_length(v_j->'by_ars') = 2 and (v_j->'by_ars'->0->>'pct_completo')::numeric = 0.0 and (v_j->'by_ars'->1->>'pct_completo')::numeric = 100.0), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-98 · Por mes: un solo mes con las 4 reclamaciones','ok',coalesce((jsonb_array_length(v_j->'by_month') = 1 and (v_j->'by_month'->0->>'total')::int = 4), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.authorize_dossier_exception(array[v_lr2], 'QA: la ARS no exige el formulario en este caso');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.change_submission_status(v_sr2, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-2', 'fisico', 'LOTE-QA-2');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-99 · Una radicación con excepción se cuenta como incompleta con excepción (no como completa)','ok',coalesce(((select not complete and excepted from public.claim_dossier_snapshots where service_line_id = v_lr2)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_indicator(v_oa);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-100 · El resumen separa completos, con excepción e incompletos','ok',coalesce(((v_j->'summary'->>'con_excepcion')::int = 1 and (v_j->'summary'->>'incompletos')::int = 0 and (v_j->'summary'->>'completos')::int = 0), false),'d',(null)::text));
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
      perform public.change_submission_status(v_sb1, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-4', 'fisico', 'LOTE-QA-4');
      perform public.change_submission_status(v_sr3, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-3', 'fisico', 'LOTE-QA-3');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_indicator(null);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-101 · Indicador general del personal: suma todos los clientes (1 de B y 2 de A: 3 completas de 3)','ok',coalesce(((v_j->'summary'->>'total')::int = 3 and (v_j->'summary'->>'pct_completo')::numeric = 100.0 and (v_j->>'meets_target')::boolean), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_indicator(v_ob);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-102 · El Médico B ve el indicador de su consultorio (1 de 1, cumple la meta)','ok',coalesce(((v_j->'summary'->>'total')::int = 1 and (v_j->>'meets_target')::boolean), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_indicator(v_oa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-103 · AISLAMIENTO: el Médico B no ve el indicador del cliente A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-103 · AISLAMIENTO: el Médico B no ve el indicador del cliente A','ok',sqlerrm like 'No tiene acceso al indicador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_indicator(null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-104 · El indicador general no es del Médico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-104 · El indicador general no es del Médico','ok',sqlerrm like 'El indicador general lo ve el personal%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_indicator(v_oa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-105 · La Secretaria no ve el indicador de cumplimiento','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-105 · La Secretaria no ve el indicador de cumplimiento','ok',sqlerrm like 'No tiene acceso al indicador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dossier_indicator(v_oa, current_date, current_date - 5);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-106 · Un período al revés se rechaza con qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-106 · Un período al revés se rechaza con qué hacer','ok',sqlerrm like 'La fecha inicial es posterior%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.change_submission_status(v_sb1, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-4', 'fisico', 'LOTE-QA-4');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
    values (v_ob, 'submission', v_sb1, null, null, v_ob::text || '/' || v_sb1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 1000);
    update public.claim_dossier_snapshots set taken_at = now() - interval '400 days' where submission_id = v_sb1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.dossier_indicator(v_ob, current_date - 30, current_date);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-107 · El filtro de fechas deja fuera lo radicado hace más de un año','ok',coalesce(((v_j->'summary'->>'total')::int = 0 and (v_j->'summary'->>'pct_completo') is null and (v_j->>'meets_target') is null), false),'d',(null)::text));
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
      perform public.change_submission_status(v_sr2, 'radicada', null, 'QA: autorizado para la prueba', current_date, 'R-QA-2', 'fisico', 'LOTE-QA-2');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select complete into v_cnt1 from (select complete::int from public.claim_dossier_snapshots where service_line_id = v_lr2) q;
    for v_r in select i.document_type_code as c from app.claim_dossier_items(v_lr2) i where i.mandatory and not i.present order by i.sort_order loop
      insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
      values (v_oa, 'submission', v_sr2, v_lr2, v_r.c, v_oa::text || '/' || v_sr2::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 20000);
    end loop;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-108 · La foto es del momento de radicar: subir los documentos después no la cambia','ok',coalesce(((select complete::int from public.claim_dossier_snapshots where service_line_id = v_lr2) = v_cnt1 and (select not complete from public.claim_dossier_snapshots where service_line_id = v_lr2)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-109 · El estado de espacio: sin límite, ok, aviso (80 %), justo en el límite = excedido','ok',coalesce((app.storage_status(5000000, null, 80) = 'sin_limite' and app.storage_status(100, 10, 80) = 'ok' and app.storage_status(8388607, 10, 80) = 'ok' and app.storage_status(8388608, 10, 80) = 'aviso' and app.storage_status(10485759, 10, 80) = 'aviso' and app.storage_status(10485760, 10, 80) = 'excedido' and app.storage_status(0, 1, 50) = 'ok'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
    values (v_oa, 'submission', v_s1, null, 'otro', v_oa::text || '/' || v_s1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 2097152);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.client_storage_limit_set(v_oa, 1, 'QA límite chico');
      v_j := public.storage_usage_report();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-110 · Reporte de Storage: el cliente A con 2 MB y límite de 1 MB sale excedido, con su límite propio','ok',coalesce(((select (e->>'status') = 'excedido' and (e->>'limit_source') = 'cliente' and (e->>'limit_mb')::int = 1 and (e->>'pct_used')::numeric > 100 from jsonb_array_elements(v_j->'rows') e where e->>'organization_id' = v_oa::text)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-111 · El reporte cuenta archivos y bytes reales de documents por cliente','ok',coalesce(((select (e->>'bytes')::bigint = (select sum(size_bytes) from public.documents where organization_id = v_oa) and (e->>'files')::int = (select count(*) from public.documents where organization_id = v_oa) from jsonb_array_elements(v_j->'rows') e where e->>'organization_id' = v_oa::text)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-112 · El resumen cuenta clientes excedidos y en aviso','ok',coalesce(((v_j->'summary'->>'excedidos')::int >= 1), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-113 · El reporte ordena por consumo: el cliente A (más pesado) va primero','ok',coalesce(((v_j->'rows'->0->>'organization_id') = v_oa::text), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
    values (v_ob, 'submission', v_sb1, null, 'otro', v_ob::text || '/' || v_sb1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 2621440);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.client_storage_limit_set(v_ob, 3);
      v_j := public.storage_usage_report();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-114 · Aviso: 2.5 MB de 3 MB (83 %) sale en aviso y no excedido','ok',coalesce(((select (e->>'status') = 'aviso' from jsonb_array_elements(v_j->'rows') e where e->>'organization_id' = v_ob::text)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dossier_params_set(false, 10, 1000, 80, 95);
      v_j := public.storage_usage_report();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-115 · El límite general rige para los clientes sin límite propio y se marca como «general»','ok',coalesce(((select (e->>'limit_source') = 'general' and (e->>'status') = 'ok' and (e->>'limit_mb')::int = 1000 from jsonb_array_elements(v_j->'rows') e where e->>'organization_id' = v_ob::text)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.client_storage_limit_set(v_ob, 5);
      v_j := public.storage_usage_report();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-116 · El límite propio del cliente gana sobre el general','ok',coalesce(((select (e->>'limit_source') = 'cliente' and (e->>'limit_mb')::int = 5 from jsonb_array_elements(v_j->'rows') e where e->>'organization_id' = v_ob::text)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.client_storage_limit_set(v_ob, null);
      v_j := public.storage_usage_report();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-117 · Dejar el límite vacío quita el propio y vuelve a regir el general','ok',coalesce(((select (e->>'limit_source') = 'general' from jsonb_array_elements(v_j->'rows') e where e->>'organization_id' = v_ob::text) and not exists (select 1 from public.client_storage_limits where organization_id = v_ob)), false),'d',(null)::text));
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
      v_j := public.storage_usage_report();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-118 · Sin límite general ni propio el estado es «sin_limite» y no hay porcentaje','ok',coalesce(((select (e->>'status') = 'sin_limite' and (e->>'pct_used') is null from jsonb_array_elements(v_j->'rows') e where e->>'organization_id' = v_ob::text)), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.storage_usage_report();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-119 · ATAQUE: Facturación no ve el consumo de Storage de todos los clientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-119 · ATAQUE: Facturación no ve el consumo de Storage de todos los clientes','ok',sqlerrm like 'El consumo de Storage lo ven el Super Admin y el Administrador%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.client_storage_limit_set(v_oa, 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-120 · ATAQUE: Facturación no cambia el límite de espacio de un cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-120 · ATAQUE: Facturación no cambia el límite de espacio de un cliente','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian el límite%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.storage_usage_report();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-121 · ATAQUE: el Médico no ve el consumo de Storage de todos los clientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-121 · ATAQUE: el Médico no ve el consumo de Storage de todos los clientes','ok',sqlerrm like 'El consumo de Storage lo ven el Super Admin y el Administrador%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.client_storage_limit_set(v_oa, 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-122 · ATAQUE: el Médico no cambia el límite de espacio de un cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-122 · ATAQUE: el Médico no cambia el límite de espacio de un cliente','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian el límite%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.storage_usage_report();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-123 · ATAQUE: el Auditor no ve el consumo de Storage de todos los clientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-123 · ATAQUE: el Auditor no ve el consumo de Storage de todos los clientes','ok',sqlerrm like 'El consumo de Storage lo ven el Super Admin y el Administrador%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.client_storage_limit_set(v_oa, 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-124 · ATAQUE: el Auditor no cambia el límite de espacio de un cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-124 · ATAQUE: el Auditor no cambia el límite de espacio de un cliente','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian el límite%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.storage_usage_report();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-125 · ATAQUE: la Secretaria no ve el consumo de Storage de todos los clientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-125 · ATAQUE: la Secretaria no ve el consumo de Storage de todos los clientes','ok',sqlerrm like 'El consumo de Storage lo ven el Super Admin y el Administrador%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.client_storage_limit_set(v_oa, 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-126 · ATAQUE: la Secretaria no cambia el límite de espacio de un cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-126 · ATAQUE: la Secretaria no cambia el límite de espacio de un cliente','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian el límite%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.storage_usage_report();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-127 · ATAQUE: Glosas no ve el consumo de Storage de todos los clientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-127 · ATAQUE: Glosas no ve el consumo de Storage de todos los clientes','ok',sqlerrm like 'El consumo de Storage lo ven el Super Admin y el Administrador%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.client_storage_limit_set(v_oa, 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-128 · ATAQUE: Glosas no cambia el límite de espacio de un cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-128 · ATAQUE: Glosas no cambia el límite de espacio de un cliente','ok',sqlerrm like 'Solo el Super Admin o el Administrador cambian el límite%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.client_storage_limit_set(v_oa, 0);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-129 · Un límite de 0 MB se rechaza con qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-129 · Un límite de 0 MB se rechaza con qué hacer','ok',sqlerrm like 'El límite va de 1 MB%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.client_storage_limit_set(gen_random_uuid(), 10);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-130 · Un cliente inexistente se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-130 · Un cliente inexistente se rechaza','ok',sqlerrm like 'Cliente no encontrado o sin acceso%','d',left(sqlerrm,120)));
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
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes)
    values (v_oa, 'submission', v_s1, null, 'otro', v_oa::text || '/' || v_s1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 2097152);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.client_storage_limit_set(v_oa, 1);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.storage_usage_org(v_oa);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-131 · El Médico ve el estado de espacio de su consultorio: excedido, con mensaje que dice qué hacer y sin bloquear','ok',coalesce(((v_j->>'status') = 'excedido' and (v_j->>'message') like '%Los documentos siguen guardándose%' and (v_j->>'mb')::numeric >= 2), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j2 := public.storage_usage_org(v_oa);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-132 · La Secretaria asignada también ve el aviso de espacio','ok',coalesce(((v_j2->>'status') = 'excedido'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.storage_usage_org(v_oa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-133 · AISLAMIENTO: el Médico de otro cliente no ve el espacio del cliente A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-133 · AISLAMIENTO: el Médico de otro cliente no ve el espacio del cliente A','ok',sqlerrm like 'No tiene acceso a ese cliente%','d',left(sqlerrm,120)));
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
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes, uploaded_at)
    values (v_oa, 'submission', v_s1, null, 'otro', v_oa::text || '/' || v_s1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 3145728, now() - interval '12 years');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_j := public.storage_usage_report();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-134 · Conservación: con 10 años, el documento de hace 12 años se cuenta como vencido y solo se cuenta','ok',coalesce(((select (e->>'files_over_retention')::int = 1 and (e->>'mb_over_retention')::numeric > 0 from jsonb_array_elements(v_j->'rows') e where e->>'organization_id' = v_oa::text) and (v_j->'summary'->>'retention_years')::int = 10), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dossier_params_set(false, 15, null, 80, 95);
      v_j := public.storage_usage_report();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-135 · Con 15 años de conservación ya no está vencido','ok',coalesce(((select (e->>'files_over_retention')::int = 0 from jsonb_array_elements(v_j->'rows') e where e->>'organization_id' = v_oa::text)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select count(*) into v_docs from public.documents;
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes, uploaded_at)
    values (v_oa, 'submission', v_s1, null, 'otro', v_oa::text || '/' || v_s1::text || '/' || gen_random_uuid()::text || '.pdf', 'qa.pdf', 'application/pdf', 1000, now() - interval '20 years');
    v_docs := v_docs + 1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dossier_params_set(true, 1, 1, 50, 50);
      perform public.client_storage_limit_set(v_oa, 1);
      perform public.storage_usage_report();
      perform public.storage_usage_org(v_oa);
      perform public.dossier_indicator(null);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-136 · NUNCA se borra solo: con conservación de 1 año y límite de 1 MB, ningún documento desaparece','ok',coalesce(((select count(*) from public.documents) = v_docs), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-137 · Ninguna función de la 196 borra documentos ni toca los objetos de Storage','ok',coalesce((not exists (select 1 from pg_proc p where p.pronamespace in ('app'::regnamespace, 'public'::regnamespace) and (p.proname like 'dossier\_%' or p.proname like 'storage\_%' or p.proname = 'client_storage_limit_set') and (p.prosrc ~* 'delete\s+from\s+public\.documents' or p.prosrc ~* 'storage\.objects' or p.prosrc ~* 'storage\.delete'))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-138 · change_submission_status conserva sus permisos y su search_path vacío al extenderse','ok',coalesce(((select prosecdef and proconfig is not null from pg_proc where oid = 'public.change_submission_status(uuid,text,text,text,date,text,text,text,uuid)'::regprocedure) and has_function_privilege('authenticated', 'public.change_submission_status(uuid,text,text,text,date,text,text,text,uuid)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EX-139 · La extensión conserva la regla SEG-36 de la 174 (el acuse debe ser del mismo cliente)','ok',coalesce(((select prosrc like '%El documento de acuse no pertenece a este cliente%' and prosrc like '%expediente_incompleto%' from pg_proc where oid = 'public.change_submission_status(uuid,text,text,text,date,text,text,text,uuid)'::regprocedure)), false),'d',(null)::text));
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
revoke all on function app.qa_run_tests_expediente() from public, anon, authenticated;
