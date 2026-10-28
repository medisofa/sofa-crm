-- 187 · Suite de la 186 (relaciones de pago de las ARS: estructura e importador, I58). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_relaciones_pago();
create or replace function app.qa_run_tests_relaciones_pago()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_a constant uuid := '01860000-0000-4000-8000-000000000001'; v_b constant uuid := '01860000-0000-4000-8000-000000000002';
  v_pa constant uuid := '01860000-0000-4000-8000-000000000011'; v_pb constant uuid := '01860000-0000-4000-8000-000000000012';
  v_sa constant text := '01860000-0000-4000-8000-000000000021'; v_ad constant text := '01860000-0000-4000-8000-000000000022'; v_gl constant text := '01860000-0000-4000-8000-000000000023'; v_au constant text := '01860000-0000-4000-8000-000000000024'; v_bil constant text := '01860000-0000-4000-8000-000000000025'; v_ops constant text := '01860000-0000-4000-8000-000000000026';
  v_co constant text := '01860000-0000-4000-8000-000000000027'; v_ma constant text := '01860000-0000-4000-8000-000000000031'; v_mb constant text := '01860000-0000-4000-8000-000000000032'; v_sec constant text := '01860000-0000-4000-8000-000000000033';
  v_x1 uuid; v_x2 uuid; v_x3 uuid; v_proc uuid; v_per date; v_d0 text; v_d1 text; v_d2 text; v_d3 text; v_d4 text;
  v_s1 uuid; v_s2 uuid; v_s3 uuid; v_s4 uuid; v_s5 uuid;
  v_f1 uuid; v_f2 uuid; v_f3 uuid; v_rows jsonb; v_r jsonb; v_rem uuid; v_rem2 uuid; v_id uuid; v_rl text; v_t numeric; v_u numeric;
  l_a1 uuid; l_a2 uuid; l_a3 uuid; l_a4 uuid; l_a5a uuid; l_a5b uuid; l_a6 uuid; l_a7 uuid; l_b0 uuid; l_b1 uuid; l_b2 uuid; l_b3 uuid; l_g1 uuid; l_g2 uuid; l_g3 uuid; l_x1 uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '186') then
    raise exception 'Falta la migración 186. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.rp.sa@sofa.test','x'),(v_ad::uuid,'qa.rp.ad@sofa.test','x'),(v_gl::uuid,'qa.rp.gl@sofa.test','x'),(v_au::uuid,'qa.rp.au@sofa.test','x'),(v_bil::uuid,'qa.rp.bil@sofa.test','x'),(v_ops::uuid,'qa.rp.ops@sofa.test','x'),(v_co::uuid,'qa.rp.co@sofa.test','x'),(v_ma::uuid,'qa.rp.ma@sofa.test','x'),(v_mb::uuid,'qa.rp.mb@sofa.test','x'),(v_sec::uuid,'qa.rp.sec@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.rp.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_a, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA RP Consultorio A', '00000018601', 'Médico independiente', 'activo', current_date - 90, '8095558601');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_b, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA RP Consultorio B', '00000018602', 'Médico independiente', 'activo', current_date - 90, '8095558602');
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
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-01 · La migración 186 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '186')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-02 · Las cuatro tablas existen con RLS encendida','ok',coalesce(((select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('payment_import_formats','payment_remittances','payment_remittance_lines','payment_remittance_applications') and relrowsecurity) = 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-03 · anon no tiene ningún permiso sobre las tablas de relaciones de pago','ok',coalesce((not has_table_privilege('anon', 'public.payment_remittances', 'select') and not has_table_privilege('anon', 'public.payment_remittance_lines', 'select') and not has_table_privilege('anon', 'public.payment_import_formats', 'select')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-04 · authenticated solo puede leer (sin insertar, actualizar ni borrar) las tablas de relaciones','ok',coalesce((has_table_privilege('authenticated', 'public.payment_remittances', 'select') and not has_table_privilege('authenticated', 'public.payment_remittances', 'insert') and not has_table_privilege('authenticated', 'public.payment_remittance_lines', 'update') and not has_table_privilege('authenticated', 'public.payment_remittance_lines', 'delete') and not has_table_privilege('authenticated', 'public.payment_import_formats', 'insert')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-05 · Las funciones públicas no están abiertas a anon pero sí a authenticated','ok',coalesce((not has_function_privilege('anon', 'public.remittance_import(uuid,uuid,jsonb,uuid,jsonb,text,date,numeric,boolean,text)', 'execute') and not has_function_privilege('anon', 'public.remittance_list(uuid,text)', 'execute') and has_function_privilege('authenticated', 'public.remittance_import(uuid,uuid,jsonb,uuid,jsonb,text,date,numeric,boolean,text)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-06 · Las funciones internas (app.pm_*) no se llaman desde la API','ok',coalesce((not has_function_privilege('authenticated', 'app.pm_require(uuid,text)', 'execute') and not has_function_privilege('authenticated', 'app.pm_parse_amount(text)', 'execute') and not has_function_privilege('anon', 'app.pm_refresh_status(uuid)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-07 · NSS con guiones, espacios y ceros a la izquierda son el mismo número','ok',coalesce((app.pm_norm_id('001-0123456-7') = '101234567' and app.pm_norm_id('0010123456 7') = '101234567' and app.pm_norm_id('00101234567') = '101234567' and app.pm_norm_id('  ') is null and app.pm_norm_id(null) is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-08 · La autorización se limpia sin importar mayúsculas ni guiones','ok',coalesce((app.pm_norm_id('aut-1002') = 'AUT1002' and app.pm_norm_id('AUT 1002') = 'AUT1002'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-09 · Montos con punto decimal, coma de miles y símbolo: «RD$ 12,500.00» = 12500','ok',coalesce((app.pm_parse_amount('RD$ 12,500.00') = 12500.00 and app.pm_parse_amount('1,500.00') = 1500.00 and app.pm_parse_amount('1500') = 1500), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-10 · Montos con coma decimal: «1234,50» = 1234.50, «12,5» = 12.5 y «12.500,00» = 12500','ok',coalesce((app.pm_parse_amount('1234,50') = 1234.50 and app.pm_parse_amount('12,5') = 12.5 and app.pm_parse_amount('12.500,00') = 12500.00 and app.pm_parse_amount('1200,00') = 1200), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-11 · «1,234» (coma de miles) vale mil doscientos treinta y cuatro; el paréntesis es negativo; el texto raro no se entiende','ok',coalesce((app.pm_parse_amount('1,234') = 1234 and app.pm_parse_amount('(300.00)') = -300.00 and app.pm_parse_amount('abc') is null and app.pm_parse_amount('') is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-12 · El encabezado se encuentra sin importar mayúsculas, tildes ni espacios','ok',coalesce((app.pm_get('{"No. Autorización": "AUT-1"}'::jsonb, 'no. autorizacion') = 'AUT-1' and app.pm_get('{"A": " x "}'::jsonb, 'A') = 'x' and app.pm_get('{"A": ""}'::jsonb, 'A') is null and app.pm_get('{"A": "1"}'::jsonb, 'B') is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_f1 := public.payment_format_save(v_a, v_x1, 'QA Alfa · relación mensual', '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb);
    v_f2 := public.payment_format_save(v_a, v_x2, 'QA Beta · relación mensual', '{"nss":"NSS","autorizacion":"No. Autorización","fecha":"Fecha","facturado":"Valor Reclamado","pagado":"Valor Aprobado","motivo":"Observación"}'::jsonb);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-13 · El Administrador guarda un formato de columnas por cliente y ARS','ok',coalesce(((select count(*) from public.payment_import_formats where organization_id = v_a) = 2 and (select columns->>'nss' from public.payment_import_formats where id = v_f1) = 'No. Afiliado'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.payment_format_save(v_a, v_x1, 'qa alfa · RELACIÓN mensual', '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-14 · Otro formato con el mismo nombre en la misma ARS se rechaza y dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-14 · Otro formato con el mismo nombre en la misma ARS se rechaza y dice qué hacer','ok',sqlerrm like 'Ya existe un formato con el nombre%Elíjalo de la lista%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.payment_format_save(v_a, v_x1, 'Sin pagado', '{"nss":"NSS"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-15 · Un formato sin la columna del monto pagado se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-15 · Un formato sin la columna del monto pagado se rechaza','ok',sqlerrm like 'Falta indicar la columna del monto pagado%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.payment_format_save(v_a, v_x1, 'Sin ids', '{"pagado":"Pagado","fecha":"Fecha"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-16 · Un formato sin NSS ni autorización se rechaza (no habría con qué buscar)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-16 · Un formato sin NSS ni autorización se rechaza (no habría con qué buscar)','ok',sqlerrm like 'Indique al menos la columna del NSS o la del número de autorización%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.payment_format_save(v_a, v_x1, 'Dato raro', '{"pagado":"P","nss":"N","salario":"S"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-17 · Un dato desconocido en el mapeo se rechaza y lista los válidos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-17 · Un dato desconocido en el mapeo se rechaza y lista los válidos','ok',sqlerrm like 'El dato «salario» no existe en el mapeo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.payment_format_save(v_a, v_x1, 'ab', '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-18 · El nombre del formato necesita al menos 3 letras','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-18 · El nombre del formato necesita al menos 3 letras','ok',sqlerrm like 'Ponga un nombre al formato%','d',left(sqlerrm,120)));
    end;
    v_r := public.payment_formats_list(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-19 · La lista de formatos devuelve los dos con su ARS y las columnas','ok',coalesce((jsonb_array_length(v_r) = 2 and (select count(*) from jsonb_array_elements(v_r) x where x->>'ars' like 'ARS QA%') = 2), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform public.payment_format_save(v_a, v_x1, 'QA Alfa · renombrado', '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb, v_f1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-20 · Editar un formato por su id cambia el nombre sin duplicarlo','ok',coalesce(((select name from public.payment_import_formats where id = v_f1) = 'QA Alfa · renombrado' and (select count(*) from public.payment_import_formats where organization_id = v_a) = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.payment_format_save(v_a, v_x1, 'Formato de facturación', '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-21 · ATAQUE: Facturación no guarda formatos (la 174 le quitó los pagos de ARS)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-21 · ATAQUE: Facturación no guarda formatos (la 174 le quitó los pagos de ARS)','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.payment_format_save(v_a, v_x1, 'Formato de operaciones', '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-22 · ATAQUE: Operaciones no guarda formatos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-22 · ATAQUE: Operaciones no guarda formatos','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.payment_format_save(v_a, v_x1, 'Formato del médico', '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-23 · ATAQUE: el Médico no guarda formatos ni siquiera de su propio consultorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-23 · ATAQUE: el Médico no guarda formatos ni siquiera de su propio consultorio','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.payment_formats_list(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-24 · ATAQUE: el Médico no lista los formatos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-24 · ATAQUE: el Médico no lista los formatos','ok',sqlerrm like 'Sin acceso a las relaciones de pago de este cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_list(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-25 · ATAQUE: la Secretaria no lista relaciones de pago','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-25 · ATAQUE: la Secretaria no lista relaciones de pago','ok',sqlerrm like 'Sin acceso a las relaciones de pago de este cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.payment_format_save(v_a, v_x1, 'Formato del auditor', '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-26 · ATAQUE: el Auditor consulta pero no guarda formatos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-26 · ATAQUE: el Auditor consulta pero no guarda formatos','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    v_r := public.payment_formats_list(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-27 · El Auditor sí consulta la lista de formatos','ok',coalesce((jsonb_array_length(v_r) = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_id := public.payment_format_save(v_a, v_x3, 'QA Gamma · relación mensual', '{"nss":"Afiliado","fecha":"Fecha de servicio","pagado":"Pagado"}'::jsonb);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-28 · Glosas sí guarda formatos','ok',coalesce((exists (select 1 from public.payment_import_formats where id = v_id)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.payment_format_delete(v_id);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-29 · El Administrador borra un formato','ok',coalesce((not exists (select 1 from public.payment_import_formats where id = v_id)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_rows := jsonb_build_array(
      jsonb_build_object('No. Afiliado', '900-00101', 'Autorización', 'AUT-1001', 'Fecha Servicio', v_d0, 'Monto Facturado', '1,500.00', 'Monto Pagado', '1,500.00', 'Estado', 'Pagada', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '0090000102', 'Autorización', 'aut 1002', 'Fecha Servicio', v_d0, 'Monto Facturado', '2.000,00', 'Monto Pagado', '2.000,00', 'Estado', 'Pagada', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '900 00103', 'Autorización', 'AUT-1003', 'Fecha Servicio', v_d1, 'Monto Facturado', '1200,00', 'Monto Pagado', '700,00', 'Estado', 'Parcial', 'Motivo', 'Tarifa superior a la contratada'),
      jsonb_build_object('No. Afiliado', '90000104', 'Autorización', 'AUT-1004', 'Fecha Servicio', v_d1, 'Monto Facturado', '800', 'Monto Pagado', '0', 'Estado', 'Rechazada', 'Motivo', 'Sin autorización vigente'),
      jsonb_build_object('No. Afiliado', '900-00101', 'Autorización', 'AUT-1001', 'Fecha Servicio', v_d0, 'Monto Facturado', '1,500.00', 'Monto Pagado', '1,500.00', 'Estado', 'Pagada', 'Motivo', ''));
    v_r := public.remittance_import(v_a, v_x1, v_rows, v_f1, null, null, null, null, false, 'relacion_alfa.xlsx');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-30 · Revisar no guarda nada: 5 filas válidas, 1 repetida en el archivo y 0 errores','ok',coalesce(((v_r->>'valid')::int = 5 and (v_r->>'duplicates_in_file')::int = 1 and jsonb_array_length(v_r->'errors') = 0 and not exists (select 1 from public.payment_remittances where organization_id = v_a)), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-31 · El total pagado no cuenta la fila repetida: 4,200 (1,500 + 2,000 + 700 + 0)','ok',coalesce(((v_r->>'total_paid')::numeric = 4200), false),'d',(v_r->>'total_paid')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-32 · La revisión limpia los datos: NSS sin guiones, autorización en mayúscula, montos con coma y estado parcial/rechazada','ok',coalesce(((v_r->'rows'->0->>'nss') = '90000101' and (v_r->'rows'->1->>'nss') = '90000102' and (v_r->'rows'->1->>'auth_no') = 'AUT1002' and (v_r->'rows'->1->>'billed')::numeric = 2000 and (v_r->'rows'->2->>'paid')::numeric = 700 and v_r->'rows'->2->>'ars_status' = 'parcial' and v_r->'rows'->3->>'ars_status' = 'rechazada'), false),'d',(v_r->'rows')::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_import(v_a, v_x1, v_rows, v_f1, null, null, null, 4000, false, 'relacion_alfa.xlsx');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-33 · Si el total declarado no cuadra, la revisión dice la diferencia (la ARS retuvo 200)','ok',coalesce(((v_r->>'total_difference')::numeric = -200), false),'d',(v_r->>'total_difference')::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_import(v_a, v_x1, jsonb_build_array(
      jsonb_build_object('No. Afiliado', '90000108', 'Autorización', 'AUT-2001', 'Fecha Servicio', v_d0, 'Monto Facturado', '100', 'Monto Pagado', 'abc', 'Estado', '', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '', 'Autorización', '', 'Fecha Servicio', v_d0, 'Monto Facturado', '100', 'Monto Pagado', '100', 'Estado', '', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '90000109', 'Autorización', 'AUT-2002', 'Fecha Servicio', '31/02/2026', 'Monto Facturado', '100', 'Monto Pagado', '100', 'Estado', '', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '90000110', 'Autorización', 'AUT-2003', 'Fecha Servicio', v_d0, 'Monto Facturado', '100', 'Monto Pagado', '(300.00)', 'Estado', '', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '', 'Autorización', '', 'Fecha Servicio', '', 'Monto Facturado', '', 'Monto Pagado', '', 'Estado', '', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '90000111', 'Autorización', 'AUT-2004', 'Fecha Servicio', v_d0, 'Monto Facturado', '100', 'Monto Pagado', '', 'Estado', 'Rechazada', 'Motivo', 'Sin cobertura')), v_f1, null, null, null, null, false, 'malo.csv');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-34 · Cuatro filas malas se reportan con su número y qué corregir; la fila vacía se salta; la rechazada sin monto vale 0','ok',coalesce((jsonb_array_length(v_r->'errors') = 4 and (v_r->>'valid')::int = 1 and (v_r->>'blank_skipped')::int = 1 and (v_r->'errors'->0->'errors'->>0) like 'Monto pagado inválido: «abc»%' and (v_r->'errors'->1->'errors'->>0) like 'No tiene NSS ni número de autorización%' and (v_r->'errors'->2->'errors'->>0) like 'Fecha inválida%DD/MM/AAAA%' and (v_r->'errors'->3->'errors'->>0) like 'Monto pagado negativo%' and (v_r->'rows'->0->>'paid')::numeric = 0), false),'d',(v_r->'errors'::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.remittance_import(v_a, v_x1, jsonb_build_array(jsonb_build_object('No. Afiliado', '90000108', 'Autorización', 'AUT-2001', 'Fecha Servicio', v_d0, 'Monto Facturado', '100', 'Monto Pagado', 'abc', 'Estado', '', 'Motivo', '')), v_f1, null, 'REF-MALA', current_date, null, true, 'malo.csv');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-35 · Guardar con filas malas se rechaza y no guarda nada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-35 · Guardar con filas malas se rechaza y no guarda nada','ok',sqlerrm like 'Corrija las 1 fila(s) con error%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_import(v_a, v_x1, v_rows, v_f1, null, null, current_date, null, true, 'relacion_alfa.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-36 · Guardar sin referencia pide la referencia del pago de la ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-36 · Guardar sin referencia pide la referencia del pago de la ARS','ok',sqlerrm like 'Escriba la referencia del pago de la ARS%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_import(v_a, v_x1, v_rows, v_f1, null, 'REF-001', null, null, true, 'relacion_alfa.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-37 · Guardar sin fecha de pago pide la fecha','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-37 · Guardar sin fecha de pago pide la fecha','ok',sqlerrm like 'Escriba la fecha en que la ARS hizo el pago%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_import(v_a, v_x1, v_rows, v_f1, null, 'REF-001', current_date + 3, null, true, 'relacion_alfa.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-38 · La fecha de pago no puede ser futura','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-38 · La fecha de pago no puede ser futura','ok',sqlerrm like 'La fecha del pago no puede ser futura%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_import(v_a, v_x1, v_rows, v_f2, null, 'REF-001', current_date, null, true, 'relacion_alfa.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-39 · Un formato de otra ARS se rechaza y dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-39 · Un formato de otra ARS se rechaza y dice qué hacer','ok',sqlerrm like 'El formato elegido no es de esta ARS o de este cliente%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_import(v_a, v_x2, v_rows, v_f2, null, 'REF-001', current_date, null, false, 'relacion_alfa.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-40 · Si la columna del formato no está en el archivo, lo dice y sugiere revisar la ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-40 · Si la columna del formato no está en el archivo, lo dice y sugiere revisar la ARS','ok',sqlerrm like 'La columna «% no aparece en el archivo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_import(v_a, v_x1, (select jsonb_agg(jsonb_build_object('No. Afiliado', g::text)) from generate_series(1, 3001) g), v_f1, null, 'REF-001', current_date, null, false, 'grande.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-41 · Más de 3,000 filas se rechaza y pide dividir el archivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-41 · Más de 3,000 filas se rechaza y pide dividir el archivo','ok',sqlerrm like 'Máximo 3,000 filas por relación%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.remittance_import(v_a, v_x1, '[]'::jsonb, v_f1, null, 'REF-001', current_date, null, false, 'vacio.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-42 · Un archivo sin filas se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-42 · Un archivo sin filas se rechaza','ok',sqlerrm like 'El archivo no tiene filas%','d',left(sqlerrm,120)));
    end;
    v_r := public.remittance_import(v_a, v_x1, v_rows, v_f1, null, 'REF-ALFA-001', current_date - 2, 4200, true, 'relacion_alfa.xlsx');
    v_rem := (v_r->>'remittance')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-43 · Guardar crea la relación con folio REL-AAAA-NNNN, 5 líneas y la referencia','ok',coalesce((v_rem is not null and (select folio from public.payment_remittances where id = v_rem) like 'REL-%' and (select count(*) from public.payment_remittance_lines where remittance_id = v_rem) = 5 and (select reference from public.payment_remittances where id = v_rem) = 'REF-ALFA-001' and not (v_r->>'already_imported')::boolean), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-44 · La fila repetida queda como «duplicado» y nunca como pendiente de aplicar','ok',coalesce(((select state from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) = 'duplicado' and (select reason_text from public.payment_remittance_lines where remittance_id = v_rem and row_no = 5) like 'Fila repetida dentro del mismo archivo%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-45 · Los datos quedan limpios en la línea: NSS 90000101 y el original con guion','ok',coalesce(((select nss from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = '90000101' and (select nss_raw from public.payment_remittance_lines where remittance_id = v_rem and row_no = 1) = '900-00101' and (select paid_amount from public.payment_remittance_lines where remittance_id = v_rem and row_no = 3) = 700), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-46 · Usar el formato sube su contador de usos','ok',coalesce(((select used_count from public.payment_import_formats where id = v_f1) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_import(v_a, v_x1, v_rows, v_f1, null, 'REF-OTRA', current_date - 1, null, true, 'relacion_alfa_copia.xlsx');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-47 · IDEMPOTENTE: reimportar el mismo archivo no duplica nada y avisa cuál relación ya lo tiene','ok',coalesce(((v_r->>'already_imported')::boolean and (v_r->>'existing_folio') = (select folio from public.payment_remittances where id = v_rem) and (select count(*) from public.payment_remittances where organization_id = v_a) = 1 and (select count(*) from public.payment_remittance_lines where organization_id = v_a) = 5), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-48 · Reimportar no sube otra vez el contador del formato','ok',coalesce(((select used_count from public.payment_import_formats where id = v_f1) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.remittance_import(v_a, v_x1, jsonb_build_array(
      jsonb_build_object('No. Afiliado', '900-00101', 'Autorización', 'AUT-1001', 'Fecha Servicio', v_d0, 'Monto Facturado', '1,500.00', 'Monto Pagado', '1,500.00', 'Estado', 'Pagada', 'Motivo', ''),
      jsonb_build_object('No. Afiliado', '90000105', 'Autorización', 'AUT-1005', 'Fecha Servicio', v_d2, 'Monto Facturado', '500', 'Monto Pagado', '500', 'Estado', 'Pagada', 'Motivo', '')), v_f1, null, 'REF-ALFA-002', current_date - 1, null, true, 'relacion_alfa_2.xlsx');
    v_rem2 := (v_r->>'remittance')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-49 · Una fila que ya estaba en otra relación de la misma ARS se guarda como duplicado y dice en cuál','ok',coalesce(((v_r->>'duplicates_previous')::int = 1 and (select state from public.payment_remittance_lines where remittance_id = v_rem2 and row_no = 1) = 'duplicado' and (select reason_text from public.payment_remittance_lines where remittance_id = v_rem2 and row_no = 1) like 'Ya estaba en la relación REL-%' and (select state from public.payment_remittance_lines where remittance_id = v_rem2 and row_no = 2) <> 'duplicado'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.remittance_import(v_a, v_x1, jsonb_build_array(jsonb_build_object('No. Afiliado', '90000102', 'Autorización', 'AUT-1002', 'Fecha Servicio', v_d0, 'Monto Facturado', '2000', 'Monto Pagado', '2000', 'Estado', '', 'Motivo', '')), v_f1, null, 'ref-alfa-001', current_date, null, true, 'otra.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-50 · La misma referencia con contenido distinto se rechaza y dice cómo corregir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-50 · La misma referencia con contenido distinto se rechaza y dice cómo corregir','ok',sqlerrm like 'Ya existe la relación REL-%con esa referencia pero con contenido distinto%','d',left(sqlerrm,120)));
    end;
    v_r := public.remittance_list(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-51 · La lista muestra las 2 relaciones con sus conteos por estado y el total pagado','ok',coalesce((jsonb_array_length(v_r) = 2 and (select (x->>'total_paid')::numeric from jsonb_array_elements(v_r) x where x->>'reference' = 'REF-ALFA-001') = 4200 and (select (x->'counts'->>'duplicado')::int from jsonb_array_elements(v_r) x where x->>'reference' = 'REF-ALFA-001') = 1), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_annul(v_rem2, 'Intento del médico');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-52 · ATAQUE: el Médico no anula relaciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-52 · ATAQUE: el Médico no anula relaciones','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_annul(v_rem2, 'no');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-53 · Anular exige el motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-53 · Anular exige el motivo','ok',sqlerrm like 'Escriba el motivo de la anulación%','d',left(sqlerrm,120)));
    end;
    perform public.remittance_annul(v_rem2, 'Archivo cargado por error de la prueba');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-54 · Anular deja la relación anulada con su motivo','ok',coalesce(((select status from public.payment_remittances where id = v_rem2) = 'anulada' and (select annulled_reason from public.payment_remittances where id = v_rem2) like 'Archivo cargado%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.remittance_annul(v_rem2, 'Otra vez el mismo motivo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-55 · Anular dos veces se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-55 · Anular dos veces se rechaza','ok',sqlerrm like 'Esa relación ya está anulada%','d',left(sqlerrm,120)));
    end;
    v_r := public.remittance_import(v_a, v_x1, jsonb_build_array(jsonb_build_object('No. Afiliado', '90000105', 'Autorización', 'AUT-1005', 'Fecha Servicio', v_d2, 'Monto Facturado', '500', 'Monto Pagado', '500', 'Estado', 'Pagada', 'Motivo', '')), v_f1, null, 'REF-ALFA-002', current_date - 1, null, true, 'relacion_alfa_2.xlsx');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-56 · Después de anular, el mismo archivo y la misma referencia se pueden volver a cargar','ok',coalesce((not (v_r->>'already_imported')::boolean and (v_r->>'remittance') is not null), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_list(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-57 · ATAQUE: el Médico de otro consultorio no ve las relaciones del consultorio A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-57 · ATAQUE: el Médico de otro consultorio no ve las relaciones del consultorio A','ok',sqlerrm like 'Sin acceso a las relaciones de pago de este cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.remittance_import(v_a, v_x2, jsonb_build_array(
      jsonb_build_object('NSS', '80000201', 'No. Autorización', 'BET-2001', 'Fecha', v_d0, 'Valor Reclamado', '1.000,00', 'Valor Aprobado', '1.000,00', 'Observación', ''),
      jsonb_build_object('NSS', '80000202', 'No. Autorización', 'BET-2002', 'Fecha', v_d0, 'Valor Reclamado', '2500,00', 'Valor Aprobado', '2500,00', 'Observación', ''),
      jsonb_build_object('NSS', '800-00203', 'No. Autorización', 'BET-2003', 'Fecha', v_d1, 'Valor Reclamado', '4.000,00', 'Valor Aprobado', '4.000,00', 'Observación', '')), v_f2, null, 'REF-BETA-001', current_date - 1, null, true, 'beta.xlsx');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-58 · Glosas sí importa una relación (otra ARS, otro formato, coma decimal)','ok',coalesce(((v_r->>'remittance') is not null and (v_r->>'total_paid')::numeric = 7500), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.remittance_import(v_a, v_x3, jsonb_build_array(
      jsonb_build_object('Afiliado', '70000301', 'Fecha de servicio', v_d0, 'Pagado', '750'),
      jsonb_build_object('Afiliado', '70000302', 'Fecha de servicio', v_d1, 'Pagado', '1,250.00')), null, '{"nss":"Afiliado","fecha":"Fecha de servicio","pagado":"Pagado"}'::jsonb, 'REF-GAMMA-001', current_date - 1, null, true, 'gamma.csv');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-59 · Tercera ARS: formato mínimo (sin autorización ni monto facturado) también se importa','ok',coalesce(((v_r->>'remittance') is not null and (v_r->>'total_paid')::numeric = 2000), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_import(v_a, v_x1, v_rows, null, '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb, 'REF-X', current_date, null, true, 'x.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-60 · ATAQUE: el Médico B no importa relaciones en el cliente A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-60 · ATAQUE: el Médico B no importa relaciones en el cliente A','ok',sqlerrm like 'Las relaciones de pago las gestiona el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    insert into public.organization_plans (organization_id, plan_code, starts_on, status) values (v_b, 'saas_basico', current_date, 'activo');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.remittance_import(v_b, v_x1, v_rows, null, '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb, 'REF-PLAN', current_date, null, false, 'x.xlsx');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-61 · Con el bloqueo por plan encendido, un cliente sin plan que incluya la conciliación no importa y se le dice cómo mejorarlo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-61 · Con el bloqueo por plan encendido, un cliente sin plan que incluya la conciliación no importa y se le dice cómo mejorarlo','ok',sqlerrm like 'El plan de este cliente no incluye la conciliación de pagos%mejorar el plan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.app_settings set enforce_plans = false where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.remittance_import(v_b, v_x1, v_rows, null, '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb, null, null, null, false, 'x.xlsx');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-62 · Con el bloqueo apagado el mismo cliente sí pasa el control del plan','ok',coalesce(((v_r->>'valid')::int = 5), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.remittance_import(v_a, v_x1, v_rows, null, '{"nss":"No. Afiliado","autorizacion":"Autorización","fecha":"Fecha Servicio","facturado":"Monto Facturado","pagado":"Monto Pagado","estado":"Estado","motivo":"Motivo"}'::jsonb, null, null, null, false, 'adhoc.xlsx');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-63 · Sin formato guardado, el mapeo se puede enviar al revisar (para probarlo antes de guardarlo)','ok',coalesce(((v_r->>'valid')::int = 5), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RP-64 · Las cargas y los formatos quedan en la bitácora de auditoría','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'payment_remittances' and operation = 'INSERT' and organization_id = v_a) and exists (select 1 from public.audit_log where table_name = 'payment_import_formats' and operation = 'INSERT' and organization_id = v_a)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
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
revoke all on function app.qa_run_tests_relaciones_pago() from public, anon, authenticated;
