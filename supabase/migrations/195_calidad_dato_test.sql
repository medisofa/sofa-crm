-- 195 · Suite de la 194 (calidad del dato en la captura, I61). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_calidad_dato();
create or replace function app.qa_run_tests_calidad_dato()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_a constant uuid := '01940000-0000-4000-8000-000000000001'; v_b constant uuid := '01940000-0000-4000-8000-000000000002';
  v_pa constant uuid := '01940000-0000-4000-8000-000000000011'; v_pb constant uuid := '01940000-0000-4000-8000-000000000012';
  v_sa constant text := '01940000-0000-4000-8000-000000000021'; v_ad constant text := '01940000-0000-4000-8000-000000000022'; v_ops constant text := '01940000-0000-4000-8000-000000000023'; v_bil constant text := '01940000-0000-4000-8000-000000000024'; v_co constant text := '01940000-0000-4000-8000-000000000025';
  v_ma constant text := '01940000-0000-4000-8000-000000000031'; v_sec1 constant text := '01940000-0000-4000-8000-000000000032'; v_sec2 constant text := '01940000-0000-4000-8000-000000000033'; v_mb constant text := '01940000-0000-4000-8000-000000000034';
  v_ars uuid; v_ars2 uuid; v_proc uuid; v_proc2 uuid; v_sub_a uuid; v_r jsonb; v_r2 jsonb; v_rl text; v_id uuid; v_gl uuid; v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid; v_l5 uuid; v_l6 uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '178') then
    raise exception 'Falta la migración 178. Aplícala y vuelve a correr las pruebas.';
  end if;
  if not exists (select 1 from app.schema_migrations where version = '194') then
    raise exception 'Falta la migración 194. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.dq.sa@sofa.test','x'),(v_ad::uuid,'qa.dq.ad@sofa.test','x'),(v_ops::uuid,'qa.dq.ops@sofa.test','x'),(v_bil::uuid,'qa.dq.bil@sofa.test','x'),(v_co::uuid,'qa.dq.co@sofa.test','x'),(v_ma::uuid,'qa.dq.ma@sofa.test','x'),(v_sec1::uuid,'qa.dq.sec1@sofa.test','x'),(v_sec2::uuid,'qa.dq.sec2@sofa.test','x'),(v_mb::uuid,'qa.dq.mb@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.dq.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_a, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA DQ Consultorio A', '00000019401', 'Médico independiente', 'activo', current_date - 90, '8095559401');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_b, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA DQ Consultorio B', '00000019402', 'Médico independiente', 'activo', current_date - 90, '8095559402');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_a, 'Dr. A QA', 'Cardiología', true), (v_pb, v_b, 'Dr. B QA', 'Ortopedia', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_co::uuid, 'assistant', true),
      (v_a, v_ma::uuid, 'client', true), (v_a, v_sec1::uuid, 'capturer', true), (v_b, v_sec2::uuid, 'capturer', true), (v_b, v_mb::uuid, 'client', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec1::uuid, v_pa, v_a, true, true), (v_sec2::uuid, v_pb, v_b, true, true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_dq_ars', 'ARS QA Calidad', 'Contributivo', true) returning id into v_ars;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_dq_ars2', 'ARS QA Calidad Dos', 'Contributivo', true) returning id into v_ars2;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    select id into v_proc2 from public.procedures where is_active and id <> v_proc order by internal_code limit 1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_ars, date_trunc('month', current_date)::date, 1, 'borrador') returning id into v_sub_a;
    update public.app_settings set dq_enforce = false where true;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-01 · La migración 194 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '194')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-02 · Cédula válida: con y sin guiones, y con espacios','ok',coalesce((app.cedula_valida('40212345678') and app.cedula_valida('402-1234567-8') and app.cedula_valida(' 001 1234567 3 ') and app.cedula_valida('00112345673')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-03 · Cédula inválida: dígito verificador cambiado, 10 dígitos, 12 dígitos, letras, nula y vacía','ok',coalesce((not app.cedula_valida('40212345679') and not app.cedula_valida('4021234567') and not app.cedula_valida('402123456789') and not app.cedula_valida('4021234567A') and not app.cedula_valida(null) and not app.cedula_valida('')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-04 · Cédula inválida: todos los dígitos iguales y prefijo 000 (aunque el dígito verificador cuadre)','ok',coalesce((not app.cedula_valida('11111111111') and not app.cedula_valida('00000000000') and not app.cedula_valida('00012345674') and not app.cedula_valida('99999999999')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-05 · El algoritmo coincide con el de la puesta en marcha (golive_doc_check) en 8 cédulas de muestra','ok',coalesce(((select bool_and((app.golive_doc_check(c) is null) = app.cedula_valida(c)) from unnest(array['40212345678','40212345679','00112345673','22300123456','22300123450','00100000009','00100000008','12345678901']) c)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-06 · Diagnósticos: se normalizan a CIE-10 con punto, sin repetir y sin importar mayúsculas ni separadores','ok',coalesce(((select codes from app.dq_parse_dx(' i10, e119 / E11.9;I10 ')) = array['I10','E11.9'] and (select cardinality(invalidos) from app.dq_parse_dx('I10 E11')) = 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-07 · Diagnósticos: lo que no es un código CIE-10 se reporta como inválido (texto libre, números, código largo)','ok',coalesce(((select invalidos from app.dq_parse_dx('hipertension, 123, I10')) = array['HIPERTENSION','123'] and (select codes from app.dq_parse_dx('hipertension, 123, I10')) = array['I10'] and (select cardinality(invalidos) from app.dq_parse_dx('A12345678')) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-08 · NSS: se rechaza el que repite el mismo carácter, el muy corto y el muy largo; un NSS normal pasa','ok',coalesce((app.dq_nss_check('111111111', null) is not null and app.dq_nss_check('12345', null) like '%tiene 5 caracteres y se esperan entre 6 y 15%' and app.dq_nss_check('1234567890123456', null) is not null and app.dq_nss_check('123456789', null) is null and app.dq_nss_check('SN-123456', null) is null and app.dq_nss_check('  ', null) is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-09 · Sembrado: 3 comprobaciones básicas activas en modo «advertir» y un formato general de NSS','ok',coalesce(((select count(*) from public.dq_basic_checks where status = 'activa' and mode = 'advertir') = 3 and (select count(*) from public.dq_nss_formats where ars_id is null) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-10 · Sembrado: 3 reglas de EJEMPLO ficticias, todas inactivas y marcadas como ejemplo; ninguna otra','ok',coalesce(((select count(*) from public.dq_rules) = 3 and (select bool_and(is_example and status = 'inactiva' and name like 'EJEMPLO FICTICIO%') from public.dq_rules)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-11 · Sembrado: datos ilegibles, codificación y duplicidad cuentan como error de captura','ok',coalesce(((select count(*) from public.dq_capture_error_reasons where is_capture_error and reason_code in ('datos_ilegibles','codificacion','duplicidad')) = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-12 · El interruptor nace APAGADO y la meta del indicador es 2 %','ok',coalesce(((select column_default from information_schema.columns where table_schema = 'public' and table_name = 'app_settings' and column_name = 'dq_enforce') = 'false' and (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'app_settings' and column_name = 'dq_target_pct') like '2%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-13 · Las tablas de calidad no se tocan por la API: ni anon ni authenticated tienen permisos','ok',coalesce((not has_table_privilege('authenticated', 'public.dq_rules', 'select') and not has_table_privilege('authenticated', 'public.dq_rules', 'update') and not has_table_privilege('authenticated', 'public.dq_basic_checks', 'update') and not has_table_privilege('authenticated', 'public.dq_nss_formats', 'insert') and not has_table_privilege('authenticated', 'public.dq_capture_error_reasons', 'delete') and not has_table_privilege('anon', 'public.dq_rules', 'select')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-14 · Las funciones internas no se llaman desde la API y las públicas no están abiertas a anon','ok',coalesce((not has_function_privilege('authenticated', 'app.dq_evaluate(uuid,uuid,text,text,text,uuid)', 'execute') and not has_function_privilege('authenticated', 'app.cedula_valida(text)', 'execute') and not has_function_privilege('anon', 'public.dq_check_claim(uuid,uuid,uuid,text,text,text)', 'execute') and not has_function_privilege('anon', 'public.dq_secretary_quality(date,date,uuid)', 'execute') and not has_function_privilege('anon', 'public.capture_claim_dx(uuid,uuid,uuid,date,text,text,text,text,numeric,numeric,text,text,text,text,text,text,boolean,uuid,text)', 'execute') and has_function_privilege('authenticated', 'public.capture_claim_dx(uuid,uuid,uuid,date,text,text,text,text,numeric,numeric,text,text,text,text,text,text,boolean,uuid,text)', 'execute') and has_function_privilege('authenticated', 'public.capture_claim(uuid,uuid,uuid,date,text,text,text,text,numeric,numeric,text,text,text,text,text,text,boolean,uuid)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-15 · capture_claim conserva su firma de siempre (la puesta en marcha 182 la exige) y capture_claim_dx es la nueva con diagnóstico','ok',coalesce((to_regprocedure('public.capture_claim(uuid,uuid,uuid,date,text,text,text,text,numeric,numeric,text,text,text,text,text,text,boolean,uuid)') is not null and to_regprocedure('public.capture_claim_dx(uuid,uuid,uuid,date,text,text,text,text,numeric,numeric,text,text,text,text,text,text,boolean,uuid,text)') is not null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_rule_save(null, 'Regla de ataque', null, null, 'dx_requerido', '{}', 'bloquear', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-16 · ATAQUE: El Médico no crea reglas de calidad','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-16 · ATAQUE: El Médico no crea reglas de calidad','ok',sqlerrm like 'Las reglas de calidad las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_rule_save(null, 'Regla de ataque', null, null, 'dx_requerido', '{}', 'bloquear', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-17 · ATAQUE: La Secretaria no crea reglas de calidad','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-17 · ATAQUE: La Secretaria no crea reglas de calidad','ok',sqlerrm like 'Las reglas de calidad las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_rule_save(null, 'Regla de ataque', null, null, 'dx_requerido', '{}', 'bloquear', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-18 · ATAQUE: Operaciones no crea reglas de calidad','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-18 · ATAQUE: Operaciones no crea reglas de calidad','ok',sqlerrm like 'Las reglas de calidad las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_rule_save(null, 'Regla de ataque', null, null, 'dx_requerido', '{}', 'bloquear', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-19 · ATAQUE: Facturación no crea reglas de calidad','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-19 · ATAQUE: Facturación no crea reglas de calidad','ok',sqlerrm like 'Las reglas de calidad las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_rule_save(null, 'Regla de ataque', null, null, 'dx_requerido', '{}', 'bloquear', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-20 · ATAQUE: El Comercial no crea reglas de calidad','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-20 · ATAQUE: El Comercial no crea reglas de calidad','ok',sqlerrm like 'Las reglas de calidad las administra%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      update public.dq_rules set status = 'activa' where true;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-21 · ATAQUE: el Médico no cambia reglas con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-21 · ATAQUE: el Médico no cambia reglas con UPDATE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      insert into public.dq_rules (code, name, kind) values ('x_ataque', 'Regla de ataque', 'dx_requerido');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-22 · ATAQUE: el Médico no inserta reglas por la API','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-22 · ATAQUE: el Médico no inserta reglas por la API','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      delete from public.dq_rules where true;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-23 · ATAQUE: el Médico no borra reglas por la API','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-23 · ATAQUE: el Médico no borra reglas por la API','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      perform 1 from public.dq_rules limit 1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-24 · ATAQUE: el Médico no lee las reglas de la tabla','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-24 · ATAQUE: el Médico no lee las reglas de la tabla','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      update public.dq_basic_checks set status = 'inactiva' where true;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-25 · ATAQUE: el Médico no apaga una comprobación con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-25 · ATAQUE: el Médico no apaga una comprobación con UPDATE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-26 · ATAQUE: el Médico no ve la configuración de calidad','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-26 · ATAQUE: el Médico no ve la configuración de calidad','ok',sqlerrm like 'La configuración de calidad de captura la ven%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_check_set('cedula_digito', 'bloquear', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-27 · ATAQUE: el Médico no cambia comprobaciones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-27 · ATAQUE: el Médico no cambia comprobaciones','ok',sqlerrm like 'Las comprobaciones de calidad las administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_nss_format_save(null, 3, 30, false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-28 · ATAQUE: el Médico no cambia el formato del NSS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-28 · ATAQUE: el Médico no cambia el formato del NSS','ok',sqlerrm like 'El formato del NSS lo administra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_error_reason_set('datos_ilegibles', false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-29 · ATAQUE: el Médico no define qué cuenta como error de captura','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-29 · ATAQUE: el Médico no define qué cuenta como error de captura','ok',sqlerrm like 'Los motivos que cuentan como error de captura%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_set_enforce(true, 'Quiero ver qué pasa si lo activo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-30 · ATAQUE: el Médico no activa el bloqueo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-30 · ATAQUE: el Médico no activa el bloqueo','ok',sqlerrm like 'Solo el Super Admin activa%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_set_target(50);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-31 · ATAQUE: el Médico no cambia la meta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-31 · ATAQUE: el Médico no cambia la meta','ok',sqlerrm like 'La meta de calidad la define%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_secretary_quality();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-32 · ATAQUE: el Médico no ve el indicador de calidad por secretaria','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-32 · ATAQUE: el Médico no ve el indicador de calidad por secretaria','ok',sqlerrm like 'El indicador de calidad por secretaria lo ven%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_set_enforce(true, 'Activación sin permiso del Super Admin');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-33 · ATAQUE: el Administrador tampoco activa el interruptor (es del Super Admin)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-33 · ATAQUE: el Administrador tampoco activa el interruptor (es del Super Admin)','ok',sqlerrm like 'Solo el Super Admin activa%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      update public.app_settings set dq_enforce = true where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-34 · ATAQUE: ni el Super Admin cambia el interruptor con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-34 · ATAQUE: ni el Super Admin cambia el interruptor con UPDATE directo','ok',sqlerrm like 'El bloqueo de calidad del dato se activa o desactiva con%','d',left(sqlerrm,120)));
    end;
    begin
      update public.app_settings set dq_target_pct = 50 where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-35 · ATAQUE: ni el Super Admin cambia la meta con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-35 · ATAQUE: ni el Super Admin cambia la meta con UPDATE directo','ok',sqlerrm like 'La meta de calidad de captura se cambia con%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_set_enforce(true, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-36 · El interruptor exige un motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-36 · El interruptor exige un motivo','ok',sqlerrm like 'Escriba el motivo (mínimo 10 caracteres)%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dq_set_enforce(true, 'Activación de prueba del bloqueo de calidad');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-37 · El Super Admin enciende el bloqueo y queda en la bitácora con su motivo','ok',coalesce((exists (select 1 from public.app_settings where dq_enforce) and exists (select 1 from public.audit_log where table_name = 'app_settings' and record_id = 'dq_enforce' and new_values->>'motivo' like 'Activación de prueba%')), false),'d',(null)::text));
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
      perform public.dq_set_target(3.5);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-38 · El Administrador cambia la meta del indicador (3,5 %)','ok',coalesce(((select dq_target_pct from public.app_settings where operator_id = '00000000-0000-4000-8000-000000000001'::uuid) = 3.5), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_set_target(0);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-39 · La meta no puede ser 0 ni mayor de 100','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-39 · La meta no puede ser 0 ni mayor de 100','ok',sqlerrm like 'La meta debe ser un porcentaje%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_set_target(101);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-40 · La meta de 101 se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-40 · La meta de 101 se rechaza','ok',sqlerrm like 'La meta debe ser un porcentaje%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_check_claim(v_b, v_ars, v_proc, null, '40212345678', '123456789');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-41 · ATAQUE: la secretaria no revisa datos a nombre de una organización ajena','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-41 · ATAQUE: la secretaria no revisa datos a nombre de una organización ajena','ok',sqlerrm like 'Su usuario no tiene acceso a esa organización%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_check_claim(null, v_ars, v_proc);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-42 · La revisión en vivo exige indicar la organización','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-42 · La revisión en vivo exige indicar la organización','ok',sqlerrm like 'Indique el médico o la organización%','d',left(sqlerrm,120)));
    end;
    v_r := public.dq_check_claim(v_a, v_ars, v_proc, 'i10', '40212345679', '111111111');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-43 · La revisión en vivo devuelve cédula con dígito malo, NSS repetido y diagnóstico normalizado, todo como advertencia (interruptor apagado)','ok',coalesce(((v_r->>'advertencias')::int = 2 and (v_r->>'bloqueos')::int = 0 and v_r->>'dx' = 'I10' and not (v_r->>'enforce')::boolean and exists (select 1 from jsonb_array_elements(v_r->'issues') x where x->>'codigo' = 'cedula_digito' and x->>'mensaje' like '%dígito verificador no coincide%') and exists (select 1 from jsonb_array_elements(v_r->'issues') x where x->>'codigo' = 'nss_formato')), false),'d',(v_r)::text));
    perform set_config('role', v_rl, true);
    v_r := public.dq_check_claim(v_a, v_ars, v_proc, 'E11.9', '40212345678', '123456789');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-44 · Datos correctos: la revisión en vivo no devuelve nada','ok',coalesce(((v_r->>'advertencias')::int = 0 and (v_r->>'bloqueos')::int = 0 and jsonb_array_length(v_r->'issues') = 0), false),'d',(v_r)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 1', '900000001', 'AUT-DQ-1', '402-1234567-8', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-45 · Cédula válida con guiones: se guarda normalizada a 11 dígitos y sin advertencias','ok',coalesce(((select patient_doc from public.service_lines where id = (v_r->>'id')::uuid) = '40212345678' and jsonb_array_length(v_r->'advertencias') = 0 and v_r ? 'folio'), false),'d',(v_r)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 2', '900000002', 'AUT-DQ-2', '40212345679', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-46 · Dígito verificador malo con el interruptor apagado: se guarda y devuelve la advertencia con qué hacer','ok',coalesce(((select patient_doc from public.service_lines where id = (v_r->>'id')::uuid) = '40212345679' and (select coalesce(string_agg(x->>'codigo', ',' order by x->>'codigo'), '') from jsonb_array_elements(v_r->'advertencias') x) = 'cedula_digito' and v_r->'advertencias'->0->>'mensaje' like '%Revise el número contra la cédula%'), false),'d',(v_r->'advertencias')::text));
    perform set_config('role', v_rl, true);
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 3', '900000003', 'AUT-DQ-3', '4021234567', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-47 · ATAQUE: una cédula de 10 dígitos se bloquea siempre (aunque el interruptor esté apagado) y dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-47 · ATAQUE: una cédula de 10 dígitos se bloquea siempre (aunque el interruptor esté apagado) y dice qué hacer','ok',sqlerrm like '%debe tener 11 números (tiene 10)%deje la casilla vacía%','d',left(sqlerrm,120)));
    end;
    begin
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 4', '900000004', 'AUT-DQ-4', 'AB123456', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-48 · ATAQUE: un pasaporte en la casilla de la cédula se bloquea y dice dónde anotarlo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-48 · ATAQUE: un pasaporte en la casilla de la cédula se bloquea y dice dónde anotarlo','ok',sqlerrm like '%debe tener 11 números%Observaciones%','d',left(sqlerrm,120)));
    end;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-49 · Una captura bloqueada no deja nada a medias (ninguna línea nueva de la secretaria)','ok',coalesce(((select count(*) from public.service_lines where organization_id = v_a and created_by = v_sec1::uuid) = 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.app_settings set dq_enforce = true where true;
      update public.dq_basic_checks set mode = 'bloquear', status = 'activa' where code = 'cedula_digito';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 5', '900000005', 'AUT-DQ-5', '40212345679', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-50 · ATAQUE: con el interruptor encendido y la comprobación en «bloquear», el dígito malo detiene la captura','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-50 · ATAQUE: con el interruptor encendido y la comprobación en «bloquear», el dígito malo detiene la captura','ok',sqlerrm like '%Revise los datos antes de guardar%dígito verificador no coincide%','d',left(sqlerrm,120)));
    end;
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 6', '900000006', 'AUT-DQ-6', '40212345678', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-51 · Con el bloqueo encendido, la cédula correcta sigue entrando','ok',coalesce((v_r ? 'id'), false),'d',(null)::text));
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
      update public.app_settings set dq_enforce = true where true;
      update public.dq_basic_checks set mode = 'advertir', status = 'activa' where code = 'cedula_digito';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 7', '900000007', 'AUT-DQ-7', '40212345679', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-52 · Interruptor encendido pero la comprobación en «advertir»: solo advierte (cada regla manda en su modo)','ok',coalesce(((select coalesce(string_agg(x->>'codigo', ',' order by x->>'codigo'), '') from jsonb_array_elements(v_r->'advertencias') x) = 'cedula_digito'), false),'d',(null)::text));
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
      update public.dq_basic_checks set mode = 'bloquear', status = 'inactiva' where code = 'cedula_digito';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 8', '900000008', 'AUT-DQ-8', '40212345679', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-53 · Comprobación inactiva: el dígito malo ni siquiera advierte','ok',coalesce(((select coalesce(string_agg(x->>'codigo', ',' order by x->>'codigo'), '') from jsonb_array_elements(v_r->'advertencias') x) = ''), false),'d',(null)::text));
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
      update public.dq_basic_checks set mode = 'bloquear', status = 'activa' where code = 'cedula_digito';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 9', '900000009', 'AUT-DQ-9', '40212345679', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-54 · Comprobación en «bloquear» pero interruptor apagado: guarda y el mensaje avisa «hoy solo advierte»','ok',coalesce((v_r->'advertencias'->0->>'mensaje' like '%Hoy solo es una advertencia%'), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 10', '111111111', 'AUT-DQ-10', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-55 · NSS con el mismo número repetido: se guarda y advierte (interruptor apagado)','ok',coalesce(((select coalesce(string_agg(x->>'codigo', ',' order by x->>'codigo'), '') from jsonb_array_elements(v_r->'advertencias') x) = 'nss_formato' and v_r->'advertencias'->0->>'mensaje' like '%carnet del afiliado%'), false),'d',(null)::text));
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
      update public.app_settings set dq_enforce = true where true;
      update public.dq_basic_checks set mode = 'bloquear', status = 'activa' where code = 'nss_formato';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 11', '1234', 'AUT-DQ-11', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-56 · ATAQUE: con el bloqueo encendido, un NSS de 4 caracteres se detiene con el mensaje del largo esperado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-56 · ATAQUE: con el bloqueo encendido, un NSS de 4 caracteres se detiene con el mensaje del largo esperado','ok',sqlerrm like '%El NSS «1234» tiene 4 caracteres y se esperan entre 6 y 15%','d',left(sqlerrm,120)));
    end;
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 12', '900000012', 'AUT-DQ-12', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-57 · Con el bloqueo encendido un NSS normal entra','ok',coalesce((v_r ? 'id'), false),'d',(null)::text));
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
      perform public.dq_nss_format_save(v_ars, 9, 9, true, 'Ejemplo ficticio: 123456789');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 13', '12345678A', 'AUT-DQ-13', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_r2 := public.capture_claim_dx(v_pa, v_ars2, v_proc, current_date - 1, 'Paciente QA 14', 'AB1234567', 'AUT-DQ-14', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-58 · Formato de NSS propio de la ARS (9 números): las letras advierten en esa ARS y no en otra que usa el formato general','ok',coalesce(((select coalesce(string_agg(x->>'codigo', ',' order by x->>'codigo'), '') from jsonb_array_elements(v_r->'advertencias') x) = 'nss_formato' and (select coalesce(string_agg(x->>'codigo', ',' order by x->>'codigo'), '') from jsonb_array_elements(v_r2->'advertencias') x) = ''), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 15', '900000015', 'AUT-DQ-15', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, ' i10, e119 ');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-59 · El diagnóstico se normaliza y se guarda en claim_diagnoses (I10, E11.9)','ok',coalesce(((select codes from public.claim_diagnoses where service_line_id = (v_r->>'id')::uuid) = 'I10, E11.9' and v_r->>'diagnostico' = 'I10, E11.9' and jsonb_array_length(v_r->'advertencias') = 0), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 16', '900000016', 'AUT-DQ-16', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, 'dolor de pecho');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-60 · Un diagnóstico escrito en texto libre advierte el formato y no se guarda como código','ok',coalesce((jsonb_array_length(v_r->'advertencias') = 1 and v_r->'advertencias'->0->>'codigo' = 'dx_formato' and v_r->'advertencias'->0->>'mensaje' like '%no es un código CIE-10 válido%' and not exists (select 1 from public.claim_diagnoses where service_line_id = (v_r->>'id')::uuid)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 17', '900000017', 'AUT-DQ-17', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, 'A00,A01,A02,A03,A04,A05,A06,A07,A08,A09,A15');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-61 · ATAQUE: más de 10 diagnósticos se bloquean siempre','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-61 · ATAQUE: más de 10 diagnósticos se bloquean siempre','ok',sqlerrm like '%más de 10 diagnósticos%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_req', 'Regla QA qa_req', null, null, 'dx_requerido', '{}', 'advertir', 'activa', null);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 18', '900000018', 'AUT-DQ-18', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_r2 := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 19', '900000019', 'AUT-DQ-19', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, 'I10');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-62 · Regla «diagnóstico requerido» (advertir): sin diagnóstico advierte con el nombre de la regla; con diagnóstico no dice nada','ok',coalesce(((select coalesce(string_agg(x->>'codigo', ',' order by x->>'codigo'), '') from jsonb_array_elements(v_r->'advertencias') x) = 'dx_requerido' and v_r->'advertencias'->0->>'mensaje' like '%Regla QA qa_req%Diagnóstico%' and jsonb_array_length(v_r2->'advertencias') = 0), false),'d',(null)::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_perm', 'Regla QA qa_perm', null, null, 'dx_permitidos', '{O,Z34}', 'bloquear', 'activa', null);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 20', '900000020', 'AUT-DQ-20', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, 'I10');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-63 · Regla «solo permitidos» en modo bloquear con el interruptor apagado: guarda y avisa «hoy solo advierte»','ok',coalesce(((select coalesce(string_agg(x->>'codigo', ',' order by x->>'codigo'), '') from jsonb_array_elements(v_r->'advertencias') x) = 'dx_no_permitido' and v_r->'advertencias'->0->>'mensaje' like '%Hoy solo es una advertencia%'), false),'d',(null)::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_perm', 'Regla QA qa_perm', null, null, 'dx_permitidos', '{O,Z34}', 'bloquear', 'activa', null);
      update public.app_settings set dq_enforce = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 21', '900000021', 'AUT-DQ-21', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, 'I10');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-64 · ATAQUE: con el bloqueo encendido, un diagnóstico fuera de lo permitido detiene la captura y dice cómo corregir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-64 · ATAQUE: con el bloqueo encendido, un diagnóstico fuera de lo permitido detiene la captura y dice cómo corregir','ok',sqlerrm like '%Revise los datos antes de guardar%I10 no corresponde%Revise el diagnóstico en la receta%','d',left(sqlerrm,120)));
    end;
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 22', '900000022', 'AUT-DQ-22', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, 'O80, z34.0');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-65 · Con el bloqueo encendido, los diagnósticos permitidos (O80, Z34.0) entran','ok',coalesce((v_r ? 'id' and (select codes from public.claim_diagnoses where service_line_id = (v_r->>'id')::uuid) = 'O80, Z34.0'), false),'d',(null)::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_perm', 'Regla QA qa_perm', null, null, 'dx_permitidos', '{O}', 'bloquear', 'activa', null);
      update public.app_settings set dq_enforce = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 23', '900000023', 'AUT-DQ-23', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-66 · «Solo permitidos» no exige diagnóstico (para eso está la regla de requerido): sin diagnóstico entra','ok',coalesce((v_r ? 'id' and jsonb_array_length(v_r->'advertencias') = 0), false),'d',(null)::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_excl', 'Regla QA qa_excl', null, null, 'dx_excluidos', '{Z76,R69}', 'bloquear', 'activa', 'Ese diagnóstico solo no justifica el servicio: agregue el diagnóstico principal.');
      update public.app_settings set dq_enforce = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 24', '900000024', 'AUT-DQ-24', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, 'I10, R69.1');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-67 · ATAQUE: diagnóstico excluido (R69.1 empieza por R69) con bloqueo encendido: se detiene con el mensaje propio de la regla','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-67 · ATAQUE: diagnóstico excluido (R69.1 empieza por R69) con bloqueo encendido: se detiene con el mensaje propio de la regla','ok',sqlerrm like '%Ese diagnóstico solo no justifica el servicio%','d',left(sqlerrm,120)));
    end;
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 25', '900000025', 'AUT-DQ-25', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, 'I10');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-68 · Un diagnóstico que no está en la lista de excluidos entra','ok',coalesce((v_r ? 'id'), false),'d',(null)::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_ars', 'Regla QA qa_ars', v_ars2, null, 'dx_requerido', '{}', 'bloquear', 'activa', null);
      update public.app_settings set dq_enforce = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 26', '900000026', 'AUT-DQ-26', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-69 · Una regla de otra ARS no aplica a esta ARS','ok',coalesce((v_r ? 'id' and jsonb_array_length(v_r->'advertencias') = 0), false),'d',(null)::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_ars', 'Regla QA qa_ars', v_ars, null, 'dx_requerido', '{}', 'bloquear', 'activa', null);
      update public.app_settings set dq_enforce = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 27', '900000027', 'AUT-DQ-27', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-70 · ATAQUE: la regla de esta ARS (requerido, bloquear) detiene la captura sin diagnóstico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-70 · ATAQUE: la regla de esta ARS (requerido, bloquear) detiene la captura sin diagnóstico','ok',sqlerrm like '%Este servicio exige diagnóstico%','d',left(sqlerrm,120)));
    end;
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 28', '900000028', 'AUT-DQ-28', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, 'I10');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-71 · Con el diagnóstico escrito la regla de la ARS deja pasar','ok',coalesce((v_r ? 'id'), false),'d',(null)::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_pr', 'Regla QA qa_pr', null, v_proc2, 'dx_requerido', '{}', 'bloquear', 'activa', null);
      update public.app_settings set dq_enforce = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 29', '900000029', 'AUT-DQ-29', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-72 · Una regla de otro servicio no aplica a este servicio','ok',coalesce((v_r ? 'id'), false),'d',(null)::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_off', 'Regla QA qa_off', null, null, 'dx_requerido', '{}', 'bloquear', 'inactiva', null);
      update public.app_settings set dq_enforce = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 30', '900000030', 'AUT-DQ-30', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-73 · Una regla inactiva no hace nada, aunque diga «bloquear» y el interruptor esté encendido','ok',coalesce((v_r ? 'id' and jsonb_array_length(v_r->'advertencias') = 0), false),'d',(null)::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_req', 'Regla QA qa_req', null, null, 'dx_requerido', '{}', 'bloquear', 'activa', null);
      update public.app_settings set dq_enforce = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      v_r := public.capture_claim(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 31', '900000031', 'AUT-DQ-31', null, 100, 1, null, null, null, null, 'pendiente', null, false, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-74 · ATAQUE: la firma de siempre, capture_claim, también respeta las reglas (nadie la usa para saltarse el bloqueo)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-74 · ATAQUE: la firma de siempre, capture_claim, también respeta las reglas (nadie la usa para saltarse el bloqueo)','ok',sqlerrm like '%Este servicio exige diagnóstico%','d',left(sqlerrm,120)));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 32', '900000032', 'AUT-DQ-32', '40212345678', 100, 1, null, null, null, null, 'pendiente', null, false, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-75 · capture_claim (firma de siempre, sin diagnóstico) sigue funcionando y devuelve la lista de advertencias','ok',coalesce((v_r ? 'id' and v_r ? 'folio' and jsonb_typeof(v_r->'advertencias') = 'array'), false),'d',(null)::text));
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
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 33', '900000033', 'AUT-DQ-33', '40212345679', 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-76 · El Médico (cliente) también recibe las advertencias al capturar','ok',coalesce(((select coalesce(string_agg(x->>'codigo', ',' order by x->>'codigo'), '') from jsonb_array_elements(v_r->'advertencias') x) = 'cedula_digito'), false),'d',(null)::text));
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
      v_r := public.import_claims(jsonb_build_array(
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 2, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Uno', 'nss', '900100001', 'autorizacion', 'AUT-XL-1', 'cedula', '402-1234567-8', 'monto', '100'),
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 3, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Dos', 'nss', '900100002', 'autorizacion', 'AUT-XL-2', 'cedula', '40212345679', 'monto', '100')), false);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-77 · Importación (vista previa), interruptor apagado: las dos filas son válidas y la de la cédula mala trae su advertencia','ok',coalesce(((v_r->>'valid')::int = 2 and jsonb_array_length(v_r->'errors') = 0 and jsonb_array_length(v_r->'rows'->1->'advertencias') = 1 and jsonb_array_length(v_r->'rows'->0->'advertencias') = 0 and v_r->'rows'->1->'advertencias'->>0 like '%dígito verificador%'), false),'d',(v_r->'rows'->1->'advertencias')::text));
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
      update public.app_settings set dq_enforce = true where true;
      update public.dq_basic_checks set mode = 'bloquear', status = 'activa' where code = 'cedula_digito';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.import_claims(jsonb_build_array(
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 2, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Uno', 'nss', '900100001', 'autorizacion', 'AUT-XL-1', 'cedula', '402-1234567-8', 'monto', '100'),
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 3, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Dos', 'nss', '900100002', 'autorizacion', 'AUT-XL-2', 'cedula', '40212345679', 'monto', '100')), false);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-78 · Importación (vista previa) con bloqueo encendido: la fila de la cédula mala sale como error con el mensaje que dice qué hacer y la buena sigue válida','ok',coalesce(((v_r->>'valid')::int = 1 and jsonb_array_length(v_r->'errors') = 1 and (v_r->'errors'->0->>'row')::int = 2 and v_r->'errors'->0->'errors'->>0 like '%dígito verificador no coincide%'), false),'d',(v_r->'errors')::text));
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
      update public.app_settings set dq_enforce = true where true;
      update public.dq_basic_checks set mode = 'bloquear', status = 'activa' where code = 'cedula_digito';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.import_claims(jsonb_build_array(
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 2, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Uno', 'nss', '900100001', 'autorizacion', 'AUT-XL-1', 'cedula', '402-1234567-8', 'monto', '100'),
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 3, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Dos', 'nss', '900100002', 'autorizacion', 'AUT-XL-2', 'cedula', '40212345679', 'monto', '100')), true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-79 · ATAQUE: con el bloqueo encendido no se puede importar el archivo mientras tenga filas con error','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-79 · ATAQUE: con el bloqueo encendido no se puede importar el archivo mientras tenga filas con error','ok',sqlerrm like 'Corrija las 1 filas con errores antes de importar%','d',left(sqlerrm,120)));
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
      v_r := public.import_claims(jsonb_build_array(
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 2, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Uno', 'nss', '900100001', 'autorizacion', 'AUT-XL-1', 'cedula', '402-1234567-8', 'monto', '100', 'diagnostico', 'i10, e119'),
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 3, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Dos', 'nss', '900100002', 'autorizacion', 'AUT-XL-2', 'cedula', '40212345679', 'monto', '100')), true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-80 · Importación real: carga las 2 filas, guarda la cédula sin guiones y el diagnóstico normalizado de la columna «diagnostico»','ok',coalesce(((v_r->>'imported')::int = 2 and (select count(*) from public.service_lines where organization_id = v_a and patient_doc = '40212345678') = 1 and (select count(*) from public.claim_diagnoses cd join public.service_lines l on l.id = cd.service_line_id where l.patient_name = 'Paciente Excel Uno' and cd.codes = 'I10, E11.9') = 1), false),'d',(v_r->>'imported')::text));
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
      insert into public.dq_rules (code, name, ars_id, procedure_id, kind, dx_prefixes, mode, status, message) values ('qa_req', 'Regla QA qa_req', null, null, 'dx_requerido', '{}', 'bloquear', 'activa', null);
      update public.app_settings set dq_enforce = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.import_claims(jsonb_build_array(
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 2, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Uno', 'nss', '900100001', 'autorizacion', 'AUT-XL-1', 'cedula', '402-1234567-8', 'monto', '100', 'diagnostico', 'I10'),
        jsonb_build_object('medico', v_pa::text, 'ars', 'qa_dq_ars', 'servicio', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 3, 'DD/MM/YYYY'),
          'paciente', 'Paciente Excel Dos', 'nss', '900100002', 'autorizacion', 'AUT-XL-2', 'cedula', '40212345679', 'monto', '100')), false);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-81 · Importación con regla «requerido» en bloqueo: la fila con diagnóstico pasa y la que no lo trae queda como error','ok',coalesce(((v_r->>'valid')::int = 1 and jsonb_array_length(v_r->'errors') = 1 and v_r->'errors'->0->'errors'->>0 like '%Este servicio exige diagnóstico%'), false),'d',(v_r->'errors')::text));
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
      v_r := public.import_service_lines(v_sub_a, jsonb_build_array(jsonb_build_object('codigo', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 5, 'DD/MM/YYYY'), 'afiliado', 'Afiliado Masivo QA', 'cedula', '40212345679', 'nss', '900200001', 'autorizacion', 'AUT-SL-1', 'monto', '100')));
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-82 · Carga a una radicación, interruptor apagado: entra la fila y la cédula con dígito malo viene como advertencia','ok',coalesce(((v_r->>'inserted')::int = 1 and jsonb_array_length(v_r->'rows'->0->'advertencias') = 1), false),'d',(v_r)::text));
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
      update public.app_settings set dq_enforce = true where true;
      update public.dq_basic_checks set mode = 'bloquear', status = 'activa' where code = 'cedula_digito';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.import_service_lines(v_sub_a, jsonb_build_array(jsonb_build_object('codigo', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 5, 'DD/MM/YYYY'), 'afiliado', 'Afiliado Masivo QA', 'cedula', '40212345679', 'nss', '900200001', 'autorizacion', 'AUT-SL-1', 'monto', '100')));
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-83 · Carga a una radicación con bloqueo encendido: la fila se rechaza con el mensaje del dígito verificador','ok',coalesce(((v_r->>'inserted')::int = 0 and (v_r->>'errors')::int = 1 and v_r->'rows'->0->>'error' like '%dígito verificador no coincide%'), false),'d',(v_r)::text));
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
      v_r := public.import_service_lines(v_sub_a, jsonb_build_array(jsonb_build_object('codigo', (select internal_code from public.procedures where id = v_proc), 'fecha', to_char(current_date - 5, 'DD/MM/YYYY'), 'afiliado', 'Afiliado Corto QA', 'cedula', '123', 'monto', '100')));
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-84 · La carga que ya fallaba por una cédula que no tiene 11 dígitos sigue fallando igual (no se aflojó nada)','ok',coalesce(((v_r->>'errors')::int = 1 and v_r->'rows'->0->>'error' like 'Cédula del afiliado inválida (11 dígitos)%'), false),'d',(v_r)::text));
    perform set_config('role', v_rl, true);
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_rule_save(null, 'a', null, null, 'dx_requerido', '{}', 'advertir', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-85 · Regla sin nombre: se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-85 · Regla sin nombre: se rechaza','ok',sqlerrm like 'Escriba un nombre para la regla%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_rule_save(null, 'Regla QA tipo', null, null, 'otro', '{}', 'advertir', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-86 · Regla con tipo desconocido: se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-86 · Regla con tipo desconocido: se rechaza','ok',sqlerrm like 'Elija el tipo de regla%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_rule_save(null, 'Regla QA modo', null, null, 'dx_requerido', '{}', 'ignorar', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-87 · Regla con modo desconocido: se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-87 · Regla con modo desconocido: se rechaza','ok',sqlerrm like 'Elija el modo de la regla%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_rule_save(null, 'Regla QA sin prefijos', null, null, 'dx_permitidos', '{}', 'advertir', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-88 · Regla de «permitidos» sin prefijos: se rechaza y dice qué escribir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-88 · Regla de «permitidos» sin prefijos: se rechaza y dice qué escribir','ok',sqlerrm like 'Esta regla necesita al menos un prefijo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_rule_save(null, 'Regla QA prefijo', null, null, 'dx_excluidos', '{12,abc!}', 'advertir', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-89 · Prefijo que no es CIE-10: se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-89 · Prefijo que no es CIE-10: se rechaza','ok',sqlerrm like 'El código «12» no sirve como prefijo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_rule_save(null, 'Regla QA ars', '99999999-9999-4999-8999-999999999999', null, 'dx_requerido', '{}', 'advertir', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-90 · Regla con una ARS inexistente: se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-90 · Regla con una ARS inexistente: se rechaza','ok',sqlerrm like 'La ARS elegida no existe%','d',left(sqlerrm,120)));
    end;
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_id := public.dq_rule_save(null, 'Regla QA creada por el Administrador', v_ars, v_proc, 'dx_permitidos', '{i10, e11.9, i10}', 'bloquear', 'activa', 'Solo diagnósticos cardiometabólicos para este servicio.');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-91 · El Administrador crea una regla: prefijos normalizados y sin repetir (I10, E119), código automático','ok',coalesce(((select dx_prefixes from public.dq_rules where id = v_id) = array['I10','E119'] and (select code from public.dq_rules where id = v_id) like 'r\_%' and not (select is_example from public.dq_rules where id = v_id)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.dq_overview();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-92 · dq_overview lista la regla con el nombre de la ARS y del servicio','ok',coalesce((exists (select 1 from jsonb_array_elements(v_r->'rules') x where x->>'id' = v_id::text and x->>'ars' = 'ARS QA Calidad' and x->>'procedure' is not null)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
      perform public.dq_rule_delete(v_id);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-93 · El Administrador borra la regla','ok',coalesce((not exists (select 1 from public.dq_rules where id = v_id)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_rule_delete(v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-94 · Borrar una regla que ya no existe dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-94 · Borrar una regla que ya no existe dice qué hacer','ok',sqlerrm like 'La regla no existe%Actualice la pantalla%','d',left(sqlerrm,120)));
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
      select id into v_id from public.dq_rules where code = 'ejemplo_dx_excluidos';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dq_rule_save(v_id, 'Regla propia: sin Z76', null, null, 'dx_excluidos', '{Z76}', 'advertir', 'activa');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-95 · Al editar un ejemplo ficticio deja de ser ejemplo y queda activa','ok',coalesce(((select not is_example and status = 'activa' from public.dq_rules where id = v_id)), false),'d',(null)::text));
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
      perform public.dq_check_set('nss_formato', 'bloquear', 'activa');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-96 · El Administrador cambia una comprobación básica a «bloquear»','ok',coalesce(((select mode from public.dq_basic_checks where code = 'nss_formato') = 'bloquear'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_check_set('inventada', 'bloquear', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-97 · Una comprobación desconocida se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-97 · Una comprobación desconocida se rechaza','ok',sqlerrm like 'Esa comprobación no existe%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_check_set('nss_formato', 'ignorar', 'activa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-98 · Un modo desconocido se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-98 · Un modo desconocido se rechaza','ok',sqlerrm like 'Elija el modo%','d',left(sqlerrm,120)));
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
      perform public.dq_nss_format_save(v_ars2, 8, 10, true, 'Ejemplo ficticio: 12345678');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-99 · Formato de NSS por ARS: se crea y se actualiza sin duplicarse','ok',coalesce(((select count(*) from public.dq_nss_formats where ars_id = v_ars2) = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dq_nss_format_save(v_ars2, 7, 12, false);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-100 · El formato de NSS por ARS se actualiza (7 a 12, sin exigir solo números)','ok',coalesce(((select count(*) from public.dq_nss_formats where ars_id = v_ars2) = 1 and (select max_len from public.dq_nss_formats where ars_id = v_ars2) = 12), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform public.dq_nss_format_delete(v_ars2);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-101 · El formato propio de una ARS se borra y vuelve a regir el general','ok',coalesce((not exists (select 1 from public.dq_nss_formats where ars_id = v_ars2)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_nss_format_delete(null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-102 · El formato general del NSS no se borra','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-102 · El formato general del NSS no se borra','ok',sqlerrm like 'El formato general del NSS no se borra%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_nss_format_save(v_ars2, 10, 5, false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-103 · Un largo de NSS inválido (máximo menor que el mínimo) se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-103 · Un largo de NSS inválido (máximo menor que el mínimo) se rechaza','ok',sqlerrm like 'El largo del NSS debe estar entre%','d',left(sqlerrm,120)));
    end;
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.dq_overview();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-104 · Operaciones ve la configuración pero no puede editarla; trae 3 comprobaciones, formato de NSS, reglas y motivos','ok',coalesce((not (v_r->>'puede_editar')::boolean and not (v_r->>'puede_activar')::boolean and jsonb_array_length(v_r->'checks') = 3 and jsonb_array_length(v_r->'nss_formats') >= 1 and jsonb_array_length(v_r->'rules') >= 3 and jsonb_array_length(v_r->'error_reasons') >= 3), false),'d',(v_r->'checks')::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.dq_overview();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-105 · El Administrador sí puede editar pero no activar el bloqueo global','ok',coalesce(((v_r->>'puede_editar')::boolean and not (v_r->>'puede_activar')::boolean), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 34', '900000034', 'AUT-DQ-34', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_l1 := (v_r->>'id')::uuid;
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 35', '900000035', 'AUT-DQ-35', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_l2 := (v_r->>'id')::uuid;
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 36', '900000036', 'AUT-DQ-36', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_l3 := (v_r->>'id')::uuid;
      v_r := public.capture_claim_dx(v_pa, v_ars, v_proc, current_date - 1, 'Paciente QA 37', '900000037', 'AUT-DQ-37', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_l4 := (v_r->>'id')::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec2, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.capture_claim_dx(v_pb, v_ars, v_proc, current_date - 1, 'Paciente QA 38', '900000038', 'AUT-DQ-38', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_l5 := (v_r->>'id')::uuid;
      v_r := public.capture_claim_dx(v_pb, v_ars, v_proc, current_date - 1, 'Paciente QA 39', '900000039', 'AUT-DQ-39', null, 100, 1, null, null, null, null, 'pendiente', null, false, null, null);
      v_l6 := (v_r->>'id')::uuid;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      perform set_config('app.claim_change', 'on', true);
      update public.service_lines set claim_status = 'devuelta' where id = v_l1;
      perform set_config('app.claim_change', '', true);
      update public.submissions set submitted_on = current_date where id in (select submission_id from public.service_lines where id = v_l2);
      insert into public.glosas (organization_id, submission_id, notified_on, appeal_deadline) select organization_id, submission_id, current_date, current_date + 15 from public.service_lines where id = v_l2 returning id into v_gl;
      insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_gl, v_a, v_l2, 'datos_ilegibles', 50);
      insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_gl, v_a, v_l3, 'pertinencia', 50);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.dq_secretary_quality();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-106 · La secretaria ve solo lo suyo: 4 capturadas, 1 devuelta, 1 glosada por captura (50 %), sin ver a la otra secretaria','ok',coalesce((jsonb_array_length(v_r->'filas') = 1 and (v_r->'filas'->0->>'user_id') = v_sec1 and (v_r->'filas'->0->>'capturadas')::int = 4 and (v_r->'filas'->0->>'devueltas')::int = 1 and (v_r->'filas'->0->>'glosadas_por_captura')::int = 1 and (v_r->'filas'->0->>'pct_error')::numeric = 50 and not (v_r->'filas'->0->>'cumple_meta')::boolean and not (v_r->>'ve_todas')::boolean), false),'d',(v_r->'filas')::text));
    perform set_config('role', v_rl, true);
      v_r2 := public.dq_secretary_quality(current_date - 30, current_date, v_b);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-107 · ATAQUE: la secretaria no ve a las de otra organización ni pidiéndolas por el parámetro de organización','ok',coalesce((jsonb_array_length(v_r2->'filas') = 0), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec2, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.dq_secretary_quality();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-108 · La otra secretaria ve solo sus 2 capturadas con 0 % de error (cumple la meta)','ok',coalesce((jsonb_array_length(v_r->'filas') = 1 and (v_r->'filas'->0->>'user_id') = v_sec2 and (v_r->'filas'->0->>'capturadas')::int = 2 and (v_r->'filas'->0->>'pct_error')::numeric = 0 and (v_r->'filas'->0->>'cumple_meta')::boolean), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.dq_secretary_quality();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-109 · Operaciones (supervisión) ve a las dos secretarias de la prueba (y a las demás de sus clientes), con la meta de 2 %','ok',coalesce(((v_r->>'ve_todas')::boolean and (v_r->>'meta_pct')::numeric = 2 and exists (select 1 from jsonb_array_elements(v_r->'filas') x where x->>'user_id' = v_sec1 and (x->>'capturadas')::int = 4) and exists (select 1 from jsonb_array_elements(v_r->'filas') x where x->>'user_id' = v_sec2 and (x->>'capturadas')::int = 2)), false),'d',(v_r->'total')::text));
    perform set_config('role', v_rl, true);
      v_r := public.dq_secretary_quality(current_date - 30, current_date, v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-110 · Filtrado por el cliente A: el total es 2 con error de 4 (50 %)','ok',coalesce(((v_r->'total'->>'capturadas')::int = 4 and (v_r->'total'->>'con_error')::int = 2 and (v_r->'total'->>'pct_error')::numeric = 50 and not (v_r->'total'->>'cumple_meta')::boolean), false),'d',(v_r->'total')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-111 · La tendencia trae 6 meses y el mes actual refleja las capturadas por la secretaria de la prueba','ok',coalesce((jsonb_array_length(v_r->'tendencia') = 6 and (v_r->'tendencia'->5->>'capturadas')::int = 4 and (v_r->'tendencia'->5->>'con_error')::int = 2), false),'d',(v_r->'tendencia')::text));
    perform set_config('role', v_rl, true);
      v_r := public.dq_secretary_quality(current_date - 30, current_date);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-112 · Las filas vienen ordenadas de mayor a menor porcentaje de error','ok',coalesce(((select bool_and((a->>'pct_error')::numeric >= (b->>'pct_error')::numeric) from (select x a, lead(x) over () b from jsonb_array_elements(v_r->'filas') x) q where b is not null)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      v_r := public.dq_secretary_quality(current_date - 30, current_date, v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-113 · El Administrador filtra por organización y ve solo a la secretaria de ese cliente','ok',coalesce((jsonb_array_length(v_r->'filas') = 1 and (v_r->'filas'->0->>'user_id') = v_sec1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
      perform public.dq_error_reason_set('datos_ilegibles', false);
      v_r := public.dq_secretary_quality();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-114 · Si «datos ilegibles» deja de contar como error de captura, el error de la secretaria baja a 25 % (1 de 4)','ok',coalesce(((select (x->>'pct_error')::numeric from jsonb_array_elements(v_r->'filas') x where x->>'user_id' = v_sec1) = 25), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
      perform public.dq_error_reason_set('pertinencia', true);
      v_r := public.dq_secretary_quality();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-115 · Si «pertinencia» pasa a contar como error de captura, vuelve a 25 % por la glosa de pertinencia (devuelta + pertinencia = 2 de 4 = 50 %)','ok',coalesce(((select (x->>'pct_error')::numeric from jsonb_array_elements(v_r->'filas') x where x->>'user_id' = v_sec1) = 50), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_secretary_quality(current_date, current_date - 5);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-116 · ATAQUE: un período con fecha final anterior a la inicial se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-116 · ATAQUE: un período con fecha final anterior a la inicial se rechaza','ok',sqlerrm like 'La fecha final no puede ser anterior%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.dq_secretary_quality(current_date - 400, current_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-117 · Un período de más de un año se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-117 · Un período de más de un año se rechaza','ok',sqlerrm like 'El período máximo es de un año%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_secretary_quality();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-118 · ATAQUE: Facturación no ve el indicador por secretaria','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-118 · ATAQUE: Facturación no ve el indicador por secretaria','ok',sqlerrm like 'El indicador de calidad por secretaria lo ven%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.dq_secretary_quality(current_date - 30, current_date, v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-119 · ATAQUE: el Médico de otra organización no ve el indicador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DQ-119 · ATAQUE: el Médico de otra organización no ve el indicador','ok',sqlerrm like 'El indicador de calidad por secretaria lo ven%','d',left(sqlerrm,120)));
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

revoke all on function app.qa_run_tests_calidad_dato() from public, anon, authenticated;
