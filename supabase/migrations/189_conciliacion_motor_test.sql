-- 189 · Suite de la 188 (conciliación de relaciones de pago: motor y aplicación, I58). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_conciliacion_motor();
create or replace function app.qa_run_tests_conciliacion_motor()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_a constant uuid := '01880000-0000-4000-8000-000000000001'; v_b constant uuid := '01880000-0000-4000-8000-000000000002';
  v_pa constant uuid := '01880000-0000-4000-8000-000000000011'; v_pb constant uuid := '01880000-0000-4000-8000-000000000012';
  v_sa constant text := '01880000-0000-4000-8000-000000000021'; v_ad constant text := '01880000-0000-4000-8000-000000000022'; v_gl constant text := '01880000-0000-4000-8000-000000000023'; v_au constant text := '01880000-0000-4000-8000-000000000024'; v_bil constant text := '01880000-0000-4000-8000-000000000025'; v_ops constant text := '01880000-0000-4000-8000-000000000026';
  v_co constant text := '01880000-0000-4000-8000-000000000027'; v_ma constant text := '01880000-0000-4000-8000-000000000031'; v_mb constant text := '01880000-0000-4000-8000-000000000032'; v_sec constant text := '01880000-0000-4000-8000-000000000033';
  v_x1 uuid; v_x2 uuid; v_x3 uuid; v_proc uuid; v_per date; v_d0 text; v_d1 text; v_d2 text; v_d3 text; v_d4 text;
  v_s1 uuid; v_s2 uuid; v_s3 uuid; v_s4 uuid; v_s5 uuid;
  v_f1 uuid; v_f2 uuid; v_f3 uuid; v_rows jsonb; v_r jsonb; v_rem uuid; v_rem2 uuid; v_id uuid; v_rl text; v_t numeric; v_u numeric;
  l_a1 uuid; l_a2 uuid; l_a3 uuid; l_a4 uuid; l_a5a uuid; l_a5b uuid; l_a6 uuid; l_a7 uuid; l_b0 uuid; l_b1 uuid; l_b2 uuid; l_b3 uuid; l_g1 uuid; l_g2 uuid; l_g3 uuid; l_x1 uuid;
  v_q1 uuid; v_q2 uuid; v_q3 uuid; v_q4 uuid; v_q5 uuid; v_q6 uuid; v_q7 uuid; v_q8 uuid; v_q9 uuid; v_al uuid; v_pay uuid; v_ref text; v_main uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '188') then
    raise exception 'Falta la migración 188. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.cm.sa@sofa.test','x'),(v_ad::uuid,'qa.cm.ad@sofa.test','x'),(v_gl::uuid,'qa.cm.gl@sofa.test','x'),(v_au::uuid,'qa.cm.au@sofa.test','x'),(v_bil::uuid,'qa.cm.bil@sofa.test','x'),(v_ops::uuid,'qa.cm.ops@sofa.test','x'),(v_co::uuid,'qa.cm.co@sofa.test','x'),(v_ma::uuid,'qa.cm.ma@sofa.test','x'),(v_mb::uuid,'qa.cm.mb@sofa.test','x'),(v_sec::uuid,'qa.cm.sec@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.cm.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_a, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA CM Consultorio A', '00000018601', 'Médico independiente', 'activo', current_date - 90, '8095558601');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_b, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA CM Consultorio B', '00000018602', 'Médico independiente', 'activo', current_date - 90, '8095558602');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_a, 'Dr. A QA', 'Cardiología', true), (v_pb, v_b, 'Dr. B QA', 'Urología', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_gl::uuid, 'glosas', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_au::uuid, 'auditor', true),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_co::uuid, 'assistant', true),
      (v_a, v_ma::uuid, 'client', true), (v_b, v_mb::uuid, 'client', true), (v_a, v_sec::uuid, 'capturer', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_pa, v_a, true, true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_i58_x1', 'ARS QA Alfa', 'Contributivo', true) returning id into v_x1;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_i58_x2', 'ARS QA Beta', 'Contributivo', true) returning id into v_x2;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_i58_x3', 'ARS QA Gamma', 'Subsidiado', true) returning id into v_x3;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    v_per := (date_trunc('month', current_date) - interval '2 months')::date;
    v_d0 := to_char(v_per + 5, 'DD/MM/YYYY'); v_d1 := to_char(v_per + 6, 'DD/MM/YYYY'); v_d2 := to_char(v_per + 7, 'DD/MM/YYYY'); v_d3 := to_char(v_per + 8, 'DD/MM/YYYY'); v_d4 := to_char(v_per + 9, 'DD/MM/YYYY');
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_x1, v_per, 1, 'borrador') returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_x1, v_per, 2, 'borrador') returning id into v_s2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_x2, v_per, 1, 'borrador') returning id into v_s3;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_b, v_pb, v_x1, v_per, 1, 'borrador') returning id into v_s4;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_x3, v_per, 1, 'borrador') returning id into v_s5;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_a, v_per + 5, 'Paciente QA Uno', '90000101', 'AUT-1001', v_proc, 1, 1500) returning id into l_a1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_a, v_per + 5, 'Paciente QA Dos', '90000102', 'AUT-1002', v_proc, 1, 2000) returning id into l_a2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_a, v_per + 6, 'Paciente QA Tres', '90000103', 'AUT-1003', v_proc, 1, 1200) returning id into l_a3;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_a, v_per + 6, 'Paciente QA Cuatro', '90000104', 'AUT-1004', v_proc, 1, 800) returning id into l_a4;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_a, v_per + 7, 'Paciente QA Cinco', '90000105', 'AUT-1005', v_proc, 1, 500) returning id into l_a5a;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_a, v_per + 8, 'Paciente QA Cinco', '90000105', 'AUT-1006', v_proc, 1, 500) returning id into l_a5b;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_a, v_per + 9, 'Paciente QA Seis', '90000106', 'AUT-1007', v_proc, 1, 3000) returning id into l_a6;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s2, v_a, v_per + 5, 'Paciente QA Siete', '90000107', 'AUT-1008', v_proc, 1, 600) returning id into l_a7;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s3, v_a, v_per + 5, 'Paciente QA Cero', '90000101', 'AUT-9001', v_proc, 1, 100) returning id into l_b0;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s3, v_a, v_per + 5, 'Paciente QA Beta Uno', '80000201', 'BET-2001', v_proc, 1, 1000) returning id into l_b1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s3, v_a, v_per + 5, 'Paciente QA Beta Dos', '80000202', 'BET-2002', v_proc, 1, 2500) returning id into l_b2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s3, v_a, v_per + 6, 'Paciente QA Beta Tres', '80000203', 'BET-2003', v_proc, 1, 4000) returning id into l_b3;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s5, v_a, v_per + 5, 'Paciente QA Gamma Uno', '70000301', null, v_proc, 1, 750) returning id into l_g1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s5, v_a, v_per + 6, 'Paciente QA Gamma Dos', '70000302', null, v_proc, 1, 1250) returning id into l_g2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s5, v_a, v_per + 5, 'Paciente QA Gamma Uno', '70000301', null, v_proc, 1, 750) returning id into l_g3;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s4, v_b, v_per + 5, 'Paciente QA Otro Cliente', '90000101', 'AUT-1001', v_proc, 1, 1500) returning id into l_x1;
    perform set_config('app.status_change', 'on', true);
    update public.submissions set status = 'radicada', submitted_on = current_date - 10, ars_receipt_number = 'QA58', ncf = 'B0100000058' where id in (v_s1, v_s3, v_s4, v_s5);
    perform set_config('app.status_change', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-01 · La migración 188 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '188')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-02 · Las funciones públicas del motor no están abiertas a anon pero sí a authenticated','ok',coalesce((not has_function_privilege('anon', 'public.remittance_apply(uuid,uuid[],int)', 'execute') and not has_function_privilege('anon', 'public.remittance_to_glosa(uuid,uuid[])', 'execute') and not has_function_privilege('anon', 'public.payment_match_rules()', 'execute') and has_function_privilege('authenticated', 'public.remittance_apply(uuid,uuid[],int)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-03 · Las funciones internas del motor (app.pm_*) no se llaman desde la API','ok',coalesce((not has_function_privilege('authenticated', 'app.pm_match_rows(uuid,uuid,boolean,int)', 'execute') and not has_function_privilege('authenticated', 'app.pm_apply_lines(uuid,uuid[],text,int)', 'execute') and not has_function_privilege('authenticated', 'app.pm_candidates(uuid,uuid,text,text,date,numeric,numeric)', 'execute') and not has_function_privilege('anon', 'app.pm_line_pending(uuid)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-04 · Las dos causas de glosa nuevas existen (pago menor y rechazada en la relación)','ok',coalesce(((select count(*) from public.glosa_reasons where code in ('pago_menor','rechazada_ars') and is_active) = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.payment_match_rules();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-05 · Las reglas son visibles: umbral 85, margen 20 y 8 reglas con sus puntos','ok',coalesce(((v_r->>'umbral_segura')::int = 85 and (v_r->>'margen_segura')::int = 20 and jsonb_array_length(v_r->'reglas') = 8 and (select (x->>'points')::int from jsonb_array_elements(v_r->'reglas') x where x->>'code' = 'nss') = 40), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_f1 := public.payment_format_save(v_a, v_x1, 'QA Alfa · relación mensual', '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb);
    v_f2 := public.payment_format_save(v_a, v_x2, 'QA Beta · relación mensual', '{"nss":"NSS","autorizacion":"No. Autorización","fecha":"Fecha","facturado":"Valor Reclamado","pagado":"Valor Aprobado","motivo":"Observación"}'::jsonb);
    v_f3 := public.payment_format_save(v_a, v_x3, 'QA Gamma · relación mensual', '{"nss":"Afiliado","fecha":"Fecha de servicio","pagado":"Pagado"}'::jsonb);
    v_rows := jsonb_build_array(
      jsonb_build_object('No. Afiliado', '900-00101', 'Autorización', 'AUT-1001', 'Fecha Servicio', v_d0, 'Monto Facturado', '1,500.00', 'Monto Pagado', '1,500.00', 'Estado', 'Pagada', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '0090000102', 'Autorización', 'aut 1002', 'Fecha Servicio', v_d0, 'Monto Facturado', '2.000,00', 'Monto Pagado', '2.000,00', 'Estado', 'Pagada', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '900 00103', 'Autorización', 'AUT-1003', 'Fecha Servicio', v_d1, 'Monto Facturado', '1200,00', 'Monto Pagado', '700,00', 'Estado', 'Parcial', 'Motivo', 'Tarifa superior a la contratada'),
      jsonb_build_object('No. Afiliado', '90000104', 'Autorización', 'AUT-1004', 'Fecha Servicio', v_d1, 'Monto Facturado', '800', 'Monto Pagado', '0', 'Estado', 'Rechazada', 'Motivo', 'Sin autorización vigente'),
      jsonb_build_object('No. Afiliado', '90000105', 'Autorización', '', 'Fecha Servicio', v_d2, 'Monto Facturado', '500', 'Monto Pagado', '500', 'Estado', 'Pagada', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '90000106', 'Autorización', 'AUT-1007', 'Fecha Servicio', v_d4, 'Monto Facturado', '3,000.00', 'Monto Pagado', '3,500.00', 'Estado', 'Pagada', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '90000199', 'Autorización', 'AUT-7777', 'Fecha Servicio', v_d0, 'Monto Facturado', '400', 'Monto Pagado', '400', 'Estado', 'Pagada', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '900-00101', 'Autorización', 'AUT-1001', 'Fecha Servicio', v_d0, 'Monto Facturado', '1,500.00', 'Monto Pagado', '1,500.00', 'Estado', 'Pagada', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '90000107', 'Autorización', 'AUT-1008', 'Fecha Servicio', v_d0, 'Monto Facturado', '600', 'Monto Pagado', '600', 'Estado', 'Pagada', 'Motivo', ''));
    v_r := public.remittance_import(v_a, v_x1, v_rows, v_f1, null, 'REF-ALFA-189', current_date - 3, null, true, 'relacion_alfa.xlsx');
    v_rem := (v_r->>'remittance')::uuid;
    v_main := v_rem;
    v_r := public.remittance_detail(v_rem);
    v_q1 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1);
    v_q2 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 2);
    v_q3 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3);
    v_q4 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 4);
    v_q5 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5);
    v_q6 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 6);
    v_q7 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 7);
    v_q8 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 8);
    v_q9 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 9);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-06 · Los 9 renglones de la relación dan 4 seguras, 2 dudosas, 2 sin pareja y 1 duplicado','ok',coalesce(((v_r->'counts'->>'segura')::int = 4 and (v_r->'counts'->>'dudosa')::int = 2 and (v_r->'counts'->>'sin_pareja')::int = 2 and (v_r->'counts'->>'duplicado')::int = 1), false),'d',(v_r->'counts')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-07 · Fila 1 (NSS con guion): segura con 100 puntos, la eligió el motor y apunta a la reclamación correcta','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = 'segura' and (select score from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = 100 and (select chosen_by from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = 'motor' and (select service_line_id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = l_a1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-08 · Fila 1 guarda las reglas que cumplió, visibles: NSS, autorización, fecha, facturado y que cabe en lo pendiente','ok',coalesce((jsonb_array_length((select rules from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1)) = 5 and (select count(*) from jsonb_array_elements((select rules from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1)) x where (x->>'ok')::boolean) = 5 and exists (select 1 from jsonb_array_elements((select rules from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1)) x where x->>'code' = 'nss' and x->>'detail' = 'NSS igual')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-09 · Fila 2 (NSS con ceros y monto 2.000,00): segura y a la reclamación de 2,000','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 2) = 'segura' and (select service_line_id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 2) = l_a2 and (select paid_amount from public.payment_remittance_lines where remittance_id = v_rem and row_no = 2) = 2000), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-10 · Fila 3 (pago parcial 700 de 1,200 con coma decimal): segura; el parcial no la vuelve dudosa','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3) = 'segura' and (select service_line_id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3) = l_a3 and (select paid_amount from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3) = 700 and (select ars_status from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3) = 'parcial'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-11 · Fila 4 (rechazada, paga 0): segura y marcada rechazada','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 4) = 'segura' and (select paid_amount from public.payment_remittance_lines where remittance_id = v_rem and row_no = 4) = 0 and (select ars_status from public.payment_remittance_lines where remittance_id = v_rem and row_no = 4) = 'rechazada' and (select service_line_id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 4) = l_a4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-12 · Fila 5 (sin autorización, mismo afiliado con dos servicios): dudosa, con las dos candidatas y la explicación','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) = 'dudosa' and jsonb_array_length((select candidates from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5)) = 2 and (select reason_text from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) like 'Hay 2 reclamaciones parecidas%' and ((select candidates from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5)->0->>'service_line_id')::uuid = l_a5a and (select chosen_by from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-13 · Fila 6 (paga 3,500 de una reclamación de 3,000): nunca es segura; dudosa por exceso','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 6) = 'dudosa' and (select reason_text from public.payment_remittance_lines where remittance_id = v_rem and row_no = 6) like '%mayor que lo pendiente%No se puede asignar más que el monto de la reclamación%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-14 · Fila 7 (NSS que no existe): sin pareja con la instrucción de qué hacer','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 7) = 'sin_pareja' and (select reason_text from public.payment_remittance_lines where remittance_id = v_rem and row_no = 7) like 'No hay ninguna reclamación enviada de esta ARS%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-15 · Fila 9 (la reclamación existe pero su radicación no está enviada): sin pareja y lo dice','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 9) = 'sin_pareja' and (select reason_text from public.payment_remittance_lines where remittance_id = v_rem and row_no = 9) like 'Existe una reclamación con ese NSS o autorización, pero su radicación no está enviada%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-16 · Fila 8 (repetida): duplicado, no se aplica','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 8) = 'duplicado'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-17 · Aislamiento: el mismo NSS en otro cliente y en otra ARS no entra como candidata (la fila 1 tiene una sola)','ok',coalesce((jsonb_array_length((select candidates from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1)) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-18 · Revisar no mueve dinero: todavía no hay ningún pago ni reparto del cliente','ok',coalesce((not exists (select 1 from public.payments where organization_id = v_a) and not exists (select 1 from public.payment_line_allocations where organization_id = v_a)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-19 · El detalle trae lo que falta por aplicar: 4,200 en seguras con pago','ok',coalesce(((v_r->'remittance'->>'to_apply_amount')::numeric = 4200 and jsonb_array_length(v_r->'lines') = 9), false),'d',(v_r->'remittance'->>'to_apply_amount')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_apply(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-20 · ATAQUE: el Médico no aplica pagos de ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-20 · ATAQUE: el Médico no aplica pagos de ARS','ok',sqlerrm like 'Aplicar el pago de una ARS es del Super Admin o un Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_apply(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-21 · ATAQUE: Facturación no aplica pagos de ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-21 · ATAQUE: Facturación no aplica pagos de ARS','ok',sqlerrm like 'Aplicar el pago de una ARS es del Super Admin o un Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_apply(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-22 · ATAQUE: Operaciones no aplica pagos de ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-22 · ATAQUE: Operaciones no aplica pagos de ARS','ok',sqlerrm like 'Aplicar el pago de una ARS es del Super Admin o un Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_apply(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-23 · ATAQUE: Glosas no aplica pagos de ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-23 · ATAQUE: Glosas no aplica pagos de ARS','ok',sqlerrm like 'Aplicar el pago de una ARS es del Super Admin o un Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_apply(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-24 · ATAQUE: el Auditor no aplica pagos de ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-24 · ATAQUE: el Auditor no aplica pagos de ARS','ok',sqlerrm like 'Aplicar el pago de una ARS es del Super Admin o un Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_apply(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-25 · ATAQUE: la Secretaria no aplica pagos de ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-25 · ATAQUE: la Secretaria no aplica pagos de ARS','ok',sqlerrm like 'Aplicar el pago de una ARS es del Super Admin o un Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_resolve(v_q5, l_a5a, false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-26 · ATAQUE: el Médico no resuelve dudosas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-26 · ATAQUE: el Médico no resuelve dudosas','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_resolve(v_q5, l_a5a, false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-27 · ATAQUE: Facturación no resuelve dudosas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-27 · ATAQUE: Facturación no resuelve dudosas','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_resolve(v_q5, l_a5a, false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-28 · ATAQUE: Operaciones no resuelve dudosas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-28 · ATAQUE: Operaciones no resuelve dudosas','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_resolve(v_q5, l_a5a, false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-29 · ATAQUE: el Auditor no resuelve dudosas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-29 · ATAQUE: el Auditor no resuelve dudosas','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_to_glosa(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-30 · ATAQUE: el Auditor no convierte diferencias en glosa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-30 · ATAQUE: el Auditor no convierte diferencias en glosa','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_ignore(v_q7, 'Intento del auditor sobre una fila');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-31 · ATAQUE: el Auditor no ignora filas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-31 · ATAQUE: el Auditor no ignora filas','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    v_r := public.remittance_detail(v_rem);
    v_u := (public.remittance_indicator(v_a)->'summary'->>'total')::numeric;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-32 · El Auditor sí consulta el detalle y el indicador','ok',coalesce((jsonb_array_length(v_r->'lines') = 9 and v_u is not null), false),'d',(v_u::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_detail(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-33 · ATAQUE: el Médico del cliente no ve el detalle de la relación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-33 · ATAQUE: el Médico del cliente no ve el detalle de la relación','ok',sqlerrm like 'Sin acceso a las relaciones de pago de este cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_detail(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-34 · ATAQUE: el Médico de otro cliente no ve el detalle de la relación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-34 · ATAQUE: el Médico de otro cliente no ve el detalle de la relación','ok',sqlerrm like 'Sin acceso a las relaciones de pago de este cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_detail(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-35 · ATAQUE: Facturación no ve el detalle de la relación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-35 · ATAQUE: Facturación no ve el detalle de la relación','ok',sqlerrm like 'Sin acceso a las relaciones de pago de este cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_detail(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-36 · ATAQUE: la Secretaria no ve el detalle de la relación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-36 · ATAQUE: la Secretaria no ve el detalle de la relación','ok',sqlerrm like 'Sin acceso a las relaciones de pago de este cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      update public.payment_remittance_lines set state = 'aplicada', applied_amount = 999999 where id = v_q1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-37 · ATAQUE: ni el Administrador cambia una línea con UPDATE directo (solo las funciones)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-37 · ATAQUE: ni el Administrador cambia una línea con UPDATE directo (solo las funciones)','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.payment_remittance_applications (remittance_id, organization_id, kind, lines_count, amount) values (v_rem, v_a, 'bloque', 1, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-38 · ATAQUE: ni el Administrador inserta un registro de aplicación a mano','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-38 · ATAQUE: ni el Administrador inserta un registro de aplicación a mano','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      delete from public.payment_remittance_lines where id = v_q1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-39 · ATAQUE: ni el Administrador borra líneas de una relación con DELETE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-39 · ATAQUE: ni el Administrador borra líneas de una relación con DELETE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.remittance_apply(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-40 · Un clic: se aplican las 3 seguras con pago (4,200); la rechazada no genera pago','ok',coalesce(((v_r->>'applied')::int = 3 and (v_r->>'amount')::numeric = 4200 and jsonb_array_length(v_r->'skipped') = 0), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-41 · Se registró UN pago con las funciones existentes: transferencia, 4,200, fecha de la relación y referencia con consecutivo','ok',coalesce(((select count(*) from public.payments where organization_id = v_a) = 1 and (select amount from public.payments where organization_id = v_a) = 4200 and (select method from public.payments where organization_id = v_a) = 'transferencia' and (select reference from public.payments where organization_id = v_a) = 'REF-ALFA-189-1' and (select paid_on from public.payments where organization_id = v_a) = current_date - 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-42 · El pago quedó asignado a la radicación por 4,200 y la radicación lo ve pagado','ok',coalesce(((select amount from public.payment_allocations where organization_id = v_a) = 4200 and (select paid from public.v_submission_balance where id = v_s1) = 4200), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-43 · El reparto por reclamación es exacto: 1,500, 2,000 y 700 (la rechazada no recibe nada)','ok',coalesce(((select sum(amount) from public.payment_line_allocations where service_line_id = l_a1 and superseded_at is null) = 1500 and (select sum(amount) from public.payment_line_allocations where service_line_id = l_a2 and superseded_at is null) = 2000 and (select sum(amount) from public.payment_line_allocations where service_line_id = l_a3 and superseded_at is null) = 700 and coalesce((select sum(amount) from public.payment_line_allocations where service_line_id = l_a4 and superseded_at is null), 0) = 0 and (select method from public.payment_line_allocations where service_line_id = l_a3 and superseded_at is null) = 'manual'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-44 · Las 3 líneas quedan aplicadas «automática» (sin intervención manual) con su pago; la rechazada sigue segura','ok',coalesce(((select count(*) from public.payment_remittance_lines where remittance_id = v_rem and state = 'aplicada' and applied_how = 'automatica' and payment_id is not null) = 3 and (select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 4) = 'segura' and (select applied_amount from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3) = 700), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-45 · La reclamación pagada completa se ve pagada y la parcial en pago parcial','ok',coalesce(((select claim_status from public.service_lines where id = l_a1) = 'pagada' and (select claim_status from public.service_lines where id = l_a3) = 'pago_parcial'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_apply(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-46 · IDEMPOTENTE: aplicar otra vez no hace nada (0 líneas) y no duplica el pago','ok',coalesce(((v_r->>'applied')::int = 0 and (select count(*) from public.payments where organization_id = v_a) = 1 and (select count(*) from public.payment_remittance_applications where remittance_id = v_rem) = 1), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_import(v_a, v_x1, v_rows, v_f1, null, 'REF-ALFA-189-COPIA', current_date - 1, null, true, 'relacion_alfa_copia.xlsx');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-47 · IDEMPOTENTE: reimportar el mismo archivo después de aplicar no duplica líneas ni pagos','ok',coalesce(((v_r->>'already_imported')::boolean and (select count(*) from public.payment_remittance_lines where organization_id = v_a) = 9 and (select count(*) from public.payments where organization_id = v_a) = 1), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-48 · Nunca se asigna más que el monto de la reclamación: ninguna reclamación tiene más pagado que su valor','ok',coalesce((not exists (select 1 from public.service_lines l where l.submission_id = v_s1 and coalesce((select sum(p.amount) from public.payment_line_allocations p where p.service_line_id = l.id and p.superseded_at is null), 0) > l.amount)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_indicator(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-49 · Indicador tras aplicar las seguras: 4,200 aplicados sin intervención manual y 0 manual','ok',coalesce(((v_r->'summary'->>'auto')::numeric = 4200 and (v_r->'summary'->>'manual')::numeric = 0 and (v_r->'summary'->>'remittances')::int = 1), false),'d',(v_r->'summary')::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_detail(v_rem, 'diferencia');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-50 · Hay 2 diferencias abiertas por 1,300: lo pagado de menos (500) y lo rechazado (800)','ok',coalesce(((v_r->'differences'->>'lines')::int = 2 and (v_r->'differences'->>'amount')::numeric = 1300 and jsonb_array_length(v_r->'lines') = 2), false),'d',(v_r->'differences')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_to_glosa(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-51 · ATAQUE: el Médico no convierte diferencias en glosa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-51 · ATAQUE: el Médico no convierte diferencias en glosa','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_to_glosa(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-52 · ATAQUE: Facturación no convierte diferencias en glosa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-52 · ATAQUE: Facturación no convierte diferencias en glosa','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_to_glosa(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-53 · ATAQUE: Operaciones no convierte diferencias en glosa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-53 · ATAQUE: Operaciones no convierte diferencias en glosa','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.remittance_to_glosa(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-54 · Glosas convierte las diferencias con un clic: 1 glosa, 2 líneas, 1,300','ok',coalesce(((v_r->>'glosas')::int = 1 and (v_r->>'lines')::int = 2 and (v_r->>'amount')::numeric = 1300), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-55 · La glosa quedó en la radicación con la referencia de la relación y la causa que dijo la ARS (tarifa superior; sin autorización)','ok',coalesce(((select count(*) from public.glosas where submission_id = v_s1) = 1 and (select ars_reference from public.glosas where submission_id = v_s1) = 'REF-ALFA-189' and (select gi.reason_code from public.glosa_items gi where gi.service_line_id = l_a3) = 'tarifa_superior' and (select gi.amount from public.glosa_items gi where gi.service_line_id = l_a3) = 500 and (select gi.reason_code from public.glosa_items gi where gi.service_line_id = l_a4) = 'sin_autorizacion' and (select gi.amount from public.glosa_items gi where gi.service_line_id = l_a4) = 800), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-56 · Las líneas recuerdan su glosa: la parcial sigue aplicada y la rechazada pasa a «glosada»','ok',coalesce(((select glosa_id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3) is not null and (select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3) = 'aplicada' and (select glosa_amount from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3) = 500 and (select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 4) = 'glosada' and (select glosa_amount from public.payment_remittance_lines where remittance_id = v_rem and row_no = 4) = 800), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_to_glosa(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-57 · IDEMPOTENTE: repetir la conversión no crea otra glosa','ok',coalesce(((v_r->>'glosas')::int = 0 and (select count(*) from public.glosas where submission_id = v_s1) = 1), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_detail(v_rem, 'diferencia');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-58 · Ya no quedan diferencias abiertas en la relación','ok',coalesce(((v_r->'differences'->>'lines')::int = 0), false),'d',(v_r->'differences')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_resolve(v_q5, l_a5a, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-59 · ATAQUE: Glosas puede elegir la reclamación pero no aplicar el pago: pide a un Administrador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-59 · ATAQUE: Glosas puede elegir la reclamación pero no aplicar el pago: pide a un Administrador','ok',sqlerrm like 'Aplicar el pago de una ARS es del Super Admin%','d',left(sqlerrm,120)));
    end;
    v_r := public.remittance_resolve(v_q5, l_a5a, false);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-60 · Glosas resuelve la fila 5 sin aplicar: queda segura, elegida por una persona y sin mover dinero','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) = 'segura' and (select chosen_by from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) = 'usuario' and (select service_line_id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) = l_a5a and (select count(*) from public.payments where organization_id = v_a) = 1), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_resolve(v_q6, l_a6, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-61 · No se asigna más que lo pendiente: la fila 6 (3,500) no cabe en la reclamación de 3,000','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-61 · No se asigna más que lo pendiente: la fila 6 (3,500) no cabe en la reclamación de 3,000','ok',sqlerrm like 'Lo pagado (RD$ 3,500.00) es mayor que lo pendiente de esa reclamación (RD$ 3,000.00)%elija otra, o ignore la fila%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_resolve(v_q7, l_b1, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-62 · No se resuelve contra una reclamación de otra ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-62 · No se resuelve contra una reclamación de otra ARS','ok',sqlerrm like 'Esa reclamación es de otra ARS%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_resolve(v_q7, l_x1, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-63 · No se resuelve contra una reclamación de otro cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-63 · No se resuelve contra una reclamación de otro cliente','ok',sqlerrm like 'Esa reclamación no es de este cliente%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_resolve(v_q9, l_a7, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-64 · No se resuelve contra una reclamación cuya radicación no está enviada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-64 · No se resuelve contra una reclamación cuya radicación no está enviada','ok',sqlerrm like 'La radicación de esa reclamación no está enviada%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_resolve(v_q1, l_a1, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-65 · Una línea ya aplicada no se resuelve de nuevo y dice cómo deshacerlo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-65 · Una línea ya aplicada no se resuelve de nuevo y dice cómo deshacerlo','ok',sqlerrm like 'Esta línea está aplicada%','d',left(sqlerrm,120)));
    end;
    v_r := public.remittance_apply(v_rem, array[v_q5]);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-66 · El Administrador aplica la resuelta: 500, marcada MANUAL, y la reclamación queda sin pendiente','ok',coalesce(((v_r->>'applied')::int = 1 and (v_r->>'amount')::numeric = 500 and (select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) = 'aplicada' and (select applied_how from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) = 'manual' and app.pm_line_pending(l_a5a) = 0), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-67 · Esta segunda aplicación creó su propio pago con otra referencia (REF-ALFA-189-2)','ok',coalesce(((select count(*) from public.payments where organization_id = v_a) = 2 and exists (select 1 from public.payments where reference = 'REF-ALFA-189-2' and amount = 500)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.remittance_ignore(v_q6, 'no');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-68 · Ignorar exige un motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-68 · Ignorar exige un motivo','ok',sqlerrm like 'Escriba por qué se ignora la fila%','d',left(sqlerrm,120)));
    end;
    perform public.remittance_ignore(v_q6, 'La ARS pagó de más; se consulta con la ARS antes de aplicar');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-69 · Ignorar deja la fila ignorada con su nota y fuera de lo pendiente','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 6) = 'ignorada' and (select note from public.payment_remittance_lines where remittance_id = v_rem and row_no = 6) like 'La ARS pagó de más%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_reopen(v_q6);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-70 · Reabrir una ignorada la vuelve a revisar (y sigue dudosa por exceso)','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 6) = 'dudosa' and (select note from public.payment_remittance_lines where remittance_id = v_rem and row_no = 6) is null), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_search_lines(v_rem, 'Paciente QA Cinco');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-71 · Buscar a mano por nombre devuelve las reclamaciones abiertas de la ARS (2 de la paciente Cinco)','ok',coalesce((jsonb_array_length(v_r) = 2), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_search_lines(v_rem, 'Siete');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-72 · La búsqueda no ofrece reclamaciones de radicaciones sin enviar','ok',coalesce((jsonb_array_length(v_r) = 0), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_search_lines(v_rem, '900-00101');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-73 · La búsqueda por NSS con guiones encuentra solo la del cliente y la ARS (no la de otro cliente ni la de otra ARS)','ok',coalesce((jsonb_array_length(v_r) = 1 and (v_r->0->>'service_line_id')::uuid = l_a1), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.remittance_search_lines(v_rem, 'ab');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-74 · Buscar con menos de 3 caracteres dice qué escribir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-74 · Buscar con menos de 3 caracteres dice qué escribir','ok',sqlerrm like 'Escriba al menos 3 caracteres%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_reopen(v_q8, 'no');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-75 · «No es duplicado» exige explicar por qué','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-75 · «No es duplicado» exige explicar por qué','ok',sqlerrm like 'Escriba por qué no es un duplicado%','d',left(sqlerrm,120)));
    end;
    v_r := public.remittance_reopen(v_q8, 'Segundo pago parcial real de la misma autorización');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-76 · Si se declara «no es duplicado» pero esa reclamación ya está pagada, el motor no la deja segura (nunca paga dos veces)','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 8) = 'dudosa' and (select reason_text from public.payment_remittance_lines where remittance_id = v_rem and row_no = 8) like '%mayor que lo pendiente%' and (select allow_duplicate from public.payment_remittance_lines where id = v_q8)), false),'d',((select reason_text from public.payment_remittance_lines where remittance_id = v_rem and row_no = 8))::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_indicator(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-77 · Indicador: de 10,700 de la relación, 4,200 se aplicaron solos (39.3 %) y 500 con intervención manual','ok',coalesce(((v_r->'summary'->>'total')::numeric = 10700 and (v_r->'summary'->>'auto')::numeric = 4200 and (v_r->'summary'->>'manual')::numeric = 500 and (v_r->'summary'->>'pct_auto')::numeric = 39.3), false),'d',(v_r->'summary')::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.remittance_annul(v_rem, 'Intento de anular una relación aplicada');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-78 · Una relación con pagos aplicados no se anula y dice cómo deshacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-78 · Una relación con pagos aplicados no se anula y dice cómo deshacer','ok',sqlerrm like 'La relación REL-%ya tiene pagos aplicados%','d',left(sqlerrm,120)));
    end;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-79 · La relación pasó por sus estados: tiene aplicaciones registradas y queda en aplicación mientras hay filas abiertas','ok',coalesce(((select status from public.payment_remittances where id = v_rem) = 'en_aplicacion' and (select count(*) from public.payment_remittance_applications where remittance_id = v_rem) = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-80 · Cada aplicación queda en la bitácora de auditoría','ok',coalesce(((select count(*) from public.audit_log where table_name = 'payment_remittance_applications' and operation = 'INSERT' and organization_id = v_a) = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_rows := jsonb_build_array(
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '1.000,00', 'Observación', ''),
      jsonb_build_object('NSS', '80000202', 'No. Autorización', 'BET-2002', 'Fecha', v_d0, 'Valor Reclamado', '2500,00', 'Valor Aprobado', '2500,00', 'Observación', ''),
      jsonb_build_object('NSS', '800-00203', 'No. Autorización', 'BET-2003', 'Fecha', v_d1, 'Valor Reclamado', '4.000,00', 'Valor Aprobado', '4.000,00', 'Observación', ''));
      v_r := public.remittance_import(v_a, v_x2, v_rows, v_f2, null, 'REF-BETA-189', current_date - 2, null, true, 'beta.xlsx');
      v_rem := (v_r->>'remittance')::uuid;
      v_r := public.remittance_detail(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-81 · ARS Beta (montos «1.000,00» y «2500,00», NSS con guion): las 3 filas salen seguras','ok',coalesce(((v_r->'counts'->>'segura')::int = 3 and not exists (select 1 from jsonb_array_elements(v_r->'lines') x where x->>'state' <> 'segura')), false),'d',(v_r->'counts')::text));
    perform set_config('role', v_rl, true);
      v_r := public.remittance_apply(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-82 · Aplicar Beta: 7,500 en un pago y cada reclamación queda pagada completa','ok',coalesce(((v_r->>'amount')::numeric = 7500 and app.pm_line_pending(l_b1) = 0 and app.pm_line_pending(l_b2) = 0 and app.pm_line_pending(l_b3) = 0 and app.pm_line_pending(l_b0) = 100), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
      v_r := public.remittance_detail(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-83 · La relación Beta queda «aplicada» (ya no tiene filas abiertas)','ok',coalesce(((select status from public.payment_remittances where id = v_rem) = 'aplicada'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
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
      v_rows := jsonb_build_array(
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '1.000,00', 'Observación', ''),
      jsonb_build_object('NSS', '80000202', 'No. Autorización', 'BET-2002', 'Fecha', v_d0, 'Valor Reclamado', '2500,00', 'Valor Aprobado', '2500,00', 'Observación', ''),
      jsonb_build_object('NSS', '800-00203', 'No. Autorización', 'BET-2003', 'Fecha', v_d1, 'Valor Reclamado', '4.000,00', 'Valor Aprobado', '4.000,00', 'Observación', ''));
      v_r := public.remittance_import(v_a, v_x2, v_rows, v_f2, null, 'REF-BETA-RACE', current_date - 2, null, true, 'beta.xlsx');
      v_rem := (v_r->>'remittance')::uuid;
      v_pay := public.register_payment(v_a, v_x2, current_date - 1, 1000, 'transferencia', 'PAGO-APARTE-1', jsonb_build_array(jsonb_build_object('submission_id', v_s3, 'amount', 1000)));
      select id into v_al from public.payment_allocations where payment_id = v_pay;
      perform public.adjust_payment_distribution(v_al, jsonb_build_array(jsonb_build_object('service_line_id', l_b1, 'amount', 1000)), 'Pago aparte de la prueba');
      v_r := public.remittance_apply(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-84 · Si mientras tanto alguien pagó una reclamación, al aplicar se revalida: esa fila vuelve a dudosa con el motivo y las otras se aplican','ok',coalesce(((v_r->>'applied')::int = 2 and (v_r->>'amount')::numeric = 6500 and jsonb_array_length(v_r->'skipped') = 1 and (v_r->'skipped'->0->>'reason') like 'Mientras tanto la reclamación quedó con menos saldo%' and (select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = 'dudosa'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-85 · Esa reclamación no recibió un segundo pago: sigue con los 1,000 del pago aparte','ok',coalesce(((select sum(amount) from public.payment_line_allocations where service_line_id = l_b1 and superseded_at is null) = 1000), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
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
      v_rows := jsonb_build_array(
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '400,00', 'Observación', ''),
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '600,00', 'Observación', ''));
      v_r := public.remittance_import(v_a, v_x2, v_rows, v_f2, null, 'REF-BETA-PARC', current_date - 2, null, true, 'beta_parcial.xlsx');
      v_rem := (v_r->>'remittance')::uuid;
      v_r := public.remittance_detail(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-86 · Dos pagos parciales distintos (400 y 600) sobre una reclamación de 1,000: ambas filas seguras','ok',coalesce(((v_r->'counts'->>'segura')::int = 2), false),'d',(v_r->'counts')::text));
    perform set_config('role', v_rl, true);
      v_r := public.remittance_apply(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-87 · Se aplican los dos y suman exactamente lo pendiente (1,000), ni un peso más','ok',coalesce(((v_r->>'applied')::int = 2 and (v_r->>'amount')::numeric = 1000 and app.pm_line_pending(l_b1) = 0 and (select sum(amount) from public.payment_line_allocations where service_line_id = l_b1 and superseded_at is null) = 1000), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
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
      v_rows := jsonb_build_array(
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '600,00', 'Observación', ''),
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '700,00', 'Observación', ''));
      v_r := public.remittance_import(v_a, v_x2, v_rows, v_f2, null, 'REF-BETA-EXC', current_date - 2, null, true, 'beta_exceso.xlsx');
      v_rem := (v_r->>'remittance')::uuid;
      v_r := public.remittance_detail(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-88 · Dos filas que sumadas (600 + 700) pasan lo pendiente: la primera es segura y la segunda dudosa, con el motivo','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = 'segura' and (select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 2) = 'dudosa' and (select reason_text from public.payment_remittance_lines where remittance_id = v_rem and row_no = 2) like 'Otra fila de esta misma relación ya usa esa reclamación%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
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
      v_rows := jsonb_build_array(
      jsonb_build_object('Afiliado', '70000301', 'Fecha de servicio', v_d0, 'Pagado', '750'),
      jsonb_build_object('Afiliado', '70000302', 'Fecha de servicio', v_d1, 'Pagado', '1,250.00'));
      v_r := public.remittance_import(v_a, v_x3, v_rows, v_f3, null, 'REF-GAMMA-189', current_date - 2, null, true, 'gamma.csv');
      v_rem := (v_r->>'remittance')::uuid;
      v_r := public.remittance_detail(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-89 · ARS Gamma (solo NSS, fecha y pagado): la fila única por NSS, fecha y monto es segura; la que tiene dos reclamaciones idénticas es dudosa aunque llegue al 100 %','ok',coalesce(((v_r->'counts'->>'segura')::int = 1 and (v_r->'counts'->>'dudosa')::int = 1 and (select x->>'state' from jsonb_array_elements(v_r->'lines') x where (x->>'row_no')::int = 1) = 'dudosa' and (select (x->>'score')::int from jsonb_array_elements(v_r->'lines') x where (x->>'row_no')::int = 1) = 100 and (select x->>'reason' from jsonb_array_elements(v_r->'lines') x where (x->>'row_no')::int = 1) like 'Hay 2 reclamaciones parecidas%'), false),'d',(v_r->'counts')::text));
    perform set_config('role', v_rl, true);
      v_q1 := (select id from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1);
      v_r := public.remittance_resolve(v_q1, l_g1, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-90 · Se resuelve a mano (elegir y aplicar en un paso): 750 aplicados, marcados manual','ok',coalesce(((v_r->>'applied')::int = 1 and (v_r->>'amount')::numeric = 750 and (select applied_how from public.payment_remittance_lines where id = v_q1) = 'manual' and app.pm_line_pending(l_g1) = 0 and app.pm_line_pending(l_g3) = 750), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
      v_r := public.remittance_apply(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-91 · Un clic aplica la segura que quedaba (1,250) como automática','ok',coalesce(((v_r->>'applied')::int = 1 and (v_r->>'amount')::numeric = 1250 and app.pm_line_pending(l_g2) = 0), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
      v_r := public.remittance_indicator(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-92 · El indicador de esa relación es 62.5 % automático (1,250 de 2,000; 750 fueron manuales)','ok',coalesce(((select (x->>'pct_auto')::numeric from jsonb_array_elements(v_r->'by_remittance') x where x->>'folio' = (select folio from public.payment_remittances where id = v_rem)) = 62.5), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
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
      v_rows := jsonb_build_array(
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '1.000,00', 'Observación', ''),
      jsonb_build_object('NSS', '80000202', 'No. Autorización', 'BET-2002', 'Fecha', v_d0, 'Valor Reclamado', '2500,00', 'Valor Aprobado', '2500,00', 'Observación', ''),
      jsonb_build_object('NSS', '800-00203', 'No. Autorización', 'BET-2003', 'Fecha', v_d1, 'Valor Reclamado', '4.000,00', 'Valor Aprobado', '4.000,00', 'Observación', ''));
      v_r := public.remittance_import(v_a, v_x2, v_rows, v_f2, null, 'REF-BETA-TANDAS', current_date - 2, null, true, 'beta.xlsx');
      v_rem := (v_r->>'remittance')::uuid;
      v_r := public.remittance_apply(v_rem, null, 2);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-93 · Aplicar por tandas: la primera tanda aplica 2 líneas (con su pago) y avisa que queda 1 por aplicar','ok',coalesce(((v_r->>'applied')::int = 2 and (v_r->>'remaining')::int = 1 and (select count(*) from public.payments where reference like 'REF-BETA-TANDAS-%') = 1), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
      v_r := public.remittance_apply(v_rem, null, 2);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-94 · La segunda tanda aplica la que faltaba con otro pago y ya no queda nada; en total 7,500 sin duplicar','ok',coalesce(((v_r->>'applied')::int = 1 and (v_r->>'remaining')::int = 0 and (select count(*) from public.payments where reference like 'REF-BETA-TANDAS-%') = 2 and (select sum(amount) from public.payments where reference like 'REF-BETA-TANDAS-%') = 7500), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
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
      v_rows := (select jsonb_agg(jsonb_build_object('Afiliado', '7999' || lpad(g::text, 5, '0'), 'Fecha de servicio', v_d0, 'Pagado', '100')) from generate_series(1, 650) g);
      v_r := public.remittance_import(v_a, v_x3, v_rows, v_f3, null, 'REF-GAMMA-GRANDE', current_date - 2, null, true, 'grande.csv');
      v_rem := (v_r->>'remittance')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-95 · Una relación de más de 600 filas no se revisa sola al importar: las deja sin revisar y avisa que falta correr el motor','ok',coalesce(((v_r->>'match_pending')::boolean and (select count(*) from public.payment_remittance_lines where remittance_id = v_rem and state = 'pendiente') = 650), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
      v_r := public.remittance_match(v_rem, true, 300);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-96 · El motor por tandas revisa 300 y dice cuántas faltan (350)','ok',coalesce(((v_r->>'pending_review')::int = 350 and (v_r->>'sin_pareja')::int = 300), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
      v_r := public.remittance_match(v_rem, true, 300);
      v_r := public.remittance_match(v_rem, true, 300);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-97 · Tras las tandas necesarias no queda ninguna sin revisar (650 sin pareja) y la relación no se vuelve a revisar de cero','ok',coalesce((coalesce((v_r->>'pending_review')::int, 0) = 0 and (v_r->>'sin_pareja')::int = 650), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
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
      v_rows := jsonb_build_array(jsonb_build_object('NSS', '80000201', 'Aut', 'BET-2001', 'Pagado', '1000'), jsonb_build_object('NSS', '80000202', 'Aut', '', 'Pagado', '2500'));
      v_r := public.remittance_import(v_a, v_x2, v_rows, null, '{"nss":"NSS","autorizacion":"Aut","pagado":"Pagado"}'::jsonb, 'REF-BETA-MIN', current_date - 2, null, true, 'minimo.csv');
      v_rem := (v_r->>'remittance')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-98 · Un archivo con solo NSS, autorización y pagado: la fila con NSS y autorización exactos es segura (100 % de lo que el archivo permite evaluar)','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = 'segura' and (select score from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = 100), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-99 · La fila con solo NSS (sin autorización ni fecha en el archivo) nunca es segura: dudosa y lo explica','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 2) = 'dudosa' and (select reason_text from public.payment_remittance_lines where remittance_id = v_rem and row_no = 2) like 'La coincidencia es incompleta%NSS con fecha o autorización%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
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
      v_rows := jsonb_build_array(
      jsonb_build_object('NSS', '80000202', 'No. Autorización', 'BET-2002', 'Fecha', v_d0, 'Valor Reclamado', '2500,00', 'Valor Aprobado', '0', 'Observación', ''),
      jsonb_build_object('NSS', '800-00203', 'No. Autorización', 'BET-2003', 'Fecha', v_d1, 'Valor Reclamado', '4.000,00', 'Valor Aprobado', '1.000,00', 'Observación', ''));
      v_r := public.remittance_import(v_a, v_x2, v_rows, v_f2, null, 'REF-BETA-CAUSA', current_date - 2, null, true, 'beta_causa.xlsx');
      v_rem := (v_r->>'remittance')::uuid;
      perform public.remittance_apply(v_rem);
      v_r := public.remittance_to_glosa(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-100 · Sin causa escrita por la ARS: lo rechazado es «rechazada en la relación» y lo pagado de menos es «pago menor»','ok',coalesce(((v_r->>'amount')::numeric = 5500 and (select gi.reason_code from public.glosa_items gi where gi.service_line_id = l_b2) = 'rechazada_ars' and (select gi.amount from public.glosa_items gi where gi.service_line_id = l_b2) = 2500 and (select gi.reason_code from public.glosa_items gi where gi.service_line_id = l_b3) = 'pago_menor' and (select gi.amount from public.glosa_items gi where gi.service_line_id = l_b3) = 3000), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
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
      v_rows := jsonb_build_array(
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '1.000,00', 'Observación', ''),
      jsonb_build_object('NSS', '80000202', 'No. Autorización', 'BET-2002', 'Fecha', v_d0, 'Valor Reclamado', '2500,00', 'Valor Aprobado', '2500,00', 'Observación', ''),
      jsonb_build_object('NSS', '800-00203', 'No. Autorización', 'BET-2003', 'Fecha', v_d1, 'Valor Reclamado', '4.000,00', 'Valor Aprobado', '4.000,00', 'Observación', ''));
      v_r := public.remittance_import(v_a, v_x2, v_rows, v_f2, null, 'REF-BETA-ANUL', current_date - 2, null, true, 'beta.xlsx');
      v_rem := (v_r->>'remittance')::uuid;
      perform public.remittance_annul(v_rem, 'Se cargó la relación equivocada');
    begin
      perform public.remittance_apply(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-101 · Una relación anulada no se aplica ni se revisa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-101 · Una relación anulada no se aplica ni se revisa','ok',sqlerrm like 'La relación REL-%está anulada%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_match(v_rem);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-102 · Una relación anulada no se vuelve a revisar con el motor','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-102 · Una relación anulada no se vuelve a revisar con el motor','ok',sqlerrm like 'La relación REL-%está anulada%','d',left(sqlerrm,120)));
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
      v_rows := jsonb_build_array(
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '1.000,00', 'Observación', ''),
      jsonb_build_object('NSS', '80000202', 'No. Autorización', 'BET-2002', 'Fecha', v_d0, 'Valor Reclamado', '2500,00', 'Valor Aprobado', '2500,00', 'Observación', ''),
      jsonb_build_object('NSS', '800-00203', 'No. Autorización', 'BET-2003', 'Fecha', v_d1, 'Valor Reclamado', '4.000,00', 'Valor Aprobado', '4.000,00', 'Observación', ''));
      v_r := public.remittance_import(v_a, v_x2, v_rows, v_f2, null, 'REF-BETA-AJENA', current_date - 2, null, true, 'beta.xlsx');
      v_rem2 := (v_r->>'remittance')::uuid;
      v_r := public.remittance_apply(v_rem2, array[v_q1, v_q2, v_q3]);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-103 · ATAQUE: pasar ids de líneas de OTRA relación en la lista no aplica nada de esa otra relación','ok',coalesce(((v_r->>'applied')::int = 0 and not exists (select 1 from public.payments where reference like 'REF-BETA-AJENA%')), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_rem := v_main;
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      insert into public.organization_plans (organization_id, plan_code, starts_on, status) values (v_a, 'saas_basico', current_date, 'activo');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      begin
        perform public.remittance_apply(v_rem);
        v_n := -1;
      exception when others then v_n := case when sqlerrm like 'El plan de este cliente no incluye la conciliación de pagos%' then 1 else 0 end; end;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-104 · Con el bloqueo por plan encendido y un plan sin conciliación, aplicar se frena en el servidor y dice cómo mejorar el plan','ok',coalesce((v_n = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_rem := v_main;
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      insert into public.organization_plans (organization_id, plan_code, starts_on, status) values (v_a, 'saas_intermedio', current_date, 'activo');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.remittance_detail(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-105 · Con el plan Intermedio (incluye conciliación) el cliente sí usa el módulo aunque el bloqueo esté encendido','ok',coalesce((jsonb_array_length(v_r->'lines') = 9), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_rem := v_main;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.remittance_match(v_rem);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-106 · Volver a correr el motor no pisa lo ya aplicado ni lo glosado (4 aplicadas y 1 glosada siguen igual)','ok',coalesce(((select count(*) from public.payment_remittance_lines where remittance_id = v_rem and state = 'aplicada') = 4 and (select count(*) from public.payment_remittance_lines where remittance_id = v_rem and state = 'glosada') = 1), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);

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
revoke all on function app.qa_run_tests_conciliacion_motor() from public, anon, authenticated;
