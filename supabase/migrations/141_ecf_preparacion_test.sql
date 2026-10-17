-- 141 · Suite de la 140 (preparación e-CF del médico). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_ecf_preparacion();
create or replace function app.qa_run_tests_ecf_preparacion()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01410000-0000-4000-8000-000000000001'; v_org2 constant uuid := '01410000-0000-4000-8000-000000000002'; v_prov constant uuid := '01410000-0000-4000-8000-000000000003';
  v_sa constant text := '01410000-0000-4000-8000-000000000011'; v_ops constant text := '01410000-0000-4000-8000-000000000012'; v_med constant text := '01410000-0000-4000-8000-000000000013'; v_sec constant text := '01410000-0000-4000-8000-000000000014'; v_otro constant text := '01410000-0000-4000-8000-000000000015';
  v_ars uuid; v_prv uuid; v_cnt int; v_s text;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.ec.sa@sofa.test','x'),(v_ops::uuid,'qa.ec.ops@sofa.test','x'),(v_med::uuid,'qa.ec.med@sofa.test','x'),(v_sec::uuid,'qa.ec.sec@sofa.test','x'),(v_otro::uuid,'qa.ec.otro@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ec.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA EC Consultorio', '00000000801', 'Médico independiente', 'activo', current_date - 90, '8095550801');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA EC Otro', '00000000802', 'Médico independiente', 'activo', current_date - 90, '8095550802');
    update public.organizations set ecf_required_from = current_date + 10, ecf_status = 'no_iniciado' where id in (v_org, v_org2);
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. e-CF', 'Medicina Interna');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'),
      (v_org2, v_otro::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin'), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_ec_ars', 'QA ARS e-CF', 'Contributivo', true) returning id into v_ars;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, ncf) values
      (v_org, v_prov, v_ars, date_trunc('month', current_date)::date, 1, 'borrador', 'B0100000001');
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, ncf, ecf_security_code, ecf_dgii_status) values
      (v_org, v_prov, v_ars, date_trunc('month', current_date)::date, 2, 'borrador', 'E310000000001', 'ABC123', 'aceptado');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.ecf_client_status(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-01 · El Médico ve sus 6 pasos, los días que faltan y puede marcarlos','ok',coalesce((jsonb_array_length(v_x->'steps') = 6 and (v_x->>'days_left')::int = 10 and (v_x->>'can_edit')::boolean), false),'d',(v_x::text)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-02 · Simulacro: el lote sin E31 sale bloqueado con sus 3 motivos; el lote aceptado no','ok',coalesce((jsonb_array_length(v_x->'blocked') = 1 and jsonb_array_length(v_x->'blocked'->0->'reasons') = 3), false),'d',(v_x->>'blocked')::text));
    begin
      perform public.ecf_client_step_set(v_org, 'proveedor', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-03 · Proveedor sin nombre: pide escribirlo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-03 · Proveedor sin nombre: pide escribirlo','ok',sqlerrm like 'Escriba el nombre del proveedor%','d',left(sqlerrm,120)));
    end;
    v_x := public.ecf_client_step_set(v_org, 'rnc', true, 'Oficina Virtual activa');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-04 · Al marcar el primer paso el cliente queda «en proceso»','ok',coalesce((v_x->>'status' = 'en_proceso' and not (v_x->>'all_done')::boolean), false),'d',(v_x::text)::text));
    perform public.ecf_client_step_set(v_org, 'proveedor', true, null, 'Proveedor QA');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-05 · Guarda el proveedor del cliente','ok',coalesce(((select ecf_provider from public.organizations where id = v_org) = 'Proveedor QA'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.ecf_client_status(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-06 · La Secretaria no ve la preparación e-CF','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-06 · La Secretaria no ve la preparación e-CF','ok',sqlerrm like 'Sin acceso a la preparación e-CF%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.ecf_client_step_set(v_org, 'rnc', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-07 · Otro cliente no marca pasos ajenos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-07 · Otro cliente no marca pasos ajenos','ok',sqlerrm like 'Solo el Médico o el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.ecf_readiness_board();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-08 · El Médico no ve el tablero de SOFA','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-08 · El Médico no ve el tablero de SOFA','ok',sqlerrm like 'El tablero e-CF es del equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    v_x := public.ecf_readiness_board();
    select x into v_x from jsonb_array_elements(v_x->'clients') x where (x->>'organization_id')::uuid = v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-09 · Tablero: en proceso con 10 días = rojo, 2 de 6 pasos, 1 lote bloqueado y el siguiente paso','ok',coalesce((v_x->>'light' = 'rojo' and (v_x->>'steps_done')::int = 2 and (v_x->>'blocked_lots')::int = 1 and v_x->>'next_step' like 'Certificado digital%'), false),'d',(v_x::text)::text));
    begin
      perform public.ecf_provider_save(null, 'Proveedor Uno');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-10 · Operaciones no cambia la lista de proveedores','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-10 · Operaciones no cambia la lista de proveedores','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    v_prv := public.ecf_provider_save(null, 'Proveedor Uno QA', 'https://ejemplo.do', 'Autorizado por la DGII');
    begin
      perform public.ecf_provider_save(null, 'proveedor uno qa');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-11 · No repite un proveedor','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-11 · No repite un proveedor','ok',sqlerrm like 'Ese proveedor ya está en la lista%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-12 · El Médico ve los proveedores que recomienda SOFA','ok',coalesce((exists (select 1 from jsonb_array_elements(public.ecf_client_status(v_org)->'providers') p where p->>'name' = 'Proveedor Uno QA')), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_cnt := app.ecf_followup();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-13 · Seguimiento: tarea para SOFA y aviso al Médico (10 días)','ok',coalesce((exists (select 1 from public.tasks where organization_id = v_org and title like 'e-CF: QA EC Consultorio%') and exists (select 1 from public.notifications where user_id = v_med::uuid and title like 'Facturación electrónica: faltan 10 días%')), false),'d',(v_cnt)::text));
    v_cnt := app.ecf_followup();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-14 · No repite el aviso el mismo umbral','ok',coalesce(((select count(*) from public.tasks where organization_id = v_org and title like 'e-CF: QA EC Consultorio%') = 1), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    perform public.ecf_client_step_set(v_org, s, true) from unnest(array['certificado','autorizacion','pruebas']) s;
    v_x := public.ecf_client_step_set(v_org, 'primer_e31', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-15 · Con los 6 pasos listos avisa que SOFA lo marque «Listo»','ok',coalesce(((v_x->>'all_done')::boolean and v_x->>'hint' like 'Todos los pasos están listos%'), false),'d',(v_x::text)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EC-16 · Las tablas solo se usan por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.ecf_client_steps', 'select') and not has_function_privilege('anon', 'public.ecf_client_status(uuid)', 'execute')), false),'d',(null)::text));

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
