-- 181 · Suite de la 180 (suscripción y pre-factura, P2). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_suscripcion();
create or replace function app.qa_run_tests_suscripcion()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_a constant uuid := '01800000-0000-4000-8000-000000000001'; v_b constant uuid := '01800000-0000-4000-8000-000000000002'; v_c constant uuid := '01800000-0000-4000-8000-000000000003'; v_d constant uuid := '01800000-0000-4000-8000-000000000004';
  v_pa constant uuid := '01800000-0000-4000-8000-000000000011'; v_pa2 constant uuid := '01800000-0000-4000-8000-000000000012'; v_pb constant uuid := '01800000-0000-4000-8000-000000000013'; v_pc1 constant uuid := '01800000-0000-4000-8000-000000000014'; v_pc2 constant uuid := '01800000-0000-4000-8000-000000000015'; v_pc3 constant uuid := '01800000-0000-4000-8000-000000000016';
  v_sa constant text := '01800000-0000-4000-8000-000000000021'; v_ad constant text := '01800000-0000-4000-8000-000000000022'; v_ops constant text := '01800000-0000-4000-8000-000000000023'; v_bil constant text := '01800000-0000-4000-8000-000000000024'; v_co constant text := '01800000-0000-4000-8000-000000000025';
  v_ma constant text := '01800000-0000-4000-8000-000000000031'; v_sec1 constant text := '01800000-0000-4000-8000-000000000032'; v_mb constant text := '01800000-0000-4000-8000-000000000033'; v_mc constant text := '01800000-0000-4000-8000-000000000034'; v_md constant text := '01800000-0000-4000-8000-000000000035';
  v_ars uuid; v_proc uuid; v_per date; v_sub_a uuid; v_sub_b uuid; v_r jsonb; v_r2 jsonb; v_rl text; v_m1 date; v_m2 date; v_ml int; v_st date; v_rem int; v_ex numeric; v_ex2 numeric;
  v_inv_b uuid; v_inv_c uuid; v_inv_d uuid; v_inv_x uuid; v_exp_a uuid; v_cnt1 int; v_cnt2 int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '180') then
    raise exception 'Falta la migración 180. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.su.sa@sofa.test','x'),(v_ad::uuid,'qa.su.ad@sofa.test','x'),(v_ops::uuid,'qa.su.ops@sofa.test','x'),(v_bil::uuid,'qa.su.bil@sofa.test','x'),(v_co::uuid,'qa.su.co@sofa.test','x'),(v_ma::uuid,'qa.su.ma@sofa.test','x'),(v_sec1::uuid,'qa.su.sec1@sofa.test','x'),(v_mb::uuid,'qa.su.mb@sofa.test','x'),(v_mc::uuid,'qa.su.mc@sofa.test','x'),(v_md::uuid,'qa.su.md@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.su.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_a, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA SU Consultorio A', '00000018001', 'Médico independiente', 'activo', current_date - 90, '8095558001');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_b, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA SU Consultorio B', '00000018002', 'Médico independiente', 'activo', current_date - 90, '8095558002');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_c, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA SU Consultorio C', '00000018003', 'Médico independiente', 'activo', current_date - 90, '8095558003');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_d, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA SU Consultorio D', '00000018004', 'Médico independiente', 'activo', current_date - 90, '8095558004');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_a, 'Dr. A Uno QA', 'Cardiología', true), (v_pa2, v_a, 'Dr. A Dos QA', 'Pediatría', false),
      (v_pb, v_b, 'Dr. B QA', 'Ortopedia', true), (v_pc1, v_c, 'Dr. C Uno QA', 'Urología', true), (v_pc2, v_c, 'Dr. C Dos QA', 'Urología', true), (v_pc3, v_c, 'Dr. C Tres QA', 'Urología', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_co::uuid, 'assistant', true),
      (v_a, v_ma::uuid, 'client', true), (v_a, v_sec1::uuid, 'capturer', true), (v_b, v_mb::uuid, 'client', true), (v_c, v_mc::uuid, 'client', true), (v_d, v_md::uuid, 'client', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec1::uuid, v_pa, v_a, true, true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_su_ars', 'ARS QA Suscripción', 'Contributivo', true) returning id into v_ars;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    v_per := date_trunc('month', current_date)::date;
    v_m1 := v_per; v_m2 := (v_per + interval '1 month')::date; v_ml := v_m2 - v_m1; v_st := least(v_m1 + 14, current_date);
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_ars, v_per, 1, 'borrador') returning id into v_sub_a;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_b, v_pb, v_ars, v_per, 1, 'borrador') returning id into v_sub_b;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-01 · La migración 180 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '180')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-02 · Parámetros sembrados con las reglas del documento: prueba 14 días, datos 30, atraso 1/10/20/60, retención 90, avisos 80 % y 100 %','ok',coalesce(((select value from public.subscription_params where code = 'trial_days') = 14 and (select value from public.subscription_params where code = 'trial_retention_days') = 30 and (select array_agg(value order by value) from public.subscription_params where code in ('overdue_notice_day','overdue_app_notice_day','overdue_readonly_day','overdue_suspend_day')) = array[1,10,20,60]::numeric[] and (select value from public.subscription_params where code = 'cancel_retention_days') = 90 and (select value from public.subscription_params where code = 'usage_warn_pct') = 80 and (select value from public.subscription_params where code = 'export_block_pct') = 100), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-03 · Decisiones abiertas SIN inventar: ITBIS vacío, días para pagar vacío y ninguna escala de descuento por volumen','ok',coalesce(((select value from public.subscription_params where code = 'itbis_rate') is null and (select value from public.subscription_params where code = 'invoice_due_days') is null and not exists (select 1 from public.subscription_volume_discounts)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-04 · Las tablas de suscripción no se tocan por la API: ni anon ni authenticated tienen permisos','ok',coalesce((not has_table_privilege('authenticated', 'public.subscriptions', 'select') and not has_table_privilege('authenticated', 'public.subscription_invoices', 'update') and not has_table_privilege('authenticated', 'public.subscription_invoice_lines', 'insert') and not has_table_privilege('authenticated', 'public.subscription_payments', 'select') and not has_table_privilege('authenticated', 'public.subscription_events', 'select') and not has_table_privilege('authenticated', 'public.subscription_export_requests', 'update') and not has_table_privilege('authenticated', 'public.subscription_params', 'update') and not has_table_privilege('anon', 'public.subscriptions', 'select') and not has_table_privilege('authenticated', 'public.subscription_volume_discounts', 'insert')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-05 · Las 17 funciones públicas de suscripción no están abiertas a anon y sí a authenticated','ok',coalesce(((select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('sub_overview','sub_invoice_list','sub_invoice_generate','sub_invoice_issue','sub_invoice_pay','sub_apply_overdue','sub_start_trial','sub_contract','sub_change_plan','sub_export_set_status','sub_param_set','sub_discount_set','my_subscription','sub_invoice_detail','sub_cancel_request','sub_cancel_undo','sub_export_gate')) = 17 and not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('sub_overview','sub_invoice_list','sub_invoice_generate','sub_invoice_issue','sub_invoice_pay','sub_apply_overdue','sub_start_trial','sub_contract','sub_change_plan','sub_export_set_status','sub_param_set','sub_discount_set','my_subscription','sub_invoice_detail','sub_cancel_request','sub_cancel_undo','sub_export_gate') and (has_function_privilege('anon', p.oid, 'execute') or not has_function_privilege('authenticated', p.oid, 'execute')))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-06 · Las funciones internas (calendario, cálculo, enganche) no se llaman desde la API y son SECURITY DEFINER','ok',coalesce((not has_function_privilege('authenticated', 'app.sub_advance_core(date)', 'execute') and not has_function_privilege('authenticated', 'app.sub_quote(uuid,date,date,date,date)', 'execute') and not has_function_privilege('authenticated', 'app.plan_access(uuid,text)', 'execute') and not has_function_privilege('authenticated', 'app.plan_allows(uuid,text)', 'execute') and not has_function_privilege('anon', 'app.plan_guard(uuid,text,integer,text)', 'execute') and not has_function_privilege('authenticated', 'app.sub_apply_plan(uuid,text,date,text,boolean)', 'execute') and (select bool_and(prosecdef) from pg_proc where pronamespace = 'app'::regnamespace and proname in ('sub_advance_core','sub_quote','plan_access','plan_allows','plan_guard','sub_apply_plan','sub_generate'))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-07 · Cada función nueva de suscripción trae search_path vacío','ok',coalesce((not exists (select 1 from pg_proc p where p.pronamespace in ('app'::regnamespace, 'public'::regnamespace) and (p.proname like 'sub\_%' or p.proname in ('my_subscription','plan_access','guard_sub_export')) and not coalesce('search_path=""' = any (p.proconfig) or 'search_path=' = any (p.proconfig), false))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_start_trial(v_a, 'saas_basico', 'Intento de iniciar una prueba por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-08 · ATAQUE: El Médico no inicia pruebas de suscripción','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-08 · ATAQUE: El Médico no inicia pruebas de suscripción','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-09 · ATAQUE: El Médico no ve el tablero de suscripciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-09 · ATAQUE: El Médico no ve el tablero de suscripciones','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_start_trial(v_a, 'saas_basico', 'Intento de iniciar una prueba por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-10 · ATAQUE: La Secretaria no inicia pruebas de suscripción','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-10 · ATAQUE: La Secretaria no inicia pruebas de suscripción','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-11 · ATAQUE: La Secretaria no ve el tablero de suscripciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-11 · ATAQUE: La Secretaria no ve el tablero de suscripciones','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_start_trial(v_a, 'saas_basico', 'Intento de iniciar una prueba por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-12 · ATAQUE: Operaciones no inicia pruebas de suscripción','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-12 · ATAQUE: Operaciones no inicia pruebas de suscripción','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-13 · ATAQUE: Operaciones no ve el tablero de suscripciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-13 · ATAQUE: Operaciones no ve el tablero de suscripciones','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_start_trial(v_a, 'saas_basico', 'Intento de iniciar una prueba por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-14 · ATAQUE: Facturación no inicia pruebas de suscripción','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-14 · ATAQUE: Facturación no inicia pruebas de suscripción','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-15 · ATAQUE: Facturación no ve el tablero de suscripciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-15 · ATAQUE: Facturación no ve el tablero de suscripciones','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_start_trial(v_a, 'saas_basico', 'Intento de iniciar una prueba por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-16 · ATAQUE: El Comercial no inicia pruebas de suscripción','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-16 · ATAQUE: El Comercial no inicia pruebas de suscripción','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-17 · ATAQUE: El Comercial no ve el tablero de suscripciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-17 · ATAQUE: El Comercial no ve el tablero de suscripciones','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_contract(v_a, 'saas_basico', 'mensual', current_date, true, 'Contratación por cuenta propia con precio de fundador');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-18 · ATAQUE: el Médico no contrata ni se pone un plan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-18 · ATAQUE: el Médico no contrata ni se pone un plan','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_generate(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-19 · ATAQUE: el Médico no genera pre-facturas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-19 · ATAQUE: el Médico no genera pre-facturas','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_apply_overdue();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-20 · ATAQUE: el Médico no aplica el atraso','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-20 · ATAQUE: el Médico no aplica el atraso','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_param_set('overdue_suspend_day', 3650);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-21 · ATAQUE: el Médico no cambia parámetros del calendario de atraso','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-21 · ATAQUE: el Médico no cambia parámetros del calendario de atraso','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_discount_set(2, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-22 · ATAQUE: el Médico no se da descuento por volumen','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-22 · ATAQUE: el Médico no se da descuento por volumen','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_change_plan(v_a, 'saas_avanzado', 'Subo mi plan sin pagar la diferencia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-23 · ATAQUE: el Médico no cambia su plan por esta vía','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-23 · ATAQUE: el Médico no cambia su plan por esta vía','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-24 · ATAQUE: el Médico no lista las pre-facturas de todos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-24 · ATAQUE: el Médico no lista las pre-facturas de todos','ok',sqlerrm like 'Las suscripciones y pre-facturas las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_export_set_status(gen_random_uuid(), 'entregada');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-25 · ATAQUE: el Médico no cambia el estado de una exportación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-25 · ATAQUE: el Médico no cambia el estado de una exportación','ok',sqlerrm like 'Solicitud de exportación no encontrada%','d',left(sqlerrm,120)));
    end;
    begin
      perform 1 from public.subscriptions limit 1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-26 · ATAQUE: el Médico no lee la tabla de suscripciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-26 · ATAQUE: el Médico no lee la tabla de suscripciones','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      perform 1 from public.subscription_invoices limit 1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-27 · ATAQUE: el Médico no lee las pre-facturas por la API','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-27 · ATAQUE: el Médico no lee las pre-facturas por la API','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.subscriptions (organization_id, state) values (v_a, 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-28 · ATAQUE: el Médico no se pone una suscripción activa con INSERT','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-28 · ATAQUE: el Médico no se pone una suscripción activa con INSERT','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      update public.subscriptions set state = 'activa' where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-29 · ATAQUE: el Médico no se reactiva con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-29 · ATAQUE: el Médico no se reactiva con UPDATE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      update public.subscription_invoices set status = 'pagada' where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-30 · ATAQUE: el Médico no marca pagada una pre-factura con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-30 · ATAQUE: el Médico no marca pagada una pre-factura con UPDATE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      delete from public.subscription_events where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-31 · ATAQUE: el Médico no borra su historial de suscripción','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-31 · ATAQUE: el Médico no borra su historial de suscripción','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.subscription_payments (invoice_id, organization_id, amount, paid_on, reference) values (gen_random_uuid(), v_a, 1, current_date, 'XXX');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-32 · ATAQUE: el Médico no se inserta un pago','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-32 · ATAQUE: el Médico no se inserta un pago','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_start_trial(v_a, 'plan_fantasma', 'Prueba con un plan inexistente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-33 · Una prueba con un plan que no existe dice que elija de la lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-33 · Una prueba con un plan que no existe dice que elija de la lista','ok',sqlerrm like 'El plan %plan_fantasma% no existe%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_start_trial('00000000-0000-4000-8000-000000000001'::uuid, 'saas_basico', 'Intento de prueba para la operadora');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-34 · No se inicia prueba a la organización de SOFA','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-34 · No se inicia prueba a la organización de SOFA','ok',sqlerrm like 'Cliente no encontrado%','d',left(sqlerrm,120)));
    end;
    v_r := public.sub_start_trial(v_a, 'saas_intermedio', 'Prueba del consultorio A con datos ficticios');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-35 · El Super Admin inicia la prueba: 14 días, solo datos ficticios, datos conservados 30 días más y el plan elegido desde hoy','ok',coalesce((v_r->>'trial_ends_on' = (current_date + 14)::text and v_r->>'retention_until' = (current_date + 44)::text and (select state from public.subscriptions where organization_id = v_a) = 'prueba' and (select fictitious_only from public.subscriptions where organization_id = v_a) and app.org_plan(v_a) = 'saas_intermedio'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_start_trial(v_a, null, 'Segunda prueba del mismo consultorio A');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-36 · La prueba se inicia una sola vez por cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-36 · La prueba se inicia una sola vez por cliente','ok',sqlerrm like 'Este cliente ya tiene una suscripción%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      insert into public.subscription_invoices (organization_id, subscription_id, number, fiscal, kind, period_start, period_end) select v_a, id, 'PF-X', true, 'mensual', current_date, current_date from public.subscriptions where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-37 · ATAQUE: ninguna pre-factura puede ser fiscal: la restricción de la tabla lo impide (fiscal = true se rechaza hasta con el SQL Editor)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-37 · ATAQUE: ninguna pre-factura puede ser fiscal: la restricción de la tabla lo impide (fiscal = true se rechaza hasta con el SQL Editor)','ok',sqlerrm like '%check constraint%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_subscription();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-38 · El Médico ve su prueba (14 días), el aviso de datos ficticios, ninguna pre-factura y la nota de que no es comprobante fiscal','ok',coalesce((v_r->'subscription'->>'state' = 'prueba' and (v_r->'subscription'->>'trial_days_left')::int = 14 and jsonb_array_length(v_r->'invoices') = 0 and (v_r->'subscription'->>'fictitious_only')::boolean and exists (select 1 from jsonb_array_elements_text(v_r->'alerts') a where a like '%solo datos ficticios%') and v_r->>'fiscal_notice' like '%no son comprobantes fiscales%'), false),'d',(v_r->'alerts')::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform app.sub_advance_core(current_date + 13);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-39 · Día 13 de la prueba: sigue en prueba','ok',coalesce((app.sub_state(v_a) = 'prueba'), false),'d',(null)::text));
      perform app.sub_advance_core(current_date + 15);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-40 · Pasados los 14 días la prueba pasa a «pendiente de pago»','ok',coalesce((app.sub_state(v_a) = 'pendiente_pago'), false),'d',(null)::text));
      perform app.sub_advance_core(current_date + 44);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-41 · Dentro de los 30 días de conservación sigue pendiente de pago','ok',coalesce((app.sub_state(v_a) = 'pendiente_pago'), false),'d',(null)::text));
      perform app.sub_advance_core(current_date + 46);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-42 · Pasados los 30 días queda suspendida y sus datos siguen ahí (no se borró nada)','ok',coalesce((app.sub_state(v_a) = 'suspendida' and exists (select 1 from public.providers where id = v_pa) and exists (select 1 from public.submissions where id = v_sub_a) and exists (select 1 from public.organizations where id = v_a)), false),'d',(null)::text));
      select count(*) into v_n from public.subscription_events where organization_id = v_a and event = 'cambio_de_estado';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-43 · Cada cambio de estado deja su evento en la bitácora (prueba→pendiente→suspendida)','ok',coalesce((v_n = 2), false),'d',(null)::text));
      v_r := app.sub_advance_core(current_date + 46);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-44 · Correr el calendario otra vez el mismo día no cambia nada (idempotente)','ok',coalesce((jsonb_array_length(v_r->'cambios') = 0), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_contract(v_b, 'saas_intermedio', 'semanal', current_date, false, 'Contratación del consultorio B, ciclo raro');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-45 · Contratar con un ciclo inválido dice las opciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-45 · Contratar con un ciclo inválido dice las opciones','ok',sqlerrm like 'El ciclo de cobro es%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_contract(v_b, 'saas_intermedio', 'mensual', current_date, false, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-46 · Contratar con motivo corto se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-46 · Contratar con motivo corto se rechaza','ok',sqlerrm like 'Escriba el motivo o las condiciones%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_contract(v_b, 'servicio_basico', 'anual', current_date, false, 'Contratación anual de un plan de servicio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-47 · Un plan sin precio anual no se contrata anual (los de servicio no lo tienen) y dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-47 · Un plan sin precio anual no se contrata anual (los de servicio no lo tienen) y dice qué hacer','ok',sqlerrm like 'El plan %no tiene precio anual%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_contract(v_b, 'legado', 'mensual', current_date, false, 'Contratación del plan legado sin precio');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-48 · El plan Fundador/Legado no tiene precio: no se contrata (cuota sin precio)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-48 · El plan Fundador/Legado no tiene precio: no se contrata (cuota sin precio)','ok',sqlerrm like 'El plan %no tiene precio mensual%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_contract(v_b, 'saas_intermedio', 'mensual', current_date - 90, false, 'Contratación con fecha muy atrasada');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-49 · La fecha de inicio del cobro no puede ser de hace meses','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-49 · La fecha de inicio del cobro no puede ser de hace meses','ok',sqlerrm like 'La fecha de inicio del cobro debe estar%','d',left(sqlerrm,120)));
    end;
    v_r := public.sub_contract(v_b, 'saas_intermedio', 'mensual', v_st, false, 'Contratación del consultorio B, plan Intermedio SaaS');
    v_inv_b := (v_r->>'invoice_id')::uuid;
    v_ex := round(2900 * 1 * (v_m2 - v_st)::numeric / v_ml, 2);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-50 · La primera cuota se prorratea por días: precio × médicos activos × días del período / días del mes (borrador, número interno PF-, no fiscal)','ok',coalesce(((select total from public.subscription_invoices where id = v_inv_b) = v_ex and (select status from public.subscription_invoices where id = v_inv_b) = 'borrador' and (select number from public.subscription_invoices where id = v_inv_b) ~ '^PF-[0-9]{4}-[0-9]{6}$' and not (select fiscal from public.subscription_invoices where id = v_inv_b) and (select kind from public.subscription_invoices where id = v_inv_b) = 'alta' and (select days from public.subscription_invoice_lines where invoice_id = v_inv_b) = (v_m2 - v_st) and (select days_in_period from public.subscription_invoice_lines where invoice_id = v_inv_b) = v_ml), false),'d',((select total from public.subscription_invoices where id = v_inv_b)::text || ' vs ' || v_ex::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-51 · La suscripción nace «pendiente de pago» con ciclo mensual y el cobro empieza en la fecha indicada','ok',coalesce(((select state from public.subscriptions where organization_id = v_b) = 'pendiente_pago' and (select cycle from public.subscriptions where organization_id = v_b) = 'mensual' and (select billing_start_on from public.subscriptions where organization_id = v_b) = v_st and (select next_billing_on from public.subscriptions where organization_id = v_b) = v_m2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.subscriptions set state = 'activa' where organization_id = v_b;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_contract(v_b, 'saas_avanzado', 'mensual', current_date, false, 'Segunda contratación del mismo cliente B');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-52 · Contratar dos veces un cliente que ya pasó a activa se rechaza (use Cambiar plan)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-52 · Contratar dos veces un cliente que ya pasó a activa se rechaza (use Cambiar plan)','ok',sqlerrm like 'La suscripción de este cliente está%Cambiar plan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.subscriptions set state = 'pendiente_pago' where organization_id = v_b;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_inv_x := public.sub_invoice_generate(v_b, v_m1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-53 · Pedir otra vez el mismo período de la cuota de alta recalcula ese mismo borrador (no crea otra pre-factura)','ok',coalesce((v_inv_x = v_inv_b and (select count(*) from public.subscription_invoices where organization_id = v_b) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_invoice_generate(v_b, v_m1 + 3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-54 · Una fecha de período que no es día 1 se rechaza en ciclo mensual','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-54 · Una fecha de período que no es día 1 se rechaza en ciclo mensual','ok',sqlerrm like 'En el ciclo mensual el período empieza el día 1%','d',left(sqlerrm,120)));
    end;
    v_r := public.sub_invoice_detail(v_inv_b);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-55 · El administrador ve el detalle de la pre-factura: líneas con precio, médicos, días y monto, y la nota de documento NO fiscal','ok',coalesce((jsonb_array_length(v_r->'lines') = 1 and (v_r->'lines'->0->>'unit_price')::numeric = 2900 and (v_r->'lines'->0->>'providers')::int = 1 and (v_r->>'fiscal')::boolean = false and v_r->>'fiscal_notice' like '%NO fiscal%'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_subscription();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-56 · El Médico NO ve su pre-factura mientras es borrador (solo lo emitido)','ok',coalesce((jsonb_array_length(v_r->'invoices') = 0 and (v_r->'subscription'->>'state') = 'pendiente_pago'), false),'d',(v_r->'invoices')::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_invoice_detail(v_inv_b);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-57 · ATAQUE: el Médico no abre el borrador de su pre-factura por su identificador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-57 · ATAQUE: el Médico no abre el borrador de su pre-factura por su identificador','ok',sqlerrm like 'No encontramos esa pre-factura%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_invoice_issue(v_inv_b);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-58 · Emitir sin fecha de vencimiento: pide la fecha (los días para pagar son una decisión abierta)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-58 · Emitir sin fecha de vencimiento: pide la fecha (los días para pagar son una decisión abierta)','ok',sqlerrm like 'Indique la fecha de vencimiento%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_issue(v_inv_b, current_date - 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-59 · Una fecha de vencimiento pasada se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-59 · Una fecha de vencimiento pasada se rechaza','ok',sqlerrm like 'La fecha de vencimiento no puede estar en el pasado%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_issue(v_inv_b, current_date + 10, 'E31<script>');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-60 · El número del comprobante externo con caracteres raros se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-60 · El número del comprobante externo con caracteres raros se rechaza','ok',sqlerrm like 'El número del comprobante externo usa%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_pay(v_inv_b, 1, current_date, 'TRF-0001');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-61 · Registrar un pago en un borrador se rechaza y dice que se emita primero','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-61 · Registrar un pago en un borrador se rechaza y dice que se emita primero','ok',sqlerrm like 'La pre-factura % sigue en borrador%','d',left(sqlerrm,120)));
    end;
    v_r := public.sub_invoice_issue(v_inv_b, current_date + 10, 'E310000000123');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-62 · Emitida: pasa a «emitida_externa» con el número del comprobante fiscal externo y el aviso de que SOFA no lo emite','ok',coalesce(((select status from public.subscription_invoices where id = v_inv_b) = 'emitida_externa' and (select external_ref from public.subscription_invoices where id = v_inv_b) = 'E310000000123' and v_r->>'message' like '%NO es el comprobante fiscal%'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_invoice_issue(v_inv_b, current_date + 10);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-63 · Emitir dos veces la misma pre-factura se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-63 · Emitir dos veces la misma pre-factura se rechaza','ok',sqlerrm like 'La pre-factura % ya está emitida externa%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_generate(v_b, v_m1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-64 · Regenerar una pre-factura ya emitida se rechaza (no se duplica ni se pisa)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-64 · Regenerar una pre-factura ya emitida se rechaza (no se duplica ni se pisa)','ok',sqlerrm like 'Ya existe la pre-factura %','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      update public.subscription_invoices set total = 1 where id = v_inv_b;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-65 · ATAQUE: no se cambia el monto de una pre-factura emitida (ni siquiera con el SQL Editor)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-65 · ATAQUE: no se cambia el monto de una pre-factura emitida (ni siquiera con el SQL Editor)','ok',sqlerrm like 'La pre-factura % ya fue emitida: no se cambian sus montos%','d',left(sqlerrm,120)));
    end;
    begin
      update public.subscription_invoices set number = 'PF-9999-000001' where id = v_inv_b;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-66 · ATAQUE: no se cambia el número de una pre-factura emitida','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-66 · ATAQUE: no se cambia el número de una pre-factura emitida','ok',sqlerrm like 'La pre-factura % ya fue emitida%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.subscription_invoice_lines (invoice_id, concept, amount) values (v_inv_b, 'Cargo escondido', 5000);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-67 · ATAQUE: no se agregan líneas a una pre-factura emitida','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-67 · ATAQUE: no se agregan líneas a una pre-factura emitida','ok',sqlerrm like 'Las líneas de una pre-factura emitida no se modifican%','d',left(sqlerrm,120)));
    end;
    begin
      delete from public.subscription_invoice_lines where invoice_id = v_inv_b;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-68 · ATAQUE: no se borran las líneas de una pre-factura emitida','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-68 · ATAQUE: no se borran las líneas de una pre-factura emitida','ok',sqlerrm like 'Las líneas de una pre-factura emitida no se modifican%','d',left(sqlerrm,120)));
    end;
    begin
      update public.subscription_invoices set status = 'borrador' where id = v_inv_b;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-69 · ATAQUE: una pre-factura emitida no vuelve a borrador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-69 · ATAQUE: una pre-factura emitida no vuelve a borrador','ok',sqlerrm like 'Una pre-factura emitida no vuelve a borrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_subscription();
    v_r2 := public.sub_invoice_detail(v_inv_b);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-70 · El Médico ya ve su pre-factura emitida (con vencimiento y comprobante externo) y su detalle, sin la nota interna','ok',coalesce((jsonb_array_length(v_r->'invoices') = 1 and v_r->'invoices'->0->>'status' = 'emitida_externa' and v_r->'invoices'->0->>'due_on' = (current_date + 10)::text and v_r2->>'external_ref' = 'E310000000123' and v_r2->>'note' is null), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_invoice_pay(v_inv_b, 1, current_date, '  ');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-71 · El pago exige referencia','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-71 · El pago exige referencia','ok',sqlerrm like 'Escriba la referencia del pago%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_pay(v_inv_b, 0, current_date, 'TRF-0001');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-72 · El pago no puede ser cero o negativo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-72 · El pago no puede ser cero o negativo','ok',sqlerrm like 'El monto del pago debe ser mayor que cero%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_pay(v_inv_b, 999999, current_date, 'TRF-0001');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-73 · El pago no puede superar el saldo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-73 · El pago no puede superar el saldo','ok',sqlerrm like 'El pago % es mayor que el saldo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_pay(v_inv_b, 1, current_date + 2, 'TRF-0001');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-74 · La fecha del pago no puede ser futura','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-74 · La fecha del pago no puede ser futura','ok',sqlerrm like 'La fecha del pago no puede ser futura%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_invoice_pay(v_inv_b, 1, current_date, 'TRF-0001', 'bitcoin');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-75 · El método de pago debe ser uno de la lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-75 · El método de pago debe ser uno de la lista','ok',sqlerrm like 'El método de pago es%','d',left(sqlerrm,120)));
    end;
    v_ex2 := round(v_ex / 2, 2);
    v_r := public.sub_invoice_pay(v_inv_b, v_ex2, current_date, 'TRF-0001', 'transferencia');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-76 · Un pago parcial deja saldo, la pre-factura sigue emitida y la suscripción NO se activa todavía','ok',coalesce((v_r->>'status' = 'emitida_externa' and (v_r->>'balance')::numeric = (select total from public.subscription_invoices where id = v_inv_b) - v_ex2 and app.sub_state(v_b) = 'pendiente_pago' and (select converted_on from public.subscriptions where organization_id = v_b) is null), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_ex2 := (select total - amount_paid from public.subscription_invoices where id = v_inv_b);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.sub_invoice_pay(v_inv_b, v_ex2, current_date, 'TRF-0002', 'deposito');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-77 · Al cubrir el saldo queda «pagada», la suscripción pasa a ACTIVA y se anota la fecha de conversión','ok',coalesce((v_r->>'status' = 'pagada' and app.sub_state(v_b) = 'activa' and (select converted_on from public.subscriptions where organization_id = v_b) = current_date and (select paid_on from public.subscription_invoices where id = v_inv_b) = current_date and (select count(*) from public.subscription_payments where invoice_id = v_inv_b) = 2), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_invoice_pay(v_inv_b, 10, current_date, 'TRF-0003');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-78 · Una pre-factura pagada no recibe más pagos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-78 · Una pre-factura pagada no recibe más pagos','ok',sqlerrm like 'La pre-factura % ya está pagada%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-79 · Los pagos y las emisiones quedan en la bitácora de eventos y en la auditoría general','ok',coalesce(((select count(*) from public.subscription_events where organization_id = v_b and event = 'pago_registrado') = 2 and exists (select 1 from public.subscription_events where organization_id = v_b and event = 'prefactura_emitida') and exists (select 1 from public.audit_log where table_name = 'subscription_invoices' and operation = 'INSERT' and organization_id = v_b)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.my_subscription(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-80 · ATAQUE: el Médico B no ve la suscripción del consultorio A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-80 · ATAQUE: el Médico B no ve la suscripción del consultorio A','ok',sqlerrm like 'No tiene acceso a la suscripción de ese consultorio%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_export_gate(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-81 · ATAQUE: el Médico B no consulta el cupo de exportación del consultorio A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-81 · ATAQUE: el Médico B no consulta el cupo de exportación del consultorio A','ok',sqlerrm like 'No tiene acceso a ese consultorio%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.my_subscription(v_b);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-82 · ATAQUE: Operaciones no ve la suscripción (dinero) de un cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-82 · ATAQUE: Operaciones no ve la suscripción (dinero) de un cliente','ok',sqlerrm like 'No tiene acceso a la suscripción%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_invoice_detail(v_inv_b);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-83 · ATAQUE: el Médico A no abre una pre-factura del consultorio B','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-83 · ATAQUE: el Médico A no abre una pre-factura del consultorio B','ok',sqlerrm like 'No encontramos esa pre-factura%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.my_subscription(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-84 · ATAQUE: la Secretaria no ve la suscripción del consultorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-84 · ATAQUE: la Secretaria no ve la suscripción del consultorio','ok',sqlerrm like 'No tiene acceso a la suscripción%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_cancel_request(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-85 · ATAQUE: la Secretaria no pide la cancelación del consultorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-85 · ATAQUE: la Secretaria no pide la cancelación del consultorio','ok',sqlerrm like 'Solo el médico del consultorio o la Administración%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_discount_set(1, 10);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-86 · Escala de descuento: desde 2 médicos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-86 · Escala de descuento: desde 2 médicos','ok',sqlerrm like 'La escala empieza desde 2 médicos%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_discount_set(3, 150);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-87 · Escala de descuento: porcentaje entre 0 y 100','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-87 · Escala de descuento: porcentaje entre 0 y 100','ok',sqlerrm like 'El descuento es un porcentaje entre 0 y 100%','d',left(sqlerrm,120)));
    end;
    v_r := public.sub_contract(v_c, 'servicio_basico', 'mensual', v_m1, false, 'Contratación del consultorio C, tres médicos');
    v_inv_c := (v_r->>'invoice_id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-88 · Con 3 médicos activos y SIN escala cargada la cuota es 4,500 × 3 = 13,500 y no hay descuento ni ITBIS (decisiones abiertas)','ok',coalesce(((select subtotal from public.subscription_invoices where id = v_inv_c) = 13500 and (select discount_pct from public.subscription_invoices where id = v_inv_c) = 0 and (select itbis_amount from public.subscription_invoices where id = v_inv_c) is null and (select total from public.subscription_invoices where id = v_inv_c) = 13500), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform public.sub_discount_set(3, 10);
    perform public.sub_discount_set(5, 15);
    v_inv_x := public.sub_invoice_generate(v_c, v_m1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-89 · Con la escala «3 médicos o más: 10 %» el borrador se recalcula: descuento 1,350 y total 12,150','ok',coalesce(((select discount_pct from public.subscription_invoices where id = v_inv_c) = 10 and (select discount_amount from public.subscription_invoices where id = v_inv_c) = 1350 and (select total from public.subscription_invoices where id = v_inv_c) = 12150 and (select count(*) from public.subscription_invoices where organization_id = v_c) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_param_set('itbis', 18);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-90 · Los parámetros no admiten un código desconocido','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-90 · Los parámetros no admiten un código desconocido','ok',sqlerrm like 'Parámetro desconocido%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_param_set('itbis_rate', 180);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-91 · Los porcentajes no pasan de 100','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-91 · Los porcentajes no pasan de 100','ok',sqlerrm like 'Un porcentaje no puede pasar de 100%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_param_set('trial_days', 2.5);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-92 · Los días son enteros y no quedan vacíos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-92 · Los días son enteros y no quedan vacíos','ok',sqlerrm like 'Este parámetro es un número entero%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_param_set('overdue_readonly_day', 5);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-93 · El calendario de atraso debe ir en orden (solo lectura antes del aviso en la app se rechaza)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-93 · El calendario de atraso debe ir en orden (solo lectura antes del aviso en la app se rechaza)','ok',sqlerrm like 'El calendario de atraso debe ir en orden%','d',left(sqlerrm,120)));
    end;
    perform public.sub_param_set('itbis_rate', 18);
    v_inv_x := public.sub_invoice_generate(v_c, v_m1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-94 · Con ITBIS 18 % cargado: base 12,150, ITBIS 2,187 y total 14,337','ok',coalesce(((select itbis_rate from public.subscription_invoices where id = v_inv_c) = 18 and (select itbis_amount from public.subscription_invoices where id = v_inv_c) = 2187 and (select total from public.subscription_invoices where id = v_inv_c) = 14337), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform public.sub_param_set('itbis_rate', null);
    perform public.sub_discount_set(5, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-95 · Quitar una escala (porcentaje vacío) la elimina y deja la otra','ok',coalesce((not exists (select 1 from public.subscription_volume_discounts where min_doctors = 5) and exists (select 1 from public.subscription_volume_discounts where min_doctors = 3)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.sub_param_set('invoice_due_days', 15);
      v_r := public.sub_invoice_issue(v_inv_c);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-96 · Con «días para pagar» definido en 15, emitir sin fecha vence a 15 días','ok',coalesce(((select due_on from public.subscription_invoices where id = v_inv_c) = current_date + 15), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.sub_contract(v_d, 'saas_basico', 'mensual', v_m1, false, 'Contratación del consultorio D sin médicos todavía');
    v_inv_d := (v_r->>'invoice_id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-97 · Sin médicos activos la cuota es cero','ok',coalesce(((select total from public.subscription_invoices where id = v_inv_d) = 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_invoice_issue(v_inv_d, current_date + 5);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-98 · No se emite una pre-factura con total cero y dice qué revisar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-98 · No se emite una pre-factura con total cero y dice qué revisar','ok',sqlerrm like 'La pre-factura % tiene total cero%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.providers (organization_id, full_name, specialty, is_active) values (v_d, 'Dr. D QA', 'Urología', true);
      delete from public.subscription_invoice_lines where invoice_id = v_inv_d;
      delete from public.subscription_invoices where id = v_inv_d;
      delete from public.subscriptions where organization_id = v_d;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.sub_contract(v_d, 'saas_intermedio', 'anual', current_date, false, 'Contratación anual del consultorio D');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-99 · Ciclo anual: precio anual 29,000 × 1 médico, el período dura un año completo y el siguiente cobro es al año','ok',coalesce(((select total from public.subscription_invoices where id = (v_r->>'invoice_id')::uuid) = 29000 and (select kind from public.subscription_invoices where id = (v_r->>'invoice_id')::uuid) = 'alta' and (select period_end from public.subscription_invoices where id = (v_r->>'invoice_id')::uuid) = (current_date + interval '1 year')::date - 1 and (select next_billing_on from public.subscriptions where organization_id = v_d) = (current_date + interval '1 year')::date), false),'d',((select total::text || ' ' || kind || ' ' || period_end::text from public.subscription_invoices where id = (v_r->>'invoice_id')::uuid) || ' ' || (select next_billing_on::text from public.subscriptions where organization_id = v_d))::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      select count(*) into v_cnt1 from public.providers where organization_id = v_b;
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_b, v_b, v_per + 3, 'Paciente QA B1', v_proc, 1, 100);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_inv_x := public.sub_invoice_generate(v_b, v_m2);
      perform public.sub_invoice_issue(v_inv_x, current_date, 'E310000000200');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_r := app.sub_advance_core(current_date);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-100 · El día del vencimiento todavía no hay atraso: la suscripción sigue activa','ok',coalesce((app.sub_state(v_b) = 'activa' and (select status from public.subscription_invoices where id = v_inv_x) = 'emitida_externa'), false),'d',(null)::text));
      v_r := app.sub_advance_core(current_date + 1);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-101 · Día 1 de atraso: la pre-factura queda vencida, la suscripción pasa a «pendiente de pago» y el nivel es aviso','ok',coalesce(((select status from public.subscription_invoices where id = v_inv_x) = 'vencida' and app.sub_state(v_b) = 'pendiente_pago' and app.sub_overdue(v_b, current_date + 1)->>'level' = 'aviso' and (app.sub_overdue(v_b, current_date + 1)->>'days')::int = 1), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform app.sub_advance_core(current_date + 10);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-102 · Día 10: aviso dentro de la app (todavía puede trabajar con normalidad)','ok',coalesce((app.sub_state(v_b) = 'pendiente_pago' and app.sub_overdue(v_b, current_date + 10)->>'level' = 'aviso_app' and app.sub_overdue(v_b, current_date + 10)->>'message' like '%solo lectura%'), false),'d',(null)::text));
      perform app.sub_advance_core(current_date + 19);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-103 · Día 19 todavía no es solo lectura','ok',coalesce((app.sub_state(v_b) = 'pendiente_pago'), false),'d',(null)::text));
      perform app.sub_advance_core(current_date + 20);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-104 · Día 20: solo lectura','ok',coalesce((app.sub_state(v_b) = 'solo_lectura'), false),'d',(null)::text));
      perform app.sub_advance_core(current_date + 59);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-105 · Día 59 sigue en solo lectura','ok',coalesce((app.sub_state(v_b) = 'solo_lectura'), false),'d',(null)::text));
      perform app.sub_advance_core(current_date + 60);
      select count(*) into v_cnt2 from public.providers where organization_id = v_b;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-106 · Día 60: suspendida, SIN borrar datos (médicos, reclamaciones, pre-facturas y pagos intactos)','ok',coalesce((app.sub_state(v_b) = 'suspendida' and v_cnt1 = v_cnt2 and exists (select 1 from public.service_lines where submission_id = v_sub_b and patient_name = 'Paciente QA B1') and exists (select 1 from public.subscription_invoices where id = v_inv_b) and (select count(*) from public.subscription_payments where invoice_id = v_inv_b) = 2), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_ex2 := (select total from public.subscription_invoices where id = v_inv_x);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.sub_invoice_pay(v_inv_x, v_ex2, current_date, 'TRF-0100');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-107 · Al registrar el pago la cuenta suspendida se reactiva sola (activa, sin más pasos)','ok',coalesce((v_r->>'status' = 'pagada' and app.sub_state(v_b) = 'activa'), false),'d',(v_r::text)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.sub_apply_overdue();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-108 · «Aplicar atraso» del administrador corre el calendario y responde qué cambió','ok',coalesce((v_r ? 'cambios' and v_r ? 'borradores_generados'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      select count(*) into v_cnt1 from public.subscription_invoices where organization_id = v_b;
      perform app.sub_advance_core(v_m2);
      select count(*) into v_cnt2 from public.subscription_invoices where organization_id = v_b;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-109 · El calendario genera el borrador del período siguiente de las suscripciones activas (y no lo duplica al correr de nuevo)','ok',coalesce((v_cnt2 = v_cnt1 + 1 and (select status from public.subscription_invoices where organization_id = v_b and period_start = v_m2) = 'borrador'), false),'d',(null)::text));
      perform app.sub_advance_core(v_m2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-110 · Correr el calendario de nuevo no duplica el borrador','ok',coalesce(((select count(*) from public.subscription_invoices where organization_id = v_b and period_start = v_m2) = 1), false),'d',(null)::text));
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
      v_inv_x := public.sub_invoice_generate(v_b, v_m2);
      perform public.sub_invoice_issue(v_inv_x, current_date, 'E310000000201');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.subscription_invoices set status = 'vencida', due_on = current_date - 1 where id = v_inv_x;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.my_subscription();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-111 · Día 1: el Médico ve su aviso de atraso con a quién contactar y qué hacer (pagar y enviar la referencia)','ok',coalesce((v_r->'overdue'->>'level' = 'aviso' and exists (select 1 from jsonb_array_elements_text(v_r->'alerts') a where a like '%vencida%Pague y envíe la referencia del pago a SOFA%')), false),'d',(v_r->'alerts')::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.subscription_invoices set due_on = current_date - 10 where id = v_inv_x;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.my_subscription();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-112 · Día 10: el aviso dentro de la app dice cuántos días le quedan antes del solo lectura','ok',coalesce((v_r->'overdue'->>'level' = 'aviso_app' and exists (select 1 from jsonb_array_elements_text(v_r->'alerts') a where a like '%A los 20 días su cuenta pasa a solo lectura (le quedan 10)%')), false),'d',(v_r->'alerts')::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.subscription_invoices set due_on = current_date - 20 where id = v_inv_x;
      perform app.sub_advance_core(current_date);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.my_subscription();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-113 · Día 20: la cuenta pasa a solo lectura y el Médico lo ve con el aviso de cómo reactivarla','ok',coalesce((v_r->'subscription'->>'state' = 'solo_lectura' and exists (select 1 from jsonb_array_elements_text(v_r->'alerts') a where a like 'Su cuenta está en solo lectura%')), false),'d',(v_r->'alerts')::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_change_plan(v_b, 'saas_intermedio', 'Cambio al mismo plan que ya tiene');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-114 · Cambiar al mismo plan se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-114 · Cambiar al mismo plan se rechaza','ok',sqlerrm like 'Ese cliente ya está en el plan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_change_plan(v_b, 'saas_avanzado', 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-115 · Cambiar de plan exige motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-115 · Cambiar de plan exige motivo','ok',sqlerrm like 'Escriba el motivo del cambio de plan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.sub_change_plan(v_b, 'plan_fantasma', 'Cambio a un plan que no existe');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-116 · Cambiar a un plan inexistente dice que elija de la lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-116 · Cambiar a un plan inexistente dice que elija de la lista','ok',sqlerrm like 'El plan %plan_fantasma% no existe%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.subscriptions set state = 'pendiente_pago' where organization_id = v_b;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_change_plan(v_b, 'saas_avanzado', 'Cambio de plan con pago pendiente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-117 · Un cliente que no está al día no cambia de plan hasta pagar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-117 · Un cliente que no está al día no cambia de plan hasta pagar','ok',sqlerrm like 'La suscripción está%Regularice el pago%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.subscriptions set state = 'activa' where organization_id = v_b;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rem := (select period_end from public.subscriptions where organization_id = v_b) - current_date + 1;
    v_ex := round(4900 * 1 * v_rem::numeric / v_ml, 2) - round(2900 * 1 * v_rem::numeric / v_ml, 2);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.sub_change_plan(v_b, 'saas_avanzado', 'Sube al plan Avanzado por el tablero de dirección');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-118 · Subir de plan es INSTANTÁNEO y se cobra la diferencia prorrateada por los días que faltan (borrador «cambio_plan» con crédito del plan anterior)','ok',coalesce((v_r->>'mode' = 'inmediato' and app.org_plan(v_b) = 'saas_avanzado' and (select total from public.subscription_invoices where id = (v_r->>'invoice_id')::uuid) = v_ex and (select kind from public.subscription_invoices where id = (v_r->>'invoice_id')::uuid) = 'cambio_plan' and (select count(*) from public.subscription_invoice_lines where invoice_id = (v_r->>'invoice_id')::uuid) = 2 and (select min(amount) from public.subscription_invoice_lines where invoice_id = (v_r->>'invoice_id')::uuid) < 0), false),'d',(v_r::text || ' esperado ' || v_ex::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.sub_change_plan(v_b, 'saas_intermedio', 'Baja al Intermedio el mes que viene');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-119 · Bajar de plan NO es inmediato: queda programado para el mes siguiente y hoy sigue con el plan actual','ok',coalesce((v_r->>'mode' = 'programado' and v_r->>'starts_on' = v_m2::text and app.org_plan(v_b) = 'saas_avanzado' and (select pending_plan_code from public.subscriptions where organization_id = v_b) = 'saas_intermedio' and (select pending_plan_from from public.subscriptions where organization_id = v_b) = v_m2), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_subscription();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-120 · El Médico ve el aviso de la bajada programada (fecha y que las pantallas pasarán a solo lectura)','ok',coalesce((v_r->'subscription'->'pending_plan'->>'code' = 'saas_intermedio' and exists (select 1 from jsonb_array_elements_text(v_r->'alerts') a where a like '%entra el%pasarán a solo lectura%')), false),'d',(v_r->'alerts')::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform app.sub_advance_core(v_m2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-121 · Al llegar el mes siguiente se aplica la bajada: el plan nuevo entra ese día y la bajada programada desaparece','ok',coalesce((app.org_plan(v_b, v_m2) = 'saas_intermedio' and (select pending_plan_code from public.subscriptions where organization_id = v_b) is null and exists (select 1 from public.subscription_events where organization_id = v_b and event = 'bajada_de_plan_aplicada')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.organization_plans where organization_id = v_b;
      insert into public.organization_plans (organization_id, plan_code, starts_on, ends_on, status) values (v_b, 'saas_avanzado', current_date - 40, current_date - 1, 'finalizado'), (v_b, 'saas_intermedio', current_date, null, 'activo');
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-122 · Tras bajar de Avanzado a Intermedio, las pantallas del Avanzado que el Intermedio no incluye quedan en SOLO LECTURA (no desaparecen)','ok',coalesce((app.plan_access(v_b, 'tablero_direccion') = 'solo_lectura' and app.plan_access(v_b, 'conciliacion_pagos') = 'completo' and not app.plan_allows(v_b, 'tablero_direccion') and app.plan_allows(v_b, 'conciliacion_pagos')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-123 · Una pantalla que ninguno de los dos planes incluye sigue bloqueada, no en lectura','ok',coalesce((app.plan_access(v_b, 'historia_clinica') = 'bloqueado' and not app.plan_allows(v_b, 'historia_clinica')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      update public.subscriptions set state = 'solo_lectura' where organization_id = v_b;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated')::text, true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_b, v_b, v_per + 3, 'Paciente QA X', v_proc, 1, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-124 · Con el interruptor encendido, un cliente en solo lectura no agrega reclamaciones y el mensaje dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-124 · Con el interruptor encendido, un cliente en solo lectura no agrega reclamaciones y el mensaje dice qué hacer','ok',sqlerrm like 'Su cuenta está en solo lectura%SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.providers (organization_id, full_name, specialty) values (v_b, 'Dr. Nuevo QA', 'Urología');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-125 · Con el interruptor encendido, un cliente en solo lectura no agrega médicos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-125 · Con el interruptor encendido, un cliente en solo lectura no agrega médicos','ok',sqlerrm like 'Su cuenta está en solo lectura%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.organization_users (organization_id, user_id, role_code) values (v_b, v_md::uuid, 'capturer');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-126 · Con el interruptor encendido, un cliente en solo lectura no agrega usuarios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-126 · Con el interruptor encendido, un cliente en solo lectura no agrega usuarios','ok',sqlerrm like 'Su cuenta está en solo lectura%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-127 · En solo lectura plan_allows dice no y plan_access explica (lectura)','ok',coalesce((not app.plan_allows(v_b, 'agenda_pacientes') and app.plan_access(v_b, 'agenda_pacientes') = 'solo_lectura'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      update public.subscriptions set state = 'suspendida' where organization_id = v_b;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated')::text, true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_b, v_b, v_per + 3, 'Paciente QA X', v_proc, 1, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-128 · Con el interruptor encendido, un cliente en suspendida no agrega reclamaciones y el mensaje dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-128 · Con el interruptor encendido, un cliente en suspendida no agrega reclamaciones y el mensaje dice qué hacer','ok',sqlerrm like 'Su cuenta está suspendida%SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.providers (organization_id, full_name, specialty) values (v_b, 'Dr. Nuevo QA', 'Urología');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-129 · Con el interruptor encendido, un cliente en suspendida no agrega médicos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-129 · Con el interruptor encendido, un cliente en suspendida no agrega médicos','ok',sqlerrm like 'Su cuenta está suspendida%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.organization_users (organization_id, user_id, role_code) values (v_b, v_md::uuid, 'capturer');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-130 · Con el interruptor encendido, un cliente en suspendida no agrega usuarios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-130 · Con el interruptor encendido, un cliente en suspendida no agrega usuarios','ok',sqlerrm like 'Su cuenta está suspendida%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-131 · En suspendida plan_allows dice no y plan_access explica (bloqueado)','ok',coalesce((not app.plan_allows(v_b, 'agenda_pacientes') and app.plan_access(v_b, 'agenda_pacientes') = 'bloqueado'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      update public.subscriptions set state = 'cancelada' where organization_id = v_b;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated')::text, true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_b, v_b, v_per + 3, 'Paciente QA X', v_proc, 1, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-132 · Con el interruptor encendido, un cliente en cancelada no agrega reclamaciones y el mensaje dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-132 · Con el interruptor encendido, un cliente en cancelada no agrega reclamaciones y el mensaje dice qué hacer','ok',sqlerrm like 'Su suscripción está cancelada%SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.providers (organization_id, full_name, specialty) values (v_b, 'Dr. Nuevo QA', 'Urología');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-133 · Con el interruptor encendido, un cliente en cancelada no agrega médicos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-133 · Con el interruptor encendido, un cliente en cancelada no agrega médicos','ok',sqlerrm like 'Su suscripción está cancelada%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.organization_users (organization_id, user_id, role_code) values (v_b, v_md::uuid, 'capturer');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-134 · Con el interruptor encendido, un cliente en cancelada no agrega usuarios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-134 · Con el interruptor encendido, un cliente en cancelada no agrega usuarios','ok',sqlerrm like 'Su suscripción está cancelada%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-135 · En cancelada plan_allows dice no y plan_access explica (bloqueado)','ok',coalesce((not app.plan_allows(v_b, 'agenda_pacientes') and app.plan_access(v_b, 'agenda_pacientes') = 'bloqueado'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.subscriptions set state = 'solo_lectura' where organization_id = v_b;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated')::text, true);
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_b, v_b, v_per + 3, 'Paciente QA Y', v_proc, 1, 100);
      insert into public.providers (organization_id, full_name, specialty) values (v_b, 'Dr. Libre QA', 'Urología');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-136 · Con el interruptor APAGADO nada se bloquea aunque la suscripción esté en solo lectura (el enganche respeta enforce_plans)','ok',coalesce((exists (select 1 from public.service_lines where patient_name = 'Paciente QA Y') and app.plan_allows(v_b, 'agenda_pacientes') and app.plan_access(v_b, 'tablero_direccion') = 'completo'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      update public.subscriptions set state = 'activa' where organization_id = v_b;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated')::text, true);
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_b, v_b, v_per + 3, 'Paciente QA Z', v_proc, 1, 100);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-137 · Con la suscripción activa y el interruptor encendido el cliente captura con normalidad','ok',coalesce((exists (select 1 from public.service_lines where patient_name = 'Paciente QA Z')), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      update public.subscriptions set state = 'solo_lectura' where organization_id = v_b;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.my_plan_usage();
      v_r2 := public.my_subscription();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-138 · Sin romper las funciones por rol: en solo lectura el Médico sigue viendo su plan y su suscripción (con el aviso de qué hacer)','ok',coalesce(((v_r->>'organization_id')::uuid = v_b and v_r2->'subscription'->>'state' = 'solo_lectura' and exists (select 1 from jsonb_array_elements_text(v_r2->'alerts') a where a like '%solo lectura%')), false),'d',(v_r2->'alerts')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.my_plan_usage(v_b);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-139 · Y Operaciones sigue consultando el consumo del cliente en solo lectura','ok',coalesce(((v_r->>'organization_id')::uuid = v_b), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-140 · La organización de SOFA (operadora) no se evalúa nunca: plan_allows siempre sí','ok',coalesce((app.plan_allows('00000000-0000-4000-8000-000000000001'::uuid, 'tablero_direccion') and app.plan_access('00000000-0000-4000-8000-000000000001'::uuid, 'tablero_direccion') = 'completo'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.plan_limits set limit_value = 5, on_exceed = 'avisar' where plan_code = 'saas_intermedio' and limit_code = 'reclamaciones_mes_por_medico';
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      update public.subscriptions set state = 'activa', converted_on = current_date where organization_id = v_a;
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_sub_a, v_a, v_per + 3, 'Paciente QA 1', v_proc, 1, 100);
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_sub_a, v_a, v_per + 3, 'Paciente QA 2', v_proc, 1, 100);
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_sub_a, v_a, v_per + 3, 'Paciente QA 3', v_proc, 1, 100);
      v_r := app.sub_export_gate(v_a, v_pa);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-141 · Con 3 de 5 reclamaciones (60 %) no hay aviso ni bloqueo','ok',coalesce((not (v_r->>'warn')::boolean and not (v_r->>'blocked')::boolean and (v_r->>'used')::int = 3 and (v_r->>'limit')::int = 5), false),'d',(v_r::text)::text));
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_sub_a, v_a, v_per + 3, 'Paciente QA 4', v_proc, 1, 100);
      v_r := app.sub_export_gate(v_a, v_pa);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-142 · Con 4 de 5 (80 %) avisa y todavía deja exportar','ok',coalesce(((v_r->>'warn')::boolean and not (v_r->>'blocked')::boolean and v_r->>'warning' like '%Al pasar el 100 %no podrá exportar lotes%'), false),'d',(v_r::text)::text));
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_sub_a, v_a, v_per + 3, 'Paciente QA 5', v_proc, 1, 100);
      v_r := app.sub_export_gate(v_a, v_pa);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-143 · Exactamente en el 100 % (5 de 5) todavía NO se bloquea: el bloqueo es «pasado» el 100 %','ok',coalesce((not (v_r->>'blocked')::boolean and (v_r->>'pct')::numeric = 100), false),'d',(v_r::text)::text));
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_sub_a, v_a, v_per + 3, 'Paciente QA 6', v_proc, 1, 100);
      v_r := app.sub_export_gate(v_a, v_pa);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-144 · Pasado el 100 % (6 de 5) la exportación de lotes se bloquea y dice cómo seguir (mejorar el plan o esperar al mes siguiente)','ok',coalesce(((v_r->>'blocked')::boolean and v_r->>'reason' like '%ya pasó el 100 %no puede exportar más lotes hasta mejorar su plan o hasta el próximo mes%Escriba a SOFA%'), false),'d',(v_r::text)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
      perform set_config('app.status_change', 'on', true);
    begin
      update public.submissions set status = 'lista_para_radicar' where id = v_sub_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-145 · ATAQUE: pasar el lote a «lista para radicar» pasado el 100 % se bloquea en el servidor (no solo en la pantalla)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-145 · ATAQUE: pasar el lote a «lista para radicar» pasado el 100 % se bloquea en el servidor (no solo en la pantalla)','ok',sqlerrm like '%no puede exportar más lotes%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      v_r := app.sub_export_gate(v_a, v_pa2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-146 · El cupo es por médico: otro médico del mismo consultorio sin reclamaciones no está bloqueado','ok',coalesce((not (v_r->>'blocked')::boolean and (v_r->>'used')::int = 0), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.sub_export_gate();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-147 · El Médico consulta su cupo sin indicar el cliente y ve el bloqueo','ok',coalesce(((v_r->>'blocked')::boolean), false),'d',(v_r::text)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.app_settings set enforce_plans = false where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      v_r := app.sub_export_gate(v_a, v_pa);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-148 · Con el interruptor apagado la exportación nunca se bloquea (solo informa el consumo)','ok',coalesce((not (v_r->>'blocked')::boolean and (v_r->>'used')::int = 6), false),'d',(v_r::text)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
      perform set_config('app.status_change', 'on', true);
      update public.submissions set status = 'lista_para_radicar' where id = v_sub_a;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-149 · Apagado el interruptor, preparar el lote pasa sin bloqueo del plan','ok',coalesce(((select status from public.submissions where id = v_sub_a) = 'lista_para_radicar'), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_cancel_request(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-150 · ATAQUE: el Médico B no cancela la suscripción del consultorio A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-150 · ATAQUE: el Médico B no cancela la suscripción del consultorio A','ok',sqlerrm like 'Solo el médico del consultorio o la Administración%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_cancel_undo();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-151 · Sin cancelación pendiente, anular dice que no hay nada que anular','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-151 · Sin cancelación pendiente, anular dice que no hay nada que anular','ok',sqlerrm like 'No hay una cancelación pendiente que anular%','d',left(sqlerrm,120)));
    end;
    v_r := public.sub_cancel_request(null, 'Cierro el consultorio a fin de mes');
    v_exp_a := (v_r->>'export_request')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-152 · El Médico pide cancelar: termina el último día del mes, los datos se conservan 90 días y queda la solicitud de exportación completa','ok',coalesce((v_r->>'effective_on' = ((date_trunc('month', current_date) + interval '1 month')::date - 1)::text and (v_r->>'retention_until')::date = ((date_trunc('month', current_date) + interval '1 month')::date - 1) + 90 and (select status from public.subscription_export_requests where id = v_exp_a) = 'solicitada' and (select file_ref from public.subscription_export_requests where id = v_exp_a) is null and v_r->>'message' like '%paso posterior%'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_cancel_request(null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-153 · Pedir la cancelación dos veces dice cuándo termina','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-153 · Pedir la cancelación dos veces dice cuándo termina','ok',sqlerrm like 'La cancelación ya fue solicitada y termina el%','d',left(sqlerrm,120)));
    end;
    v_r := public.my_subscription();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-154 · El Médico ve la fecha de fin, la retención y su solicitud de exportación (y solo la suya)','ok',coalesce((v_r->'subscription'->>'cancel_effective_on' = ((date_trunc('month', current_date) + interval '1 month')::date - 1)::text and jsonb_array_length(v_r->'exports') = 1 and (v_r->'exports'->0->>'id')::uuid = v_exp_a and exists (select 1 from jsonb_array_elements_text(v_r->'alerts') a where a like 'Pidió cancelar%')), false),'d',(v_r->'alerts')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_subscription();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-155 · El Médico B no ve la solicitud de exportación del consultorio A','ok',coalesce((jsonb_array_length(v_r->'exports') = 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.sub_cancel_undo();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-156 · Anular la cancelación limpia las fechas, devuelve la retención de la prueba y cancela la solicitud de exportación','ok',coalesce(((select cancel_effective_on from public.subscriptions where organization_id = v_a) is null and (select status from public.subscription_export_requests where id = v_exp_a) = 'cancelada' and (select retention_until from public.subscriptions where organization_id = v_a) = (select trial_ends_on + 30 from public.subscriptions where organization_id = v_a)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.sub_cancel_request(null, 'Mejor cancelo de una vez, gracias');
    v_exp_a := (v_r->>'export_request')::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_export_set_status(v_exp_a, 'quemada');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-157 · El estado de la exportación debe ser uno de la lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-157 · El estado de la exportación debe ser uno de la lista','ok',sqlerrm like 'El estado de la exportación es%','d',left(sqlerrm,120)));
    end;
    perform public.sub_export_set_status(v_exp_a, 'en_preparacion', 'El equipo prepara el archivo');
    perform public.sub_export_set_status(v_exp_a, 'lista');
    perform public.sub_export_set_status(v_exp_a, 'entregada', 'Entregada al médico');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-158 · El equipo marca la exportación en preparación → lista → entregada (la generación del archivo es fase posterior)','ok',coalesce(((select status from public.subscription_export_requests where id = v_exp_a) = 'entregada' and (select note from public.subscription_export_requests where id = v_exp_a) = 'Entregada al médico'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_export_set_status(v_exp_a, 'solicitada');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-159 · Una exportación entregada no cambia más','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-159 · Una exportación entregada no cambia más','ok',sqlerrm like 'La exportación ya está entregada%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      select count(*) into v_cnt1 from public.service_lines where submission_id = v_sub_a;
      perform app.sub_advance_core((date_trunc('month', current_date) + interval '1 month')::date - 1);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-160 · El último día del mes la suscripción sigue vigente (la cancelación es al terminar el mes)','ok',coalesce((app.sub_state(v_a) <> 'cancelada'), false),'d',(null)::text));
      perform app.sub_advance_core((date_trunc('month', current_date) + interval '1 month')::date);
      select count(*) into v_cnt2 from public.service_lines where submission_id = v_sub_a;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-161 · Al día siguiente del fin de mes queda cancelada, con los datos intactos y la retención de 90 días registrada','ok',coalesce((app.sub_state(v_a) = 'cancelada' and v_cnt1 = v_cnt2 and exists (select 1 from public.providers where id = v_pa) and (select retention_until from public.subscriptions where organization_id = v_a) = ((date_trunc('month', current_date) + interval '1 month')::date - 1) + 90), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.sub_invoice_generate(v_a, v_m2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-162 · Una suscripción cancelada no genera más pre-facturas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-162 · Una suscripción cancelada no genera más pre-facturas','ok',sqlerrm like 'La suscripción de este cliente está cancelada%','d',left(sqlerrm,120)));
    end;
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.sub_overview();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-163 · El tablero del administrador lista los 4 clientes de la prueba con su estado, saldo y parámetros, y cuenta por estado','ok',coalesce(((select count(*) from jsonb_array_elements(v_r->'clients') c where c->>'name' like 'QA SU%') = 4 and (select c->>'state' from jsonb_array_elements(v_r->'clients') c where c->>'name' = 'QA SU Consultorio A') = 'prueba' and (select c->>'state' from jsonb_array_elements(v_r->'clients') c where c->>'name' = 'QA SU Consultorio B') = 'activa' and jsonb_array_length(v_r->'params') >= 11 and jsonb_array_length(v_r->'discounts') = 1 and (v_r->'counts'->>'activa')::int >= 1), false),'d',(v_r->'counts')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-164 · El saldo del tablero suma lo emitido sin pagar y no cuenta los borradores (C tiene un borrador: saldo 0)','ok',coalesce(((select (c->>'balance')::numeric from jsonb_array_elements(v_r->'clients') c where c->>'name' = 'QA SU Consultorio C') = 0 and (select (c->>'drafts')::int from jsonb_array_elements(v_r->'clients') c where c->>'name' = 'QA SU Consultorio C') = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.sub_invoice_list(v_b);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-165 · La lista de pre-facturas del administrador filtra por cliente','ok',coalesce((jsonb_array_length(v_r) >= 1 and (select bool_and(x->>'org_name' = 'QA SU Consultorio B') from jsonb_array_elements(v_r) x)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.sub_invoice_list(null, 'borrador');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-166 · Y filtra por estado (borrador)','ok',coalesce(((select bool_and(x->>'status' = 'borrador') from jsonb_array_elements(v_r) x)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.sub_invoice_list(null, 'rota');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-167 · Un estado de pre-factura inválido dice las opciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-167 · Un estado de pre-factura inválido dice las opciones','ok',sqlerrm like 'El estado de la pre-factura es%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-168 · Las pre-facturas tienen número único y consecutivo, todas internas (ninguna fiscal)','ok',coalesce(((select count(distinct number) = count(*) from public.subscription_invoices where organization_id in (v_a, v_b, v_c, v_d)) and not exists (select 1 from public.subscription_invoices where fiscal)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','SU-169 · Ningún dato se borró en toda la prueba: los médicos y las reclamaciones de los clientes siguen ahí','ok',coalesce(((select count(*) from public.providers where organization_id in (v_a, v_b, v_c)) = 6 and exists (select 1 from public.submissions where id = v_sub_a) and exists (select 1 from public.submissions where id = v_sub_b)), false),'d',(null)::text));
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
revoke all on function app.qa_run_tests_suscripcion() from public, anon, authenticated;
