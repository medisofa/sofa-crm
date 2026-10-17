-- 199 · Suite de la 198 (avisos por correo y resúmenes programados, I63). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_avisos();
create or replace function app.qa_run_tests_avisos()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_oa constant uuid := '01990000-0000-4000-8000-000000000001'; v_ob constant uuid := '01990000-0000-4000-8000-000000000002'; v_ox constant uuid := '01990000-0000-4000-8000-000000000003'; v_op2 constant uuid := '01990000-0000-4000-8000-000000000004';
  v_pa constant uuid := '01990000-0000-4000-8000-000000000011'; v_pb constant uuid := '01990000-0000-4000-8000-000000000012'; v_px constant uuid := '01990000-0000-4000-8000-000000000013';
  v_sa constant text := '01990000-0000-4000-8000-000000000021'; v_ad constant text := '01990000-0000-4000-8000-000000000022'; v_ops constant text := '01990000-0000-4000-8000-000000000023'; v_bil constant text := '01990000-0000-4000-8000-000000000024'; v_bilr constant text := '01990000-0000-4000-8000-000000000025'; v_gl constant text := '01990000-0000-4000-8000-000000000026';
  v_ma constant text := '01990000-0000-4000-8000-000000000031'; v_mb constant text := '01990000-0000-4000-8000-000000000032'; v_mx constant text := '01990000-0000-4000-8000-000000000033'; v_sec constant text := '01990000-0000-4000-8000-000000000034'; v_adx constant text := '01990000-0000-4000-8000-000000000035'; v_mn constant text := '01990000-0000-4000-8000-000000000038'; v_on constant uuid := '01990000-0000-4000-8000-000000000005'; v_aud constant text := '01990000-0000-4000-8000-000000000036'; v_bad constant text := '01990000-0000-4000-8000-000000000037';
  v_ars uuid; v_proc uuid; v_t date; v_mon date; v_reason text; v_sub_a uuid; v_sub_b uuid; v_sub_x uuid; v_la uuid; v_lb uuid; v_lx uuid; v_l uuid;
  v_g1 uuid; v_g2 uuid; v_g3 uuid; v_gb uuid; v_gx uuid; v_f1 text; v_fb text; v_fx text; v_pay uuid;
  v_r jsonb; v_rl text; v_id uuid; v_id2 uuid; v_n2 int; v_s text; v_tok uuid; v_ver int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '198') then
    raise exception 'Falta la migración 198. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    v_t := app.email_today(); v_mon := v_t + ((8 - extract(isodow from v_t)::int) % 7);
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.i63.sa@sofa.test','x'),(v_ad::uuid,'qa.i63.ad@sofa.test','x'),(v_ops::uuid,'qa.i63.ops@sofa.test','x'),(v_bil::uuid,'qa.i63.bil@sofa.test','x'),(v_bilr::uuid,'qa.i63.bilr@sofa.test','x'),(v_gl::uuid,'qa.i63.gl@sofa.test','x'),(v_ma::uuid,'qa.i63.ma@sofa.test','x'),(v_mb::uuid,'qa.i63.mb@sofa.test','x'),(v_mx::uuid,'qa.i63.mx@sofa.test','x'),(v_sec::uuid,'qa.i63.sec@sofa.test','x'),(v_adx::uuid,'qa.i63.adx@sofa.test','x'),(v_aud::uuid,'qa.i63.aud@sofa.test','x'),(v_mn::uuid,'qa.i63.mn@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.i63.%@sofa.test' on conflict (id) do nothing;
    insert into auth.users (id, email, encrypted_password) values (v_bad::uuid, 'correo-sin-arroba', 'x');
    insert into public.profiles (id, full_name) values (v_bad::uuid, 'qa.i63.bad') on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_oa, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I63 A', '00000019801', 'Médico independiente', 'activo', current_date - 90, '8095559801');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_ob, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I63 B', '00000019802', 'Médico independiente', 'activo', current_date - 90, '8095559802');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_on, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA I63 N', '00000019805', 'Médico independiente', 'activo', current_date - 90, '8095559805');
    insert into public.organizations (id, kind, legal_name, tax_id, org_type, status, started_on) values (v_op2, 'operator', 'QA I63 Operador Dos', '00000019809', 'Operador', 'activo', current_date - 90);
    -- Folio de reclamación único en toda la base (índice service_lines_claim_folio_uq de producción) pero contador por operador: se adelanta el del segundo operador para que no choque con el primero.
    insert into public.folio_counters (scope_id, kind, year, last_value) select v_op2, k, extract(year from current_date)::smallint, 900000 from unnest(array['REC','GLO','RAD','FAC','CON','PAG','PRV','REL','RET','SRV','HAB']) as k on conflict (scope_id, kind, year) do update set last_value = 900000;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_ox, 'client', v_op2, 'QA I63 X', '00000019804', 'Médico independiente', 'activo', current_date - 90, '8095550004');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_oa, 'Dr. A QA', 'Cardiología', true), (v_pb, v_ob, 'Dr. B QA', 'Ortopedia', true), (v_px, v_ox, 'Dr. X QA', 'Pediatría', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_bilr::uuid, 'billing', true),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_gl::uuid, 'glosas', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_aud::uuid, 'auditor', true),
      (v_oa, v_ma::uuid, 'client', true), (v_oa, v_sec::uuid, 'capturer', true), (v_ob, v_mb::uuid, 'client', true), (v_ox, v_mx::uuid, 'client', true), (v_on, v_mn::uuid, 'client', true), (v_op2, v_adx::uuid, 'admin', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_pa, v_oa, true, true);
    insert into public.staff_client_access (user_id, client_org_id) values (v_bilr::uuid, v_ob);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_av_ars', 'ARS QA Avisos', 'Contributivo', true) returning id into v_ars;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    select code into v_reason from public.glosa_reasons order by code limit 1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_oa, v_pa, v_ars, date_trunc('month', v_mon - 5)::date, 1, 'borrador', v_mon - 3, 'RQAV1', 'B0100001901') returning id into v_sub_a;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_ob, v_pb, v_ars, date_trunc('month', v_mon - 5)::date, 1, 'borrador', v_mon - 3, 'RQAV2', 'B0100001902') returning id into v_sub_b;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on, ars_receipt_number, ncf) values (v_ox, v_px, v_ars, date_trunc('month', v_mon - 5)::date, 1, 'borrador', v_mon - 3, 'RQAV3', 'B0100001903') returning id into v_sub_x;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sub_a, v_oa, v_mon - 5, 'PACIENTE-SECRETO-QA', v_proc, 1, 5000, 'MIEMBRO-SECRETO-777', 'AUT-SECRETA-888') returning id into v_l;
    perform set_config('app.contract_override', '', true);
    v_la := v_l;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sub_b, v_ob, v_mon - 5, 'Paciente QA 2', v_proc, 1, 2000, 'MIEMBRO-QA-2', 'AUT-QA-2') returning id into v_l;
    perform set_config('app.contract_override', '', true);
    v_lb := v_l;
    perform set_config('app.contract_override', 'on', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, member_number, authorization_number) values (v_sub_x, v_ox, v_mon - 5, 'Paciente QA 3', v_proc, 1, 1000, 'MIEMBRO-QA-3', 'AUT-QA-3') returning id into v_l;
    perform set_config('app.contract_override', '', true);
    v_lx := v_l;
    insert into public.glosas (organization_id, submission_id, notified_on, appeal_deadline) values (v_oa, v_sub_a, v_mon - 2, v_mon + 2) returning id, folio into v_g1, v_f1;
    insert into public.glosas (organization_id, submission_id, notified_on, appeal_deadline) values (v_oa, v_sub_a, v_mon - 2, v_mon + 3) returning id into v_g2;
    insert into public.glosas (organization_id, submission_id, notified_on, appeal_deadline) values (v_oa, v_sub_a, v_mon - 2, v_mon + 30) returning id into v_g3;
    insert into public.glosas (organization_id, submission_id, notified_on, appeal_deadline) values (v_ob, v_sub_b, v_mon - 2, v_mon + 1) returning id, folio into v_gb, v_fb;
    insert into public.glosas (organization_id, submission_id, notified_on, appeal_deadline) values (v_ox, v_sub_x, v_mon - 2, v_mon + 1) returning id, folio into v_gx, v_fx;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_g1, v_oa, v_la, v_reason, 300), (v_g2, v_oa, v_la, v_reason, 800),
      (v_g3, v_oa, v_la, v_reason, 100), (v_gb, v_ob, v_lb, v_reason, 500), (v_gx, v_ox, v_lx, v_reason, 200);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-01 · La migración 198 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '198')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-02 · Las seis tablas tienen seguridad por filas y ningún permiso para la API','ok',coalesce(((select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('email_settings','email_topics','email_preferences','email_templates','email_queue','email_log') and c.relrowsecurity) = 6
      and not exists (select 1 from unnest(array['email_settings','email_topics','email_preferences','email_templates','email_queue','email_log']) t(n), unnest(array['anon','authenticated']) r(r)
                       where has_table_privilege(r.r, 'public.' || t.n, 'select,insert,update,delete'))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-03 · Las funciones internas y las del servicio no las puede llamar un usuario','ok',coalesce((not has_function_privilege('authenticated', 'public.email_claim_batch(integer)', 'execute') and not has_function_privilege('authenticated', 'public.email_mark_sent(uuid,text,text)', 'execute')
      and not has_function_privilege('authenticated', 'public.email_mark_failed(uuid,text,boolean)', 'execute') and not has_function_privilege('authenticated', 'public.email_register_open(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.email_security_notice(uuid,text)', 'execute') and not has_function_privilege('anon', 'public.email_my_preferences()', 'execute')
      and not has_function_privilege('authenticated', 'app.email_enqueue(uuid,text,jsonb,text,uuid,timestamptz)', 'execute') and not has_function_privilege('authenticated', 'app.email_gen_glosas(date,uuid)', 'execute')
      and has_function_privilege('service_role', 'public.email_claim_batch(integer)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform count(*) from public.email_queue;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-04 · ATAQUE: el médico no lee la cola directamente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-04 · ATAQUE: el médico no lee la cola directamente','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.email_preferences (user_id, topic, enabled) values ('01990000-0000-4000-8000-000000000032'::uuid, 'pago_recibido', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-05 · ATAQUE: el médico no escribe preferencias directo en la tabla','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-05 · ATAQUE: el médico no escribe preferencias directo en la tabla','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      update public.email_templates set subject = 'x' where code = 'seguridad';
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-06 · ATAQUE: el médico no edita plantillas directo en la tabla','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-06 · ATAQUE: el médico no edita plantillas directo en la tabla','ok',sqlerrm like 'permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_queue_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-07 · ATAQUE: el médico no pide la cola','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-07 · ATAQUE: el médico no pide la cola','ok',sqlerrm like 'La cola de correos y su configuración son del Super Admin%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_settings_set(true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-08 · ATAQUE: el médico no cambia la configuración','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-08 · ATAQUE: el médico no cambia la configuración','ok',sqlerrm like 'La cola de correos y su configuración son del Super Admin%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_generate_now();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-09 · ATAQUE: el médico no activa los avisos de la clínica por la vía de generar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-09 · ATAQUE: el médico no activa los avisos de la clínica por la vía de generar','ok',sqlerrm like 'La cola de correos y su configuración son del Super Admin%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.email_queue_stats();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-10 · ATAQUE: Facturación (personal no administrador) no ve la cola','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-10 · ATAQUE: Facturación (personal no administrador) no ve la cola','ok',sqlerrm like 'La cola de correos y su configuración son del Super Admin%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.email_my_preferences();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-11 · Sin sesión no hay preferencias','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-11 · Sin sesión no hay preferencias','ok',sqlerrm like 'Su sesión venció%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_my_preferences();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-12 · Por defecto el médico ve 4 avisos: solo lo esencial activo (seguridad y glosas por vencer)','ok',coalesce((jsonb_array_length(v_r->'topics') = 4 and (select string_agg(x->>'topic', ',' order by x->>'topic') from jsonb_array_elements(v_r->'topics') x where (x->>'enabled')::boolean) = 'glosas_por_vencer,seguridad'
       and (v_r->>'avisos_activos')::boolean = false), false),'d',(null)::text));
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
      v_r := public.email_my_preferences();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-13 · El personal de apoyo (captura) solo ve el aviso de seguridad','ok',coalesce((jsonb_array_length(v_r->'topics') = 1 and v_r->'topics'->0->>'topic' = 'seguridad'), false),'d',(null)::text));
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
      v_r := public.email_my_preferences();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-14 · Facturación ve seguridad y glosas por vencer, pero no pagos ni resumen','ok',coalesce(((select string_agg(x->>'topic', ',' order by x->>'topic') from jsonb_array_elements(v_r->'topics') x) = 'glosas_por_vencer,seguridad'), false),'d',(null)::text));
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
      perform public.email_my_preference_set('resumen_semanal', true, 'quincenal');
      v_r := public.email_my_preferences();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-15 · El médico activa el resumen semanal y su elección queda guardada','ok',coalesce(((select (x->>'enabled')::boolean and x->>'frequency' = 'quincenal' and not (x->>'is_default')::boolean from jsonb_array_elements(v_r->'topics') x where x->>'topic' = 'resumen_semanal')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.email_my_preference_set('resumen_semanal', true, 'cada_minuto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-16 · Una frecuencia que no existe se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-16 · Una frecuencia que no existe se rechaza','ok',sqlerrm like 'Esa frecuencia no existe para este aviso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_my_preference_set('seguridad', false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-17 · ATAQUE: el aviso de seguridad no se apaga','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-17 · ATAQUE: el aviso de seguridad no se apaga','ok',sqlerrm like 'Los avisos de seguridad no se pueden apagar%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_my_preference_set('spam_total', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-18 · ATAQUE: un aviso inventado se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-18 · ATAQUE: un aviso inventado se rechaza','ok',sqlerrm like 'Ese aviso no está disponible para su usuario%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.email_my_preference_set('pago_recibido', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-19 · ATAQUE: Facturación no puede activar un aviso que es solo del médico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-19 · ATAQUE: Facturación no puede activar un aviso que es solo del médico','ok',sqlerrm like 'Ese aviso no está disponible para su usuario%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      insert into public.email_preferences (user_id, topic, enabled) values ('01990000-0000-4000-8000-000000000031'::uuid, 'seguridad', false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-20 · ATAQUE: ni por tabla se apaga el aviso de seguridad (disparador)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-20 · ATAQUE: ni por tabla se apaga el aviso de seguridad (disparador)','ok',sqlerrm like 'Los avisos de seguridad no se pueden apagar%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.email_my_mute_all(true);
      v_r := public.email_my_preferences();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-21 · «Apagar todos mis avisos» apaga todo lo apagable y el de seguridad sigue activo','ok',coalesce(((v_r->>'todo_apagado')::boolean and (select (x->>'enabled')::boolean from jsonb_array_elements(v_r->'topics') x where x->>'topic' = 'seguridad') and not exists (select 1 from jsonb_array_elements(v_r->'topics') x where x->>'topic' <> 'seguridad' and (x->>'enabled')::boolean)), false),'d',(null)::text));
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
      perform public.email_my_mute_all(true);
      perform public.email_my_mute_all(false);
      v_r := public.email_my_preferences();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-22 · Volver a los avisos esenciales restablece los valores por defecto','ok',coalesce(((select string_agg(x->>'topic', ',' order by x->>'topic') from jsonb_array_elements(v_r->'topics') x where (x->>'enabled')::boolean) = 'glosas_por_vencer,seguridad'), false),'d',(null)::text));
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
      perform public.email_my_preference_set('pago_recibido', true, 'diario');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_my_preferences();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-23 · Cada usuario ve solo sus preferencias: lo que cambia un médico no afecta al otro','ok',coalesce(((select not (x->>'enabled')::boolean from jsonb_array_elements(v_r->'topics') x where x->>'topic' = 'pago_recibido')), false),'d',(null)::text));
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
      perform public.email_my_preference_set('pago_recibido', true, 'diario');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-24 · Cambiar una preferencia deja huella en la bitácora de auditoría','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'email_preferences' and operation = 'INSERT' and record_id::text like '%01990000-0000-4000-8000-000000000031%')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-25 · Con los avisos apagados (valor inicial) los generadores no encolan nada','ok',coalesce((app.email_gen_glosas(v_mon) = 0 and (select count(*) from public.email_queue where recipient_id in (select id from public.profiles where full_name like 'qa.i63.%')) = 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    update public.email_settings set enabled = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    insert into public.email_settings (operator_id, enabled) values (v_op2, true) on conflict (operator_id) do update set enabled = true;
    perform app.email_gen_glosas(v_mon, '00000000-0000-4000-8000-000000000001'::uuid);
    perform app.email_gen_glosas(v_mon, v_op2);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-26 · Glosas por vencer: encola un correo por persona del equipo y médicos (8 del operador uno, 2 del dos)','ok',coalesce(((select count(*) from public.email_queue q where q.operator_id = '00000000-0000-4000-8000-000000000001'::uuid and q.recipient_id in (select id from public.profiles where full_name like 'qa.i63.%')) = 8 and (select count(*) from public.email_queue q where q.operator_id = v_op2 and q.recipient_id in (select id from public.profiles where full_name like 'qa.i63.%')) = 2), false),'d',((select string_agg(p.full_name||':'||(q.operator_id = v_op2)::text, ',') from public.email_queue q join public.profiles p on p.id = q.recipient_id where p.full_name like 'qa.i63.%'))::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-27 · Re-ejecutar el generador el mismo día no duplica nada','ok',coalesce((app.email_gen_glosas(v_mon) = 0 and app.email_gen_pagos(v_mon) = 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-28 · El correo del médico trae folio, conteo y monto de sus glosas por vencer (no la lejana)','ok',coalesce(((select q.body_html like '%' || v_f1 || '%' and q.body_html like '%RD$ 1,100.00%' and q.subject like '%2 glosa%' and q.body_html not like '%' || v_fb || '%'
        from public.email_queue q where q.recipient_id = v_ma::uuid and q.topic = 'glosas_por_vencer')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-29 · PRIVACIDAD: ningún correo trae nombre, afiliado ni autorización de pacientes','ok',coalesce((not exists (select 1 from public.email_queue q where q.recipient_id in (select id from public.profiles where full_name like 'qa.i63.%')
        and (q.body_html ~* 'SECRETO|MIEMBRO-QA|AUT-QA|AUT-SECRETA|Paciente QA' or q.body_text ~* 'SECRETO|MIEMBRO-QA|AUT-QA|AUT-SECRETA|Paciente QA'))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-30 · El correo del médico B no menciona las glosas del médico A (ni de otro operador)','ok',coalesce(((select q.body_html like '%' || v_fb || '%' and q.body_html not like '%' || v_f1 || '%' and q.body_html not like '%' || v_fx || '%' from public.email_queue q where q.recipient_id = v_mb::uuid)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-31 · Personal limitado a un cliente solo recibe las glosas de ese cliente','ok',coalesce(((select q.body_html like '%' || v_fb || '%' and q.body_html not like '%' || v_f1 || '%' from public.email_queue q where q.recipient_id = v_bilr::uuid)
        and (select q.body_html like '%' || v_f1 || '%' and q.body_html like '%' || v_fb || '%' from public.email_queue q where q.recipient_id = v_bil::uuid)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-32 · AISLAMIENTO: el administrador del otro operador solo recibe las glosas de su operador','ok',coalesce(((select q.body_html like '%' || v_fx || '%' and q.body_html not like '%' || v_f1 || '%' and q.operator_id = v_op2 from public.email_queue q where q.recipient_id = v_adx::uuid)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-33 · Quien no tiene el rol del aviso (auditor, captura) no recibe glosas por vencer','ok',coalesce((not exists (select 1 from public.email_queue q where q.recipient_id in (v_aud::uuid, v_sec::uuid))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-34 · Cada correo encolado deja su evento «encolado» en la bitácora de envío','ok',coalesce(((select count(*) from public.email_queue q where q.recipient_id in (select id from public.profiles where full_name like 'qa.i63.%')) = (select count(*) from public.email_log l join public.email_queue q on q.id = l.queue_id where l.event = 'encolado' and q.recipient_id in (select id from public.profiles where full_name like 'qa.i63.%'))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.email_queue where recipient_id = v_ma::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.email_my_preference_set('glosas_por_vencer', false);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-35 · Quien apagó las glosas por vencer no recibe el correo','ok',coalesce((app.email_gen_glosas(v_mon, '00000000-0000-4000-8000-000000000001'::uuid) = 0 and not exists (select 1 from public.email_queue where recipient_id = v_ma::uuid and topic = 'glosas_por_vencer')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.email_queue where recipient_id = v_ma::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.email_my_preference_set('glosas_por_vencer', true, 'semanal');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform app.email_gen_glosas(v_mon + 1, '00000000-0000-4000-8000-000000000001'::uuid);
      v_n2 := (select count(*) from public.email_queue where recipient_id = v_ma::uuid);
      perform app.email_gen_glosas(v_mon, '00000000-0000-4000-8000-000000000001'::uuid);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-36 · Frecuencia semanal: solo los lunes (martes no sale, lunes sí)','ok',coalesce((v_n2 = 0 and (select count(*) from public.email_queue where recipient_id = v_ma::uuid) = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.organization_users (organization_id, user_id, role_code, is_active) values ('00000000-0000-4000-8000-000000000001'::uuid, v_bad::uuid, 'billing', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-37 · Un usuario con correo inválido no recibe nada y no rompe la cola (devuelve nada)','ok',coalesce((app.email_enqueue(v_bad::uuid, 'glosas_por_vencer', app.email_vars_glosas(v_bad::uuid, v_mon, 3), 'qa:bad', null) is null), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.profiles set is_active = false where id = v_ma::uuid;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-38 · Un usuario inactivo no recibe correos (ni de seguridad)','ok',coalesce((app.email_security_notice(v_ma::uuid, 'Se cambió la clave de su cuenta.') is null), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.email_queue where recipient_id = v_ma::uuid;
      perform app.email_gen_resumen(v_mon, '00000000-0000-4000-8000-000000000001'::uuid);
      v_n2 := (select count(*) from public.email_queue where recipient_id = v_ma::uuid);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.email_my_preference_set('resumen_semanal', true, 'semanal');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform app.email_gen_resumen(v_mon, '00000000-0000-4000-8000-000000000001'::uuid);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-39 · Resumen semanal: apagado por defecto no sale; encendido sale un lunes con conteos y montos','ok',coalesce((v_n2 = 0 and (select count(*) from public.email_queue where recipient_id = v_ma::uuid) = 1 and (select q.body_html like '%RD$ 5,000.00%' and q.body_html like '%Reclamaciones radicadas: <strong>1</strong>%' and q.subject like 'SOFA · Su resumen%' from public.email_queue q where q.recipient_id = v_ma::uuid and q.topic = 'resumen_semanal')), false),'d',(null)::text));
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
      perform public.email_my_preference_set('resumen_semanal', true, 'semanal');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mn, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.email_my_preference_set('resumen_semanal', true, 'semanal');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform app.email_gen_resumen(v_mon + 1, '00000000-0000-4000-8000-000000000001'::uuid);
      v_n2 := (select count(*) from public.email_queue where recipient_id = v_ma::uuid and topic = 'resumen_semanal');
      perform app.email_gen_resumen(v_mon, '00000000-0000-4000-8000-000000000001'::uuid);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-40 · Resumen semanal: un martes no sale, y el médico sin movimiento tampoco (aunque lo activó)','ok',coalesce((v_n2 = 0 and not exists (select 1 from public.email_queue where recipient_id = v_mn::uuid)), false),'d',(null)::text));
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
      perform public.email_my_preference_set('pago_recibido', true, 'inmediato');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.payments (organization_id, ars_id, paid_on, amount, reference) values (v_oa, v_ars, v_t, 700, 'QA-AV-PAGO') returning id into v_pay;
      insert into public.payments (organization_id, ars_id, paid_on, amount, reference) values (v_ob, v_ars, v_t, 300, 'QA-AV-PAGO-B');
      perform app.email_gen_pagos(v_t, 'inmediato', '00000000-0000-4000-8000-000000000001'::uuid);
      v_n2 := (select count(*) from public.email_queue where recipient_id = v_ma::uuid and topic = 'pago_recibido');
      perform app.email_gen_pagos(v_t, 'inmediato', '00000000-0000-4000-8000-000000000001'::uuid);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-41 · Pago recibido inmediato: se encola una vez por pago y solo si el médico lo activó','ok',coalesce((v_n2 = 1 and (select count(*) from public.email_queue where recipient_id = v_ma::uuid and topic = 'pago_recibido') = 1 and not exists (select 1 from public.email_queue where recipient_id = v_mb::uuid and topic = 'pago_recibido') and (select q.body_html like '%RD$ 700.00%' and q.body_html like '%ARS QA Avisos%' and q.body_html not like '%QA-AV-PAGO%' from public.email_queue q where q.recipient_id = v_ma::uuid and q.topic = 'pago_recibido')), false),'d',(null)::text));
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
      perform public.email_my_preference_set('pago_recibido', true, 'diario');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.payments (organization_id, ars_id, paid_on, amount, reference, created_at) values (v_oa, v_ars, v_t - 1, 400, 'QA-AV-D1', (v_t - 1)::timestamp + interval '15 hours');
      perform app.email_gen_pagos(v_t, 'diario', '00000000-0000-4000-8000-000000000001'::uuid);
      v_n2 := (select count(*) from public.email_queue where recipient_id = v_ma::uuid and topic = 'pago_recibido');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-42 · Pago recibido diario: resume los pagos de ayer en un solo correo','ok',coalesce((v_n2 = 1 and (select q.body_html like '%RD$ 400.00%' from public.email_queue q where q.recipient_id = v_ma::uuid and q.topic = 'pago_recibido')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.email_settings set enabled = false where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.email_my_mute_all(true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_id := app.email_security_notice(v_ma::uuid, 'Se cambió la clave de su cuenta.', 'qa:sec1');
      v_id2 := app.email_security_notice(v_ma::uuid, 'Se cambió la clave de su cuenta.', 'qa:sec1');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-43 · El aviso de seguridad se encola aunque los avisos del operador estén apagados y el usuario lo apagó todo','ok',coalesce((v_id is not null and v_id2 is null and (select q.is_critical and not q.track_opens and q.body_html like '%Se cambió la clave%' and q.body_html like '%no se puede apagar%' from public.email_queue q where q.id = v_id)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform app.email_security_notice('01990000-0000-4000-8000-000000000031'::uuid, '   ');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-44 · El aviso de seguridad sin evento se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-44 · El aviso de seguridad sin evento se rechaza','ok',sqlerrm like 'Escriba qué pasó en la cuenta%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_id := app.email_security_notice(v_ma::uuid, 'Acceso <script>alert(1)</script> nuevo', 'qa:sec2');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-45 · Un texto malicioso en el evento sale escapado en el HTML','ok',coalesce(((select q.body_html not like '%<script>alert%' and q.body_html like '%&lt;script&gt;%' from public.email_queue q where q.id = v_id)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.profiles set full_name = '<img src=x onerror=alert(1)>' where id = v_ma::uuid;
      v_id := app.email_security_notice(v_ma::uuid, 'Se cambió la clave de su cuenta.', 'qa:sec3');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-46 · Un nombre de usuario con HTML sale escapado en el correo','ok',coalesce(((select q.body_html not like '%<img src=x%' and q.body_html like '%&lt;img src=x%' from public.email_queue q where q.id = v_id)), false),'d',(null)::text));
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
      v_r := public.email_queue_list();
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adx, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_s := (public.email_queue_list())::text;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-47 · Cola: cada administrador ve solo los correos de su operador','ok',coalesce(((v_r->>'total')::int >= 8 and v_s like '%"total": 2%'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-48 · prep','ok',coalesce((true), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_id := (select id from public.email_queue where recipient_id = v_ma::uuid and operator_id = '00000000-0000-4000-8000-000000000001'::uuid limit 1);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adx, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.email_queue_get(v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-49 · ATAQUE: el administrador de otro operador no abre un correo ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-49 · ATAQUE: el administrador de otro operador no abre un correo ajeno','ok',sqlerrm like 'Correo no encontrado o de otro operador%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_queue_cancel(v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-50 · ATAQUE: no reintenta ni cancela ni lee la bitácora de un correo ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-50 · ATAQUE: no reintenta ni cancela ni lee la bitácora de un correo ajeno','ok',sqlerrm like 'Correo no encontrado o de otro operador%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_log_list(v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-51 · ATAQUE: tampoco la bitácora de un correo ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-51 · ATAQUE: tampoco la bitácora de un correo ajeno','ok',sqlerrm like 'Correo no encontrado o de otro operador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.email_queue_list('volando');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-52 · Un estado de filtro inventado se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-52 · Un estado de filtro inventado se rechaza','ok',sqlerrm like 'Estado no válido%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.email_queue where id is not null;
      v_id := app.email_security_notice(v_ma::uuid, 'Aviso del ciclo completo.', 'qa:ciclo');
      update public.email_queue set max_attempts = 2 where id = v_id;
      v_r := public.email_claim_batch(10);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-53 · Tomar el lote marca «enviando», cuenta el intento y no entrega el token si no hay seguimiento','ok',coalesce(((select q.status = 'enviando' and q.attempts = 1 from public.email_queue q where q.id = v_id) and exists (select 1 from jsonb_array_elements(v_r) x where x->>'id' = v_id::text and x->>'token' is null)), false),'d',(null)::text));
      v_s := public.email_mark_failed(v_id, 'Proveedor caído', false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-54 · Una falla temporal vuelve a pendiente con espera y deja «reintento»','ok',coalesce((v_s = 'pendiente' and (select q.scheduled_for > now() + interval '10 minutes' and q.last_error = 'Proveedor caído' from public.email_queue q where q.id = v_id) and exists (select 1 from public.email_log where queue_id = v_id and event = 'reintento')), false),'d',(null)::text));
      update public.email_queue set scheduled_for = now() where id = v_id;
      perform public.email_claim_batch(10);
      v_s := public.email_mark_failed(v_id, 'Proveedor caído otra vez', false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-55 · Al agotar los intentos queda «fallido»','ok',coalesce((v_s = 'fallido' and (select q.status = 'fallido' and q.attempts = 2 from public.email_queue q where q.id = v_id)), false),'d',(null)::text));
      perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      v_r := public.email_queue_retry(v_id);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-56 · El administrador reintenta un fallido: vuelve a pendiente con los intentos en cero','ok',coalesce(((select q.status = 'pendiente' and q.attempts = 0 and q.last_error is null from public.email_queue q where q.id = v_id)), false),'d',(null)::text));
      perform public.email_claim_batch(10);
      perform public.email_mark_sent(v_id, 'simulado', 'sim-123');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-57 · Marcar enviado registra proveedor, id y hora','ok',coalesce(((select q.status = 'enviado' and q.sent_at is not null and q.provider_message_id = 'sim-123' from public.email_queue q where q.id = v_id)), false),'d',(null)::text));
      begin perform public.email_mark_sent(v_id, 'simulado', 'otra-vez'); v_s := 'se permitió'; exception when others then v_s := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-58 · Marcar enviado dos veces se rechaza','ok',coalesce((v_s like 'Ese correo no está en envío%'), false),'d',(null)::text));
      begin perform public.email_mark_failed(v_id, 'tarde', false); v_s := 'se permitió'; exception when others then v_s := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-59 · Marcar fallido un correo ya enviado se rechaza','ok',coalesce((v_s like 'Ese correo no está en envío%'), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-60 · Ciclo completo: tomar lote, falla temporal con espera, agotar intentos, reintento manual y envío','ok',coalesce((true), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.email_queue where id is not null;
      v_id := app.email_security_notice(v_ma::uuid, 'Aviso de prueba de estados.', 'qa:est1');
      perform public.email_claim_batch(10);
      perform public.email_mark_sent(v_id, 'simulado', 'sim-est');
      begin update public.email_queue set status = 'pendiente' where id = v_id; v_s := 'se permitió'; exception when others then v_s := sqlerrm; end;
      begin update public.email_queue set body_html = '<p>cambiado a mano en la cola</p>' where id = v_id; v_rl := 'se permitió'; exception when others then v_rl := sqlerrm; end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-61 · ATAQUE: un correo enviado no se puede regresar a pendiente ni cambiar su contenido','ok',coalesce((v_s like 'Un correo «enviado» no puede pasar a «pendiente»%' and v_rl like 'El contenido y el destinatario de un correo encolado no se cambian%'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_id := app.email_security_notice(v_ma::uuid, 'Aviso de prueba de destinatario.', 'qa:dest1');
      begin update public.email_queue set recipient_id = v_mb::uuid where id = v_id; v_s := 'se permitió'; exception when others then v_s := sqlerrm; end;
      update public.email_queue set recipient_id = null where id = v_id;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-62 · ATAQUE: no se cambia el destinatario de un correo encolado, pero sí queda sin destinatario si se borra su perfil','ok',coalesce((v_s like 'El contenido y el destinatario de un correo encolado no se cambian%' and (select recipient_id is null from public.email_queue where id = v_id)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.email_queue where id is not null;
      v_id := app.email_security_notice(v_ma::uuid, 'Aviso para cancelar.', 'qa:can1');
      v_id2 := app.email_security_notice(v_ma::uuid, 'Aviso para enviar.', 'qa:can2');
      perform public.email_claim_batch(1);
      update public.email_queue set status = 'pendiente', locked_at = null where id = v_id and status = 'enviando';
      update public.email_queue set status = 'pendiente', locked_at = null where id = v_id2 and status = 'enviando';
      update public.email_queue set status = 'enviando' where id = v_id2;
      update public.email_queue set status = 'enviado', sent_at = now() where id = v_id2;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_queue_cancel(v_id);
      begin perform public.email_queue_cancel(v_id2); v_s := 'se permitió'; exception when others then v_s := sqlerrm; end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-63 · Cancelar: un pendiente se cancela y un enviado no','ok',coalesce((v_r->>'status' = 'cancelado' and v_s like 'Solo se cancelan correos pendientes o fallidos%' and exists (select 1 from public.email_log where queue_id = v_id and event = 'cancelado')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.email_queue where id is not null;
      v_id := app.email_security_notice(v_ma::uuid, 'Aviso de envío interrumpido.', 'qa:stk1');
      perform public.email_claim_batch(1);
      update public.email_queue set locked_at = now() - interval '30 minutes' where id = v_id;
      perform public.email_claim_batch(0);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-64 · Un envío que se quedó «enviando» más de 10 minutos vuelve a la cola','ok',coalesce(((select q.attempts = 2 and q.status = 'enviando' from public.email_queue q where q.id = v_id) and exists (select 1 from public.email_log where queue_id = v_id and event = 'reintento')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.email_queue where id is not null;
      perform app.email_security_notice(v_ma::uuid, 'Aviso uno de lote.', 'qa:lot1');
      perform app.email_security_notice(v_ma::uuid, 'Aviso dos de lote.', 'qa:lot2');
      perform app.email_security_notice(v_mb::uuid, 'Aviso tres de lote.', 'qa:lot3');
      update public.email_queue set scheduled_for = now() + interval '1 day' where dedupe_key = 'qa:lot3';
      v_r := public.email_claim_batch(1);
      v_n2 := jsonb_array_length(public.email_claim_batch(50));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-65 · El lote respeta el límite pedido y nunca entrega correos programados a futuro','ok',coalesce((jsonb_array_length(v_r) = 1 and v_n2 = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.email_settings set enabled = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      delete from public.email_queue where id is not null;
      delete from public.email_preferences where user_id = v_ma::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.email_my_preference_set('resumen_semanal', true, 'semanal');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_open_rate();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform app.email_gen_resumen(v_mon, '00000000-0000-4000-8000-000000000001'::uuid);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-66 · Seguimiento de aperturas apagado por defecto: sin token ni pixel; «sin medición»','ok',coalesce(((v_r->>'medido')::boolean = false and v_r->'porcentaje' = 'null'::jsonb and (select not q.track_opens and q.body_html not like '%sofa-pixel%' from public.email_queue q where q.recipient_id = v_ma::uuid and q.topic = 'resumen_semanal')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.email_settings set enabled = true, track_opens = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      delete from public.email_queue where id is not null;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.email_my_preference_set('resumen_semanal', true, 'semanal');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform app.email_gen_resumen(v_mon, '00000000-0000-4000-8000-000000000001'::uuid);
      v_id2 := app.email_security_notice(v_ma::uuid, 'Aviso de seguridad con seguimiento encendido.', 'qa:trk1');
      select id, open_token into v_id, v_tok from public.email_queue where recipient_id = v_ma::uuid and topic = 'resumen_semanal';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-67 · El resumen lleva el pixel de seguimiento y el aviso de seguridad no','ok',coalesce(((select q.track_opens and q.body_html like '%sofa-pixel:' || q.open_token::text || '%' from public.email_queue q where q.id = v_id) and (select not q.track_opens and q.body_html not like '%sofa-pixel%' from public.email_queue q where q.id = v_id2)), false),'d',(null)::text));
      begin perform public.email_register_open(v_tok); v_s := 'x'; exception when others then v_s := sqlerrm; end;
      v_n2 := (select count(*) from public.email_queue where id = v_id and opened_at is null and open_count = 0);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-68 · Una apertura antes de que el correo se envíe no cuenta','ok',coalesce((v_n2 = 1), false),'d',(null)::text));
      perform public.email_claim_batch(10);
      perform public.email_mark_sent(v_id, 'simulado', 'sim-trk');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-69 · Un token desconocido no registra nada','ok',coalesce((public.email_register_open(gen_random_uuid()) = false), false),'d',(null)::text));
      v_n2 := (case when public.email_register_open(v_tok) then 1 else 0 end) + (case when public.email_register_open(v_tok) then 1 else 0 end);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-70 · La apertura de un correo enviado se registra (la segunda solo suma al conteo)','ok',coalesce((v_n2 = 2 and (select q.open_count = 2 and q.opened_at is not null from public.email_queue q where q.id = v_id) and (select count(*) from public.email_log where queue_id = v_id and event = 'abierto') = 1), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_open_rate();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-71 · Con el seguimiento encendido: el resumen lleva pixel, el de seguridad nunca, y la apertura se mide','ok',coalesce(((v_r->>'medido')::boolean and (v_r->>'porcentaje')::numeric = 100 and (v_r->>'medicos_enviados')::int = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.email_template_save('glosas_por_vencer', 'Asunto', '<p>Hola {{nombre}}, tiene glosas.</p>', 'Hola {{nombre}}, tiene glosas.');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-72 · ATAQUE: el Administrador no edita plantillas (solo el Super Admin)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-72 · ATAQUE: el Administrador no edita plantillas (solo el Super Admin)','ok',sqlerrm like 'Las plantillas las cambia solo el Super Admin%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_template_activate('glosas_por_vencer', 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-73 · ATAQUE: el Administrador no activa versiones de plantillas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-73 · ATAQUE: el Administrador no activa versiones de plantillas','ok',sqlerrm like 'Las plantillas las cambia solo el Super Admin%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.email_template_save('glosas_por_vencer', 'Asunto', '<p>Hola {{nombre}}</p><script>alert(1)</script>', 'Hola {{nombre}} texto largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-74 · ATAQUE: una plantilla con script se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-74 · ATAQUE: una plantilla con script se rechaza','ok',sqlerrm like 'El HTML tiene elementos no permitidos%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_template_save('glosas_por_vencer', 'Asunto', '<p onclick="x()">Hola {{nombre}}</p>', 'Hola {{nombre}} texto largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-75 · ATAQUE: una plantilla con evento onclick se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-75 · ATAQUE: una plantilla con evento onclick se rechaza','ok',sqlerrm like 'El HTML tiene elementos no permitidos%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_template_save('glosas_por_vencer', 'Asunto', '<p>Hola {{nombre}}</p><img src="http://malo.example/p.gif">', 'Hola {{nombre}} texto largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-76 · ATAQUE: una imagen externa (rastreo) se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-76 · ATAQUE: una imagen externa (rastreo) se rechaza','ok',sqlerrm like 'El HTML tiene elementos no permitidos%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_template_save('glosas_por_vencer', 'Asunto', '<p>Hola {{cedula}} y más texto</p>', 'Hola {{nombre}} texto largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-77 · Una variable que no existe se rechaza y se listan las disponibles','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-77 · Una variable que no existe se rechaza y se listan las disponibles','ok',sqlerrm like 'La variable {{cedula}} no existe en este aviso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_template_save('glosas_por_vencer', 'Asunto', '<p>Hola {{ nombre }} y más texto</p>', 'Hola {{nombre}} texto largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-78 · Una llave mal escrita se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-78 · Una llave mal escrita se rechaza','ok',sqlerrm like 'Hay una llave%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_template_save('glosas_por_vencer', E'Asunto\nBcc: x@y.com', '<p>Hola {{nombre}} y más texto</p>', 'Hola {{nombre}} texto largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-79 · Un asunto con salto de línea se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-79 · Un asunto con salto de línea se rechaza','ok',sqlerrm like 'El asunto debe tener entre 1 y 150%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_template_save('glosas_por_vencer', 'Asunto {{detalle_html}}', '<p>Hola {{nombre}} y más texto</p>', 'Hola {{nombre}} texto largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-80 · El asunto no admite variables de detalle','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-80 · El asunto no admite variables de detalle','ok',sqlerrm like 'El asunto no puede llevar variables de detalle%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_template_save('seguridad', 'Asunto', '<p>Hola {{nombre}} y más texto</p>', 'Hola {{nombre}} texto largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-81 · La plantilla de seguridad debe llevar {{evento}}','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-81 · La plantilla de seguridad debe llevar {{evento}}','ok',sqlerrm like 'El aviso de seguridad debe incluir la variable%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_template_save('inventado', 'Asunto', '<p>Hola {{nombre}} y más texto</p>', 'Hola {{nombre}} texto largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-82 · Un aviso que no existe no tiene plantilla','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-82 · Un aviso que no existe no tiene plantilla','ok',sqlerrm like 'Ese aviso no tiene plantilla%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_template_save('glosas_por_vencer', 'SOFA · Atención: {{n_glosas}} glosas', '<p>Versión dos para {{nombre}}: {{n_glosas}}</p>{{detalle_html}}', 'Versión dos para {{nombre}}: {{n_glosas}}', 'Prueba');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_ver := (v_r->>'version')::int;
      v_n2 := (select count(*) from public.email_templates where code = 'glosas_por_vencer' and is_active);
      select r_subject into v_s from app.email_render('glosas_por_vencer', jsonb_build_object('nombre', 'Ana', 'n_glosas', 3));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.email_template_activate('glosas_por_vencer', 1);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-83 · Plantillas versionadas: una nueva versión queda activa, se renderiza y se puede volver a la anterior','ok',coalesce((v_ver = 2 and v_n2 = 1 and v_s = 'SOFA · Atención: 3 glosas' and (select is_active from public.email_templates where code = 'glosas_por_vencer' and version = 1) and not (select is_active from public.email_templates where code = 'glosas_por_vencer' and version = 2)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform app.email_render('glosas_por_vencer', '{}'::jsonb, 99);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-84 · Activar una versión que no existe se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-84 · Activar una versión que no existe se rechaza','ok',sqlerrm like 'No hay plantilla activa%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_templates_list();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-85 · El Administrador ve la lista de plantillas con sus variables','ok',coalesce((jsonb_array_length(v_r) >= 4 and v_r::text like '%n_glosas%'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.glosas set notified_on = v_t - 1, appeal_deadline = v_t + 1 where id = v_g1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_my_preview('glosas_por_vencer');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-86 · Vista previa con datos reales del médico (no es ejemplo) y sin datos de pacientes','ok',coalesce((not (v_r->>'ejemplo')::boolean and v_r->>'html' like '%' || v_f1 || '%' and v_r->>'html' !~* 'SECRETO|MIEMBRO|AUT-' and v_r->>'text' like '%Responda a tiempo%'), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_mx, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_my_preview('pago_recibido');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-87 · Vista previa con datos de EJEMPLO cuando todavía no hay movimiento','ok',coalesce(((v_r->>'ejemplo')::boolean and v_r->>'html' like '%ARS de ejemplo%'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.email_my_preview('resumen_semanal');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-88 · ATAQUE: la vista previa de un aviso que no es de su rol se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-88 · ATAQUE: la vista previa de un aviso que no es de su rol se rechaza','ok',sqlerrm like 'Ese aviso no está disponible para su usuario%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.email_settings_set(null, null, 30);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-89 · Días de anticipación fuera de 1 a 14 se rechazan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-89 · Días de anticipación fuera de 1 a 14 se rechazan','ok',sqlerrm like 'Los días de anticipación de las glosas van de 1 a 14%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.email_settings_set(null, null, null, 0);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-90 · Intentos de envío fuera de 1 a 10 se rechazan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-90 · Intentos de envío fuera de 1 a 10 se rechazan','ok',sqlerrm like 'Los intentos de envío van de 1 a 10%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_settings_set(true, null, 5);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-91 · El administrador enciende los avisos y cambia los días; queda en la bitácora y el proveedor sigue «simulado»','ok',coalesce(((v_r->>'enabled')::boolean and (v_r->>'glosa_days_ahead')::int = 5 and v_r->>'provider' = 'simulado' and v_r->>'nota_proveedor' like '%simulado%' and exists (select 1 from public.audit_log where table_name = 'email_settings' and operation = 'UPDATE')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.email_settings set enabled = false where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      begin perform public.email_generate_now(v_mon); v_s := 'se permitió'; exception when others then v_s := sqlerrm; end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-92 · «Generar ahora» con los avisos apagados se rechaza con instrucción','ok',coalesce((v_s like 'Los avisos están apagados para su operador%'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.email_settings set enabled = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      delete from public.email_queue where id is not null;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_generate_now(v_mon);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-93 · «Generar ahora» con los avisos encendidos devuelve el conteo por tipo y solo del operador','ok',coalesce(((v_r->>'glosas_por_vencer')::int >= 8 and v_r ? 'resumen_semanal' and not exists (select 1 from public.email_queue where operator_id = v_op2)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.email_settings set enabled = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      delete from public.email_queue where id is not null;
      perform app.email_gen_glosas(v_mon, '00000000-0000-4000-8000-000000000001'::uuid);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.email_queue_stats();
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-94 · Estadísticas de la cola: por estado, pendientes viejos y enviados de la semana','ok',coalesce(((v_r->'por_estado'->>'pendiente')::int >= 8 and v_r ? 'fallidos_24h' and (v_r->>'enviados_7d')::int = 0), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform app.email_purge(7);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-95 · La limpieza exige conservar al menos 30 días','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-95 · La limpieza exige conservar al menos 30 días','ok',sqlerrm like 'La limpieza conserva al menos 30 días%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.email_queue where id is not null;
      v_id := app.email_security_notice(v_ma::uuid, 'Aviso viejo enviado.', 'qa:pur1');
      v_id2 := app.email_security_notice(v_ma::uuid, 'Aviso nuevo pendiente.', 'qa:pur2');
      perform public.email_claim_batch(1);
      perform public.email_mark_sent(v_id, 'simulado', 'sim-pur');
      update public.email_queue set sent_at = now() - interval '120 days' where id = v_id;
      v_n2 := app.email_purge(90);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-96 · La limpieza borra enviados y cancelados viejos y conserva los recientes y los pendientes','ok',coalesce((v_n2 = 1 and not exists (select 1 from public.email_queue where id = v_id) and exists (select 1 from public.email_queue where id = v_id2 and status = 'pendiente') and not exists (select 1 from public.email_log where queue_id = v_id)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.email_settings set enabled = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      delete from public.email_queue where id is not null;
      v_n2 := app.email_gen_glosas(v_mon, v_op2);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AV-97 · Los generadores del operador uno no tocan a los del operador dos','ok',coalesce((v_n2 >= 2 and not exists (select 1 from public.email_queue where operator_id = '00000000-0000-4000-8000-000000000001'::uuid)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
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

revoke all on function app.qa_run_tests_avisos() from public, anon, authenticated;
