-- 207 · Prueba de la 206 (Reporte de hospitalización del médico · I68a). app.qa_run_tests_hospital()
-- Se deshace sola (rollback por excepción). No deja datos. NO cambia el rol de sesión; la identidad va por el claim sub.
create or replace function app.qa_run_tests_hospital()
returns table(n int, resultado text, prueba text, detalle text)
language plpgsql
as $function$
declare
  v_res jsonb := '[]'::jsonb;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_sa   constant uuid := '20700000-0000-4000-8000-000000000001';
  v_medU constant uuid := '20700000-0000-4000-8000-000000000002';
  v_med2U constant uuid := '20700000-0000-4000-8000-000000000003';
  v_sinU constant uuid := '20700000-0000-4000-8000-000000000004';  -- usuario sin provider
  v_cli  constant uuid := '20700000-0000-4000-8000-0000000000a1';
  v_cli2 constant uuid := '20700000-0000-4000-8000-0000000000a2';
  v_cliX constant uuid := '20700000-0000-4000-8000-0000000000a3';  -- centro que NO es de la ficha
  v_med  constant uuid := '20700000-0000-4000-8000-0000000000b1';
  v_med2 constant uuid := '20700000-0000-4000-8000-0000000000b2';
  v_hc1  constant uuid := '20700000-0000-4000-8000-0000000000c1';  -- centro de salud de la Clínica A
  v_hc2  constant uuid := '20700000-0000-4000-8000-0000000000c2';  -- centro de salud de la Clínica B
  v_hcX  constant uuid := '20700000-0000-4000-8000-0000000000c3';  -- centro de salud que NO está en la ficha
  v_proc1 uuid; v_proc2 uuid; v_rep uuid; v_line uuid; v_x jsonb; v_ok boolean; v_t text; v_total numeric;
begin
  if not exists (select 1 from app.schema_migrations where version = '206') then
    raise exception 'Falta la migración 206. Aplícala y vuelve a correr las pruebas.';
  end if;

  begin
    insert into public.organizations (id, kind, operator_id, legal_name, org_type, status, started_on) values
      (v_cli,'client',v_sofa,'QA I68 Clínica A','Centro médico','activo',current_date-200),
      (v_cli2,'client',v_sofa,'QA I68 Clínica B','Centro médico','activo',current_date-200),
      (v_cliX,'client',v_sofa,'QA I68 Clínica X','Centro médico','activo',current_date-200)
      on conflict (id) do nothing;
    insert into auth.users (id,email) values (v_sa,'qa.i68.sa@sofa.do'),(v_medU,'qa.i68.med@sofa.do'),(v_med2U,'qa.i68.med2@sofa.do'),(v_sinU,'qa.i68.sin@sofa.do') on conflict (id) do nothing;
    insert into public.profiles (id, full_name, is_active) values
      (v_sa,'QA SA',true),(v_medU,'Dr. QA',true),(v_med2U,'Dra. QA 2',true),(v_sinU,'QA Sin Provider',true)
      on conflict (id) do update set is_active=true;
    insert into public.organization_users (organization_id,user_id,role_code,is_active) values
      (v_sofa,v_sa,'super_admin',true),
      (v_cli, v_medU,'client',true), (v_cli2, v_medU,'client',true),
      (v_cli, v_med2U,'client',true) on conflict do nothing;
    insert into public.providers (id, organization_id, full_name, specialty, is_active, user_id) values
      (v_med, v_cli, 'Dr. QA', 'Cirugía', true, v_medU),
      (v_med2, v_cli, 'Dra. QA 2', 'Pediatría', true, v_med2U) on conflict (id) do nothing;
    -- centros de salud (pertenecen a cada clínica)
    insert into public.health_centers (id, organization_id, name, is_active) values
      (v_hc1, v_cli, 'Centro A', true), (v_hc2, v_cli2, 'Centro B', true), (v_hcX, v_cliX, 'Centro X', true) on conflict (id) do nothing;
    -- ficha del médico: trabaja en Centro A (principal) y Centro B, NO en X
    insert into public.provider_centers (provider_id, center_id, is_primary) values
      (v_med, v_hc1, true), (v_med, v_hc2, false) on conflict do nothing;
    select id into v_proc1 from public.procedures where is_active order by internal_code limit 1;
    select id into v_proc2 from public.procedures where is_active and id <> v_proc1 order by internal_code limit 1;
    -- tarifario del médico: solo v_proc1 tiene precio
    insert into public.private_tariffs (organization_id, provider_id, procedure_id, amount, status, valid_during)
      values (v_cli, v_med, v_proc1, 1500.00, 'vigente', daterange(current_date-365, null, '[)'));

    -- CF estructura
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-01 · La migración 206 queda registrada','ok',exists(select 1 from app.schema_migrations where version='206'),'d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-02 · Las tablas no las toca la API (ni anon ni authenticated)','ok',
      (not has_table_privilege('authenticated','public.hospital_reports','select') and not has_table_privilege('authenticated','public.hospital_report_lines','insert')),'d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-03 · Las funciones públicas son SECURITY DEFINER con search_path vacío','ok',
      (select bool_and(p.prosecdef and array_to_string(coalesce(p.proconfig,array[]::text[]),',') like '%search_path=%')
         from pg_proc p join pg_namespace nx on nx.oid=p.pronamespace
        where nx.nspname='public' and p.proname in ('hospital_centers_mine','hospital_report_save','hospital_report_line_add','hospital_report_submit','hospital_report_get','hospital_report_list')),'d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-04 · No abiertas a anon y sí a authenticated','ok',
      (not has_function_privilege('anon','public.hospital_centers_mine()','execute') and has_function_privilege('authenticated','public.hospital_centers_mine()','execute')),'d',null));

    -- Sesión del médico
    perform set_config('request.jwt.claims', json_build_object('sub', v_medU, 'role','authenticated','aal','aal2')::text, true);

    -- HS-05 · sus centros
    v_x := public.hospital_centers_mine();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-05 · El médico ve los centros de su ficha (2), con el principal primero','ok',
      (v_x->>'soy_medico')::boolean and jsonb_array_length(v_x->'centros')=2 and (v_x->'centros'->0->>'principal')::boolean,'d',null));

    -- HS-19 · el médico ve su tarifario (el servicio con precio)
    v_x := public.hospital_my_tariff(current_date-2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-19 · El médico ve su tarifario con el precio vigente','ok',
      jsonb_array_length(v_x) >= 1 and exists(select 1 from jsonb_array_elements(v_x) e where (e->>'amount')::numeric = 1500),'d', format('%s servicios', jsonb_array_length(v_x))));

    -- HS-07 · crear reporte en un centro de su ficha
    v_x := public.hospital_report_save(v_hc1, 'Paciente QA', '001-0000000-1', null, current_date-3, null, 'ingreso de prueba');
    v_rep := (v_x->>'id')::uuid;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-07 · El médico crea un reporte en un centro de su ficha','ok',
      v_rep is not null and v_x->>'status'='borrador' and (v_x->>'puede_editar')::boolean,'d',null));

    -- HS-08 · ATAQUE: centro que no es de su ficha
    begin perform public.hospital_report_save(v_hcX, 'Paciente Y'); v_ok:=false; v_t:='no falló';
    exception when others then v_ok:=(sqlerrm like '%no está en tu ficha%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-08 · ATAQUE: no se reporta en un centro que no es de su ficha','ok',v_ok,'d',v_t));

    -- HS-09 · línea con precio del tarifario (auto)
    v_x := public.hospital_report_line_add(v_rep, v_proc1, current_date-2, 2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-09 · Línea cobrada al tarifario del médico (2 x 1500 = 3000)','ok',
      (v_x->>'total')::numeric = 3000 and (v_x->'lineas'->0->>'unit_amount')::numeric = 1500,'d', format('total=%s', v_x->>'total')));

    -- HS-10 · servicio sin precio en el tarifario y sin monto manual
    begin perform public.hospital_report_line_add(v_rep, v_proc2, current_date-2, 1); v_ok:=false; v_t:='no falló';
    exception when others then v_ok:=(sqlerrm like '%no tiene precio en tu tarifario%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-10 · Un servicio sin precio en el tarifario pide ponerlo a mano','ok',v_ok,'d',v_t));

    -- HS-11 · con monto manual sí entra
    v_x := public.hospital_report_line_add(v_rep, v_proc2, current_date-2, 1, 800);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-11 · Con precio a mano, el servicio sin tarifario sí se agrega','ok',
      (v_x->>'total')::numeric = 3800,'d', format('total=%s', v_x->>'total')));

    -- HS-12 · total se recalcula al quitar una línea
    v_line := (select l->>'id' from jsonb_array_elements(v_x->'lineas') l where (l->>'amount')::numeric = 800 limit 1)::uuid;
    v_x := public.hospital_report_line_remove(v_line);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-12 · Al quitar una línea el total baja (vuelve a 3000)','ok',(v_x->>'total')::numeric = 3000,'d', format('total=%s', v_x->>'total')));

    -- HS-18 · enviar sin líneas se rechaza (probado con un reporte nuevo vacío)
    v_x := public.hospital_report_save(v_hc2, 'Paciente Vacío');
    begin perform public.hospital_report_submit((v_x->>'id')::uuid); v_ok:=false; v_t:='no falló';
    exception when others then v_ok:=(sqlerrm like '%al menos un servicio%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-18 · No se envía un reporte sin servicios','ok',v_ok,'d',v_t));

    -- HS-13 · enviar el reporte con líneas: queda en firme
    v_x := public.hospital_report_submit(v_rep);
    v_ok := v_x->>'status'='enviado' and not (v_x->>'puede_editar')::boolean;
    begin perform public.hospital_report_line_add(v_rep, v_proc1, current_date-1, 1); v_ok := false; v_t:='dejó agregar';
    exception when others then v_ok := v_ok and (sqlerrm like '%ya fue enviado%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-13 · Enviado queda en firme y no admite más servicios','ok',v_ok,'d',v_t));

    -- HS-16 · la lista del médico trae solo lo suyo
    v_x := public.hospital_report_list();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-16 · El médico ve en la lista solo sus reportes','ok',
      jsonb_array_length(v_x) >= 1 and not exists(select 1 from jsonb_array_elements(v_x) e where e->>'medico' <> 'Dr. QA'),'d', format('%s reportes', jsonb_array_length(v_x))));

    -- HS-06 · usuario sin provider
    perform set_config('request.jwt.claims', json_build_object('sub', v_sinU, 'role','authenticated','aal','aal2')::text, true);
    v_x := public.hospital_centers_mine();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-06 · Un usuario que no es médico no tiene centros','ok',not (v_x->>'soy_medico')::boolean,'d',null));

    -- HS-14 · ATAQUE: otro médico no ve el reporte ajeno
    perform set_config('request.jwt.claims', json_build_object('sub', v_med2U, 'role','authenticated','aal','aal2')::text, true);
    begin v_x := public.hospital_report_get(v_rep); v_ok:=false; v_t:='lo vio';
    exception when others then v_ok:=(sqlerrm like '%no es tuyo%'); v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-14 · ATAQUE: otro médico no ve el reporte ajeno','ok',v_ok,'d',v_t));

    -- HS-15 · la supervisión de SOFA sí lo ve (solo lectura) por su centro
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role','authenticated','aal','aal2')::text, true);
    v_x := public.hospital_report_get(v_rep);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-15 · El Super Admin ve el reporte por su centro (no lo edita)','ok',
      v_x->>'id' = v_rep::text and not (v_x->>'puede_editar')::boolean,'d',null));

    -- HS-17 · sin sesión
    perform set_config('request.jwt.claims','',true);
    begin v_x := public.hospital_report_list(); v_ok:=false; v_t:='no falló';
    exception when others then v_ok:=true; v_t:=left(sqlerrm,80); end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HS-17 · ATAQUE: sin sesión no hay reportes','ok',v_ok,'d',v_t));

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('request.jwt.claims','',true);
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

revoke all on function app.qa_run_tests_hospital() from public, anon, authenticated;
