-- 179 · Suite de la 178 (planes y bloqueo por plan, P1). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_planes();
create or replace function app.qa_run_tests_planes()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_a constant uuid := '01780000-0000-4000-8000-000000000001'; v_b constant uuid := '01780000-0000-4000-8000-000000000002'; v_c constant uuid := '01780000-0000-4000-8000-000000000003'; v_d constant uuid := '01780000-0000-4000-8000-000000000004';
  v_pa constant uuid := '01780000-0000-4000-8000-000000000011'; v_pa2 constant uuid := '01780000-0000-4000-8000-000000000012'; v_pb constant uuid := '01780000-0000-4000-8000-000000000013'; v_pc constant uuid := '01780000-0000-4000-8000-000000000014';
  v_sa constant text := '01780000-0000-4000-8000-000000000021'; v_ad constant text := '01780000-0000-4000-8000-000000000022'; v_ops constant text := '01780000-0000-4000-8000-000000000023'; v_bil constant text := '01780000-0000-4000-8000-000000000024'; v_co constant text := '01780000-0000-4000-8000-000000000025';
  v_ma constant text := '01780000-0000-4000-8000-000000000031'; v_sec1 constant text := '01780000-0000-4000-8000-000000000032'; v_sec2 constant text := '01780000-0000-4000-8000-000000000033'; v_mb constant text := '01780000-0000-4000-8000-000000000034'; v_mc constant text := '01780000-0000-4000-8000-000000000035';
  v_ars uuid; v_proc uuid; v_per date; v_sub_a uuid; v_sub_a2 uuid; v_sub_b uuid; v_l1 uuid; v_lb uuid; v_r jsonb; v_rl text;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '178') then
    raise exception 'Falta la migración 178. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.pl.sa@sofa.test','x'),(v_ad::uuid,'qa.pl.ad@sofa.test','x'),(v_ops::uuid,'qa.pl.ops@sofa.test','x'),(v_bil::uuid,'qa.pl.bil@sofa.test','x'),(v_co::uuid,'qa.pl.co@sofa.test','x'),(v_ma::uuid,'qa.pl.ma@sofa.test','x'),(v_sec1::uuid,'qa.pl.sec1@sofa.test','x'),(v_sec2::uuid,'qa.pl.sec2@sofa.test','x'),(v_mb::uuid,'qa.pl.mb@sofa.test','x'),(v_mc::uuid,'qa.pl.mc@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.pl.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_a, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA PL Consultorio A', '00000017801', 'Médico independiente', 'activo', current_date - 90, '8095557801');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_b, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA PL Consultorio B', '00000017802', 'Médico independiente', 'activo', current_date - 90, '8095557802');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_c, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA PL Consultorio C', '00000017803', 'Médico independiente', 'activo', current_date - 90, '8095557803');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_d, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA PL Consultorio D', '00000017804', 'Médico independiente', 'activo', current_date - 90, '8095557804');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_a, 'Dr. A Uno QA', 'Cardiología', true), (v_pa2, v_a, 'Dr. A Dos QA', 'Pediatría', false),
      (v_pb, v_b, 'Dr. B QA', 'Ortopedia', true), (v_pc, v_c, 'Dr. C QA', 'Urología', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_co::uuid, 'assistant', true),
      (v_a, v_ma::uuid, 'client', true), (v_a, v_sec1::uuid, 'capturer', true), (v_a, v_sec2::uuid, 'capturer', false), (v_b, v_mb::uuid, 'client', true), (v_c, v_mc::uuid, 'client', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec1::uuid, v_pa, v_a, true, true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_pl_ars', 'ARS QA Planes', 'Contributivo', true) returning id into v_ars;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    v_per := date_trunc('month', current_date)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_ars, v_per, 1, 'borrador') returning id into v_sub_a;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa2, v_ars, v_per, 2, 'borrador') returning id into v_sub_a2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_b, v_pb, v_ars, v_per, 1, 'borrador') returning id into v_sub_b;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-01 · La migración 178 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '178')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-02 · Siete planes sembrados (3 de servicio, 3 SaaS y Fundador/Legado) con los precios de los documentos','ok',coalesce(((select count(*) from public.plans where code in ('servicio_basico','servicio_intermedio','servicio_avanzado','saas_basico','saas_intermedio','saas_avanzado','legado')) = 7 and (select price_monthly from public.plans where code = 'servicio_intermedio') = 6500 and (select price_founder from public.plans where code = 'servicio_intermedio') = 5000 and (select price_monthly from public.plans where code = 'saas_avanzado') = 4900 and (select price_annual from public.plans where code = 'saas_basico') = 15000), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-03 · Límites sembrados: Servicio Básico 150 reclamaciones y 1 secretaria; SaaS Intermedio 500 y 3 usuarios; SaaS Básico 1 médico','ok',coalesce(((select limit_value from public.plan_limits where plan_code = 'servicio_basico' and limit_code = 'reclamaciones_mes_por_medico') = 150 and (select limit_value from public.plan_limits where plan_code = 'servicio_basico' and limit_code = 'secretarias_por_medico') = 1 and (select limit_value from public.plan_limits where plan_code = 'saas_intermedio' and limit_code = 'reclamaciones_mes_por_medico') = 500 and (select limit_value from public.plan_limits where plan_code = 'saas_intermedio' and limit_code = 'usuarios_por_medico') = 3 and (select limit_value from public.plan_limits where plan_code = 'saas_basico' and limit_code = 'max_medicos') = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-04 · Fundador/Legado: sin ningún límite y con todos los módulos incluidos','ok',coalesce((not exists (select 1 from public.plan_limits where plan_code = 'legado') and not exists (select 1 from public.plan_feature_defs d left join public.plan_features f on f.feature_code = d.code and f.plan_code = 'legado' where coalesce(f.included, false) = false)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-05 · Módulos por plan: el SaaS Básico no incluye conciliación, el Intermedio sí; el tablero de dirección es del Avanzado','ok',coalesce((not coalesce((select included from public.plan_features where plan_code = 'saas_basico' and feature_code = 'conciliacion_pagos'), false) and (select included from public.plan_features where plan_code = 'saas_intermedio' and feature_code = 'conciliacion_pagos') and not coalesce((select included from public.plan_features where plan_code = 'saas_intermedio' and feature_code = 'tablero_direccion'), false) and (select included from public.plan_features where plan_code = 'saas_avanzado' and feature_code = 'tablero_direccion')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-06 · La historia clínica queda fuera de los seis planes (solo el legado la conserva)','ok',coalesce((not exists (select 1 from public.plan_features where feature_code = 'historia_clinica' and included and plan_code <> 'legado') and exists (select 1 from public.plan_features where feature_code = 'historia_clinica' and plan_code = 'legado' and included)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-07 · Los clientes que ya existían quedaron en Fundador/Legado (ninguno sin plan)','ok',coalesce((not exists (select 1 from public.organizations o where o.kind = 'client' and o.id not in (v_a, v_b, v_c, v_d) and app.org_plan(o.id) is distinct from 'legado')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-08 · El interruptor nace APAGADO (valor por defecto falso)','ok',coalesce(((select column_default from information_schema.columns where table_schema = 'public' and table_name = 'app_settings' and column_name = 'enforce_plans') = 'false'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-09 · Las tablas de planes no se tocan por la API: ni anon ni authenticated tienen permisos','ok',coalesce((not has_table_privilege('authenticated', 'public.organization_plans', 'select') and not has_table_privilege('authenticated', 'public.organization_plans', 'update') and not has_table_privilege('authenticated', 'public.plans', 'select') and not has_table_privilege('authenticated', 'public.plan_limits', 'update') and not has_table_privilege('authenticated', 'public.plan_features', 'insert') and not has_table_privilege('anon', 'public.organization_plans', 'select')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-10 · plan_allows, plan_limit y plan_includes son SECURITY DEFINER y no se llaman desde la API','ok',coalesce(((select bool_and(prosecdef) from pg_proc where pronamespace = 'app'::regnamespace and proname in ('plan_allows','plan_limit','plan_includes')) and not has_function_privilege('authenticated', 'app.plan_allows(uuid,text)', 'execute') and not has_function_privilege('anon', 'app.plan_limit(uuid,text)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-11 · Las funciones públicas de planes no están abiertas a anon','ok',coalesce((not has_function_privilege('anon', 'public.my_plan_usage(uuid)', 'execute') and not has_function_privilege('anon', 'public.assign_org_plan(uuid,text,date,text,boolean)', 'execute') and has_function_privilege('authenticated', 'public.my_plan_usage(uuid)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.assign_org_plan(v_a, 'legado', current_date, 'Intento de cambiar el plan por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-12 · ATAQUE: El Médico no asigna planes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-12 · ATAQUE: El Médico no asigna planes','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA asignan planes%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.assign_org_plan(v_a, 'legado', current_date, 'Intento de cambiar el plan por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-13 · ATAQUE: La Secretaria no asigna planes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-13 · ATAQUE: La Secretaria no asigna planes','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA asignan planes%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.assign_org_plan(v_a, 'legado', current_date, 'Intento de cambiar el plan por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-14 · ATAQUE: Operaciones no asigna planes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-14 · ATAQUE: Operaciones no asigna planes','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA asignan planes%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.assign_org_plan(v_a, 'legado', current_date, 'Intento de cambiar el plan por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-15 · ATAQUE: Facturación no asigna planes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-15 · ATAQUE: Facturación no asigna planes','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA asignan planes%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.assign_org_plan(v_a, 'legado', current_date, 'Intento de cambiar el plan por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-16 · ATAQUE: El Comercial no asigna planes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-16 · ATAQUE: El Comercial no asigna planes','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA asignan planes%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      update public.organization_plans set plan_code = 'legado' where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-17 · ATAQUE: el Médico no cambia su plan con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-17 · ATAQUE: el Médico no cambia su plan con UPDATE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.organization_plans (organization_id, plan_code) values (v_a, 'legado');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-18 · ATAQUE: el Médico no inserta un plan por la API','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-18 · ATAQUE: el Médico no inserta un plan por la API','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      delete from public.organization_plans where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-19 · ATAQUE: el Médico no borra el historial de planes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-19 · ATAQUE: el Médico no borra el historial de planes','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      perform 1 from public.organization_plans limit 1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-20 · ATAQUE: el Médico no lee la tabla de planes de los clientes (ni la suya ni la de otros)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-20 · ATAQUE: el Médico no lee la tabla de planes de los clientes (ni la suya ni la de otros)','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      update public.plan_limits set limit_value = 999999;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-21 · ATAQUE: el Médico no sube el límite de su plan con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-21 · ATAQUE: el Médico no sube el límite de su plan con UPDATE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      update public.plans set price_monthly = 1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-22 · ATAQUE: el Médico no cambia precios con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-22 · ATAQUE: el Médico no cambia precios con UPDATE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.plan_limit_set('saas_basico', 'max_medicos', 99, 'bloquear');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-23 · ATAQUE: el Médico no usa plan_limit_set','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-23 · ATAQUE: el Médico no usa plan_limit_set','ok',sqlerrm like 'Los planes los administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.plan_save('saas_basico', 'Gratis', 'saas', null, 0);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-24 · ATAQUE: el Médico no usa plan_save','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-24 · ATAQUE: el Médico no usa plan_save','ok',sqlerrm like 'Los planes los administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.plan_feature_set('saas_basico', 'tablero_direccion', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-25 · ATAQUE: el Médico no usa plan_feature_set','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-25 · ATAQUE: el Médico no usa plan_feature_set','ok',sqlerrm like 'Los planes los administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.plans_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-26 · ATAQUE: el Médico no ve el panel de planes de todos los clientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-26 · ATAQUE: el Médico no ve el panel de planes de todos los clientes','ok',sqlerrm like 'Los planes los administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.plans_set_enforce(true, 'Quiero ver qué pasa si lo activo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-27 · ATAQUE: el Médico no activa el bloqueo por plan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-27 · ATAQUE: el Médico no activa el bloqueo por plan','ok',sqlerrm like 'Solo el Super Admin activa%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.plans_set_enforce(true, 'Activación sin permiso del Super Admin');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-28 · ATAQUE: el Administrador tampoco activa el interruptor (es del Super Admin)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-28 · ATAQUE: el Administrador tampoco activa el interruptor (es del Super Admin)','ok',sqlerrm like 'Solo el Super Admin activa%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-29 · ATAQUE: ni el Super Admin cambia el interruptor con UPDATE directo (evita la verificación de clientes sin plan)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-29 · ATAQUE: ni el Super Admin cambia el interruptor con UPDATE directo (evita la verificación de clientes sin plan)','ok',sqlerrm like 'El bloqueo por plan se activa o desactiva con%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    update public.app_settings set enforce_plans = true where true; get diagnostics v_n = row_count;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-30 · ATAQUE: el Médico no cambia app_settings (la política no lo deja tocar ninguna fila)','ok',coalesce((v_n = 0 and not exists (select 1 from public.app_settings where enforce_plans)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform public.plan_save('qa_tiny', 'QA Mini', 'saas', 'Plan de prueba', 100, null, 1000, 0, true, 999);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-31 · El Super Admin crea un plan con plan_save','ok',coalesce((exists (select 1 from public.plans where code = 'qa_tiny' and price_monthly = 100)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform public.plan_limit_set('qa_tiny', 'reclamaciones_mes_por_medico', 3);
    perform public.plan_limit_set('qa_tiny', 'secretarias_por_medico', 1);
    perform public.plan_limit_set('qa_tiny', 'usuarios_por_medico', 2);
    perform public.plan_limit_set('qa_tiny', 'max_medicos', 1);
    perform public.plan_feature_set('qa_tiny', 'agenda_pacientes', true, 'Solo lo básico');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-32 · plan_limit_set y plan_feature_set dejan 4 límites y un módulo','ok',coalesce(((select count(*) from public.plan_limits where plan_code = 'qa_tiny') = 4 and (select count(*) from public.plan_features where plan_code = 'qa_tiny' and included) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.plan_limit_set('qa_tiny', 'max_medicos', -1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-33 · Un límite negativo se rechaza y dice cómo quitarlo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-33 · Un límite negativo se rechaza y dice cómo quitarlo','ok',sqlerrm like 'El límite no puede ser negativo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.plan_save('Plan Raro!', 'Raro', 'saas');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-34 · Código de plan inválido: dice el formato','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-34 · Código de plan inválido: dice el formato','ok',sqlerrm like 'El código del plan usa solo minúsculas%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.plan_limit_set('qa_tiny', 'max_medicos', 2, 'ignorar');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-35 · Al pasarse del límite solo se puede bloquear o avisar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-35 · Al pasarse del límite solo se puede bloquear o avisar','ok',sqlerrm like 'Al pasarse del límite se puede%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.assign_org_plan(v_a, 'qa_tiny', current_date, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-36 · Asignar sin motivo suficiente se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-36 · Asignar sin motivo suficiente se rechaza','ok',sqlerrm like 'Escriba el motivo del cambio de plan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.assign_org_plan(v_a, 'plan_fantasma', current_date, 'Plan que no existe en el catálogo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-37 · Asignar un plan inexistente dice que elija de la lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-37 · Asignar un plan inexistente dice que elija de la lista','ok',sqlerrm like 'El plan %plan_fantasma% no existe%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.assign_org_plan('00000000-0000-4000-8000-000000000001'::uuid, 'legado', current_date, 'Intento de plan para la operadora');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-38 · Asignar un plan a la organización de SOFA se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-38 · Asignar un plan a la organización de SOFA se rechaza','ok',sqlerrm like 'Cliente no encontrado%','d',left(sqlerrm,120)));
    end;
    v_r := public.assign_org_plan(v_a, 'qa_tiny', current_date, 'Plan de prueba para el consultorio A');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-39 · El Administrador asigna un plan: el cliente queda en él hoy','ok',coalesce((v_r->>'plan_code' = 'qa_tiny' and app.org_plan(v_a) = 'qa_tiny' and (v_r->>'previous_plan') is null), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform public.assign_org_plan(v_b, 'legado', current_date, 'Cliente anterior a los planes, sin límites');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-40 · Fundador/Legado asignado al consultorio B','ok',coalesce((app.org_plan(v_b) = 'legado'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.assign_org_plan(v_a, 'qa_tiny', current_date, 'Reasignación del mismo plan de prueba');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-41 · Reasignar el mismo plan no hace nada y lo dice','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-41 · Reasignar el mismo plan no hace nada y lo dice','ok',sqlerrm like 'Ese cliente ya está en el plan%','d',left(sqlerrm,120)));
    end;
    perform public.assign_org_plan(v_d, 'legado', current_date - 3, 'Cliente D parte en el plan legado');
    perform public.assign_org_plan(v_d, 'saas_basico', current_date + 10, 'Baja programada al plan básico del SaaS');
    v_r := public.plan_history(v_d);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-42 · Plan programado: hoy sigue el legado, en 10 días entra el Básico, y el historial lo muestra','ok',coalesce((app.org_plan(v_d) = 'legado' and app.org_plan(v_d, current_date + 10) = 'saas_basico' and jsonb_array_length(v_r) = 2 and v_r->0->>'status' = 'programado' and v_r->1->>'status' = 'vigente'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform public.assign_org_plan(v_d, 'saas_avanzado', current_date + 5, 'Mejor se le sube al avanzado en 5 días');
    v_r := public.plan_history(v_d);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-43 · Reemplazar lo programado: el Básico queda cancelado y el legado termina un día antes del Avanzado','ok',coalesce((app.org_plan(v_d, current_date + 5) = 'saas_avanzado' and app.org_plan(v_d, current_date + 4) = 'legado' and app.org_plan(v_d, current_date + 10) = 'saas_avanzado' and (select count(*) from jsonb_array_elements(v_r) x where x->>'status' = 'cancelado') = 1), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-44 · El historial queda en la bitácora de auditoría','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'organization_plans' and organization_id = v_a and operation = 'INSERT')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      insert into public.organization_plans (organization_id, plan_code, starts_on, status) values (v_a, 'legado', current_date + 1, 'activo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-45 · Dos vigencias activas que se traslapan se rechazan (inserción directa del SQL Editor)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-45 · Dos vigencias activas que se traslapan se rechazan (inserción directa del SQL Editor)','ok',sqlerrm like 'Las vigencias de los planes de este cliente se traslapan%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.organization_plans (organization_id, plan_code) values ('00000000-0000-4000-8000-000000000001'::uuid, 'legado');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-46 · No se asigna un plan a la organización de SOFA (inserción directa)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-46 · No se asigna un plan a la organización de SOFA (inserción directa)','ok',sqlerrm like 'Los planes se asignan a clientes%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_plan_usage();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-47 · El Médico ve su propio plan, 4 límites y los módulos, sin indicar el cliente','ok',coalesce(((v_r->>'organization_id')::uuid = v_a and v_r->'plan'->>'code' = 'qa_tiny' and jsonb_array_length(v_r->'limits') = 4 and jsonb_array_length(v_r->'features') > 30), false),'d',(v_r->'plan'::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-48 · El Médico ve que agenda está incluida y el tablero de dirección no','ok',coalesce(((select (f->>'included')::boolean from jsonb_array_elements(v_r->'features') f where f->>'code' = 'agenda_pacientes') and not (select (f->>'included')::boolean from jsonb_array_elements(v_r->'features') f where f->>'code' = 'tablero_direccion')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.my_plan_usage(v_b);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-49 · ATAQUE: el Médico A no consulta el plan del consultorio B','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-49 · ATAQUE: el Médico A no consulta el plan del consultorio B','ok',sqlerrm like 'No tiene acceso al plan de ese consultorio%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.plan_history(v_b);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-50 · ATAQUE: el Médico A no lee el historial de planes del consultorio B','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-50 · ATAQUE: el Médico A no lee el historial de planes del consultorio B','ok',sqlerrm like 'No tiene acceso al historial%','d',left(sqlerrm,120)));
    end;
    v_r := public.plan_history(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-51 · El Médico sí lee el historial de su propio consultorio','ok',coalesce((jsonb_array_length(v_r) = 1 and v_r->0->>'plan_code' = 'qa_tiny' and v_r->0->>'assigned_by' is null), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.my_plan_usage(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-52 · ATAQUE: la Secretaria no consulta el plan del consultorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-52 · ATAQUE: la Secretaria no consulta el plan del consultorio','ok',sqlerrm like 'No tiene acceso al plan de ese consultorio%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_plan_usage();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-53 · El Médico B (Legado) ve su plan sin ningún límite','ok',coalesce((v_r->'plan'->>'code' = 'legado' and (select bool_and(l->>'state' = 'sin_limite') from jsonb_array_elements(v_r->'limits') l) and (v_r->>'organization_id')::uuid = v_b), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mc, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_plan_usage();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-54 · Un consultorio sin plan lo ve claro: sin plan y con aviso para escribir a SOFA','ok',coalesce((v_r->'plan' = 'null'::jsonb and v_r->'alerts'->>0 like 'Su cuenta todavía no tiene un plan asignado%'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_plan_usage(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-55 · Operaciones puede consultar el consumo de un cliente','ok',coalesce(((v_r->>'organization_id')::uuid = v_a), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.my_plan_usage();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-56 · Sin cliente indicado, el personal de SOFA recibe qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-56 · Sin cliente indicado, el personal de SOFA recibe qué hacer','ok',sqlerrm like 'Indique el cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.plans_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-57 · ATAQUE: Operaciones no ve el panel de administración de planes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-57 · ATAQUE: Operaciones no ve el panel de administración de planes','ok',sqlerrm like 'Los planes los administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.plans_overview();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-58 · El Administrador ve el panel: 4 clientes de la prueba, uno sin plan (C) y 7 planes o más','ok',coalesce(((select count(*) from jsonb_array_elements(v_r->'clients') c where c->>'name' like 'QA PL%') = 4 and (v_r->>'clients_without_plan')::int >= 1 and (select c->>'plan_code' from jsonb_array_elements(v_r->'clients') c where c->>'name' = 'QA PL Consultorio A') = 'qa_tiny' and jsonb_array_length(v_r->'plans') >= 8), false),'d',(v_r->>'clients_without_plan')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-59 · Con el interruptor apagado plan_allows dice sí aunque el plan no incluya el módulo, y plan_includes dice la verdad','ok',coalesce((app.plan_allows(v_a, 'tablero_direccion') and not app.plan_includes(v_a, 'tablero_direccion') and app.plan_includes(v_a, 'agenda_pacientes')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform app.plan_allows(v_a, 'modulo_inventado');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-60 · Un módulo que no existe en el catálogo se rechaza (evita errores de escritura)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-60 · Un módulo que no existe en el catálogo se rechaza (evita errores de escritura)','ok',sqlerrm like 'El módulo %modulo_inventado% no está en el catálogo%','d',left(sqlerrm,120)));
    end;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-61 · plan_limit dice lo que dice el plan, haya o no bloqueo','ok',coalesce((app.plan_limit(v_a, 'reclamaciones_mes_por_medico') = 3 and app.plan_limit(v_a, 'max_medicos') = 1 and app.plan_limit(v_b, 'reclamaciones_mes_por_medico') is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
      insert into public.providers (organization_id, full_name, specialty) values (v_a, 'Dr. Extra QA', 'Urología');
      insert into public.organization_users (organization_id, user_id, role_code) values (v_a, v_sec2::uuid, 'capturer') on conflict (organization_id, user_id) do update set is_active = true;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 1', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 2', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 3', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 4', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 5', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 6', v_proc, 1, 100);
      select count(*) into v_n from public.service_lines where submission_id = v_sub_a;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-62 · Con el interruptor APAGADO no se bloquea nada: 2º médico, 2ª secretaria y 6 reclamaciones (el plan permite 1, 1 y 3)','ok',coalesce((v_n = 6 and (select count(*) from public.providers where organization_id = v_a and is_active) = 2 and (select count(*) from public.organization_users where organization_id = v_a and role_code = 'capturer' and is_active) = 2), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.app_settings set enforce_plans = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-63 · Con el interruptor encendido plan_allows respeta el plan: agenda sí, tablero no; el legado todo; la operadora no se evalúa','ok',coalesce((app.plan_allows(v_a, 'agenda_pacientes') and not app.plan_allows(v_a, 'tablero_direccion') and app.plan_allows(v_b, 'tablero_direccion') and app.plan_allows('00000000-0000-4000-8000-000000000001'::uuid, 'tablero_direccion')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-64 · Un cliente sin plan no tiene ningún módulo con el interruptor encendido','ok',coalesce((not app.plan_allows(v_c, 'agenda_pacientes')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
    begin
      insert into public.providers (organization_id, full_name, specialty) values (v_a, 'Dr. Extra QA', 'Urología');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-65 · ATAQUE: un 2º médico por inserción directa se bloquea y dice cómo mejorar el plan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-65 · ATAQUE: un 2º médico por inserción directa se bloquea y dice cómo mejorar el plan','ok',sqlerrm like 'Su plan «QA Mini» permite hasta 1 médico(s) activo(s)%mejorar su plan%','d',left(sqlerrm,120)));
    end;
    begin
      update public.providers set is_active = true where id = v_pa2;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-66 · ATAQUE: reactivar un médico inactivo también cuenta contra el límite','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-66 · ATAQUE: reactivar un médico inactivo también cuenta contra el límite','ok',sqlerrm like 'Su plan «QA Mini» permite hasta 1 médico%','d',left(sqlerrm,120)));
    end;
    begin
      update public.providers set organization_id = v_a where id = v_pb;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-67 · ATAQUE: pasar un médico de otro cliente a este consultorio no evade el límite','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-67 · ATAQUE: pasar un médico de otro cliente a este consultorio no evade el límite','ok',sqlerrm like 'Su plan «QA Mini» permite hasta 1 médico%','d',left(sqlerrm,120)));
    end;
    update public.providers set specialty = 'Cardiología intervencionista' where id = v_pa; get diagnostics v_n = row_count;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-68 · Editar los datos de un médico que ya está activo no se bloquea','ok',coalesce((v_n = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    insert into public.providers (organization_id, full_name, specialty) values (v_b, 'Dr. B Dos QA', 'Urología'), (v_b, 'Dr. B Tres QA', 'Urología'), (v_b, 'Dr. B Cuatro QA', 'Urología');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-69 · El plan Fundador/Legado agrega médicos sin límite','ok',coalesce(((select count(*) from public.providers where organization_id = v_b and is_active) = 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      insert into public.providers (organization_id, full_name, specialty) values (v_c, 'Dr. C Dos QA', 'Urología');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-70 · Un cliente sin plan no puede agregar médicos y le dice que pida el plan a SOFA','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-70 · Un cliente sin plan no puede agregar médicos y le dice que pida el plan a SOFA','ok',sqlerrm like 'Este cliente no tiene un plan asignado%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 1', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 2', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 3', v_proc, 1, 100);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-71 · Hasta el límite del plan (3 reclamaciones al mes por médico) se captura normal','ok',coalesce(((select count(*) from public.service_lines where submission_id = v_sub_a) = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_a, v_a, v_per + 3, 'Paciente QA 4', v_proc, 1, 100);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-72 · ATAQUE: la reclamación 4 se bloquea y dice qué hacer (mejorar el plan o esperar al próximo mes)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-72 · ATAQUE: la reclamación 4 se bloquea y dice qué hacer (mejorar el plan o esperar al próximo mes)','ok',sqlerrm like 'Con el plan «QA Mini», Dr. A Uno QA ya tiene 3 reclamaciones este mes%próximo mes%escriba a SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, created_at) values (v_sub_a, v_a, v_per + 3, 'Paciente QA 5', v_proc, 1, 100, now() - interval '70 days');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-73 · ATAQUE: atrasar la fecha de captura al insertar no evade el límite','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-73 · ATAQUE: atrasar la fecha de captura al insertar no evade el límite','ok',sqlerrm like 'Con el plan «QA Mini»%','d',left(sqlerrm,120)));
    end;
    select id into v_l1 from public.service_lines where submission_id = v_sub_a order by patient_name limit 1;
    begin
      update public.service_lines set created_at = now() - interval '70 days' where id = v_l1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-74 · ATAQUE: cambiar después la fecha de captura de una línea (para sacarla del mes) se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-74 · ATAQUE: cambiar después la fecha de captura de una línea (para sacarla del mes) se rechaza','ok',sqlerrm like 'La fecha en que se capturó la reclamación no se modifica%','d',left(sqlerrm,120)));
    end;
    update public.service_lines set notes = 'Corregida por la secretaria' where id = v_l1; get diagnostics v_n = row_count;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-75 · Editar una reclamación existente con el médico al límite no se bloquea','ok',coalesce((v_n = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated')::text, true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_b, v_b, v_per + 3, 'Paciente B QA', v_proc, 1, 100) returning id into v_lb;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
    begin
      update public.service_lines set submission_id = v_sub_a where id = v_lb;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-76 · ATAQUE: mover una reclamación de otro consultorio hacia el médico que está al límite se bloquea','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-76 · ATAQUE: mover una reclamación de otro consultorio hacia el médico que está al límite se bloquea','ok',sqlerrm like 'Con el plan «QA Mini»%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated')::text, true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_b, v_b, v_per + 3, 'Paciente QA 1', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_b, v_b, v_per + 3, 'Paciente QA 2', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_b, v_b, v_per + 3, 'Paciente QA 3', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_b, v_b, v_per + 3, 'Paciente QA 4', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_b, v_b, v_per + 3, 'Paciente QA 5', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_b, v_b, v_per + 3, 'Paciente QA 6', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_b, v_b, v_per + 3, 'Paciente QA 7', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_b, v_b, v_per + 3, 'Paciente QA 8', v_proc, 1, 100);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-77 · El plan Fundador/Legado captura sin límite (9 reclamaciones del mes)','ok',coalesce(((select count(*) from public.service_lines where submission_id = v_sub_b) = 9), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_a, v_a, v_per + 3, 'Paciente QA SQL', v_proc, 1, 100);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-78 · El SQL Editor y las migraciones (sin sesión de usuario) no se bloquean','ok',coalesce(((select count(*) from public.service_lines where submission_id = v_sub_a) = 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.service_lines where submission_id = v_sub_a;
      insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, created_at)
      select v_sub_a, v_a, v_per + 3, 'Paciente Viejo ' || g, v_proc, 1, 100, app.plan_month_start() - interval '3 days' from generate_series(1, 3) g;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 21', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 22', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 23', v_proc, 1, 100);
      begin
        insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_sub_a, v_a, v_per + 3, 'Paciente QA 24', v_proc, 1, 100);
        v_n := -1;
      exception when others then v_n := 1; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-79 · Las reclamaciones del mes pasado no cuentan: el límite se reinicia cada mes (3 viejas + 3 nuevas entran, la 4ª nueva no)','ok',coalesce((v_n = 1 and (select count(*) from public.service_lines where submission_id = v_sub_a) = 6), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.service_lines where submission_id = v_sub_a;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
      begin
        insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
        select v_sub_a, v_a, v_per + 3, 'Paciente Masivo ' || g, v_proc, 1, 100 from generate_series(1, 5) g;
        v_n := -1;
      exception when others then v_n := (select count(*) from public.service_lines where submission_id = v_sub_a); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-80 · ATAQUE: cargar 5 reclamaciones en una sola instrucción (importación) no evade el límite: no entra ninguna','ok',coalesce((v_n = 0), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.service_lines where submission_id = v_sub_a;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 31', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 32', v_proc, 1, 100);
      v_r := public.my_plan_usage();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-81 · Con 2 de 3 reclamaciones (67 %) todavía no hay aviso','ok',coalesce(((select l->>'state' from jsonb_array_elements(v_r->'limits') l where l->>'code' = 'reclamaciones_mes_por_medico') = 'ok'), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
      perform public.plan_limit_set('qa_tiny', 'reclamaciones_mes_por_medico', 2);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
      v_r := public.my_plan_usage();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-82 · Con el médico justo en el límite el consumo dice «al límite», 100 % y avisa que no podrá agregar más','ok',coalesce(((select l->>'state' from jsonb_array_elements(v_r->'limits') l where l->>'code' = 'reclamaciones_mes_por_medico') = 'al_limite' and (select (l->>'pct')::numeric from jsonb_array_elements(v_r->'limits') l where l->>'code' = 'reclamaciones_mes_por_medico') = 100 and exists (select 1 from jsonb_array_elements_text(v_r->'alerts') a where a like 'Reclamaciones al mes por médico: lleva 2 de 2%no podrá agregar más%')), false),'d',(v_r->'alerts')::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
      perform public.plan_limit_set('qa_tiny', 'reclamaciones_mes_por_medico', 5);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 33', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 34', v_proc, 1, 100);
      v_r := public.my_plan_usage();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-83 · Con 4 de 5 reclamaciones (80 %) el consumo avisa que está llegando al límite','ok',coalesce(((select l->>'state' from jsonb_array_elements(v_r->'limits') l where l->>'code' = 'reclamaciones_mes_por_medico') = 'aviso' and exists (select 1 from jsonb_array_elements_text(v_r->'alerts') a where a like 'Reclamaciones al mes por médico: lleva 4 de 5%llegando al límite%')), false),'d',(v_r->'alerts')::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.service_lines where submission_id = v_sub_a;
      update public.plan_limits set on_exceed = 'avisar' where plan_code = 'qa_tiny' and limit_code = 'reclamaciones_mes_por_medico';
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 51', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 52', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 53', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 54', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 55', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 56', v_proc, 1, 100);
      select count(*) into v_n from public.service_lines where submission_id = v_sub_a;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-84 · Un límite en modo «avisar» no bloquea: entran 6 reclamaciones aunque el plan diga 3','ok',coalesce((v_n = 6), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.plan_limits where plan_code = 'qa_tiny' and limit_code = 'max_medicos';
      update public.plan_limits set limit_value = 3 where plan_code = 'qa_tiny' and limit_code = 'reclamaciones_mes_por_medico';
      delete from public.service_lines where submission_id in (v_sub_a, v_sub_a2);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
      update public.providers set is_active = true where id = v_pa2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 61', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 62', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 63', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a2, v_a, v_per + 3, 'Paciente QA 64', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a2, v_a, v_per + 3, 'Paciente QA 65', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a2, v_a, v_per + 3, 'Paciente QA 66', v_proc, 1, 100);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-85 · El límite es POR MÉDICO: con 2 médicos activos, cada uno captura sus 3 reclamaciones','ok',coalesce(((select count(*) from public.service_lines where submission_id = v_sub_a) = 3 and (select count(*) from public.service_lines where submission_id = v_sub_a2) = 3), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
    begin
      insert into public.organization_users (organization_id, user_id, role_code) values (v_a, v_mb::uuid, 'capturer');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-86 · ATAQUE: una 2ª secretaria por inserción directa se bloquea y dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-86 · ATAQUE: una 2ª secretaria por inserción directa se bloquea y dice qué hacer','ok',sqlerrm like 'Su plan «QA Mini» incluye 1 secretaria(s) por médico%Desactive%escriba a SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      update public.organization_users set is_active = true where organization_id = v_a and user_id = v_sec2::uuid;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-87 · ATAQUE: reactivar una secretaria inactiva también cuenta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-87 · ATAQUE: reactivar una secretaria inactiva también cuenta','ok',sqlerrm like 'Su plan «QA Mini» incluye 1 secretaria(s)%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.organization_users (organization_id, user_id, role_code) values (v_a, v_mb::uuid, 'client');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-88 · ATAQUE: meter a la 2ª persona como «Médico» para saltarse el tope de secretarias choca con el de usuarios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-88 · ATAQUE: meter a la 2ª persona como «Médico» para saltarse el tope de secretarias choca con el de usuarios','ok',sqlerrm like 'Su plan «QA Mini» incluye 2 usuario(s) por médico%','d',left(sqlerrm,120)));
    end;
    begin
      update public.organization_users set role_code = 'client', is_active = true where organization_id = v_a and user_id = v_sec2::uuid;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-89 · ATAQUE: cambiar el rol de una secretaria inactiva a médico y activarla tampoco evade','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-89 · ATAQUE: cambiar el rol de una secretaria inactiva a médico y activarla tampoco evade','ok',sqlerrm like 'Su plan «QA Mini» incluye 2 usuario(s)%','d',left(sqlerrm,120)));
    end;
    update public.organization_users set role_code = 'capturer' where organization_id = v_a and user_id = v_sec1::uuid; get diagnostics v_n = row_count;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-90 · Cambios que no suman usuarios (la secretaria sigue siendo secretaria) no se bloquean','ok',coalesce((v_n = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.plan_limits where plan_code = 'qa_tiny' and limit_code = 'max_medicos';
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
      update public.providers set is_active = true where id = v_pa2;
      update public.organization_users set is_active = true where organization_id = v_a and user_id = v_sec2::uuid;
      select count(*) into v_n from public.organization_users where organization_id = v_a and role_code = 'capturer' and is_active;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-91 · Los topes de personal crecen con los médicos activos: con 2 médicos caben 2 secretarias y 4 usuarios','ok',coalesce((v_n = 2), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated')::text, true);
    insert into public.organization_users (organization_id, user_id, role_code) values (v_b, v_mc::uuid, 'client'), (v_b, v_sec2::uuid, 'capturer');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-92 · Fundador/Legado agrega usuarios y secretarias sin límite','ok',coalesce(((select count(*) from public.organization_users where organization_id = v_b and is_active) = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.my_plan_usage();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-93 · El Médico ve que el interruptor está encendido y que su personal está completo (2 de 2 usuarios, 1 de 1 secretaria)','ok',coalesce(((v_r->>'enforced')::boolean and (select (l->>'used')::int from jsonb_array_elements(v_r->'limits') l where l->>'code' = 'usuarios_por_medico') = 2 and (select l->>'state' from jsonb_array_elements(v_r->'limits') l where l->>'code' = 'secretarias_por_medico') = 'al_limite'), false),'d',(v_r->'limits')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.plans_set_enforce(true, 'Activación de prueba con un cliente sin plan');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-94 · No se activa el bloqueo si hay clientes sin plan, y dice cuáles','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-94 · No se activa el bloqueo si hay clientes sin plan, y dice cuáles','ok',sqlerrm like 'No se puede activar el bloqueo: hay clientes sin plan%QA PL Consultorio C%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.plans_set_enforce(false, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-95 · El interruptor exige un motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-95 · El interruptor exige un motivo','ok',sqlerrm like 'Escriba el motivo (mínimo 10 caracteres)%','d',left(sqlerrm,120)));
    end;
    perform public.plans_set_enforce(false, 'Se apaga el bloqueo mientras se revisan los límites');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-96 · Apagado por plans_set_enforce: el interruptor queda en falso y deja constancia en la bitácora','ok',coalesce((not exists (select 1 from public.app_settings where enforce_plans) and exists (select 1 from public.audit_log where table_name = 'app_settings' and record_id = 'enforce_plans' and new_values->>'motivo' like 'Se apaga el bloqueo%')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated')::text, true);
    insert into public.providers (organization_id, full_name, specialty) values (v_a, 'Dr. Extra QA', 'Urología');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-97 · Con el interruptor de nuevo apagado el 2º médico entra sin problema','ok',coalesce(((select count(*) from public.providers where organization_id = v_a and is_active) = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.assign_org_plan(v_c, 'legado', current_date, 'Cliente C recibe el plan legado en la prueba');
      perform public.plans_set_enforce(true, 'Activación de prueba con todos los clientes con plan');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-98 · Con todos los clientes con plan, plans_set_enforce lo enciende','ok',coalesce((exists (select 1 from public.app_settings where enforce_plans)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      delete from public.service_lines where submission_id in (v_sub_a, v_sub_a2);
      update public.app_settings set enforce_plans = false where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 71', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 72', v_proc, 1, 100);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_sub_a, v_a, v_per + 3, 'Paciente QA 73', v_proc, 1, 100);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.plan_save('qa_tiny2', 'QA Mini 2', 'saas');
      perform public.plan_limit_set('qa_tiny2', 'reclamaciones_mes_por_medico', 1);
      v_r := public.assign_org_plan(v_a, 'qa_tiny2', current_date + 1, 'Bajada de plan de prueba, sobrepasa el límite');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-99 · Al bajar de plan avisa lo que el cliente ya usa por encima del plan nuevo y NO borra nada','ok',coalesce((jsonb_array_length(v_r->'warnings') >= 1 and v_r->'warnings'->>0 like 'Reclamaciones al mes por médico: el cliente ya usa 3 y el plan nuevo permite 1%' and (select count(*) from public.service_lines where submission_id = v_sub_a) = 3), false),'d',(v_r->'warnings')::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.plans (code, name, line) values ('qa_tiny3', 'QA Mini 3', 'saas');
      insert into public.organization_plans (organization_id, plan_code, starts_on, status) values (v_c, 'qa_tiny3', current_date, 'activo');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      begin
        perform public.plan_save('qa_tiny3', 'QA Mini 3', 'saas', null, null, null, null, null, false);
        v_n := -1;
      exception when others then v_n := case when sqlerrm like 'El plan tiene clientes asignados%' then 1 else 0 end; end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-100 · No se desactiva un plan que tiene clientes asignados','ok',coalesce((v_n = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.plan_limits (plan_code, limit_code, limit_value, on_exceed) values ('qa_tiny', 'max_medicos', 1, 'bloquear') on conflict (plan_code, limit_code) do nothing;
      begin
        insert into public.plan_limits (plan_code, limit_code, limit_value) values ('qa_tiny', 'limite_inexistente', 5);
        v_n := -1;
      exception when others then v_n := case when sqlstate = '23503' then 1 else 0 end; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-101 · Un límite que no está en el catálogo no se puede sembrar (llave foránea)','ok',coalesce((v_n = 1), false),'d',(null)::text));
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

revoke all on function app.qa_run_tests_planes() from public, anon, authenticated;
