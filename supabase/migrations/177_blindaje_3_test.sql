-- 177 · Suite de la 176 (blindaje de seguridad 3: SEG-21, 24, 25, 29, 34, 35 y 36). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_blindaje_3();
create or replace function app.qa_run_tests_blindaje_3()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_flag boolean; v_cap jsonb;
  v_org constant uuid := '17600000-0000-4000-8000-000000000001'; v_orgb constant uuid := '17600000-0000-4000-8000-000000000002';
  v_pa1 constant uuid := '17600000-0000-4000-8000-000000000003'; v_pb constant uuid := '17600000-0000-4000-8000-000000000005';
  v_pat1 uuid; v_pat2 uuid; v_patb uuid; v_ars uuid; v_proc uuid; v_per date; v_s1 uuid; v_sb uuid; v_l1 uuid; v_leg uuid; v_ins1 uuid;
  v_cen1 uuid; v_cen2 uuid; v_doca uuid; v_docb uuid; v_tok1 text; v_tok2 text; v_tok3 text; v_tok4 text;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values
      ('17600000-0000-4000-8000-000000000011'::uuid,'qa.b3.sa@sofa.test','x'),('17600000-0000-4000-8000-000000000012'::uuid,'qa.b3.adm@sofa.test','x'),('17600000-0000-4000-8000-000000000013'::uuid,'qa.b3.bil@sofa.test','x'),('17600000-0000-4000-8000-000000000014'::uuid,'qa.b3.ops@sofa.test','x'),
      ('17600000-0000-4000-8000-000000000021'::uuid,'qa.b3.med1@sofa.test','x'),('17600000-0000-4000-8000-000000000023'::uuid,'qa.b3.sec@sofa.test','x'),('17600000-0000-4000-8000-000000000024'::uuid,'qa.b3.medb@sofa.test','x'),('17600000-0000-4000-8000-000000000031'::uuid,'qa.b3.existe@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.b3.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA B3 Centro Médico', '00000000176', 'Médico independiente', 'activo', current_date - 90, '8095550176'),
           (v_orgb, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA B3 Otro Consultorio', '00000000177', 'Médico independiente', 'activo', current_date - 90, '8095550177');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_pa1, v_org, 'Dr. Uno QA', 'Cardiología'), (v_pb, v_orgb, 'Dr. B QA', 'Ortopedia');
    insert into public.organization_users (organization_id, user_id, role_code) values
      ('00000000-0000-4000-8000-000000000001'::uuid, '17600000-0000-4000-8000-000000000011'::uuid, 'super_admin'), ('00000000-0000-4000-8000-000000000001'::uuid, '17600000-0000-4000-8000-000000000012'::uuid, 'admin'),
      ('00000000-0000-4000-8000-000000000001'::uuid, '17600000-0000-4000-8000-000000000013'::uuid, 'billing'), ('00000000-0000-4000-8000-000000000001'::uuid, '17600000-0000-4000-8000-000000000014'::uuid, 'operations'),
      (v_org, '17600000-0000-4000-8000-000000000021'::uuid, 'client'), (v_org, '17600000-0000-4000-8000-000000000023'::uuid, 'capturer'), (v_orgb, '17600000-0000-4000-8000-000000000024'::uuid, 'client');
    insert into public.clinical_settings (organization_id, mode) values (v_org, 'prueba');
    insert into public.patients (organization_id, full_name, doc_number, phone) values (v_org, 'Paciente Uno QA', '40200001761', '8095550176') returning id into v_pat1;
    insert into public.patients (organization_id, full_name, doc_number, phone) values (v_org, 'Paciente Dos QA', '40200001762', '8095550177') returning id into v_pat2;
    insert into public.patients (organization_id, full_name, doc_number) values (v_orgb, 'Paciente B QA', '40200001763') returning id into v_patb;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_b3_ars', 'ARS QA Blindaje 3', 'Contributivo', true) returning id into v_ars;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    v_per := date_trunc('month', current_date - 120)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_pa1, v_ars, v_per, 1, 'borrador') returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_orgb, v_pb, v_ars, v_per, 1, 'borrador') returning id into v_sb;
    insert into public.health_centers (organization_id, name) values (v_org, 'Centro QA B3 Uno') returning id into v_cen1;
    insert into public.health_centers (organization_id, name) values (v_org, 'Centro QA B3 Dos') returning id into v_cen2;
    insert into public.provider_centers (provider_id, center_id) values (v_pa1, v_cen1);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount, patient_id)
    values (v_s1, v_org, v_per + 3, 'Paciente Uno QA', '900000001', 'AUT-QA-1', v_proc, 1, 1230, v_pat1) returning id into v_l1;
    insert into public.documents (organization_id, entity_type, entity_id, storage_path, file_name, mime_type, size_bytes)
    values (v_org, 'submission', v_s1, v_org::text || '/' || v_s1::text || '/acuse-qa.pdf', 'acuse-qa.pdf', 'application/pdf', 1000) returning id into v_doca;
    insert into public.documents (organization_id, entity_type, entity_id, storage_path, file_name, mime_type, size_bytes)
    values (v_orgb, 'submission', v_sb, v_orgb::text || '/' || v_sb::text || '/acuse-ajeno.pdf', 'acuse-ajeno.pdf', 'application/pdf', 1000) returning id into v_docb;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000024', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform * from public.onboarding_summary(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-01 · SEG-24 · ATAQUE: el Médico de otro consultorio no ve el avance de incorporación ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-01 · SEG-24 · ATAQUE: el Médico de otro consultorio no ve el avance de incorporación ajeno','ok',sqlerrm like 'Sin acceso al avance%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-02 · SEG-24 · Uso legítimo: el Médico ve el avance de su propio consultorio','ok',coalesce(((select total from public.onboarding_summary(v_org)) = 9), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-02 · SEG-24 · Uso legítimo: el Médico ve el avance de su propio consultorio','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-03 · SEG-24 · Uso legítimo: el personal de SOFA ve el avance de un cliente','ok',coalesce(((select total from public.onboarding_summary(v_org)) = 9), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-03 · SEG-24 · Uso legítimo: el personal de SOFA ve el avance de un cliente','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000023', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-04 · SEG-24 · Uso legítimo: la Secretaria ve el avance de su consultorio','ok',coalesce(((select total from public.onboarding_summary(v_org)) = 9), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-04 · SEG-24 · Uso legítimo: la Secretaria ve el avance de su consultorio','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform * from public.onboarding_summary('17600000-0000-4000-8000-0000000000ff'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-05 · SEG-24 · ATAQUE: un identificador inventado tampoco devuelve nada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-05 · SEG-24 · ATAQUE: un identificador inventado tampoco devuelve nada','ok',sqlerrm like 'Sin acceso al avance%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.request_user(v_org, 'qa.b3.existe@sofa.test', 'Persona Con Cuenta', 'capturer', array[v_pa1]);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-06 · SEG-25 · Un correo que ya tiene cuenta recibe la misma respuesta que uno nuevo','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-06 · SEG-25 · Un correo que ya tiene cuenta recibe la misma respuesta que uno nuevo','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-07 · SEG-25 · Ese correo no genera una solicitud (no se le da acceso ni se revela nada)','ok',coalesce((not exists (select 1 from public.user_requests where lower(email) = 'qa.b3.existe@sofa.test')), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-07 · SEG-25 · Ese correo no genera una solicitud (no se le da acceso ni se revela nada)','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-08 · SEG-25 · SOFA recibe una tarea para revisar el caso a mano','ok',coalesce((exists (select 1 from public.tasks where organization_id = v_org and title like 'Revisar solicitud de usuario · qa.b3.existe@sofa.test%')), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-08 · SEG-25 · SOFA recibe una tarea para revisar el caso a mano','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_x := to_jsonb(public.request_user(v_org, 'qa.b3.nuevo@sofa.test', 'Persona Nueva Qa', 'capturer', array[v_pa1]));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-09 · SEG-25 · Uso legítimo: un correo nuevo sí crea la solicitud','ok',coalesce((v_x is not null and exists (select 1 from public.user_requests where lower(email) = 'qa.b3.nuevo@sofa.test' and status = 'pendiente' and organization_id = v_org)), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-09 · SEG-25 · Uso legítimo: un correo nuevo sí crea la solicitud','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.request_user(v_org, 'qa.b3.nuevo@sofa.test', 'Persona Nueva Qa', 'capturer', array[v_pa1]);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-10 · SEG-25 · Una solicitud pendiente del propio consultorio sigue avisando','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-10 · SEG-25 · Una solicitud pendiente del propio consultorio sigue avisando','ok',sqlerrm like 'Ya hay una solicitud pendiente%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000024', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform public.request_user(v_orgb, 'qa.b3.cruzado@sofa.test', 'Persona Cruzada Qa', 'client');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.request_user(v_org, 'qa.b3.cruzado@sofa.test', 'Persona Cruzada Qa', 'client');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-11 · SEG-25 · Una solicitud pendiente de OTRO consultorio no se revela','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-11 · SEG-25 · Una solicitud pendiente de OTRO consultorio no se revela','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-12 · SEG-25 · Y no se duplica la solicitud ajena (queda una sola pendiente, la del otro consultorio)','ok',coalesce(((select count(*) from public.user_requests where lower(email) = 'qa.b3.cruzado@sofa.test' and status = 'pendiente') = 1 and (select organization_id from public.user_requests where lower(email) = 'qa.b3.cruzado@sofa.test' and status = 'pendiente') = v_orgb), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-12 · SEG-25 · Y no se duplica la solicitud ajena (queda una sola pendiente, la del otro consultorio)','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000024', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.request_user(v_org, 'qa.b3.otro@sofa.test', 'Persona Otra Qa', 'capturer', array[v_pa1]);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-13 · SEG-25 · ATAQUE: pedir un usuario para un consultorio ajeno sigue prohibido','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-13 · SEG-25 · ATAQUE: pedir un usuario para un consultorio ajeno sigue prohibido','ok',sqlerrm like 'Solo el Médico o el Centro%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform target_mrr from public.app_settings;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-14 · SEG-29 · ATAQUE: el Médico no lee la meta de ingresos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-14 · SEG-29 · ATAQUE: el Médico no lee la meta de ingresos','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,160)));
    end;
    begin
      perform staff_hour_cost from public.app_settings;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-15 · SEG-29 · ATAQUE: el Médico no lee el costo por hora del personal','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-15 · SEG-29 · ATAQUE: el Médico no lee el costo por hora del personal','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,160)));
    end;
    begin
      perform sofa_bank_account from public.app_settings;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-16 · SEG-29 · ATAQUE: el Médico no lee la cuenta bancaria de SOFA','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-16 · SEG-29 · ATAQUE: el Médico no lee la cuenta bancaria de SOFA','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,160)));
    end;
    begin
      perform * from public.app_settings;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-17 · SEG-29 · ATAQUE: select * de app_settings queda cerrado para el cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-17 · SEG-29 · ATAQUE: select * de app_settings queda cerrado para el cliente','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,160)));
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-18 · SEG-29 · Uso legítimo: el cliente sigue leyendo los plazos que usan sus pantallas','ok',coalesce(((select payment_term_days from public.app_settings limit 1) is not null), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-18 · SEG-29 · Uso legítimo: el cliente sigue leyendo los plazos que usan sus pantallas','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform payment_term_days from public.app_settings;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-19 · SEG-29 · ATAQUE: sin sesión no se lee app_settings','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-19 · SEG-29 · ATAQUE: sin sesión no se lee app_settings','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-20 · SEG-29 · El Médico no recibe filas de app_settings_staff()','ok',coalesce(((select count(*) from public.app_settings_staff()) = 0), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-20 · SEG-29 · El Médico no recibe filas de app_settings_staff()','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-21 · SEG-29 · Uso legítimo: el Administrador de SOFA lee la fila completa','ok',coalesce(((select target_mrr from public.app_settings_staff() limit 1) is not null), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-21 · SEG-29 · Uso legítimo: el Administrador de SOFA lee la fila completa','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-22 · SEG-29 · app_settings_public() trae lo necesario y no las columnas sensibles','ok',coalesce(((public.app_settings_public() ? 'glosa_norm_reference') and not (public.app_settings_public() ? 'target_mrr') and not (public.app_settings_public() ? 'sofa_bank_account') and not (public.app_settings_public() ? 'staff_hour_cost')), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-22 · SEG-29 · app_settings_public() trae lo necesario y no las columnas sensibles','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-23 · SEG-29 · Las vistas con permisos de quien consulta siguen funcionando para el cliente','ok',coalesce(((select count(*) from public.v_submission_balance) >= 0), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-23 · SEG-29 · Las vistas con permisos de quien consulta siguen funcionando para el cliente','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.fiscal_check(v_s1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-24 · SEG-29 · Las funciones que leen plazos (fiscal_check) siguen funcionando para el cliente','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-24 · SEG-29 · Las funciones que leen plazos (fiscal_check) siguen funcionando para el cliente','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.app_settings set staff_hour_cost = 12.5 where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-25 · SEG-29 · Uso legítimo: el Super Admin guarda un parámetro','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-25 · SEG-29 · Uso legítimo: el Super Admin guarda un parámetro','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-26 · SEG-29 · Sin sesión no se ejecutan las funciones de configuración nuevas','ok',coalesce((not has_function_privilege('anon', 'public.app_settings_staff()', 'execute') and not has_function_privilege('anon', 'public.app_settings_public()', 'execute') and not has_function_privilege('anon', 'public.password_reset_info(uuid)', 'execute') and not has_function_privilege('anon', 'public.record_recovery_link(uuid,text)', 'execute')), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-26 · SEG-29 · Sin sesión no se ejecutan las funciones de configuración nuevas','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_per + 9, 'Paciente Qa Cant', '900000099', null, v_proc, 2.5, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-27 · SEG-34 · ATAQUE: cantidad con decimales en inserción directa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-27 · SEG-34 · ATAQUE: cantidad con decimales en inserción directa','ok',sqlerrm like 'La cantidad debe ser un número entero%','d',left(sqlerrm,160)));
    end;
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_per + 9, 'Paciente Qa Cant', '900000099', null, v_proc, 1000, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-28 · SEG-34 · ATAQUE: cantidad por encima del tope (1000)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-28 · SEG-34 · ATAQUE: cantidad por encima del tope (1000)','ok',sqlerrm like 'La cantidad debe ser un número entero%','d',left(sqlerrm,160)));
    end;
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_per + 9, 'Paciente Qa Cant', '900000099', null, v_proc, 0, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-29 · SEG-34 · ATAQUE: cantidad cero','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-29 · SEG-34 · ATAQUE: cantidad cero','ok',sqlerrm like '%','d',left(sqlerrm,160)));
    end;
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_per + 10, 'Paciente Qa Cant', '900000011', null, v_proc, 3, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-30 · SEG-34 · Uso legítimo: cantidad entera (3) en inserción directa','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-30 · SEG-34 · Uso legítimo: cantidad entera (3) en inserción directa','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_per + 11, 'Paciente Qa Cant', '900000012', null, v_proc, 999, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-31 · SEG-34 · Uso legítimo: el tope (999) se acepta','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-31 · SEG-34 · Uso legítimo: el tope (999) se acepta','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      update public.service_lines set quantity = 4.5 where id = v_l1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-32 · SEG-34 · ATAQUE: cambiar la cantidad existente a un decimal','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-32 · SEG-34 · ATAQUE: cambiar la cantidad existente a un decimal','ok',sqlerrm like 'La cantidad debe ser un número entero%','d',left(sqlerrm,160)));
    end;
    begin
      update public.service_lines set quantity = 5 where id = v_l1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-33 · SEG-34 · Uso legítimo: cambiar la cantidad existente a un entero','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-33 · SEG-34 · Uso legítimo: cambiar la cantidad existente a un entero','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_per + 12, 'Paciente Qa Cant', '900000013', null, v_proc, 2.5, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-34 · SEG-34 · También sin sesión (servicio) la cantidad con decimales se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-34 · SEG-34 · También sin sesión (servicio) la cantidad con decimales se rechaza','ok',sqlerrm like 'La cantidad debe ser un número entero%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    alter table public.service_lines disable trigger service_lines_guard;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_org, v_per + 13, 'Paciente Legado Qa', '900000014', v_proc, 2.5, 100) returning id into v_leg;
    alter table public.service_lines enable trigger service_lines_guard;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.service_lines set notes = 'nota qa' where id = v_leg;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-35 · SEG-34 · Uso legítimo: una línea antigua con decimales se sigue editando si no se toca la cantidad','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-35 · SEG-34 · Uso legítimo: una línea antigua con decimales se sigue editando si no se toca la cantidad','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.capture_claim(v_pa1, v_ars, v_proc, date_trunc('month', current_date)::date, 'Paciente Cap Qa', 'NSS-B3-1', 'AUT-B3-1', null, 100, 2.5, null, null, null, null, 'pendiente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-36 · SEG-34 · ATAQUE: capture_claim con cantidad decimal','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-36 · SEG-34 · ATAQUE: capture_claim con cantidad decimal','ok',sqlerrm like 'La cantidad debe ser un número entero%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.capture_claim(v_pa1, v_ars, v_proc, date_trunc('month', current_date)::date, 'Paciente Cap Qa', 'NSS-B3-2', 'AUT-B3-2', null, 100, 1000, null, null, null, null, 'pendiente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-37 · SEG-34 · ATAQUE: capture_claim con cantidad sobre el tope','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-37 · SEG-34 · ATAQUE: capture_claim con cantidad sobre el tope','ok',sqlerrm like 'La cantidad debe ser un número entero%','d',left(sqlerrm,160)));
    end;
    v_cap := public.capture_claim(v_pa1, v_ars, v_proc, date_trunc('month', current_date)::date, 'Paciente Cap Qa', 'NSS-B3-3', 'AUT-B3-3', null, 100, 2, null, null, null, null, 'pendiente');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-38 · SEG-34 · Uso legítimo: capture_claim con cantidad entera registra la reclamación como captura rápida','ok',coalesce(((select captured_via from public.service_lines where id = (v_cap->>'id')::uuid) = 'captura_rapida'), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-38 · SEG-34 · Uso legítimo: capture_claim con cantidad entera registra la reclamación como captura rápida','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-39 · SEG-34 · El permiso interno de captura no queda encendido después de capture_claim','ok',coalesce((coalesce(current_setting('app.claim_capture', true), '') = ''), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-39 · SEG-34 · El permiso interno de captura no queda encendido después de capture_claim','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.capture_claim(v_pa1, v_ars, v_proc, date_trunc('month', current_date)::date, 'Paciente Cap Qa', 'NSS-B3-3', 'AUT-B3-3', null, 100, 1, null, null, null, null, 'pendiente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-40 · SEG-34 · capture_claim sigue bloqueando el duplicado al Médico (control propio intacto)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-40 · SEG-34 · capture_claim sigue bloqueando el duplicado al Médico (control propio intacto)','ok',sqlerrm like 'Posible reclamación duplicada%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-41 · SEG-34 · Importación Excel (vista previa): la cantidad decimal se rechaza con mensaje claro','ok',coalesce(((public.import_claims(jsonb_build_array(jsonb_build_object('medico','Dr. Uno QA','ars','qa_b3_ars','servicio',(select internal_code from public.procedures where id = v_proc),'fecha',to_char(current_date,'DD/MM/YYYY'),'paciente','Paciente Excel Qa','nss','NSS-B3-X1','autorizacion','AUT-B3-X1','cantidad','2.5')), false)::text like '%número entero entre 1 y 999%')), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-41 · SEG-34 · Importación Excel (vista previa): la cantidad decimal se rechaza con mensaje claro','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-42 · SEG-34 · Importación Excel: la cantidad entera pasa la vista previa','ok',coalesce((((public.import_claims(jsonb_build_array(jsonb_build_object('medico','Dr. Uno QA','ars','qa_b3_ars','servicio',(select internal_code from public.procedures where id = v_proc),'fecha',to_char(current_date,'DD/MM/YYYY'),'paciente','Paciente Excel Qa','nss','NSS-B3-X2','autorizacion','AUT-B3-X2','cantidad','3')), false)->>'valid')::int = 1)), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-42 · SEG-34 · Importación Excel: la cantidad entera pasa la vista previa','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-43 · SEG-34 · Importación Excel: confirmar la carga crea la reclamación por capture_claim','ok',coalesce((((public.import_claims(jsonb_build_array(jsonb_build_object('medico','Dr. Uno QA','ars','qa_b3_ars','servicio',(select internal_code from public.procedures where id = v_proc),'fecha',to_char(current_date,'DD/MM/YYYY'),'paciente','Paciente Excel Qa','nss','NSS-B3-X3','autorizacion','AUT-B3-X3','cantidad','3','monto','100')), true)->>'imported')::int = 1)), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-43 · SEG-34 · Importación Excel: confirmar la carga crea la reclamación por capture_claim','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-44 · SEG-34 · Carga masiva por import_service_lines: cantidad decimal se rechaza fila por fila y la entera se inserta','ok',coalesce((((public.import_service_lines(v_s1, jsonb_build_array(jsonb_build_object('fecha',to_char(v_per + 14,'DD/MM/YYYY'),'afiliado','Afiliado Masivo Uno','nss','900000021','codigo',(select internal_code from public.procedures where id = v_proc),'cantidad','2.5','monto','100'),jsonb_build_object('fecha',to_char(v_per + 15,'DD/MM/YYYY'),'afiliado','Afiliado Masivo Dos','nss','900000022','codigo',(select internal_code from public.procedures where id = v_proc),'cantidad','2','monto','100')), true)) @> '{"inserted":1,"errors":1}'::jsonb)), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-44 · SEG-34 · Carga masiva por import_service_lines: cantidad decimal se rechaza fila por fila y la entera se inserta','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount, captured_via) values (v_s1, v_org, v_per + 16, 'Paciente Qa Cant', '900000031', null, v_proc, 1, 100, 'captura_rapida') returning id into v_ins1;
    exception when others then null;
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-45 · SEG-34 · Inserción directa: el origen «captura_rapida» queda reservado (se guarda como manual)','ok',coalesce(((select captured_via from public.service_lines where id = v_ins1) = 'manual'), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-45 · SEG-34 · Inserción directa: el origen «captura_rapida» queda reservado (se guarda como manual)','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_per + 17, 'Paciente Qa Cant', '900000032', 'AUT-QA-1', v_proc, 1, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-46 · SEG-34 · ATAQUE: inserción directa duplicada por número de autorización','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-46 · SEG-34 · ATAQUE: inserción directa duplicada por número de autorización','ok',sqlerrm like 'Posible reclamación duplicada%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000013', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_per + 17, 'Paciente Qa Cant', '900000033', 'AUT-QA-1', v_proc, 1, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-47 · SEG-34 · Uso legítimo: Facturación puede registrar un duplicado confirmado','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-47 · SEG-34 · Uso legítimo: Facturación puede registrar un duplicado confirmado','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount, center_id) values (v_s1, v_org, v_per + 18, 'Paciente Qa Cant', '900000034', null, v_proc, 1, 100, v_cen2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-48 · SEG-34 · ATAQUE: inserción directa con un centro que no es de ese médico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-48 · SEG-34 · ATAQUE: inserción directa con un centro que no es de ese médico','ok',sqlerrm like 'El centro de salud elegido no está asignado%','d',left(sqlerrm,160)));
    end;
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount, center_id) values (v_s1, v_org, v_per + 19, 'Paciente Qa Cant', '900000035', null, v_proc, 1, 100, v_cen1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-49 · SEG-34 · Uso legítimo: inserción directa con un centro asignado al médico','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-49 · SEG-34 · Uso legítimo: inserción directa con un centro asignado al médico','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_per + 20, 'Paciente Qa Cant', 'ab', null, v_proc, 1, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-50 · SEG-34 · ATAQUE: inserción directa con NSS de 2 caracteres','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-50 · SEG-34 · ATAQUE: inserción directa con NSS de 2 caracteres','ok',sqlerrm like 'El NSS o número de afiliado%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_tok1 := (public.portal_link_create(v_pat1, 30, false))->>'token';
    v_tok2 := (public.portal_link_create(v_pat2, 30, false))->>'token';
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-51 · SEG-35 · Uso legítimo: con paciente y consultorio activos el portal abre','ok',coalesce(((public.portal_view(v_tok1)->'clinic'->>'name') is not null), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-51 · SEG-35 · Uso legítimo: con paciente y consultorio activos el portal abre','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.patients set is_active = false where id = v_pat1;
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.portal_view(v_tok1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-52 · SEG-35 · ATAQUE: con el paciente desactivado el enlace deja de abrir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-52 · SEG-35 · ATAQUE: con el paciente desactivado el enlace deja de abrir','ok',sqlerrm like 'Este enlace%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-53 · SEG-35 · Al desactivar al paciente sus enlaces quedan anulados','ok',coalesce(((select revoked_at is not null from public.patient_portal_links where token_hash = app.sha256(v_tok1))), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-53 · SEG-35 · Al desactivar al paciente sus enlaces quedan anulados','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.portal_appointment_action(v_tok1, gen_random_uuid(), 'confirmar', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-54 · SEG-35 · El enlace anulado tampoco permite pedir cambios de cita','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-54 · SEG-35 · El enlace anulado tampoco permite pedir cambios de cita','ok',sqlerrm like 'Este enlace%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.portal_link_create(v_pat1, 30, false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-55 · SEG-35 · ATAQUE: no se crea un enlace nuevo para un paciente desactivado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-55 · SEG-35 · ATAQUE: no se crea un enlace nuevo para un paciente desactivado','ok',sqlerrm like 'El paciente está desactivado%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.patients set is_active = true where id = v_pat1;
    v_x := null;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_tok3 := (public.portal_link_create(v_pat1, 30, false))->>'token';
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-56 · SEG-35 · Uso legítimo: reactivado el paciente, un enlace nuevo funciona (el viejo sigue anulado)','ok',coalesce(((public.portal_view(v_tok3)->'clinic'->>'name') is not null), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-56 · SEG-35 · Uso legítimo: reactivado el paciente, un enlace nuevo funciona (el viejo sigue anulado)','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    alter table public.patients disable trigger patients_portal_revoke;
    update public.patients set is_active = false where id = v_pat1;
    alter table public.patients enable trigger patients_portal_revoke;
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.portal_view(v_tok3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-57 · SEG-35 · Aunque el disparador falle, el portal rechaza al paciente desactivado (segunda barrera)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-57 · SEG-35 · Aunque el disparador falle, el portal rechaza al paciente desactivado (segunda barrera)','ok',sqlerrm like 'Este enlace%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.patients set is_active = true where id = v_pat1;
    update public.organizations set status = 'suspendido' where id = v_org;
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.portal_view(v_tok2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-58 · SEG-35 · ATAQUE: con el consultorio suspendido el enlace deja de abrir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-58 · SEG-35 · ATAQUE: con el consultorio suspendido el enlace deja de abrir','ok',sqlerrm like 'Este enlace%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-59 · SEG-35 · Al suspender el consultorio todos sus enlaces vigentes quedan anulados','ok',coalesce((not exists (select 1 from public.patient_portal_links where organization_id = v_org and revoked_at is null)), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-59 · SEG-35 · Al suspender el consultorio todos sus enlaces vigentes quedan anulados','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.organizations set status = 'activo' where id = v_org;
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.portal_view(v_tok2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-60 · SEG-35 · Reactivar el consultorio no revive los enlaces anulados','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-60 · SEG-35 · Reactivar el consultorio no revive los enlaces anulados','ok',sqlerrm like 'Este enlace%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_tok4 := (public.portal_link_create(v_pat2, 30, false))->>'token';
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-61 · SEG-35 · Uso legítimo: con el consultorio activo otra vez, un enlace nuevo abre','ok',coalesce(((public.portal_view(v_tok4)->'clinic'->>'name') is not null), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-61 · SEG-35 · Uso legítimo: con el consultorio activo otra vez, un enlace nuevo abre','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.change_submission_status(v_s1, 'radicada', null, null, null, 'REC-QA-1', 'fisico', null, v_docb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-62 · SEG-36 · ATAQUE: un acuse que es documento de otro cliente se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-62 · SEG-36 · ATAQUE: un acuse que es documento de otro cliente se rechaza','ok',sqlerrm like 'El documento de acuse no pertenece a este cliente%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.change_submission_status(v_s1, 'radicada', null, null, null, 'REC-QA-1', 'fisico', null, gen_random_uuid());
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-63 · SEG-36 · ATAQUE: un acuse inexistente también se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-63 · SEG-36 · ATAQUE: un acuse inexistente también se rechaza','ok',sqlerrm like 'El documento de acuse no pertenece a este cliente%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.change_submission_status(v_s1, 'radicada', null, null, null, 'REC-QA-1', 'fisico', null, v_doca);
      v_flag := true;
    exception when others then
      v_flag := sqlerrm not like 'El documento de acuse no pertenece%';
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-64 · SEG-36 · Uso legítimo: el acuse del propio cliente pasa esta regla (el resto de la radicación se valida aparte)','ok',coalesce((v_flag), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-64 · SEG-36 · Uso legítimo: el acuse del propio cliente pasa esta regla (el resto de la radicación se valida aparte)','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-65 · SEG-21 · El Super Admin ve que el Médico tiene historia clínica activa','ok',coalesce(((public.password_reset_info(('17600000-0000-4000-8000-000000000021')::uuid)->>'clinical')::boolean), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-65 · SEG-21 · El Super Admin ve que el Médico tiene historia clínica activa','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-66 · SEG-21 · Un usuario que no es Médico no activa el enlace de recuperación','ok',coalesce((not (public.password_reset_info(('17600000-0000-4000-8000-000000000023')::uuid)->>'clinical')::boolean), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-66 · SEG-21 · Un usuario que no es Médico no activa el enlace de recuperación','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-67 · SEG-21 · Un Médico de un consultorio sin historia clínica activa sigue con el flujo normal','ok',coalesce((not (public.password_reset_info(('17600000-0000-4000-8000-000000000024')::uuid)->>'clinical')::boolean), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-67 · SEG-21 · Un Médico de un consultorio sin historia clínica activa sigue con el flujo normal','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.password_reset_info(('17600000-0000-4000-8000-000000000021')::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-68 · SEG-21 · ATAQUE: el Administrador no consulta esta información','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-68 · SEG-21 · ATAQUE: el Administrador no consulta esta información','ok',sqlerrm like 'Solo el Super Admin restablece contraseñas%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.record_recovery_link(('17600000-0000-4000-8000-000000000021')::uuid, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-69 · SEG-21 · El motivo corto se rechaza y dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-69 · SEG-21 · El motivo corto se rechaza y dice qué hacer','ok',sqlerrm like 'Escriba el motivo del restablecimiento%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.record_recovery_link(('17600000-0000-4000-8000-000000000021')::uuid, 'El médico olvidó su clave y no puede entrar');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-70 · SEG-21 · Uso legítimo: con motivo suficiente se registra el enlace de recuperación','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-70 · SEG-21 · Uso legítimo: con motivo suficiente se registra el enlace de recuperación','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-71 · SEG-21 · El registro queda en la bitácora de usuarios con el motivo','ok',coalesce((exists (select 1 from public.user_admin_log where action = 'restablecer_clave' and detail like 'Enlace de recuperación%' and target_id = ('17600000-0000-4000-8000-000000000021')::uuid and detail like '%olvidó su clave%')), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-71 · SEG-21 · El registro queda en la bitácora de usuarios con el motivo','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17600000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.record_recovery_link(('17600000-0000-4000-8000-000000000024')::uuid, 'Intento de restablecer a otro usuario');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-72 · SEG-21 · ATAQUE: el Médico no registra restablecimientos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-72 · SEG-21 · ATAQUE: el Médico no registra restablecimientos','ok',sqlerrm like 'Solo el Super Admin restablece contraseñas%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-73 · B3 · La migración 176 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '176')), false),'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B3-73 · B3 · La migración 176 queda registrada','ok',false,'d',left(sqlerrm,160)));
    end;
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
revoke all on function app.qa_run_tests_blindaje_3() from public, anon, authenticated;
