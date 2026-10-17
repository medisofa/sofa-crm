-- 183 · Suite de la 182 (puesta en marcha asistida, I56). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_golive();
create or replace function app.qa_run_tests_golive()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_a constant uuid := '01820000-0000-4000-8000-000000000001'; v_b constant uuid := '01820000-0000-4000-8000-000000000002'; v_c constant uuid := '01820000-0000-4000-8000-000000000003';
  v_pa constant uuid := '01820000-0000-4000-8000-000000000011'; v_pa2 constant uuid := '01820000-0000-4000-8000-000000000012'; v_pb constant uuid := '01820000-0000-4000-8000-000000000013';
  v_sa constant text := '01820000-0000-4000-8000-000000000021'; v_ad constant text := '01820000-0000-4000-8000-000000000022'; v_ops constant text := '01820000-0000-4000-8000-000000000023'; v_bil constant text := '01820000-0000-4000-8000-000000000024'; v_co constant text := '01820000-0000-4000-8000-000000000025';
  v_ma constant text := '01820000-0000-4000-8000-000000000031'; v_sec1 constant text := '01820000-0000-4000-8000-000000000032'; v_mb constant text := '01820000-0000-4000-8000-000000000033';
  v_ars uuid; v_code text; v_rows jsonb; v_r jsonb; v_rl text; v_s jsonb; v_b1 uuid; v_n0 int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '182') then
    raise exception 'Falta la migración 182. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.gl.sa@sofa.test','x'),(v_ad::uuid,'qa.gl.ad@sofa.test','x'),(v_ops::uuid,'qa.gl.ops@sofa.test','x'),(v_bil::uuid,'qa.gl.bil@sofa.test','x'),(v_co::uuid,'qa.gl.co@sofa.test','x'),(v_ma::uuid,'qa.gl.ma@sofa.test','x'),(v_sec1::uuid,'qa.gl.sec1@sofa.test','x'),(v_mb::uuid,'qa.gl.mb@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.gl.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_a, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA GL Consultorio A', '00000018201', 'Médico independiente', 'activo', current_date - 90, '8095558201');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_b, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA GL Consultorio B', '00000018202', 'Médico independiente', 'activo', current_date - 90, '8095558202');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_c, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA GL Consultorio C', '00000018203', 'Médico independiente', 'activo', current_date - 90, '8095558203');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_pa, v_a, 'Dr. A Uno QA', 'Cardiología', true), (v_pa2, v_a, 'Dr. A Dos QA', 'Pediatría', true),
      (v_pb, v_b, 'Dr. B QA', 'Ortopedia', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ad::uuid, 'admin', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing', true), ('00000000-0000-4000-8000-000000000001'::uuid, v_co::uuid, 'assistant', true),
      (v_a, v_ma::uuid, 'client', true), (v_a, v_sec1::uuid, 'capturer', true), (v_b, v_mb::uuid, 'client', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec1::uuid, v_pa, v_a, true, true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_gl_ars', 'ARS QA Puesta en marcha', 'Contributivo', true) returning id into v_ars;
    select internal_code into v_code from public.procedures where is_active order by internal_code limit 1;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-01 · La migración 182 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '182')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-02 · Catálogo de 12 pasos: 9 obligatorios y 3 de carga opcionales','ok',coalesce(((select count(*) from public.golive_step_defs) = 12 and (select count(*) from public.golive_step_defs where mandatory) = 9 and not exists (select 1 from public.golive_step_defs where code like 'carga_%' and mandatory)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-03 · Un cliente nuevo nace en modo prueba, con 12 pasos y la fecha límite de cada uno = firma + sus días','ok',coalesce(((select mode from public.golive_clients where organization_id = v_a) = 'prueba' and (select count(*) from public.golive_steps where organization_id = v_a) = 12 and (select signed_on from public.golive_clients where organization_id = v_a) = current_date - 90 and not exists (select 1 from public.golive_steps s join public.golive_step_defs d on d.code = s.step_code join public.golive_clients g on g.organization_id = s.organization_id where s.organization_id = v_a and s.due_on <> g.signed_on + d.default_offset)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-04 · Los clientes que ya existían (no en incorporación) quedaron en modo real y sin lista','ok',coalesce((not exists (select 1 from public.organizations o join public.golive_clients g on g.organization_id = o.id where o.kind = 'client' and o.id not in (v_a, v_b, v_c) and o.status <> 'incorporacion' and g.mode <> 'real') and not exists (select 1 from public.organizations o where o.kind = 'client' and o.id not in (v_a, v_b, v_c) and not exists (select 1 from public.golive_clients g where g.organization_id = o.id))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-05 · Las seis tablas no se tocan por la API: ni anon ni authenticated tienen permisos','ok',coalesce((not has_table_privilege('authenticated', 'public.golive_clients', 'select') and not has_table_privilege('authenticated', 'public.golive_clients', 'update') and not has_table_privilege('authenticated', 'public.golive_steps', 'select') and not has_table_privilege('authenticated', 'public.golive_steps', 'insert') and not has_table_privilege('authenticated', 'public.golive_load_batches', 'select') and not has_table_privilege('authenticated', 'public.golive_load_rows', 'select') and not has_table_privilege('authenticated', 'public.golive_log', 'select') and not has_table_privilege('authenticated', 'public.golive_log', 'delete') and not has_table_privilege('authenticated', 'public.golive_step_defs', 'update') and not has_table_privilege('anon', 'public.golive_clients', 'select')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-06 · Las funciones internas no se llaman desde la API (golive_auto, golive_doc_check, golive_seed, golive_log_add)','ok',coalesce((not has_function_privilege('authenticated', 'app.golive_auto(uuid,text)', 'execute') and not has_function_privilege('authenticated', 'app.golive_doc_check(text)', 'execute') and not has_function_privilege('authenticated', 'app.golive_seed(uuid,text)', 'execute') and not has_function_privilege('authenticated', 'app.golive_log_add(uuid,text,text,jsonb)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-07 · Las funciones públicas de la puesta en marcha no están abiertas a anon pero sí a authenticated','ok',coalesce((not has_function_privilege('anon', 'public.golive_load(uuid,text,jsonb,boolean,text,uuid,text)', 'execute') and not has_function_privilege('anon', 'public.golive_go_real(uuid,text,text)', 'execute') and not has_function_privilege('anon', 'public.golive_checklist(uuid)', 'execute') and not has_function_privilege('anon', 'public.golive_overview()', 'execute') and has_function_privilege('authenticated', 'public.golive_load(uuid,text,jsonb,boolean,text,uuid,text)', 'execute')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-08 · Todas las funciones de la 182 son SECURITY DEFINER con search_path vacío','ok',coalesce(((select bool_and(prosecdef and array_to_string(proconfig, ',') like '%search_path=""%') from pg_proc where pronamespace in ('public'::regnamespace, 'app'::regnamespace) and proname like 'golive\_%' and proname not in ('golive_doc_check','golive_protect'))), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-09 · Cédula con dígito verificador correcto se acepta (también con guiones)','ok',coalesce((app.golive_doc_check('00100000017') is null and app.golive_doc_check('001-0000002-5') is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-10 · Cédula con el dígito verificador cambiado se rechaza y dice qué revisar','ok',coalesce((app.golive_doc_check('00100000034') like 'Cédula inválida: el dígito verificador no coincide%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-11 · Cédulas imposibles (11 iguales, empieza en 000) y de largo incorrecto se rechazan','ok',coalesce((app.golive_doc_check('11111111111') like 'Cédula inválida%' and app.golive_doc_check('00012345678') like 'Cédula inválida%' and app.golive_doc_check('1234567890') like 'Cédula inválida: tiene 10 dígitos%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-12 · Pasaporte (letras y números) se acepta; solo letras o texto raro se rechaza','ok',coalesce((app.golive_doc_check('PA1234567') is null and app.golive_doc_check('ABCDEFGH') like 'Documento no reconocido%' and app.golive_doc_check('12 AB') like 'Documento no reconocido%' and app.golive_doc_check('') = 'Falta el documento'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_checklist(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-13 · ATAQUE: La Secretaria no ve la lista de puesta en marcha de A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-13 · ATAQUE: La Secretaria no ve la lista de puesta en marcha de A','ok',sqlerrm like 'No tiene acceso a la puesta en marcha%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_checklist(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-14 · ATAQUE: Facturación no ve la lista de puesta en marcha de A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-14 · ATAQUE: Facturación no ve la lista de puesta en marcha de A','ok',sqlerrm like 'No tiene acceso a la puesta en marcha%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_checklist(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-15 · ATAQUE: El Comercial no ve la lista de puesta en marcha de A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-15 · ATAQUE: El Comercial no ve la lista de puesta en marcha de A','ok',sqlerrm like 'No tiene acceso a la puesta en marcha%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_checklist(v_a);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-16 · ATAQUE: El Médico de otro cliente no ve la lista de puesta en marcha de A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-16 · ATAQUE: El Médico de otro cliente no ve la lista de puesta en marcha de A','ok',sqlerrm like 'No tiene acceso a la puesta en marcha%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_step_update(v_a, 'capacitacion', 'completado', 'Intento de marcarlo por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-17 · ATAQUE: La Secretaria no actualiza pasos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-17 · ATAQUE: La Secretaria no actualiza pasos','ok',sqlerrm like 'La lista de puesta en marcha la actualizan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_step_update(v_a, 'capacitacion', 'completado', 'Intento de marcarlo por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-18 · ATAQUE: Facturación no actualiza pasos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-18 · ATAQUE: Facturación no actualiza pasos','ok',sqlerrm like 'La lista de puesta en marcha la actualizan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_step_update(v_a, 'capacitacion', 'completado', 'Intento de marcarlo por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-19 · ATAQUE: El Comercial no actualiza pasos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-19 · ATAQUE: El Comercial no actualiza pasos','ok',sqlerrm like 'La lista de puesta en marcha la actualizan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_step_update(v_a, 'capacitacion', 'completado', 'Intento de marcarlo por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-20 · ATAQUE: El Médico no actualiza pasos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-20 · ATAQUE: El Médico no actualiza pasos','ok',sqlerrm like 'La lista de puesta en marcha la actualizan%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_load(v_a, 'pacientes', jsonb_build_array(jsonb_build_object('nombre','Paciente QA')), true, 'x.xlsx', v_pa, 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-21 · ATAQUE: el Médico no carga datos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-21 · ATAQUE: el Médico no carga datos','ok',sqlerrm like 'La carga inicial la hacen%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_go_real(v_a, 'PASAR A REAL', 'intento');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-22 · ATAQUE: el Médico no pasa su cliente a real','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-22 · ATAQUE: el Médico no pasa su cliente a real','ok',sqlerrm like 'Pasar un cliente a real lo hacen%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_config_set(v_a, null, 60);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-23 · ATAQUE: el Médico no cambia el tope de meses','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-23 · ATAQUE: el Médico no cambia el tope de meses','ok',sqlerrm like 'La configuración de la puesta en marcha la cambian%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-24 · ATAQUE: el Médico no ve el resumen de todos los clientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-24 · ATAQUE: el Médico no ve el resumen de todos los clientes','ok',sqlerrm like 'La puesta en marcha la manejan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_indicador();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-25 · ATAQUE: el Médico no ve el indicador de días a la primera reclamación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-25 · ATAQUE: el Médico no ve el indicador de días a la primera reclamación','ok',sqlerrm like 'El indicador de puesta en marcha lo ven%','d',left(sqlerrm,120)));
    end;
    begin
      update public.golive_clients set mode = 'real' where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-26 · ATAQUE: el Médico no cambia su modo con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-26 · ATAQUE: el Médico no cambia su modo con UPDATE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      update public.golive_steps set status = 'completado' where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-27 · ATAQUE: el Médico no marca pasos con UPDATE directo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-27 · ATAQUE: el Médico no marca pasos con UPDATE directo','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      perform 1 from public.golive_log limit 1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-28 · ATAQUE: el Médico no inserta cargas ni lee la bitácora por la API','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-28 · ATAQUE: el Médico no inserta cargas ni lee la bitácora por la API','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_go_back(v_a, 'Intento de cambiar el modo por cuenta propia');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-29 · ATAQUE: el Médico no devuelve un cliente a prueba','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-29 · ATAQUE: el Médico no devuelve un cliente a prueba','ok',sqlerrm like 'Solo el Super Admin devuelve%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_go_back(v_a, 'Intento del administrador sin ser Super Admin');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-30 · ATAQUE: el Administrador tampoco devuelve a prueba (solo el Super Admin)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-30 · ATAQUE: el Administrador tampoco devuelve a prueba (solo el Super Admin)','ok',sqlerrm like 'Solo el Super Admin devuelve%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_go_real(v_a, 'PASAR A REAL');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-31 · ATAQUE: la Secretaria no carga datos ni pasa a real','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-31 · ATAQUE: la Secretaria no carga datos ni pasa a real','ok',sqlerrm like 'Pasar un cliente a real lo hacen%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_load(v_a, 'pacientes', jsonb_build_array(jsonb_build_object('nombre','Paciente QA')), false, 'x', v_pa, 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-32 · ATAQUE: Facturación no carga datos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-32 · ATAQUE: Facturación no carga datos','ok',sqlerrm like 'La carga inicial la hacen%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.golive_checklist(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-33 · El Médico ve su avance en solo lectura: modo prueba, 12 pasos, 9 obligatorios, sin bitácora interna','ok',coalesce((v_r->>'mode' = 'prueba' and (v_r->>'read_only')::boolean and jsonb_array_length(v_r->'steps') = 12 and (v_r->>'mandatory_total')::int = 9 and jsonb_array_length(v_r->'log') = 0), false),'d',(v_r->>'mode')::text));
    perform set_config('role', v_rl, true);
    v_r := public.golive_mine();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-34 · golive_mine entrega al Médico la lista de su propio cliente','ok',coalesce(((v_r->>'org')::uuid = v_a and (v_r->>'read_only')::boolean), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.golive_mine();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-35 · golive_mine del Médico B entrega la de B, nunca la de A','ok',coalesce(((v_r->>'org')::uuid = v_b), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.golive_checklist(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-36 · Operaciones ve la lista de A completa y no de solo lectura; lo pendiente está atrasado (firma hace 90 días), solo el usuario del médico se cumple solo y nada está listo','ok',coalesce((not (v_r->>'read_only')::boolean and not (v_r->>'ready')::boolean and (select count(*) from jsonb_array_elements(v_r->'steps') x where (x->>'late')::boolean) >= 8 and (v_r->>'mandatory_done')::int = 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.golive_mine();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-37 · Operaciones no ve el Médico en golive_mine (no es médico de un cliente)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-37 · Operaciones no ve el Médico en golive_mine (no es médico de un cliente)','ok',sqlerrm like 'Esta pantalla es para el médico%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_step_update(v_a, 'capacitacion', 'completado');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-38 · Completar un paso manual sin evidencia se rechaza y dice qué escribir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-38 · Completar un paso manual sin evidencia se rechaza y dice qué escribir','ok',sqlerrm like 'Escriba la evidencia del paso%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_step_update(v_a, 'capacitacion', 'completado', 'ok');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-39 · Una evidencia de 3 letras tampoco sirve','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-39 · Una evidencia de 3 letras tampoco sirve','ok',sqlerrm like 'Escriba la evidencia del paso%','d',left(sqlerrm,120)));
    end;
    v_s := public.golive_step_update(v_a, 'capacitacion', 'completado', 'Capacitación del 12/11 con la Dra. y su secretaria (lista de asistencia en la carpeta)');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-40 · Con evidencia el paso queda hecho a mano, con fecha y quien lo hizo','ok',coalesce(((v_s->>'done')::boolean and v_s->>'source' = 'manual' and v_s->>'done_at' is not null and not (v_s->>'late')::boolean), false),'d',(v_s::text)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.golive_step_update(v_a, 'tarifario', 'no_aplica', 'No tiene tarifario todavía');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-41 · Un paso obligatorio no puede quedar «no aplica»','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-41 · Un paso obligatorio no puede quedar «no aplica»','ok',sqlerrm like 'El paso %Tarifario% es obligatorio%','d',left(sqlerrm,120)));
    end;
    v_s := public.golive_step_update(v_a, 'carga_citas', 'no_aplica', 'El cliente no trae citas anteriores');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-42 · Un paso opcional sí puede quedar «no aplica» (con motivo) y no cuenta como atrasado','ok',coalesce((v_s->>'status' = 'no_aplica' and not (v_s->>'late')::boolean and not (v_s->>'done')::boolean), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.golive_step_update(v_a, 'carga_citas', 'terminado', 'Evidencia suficiente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-43 · Estado inventado se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-43 · Estado inventado se rechaza','ok',sqlerrm like 'Estado no válido%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_step_update(v_a, 'paso_fantasma', 'completado', 'Evidencia suficiente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-44 · Paso inexistente dice que elija de la lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-44 · Paso inexistente dice que elija de la lista','ok',sqlerrm like 'Ese paso no existe%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_step_update(v_a, 'tarifario', null, null, null, 'el vecino', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-45 · Responsable inventado se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-45 · Responsable inventado se rechaza','ok',sqlerrm like 'Responsable no válido%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_step_update(v_a, 'tarifario', null, null, date '1999-01-01');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-46 · Fecha límite absurda se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-46 · Fecha límite absurda se rechaza','ok',sqlerrm like 'La fecha límite no es válida%','d',left(sqlerrm,120)));
    end;
    v_s := public.golive_step_update(v_a, 'tarifario', 'en_curso', null, current_date + 5, 'medico', 'Dra. QA Uno');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-47 · Cambiar responsable, fecha y estado: el paso queda en curso, a cargo del médico y ya no está atrasado','ok',coalesce((v_s->>'owner_role' = 'medico' and v_s->>'owner_label' = 'Dra. QA Uno' and (v_s->>'due_on')::date = current_date + 5 and v_s->>'status' = 'en_curso' and not (v_s->>'late')::boolean), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_s := public.golive_step_update(v_a, 'capacitacion', 'pendiente');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-48 · Reabrir un paso lo deja pendiente y borra quién y cuándo lo cerró','ok',coalesce((v_s->>'status' = 'pendiente' and v_s->>'done_at' is null and (select done_by from public.golive_steps where organization_id = v_a and step_code = 'capacitacion') is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-49 · Cada cambio de paso queda en la bitácora','ok',coalesce(((select count(*) from public.golive_log where organization_id = v_a and action = 'paso') >= 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-50 · Y el paso queda auditado (audit_log)','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'golive_steps' and organization_id = v_a)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-51 · El paso «contrato firmado» NO está cumplido sin documento A firmado','ok',coalesce((not app.golive_auto(v_a, 'contrato_firmado') and not app.golive_auto(v_a, 'carga_pacientes') and app.golive_auto(v_a, 'capacitacion') is null), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    insert into public.commercial_documents (organization_id, template_code, template_version, title, content, status) values (v_a, 'A', 1, 'Contrato QA', 'Texto de prueba', 'firmado');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-52 · Al firmarse el documento A el paso se cumple solo (automático, sin que nadie lo marque)','ok',coalesce((app.golive_auto(v_a, 'contrato_firmado') and (select (x->>'done')::boolean and x->>'source' = 'automatico' from jsonb_array_elements(app.golive_steps_json(v_a)) x where x->>'code' = 'contrato_firmado')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_config_set(v_a, null, 0);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-53 · Tope de 0 meses se rechaza y dice el rango','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-53 · Tope de 0 meses se rechaza y dice el rango','ok',sqlerrm like 'El tope de meses hacia atrás va de 1 a 60%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_config_set(v_a, null, 61);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-54 · Tope de 61 meses se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-54 · Tope de 61 meses se rechaza','ok',sqlerrm like 'El tope de meses hacia atrás va de 1 a 60%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_config_set(v_a, current_date + 1, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-55 · Fecha de firma futura se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-55 · Fecha de firma futura se rechaza','ok',sqlerrm like 'La fecha de firma no puede ser futura%','d',left(sqlerrm,120)));
    end;
    v_s := public.golive_config_set(v_a, null, null);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-56 · Sin cambios el tope sigue en 12 (valor por defecto)','ok',coalesce(((v_s->>'months_back')::int = 12), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    select count(*) into v_n0 from public.patients where organization_id = v_a;
    v_rows := jsonb_build_array(jsonb_build_object('documento', '00100000017', 'nombre', 'Paciente Uno QA', 'fecha_nacimiento', to_char(current_date - 9000, 'DD/MM/YYYY'), 'sexo', 'F', 'telefono', '809-555-0101', 'email', 'uno@qa.test', 'ars', 'qa_gl_ars', 'afiliado', 'AF-0001'), jsonb_build_object('documento', '00100000026', 'nombre', 'Paciente Cedula Mala QA'), jsonb_build_object('documento', '00100000017', 'nombre', 'Paciente Uno Repetido QA'), jsonb_build_object('documento', '00100000033', 'nombre', 'Paciente Fecha Mala QA', 'fecha_nacimiento', '31/02/1980'), jsonb_build_object('documento', '00100000041', 'nombre', 'Paciente Sexo Raro QA', 'sexo', 'Q'), jsonb_build_object('documento', '00100000058', 'nombre', 'Paciente ARS Rara QA', 'ars', 'ars_que_no_existe'), jsonb_build_object('documento', 'PA7654321', 'nombre', 'Paciente Extranjero QA'), jsonb_build_object('nombre', 'Menor Sin Cedula QA', 'fecha_nacimiento', to_char(current_date - 2000, 'DD/MM/YYYY')), jsonb_build_object('nombre', 'Sin Documento Ni Fecha QA'), jsonb_build_object('documento', '00100000066', 'nombre', 'Paciente Afiliado Sin ARS QA', 'afiliado', 'AF-0002'), jsonb_build_object('documento', '00100000074', 'nombre', 'Pa', 'ars', 'qa_gl_ars'), jsonb_build_object('documento', '00100000082', 'nombre', 'Paciente Telefono Malo QA', 'telefono', 'abc'), jsonb_build_object('documento', '00100000090', 'nombre', 'Paciente Correo Malo QA', 'email', 'sin-arroba'));
    v_r := public.golive_load(v_a, 'pacientes', v_rows, false, 'pacientes.xlsx', null, 'Sistema anterior QA');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-57 · Vista previa de pacientes: 3 aceptadas (válida, pasaporte y menor sin cédula) y 10 rechazadas, sin guardar nada','ok',coalesce(((v_r->>'total')::int = 13 and (v_r->>'accepted')::int = 3 and (v_r->>'rejected')::int = 10 and v_r->>'batch_id' is null and not (v_r->>'commit')::boolean and (select count(*) from public.patients where organization_id = v_a) = v_n0 and not exists (select 1 from public.golive_load_batches where organization_id = v_a)), false),'d',(v_r->>'accepted')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-58 · Cédula con dígito verificador malo: rechazada con el motivo escrito','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 2) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 2) like '%dígito verificador no coincide%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-59 · Mismo paciente dos veces en el archivo: la segunda se rechaza y dice por qué','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) = 'aceptada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 3) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 3) like '%Duplicado dentro del archivo%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-60 · Fecha de nacimiento imposible (31/02) rechazada','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 4) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 4) like '%Fecha de nacimiento inválida%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-61 · Sexo, ARS desconocida, teléfono, correo y nombre corto rechazados con motivo','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 5) = 'rechazada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 6) = 'rechazada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 11) = 'rechazada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 12) = 'rechazada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 13) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 6) like '%ARS no reconocida%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-62 · Pasaporte aceptado; menor sin cédula pero con fecha de nacimiento aceptado; sin documento ni fecha rechazado','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 7) = 'aceptada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 8) = 'aceptada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 9) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 9) like '%Falta el documento%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-63 · Afiliado sin ARS rechazado','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 10) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 10) like '%falta la ARS%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.golive_load(v_a, 'pacientes', v_rows, true, 'pacientes.xlsx', null, 'Sistema anterior QA');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-64 · Al confirmar se guardan SOLO las 3 aceptadas, con un lote que cuenta 13 / 3 / 10 y 13 filas en el reporte','ok',coalesce(((v_r->>'accepted')::int = 3 and (select count(*) from public.patients where organization_id = v_a) = v_n0 + 3 and (select rows_total || '/' || rows_accepted || '/' || rows_rejected from public.golive_load_batches where id = (v_r->>'batch_id')::uuid) = '13/3/10' and (select count(*) from public.golive_load_rows where batch_id = (v_r->>'batch_id')::uuid) = 13 and (select count(*) from public.golive_load_rows where batch_id = (v_r->>'batch_id')::uuid and entity_id is not null) = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_b1 := (v_r->>'batch_id')::uuid;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-65 · El paciente cargado trae sus datos (ARS, afiliado, sexo, teléfono) y queda en el registro de acceso','ok',coalesce((exists (select 1 from public.patients p where p.organization_id = v_a and p.doc_number = '00100000017' and p.sex = 'F' and p.member_number = 'AF-0001' and p.ars_id = v_ars and p.phone = '8095550101') and exists (select 1 from public.patient_access_log l join public.patients p on p.id = l.patient_id where p.doc_number = '00100000017' and l.action = 'crear')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.golive_load(v_a, 'pacientes', v_rows, true, 'pacientes.xlsx', null, 'Sistema anterior QA');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-66 · Volver a cargar el mismo archivo no duplica nada: las 3 ya existen y salen rechazadas con «Ya existe»','ok',coalesce(((v_r->>'accepted')::int = 0 and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) like '%Ya existe un paciente%' and (select count(*) from public.patients where organization_id = v_a) = v_n0 + 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-67 · El paso «carga de pacientes» se cumple solo tras confirmar la carga','ok',coalesce((app.golive_auto(v_a, 'carga_pacientes')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.golive_load(v_a, 'pacientes', (select jsonb_agg(jsonb_build_object('nombre','Paciente QA')) from generate_series(1, 1001)), false, 'x', null, 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-68 · Más de 1,000 filas se rechaza y dice cómo dividir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-68 · Más de 1,000 filas se rechaza y dice cómo dividir','ok',sqlerrm like 'Máximo 1,000 filas por carga%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_load(v_a, 'pacientes', '[]'::jsonb, false, 'x', null, 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-69 · Archivo vacío se rechaza y dice cómo debe venir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-69 · Archivo vacío se rechaza y dice cómo debe venir','ok',sqlerrm like 'No hay filas para cargar%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_load(v_a, 'recetas', jsonb_build_array(jsonb_build_object('nombre','x')), false, 'x', null, 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-70 · Tipo de carga inventado se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-70 · Tipo de carga inventado se rechaza','ok',sqlerrm like 'Tipo de carga no válido%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_load(v_a, 'citas', jsonb_build_array(jsonb_build_object('nombre','Paciente QA')), false, 'x', null, 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-71 · Cliente con 2 médicos: hay que elegir el médico del archivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-71 · Cliente con 2 médicos: hay que elegir el médico del archivo','ok',sqlerrm like 'Elija el médico al que pertenece el archivo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_load(v_a, 'citas', jsonb_build_array(jsonb_build_object('nombre','Paciente QA')), false, 'x', v_pb, 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-72 · El médico de OTRO cliente no sirve','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-72 · El médico de OTRO cliente no sirve','ok',sqlerrm like 'El médico elegido no es un médico activo de este cliente%','d',left(sqlerrm,120)));
    end;
    select count(*) into v_n0 from public.appointments where organization_id = v_a;
    v_rows := jsonb_build_array(jsonb_build_object('documento', '00100000017', 'nombre', 'Paciente Uno QA', 'fecha', to_char(current_date - 30, 'DD/MM/YYYY'), 'hora', '09:30', 'ars', 'qa_gl_ars', 'afiliado', 'AF-0001', 'motivo', 'Control'), jsonb_build_object('documento', '00100000108', 'nombre', 'Paciente Privado QA', 'fecha', to_char(current_date - 10, 'DD/MM/YYYY'), 'hora', '10:00', 'estado', 'no_asistio'), jsonb_build_object('nombre', 'Paciente Muy Viejo QA', 'fecha', to_char(current_date - 403, 'DD/MM/YYYY')), jsonb_build_object('nombre', 'Paciente Pasado Programado QA', 'fecha', to_char(current_date - 5, 'DD/MM/YYYY'), 'estado', 'programada'), jsonb_build_object('nombre', 'Paciente Futuro Atendido QA', 'fecha', to_char(current_date + 5, 'DD/MM/YYYY'), 'estado', 'atendida'), jsonb_build_object('nombre', 'Paciente Hora Mala QA', 'fecha', to_char(current_date - 3, 'DD/MM/YYYY'), 'hora', '25:99'), jsonb_build_object('documento', '00100000017', 'nombre', 'Paciente Uno QA', 'fecha', to_char(current_date - 30, 'DD/MM/YYYY'), 'hora', '09:30'), jsonb_build_object('nombre', 'Paciente Futuro QA', 'fecha', to_char(current_date + 20, 'DD/MM/YYYY'), 'hora', '15:00', 'estado', 'confirmada'), jsonb_build_object('documento', '00100000117', 'nombre', 'Paciente Cedula Mala QA', 'fecha', to_char(current_date - 2, 'DD/MM/YYYY')), jsonb_build_object('nombre', 'Paciente Sin Fecha QA'), jsonb_build_object('nombre', 'Paciente Lejano QA', 'fecha', to_char(current_date + 400, 'DD/MM/YYYY')));
    v_r := public.golive_load(v_a, 'citas', v_rows, false, 'citas.xlsx', v_pa, 'Sistema anterior QA');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-73 · Vista previa de citas: 3 aceptadas y 8 rechazadas, sin guardar nada','ok',coalesce(((v_r->>'accepted')::int = 3 and (v_r->>'rejected')::int = 8 and (select count(*) from public.appointments where organization_id = v_a) = v_n0), false),'d',(v_r->>'accepted')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-74 · Cita de hace 13 meses: rechazada por pasar el tope de 12 meses y dice cómo ampliarlo','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 3) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 3) like '%tope de 12 meses hacia atrás%' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 3) like '%ampliar el tope%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-75 · Cita pasada «programada», cita futura «atendida», hora 25:99, cédula mala, sin fecha y a más de un año: rechazadas con motivo','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 4) = 'rechazada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 5) = 'rechazada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 6) = 'rechazada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 9) = 'rechazada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 10) = 'rechazada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 11) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 4) like '%Cita pasada con estado%' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 5) like '%Cita futura con estado%' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 6) like '%Hora inválida%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-76 · La cita repetida dentro del archivo se rechaza','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) = 'aceptada' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 7) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 7) like '%Duplicado dentro del archivo%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.golive_load(v_a, 'citas', v_rows, true, 'citas.xlsx', v_pa, 'Sistema anterior QA');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-77 · Al confirmar se crean 3 citas: con ARS, privada y futura; la primera queda ligada a su paciente y la pasada queda atendida','ok',coalesce(((select count(*) from public.appointments where organization_id = v_a) = v_n0 + 3 and exists (select 1 from public.appointments a join public.patients p on p.id = a.patient_id where a.organization_id = v_a and a.patient_doc = '00100000017' and a.payer_type = 'ars' and a.ars_id = v_ars and a.status = 'atendida' and a.appointment_time = time '09:30') and exists (select 1 from public.appointments a where a.organization_id = v_a and a.payer_type = 'privado' and a.status = 'no_asistio') and exists (select 1 from public.appointments a where a.organization_id = v_a and a.status = 'confirmada' and a.appointment_date > current_date and a.notes = 'Carga inicial')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.golive_load(v_a, 'citas', v_rows, true, 'citas.xlsx', v_pa, 'Sistema anterior QA');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-78 · Repetir la carga de citas no duplica: las 3 salen rechazadas por «Ya existe esa cita»','ok',coalesce(((v_r->>'accepted')::int = 0 and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) like '%Ya existe esa cita%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform public.golive_config_set(v_a, null, 3);
    v_r := public.golive_load(v_a, 'citas', jsonb_build_array(jsonb_build_object('nombre', 'Paciente Hace Cinco Meses QA', 'fecha', to_char(current_date - 150, 'DD/MM/YYYY'))), false, 'x', v_pa, 'x');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-79 · Con el tope en 3 meses, una cita de hace 5 meses se rechaza (el tope es por cliente y configurable)','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) like '%tope de 3 meses%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform public.golive_config_set(v_a, null, 24);
    v_r := public.golive_load(v_a, 'citas', jsonb_build_array(jsonb_build_object('nombre', 'Paciente Hace Trece Meses QA', 'fecha', to_char(current_date - 390, 'DD/MM/YYYY'))), false, 'x', v_pa, 'x');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-80 · Con el tope en 24 meses, una cita de hace 13 meses se acepta','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) = 'aceptada' and (v_r->>'months_back')::int = 24), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform public.golive_config_set(v_a, null, 12);
    select count(*) into v_n0 from public.service_lines where organization_id = v_a;
    v_rows := jsonb_build_array(jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date - 60, 'DD/MM/YYYY'), 'paciente', 'Afiliado Viejo Uno QA', 'nss', 'NSS-QA-001', 'autorizacion', 'AUT-0001', 'cedula', '00100000124', 'monto', '1500'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date - 90, 'DD/MM/YYYY'), 'paciente', 'Afiliado Viejo Dos QA', 'nss', 'NSS-QA-002', 'autorizacion', 'AUT-0002', 'monto', 'RD$ 2,200.50'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date - 60, 'DD/MM/YYYY'), 'paciente', 'Afiliado Viejo Uno QA', 'nss', 'NSS-QA-001', 'autorizacion', 'AUT-0003', 'monto', '1500'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date - 403, 'DD/MM/YYYY'), 'paciente', 'Afiliado Muy Viejo QA', 'nss', 'NSS-QA-003', 'autorizacion', 'AUT-0004', 'monto', '900'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date + 2, 'DD/MM/YYYY'), 'paciente', 'Afiliado Futuro QA', 'nss', 'NSS-QA-004', 'autorizacion', 'AUT-0005', 'monto', '900'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date - 20, 'DD/MM/YYYY'), 'paciente', 'Afiliado Sin Autorizacion QA', 'nss', 'NSS-QA-005', 'monto', '900'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', 'SERVICIO-QUE-NO-EXISTE', 'fecha', to_char(current_date - 20, 'DD/MM/YYYY'), 'paciente', 'Afiliado Servicio Raro QA', 'nss', 'NSS-QA-006', 'autorizacion', 'AUT-0006', 'monto', '900'), jsonb_build_object('servicio', v_code, 'fecha', to_char(current_date - 20, 'DD/MM/YYYY'), 'paciente', 'Afiliado Sin ARS QA', 'nss', 'NSS-QA-007', 'autorizacion', 'AUT-0007', 'monto', '900'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date - 20, 'DD/MM/YYYY'), 'paciente', 'Afiliado Cedula Mala QA', 'nss', 'NSS-QA-008', 'autorizacion', 'AUT-0008', 'cedula', '00100000133', 'monto', '900'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date - 20, 'DD/MM/YYYY'), 'paciente', 'Afiliado Sin Monto QA', 'nss', 'NSS-QA-009', 'autorizacion', 'AUT-0009'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date - 20, 'DD/MM/YYYY'), 'paciente', 'Afiliado Monto Malo QA', 'nss', 'NSS-QA-010', 'autorizacion', 'AUT-0010', 'monto', 'mucho'), jsonb_build_object('ars', 'qa_gl_ars', 'servicio', v_code, 'fecha', to_char(current_date - 15, 'DD/MM/YYYY'), 'paciente', 'Emergencia Sin Autorizacion QA', 'nss', 'NSS-QA-011', 'modo', 'emergencia', 'monto', '700'));
    v_r := public.golive_load(v_a, 'cuentas', v_rows, false, 'cuentas.xlsx', v_pa, 'Sistema anterior QA');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-81 · Vista previa de cuentas por cobrar: 3 aceptadas (2 con autorización y 1 emergencia) y 9 rechazadas; no crea reclamaciones','ok',coalesce(((v_r->>'accepted')::int = 3 and (v_r->>'rejected')::int = 9 and (select count(*) from public.service_lines where organization_id = v_a) = v_n0 and (v_r->>'since')::date = current_date - interval '12 months'), false),'d',(v_r->>'accepted')::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-82 · Reclamación repetida dentro del archivo, fuera del tope y futura: rechazadas con su motivo','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 3) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 3) like '%Duplicado dentro del archivo%' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 4) like '%tope de 12 meses%' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 5) like '%no puede ser futura%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-83 · Sin autorización (salvo emergencia), servicio desconocido, sin ARS y cédula mala: rechazadas con motivo','ok',coalesce(((select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 6) like '%Falta la autorización%' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 7) like '%Servicio no encontrado%' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 8) like '%Falta la ARS%' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 9) like '%dígito verificador%' and (select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 12) = 'aceptada'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-84 · Sin monto ni tarifa y monto ilegible: rechazadas diciendo qué hacer','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 10) = 'rechazada' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 10) like '%indique el monto%' and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 11) like '%Monto inválido%'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.golive_load(v_a, 'cuentas', v_rows, true, 'cuentas.xlsx', v_pa, 'Sistema anterior QA');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-85 · Al confirmar se capturan 3 reclamaciones reales (con las reglas de la captura manual) marcadas como carga inicial','ok',coalesce(((select count(*) from public.service_lines where organization_id = v_a) = v_n0 + 3 and (select count(*) from public.service_lines where organization_id = v_a and notes like '%Carga inicial (cuenta por cobrar vieja)%') = 3 and exists (select 1 from public.service_lines where organization_id = v_a and member_number = 'NSS-QA-002' and amount = 2200.50) and (select rows_accepted from public.golive_load_batches where id = (v_r->>'batch_id')::uuid) = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.golive_load(v_a, 'cuentas', v_rows, true, 'cuentas.xlsx', v_pa, 'Sistema anterior QA');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-86 · Repetir la carga de cuentas no duplica reclamaciones: la captura detecta el duplicado y la fila sale rechazada','ok',coalesce(((v_r->>'accepted')::int = 0 and (select x->>'reasons' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) like '%duplicada%' and (select count(*) from public.service_lines where organization_id = v_a) = v_n0 + 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-87 · Los tres pasos de carga se cumplen solos','ok',coalesce((app.golive_auto(v_a, 'carga_pacientes') and app.golive_auto(v_a, 'carga_citas') and app.golive_auto(v_a, 'carga_cuentas')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.golive_load(v_b, 'citas', jsonb_build_array(jsonb_build_object('nombre', 'Paciente B Unico QA', 'fecha', to_char(current_date - 4, 'DD/MM/YYYY'))), false, 'x', null, 'x');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-88 · Con un solo médico activo no hace falta elegirlo','ok',coalesce(((select x->>'status' from jsonb_array_elements(v_r->'rows') x where (x->>'row')::int = 1) = 'aceptada'), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.golive_load(v_c, 'cuentas', jsonb_build_array(jsonb_build_object('nombre','x')), false, 'x', null, 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-89 · Cliente sin médicos activos: dice que hay que elegir (0 médicos)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-89 · Cliente sin médicos activos: dice que hay que elegir (0 médicos)','ok',sqlerrm like 'Elija el médico%0 médicos%','d',left(sqlerrm,120)));
    end;
    v_r := public.golive_load_report(v_b1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-90 · El reporte de la carga de pacientes trae lote, 13 filas y los motivos de las rechazadas','ok',coalesce(((v_r->'batch'->>'total')::int = 13 and (v_r->'batch'->>'rejected')::int = 10 and jsonb_array_length(v_r->'rows') = 13 and (v_r->'batch'->>'client') = 'QA GL Consultorio A' and (select count(*) from jsonb_array_elements(v_r->'rows') x where x->>'status' = 'rechazada' and jsonb_array_length(x->'reasons') > 0) = 10), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.golive_load_report(v_b1);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-91 · El Médico del cliente puede leer el reporte de su propia carga','ok',coalesce(((v_r->'batch'->>'accepted')::int = 3), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mb, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_load_report(v_b1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-92 · ATAQUE: el Médico de otro cliente no lee el reporte','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-92 · ATAQUE: el Médico de otro cliente no lee el reporte','ok',sqlerrm like 'No se encontró ese reporte%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec1, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_load_report(v_b1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-93 · ATAQUE: la Secretaria no lee el reporte','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-93 · ATAQUE: la Secretaria no lee el reporte','ok',sqlerrm like 'No se encontró ese reporte%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      update public.golive_load_batches set rows_accepted = 0 where id = v_b1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-94 · Los lotes de carga no se modifican (ni con SQL directo)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-94 · Los lotes de carga no se modifican (ni con SQL directo)','ok',sqlerrm like 'Este registro de la puesta en marcha es de solo consulta%','d',left(sqlerrm,120)));
    end;
    begin
      delete from public.golive_load_rows where batch_id = v_b1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-95 · Las filas del reporte no se borran','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-95 · Las filas del reporte no se borran','ok',sqlerrm like 'Este registro de la puesta en marcha es de solo consulta%','d',left(sqlerrm,120)));
    end;
    begin
      update public.golive_log set detail = 'borrado' where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-96 · La bitácora no se modifica','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-96 · La bitácora no se modifica','ok',sqlerrm like 'Este registro de la puesta en marcha es de solo consulta%','d',left(sqlerrm,120)));
    end;
    begin
      delete from public.golive_log where organization_id = v_a;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-97 · La bitácora no se borra','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-97 · La bitácora no se borra','ok',sqlerrm like 'Este registro de la puesta en marcha es de solo consulta%','d',left(sqlerrm,120)));
    end;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-98 · Cada carga confirmada quedó en la bitácora con sus números','ok',coalesce(((select count(*) from public.golive_log where organization_id = v_a and action = 'carga') >= 4), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_go_real(v_a, 'PASAR A REAL');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-99 · Pasar a real sin la lista completa se rechaza y nombra lo que falta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-99 · Pasar a real sin la lista completa se rechaza y nombra lo que falta','ok',sqlerrm like 'Todavía no se puede pasar a real. Faltan % paso(s) obligatorio(s)%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_go_real(v_a, 'PASAR A REAL');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-100 · El mensaje de lo que falta nombra pasos concretos (prueba de extremo a extremo)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-100 · El mensaje de lo que falta nombra pasos concretos (prueba de extremo a extremo)','ok',sqlerrm like '%Prueba de extremo a extremo%','d',left(sqlerrm,120)));
    end;
    perform public.golive_step_update(v_a, 'datos_medico', 'completado', 'Evidencia QA del paso datos_medico: revisado y soportado');
    perform public.golive_step_update(v_a, 'usuarios', 'completado', 'Evidencia QA del paso usuarios: revisado y soportado');
    perform public.golive_step_update(v_a, 'tarifario', 'completado', 'Evidencia QA del paso tarifario: revisado y soportado');
    perform public.golive_step_update(v_a, 'ars_cartas', 'completado', 'Evidencia QA del paso ars_cartas: revisado y soportado');
    perform public.golive_step_update(v_a, 'revision_carga', 'completado', 'Evidencia QA del paso revision_carga: revisado y soportado');
    perform public.golive_step_update(v_a, 'capacitacion', 'completado', 'Evidencia QA del paso capacitacion: revisado y soportado');
    perform public.golive_step_update(v_a, 'prueba_extremo', 'completado', 'Evidencia QA del paso prueba_extremo: revisado y soportado');
    v_r := public.golive_checklist(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-101 · Con 8 de 9 obligatorios aún no está listo (falta la aprobación del médico)','ok',coalesce(((v_r->>'mandatory_done')::int = 8 and not (v_r->>'ready')::boolean and v_r->'missing'->>0 like '%aprueba pasar a real%'), false),'d',(v_r->>'pct')::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.golive_go_real(v_a, 'PASAR A REAL');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-102 · Aún falta la aprobación del médico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-102 · Aún falta la aprobación del médico','ok',sqlerrm like '%El médico aprueba pasar a real%','d',left(sqlerrm,120)));
    end;
    perform public.golive_step_update(v_a, 'aprobacion_medico', 'completado', 'Aprobó por mensaje del 14/11 a las 10:20');
    v_r := public.golive_checklist(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-103 · Con los 9 obligatorios cumplidos la lista está lista (100 %) y nada atrasado entre los obligatorios','ok',coalesce(((v_r->>'ready')::boolean and (v_r->>'pct')::int = 100 and jsonb_array_length(v_r->'missing') = 0 and not exists (select 1 from jsonb_array_elements(v_r->'steps') x where (x->>'mandatory')::boolean and (x->>'late')::boolean)), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.golive_go_real(v_a, 'si');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-104 · Sin escribir la confirmación no pasa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-104 · Sin escribir la confirmación no pasa','ok',sqlerrm like 'Para confirmar escriba exactamente PASAR A REAL%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_go_real(v_a, 'pasar a real');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-105 · Confirmación en minúscula tampoco','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-105 · Confirmación en minúscula tampoco','ok',sqlerrm like 'Para confirmar escriba exactamente PASAR A REAL%','d',left(sqlerrm,120)));
    end;
    v_s := public.golive_go_real(v_a, 'PASAR A REAL', 'Arranque con la Dra. QA el lunes');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-106 · Pasar a real: cambia el modo, fija la fecha y deja la bitácora con quién y la nota','ok',coalesce((v_s->>'mode' = 'real' and (select mode from public.golive_clients where organization_id = v_a) = 'real' and (select real_since is not null and real_by = v_ops::uuid from public.golive_clients where organization_id = v_a) and exists (select 1 from public.golive_log where organization_id = v_a and action = 'pasar_a_real' and user_id = v_ops::uuid and detail like '%Arranque con la Dra. QA%')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
      perform public.golive_go_real(v_a, 'PASAR A REAL');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-107 · Pasar a real otra vez dice que ya está en real','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-107 · Pasar a real otra vez dice que ya está en real','ok',sqlerrm like 'Este cliente ya está en modo real%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_load(v_a, 'pacientes', jsonb_build_array(jsonb_build_object('nombre','Paciente Tardio QA')), true, 'x', null, 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-108 · Con el cliente en real ya no se hace la carga inicial','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-108 · Con el cliente en real ya no se hace la carga inicial','ok',sqlerrm like 'Este cliente ya está en modo real%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ma, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.golive_checklist(v_a);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-109 · El Médico ve que su cliente ya está en real (solo lectura)','ok',coalesce((v_r->>'mode' = 'real' and (v_r->>'read_only')::boolean), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    begin
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.organizations set status = 'suspendido' where id = v_c;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      begin
        perform public.golive_go_real(v_c, 'PASAR A REAL');
        v_n0 := -1;
      exception when others then v_n0 := case when sqlerrm like 'El cliente está suspendido en SOFA%' then 1 else 0 end; end;
      begin
        perform public.golive_load(v_c, 'pacientes', jsonb_build_array(jsonb_build_object('nombre','Paciente QA')), false, 'x', null, 'x');
        v_n0 := v_n0 * 10 - 1;
      exception when others then v_n0 := v_n0 * 10 + case when sqlerrm like 'El cliente está suspendido en SOFA%' then 1 else 0 end; end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-110 · Un cliente suspendido no pasa a real ni recibe cargas','ok',coalesce((v_n0 = 11), false),'d',(null)::text));
      raise exception 'sofa_sub_rollback';
    exception when others then
      if sqlerrm <> 'sofa_sub_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado en un bloque de pruebas','ok',false,'d',left(sqlerrm,250))); end if;
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_go_back(v_a, 'Motivo suficientemente largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-111 · Devolver a prueba: el Administrador no puede','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-111 · Devolver a prueba: el Administrador no puede','ok',sqlerrm like 'Solo el Super Admin devuelve%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_go_back(v_a, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-112 · Devolver a prueba sin motivo suficiente se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-112 · Devolver a prueba sin motivo suficiente se rechaza','ok',sqlerrm like 'Escriba el motivo para devolverlo a prueba%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.golive_go_back(v_b, 'Motivo suficientemente largo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-113 · Devolver a prueba un cliente que ya está en prueba se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-113 · Devolver a prueba un cliente que ya está en prueba se rechaza','ok',sqlerrm like 'Este cliente ya está en modo prueba%','d',left(sqlerrm,120)));
    end;
    v_s := public.golive_go_back(v_a, 'Se pasó a real por error: falta cargar el tarifario nuevo');
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-114 · El Super Admin devuelve a prueba con motivo: queda en prueba y en la bitácora','ok',coalesce((v_s->>'mode' = 'prueba' and (select mode from public.golive_clients where organization_id = v_a) = 'prueba' and exists (select 1 from public.golive_log where organization_id = v_a and action = 'volver_a_prueba' and detail like '%por error%')), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_b, v_pb, v_ars, date_trunc('month', current_date)::date, 1, 'borrador', current_date - 85);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_r := public.golive_overview();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-115 · Resumen: aparecen los 3 clientes de la prueba, B con 9 obligatorios y 1 cumplido solo; A en prueba (devuelto) con sus 9 hechos','ok',coalesce(((select count(*) from jsonb_array_elements(v_r) x where x->>'client' like 'QA GL%') = 3 and (select (x->>'mandatory_total')::int || '/' || (x->>'mandatory_done')::int from jsonb_array_elements(v_r) x where x->>'client' = 'QA GL Consultorio B') = '9/1' and (select (x->>'mandatory_done')::int from jsonb_array_elements(v_r) x where x->>'client' = 'QA GL Consultorio A') = 9), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-116 · El resumen marca el atraso de B (firma hace 90 días: todo vencido)','ok',coalesce(((select (x->>'late')::int from jsonb_array_elements(v_r) x where x->>'client' = 'QA GL Consultorio B') >= 9), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    select count(*) into v_n0 from public.golive_first_claim_days() where days_to_first_claim is not null;
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-117 · Indicador firma → primera reclamación radicada: B = 5 días (firma hace 90, radicada hace 85); A sin radicada = vacío','ok',coalesce(((select days_to_first_claim from public.golive_first_claim_days() where client = 'QA GL Consultorio B') = 5 and (select first_claim_on from public.golive_first_claim_days() where client = 'QA GL Consultorio B') = current_date - 85 and (select days_to_first_claim from public.golive_first_claim_days() where client = 'QA GL Consultorio A') is null and v_n0 >= 1), false),'d',(null)::text));
    perform set_config('role', v_rl, true);
    v_r := public.golive_indicador();
    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-118 · golive_indicador resume: al menos un cliente con reclamación, promedio y mediana calculados, y los de prueba contados','ok',coalesce(((v_r->>'clients_with_claim')::int >= 1 and (v_r->>'avg_days')::numeric is not null and (v_r->>'median_days')::numeric is not null and (v_r->>'in_test')::int >= 2), false),'d',(v_r::text)::text));
    perform set_config('role', v_rl, true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_first_claim_days();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-119 · ATAQUE: Facturación no ve el indicador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-119 · ATAQUE: Facturación no ve el indicador','ok',sqlerrm like 'El indicador de puesta en marcha lo ven%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_co, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.golive_overview();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-120 · ATAQUE: el Comercial no ve el resumen','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','GL-120 · ATAQUE: el Comercial no ve el resumen','ok',sqlerrm like 'La puesta en marcha la manejan%','d',left(sqlerrm,120)));
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

revoke all on function app.qa_run_tests_golive() from public, anon, authenticated;
