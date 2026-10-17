-- 153 · Suite de la 152 (insumos facturables (cruce de tres vías)). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_insumos();
create or replace function app.qa_run_tests_insumos()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01530000-0000-4000-8000-000000000001'; v_org2 constant uuid := '01530000-0000-4000-8000-000000000002'; v_prov constant uuid := '01530000-0000-4000-8000-000000000003';
  v_med constant text := '01530000-0000-4000-8000-000000000011'; v_sec constant text := '01530000-0000-4000-8000-000000000012'; v_otro constant text := '01530000-0000-4000-8000-000000000013'; v_gl constant text := '01530000-0000-4000-8000-000000000014';
  v_ars uuid; v_p1 uuid; v_sup uuid; v_sup2 uuid; v_s uuid; v_m date;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.in.med@sofa.test','x'),(v_sec::uuid,'qa.in.sec@sofa.test','x'),(v_otro::uuid,'qa.in.otro@sofa.test','x'),(v_gl::uuid,'qa.in.gl@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.in.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA IN Centro', '00000000861', 'Médico independiente', 'activo', current_date - 90, '8095550861');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA IN Otro', '00000000862', 'Médico independiente', 'activo', current_date - 90, '8095550862');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. Insumos', 'Gastroenterología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'),
      (v_org2, v_otro::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_gl::uuid, 'glosas');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_prov, v_org, true, false);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_in_ars', 'QA ARS Insumos', 'Contributivo', true) returning id into v_ars;
    select p.id into v_p1 from public.procedures p where p.is_active order by p.internal_code limit 1;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status) values (v_ars, v_org, v_prov, v_p1, 400, daterange(current_date - 400, null), 'vigente');
    v_m := date_trunc('month', current_date)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_prov, v_ars, v_m, 1, 'borrador') returning id into v_s;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_s, v_org, v_m, 'Paciente IN', v_p1, 3, 400);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.supply_save(v_org, null, 'KIT-1', 'Kit de biopsia', 'unidad', 150, true, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-01 · Insumo facturable sin servicio: pide el servicio con que se reclama','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-01 · Insumo facturable sin servicio: pide el servicio con que se reclama','ok',sqlerrm like 'Un insumo facturable necesita el servicio%','d',left(sqlerrm,120)));
    end;
    v_sup := public.supply_save(v_org, null, 'KIT-1', 'Kit de biopsia', 'unidad', 150, true, v_p1);
    v_sup2 := public.supply_save(v_org, null, 'GUA-1', 'Guantes', 'par', 20, false, null);
    begin
      perform public.supply_save(v_org, null, 'kit-1', 'Otro kit', 'unidad', 1, false, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-02 · No repite códigos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-02 · No repite códigos','ok',sqlerrm like 'Ya existe un insumo con el código%','d',left(sqlerrm,120)));
    end;
    v_x := public.supply_dispatch_import(v_org, jsonb_build_array(jsonb_build_object('codigo', 'KIT-1', 'fecha', to_char(current_date, 'DD/MM/YYYY'), 'cantidad', '10', 'referencia', 'SAL-1'),
              jsonb_build_object('codigo', 'XXX', 'fecha', 'ayer', 'cantidad', '0')), false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-03 · Revisión del archivo: 1 fila buena y 1 con errores explicados','ok',coalesce(((v_x->>'ok')::int = 1 and jsonb_array_length(v_x->'errors') = 1 and v_x->'errors'->0->'errors'->>0 like 'Código de insumo no está en el catálogo%'), false),'d',(v_x::text)::text));
    begin
      perform public.supply_dispatch_import(v_org, jsonb_build_array(jsonb_build_object('codigo', 'XXX', 'fecha', 'ayer', 'cantidad', '1')), true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-04 · Con errores no guarda nada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-04 · Con errores no guarda nada','ok',sqlerrm like 'Hay 1 fila(s) con errores%','d',left(sqlerrm,120)));
    end;
    perform public.supply_dispatch_import(v_org, jsonb_build_array(jsonb_build_object('codigo', 'KIT-1', 'fecha', to_char(current_date, 'DD/MM/YYYY'), 'cantidad', '10', 'referencia', 'SAL-1'),
              jsonb_build_object('codigo', 'GUA-1', 'fecha', to_char(current_date, 'DD/MM/YYYY'), 'cantidad', '50', 'referencia', 'SAL-2')), true);
    v_x := public.supply_dispatch_import(v_org, jsonb_build_array(jsonb_build_object('codigo', 'KIT-1', 'fecha', to_char(current_date, 'DD/MM/YYYY'), 'cantidad', '10', 'referencia', 'SAL-1')), true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-05 · Cargar la misma salida otra vez no la duplica','ok',coalesce(((v_x->>'duplicates')::int = 1 and (v_x->>'ok')::int = 0), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    perform public.supply_usage_add(v_org, v_sup, 7, current_date, v_prov, 'Paciente IN', 'Colonoscopia');
    perform public.supply_usage_add(v_org, v_sup2, 40, current_date, v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-06 · La Secretaria registra la hoja de consumo','ok',coalesce((jsonb_array_length(public.supply_catalog(v_org)->'recent') = 2 and not (public.supply_catalog(v_org)->>'can_admin')::boolean), false),'d',(null)::text));
    begin
      perform public.supply_reconciliation(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-07 · La Secretaria no ve el cruce','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-07 · La Secretaria no ve el cruce','ok',sqlerrm like 'Sin permiso para los insumos%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.supply_reconciliation(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-08 · Cruce: 10 despachados, 7 usados, 3 reclamados = 4 sin reclamar (RD$ 1,600) y 3 sin uso','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'rows') r where (r->>'supply_id')::uuid = v_sup and (r->>'dispatched')::numeric = 10 and (r->>'used')::numeric = 7 and (r->>'claimed')::numeric = 3 and (r->>'unbilled_amount')::numeric = 1600 and (r->>'inventory_qty')::numeric = 3 and r->>'verdict' = 'fuga_facturacion')), false),'d',(v_x->>'rows')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-09 · Guantes: no facturable, se costea (40 × 20 = RD$ 800) y fuga de inventario de 10','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'rows') r where (r->>'supply_id')::uuid = v_sup2 and (r->>'nonbillable_cost')::numeric = 800 and (r->>'inventory_qty')::numeric = 10)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-10 · Fuga de facturación del mes: 57.1 % de lo usado facturable','ok',coalesce(((v_x->'totals'->>'unbilled')::numeric = 1600 and (v_x->'totals'->>'leak_pct')::numeric = 57.1), false),'d',(v_x->>'totals')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.supply_catalog(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-11 · Otro cliente no ve estos insumos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-11 · Otro cliente no ve estos insumos','ok',sqlerrm like 'Sin permiso para los insumos%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_gl, 'role', 'authenticated')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-12 · Cobros y glosas ve el cruce','ok',coalesce(((public.supply_reconciliation(v_org)->'totals'->>'unbilled')::numeric = 1600), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','IN-13 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.supply_usage', 'select') and not has_function_privilege('anon', 'public.supply_catalog(uuid)', 'execute')), false),'d',(null)::text));

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
