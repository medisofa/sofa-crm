-- 193 · Suite de la 192 (paquete de reconsideración de glosas, I60). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_reconsideracion();
create or replace function app.qa_run_tests_reconsideracion()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_oa constant uuid := '01920000-0000-4000-8000-000000000001'; v_ob constant uuid := '01920000-0000-4000-8000-000000000002'; v_ox constant uuid := '01920000-0000-4000-8000-000000000003'; v_op2 constant uuid := '01920000-0000-4000-8000-000000000004';
  v_pa constant uuid := '01920000-0000-4000-8000-000000000011'; v_pb constant uuid := '01920000-0000-4000-8000-000000000012'; v_px constant uuid := '01920000-0000-4000-8000-000000000013';
  v_sa constant uuid := '01920000-0000-4000-8000-000000000021'; v_ad constant uuid := '01920000-0000-4000-8000-000000000022'; v_gl constant uuid := '01920000-0000-4000-8000-000000000023'; v_b1 constant uuid := '01920000-0000-4000-8000-000000000024'; v_ops constant uuid := '01920000-0000-4000-8000-000000000025'; v_au constant uuid := '01920000-0000-4000-8000-000000000026';
  v_ma constant uuid := '01920000-0000-4000-8000-000000000027'; v_mb constant uuid := '01920000-0000-4000-8000-000000000028'; v_ax constant uuid := '01920000-0000-4000-8000-000000000029'; v_co constant uuid := '01920000-0000-4000-8000-000000000030';
  v_ars uuid; v_ars2 uuid; v_proc uuid; v_t date;
  v_sub_a uuid; v_sub_b uuid; v_sub_x uuid; v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid; v_lb uuid; v_lx uuid;
  v_g1 uuid; v_g2 uuid; v_g3 uuid; v_g4 uuid; v_gb uuid; v_gx uuid;
  v_t_sa uuid; v_t_tar uuid; v_t_dup uuid; v_t_ex uuid; v_t_ars uuid; v_t_new uuid;
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_p4 uuid; v_y jsonb; v_rl text;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '192') then
    raise exception 'Falta la migración 192. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    v_t := app.recon_today();
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.rc.sa@sofa.test','x'),(v_ad::uuid,'qa.rc.ad@sofa.test','x'),(v_gl::uuid,'qa.rc.gl@sofa.test','x'),(v_b1::uuid,'qa.rc.b1@sofa.test','x'),(v_ops::uuid,'qa.rc.ops@sofa.test','x'),(v_au::uuid,'qa.rc.au@sofa.test','x'),(v_ma::uuid,'qa.rc.ma@sofa.test','x'),(v_mb::uuid,'qa.rc.mb@sofa.test','x'),(v_ax::uuid,'qa.rc.ax@sofa.test','x'),(v_co::uuid,'qa.rc.co@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.rc.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_oa, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I60 A', '00000019201', 'Médico independiente', 'activo', current_date - 90, '8095559201');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_ob, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I60 B', '00000019202', 'Médico independiente', 'activo', current_date - 90, '8095559202');
    insert into public.organizations (id, kind, legal_name, tax_id, org_type, status, started_on) values (v_op2, 'operator', 'QA I60 Operador Dos', '00000019209', 'Operador', 'activo', current_date - 90);
    -- Folio de reclamación único en toda la base (índice service_lines_claim_folio_uq de producción) pero contador por operador: se adelanta el del segundo operador para que no choque con el primero.
    insert into public.folio_counters (scope_id, kind, year, last_value) select v_op2, k, extract(year from current_date)::smallint, 900000 from unnest(array['REC','GLO','RAD','FAC','CON','PAG','PRV','REL','RET','SRV','HAB']) as k on conflict (scope_id, kind, year) do update set last_value = 900000;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_ox, 'client', v_op2, 'QA I60 X', '00000019203', 'Médico independiente', 'activo', current_date - 90, '8095550003');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_oa, 'Dr. A QA', 'Cardiología', true), (v_pb, v_ob, 'Dr. B QA', 'Ortopedia', true), (v_px, v_ox, 'Dr. X QA', 'Pediatría', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_gl, 'glosas', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_b1, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops, 'operations', true),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_au, 'auditor', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_co, 'assistant', true), (v_oa, v_ma, 'client', true), (v_ob, v_mb, 'client', true), (v_op2, v_ax, 'admin', true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_rc_ars', 'ARS QA Reconsideración', 'Contributivo', true) returning id into v_ars;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_rc_ars2', 'ARS QA Otra', 'Contributivo', true) returning id into v_ars2;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_oa, v_pa, v_ars, date_trunc('month', v_t - 60)::date, 1, 'borrador', v_t - 45, 'RQC1', 'B0100000951') returning id into v_sub_a;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_ob, v_pb, v_ars2, date_trunc('month', v_t - 60)::date, 1, 'borrador', v_t - 20, 'RQC2', 'B0100000952') returning id into v_sub_b;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_ox, v_px, v_ars, date_trunc('month', v_t - 60)::date, 1, 'borrador', v_t - 20, 'RQC3', 'B0100000953') returning id into v_sub_x;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_sub_a, v_oa, date_trunc('month', v_t - 60)::date + 3, 'Paciente QA 1', v_proc, 1, 300, 'M1', 'AU1') returning id into v_l1;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_sub_a, v_oa, date_trunc('month', v_t - 60)::date + 3, 'Paciente QA 2', v_proc, 1, 100, 'M2', 'AU2') returning id into v_l2;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_sub_a, v_oa, date_trunc('month', v_t - 60)::date + 3, 'Paciente QA 3', v_proc, 1, 500, 'M3', 'AU3') returning id into v_l3;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_sub_a, v_oa, date_trunc('month', v_t - 60)::date + 3, 'Paciente QA 4', v_proc, 1, 100, 'M4', 'AU4') returning id into v_l4;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_sub_b, v_ob, date_trunc('month', v_t - 60)::date + 3, 'Paciente QA 5', v_proc, 1, 200, 'M5', 'AU5') returning id into v_lb;
    perform set_config('app.contract_override', '', true);
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number)
    values (v_sub_x, v_ox, date_trunc('month', v_t - 60)::date + 3, 'Paciente QA 6', v_proc, 1, 200, 'M6', 'AU6') returning id into v_lx;
    perform set_config('app.contract_override', '', true);
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_sub_a, v_t - 20, 'GLO-QA-RC1') returning id into v_g1;
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_sub_a, v_t, 'GLO-QA-RC2') returning id into v_g2;
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_sub_a, v_t - 3, 'GLO-QA-RC3') returning id into v_g3;
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_sub_a, v_t - 2, 'GLO-QA-RC4') returning id into v_g4;
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_ob, v_sub_b, v_t - 2, 'GLO-QA-RC5') returning id into v_gb;
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_ox, v_sub_x, v_t - 2, 'GLO-QA-RC6') returning id into v_gx;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values
      (v_g1, v_oa, v_l1, 'sin_autorizacion', 300), (v_g1, v_oa, v_l2, 'documentacion', 100), (v_g2, v_oa, v_l3, 'tarifa_superior', 500), (v_g3, v_oa, v_l4, 'otro', 50),
      (v_gb, v_ob, v_lb, 'duplicidad', 200), (v_gx, v_ox, v_lx, 'duplicidad', 200);
    perform set_config('app.glosa_change', 'on', true);
    update public.glosas set status = 'cerrada' where id = v_g3;
    perform set_config('app.glosa_change', '', true);
    select id into v_t_sa from public.glosa_letter_templates where operator_id = '00000000-0000-4000-8000-000000000001'::uuid and reason_code = 'sin_autorizacion' and ars_id is null;
    select id into v_t_tar from public.glosa_letter_templates where operator_id = '00000000-0000-4000-8000-000000000001'::uuid and reason_code = 'tarifa_superior' and ars_id is null;
    select id into v_t_dup from public.glosa_letter_templates where operator_id = '00000000-0000-4000-8000-000000000001'::uuid and reason_code = 'duplicidad' and ars_id is null;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-01 · La migración 192 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '192')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-02 · Las tres tablas no se tocan por la API: ni anon ni authenticated tienen permisos','ok',coalesce((not has_table_privilege('authenticated', 'public.glosa_letter_templates', 'select') and not has_table_privilege('authenticated', 'public.glosa_letter_templates', 'insert') and not has_table_privilege('authenticated', 'public.glosa_reconsiderations', 'update') and not has_table_privilege('authenticated', 'public.glosa_reconsiderations', 'select') and not has_table_privilege('authenticated', 'public.glosa_support_requirements', 'delete') and not has_table_privilege('anon', 'public.glosa_reconsiderations', 'select') and not has_table_privilege('anon', 'public.glosa_letter_templates', 'select')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-03 · Las funciones públicas no están abiertas a anon y sí a authenticated','ok',coalesce((not has_function_privilege('anon', 'public.recon_prepare(uuid,uuid)', 'execute') and not has_function_privilege('anon', 'public.recon_template_approve(uuid)', 'execute') and not has_function_privilege('anon', 'public.recon_indicator(uuid,date,date)', 'execute') and has_function_privilege('authenticated', 'public.recon_send(uuid,date,text,text,text)', 'execute') and has_function_privilege('authenticated', 'public.recon_list(uuid,text,integer)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-04 · Las funciones internas (rol, plazo, soportes, carta) no se llaman desde la API','ok',coalesce((not has_function_privilege('authenticated', 'app.recon_role(uuid)', 'execute') and not has_function_privilege('authenticated', 'app.recon_due(uuid,integer)', 'execute') and not has_function_privilege('authenticated', 'app.recon_support_status(uuid)', 'execute') and not has_function_privilege('authenticated', 'app.recon_render(text,uuid,numeric)', 'execute') and not has_function_privilege('anon', 'app.recon_missing(uuid)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-05 · Todas las funciones recon_ son SECURITY DEFINER con search_path vacío (salvo las de formato)','ok',coalesce((not exists (select 1 from pg_proc p where p.pronamespace in ('app'::regnamespace, 'public'::regnamespace) and p.proname like 'recon\_%' and p.proname not in ('recon_today','recon_status_label','recon_placeholders','recon_check_marks') and (not p.prosecdef or p.proconfig is null or not ('search_path=' = any (p.proconfig) or 'search_path=""' = any (p.proconfig))))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-06 · La fecha de hoy es la de República Dominicana (no la del servidor en UTC)','ok',coalesce((app.recon_today() = (now() at time zone 'America/Santo_Domingo')::date), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-07 · La migración deja un BORRADOR de carta por cada motivo activo y NINGUNA aprobada (decisión del usuario)','ok',coalesce(((select count(*) from public.glosa_letter_templates where operator_id = '00000000-0000-4000-8000-000000000001'::uuid and status = 'borrador') >= (select count(*) from public.glosa_reasons where is_active) and not exists (select 1 from public.glosa_letter_templates where status = 'aprobada')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-08 · Cada motivo trae su lista de soportes requeridos (p. ej. la falta de autorización exige la autorización y el formulario)','ok',coalesce((exists (select 1 from public.glosa_support_requirements where operator_id = '00000000-0000-4000-8000-000000000001'::uuid and reason_code = 'sin_autorizacion' and document_type_code = 'autorizacion' and requirement = 'obligatorio') and (select count(distinct reason_code) from public.glosa_support_requirements where operator_id = '00000000-0000-4000-8000-000000000001'::uuid) >= 14), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-09 · Las marcas de la carta incluyen cliente, ARS, folio, monto y detalle de servicios','ok',coalesce((app.recon_placeholders() @> array['cliente','ars_nombre','glosa_folio','monto_reclamado','detalle_servicios','norma']), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.recon_templates_list();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-10 · Glosas ve las plantillas y las edita, pero no las aprueba','ok',coalesce(((v_x->>'can_edit')::boolean and not (v_x->>'can_approve')::boolean and jsonb_array_length(v_x->'templates') >= 15), false),'d',(left(v_x::text, 200))::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_template_approve(v_t_sa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-11 · ATAQUE: Glosas no aprueba plantillas (solo Super Admin o Administrador)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-11 · ATAQUE: Glosas no aprueba plantillas (solo Super Admin o Administrador)','ok',sqlerrm like 'Solo el Super Admin o el Administrador aprueban%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_template_save(null, 'duplicidad', v_ars, 'Duplicidad · ARS QA', 'Estimados {{ars_nombre}}: solicitamos reconsiderar la glosa {{glosa_folio}} por {{monto_reclamado}}. Adjuntamos los soportes del índice anexo.');
    v_t_ars := (v_x->>'id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-12 · Glosas guarda una plantilla nueva y queda en borrador','ok',coalesce((v_x->>'status' = 'borrador' and exists (select 1 from public.glosa_letter_templates where id = v_t_ars and status = 'borrador' and ars_id = v_ars)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_template_save(null, 'duplicidad', null, 'Prueba', 'Estimados {{paciente}}: solicitamos reconsiderar esta glosa con todos los soportes.');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-13 · Una marca desconocida se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-13 · Una marca desconocida se rechaza','ok',sqlerrm like 'La marca «{{paciente}}» no existe%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_template_save(null, 'duplicidad', null, 'Prueba', 'Estimados {{ars_nombre: solicitamos reconsiderar esta glosa con todos los soportes.');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-14 · Una marca sin cerrar se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-14 · Una marca sin cerrar se rechaza','ok',sqlerrm like 'Hay una marca incompleta%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_template_save(null, 'duplicidad', null, 'Prueba', 'Corta');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-15 · Una carta demasiado corta se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-15 · Una carta demasiado corta se rechaza','ok',sqlerrm like 'La carta debe tener al menos 40%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_template_save(null, 'inventado', null, 'Prueba', 'Estimados {{ars_nombre}}: solicitamos reconsiderar la glosa {{glosa_folio}} por {{monto_reclamado}}. Adjuntamos los soportes del índice anexo.');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-16 · Un motivo inexistente se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-16 · Un motivo inexistente se rechaza','ok',sqlerrm like 'Elija el motivo de glosa%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_prepare(v_g1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-17 · ATAQUE: sin plantilla APROBADA no se prepara ningún paquete','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-17 · ATAQUE: sin plantilla APROBADA no se prepara ningún paquete','ok',sqlerrm like 'No hay una plantilla APROBADA%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_prepare(v_g1, v_t_sa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-18 · ATAQUE: una plantilla en borrador no se puede elegir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-18 · ATAQUE: una plantilla en borrador no se puede elegir','ok',sqlerrm like 'La plantilla «%» está en borrador%','d',left(sqlerrm,120)));
    end;
    begin
      perform 1 from public.glosa_reconsiderations limit 1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-19 · ATAQUE: la API no lee las tablas directamente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-19 · ATAQUE: la API no lee las tablas directamente','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.glosa_letter_templates (operator_id, reason_code, title, body, status) values ('00000000-0000-4000-8000-000000000001'::uuid, 'otro', 'Directa', 'Estimados {{ars_nombre}}: solicitamos reconsiderar la glosa {{glosa_folio}} por {{monto_reclamado}}. Adjuntamos los soportes del índice anexo.', 'aprobada');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-20 · ATAQUE: la API no escribe las plantillas directamente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-20 · ATAQUE: la API no escribe las plantillas directamente','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.recon_templates_list();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-21 · Facturación consulta las plantillas pero no las edita','ok',coalesce((not (v_x->>'can_edit')::boolean and not (v_x->>'can_approve')::boolean), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_template_save(null, 'otro', null, 'Prueba', 'Estimados {{ars_nombre}}: solicitamos reconsiderar la glosa {{glosa_folio}} por {{monto_reclamado}}. Adjuntamos los soportes del índice anexo.');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-22 · Facturación no guarda plantillas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-22 · Facturación no guarda plantillas','ok',sqlerrm like 'Solo Glosas o la Administración%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_prepare(v_g1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-23 · Facturación no prepara paquetes (solo lectura)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-23 · Facturación no prepara paquetes (solo lectura)','ok',sqlerrm like 'Su rol solo consulta%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_list();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-24 · Facturación ve en la lista las glosas abiertas sin paquete','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'without_package') e where (e->>'glosa_id')::uuid = v_g1) and not (v_x->>'can_edit')::boolean), false),'d',(left(v_x::text, 200))::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_templates_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-25 · ATAQUE: el Médico no ve las plantillas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-25 · ATAQUE: el Médico no ve las plantillas','ok',sqlerrm like 'Las plantillas de carta son del equipo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_prepare(v_g1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-26 · ATAQUE: el Médico no prepara paquetes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-26 · ATAQUE: el Médico no prepara paquetes','ok',sqlerrm like 'Glosa no encontrada o sin acceso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_supports_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-27 · ATAQUE: el Médico no ve la lista de soportes por motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-27 · ATAQUE: el Médico no ve la lista de soportes por motivo','ok',sqlerrm like 'La lista de soportes por motivo es del equipo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_check_supports(v_g1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-28 · ATAQUE: el Médico no revisa los soportes de la glosa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-28 · ATAQUE: el Médico no revisa los soportes de la glosa','ok',sqlerrm like 'Glosa no encontrada o sin acceso%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_au, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_templates_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-29 · Auditoría no ve las plantillas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-29 · Auditoría no ve las plantillas','ok',sqlerrm like 'Las plantillas de carta son del equipo%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_prepare(v_g1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-30 · Operaciones no prepara paquetes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-30 · Operaciones no prepara paquetes','ok',sqlerrm like 'Glosa no encontrada o sin acceso%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_prepare(v_g1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-31 · ATAQUE: el administrador de otro operador no prepara paquetes de este operador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-31 · ATAQUE: el administrador de otro operador no prepara paquetes de este operador','ok',sqlerrm like 'Glosa no encontrada o sin acceso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_template_approve(v_t_sa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-32 · ATAQUE: el administrador de otro operador no aprueba plantillas de este operador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-32 · ATAQUE: el administrador de otro operador no aprueba plantillas de este operador','ok',sqlerrm like 'Plantilla no encontrada%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_template_delete(v_t_ars);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-33 · ATAQUE: el administrador de otro operador no borra plantillas de este operador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-33 · ATAQUE: el administrador de otro operador no borra plantillas de este operador','ok',sqlerrm like 'Plantilla no encontrada%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.recon_template_approve(v_t_sa);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-34 · El Administrador aprueba una plantilla: queda aprobada con su fecha y quien la aprobó','ok',coalesce((v_x->>'status' = 'aprobada' and exists (select 1 from public.glosa_letter_templates where id = v_t_sa and status = 'aprobada' and approved_by = v_ad and approved_at is not null)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_template_approve(v_t_sa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-35 · Aprobar dos veces se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-35 · Aprobar dos veces se rechaza','ok',sqlerrm like 'La plantilla ya está aprobada%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_template_save(null, 'sin_autorizacion', null, 'Otra de falta de autorización', 'Estimados {{ars_nombre}}: solicitamos reconsiderar la glosa {{glosa_folio}} por {{monto_reclamado}}. Adjuntamos los soportes del índice anexo.');
    v_t_ex := (v_x->>'id')::uuid;
    begin
      perform public.recon_template_approve(v_t_ex);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-36 · No puede haber dos aprobadas para el mismo motivo y ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-36 · No puede haber dos aprobadas para el mismo motivo y ARS','ok',sqlerrm like 'Ya hay otra plantilla aprobada%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      update public.glosa_letter_templates set status = 'aprobada', approved_by = '00000000-0000-4000-8000-000000000099', approved_at = now() where id = v_t_ex;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-37 · El disparador impide aprobar escribiendo directo en la tabla','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-37 · El disparador impide aprobar escribiendo directo en la tabla','ok',sqlerrm like 'Una plantilla solo queda aprobada con%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_template_delete(v_t_sa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-38 · Una plantilla aprobada no se borra','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-38 · Una plantilla aprobada no se borra','ok',sqlerrm like 'Una plantilla aprobada no se borra%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_template_delete(v_t_ex);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-39 · Un borrador sin uso sí se borra','ok',coalesce(((v_x->>'deleted')::boolean and not exists (select 1 from public.glosa_letter_templates where id = v_t_ex)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_x := public.recon_template_save(v_t_sa, 'sin_autorizacion', null, 'Falta de autorización (ajustada)', 'Estimados {{ars_nombre}}: solicitamos reconsiderar la glosa {{glosa_folio}} por {{monto_reclamado}}. Adjuntamos los soportes del índice anexo.');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-40 · Editar una plantilla aprobada la devuelve a borrador y sube la versión','ok',coalesce(((v_x->>'returned_to_draft')::boolean and exists (select 1 from public.glosa_letter_templates where id = v_t_sa and status = 'borrador' and approved_at is null and version = 2)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform public.recon_template_approve(v_t_sa);
    perform public.recon_template_approve(v_t_tar);
    perform public.recon_template_approve(v_t_dup);
    perform public.recon_template_approve(v_t_ars);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-41 · Aprobadas las plantillas de falta de autorización, tarifa y duplicidad (general y de una ARS)','ok',coalesce(((select count(*) from public.glosa_letter_templates where status = 'aprobada') = 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_prepare(v_g2, v_t_dup);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-42 · ATAQUE: una plantilla de otro motivo no sirve para la glosa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-42 · ATAQUE: una plantilla de otro motivo no sirve para la glosa','ok',sqlerrm like 'La plantilla «%» es de un motivo que esta glosa no tiene%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_prepare(v_gb, v_t_ars);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-43 · ATAQUE: una plantilla de otra ARS no sirve para la glosa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-43 · ATAQUE: una plantilla de otra ARS no sirve para la glosa','ok',sqlerrm like '%es de otra ARS%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_prepare(v_g3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-44 · Una glosa ya cerrada no admite paquete','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-44 · Una glosa ya cerrada no admite paquete','ok',sqlerrm like 'La glosa ya está resuelta%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_prepare(v_g1);
    v_p1 := (v_x->>'id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-45 · El paquete se arma con la plantilla aprobada: monto reclamado 400 (lo glosado), ronda 1 y los 3 soportes que faltan','ok',coalesce(((v_x->>'amount_claimed')::numeric = 400 and (v_x->>'round')::int = 1 and jsonb_array_length(v_x->'missing_supports') = 3), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-46 · El plazo de la ronda 1 son 7 días hábiles desde la notificación (parámetro de la 144)','ok',coalesce(((v_x->>'due_on')::date = app.add_business_days(v_t - 20, 7)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-47 · La carta lleva el folio, la ARS y el monto, y no queda ninguna marca sin reemplazar','ok',coalesce((exists (select 1 from public.glosa_reconsiderations where id = v_p1 and letter_text like '%GLO-QA-RC1%' and letter_text like '%ARS QA Reconsideración%' and letter_text like '%RD$ 400.00%' and letter_text not like '%{{%' and template_version = 2 and reason_code = 'sin_autorizacion')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_prepare(v_g1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-48 · Con un paquete en curso no se prepara otro','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-48 · Con un paquete en curso no se prepara otro','ok',sqlerrm like 'Ya hay un paquete en curso%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_check_supports(v_g1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-49 · La verificación contra los documentos adjuntos marca como faltantes la autorización, el formulario y el récord','ok',coalesce((jsonb_array_length(v_x->'missing') = 3 and not exists (select 1 from jsonb_array_elements(v_x->'supports') e where (e->>'present')::boolean and e->>'requirement' = 'obligatorio')), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_letter_edit(v_p1, 'Texto con una marca sin completar {{cliente}} que no se reemplazó nunca antes de guardar.');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-50 · ATAQUE: la carta no admite marcas sin completar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-50 · ATAQUE: la carta no admite marcas sin completar','ok',sqlerrm like 'La carta tiene marcas%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_letter_edit(v_p1, 'Texto ajustado a mano para la glosa GLO-QA-RC1: la ARS debe revisar el expediente completo y levantar la glosa por RD$ 400.00.');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-51 · Glosas ajusta la carta del paquete sin enviar','ok',coalesce((exists (select 1 from public.glosa_reconsiderations where id = v_p1 and letter_text like 'Texto ajustado a mano%')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_send(v_p1, v_t - 10, null, 'Entrega tardía por parte del médico', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-52 · Enviar con soportes obligatorios sin adjuntar exige el motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-52 · Enviar con soportes obligatorios sin adjuntar exige el motivo','ok',sqlerrm like 'Faltan soportes obligatorios: %','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_send(v_p1, v_t + 1, null, null, 'Soportes se enviarán después');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-53 · La fecha de envío no puede ser futura','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-53 · La fecha de envío no puede ser futura','ok',sqlerrm like 'La fecha de envío no puede ser futura%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_send(v_p1, v_t - 30, null, null, 'Soportes se enviarán después');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-54 · La fecha de envío no puede ser anterior a la notificación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-54 · La fecha de envío no puede ser anterior a la notificación','ok',sqlerrm like 'La fecha de envío no puede ser anterior%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.documents (organization_id, entity_type, entity_id, document_type_code, storage_path, file_name, mime_type, size_bytes) values
      (v_oa, 'submission', v_sub_a, 'autorizacion', v_oa::text || '/rc/aut.pdf', 'aut.pdf', 'application/pdf', 1000),
      (v_oa, 'glosa', v_g1, 'formulario_ars', v_oa::text || '/rc/form.pdf', 'form.pdf', 'application/pdf', 1000),
      (v_oa, 'service_line', v_l2, 'record', v_oa::text || '/rc/rec.pdf', 'rec.pdf', 'application/pdf', 1000);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.recon_check_supports(v_g1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-55 · Con los tres documentos adjuntos (de la radicación, de la glosa y del servicio) ya no falta ninguno','ok',coalesce((jsonb_array_length(v_x->'missing') = 0 and (select count(*) from jsonb_array_elements(v_x->'supports') e where (e->>'present')::boolean) >= 3), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_send(v_p1, v_t, 'REF-1', null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-56 · Enviar fuera de plazo exige el motivo del retraso','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-56 · Enviar fuera de plazo exige el motivo del retraso','ok',sqlerrm like 'El plazo venció el%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_send(v_p1, v_t, 'REF-QA-1', 'La documentación llegó tarde desde el consultorio', null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-57 · El envío tardío queda registrado con su motivo, quien lo envió y la apelación','ok',coalesce((v_x->>'status' = 'enviada' and (v_x->>'late')::boolean and exists (select 1 from public.glosa_reconsiderations r where r.id = v_p1 and r.sent_by = v_gl and r.sent_late and r.late_reason like 'La documentación llegó tarde%' and r.sent_reference = 'REF-QA-1' and r.appeal_id is not null and r.missing_reason is null)), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-58 · Al enviar se registra la apelación con la función existente y la glosa pasa a Apelada','ok',coalesce((exists (select 1 from public.glosa_appeals a where a.glosa_id = v_g1 and a.submitted_on = v_t) and exists (select 1 from public.glosas where id = v_g1 and status = 'apelada' and ars_response_due is not null)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_send(v_p1, v_t, null, 'otra vez sin necesidad', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-59 · Un paquete enviado no se reenvía','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-59 · Un paquete enviado no se reenvía','ok',sqlerrm like 'Este paquete ya está%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_letter_edit(v_p1, 'Texto ajustado a mano para la glosa GLO-QA-RC1: la ARS debe revisar el expediente completo y levantar la glosa por RD$ 400.00.');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-60 · La carta de un paquete enviado no se edita','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-60 · La carta de un paquete enviado no se edita','ok',sqlerrm like 'Solo se ajusta la carta de un paquete sin enviar%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_cancel(v_p1, 'Quiero anularlo ahora mismo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-61 · Un paquete enviado no se anula','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-61 · Un paquete enviado no se anula','ok',sqlerrm like 'Solo se anula un paquete sin enviar%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_result(v_p1, 'tal vez', 0, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-62 · Resultado distinto de aceptada o rechazada se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-62 · Resultado distinto de aceptada o rechazada se rechaza','ok',sqlerrm like 'El resultado es «aceptada» o «rechazada»%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_result(v_p1, 'aceptada', 0, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-63 · Aceptada sin monto recuperado se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-63 · Aceptada sin monto recuperado se rechaza','ok',sqlerrm like 'Escriba el monto que la ARS aceptó%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_result(v_p1, 'aceptada', 401, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-64 · Lo recuperado no puede superar lo reclamado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-64 · Lo recuperado no puede superar lo reclamado','ok',sqlerrm like 'Lo recuperado%no puede superar%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_result(v_p1, 'rechazada', 0, null, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-65 · Rechazada sin explicar el porqué se rechaza (alimenta la causa raíz)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-65 · Rechazada sin explicar el porqué se rechaza (alimenta la causa raíz)','ok',sqlerrm like 'Escriba por qué la ARS rechazó%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_result(v_p1, 'rechazada', 0, v_t - 1, 'La ARS mantiene la glosa por pertinencia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-66 · La fecha del resultado no puede ser anterior al envío','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-66 · La fecha del resultado no puede ser anterior al envío','ok',sqlerrm like 'La fecha del resultado no puede ser anterior%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_result(v_p1, 'rechazada', 0, v_t, 'La ARS mantiene la glosa por falta de la autorización original');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-67 · Rechazada: queda sin monto recuperado, con la nota y avisa que falta la acción correctiva de causa raíz','ok',coalesce((v_x->>'status' = 'rechazada' and (v_x->>'recovered')::numeric = 0 and not (v_x->>'root_action_open')::boolean and v_x->>'next' like 'Registre una acción correctiva%' and exists (select 1 from public.glosa_reconsiderations where id = v_p1 and resolved_by = v_gl and resolved_on = v_t)), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_result(v_p1, 'aceptada', 100, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-68 · Un paquete ya resuelto no admite otro resultado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-68 · Un paquete ya resuelto no admite otro resultado','ok',sqlerrm like 'Solo se registra el resultado de un paquete enviado%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_prepare(v_g1);
    v_p2 := (v_x->>'id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-69 · Segunda ronda: se vuelve a reclamar los 400 y el plazo es la fecha límite de apelación de la glosa','ok',coalesce(((v_x->>'round')::int = 2 and (v_x->>'amount_claimed')::numeric = 400 and (v_x->>'due_on')::date = (select appeal_deadline from public.glosas where id = v_g1)), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    v_x := public.recon_send(v_p2, v_t, 'REF-QA-2', 'Plazo de apelación vencido por la demora del médico', null);
    v_x := public.recon_result(v_p2, 'aceptada', 250, v_t, 'La ARS levantó la glosa de autorización');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-70 · Aceptada: guarda el monto recuperado, la fecha y quien lo registró','ok',coalesce((v_x->>'status' = 'aceptada' and (v_x->>'recovered')::numeric = 250 and exists (select 1 from public.glosa_reconsiderations where id = v_p2 and recovered_amount = 250 and resolved_by = v_gl)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_x := public.recon_prepare(v_g1);
    v_p3 := (v_x->>'id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-71 · Tercera ronda: solo se reclama lo que falta (400 menos 250 ya recuperados)','ok',coalesce(((v_x->>'round')::int = 3 and (v_x->>'amount_claimed')::numeric = 150), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_cancel(v_p3, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-72 · Anular un paquete exige el motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-72 · Anular un paquete exige el motivo','ok',sqlerrm like 'Escriba por qué se anula%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_cancel(v_p3, 'La ARS pidió esperar la conciliación del lote');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-73 · Anular un paquete sin enviar lo deja anulado con la fecha y quien lo anuló','ok',coalesce((v_x->>'status' = 'anulada' and exists (select 1 from public.glosa_reconsiderations where id = v_p3 and cancelled_by = v_gl and cancel_reason like 'La ARS pidió%')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_x := public.recon_indicator(null, v_t - 30, v_t);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-74 · Indicador: 2 envíos, 800 reclamados, 250 recuperados (31.3 %) y los anulados no cuentan','ok',coalesce(((v_x->'totals'->>'sent')::int = 2 and (v_x->'totals'->>'claimed')::numeric = 800 and (v_x->'totals'->>'recovered')::numeric = 250 and (v_x->'totals'->>'pct_recovered')::numeric = 31.3 and (v_x->'totals'->>'accepted')::int = 1 and (v_x->'totals'->>'rejected')::int = 1), false),'d',(v_x->'totals')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-75 · Indicador: desglose por ARS, por motivo y por mes','ok',coalesce((jsonb_array_length(v_x->'by_ars') = 1 and v_x->'by_reason'->0->>'reason_code' = 'sin_autorizacion' and jsonb_array_length(v_x->'by_month') >= 1), false),'d',(left(v_x::text, 300))::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_indicator(null, v_t, v_t - 5);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-76 · El indicador rechaza una fecha final anterior a la inicial','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-76 · El indicador rechaza una fecha final anterior a la inicial','ok',sqlerrm like 'La fecha final no puede ser anterior%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_indicator(null, v_t - 500, v_t);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-77 · El indicador rechaza rangos de más de 400 días','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-77 · El indicador rechaza rangos de más de 400 días','ok',sqlerrm like 'El indicador se consulta hasta por 400 días%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_prepare(v_g2);
    v_p4 := (v_x->>'id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-78 · Sin elegir plantilla se usa la aprobada del motivo principal (tarifa superior): reclama 500 y vence a 7 días hábiles','ok',coalesce(((v_x->>'amount_claimed')::numeric = 500 and (v_x->>'due_on')::date = app.add_business_days(v_t, 7) and v_x->>'template' like 'Borrador · Tarifa%'), false),'d',(v_x::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.recon_template_unapprove(v_t_tar);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_send(v_p4, null, null, null, 'Sin soportes, la ARS los acepta así');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-79 · ATAQUE: si la plantilla ya no está aprobada, la carta no se envía','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-79 · ATAQUE: si la plantilla ya no está aprobada, la carta no se envía','ok',sqlerrm like 'La plantilla «%» ya no está aprobada%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.recon_list();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-80 · El Médico ve el ESTADO de lo suyo (ronda 1 rechazada, ronda 2 aceptada, la de tarifa preparada) sin cartas, motivos internos ni quién lo hizo','ok',coalesce((jsonb_array_length(v_x->'rows') = 4 and exists (select 1 from jsonb_array_elements(v_x->'rows') e where e->>'status' = 'aceptada' and (e->>'recovered_amount')::numeric = 250) and not exists (select 1 from jsonb_array_elements(v_x->'rows') e where e ? 'letter_text' or e ? 'reason_code' or e ? 'sent_by' or e ? 'prepared_by' or e ? 'late_reason' or e ? 'result_note' or e ? 'sent_reference') and not (v_x->>'can_edit')::boolean and jsonb_array_length(v_x->'without_package') = 0), false),'d',(left(v_x::text, 300))::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_get(v_p1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-81 · ATAQUE: el Médico no abre el detalle del paquete (carta y soportes internos)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-81 · ATAQUE: el Médico no abre el detalle del paquete (carta y soportes internos)','ok',sqlerrm like 'Paquete no encontrado o sin acceso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_send(v_p4, null, null, null, 'Quiero enviarlo yo mismo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-82 · ATAQUE: el Médico no envía paquetes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-82 · ATAQUE: el Médico no envía paquetes','ok',sqlerrm like 'Paquete no encontrado o su rol no lo envía%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_result(v_p2, 'aceptada', 100, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-83 · ATAQUE: el Médico no registra resultados','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-83 · ATAQUE: el Médico no registra resultados','ok',sqlerrm like 'Paquete no encontrado o su rol no registra resultados%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_list(v_ob);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-84 · ATAQUE: el Médico no ve la lista de otro cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-84 · ATAQUE: el Médico no ve la lista de otro cliente','ok',sqlerrm like 'Sin acceso a las reconsideraciones de este cliente%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_indicator();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-85 · El indicador del Médico solo cuenta lo suyo','ok',coalesce(((v_x->'totals'->>'sent')::int = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.recon_list();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-86 · El Médico de otro cliente no ve nada del cliente A','ok',coalesce((jsonb_array_length(v_x->'rows') = 0 and not exists (select 1 from jsonb_array_elements(v_x->'without_package') e where (e->>'organization_id')::uuid = v_oa)), false),'d',(left(v_x::text, 200))::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ax, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.recon_list();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-87 · Otro operador no ve nada de este operador (ni paquetes ni glosas sin paquete)','ok',coalesce((jsonb_array_length(v_x->'rows') = 0 and not exists (select 1 from jsonb_array_elements(v_x->'without_package') e where (e->>'organization_id')::uuid in (v_oa, v_ob))), false),'d',(left(v_x::text, 200))::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_get(v_p1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-88 · ATAQUE: otro operador no abre el detalle','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-88 · ATAQUE: otro operador no abre el detalle','ok',sqlerrm like 'Paquete no encontrado o sin acceso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_send(v_p4, null, null, null, 'No me corresponde enviarlo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-89 · ATAQUE: otro operador no envía','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-89 · ATAQUE: otro operador no envía','ok',sqlerrm like 'Paquete no encontrado o su rol no lo envía%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_cancel(v_p4, 'No me corresponde anularlo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-90 · ATAQUE: otro operador no anula','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-90 · ATAQUE: otro operador no anula','ok',sqlerrm like 'Paquete no encontrado o su rol no lo anula%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_indicator(v_oa);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-91 · ATAQUE: otro operador no pide el indicador de un cliente ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-91 · ATAQUE: otro operador no pide el indicador de un cliente ajeno','ok',sqlerrm like 'Sin acceso a las reconsideraciones de este cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.recon_get(v_p2);
    v_y := public.recon_list(v_oa);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-92 · El detalle del equipo trae carta, soportes guardados al enviar, fechas y quién hizo cada paso','ok',coalesce((v_x->>'status' = 'aceptada' and v_x->>'letter_text' is not null and jsonb_array_length(v_x->'supports') >= 3 and v_x->>'sent_by' is not null and v_x->>'resolved_by' is not null and v_x->>'late_reason' is not null), false),'d',(left(v_x::text, 300))::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-93 · La lista del equipo ordena lo pendiente primero e incluye el semáforo del plazo del paquete preparado','ok',coalesce((v_y->'rows'->0->>'status' = 'preparada' and v_y->'rows'->0->>'light' in ('rojo','amarillo','verde') and jsonb_array_length(v_y->'rows') = 4), false),'d',(left(v_y::text, 300))::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_get(v_p2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-94 · Operaciones no ve el detalle','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-94 · Operaciones no ve el detalle','ok',sqlerrm like 'Paquete no encontrado o sin acceso%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.recon_support_save('otro', 'consentimiento', 'recomendado', 'Solo si hubo procedimiento invasivo');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-95 · Glosas agrega un soporte a un motivo','ok',coalesce((exists (select 1 from public.glosa_support_requirements where operator_id = '00000000-0000-4000-8000-000000000001'::uuid and reason_code = 'otro' and document_type_code = 'consentimiento' and requirement = 'recomendado' and note like 'Solo si%')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_x := public.recon_support_save('otro', 'consentimiento', 'obligatorio', null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-96 · Guardar de nuevo el mismo soporte lo actualiza y no lo duplica','ok',coalesce(((select count(*) from public.glosa_support_requirements where operator_id = '00000000-0000-4000-8000-000000000001'::uuid and reason_code = 'otro' and document_type_code = 'consentimiento') = 1 and exists (select 1 from public.glosa_support_requirements where reason_code = 'otro' and document_type_code = 'consentimiento' and requirement = 'obligatorio')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_support_save('otro', 'contrato_sofa', 'obligatorio', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-97 · Un documento interno de SOFA (contrato) no es soporte de una glosa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-97 · Un documento interno de SOFA (contrato) no es soporte de una glosa','ok',sqlerrm like 'Elija un tipo de documento%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.recon_support_save('otro', 'record', 'opcional', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-98 · El soporte es obligatorio o recomendado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-98 · El soporte es obligatorio o recomendado','ok',sqlerrm like 'El soporte es «obligatorio» o «recomendado»%','d',left(sqlerrm,120)));
    end;
    v_x := public.recon_support_remove('otro', 'consentimiento');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-99 · Glosas quita un soporte de la lista','ok',coalesce(((v_x->>'removed')::int = 1 and not exists (select 1 from public.glosa_support_requirements where operator_id = '00000000-0000-4000-8000-000000000001'::uuid and reason_code = 'otro' and document_type_code = 'consentimiento')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.recon_support_remove('otro', 'consentimiento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-100 · Quitar un soporte que no está en la lista avisa qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-100 · Quitar un soporte que no está en la lista avisa qué hacer','ok',sqlerrm like 'Ese soporte no está en la lista%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_b1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_support_save('otro', 'record', 'obligatorio', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-101 · Facturación no edita los soportes requeridos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-101 · Facturación no edita los soportes requeridos','ok',sqlerrm like 'Solo Glosas o la Administración%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.glosas (organization_id, submission_id, notified_on, folio) values (v_oa, v_sub_a, v_t - 1, 'GLO-QA-RC7') returning id into v_g4;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.recon_prepare(v_g4);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-102 · Una glosa sin servicios glosados no admite paquete y dice qué registrar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-102 · Una glosa sin servicios glosados no admite paquete y dice qué registrar','ok',sqlerrm like 'La glosa no tiene servicios glosados%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-103 · Las plantillas y los paquetes dejan huella en la bitácora de auditoría','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'glosa_letter_templates' and operation = 'UPDATE' and new_values->>'status' = 'aprobada') and exists (select 1 from public.audit_log where table_name = 'glosa_reconsiderations' and organization_id = v_oa and operation = 'INSERT') and exists (select 1 from public.audit_log where table_name = 'glosa_reconsiderations' and organization_id = v_oa and operation = 'UPDATE' and new_values->>'status' = 'aceptada')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-104 · La causa raíz queda ligada: el paquete guarda el motivo principal de la glosa','ok',coalesce(((select reason_code from public.glosa_reconsiderations where id = v_p1) = 'sin_autorizacion' and (select reason_code from public.glosa_reconsiderations where id = v_p4) = 'tarifa_superior'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RC-105 · Reglas de la tabla: no puede haber dos paquetes activos de la misma glosa ni recuperar más de lo reclamado','ok',coalesce(((select count(*) from public.glosa_reconsiderations where glosa_id = v_g1 and status in ('preparada','enviada')) = 0 and not exists (select 1 from public.glosa_reconsiderations where recovered_amount > amount_claimed)), false),'d',(null)::text));
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

revoke all on function app.qa_run_tests_reconsideracion() from public, anon, authenticated;
