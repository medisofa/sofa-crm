-- 185 · Suite de la 184 (versiones de tarifario por ARS y plan, I57). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_tarifas_versiones();
create or replace function app.qa_run_tests_tarifas_versiones()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_a constant uuid := '01840000-0000-4000-8000-000000000001'; v_b constant uuid := '01840000-0000-4000-8000-000000000002'; v_pa constant uuid := '01840000-0000-4000-8000-000000000011'; v_pb constant uuid := '01840000-0000-4000-8000-000000000012';
  v_sa constant text := '01840000-0000-4000-8000-000000000021'; v_ad constant text := '01840000-0000-4000-8000-000000000022'; v_bil constant text := '01840000-0000-4000-8000-000000000023'; v_ops constant text := '01840000-0000-4000-8000-000000000024'; v_co constant text := '01840000-0000-4000-8000-000000000025';
  v_ma constant text := '01840000-0000-4000-8000-000000000031'; v_sec constant text := '01840000-0000-4000-8000-000000000032'; v_mb constant text := '01840000-0000-4000-8000-000000000033';
  v_h uuid; v_m uuid; v_s uuid; v_plan uuid; v_p1 uuid; v_p2 uuid; v_p3 uuid; v_p4 uuid; v_p5 uuid; v_p6 uuid; v_p7 uuid; v_p8 uuid;
  v_c1 text; v_c2 text; v_c3 text; v_c4 text; v_c5 text; v_c6 text; v_c7 text; v_c8 text; v_simon2 text; v_simon1 text; v_cups1 text;
  v_per date; v_d0 date; v_d1 date; v_sub_a uuid; v_sub_b uuid; v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid; v_lb uuid; v_r jsonb; v_r2 jsonb; v_rl text; v_v1 uuid; v_v2 uuid; v_vm uuid; v_vp uuid;
  v_n0 int; v_n1 int; v_t1 uuid; v_vpl uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '178') or not exists (select 1 from app.schema_migrations where version = '184') then
    raise exception 'Falta la migración 184 (o la 178). Aplícalas y vuelve a correr las pruebas.';
  end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.tv.sa@sofa.test','x'),(v_ad::uuid,'qa.tv.ad@sofa.test','x'),(v_bil::uuid,'qa.tv.bil@sofa.test','x'),(v_ops::uuid,'qa.tv.ops@sofa.test','x'),(v_co::uuid,'qa.tv.co@sofa.test','x'),(v_ma::uuid,'qa.tv.ma@sofa.test','x'),(v_sec::uuid,'qa.tv.sec@sofa.test','x'),(v_mb::uuid,'qa.tv.mb@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.tv.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_a, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA TV Consultorio A', '00000018401', 'Médico independiente', 'activo', current_date - 90, '8095558401');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_b, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA TV Consultorio B', '00000018402', 'Médico independiente', 'activo', current_date - 90, '8095558402');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_a, 'Dr. TV A QA', 'Cardiología', true), (v_pb, v_b, 'Dr. TV B QA', 'Ortopedia', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_co::uuid, 'assistant', true),
      (v_a, v_ma::uuid, 'client', true), (v_a, v_sec::uuid, 'capturer', true), (v_b, v_mb::uuid, 'client', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_pa, v_a, true, true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa57_h', 'ARS QA Humana Ficticia', 'Contributivo', true) returning id into v_h;
    insert into public.ars (code, name, regime_default, is_active) values ('qa57_m', 'ARS QA Mapa Ficticia', 'Contributivo', true) returning id into v_m;
    insert into public.ars (code, name, regime_default, is_active) values ('qa57_s', 'ARS QA Senda Ficticia', 'Contributivo', true) returning id into v_s;
    insert into public.ars_plans (ars_id, name, regime) values (v_h, 'QA Plan Royal Ficticio', 'Contributivo') returning id into v_plan;
    insert into public.procedures (internal_code, description, service_type_code, is_active)
    select 'QA57-P' || g, 'SERVICIO QA FICTICIO ' || g, (select service_type_code from public.procedures where is_active limit 1), true from generate_series(1, 8) g;
    insert into public.procedure_codes (procedure_id, code_system, code)
    select p.id, c.sys, c.sys || '-QA57-' || right(p.internal_code, 1) from public.procedures p cross join (values ('SIMON'), ('CUPS')) c(sys) where p.internal_code like 'QA57-P%';
    select (a)[1], (a)[2], (a)[3], (a)[4], (a)[5], (a)[6], (a)[7], (a)[8] into v_p1, v_p2, v_p3, v_p4, v_p5, v_p6, v_p7, v_p8
      from (select array_agg(id order by internal_code) a from public.procedures where internal_code like 'QA57-P%') y;
    select internal_code into v_c1 from public.procedures where id = v_p1; select internal_code into v_c2 from public.procedures where id = v_p2;
    select internal_code into v_c3 from public.procedures where id = v_p3; select internal_code into v_c4 from public.procedures where id = v_p4;
    select internal_code into v_c5 from public.procedures where id = v_p5; select internal_code into v_c6 from public.procedures where id = v_p6;
    select internal_code into v_c7 from public.procedures where id = v_p7; select internal_code into v_c8 from public.procedures where id = v_p8;
    select min(code) into v_simon1 from public.procedure_codes where procedure_id = v_p1 and code_system = 'SIMON';
    select min(code) into v_simon2 from public.procedure_codes where procedure_id = v_p2 and code_system = 'SIMON';
    select min(code) into v_cups1 from public.procedure_codes where procedure_id = v_p1 and code_system = 'CUPS';
    v_per := date_trunc('month', current_date - interval '1 month')::date;
    v_d0 := v_per - 40; v_d1 := v_per + 10;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_h, v_per, 1, 'borrador') returning id into v_sub_a;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_b, v_pb, v_h, v_per, 1, 'borrador') returning id into v_sub_b;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-01 · La migración 184 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '184')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-02 · La suite crea ocho servicios ficticios con códigos SIMON y CUPS propios (no depende del catálogo real)','ok',coalesce((v_p8 is not null and v_simon1 is not null and v_cups1 is not null and v_simon2 is not null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-03 · tariff_versions está protegida: sin permisos para anon ni authenticated y con RLS activo','ok',coalesce((not has_table_privilege('authenticated', 'public.tariff_versions', 'select') and not has_table_privilege('authenticated', 'public.tariff_versions', 'insert') and not has_table_privilege('anon', 'public.tariff_versions', 'select') and (select relrowsecurity from pg_class where oid = 'public.tariff_versions'::regclass)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-04 · Existe la restricción de no solapamiento de vigencias entre versiones y la de tarifas por código sigue ahí','ok',coalesce((exists (select 1 from pg_constraint where conrelid = 'public.tariff_versions'::regclass and conname = 'tariff_versions_no_overlap' and contype = 'x') and exists (select 1 from pg_constraint where conrelid = 'public.tariffs'::regclass and conname = 'tariffs_no_overlap' and contype = 'x')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-05 · Toda versión migrada agrupa al menos una tarifa existente (no quedan versiones vacías) y ninguna tarifa quedó fuera de su versión migrada','ok',coalesce((not exists (select 1 from public.tariff_versions v where v.source = 'Migración 184' and not exists (select 1 from public.tariffs t where t.version_id = v.id)) and not exists (select 1 from public.tariffs t where t.version_id is null and lower(t.valid_during) < '2026-10-01' and t.created_at < (select min(created_at) from public.tariff_versions where source = 'Migración 184'))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-06 · Las funciones públicas no están abiertas a anon y las internas no se llaman desde la API','ok',coalesce((not has_function_privilege('anon', 'public.tariff_version_publish(uuid,uuid,uuid,text,date,date,jsonb,boolean,text,text,text)', 'execute') and not has_function_privilege('anon', 'public.tariff_stale_claims(uuid,uuid,date,date,text,integer)', 'execute') and not has_function_privilege('anon', 'public.tariff_price_indicator(uuid,uuid,date,date)', 'execute') and has_function_privilege('authenticated', 'public.tariff_version_compare(uuid,uuid)', 'execute') and not has_function_privilege('authenticated', 'app.tariff_line_prices(uuid,uuid[],date,date)', 'execute') and not has_function_privilege('authenticated', 'app.tariff_version_analyze(uuid,uuid,uuid,date,jsonb,boolean)', 'execute') and not has_function_privilege('authenticated', 'app.tariff_price_at(uuid,uuid,uuid,date,uuid)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-07 · Todas las funciones nuevas son SECURITY DEFINER con search_path vacío','ok',coalesce(((select bool_and(prosecdef and 'search_path=""' = any (proconfig)) from pg_proc where proname in ('tariff_version_publish','tariff_version_preview','tariff_versions_list','tariff_version_items','tariff_version_compare','tariff_stale_claims','tariff_price_indicator','tariff_admin_check','tariff_staff_check','tariff_price_at','tariff_line_prices','tariff_alert_orgs','tariff_version_analyze') and pronamespace in ('public'::regnamespace, 'app'::regnamespace))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_version_publish(v_h, null, null, 'Intento sin permiso', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-08 · ATAQUE: Facturación no publica versiones de tarifario','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-08 · ATAQUE: Facturación no publica versiones de tarifario','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_preview(v_h, null, null, v_d0, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-09 · ATAQUE: Facturación no usa la vista previa de carga','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-09 · ATAQUE: Facturación no usa la vista previa de carga','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_version_publish(v_h, null, null, 'Intento sin permiso', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-10 · ATAQUE: Operaciones no publica versiones de tarifario','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-10 · ATAQUE: Operaciones no publica versiones de tarifario','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_preview(v_h, null, null, v_d0, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-11 · ATAQUE: Operaciones no usa la vista previa de carga','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-11 · ATAQUE: Operaciones no usa la vista previa de carga','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_version_publish(v_h, null, null, 'Intento sin permiso', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-12 · ATAQUE: El Comercial no publica versiones de tarifario','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-12 · ATAQUE: El Comercial no publica versiones de tarifario','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_preview(v_h, null, null, v_d0, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-13 · ATAQUE: El Comercial no usa la vista previa de carga','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-13 · ATAQUE: El Comercial no usa la vista previa de carga','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_version_publish(v_h, null, null, 'Intento sin permiso', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-14 · ATAQUE: El Médico no publica versiones de tarifario','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-14 · ATAQUE: El Médico no publica versiones de tarifario','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_preview(v_h, null, null, v_d0, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-15 · ATAQUE: El Médico no usa la vista previa de carga','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-15 · ATAQUE: El Médico no usa la vista previa de carga','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_version_publish(v_h, null, null, 'Intento sin permiso', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-16 · ATAQUE: La Secretaria no publica versiones de tarifario','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-16 · ATAQUE: La Secretaria no publica versiones de tarifario','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_preview(v_h, null, null, v_d0, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-17 · ATAQUE: La Secretaria no usa la vista previa de carga','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-17 · ATAQUE: La Secretaria no usa la vista previa de carga','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_version_publish(v_h, null, null, 'Intento sin permiso', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-18 · ATAQUE: El Médico de otro cliente no publica versiones de tarifario','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-18 · ATAQUE: El Médico de otro cliente no publica versiones de tarifario','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_preview(v_h, null, null, v_d0, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000')), false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-19 · ATAQUE: El Médico de otro cliente no usa la vista previa de carga','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-19 · ATAQUE: El Médico de otro cliente no usa la vista previa de carga','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA cargan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_versions_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-20 · ATAQUE: El Médico no lista las versiones de tarifario','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-20 · ATAQUE: El Médico no lista las versiones de tarifario','ok',sqlerrm like 'Las versiones de tarifario las consulta el personal de SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_versions_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-21 · ATAQUE: La Secretaria no lista las versiones de tarifario','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-21 · ATAQUE: La Secretaria no lista las versiones de tarifario','ok',sqlerrm like 'Las versiones de tarifario las consulta el personal de SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_versions_list();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-22 · ATAQUE: Facturación no lista las versiones de tarifario','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-22 · ATAQUE: Facturación no lista las versiones de tarifario','ok',sqlerrm like 'Las versiones de tarifario las consulta el personal de SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform 1 from public.tariff_versions limit 1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-23 · ATAQUE: el Médico no lee la tabla de versiones por la API','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-23 · ATAQUE: el Médico no lee la tabla de versiones por la API','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.tariff_versions (ars_id, name, valid_during) values (v_h, 'Versión falsa', daterange(current_date, null));
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-24 · ATAQUE: el Médico no inserta una versión por la API','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-24 · ATAQUE: el Médico no inserta una versión por la API','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    update public.tariffs set valid_during = daterange(current_date, null) where true; get diagnostics v_n = row_count;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-25 · ATAQUE: el Médico no cambia ninguna tarifa con UPDATE directo (la política no le deja tocar ninguna fila)','ok',coalesce((v_n = 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      update public.tariff_versions set name = 'Cambio directo' where true;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-26 · ATAQUE: ni el Super Admin escribe en tariff_versions por la API (solo con las funciones)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-26 · ATAQUE: ni el Super Admin escribe en tariff_versions por la API (solo con las funciones)','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.tariff_version_publish(v_h, null, null, 'QA Tarifario 2026 Humana', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1000'), jsonb_build_object('servicio', v_c2, 'tarifa', '2000'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c4, 'tarifa', '4000'), jsonb_build_object('servicio', v_c5, 'tarifa', '5000'), jsonb_build_object('servicio', v_c6, 'tarifa', '6000')), false, 'Excel', 'qa.xlsx', null);
    v_v1 := (v_r->>'version_id')::uuid;
    v_r2 := public.tariff_version_publish(v_m, null, null, 'QA Tarifario 2026 Mapa', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '900'), jsonb_build_object('servicio', v_c2, 'tarifa', '1900'), jsonb_build_object('servicio', v_c3, 'tarifa', '2900'), jsonb_build_object('servicio', v_c4, 'tarifa', '3900')), false, 'Excel', 'qa.xlsx', null);
    v_vm := (v_r2->>'version_id')::uuid;
    v_r2 := public.tariff_version_publish(v_s, null, null, 'QA Tarifario 2026 Senda', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1100'), jsonb_build_object('servicio', v_c2, 'tarifa', '2100'), jsonb_build_object('servicio', v_c7, 'tarifa', '7100'), jsonb_build_object('servicio', v_c8, 'tarifa', '8100')), false, 'Excel', 'qa.xlsx', null);
    v_vp := (v_r2->>'version_id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-27 · Publicar la versión 1 crea 6 tarifas generales de la ARS enlazadas a la versión, vigentes desde la fecha de inicio','ok',coalesce(((v_r->>'items')::int = 6 and (v_r->>'new')::int = 6 and (v_r->>'retired')::int = 0 and (select count(*) from public.tariffs where version_id = v_v1 and provider_id is null and organization_id is null and lower(valid_during) = v_d0 and upper(valid_during) is null) = 6), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-28 · Tres ARS ficticias con su versión cada una (tarifarios de ARS distintos no se mezclan)','ok',coalesce(((select count(*) from public.tariff_versions where ars_id in (v_h, v_m, v_s)) = 3 and (select count(*) from public.tariffs where ars_id = v_m) = 4 and (select count(*) from public.tariffs where ars_id = v_s) = 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-29 · Las tarifas de la versión guardan el código tal como vino en el archivo y el nombre de la versión como fuente','ok',coalesce(((select count(*) from public.tariffs where version_id = v_v1 and ars_service_code is not null and source like 'Versión: QA Tarifario 2026 Humana') = 6), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-30 · La publicación queda en la bitácora de auditoría (tariff_versions)','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'tariff_versions' and record_id = v_v1::text and operation = 'INSERT')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r2 := public.tariff_version_publish(v_h, v_plan, null, 'QA Plan Royal 2026', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1500'), jsonb_build_object('servicio', v_c2, 'tarifa', '2500')), false, 'Excel', 'qa.xlsx', null);
    v_vpl := (v_r2->>'version_id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-31 · Una versión de un plan convive con la versión general de la misma ARS (la clave incluye el plan) y la del plan manda para ese plan','ok',coalesce(((select count(*) from public.tariff_versions where ars_id = v_h and valid_during @> current_date) = 2 and (app.tariff_for(v_p1, v_h, v_d0 + 1, null, v_plan)).amount = 1500 and (app.tariff_for(v_p1, v_h, v_d0 + 1, null, null)).amount = 1000 and (app.tariff_for(v_p3, v_h, v_d0 + 1, null, v_plan)).amount = 3000), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_sub_a, s.organization_id, v_per + 5, 'Paciente QA L1', v_p1, 1, 1000 from public.submissions s where s.id = v_sub_a;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_sub_a, s.organization_id, v_per + 20, 'Paciente QA L2', v_p1, 1, 1000 from public.submissions s where s.id = v_sub_a;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_sub_a, s.organization_id, v_per + 20, 'Paciente QA L3', v_p3, 1, 3000 from public.submissions s where s.id = v_sub_a;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_sub_a, s.organization_id, v_per + 20, 'Paciente QA L4', v_p4, 1, 4000 from public.submissions s where s.id = v_sub_a;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_sub_b, s.organization_id, v_per + 20, 'Paciente QA LB', v_p1, 1, 1000 from public.submissions s where s.id = v_sub_b;
    select id into v_l1 from public.service_lines where submission_id = v_sub_a and patient_name = 'Paciente QA L1';
    select id into v_l2 from public.service_lines where submission_id = v_sub_a and patient_name = 'Paciente QA L2';
    select id into v_l3 from public.service_lines where submission_id = v_sub_a and patient_name = 'Paciente QA L3';
    select id into v_l4 from public.service_lines where submission_id = v_sub_a and patient_name = 'Paciente QA L4';
    select id into v_lb from public.service_lines where submission_id = v_sub_b and patient_name = 'Paciente QA LB';
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-32 · El precio de la línea sale del tarifario vigente en la FECHA DEL SERVICIO (1000 / 1000 / 3000 / 4000 con la versión 1)','ok',coalesce(((select tariff_amount from public.service_lines where id = v_l1) = 1000 and (select tariff_amount from public.service_lines where id = v_l3) = 3000 and (select tariff_amount from public.service_lines where id = v_l4) = 4000 and (select tariff_valid_from from public.service_lines where id = v_l1) = v_d0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.tariff_price_indicator(null, v_h, v_per, v_per + 27);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-33 · Indicador antes del cambio: todas las líneas conocidas tienen el precio vigente (100 %) y no hay alertas','ok',coalesce(((v_r->>'pct')::numeric = 100 and (v_r->>'lines')::int = 5 and (v_r->>'stale')::int = 0 and (public.tariff_stale_claims(null, v_h)->>'total')::int = 0), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select count(*) into v_n0 from public.tariffs; select count(*) into v_n1 from public.tariff_versions;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.tariff_version_preview(v_h, null, null, v_d1, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-34 · La vista previa clasifica: 1 nueva, 2 cambian, 1 igual y retira 3 códigos que no vienen en el archivo','ok',coalesce(((v_r->>'new')::int = 1 and (v_r->>'changed')::int = 2 and (v_r->>'same')::int = 1 and (v_r->>'retired_count')::int = 3 and jsonb_array_length(v_r->'errors') = 0), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-35 · La vista previa avisa del retiro y de la fecha pasada (qué hacer con el archivo parcial)','ok',coalesce(((v_r->>'warnings') like '%no vienen en el archivo y se retirarán%' and (v_r->>'warnings') like '%fecha pasada%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-36 · La vista previa calcula el cambio porcentual (+20 % y -10 %)','ok',coalesce((exists (select 1 from jsonb_array_elements(v_r->'rows') e where e->>'change' = 'cambia' and (e->>'diff_pct')::numeric = 20.0) and exists (select 1 from jsonb_array_elements(v_r->'rows') e where e->>'change' = 'cambia' and (e->>'diff_pct')::numeric = -10.0)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-37 · La vista previa no guarda nada (mismas tarifas y versiones que antes)','ok',coalesce(((select count(*) from public.tariffs) = v_n0 and (select count(*) from public.tariff_versions) = v_n1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r2 := public.tariff_version_preview(v_h, null, null, v_d1, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-38 · El Administrador también usa la vista previa (mismo resultado que el Super Admin)','ok',coalesce(((v_r2->>'changed')::int = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select t.id into v_t1 from public.tariffs t where t.version_id = v_v1 and t.procedure_id = v_p1;
    begin
      update public.tariffs set valid_during = daterange(lower(valid_during), v_d1) where id = v_t1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-39 · Sin publicar versión, el servidor sigue negando cerrar una tarifa antes de servicios que ya la usan (guardia original)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-39 · Sin publicar versión, el servidor sigue negando cerrar una tarifa antes de servicios que ya la usan (guardia original)','ok',sqlerrm like 'No se puede cerrar la tarifa antes de servicios que ya la usan%','d',left(sqlerrm,120)));
    end;
    begin
      update public.tariffs set amount = 1 where id = v_t1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-40 · ATAQUE: el Super Admin no cambia el monto de una tarifa con UPDATE directo (se crea una versión nueva)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-40 · ATAQUE: el Super Admin no cambia el monto de una tarifa con UPDATE directo (se crea una versión nueva)','ok',sqlerrm like 'Una tarifa no se modifica%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-41 · ERROR: una versión que inicia antes o el mismo día que la última se rechaza con la fecha de la última y qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-41 · ERROR: una versión que inicia antes o el mismo día que la última se rechaza con la fecha de la última y qué hacer','ok',sqlerrm like 'Ya existe una versión que inicia el%Cambie la fecha de inicio%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-42 · ERROR: el mismo día de inicio de la última versión también se rechaza (no hay vigencias solapadas)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-42 · ERROR: el mismo día de inicio de la última versión también se rechaza (no hay vigencias solapadas)','ok',sqlerrm like 'Ya existe una versión que inicia el%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, v_d1 - 1, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-43 · ERROR: «hasta» anterior a «desde»','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-43 · ERROR: «hasta» anterior a «desde»','ok',sqlerrm like 'La fecha «hasta» no puede ser anterior%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'ab', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-44 · ERROR: nombre demasiado corto','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-44 · ERROR: nombre demasiado corto','ok',sqlerrm like 'Ponga un nombre a la versión%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', current_date + 400, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-45 · ERROR: fecha de inicio a más de un año','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-45 · ERROR: fecha de inicio a más de un año','ok',sqlerrm like 'La fecha de inicio debe estar entre%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, '[]'::jsonb, false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-46 · ERROR: archivo sin filas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-46 · ERROR: archivo sin filas','ok',sqlerrm like 'El archivo no trae filas%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, '{}'::jsonb, false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-47 · ERROR: archivo que no es una lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-47 · ERROR: archivo que no es una lista','ok',sqlerrm like 'El archivo no trae filas%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, (select jsonb_agg(jsonb_build_object('servicio', v_c1, 'tarifa', '1')) from generate_series(1, 3001)), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-48 · ERROR: más de 3,000 filas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-48 · ERROR: más de 3,000 filas','ok',sqlerrm like 'Máximo 3,000 filas%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', 'NO-EXISTE-QA', 'tarifa', '10')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-49 · ERROR: servicio que no existe en el catálogo, no se guarda nada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-49 · ERROR: servicio que no existe en el catálogo, no se guarda nada','ok',sqlerrm like 'Corrija las 1 fila(s) con error%No se guardó nada%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '0')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-50 · ERROR: tarifa en cero','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-50 · ERROR: tarifa en cero','ok',sqlerrm like 'Corrija las 1 fila(s) con error%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '-5')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-51 · ERROR: tarifa negativa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-51 · ERROR: tarifa negativa','ok',sqlerrm like 'Corrija las 1 fila(s) con error%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', 'mil pesos')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-52 · ERROR: tarifa con texto','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-52 · ERROR: tarifa con texto','ok',sqlerrm like 'Corrija las 1 fila(s) con error%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c1, 'tarifa', '1300')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-53 · ERROR: servicio repetido en el archivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-53 · ERROR: servicio repetido en el archivo','ok',sqlerrm like 'Corrija las 1 fila(s) con error%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('tarifa', '100')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-54 · ERROR: fila sin servicio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-54 · ERROR: fila sin servicio','ok',sqlerrm like 'Corrija las 1 fila(s) con error%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, null, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'simon', v_simon2, 'tarifa', '100')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-55 · ERROR: SIMON que corresponde a otro servicio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-55 · ERROR: SIMON que corresponde a otro servicio','ok',sqlerrm like 'Corrija las 1 fila(s) con error%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_m, v_plan, null, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-56 · ERROR: un plan que no es de esa ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-56 · ERROR: un plan que no es de esa ARS','ok',sqlerrm like 'El plan no pertenece a esa ARS%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish('01840000-0000-4000-8000-0000000000ff'::uuid, null, null, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-57 · ERROR: ARS inexistente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-57 · ERROR: ARS inexistente','ok',sqlerrm like 'Elija una ARS activa%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_publish(v_h, null, '01840000-0000-4000-8000-0000000000fe'::uuid, 'QA Versión de error', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false, 'Excel', 'qa.xlsx', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-58 · ERROR: médico inexistente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-58 · ERROR: médico inexistente','ok',sqlerrm like 'El médico no existe o está inactivo%','d',left(sqlerrm,120)));
    end;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-59 · Ningún error dejó nada guardado (la ARS Humana sigue con su versión 1 vigente y 6 tarifas abiertas)','ok',coalesce(((select count(*) from public.tariff_versions where ars_id = v_h and plan_id is null and provider_id is null) = 1 and (select count(*) from public.tariffs where ars_id = v_h and plan_id is null and upper(valid_during) is null) = 6), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.tariff_version_publish(v_h, null, null, 'QA Tarifario 2026 Humana B', v_d1, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1200'), jsonb_build_object('servicio', v_c2, 'tarifa', '1800'), jsonb_build_object('servicio', v_c3, 'tarifa', '3000'), jsonb_build_object('servicio', v_c7, 'tarifa', '8000')), false, 'Excel', 'qa.xlsx', null);
    v_v2 := (v_r->>'version_id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-60 · La versión 2 retroactiva se publica aunque ya hay reclamaciones con el precio anterior (no se bloquea): cierra 6 tarifas, retira 3 y avisa 2 reclamaciones con precio vencido','ok',coalesce(((v_r->>'closed_tariffs')::int = 6 and (v_r->>'retired')::int = 3 and (v_r->>'new')::int = 1 and (v_r->>'changed')::int = 2 and (v_r->>'stale_claims')::int = 2), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-61 · La versión 1 queda cerrada en la fecha de inicio de la 2 (sin solapamiento) y la 2 queda vigente y abierta','ok',coalesce(((select upper(valid_during) from public.tariff_versions where id = v_v1) = v_d1 and (select upper(valid_during) is null and valid_during @> current_date from public.tariff_versions where id = v_v2) and not exists (select 1 from public.tariff_versions a join public.tariff_versions c on a.id < c.id and a.ars_id = c.ars_id and a.plan_id is not distinct from c.plan_id and a.provider_id is not distinct from c.provider_id and a.valid_during && c.valid_during)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-62 · Los códigos que no vinieron quedan retirados: sin tarifa desde la fecha de inicio y con tarifa el día anterior','ok',coalesce(((app.tariff_for(v_p4, v_h, v_d1, null, null)).id is null and (app.tariff_for(v_p4, v_h, v_d1 - 1, null, null)).amount = 4000 and (app.tariff_for(v_p5, v_h, v_d1 + 5, null, null)).id is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-63 · El precio se resuelve por la fecha del servicio: el día anterior al corte vale el precio de la versión 1 y desde el corte el de la 2','ok',coalesce(((app.tariff_for(v_p1, v_h, v_d1 - 1, null, null)).amount = 1000 and (app.tariff_for(v_p1, v_h, v_d1, null, null)).amount = 1200 and (app.tariff_for(v_p2, v_h, v_d1, null, null)).amount = 1800 and (app.tariff_for(v_p7, v_h, v_d1, null, null)).amount = 8000), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-64 · La tarifa del plan (versión aparte) no se afectó con la versión general','ok',coalesce(((app.tariff_for(v_p1, v_h, v_d1 + 1, null, v_plan)).amount = 1500), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-65 · Las reclamaciones ya capturadas conservan su precio congelado (la versión nueva no reescribe nada)','ok',coalesce(((select tariff_amount from public.service_lines where id = v_l1) = 1000 and (select tariff_amount from public.service_lines where id = v_l2) = 1000 and (select tariff_amount from public.service_lines where id = v_l4) = 4000), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_sub_a, s.organization_id, v_per + 5, 'Paciente QA L5', v_p1, 1, 1000 from public.submissions s where s.id = v_sub_a;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_sub_a, s.organization_id, v_per + 25, 'Paciente QA L6', v_p1, 1, 1200 from public.submissions s where s.id = v_sub_a;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_sub_a, s.organization_id, v_per + 25, 'Paciente QA L7', v_p4, 1, 4000 from public.submissions s where s.id = v_sub_a;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-66 · Capturar HOY una línea con fecha de servicio anterior al corte usa el precio viejo y con fecha posterior el nuevo (no importa la fecha de captura)','ok',coalesce(((select tariff_amount from public.service_lines where submission_id = v_sub_a and patient_name = 'Paciente QA L5') = 1000 and (select tariff_amount from public.service_lines where submission_id = v_sub_a and patient_name = 'Paciente QA L6') = 1200 and (select amount_ok from public.service_lines where submission_id = v_sub_a and patient_name = 'Paciente QA L5') is not null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-67 · Un servicio retirado queda sin tarifa para fechas posteriores al corte (tariff_amount nulo)','ok',coalesce(((select tariff_amount from public.service_lines where submission_id = v_sub_a and patient_name = 'Paciente QA L7') is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.tariff_versions_list(v_h, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-68 · La lista muestra para la ARS Humana: versión 1 cerrada, versión 2 vigente y la versión del plan, con sus fechas y cantidad de códigos','ok',coalesce((jsonb_array_length(v_r) = 3 and exists (select 1 from jsonb_array_elements(v_r) e where e->>'id' = v_v1::text and e->>'state' = 'cerrada' and (e->>'items')::int = 6 and (e->>'valid_to')::date = v_d1 - 1) and exists (select 1 from jsonb_array_elements(v_r) e where e->>'id' = v_v2::text and e->>'state' = 'vigente' and (e->>'items')::int = 4 and e->>'valid_to' is null and e->>'by' is not null)), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_r := public.tariff_version_items(v_v2);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-69 · El contenido de una versión trae sus 4 códigos con precio','ok',coalesce((jsonb_array_length(v_r->'items') = 4 and exists (select 1 from jsonb_array_elements(v_r->'items') e where (e->>'amount')::numeric = 8000)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.tariff_version_compare(v_v1, v_v2);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-70 · El comparador v1 → v2: 1 subió, 1 bajó, 1 nuevo, 3 retirados y 1 igual, con porcentaje promedio de los cambios','ok',coalesce(((v_r->'summary'->>'subio')::int = 1 and (v_r->'summary'->>'bajo')::int = 1 and (v_r->'summary'->>'nuevo')::int = 1 and (v_r->'summary'->>'retirado')::int = 3 and (v_r->'summary'->>'igual')::int = 1 and (v_r->'summary'->>'avg_pct')::numeric = 5.0), false),'d',(v_r->'summary')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-71 · El comparador ordena primero lo que subió y trae precios de ambas versiones y el porcentaje','ok',coalesce((v_r->'rows'->0->>'change' = 'subio' and (v_r->'rows'->0->>'amount_a')::numeric = 1000 and (v_r->'rows'->0->>'amount_b')::numeric = 1200 and (v_r->'rows'->0->>'diff_pct')::numeric = 20.0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.tariff_version_compare(v_v2, v_v1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-72 · Comparar al revés invierte el sentido (1 bajó, 1 subió, 3 nuevos, 1 retirado)','ok',coalesce(((v_r->'summary'->>'subio')::int = 1 and (v_r->'summary'->>'bajo')::int = 1 and (v_r->'summary'->>'nuevo')::int = 3 and (v_r->'summary'->>'retirado')::int = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.tariff_version_compare(v_v1, v_vm);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-73 · ERROR: no se comparan versiones de ARS distintas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-73 · ERROR: no se comparan versiones de ARS distintas','ok',sqlerrm like 'Solo se comparan versiones de la misma ARS%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_compare(v_v1, v_v1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-74 · ERROR: no se compara una versión consigo misma','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-74 · ERROR: no se compara una versión consigo misma','ok',sqlerrm like 'Elija dos versiones distintas%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_compare(v_v1, '01840000-0000-4000-8000-0000000000fd'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-75 · ERROR: versión inexistente en el comparador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-75 · ERROR: versión inexistente en el comparador','ok',sqlerrm like 'Elija dos versiones de la lista%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_compare(v_v1, v_vpl);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-76 · ERROR: no se comparan versión general y versión de un plan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-76 · ERROR: no se comparan versión general y versión de un plan','ok',sqlerrm like 'Solo se comparan versiones de la misma ARS%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.tariff_version_compare(v_v1, v_v2);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-77 · Operaciones (personal de SOFA) sí consulta el comparador y la lista','ok',coalesce(((v_r->'summary'->>'subio')::int = 1 and jsonb_array_length(public.tariff_versions_list(v_h)) = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-78 · El Comercial (personal de SOFA) sí consulta la lista','ok',coalesce((jsonb_array_length(public.tariff_versions_list(v_h)) = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_version_compare(v_v1, v_v2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-79 · ATAQUE: el Médico no usa el comparador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-79 · ATAQUE: el Médico no usa el comparador','ok',sqlerrm like 'Las versiones de tarifario las consulta el personal de SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_version_items(v_v2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-80 · ATAQUE: el Médico no lee el contenido de una versión','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-80 · ATAQUE: el Médico no lee el contenido de una versión','ok',sqlerrm like 'Las versiones de tarifario las consulta el personal de SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.tariff_stale_claims(null, v_h);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-81 · La alerta lista las 2 reclamaciones con precio vencido (L2 de A y LB de B) con precio congelado, precio vigente y diferencia','ok',coalesce(((v_r->>'total')::int = 2 and exists (select 1 from jsonb_array_elements(v_r->'rows') e where e->>'line_id' = v_l2::text and (e->>'frozen_amount')::numeric = 1000 and (e->>'current_amount')::numeric = 1200 and (e->>'diff')::numeric = 200) and exists (select 1 from jsonb_array_elements(v_r->'rows') e where e->>'line_id' = v_lb::text)), false),'d',(v_r->>'total')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-82 · La alerta NO incluye lo vigente (L1, L3, L5, L6), ni lo retirado sin tarifa (L4, L7), ni el precio igual entre versiones (L3)','ok',coalesce((not exists (select 1 from jsonb_array_elements(v_r->'rows') e where e->>'line_id' in (v_l1::text, v_l3::text, v_l4::text))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.tariff_stale_claims(null, v_h, null, null, 'abiertas', 1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-83 · Con límite 1 la alerta marca que hay más (truncated) y devuelve 1 fila','ok',coalesce(((v_r->>'truncated')::boolean and (v_r->>'shown')::int = 1 and (v_r->>'total')::int = 2), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.tariff_stale_claims(v_a, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-84 · Filtrando por cliente A solo sale L2','ok',coalesce(((v_r->>'total')::int = 1 and v_r->'rows'->0->>'client' = 'QA TV Consultorio A' and v_r->'rows'->0->>'folio' is not null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.tariff_price_indicator(null, v_h, v_per, v_per + 27);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-85 · Indicador después del cambio: de 8 líneas, 6 tienen tarifa conocida (4 vigentes y 2 vencidas) y 2 quedaron sin tarifa por retiro (aparte, no cuentan como vencidas)','ok',coalesce(((v_r->>'lines')::int = 8 and (v_r->>'stale')::int = 2 and (v_r->>'no_tariff')::int = 2 and (v_r->>'known')::int = 6 and (v_r->>'current')::int = 4), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-86 · El indicador calcula el porcentaje (4 de 6 = 66.7 %) y lo abre por ARS','ok',coalesce(((v_r->>'pct')::numeric = 66.7 and (v_r->'by_ars'->0->>'pct')::numeric = 66.7 and v_r->'by_ars'->0->>'ars' = 'ARS QA Humana Ficticia'), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.tariff_stale_claims();
    v_r2 := public.tariff_price_indicator(null, v_h, v_per, v_per + 27);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-87 · El Médico del cliente A ve SOLO sus reclamaciones vencidas (L2), nunca las del cliente B','ok',coalesce(((v_r->>'total')::int = 1 and v_r->'rows'->0->>'line_id' = v_l2::text and not exists (select 1 from jsonb_array_elements(v_r->'rows') e where e->>'line_id' = v_lb::text)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-88 · El indicador del Médico de A cuenta solo sus líneas (7 líneas: 5 conocidas, 4 vigentes = 80 %, 1 vencida, 2 sin tarifa); la de B no entra','ok',coalesce(((v_r2->>'lines')::int = 7 and (v_r2->>'stale')::int = 1 and (v_r2->>'current')::int = 4 and (v_r2->>'no_tariff')::int = 2 and (v_r2->>'known')::int = 5 and (v_r2->>'pct')::numeric = 80.0), false),'d',(v_r2::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.tariff_stale_claims(v_b);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-89 · ATAQUE: el Médico de A no pide la alerta del cliente B','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-89 · ATAQUE: el Médico de A no pide la alerta del cliente B','ok',sqlerrm like 'Sin acceso a este cliente%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_price_indicator(v_b);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-90 · ATAQUE: el Médico de A no pide el indicador del cliente B','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-90 · ATAQUE: el Médico de A no pide el indicador del cliente B','ok',sqlerrm like 'Sin acceso a este cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.tariff_stale_claims();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-91 · El Médico del cliente B ve solo LB','ok',coalesce(((v_r->>'total')::int = 1 and v_r->'rows'->0->>'line_id' = v_lb::text), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_stale_claims();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-92 · ATAQUE: la Secretaria no ve la alerta de precios (sin acceso a reclamaciones de clientes)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-92 · ATAQUE: la Secretaria no ve la alerta de precios (sin acceso a reclamaciones de clientes)','ok',sqlerrm like 'No tiene acceso a las reclamaciones de ningún cliente%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_price_indicator();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-93 · ATAQUE: la Secretaria no ve el indicador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-93 · ATAQUE: la Secretaria no ve el indicador','ok',sqlerrm like 'No tiene acceso a las reclamaciones de ningún cliente%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_stale_claims(null, null, null, null, 'otras');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-94 · ERROR: alcance inválido en la alerta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-94 · ERROR: alcance inválido en la alerta','ok',sqlerrm like 'El alcance debe ser%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('app.claim_change', 'on', true);
    update public.service_lines set claim_status = 'radicada' where id = v_l2;
    perform set_config('app.claim_change', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.tariff_stale_claims(null, v_h, null, null, 'abiertas'); v_r2 := public.tariff_stale_claims(null, v_h, null, null, 'todas');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-95 · Una reclamación ya radicada sale de «abiertas» (solo queda LB) y aparece en «todas» marcada como cerrada','ok',coalesce(((v_r->>'total')::int = 1 and (v_r2->>'total')::int = 2 and exists (select 1 from jsonb_array_elements(v_r2->'rows') e where e->>'line_id' = v_l2::text and (e->>'closed')::boolean)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.tariff_version_preview(v_h, null, null, v_d1 + 20, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1250')), true);
      v_r2 := public.tariff_version_publish(v_h, null, null, 'QA Versión que conserva', v_d1 + 20, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1250')), true, 'Excel', 'qa.xlsx', null);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-96 · Con «conservar» la vista previa no retira nada y copia los códigos que faltan; al publicar quedan con su precio en la versión nueva','ok',coalesce(((v_r->>'retired_count')::int = 0 and (v_r->>'carried_count')::int = 3 and (v_r2->>'carried')::int = 3 and (v_r2->>'items')::int = 4 and (app.tariff_for(v_p2, v_h, v_d1 + 25, null, null)).amount = 1800 and (app.tariff_for(v_p1, v_h, v_d1 + 25, null, null)).amount = 1250 and (app.tariff_for(v_p7, v_h, v_d1 + 25, null, null)).amount = 8000 and (select count(*) from public.tariffs where version_id = (v_r2->>'version_id')::uuid) = 4), false),'d',(v_r2::text)::text));
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
      v_r := public.tariff_version_publish(v_m, null, null, 'QA Versión con fin', v_d1, v_d1 + 29, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '950'), jsonb_build_object('servicio', v_c2, 'tarifa', '1950')), false, 'Excel', 'qa.xlsx', null);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-97 · Una versión con «hasta» cierra la vigencia en esa fecha (incluida) y no hay tarifa al día siguiente','ok',coalesce(((app.tariff_for(v_p1, v_m, v_d1 + 29, null, null)).amount = 950 and (app.tariff_for(v_p1, v_m, v_d1 + 30, null, null)).id is null and (select (valid_during = daterange(v_d1, v_d1 + 30)) from public.tariff_versions where id = (v_r->>'version_id')::uuid)), false),'d',(v_r::text)::text));
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
      v_r := public.tariff_version_publish(v_s, null, null, 'QA Versión futura', current_date + 10, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '1150')), false, 'Excel', 'qa.xlsx', null);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r2 := public.tariff_versions_list(v_s);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-98 · Una versión con fecha futura queda «futura» y la actual sigue vigente hasta ese día','ok',coalesce((exists (select 1 from jsonb_array_elements(v_r2) e where e->>'name' = 'QA Versión futura' and e->>'state' = 'futura') and (app.tariff_for(v_p1, v_s, current_date, null, null)).amount = 1100 and (app.tariff_for(v_p1, v_s, current_date + 10, null, null)).amount = 1150), false),'d',(null)::text));
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
      v_r := public.tariff_version_publish(v_m, null, null, 'QA Versión por códigos', v_d1, null, jsonb_build_array(jsonb_build_object('simon', v_simon1, 'tarifa', 'RD$ 1,500.50'), jsonb_build_object('cups', (select min(code) from public.procedure_codes where procedure_id = v_p2 and code_system = 'CUPS'), 'tarifa', '2 000'), jsonb_build_object('servicio', v_c3, 'simon', (select min(code) from public.procedure_codes where procedure_id = v_p3 and code_system = 'SIMON'), 'cups', (select min(code) from public.procedure_codes where procedure_id = v_p3 and code_system = 'CUPS'), 'tarifa', '3000')), false, 'Excel', 'qa.xlsx', null);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-99 · El archivo puede traer SIMON, CUPS o código interno y la tarifa con «RD$», comas o espacios (1,500.50 / 2 000)','ok',coalesce(((v_r->>'items')::int = 3 and (app.tariff_for(v_p1, v_m, v_d1, null, null)).amount = 1500.50 and (app.tariff_for(v_p2, v_m, v_d1, null, null)).amount = 2000 and (v_r->>'retired')::int = 1), false),'d',(v_r::text)::text));
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
      v_r := public.tariff_version_publish(v_h, null, v_pa, 'QA Contrato Dr A', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '5000')), false, 'Excel', 'ct.xlsx', 'Contrato QA 2026');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_sub_a, s.organization_id, v_per + 6, 'Paciente QA LC', v_p1, 1, 5000 from public.submissions s where s.id = v_sub_a;
      select id into v_t1 from public.service_lines where submission_id = v_sub_a and patient_name = 'Paciente QA LC';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r2 := public.tariff_stale_claims(v_a, v_h, null, null, 'todas');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-100 · La versión de un médico se guarda en su cliente con su contrato; la línea del médico se contrata (contrato manda) y no se marca vencida por el cambio general','ok',coalesce(((select organization_id from public.tariff_versions where id = (v_r->>'version_id')::uuid) = v_a and (select contract_ref from public.tariffs where version_id = (v_r->>'version_id')::uuid) = 'Contrato QA 2026' and (select contracted and tariff_amount = 5000 from public.service_lines where id = v_t1) and not exists (select 1 from jsonb_array_elements(v_r2->'rows') e where e->>'line_id' = v_t1::text)), false),'d',(v_r::text)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.tariff_price_indicator(v_a, v_h, v_per, v_per + 27);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-101 · El indicador cuenta la línea contratada como vigente (sale del contrato del médico, no de la ARS)','ok',coalesce(((v_r->>'known')::int >= 5 and not exists (select 1 from public.service_lines sl where sl.id = v_t1 and sl.tariff_amount is distinct from 5000)), false),'d',(v_r::text)::text));
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
      v_r := public.tariff_version_publish(v_h, null, v_pb, 'QA Contrato B', v_d0, null, jsonb_build_array(jsonb_build_object('servicio', v_c1, 'tarifa', '4700')), false, 'Excel', 'qa.xlsx', null);
      insert into public.staff_client_access (user_id, client_org_id) values (v_ops::uuid, v_a);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r2 := public.tariff_versions_list(v_h);
      v_n0 := jsonb_array_length(v_r2);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-102 · El personal con clientes asignados no ve en la lista las versiones de médicos de clientes que no tiene','ok',coalesce((not exists (select 1 from jsonb_array_elements(v_r2) e where e->>'organization_id' = v_b::text) and exists (select 1 from jsonb_array_elements(v_r2) e where e->>'organization_id' is null)), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      begin
        insert into public.tariff_versions (ars_id, name, valid_during) values (v_h, 'QA Solapada directa', daterange(v_d1 + 2, null));
        v_n0 := -1;
      exception when others then v_n0 := case when sqlstate = '23P01' then 1 else 0 end; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-103 · Aun por la vía directa (SQL Editor) la base impide dos versiones vigentes a la vez de la misma ARS y plan (23P01)','ok',coalesce((v_n0 = 1), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_r := jsonb_build_object('guc', coalesce(current_setting('app.tariff_version_publish', true), ''));
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-104 · Después de publicar y de fallar publicaciones la bandera interna de publicación queda apagada (no se puede arrastrar a otra operación)','ok',coalesce(((v_r->>'guc') = ''), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TV-105 · Las versiones migradas siguen intactas después de todo: ninguna versión de cliente se cerró ni cambió (solo las de las ARS ficticias)','ok',coalesce((not exists (select 1 from public.tariff_versions v where v.source = 'Migración 184' and v.ars_id in (v_h, v_m, v_s))), false),'d',(null)::text));
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

revoke all on function app.qa_run_tests_tarifas_versiones() from public, anon, authenticated;   -- 4.9.0: faltaba (blindaje_2 B2-76: anon no ejecuta funciones de app)
