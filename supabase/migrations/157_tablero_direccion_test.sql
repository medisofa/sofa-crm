-- 157 · Suite de la 156 (tablero de dirección de SOFA). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_tablero_direccion();
create or replace function app.qa_run_tests_tablero_direccion()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01570000-0000-4000-8000-000000000001'; v_org2 constant uuid := '01570000-0000-4000-8000-000000000002';
  v_sa constant text := '01570000-0000-4000-8000-000000000011'; v_bil constant text := '01570000-0000-4000-8000-000000000012'; v_med constant text := '01570000-0000-4000-8000-000000000013'; v_adm constant text := '01570000-0000-4000-8000-000000000014';
  v_m date := date_trunc('month', current_date)::date; v_lead uuid; v_te uuid; v_mrr0 numeric; v_cl0 int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.td.sa@sofa.test','x'),(v_bil::uuid,'qa.td.bil@sofa.test','x'),(v_med::uuid,'qa.td.med@sofa.test','x'),(v_adm::uuid,'qa.td.adm@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.td.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA TD Uno', '00000000881', 'Médico independiente', 'activo', current_date - 90, '8095550881');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA TD Dos', '00000000882', 'Médico independiente', 'activo', current_date - 90, '8095550882');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin'),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing'), ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.direction_board();
    v_mrr0 := (v_x->>'mrr')::numeric;
    v_cl0 := (v_x->>'clients_paying')::int;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.sofa_fees (organization_id, source_type, period, amount, service_code, description) values
      (v_org, 'manual', v_m, 10000, 'facturacion', 'QA'), (v_org, 'manual', v_m, 2000, 'codificacion', 'QA'), (v_org2, 'manual', v_m, 3000, 'facturacion', 'QA'),
      (v_org, 'manual', (v_m - interval '12 months')::date, 9000, 'facturacion', 'QA');
    insert into public.leads (operator_id, company, contact_name, source) values ('00000000-0000-4000-8000-000000000001'::uuid, 'QA TD Prospecto', 'Dr. Prospecto', 'Otro') returning id into v_lead;
    insert into public.leak_diagnostics (operator_id, lead_id, monthly_billing, glosa_pct, recoverable_pct, dso_days) values ('00000000-0000-4000-8000-000000000001'::uuid, v_lead, 100000, 20, 50, 120);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.direction_board();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-01 · MRR del mes suma los honorarios (+RD$ 15,000) y compara con la meta','ok',coalesce(((v_x->>'mrr')::numeric = v_mrr0 + 15000 and (v_x->>'target_mrr')::numeric > 0 and v_x ? 'mrr_pct_of_target'), false),'d',(v_x->>'mrr')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-02 · Mezcla por servicio y % de facturación médica','ok',coalesce((jsonb_array_length(v_x->'mix') >= 2 and v_x ? 'billing_mix_pct'), false),'d',(v_x->>'mix')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-03 · Tendencia de 12 meses y clientes que pagan','ok',coalesce((jsonb_array_length(v_x->'trend') = 12 and (v_x->>'clients_paying')::int = v_cl0 + 2), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-04 · Retención: el cliente de hace 12 meses sigue','ok',coalesce(((v_x->'retention_12m'->>'kept')::int >= 1), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-05 · Conversión de diagnósticos de fugas','ok',coalesce(((v_x->'funnel'->>'diagnostics')::int >= 1), false),'d',(v_x->>'funnel')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated')::text, true);
    begin
      perform public.direction_board();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-06 · Facturación no ve el tablero de dirección','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-06 · Facturación no ve el tablero de dirección','ok',sqlerrm like 'El tablero de dirección es solo%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.staff_time_add(v_org, 20, 'facturacion');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-07 · Horas fuera de rango: dice el rango','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-07 · Horas fuera de rango: dice el rango','ok',sqlerrm like 'Las horas van de 0.25 a 16%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.staff_time_add(v_org, 2, 'facturacion', current_date - 90);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-08 · Fecha muy vieja: la rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-08 · Fecha muy vieja: la rechaza','ok',sqlerrm like 'La fecha debe estar entre hoy%','d',left(sqlerrm,120)));
    end;
    v_te := public.staff_time_add(v_org, 2.6, 'glosas', current_date, 'Respuesta de glosas');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-09 · Facturación registra sus horas (redondeo a cuartos de hora)','ok',coalesce(((public.staff_time_mine(7)->0->>'hours')::numeric = 2.5), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.staff_time_add(v_org, 1, 'otro');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-10 · El Médico no registra horas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-10 · El Médico no registra horas','ok',sqlerrm like 'El registro de horas es del equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.direction_board();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-11 · Horas y honorario por hora del cliente','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'by_client') c where (c->>'organization_id')::uuid = v_org and (c->>'hours')::numeric = 2.5 and (c->>'fee_per_hour')::numeric = 4800)), false),'d',(v_x->>'by_client')::text));
    begin
      perform public.direction_settings_save(300000, 60, 500);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-12 · El Administrador no cambia las metas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-12 · El Administrador no cambia las metas','ok',sqlerrm like 'Solo el Super Admin cambia las metas%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    perform public.direction_settings_save(300000, 60, 500);
    v_x := public.direction_board();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-13 · Con costo por hora, calcula el margen del cliente','ok',coalesce(((v_x->>'target_mrr')::numeric = 300000 and exists (select 1 from jsonb_array_elements(v_x->'by_client') c where (c->>'organization_id')::uuid = v_org and (c->>'margin')::numeric = 10750)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated')::text, true);
    perform public.staff_time_delete(v_te);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-14 · Cada quien borra sus propios registros','ok',coalesce((jsonb_array_length(public.staff_time_mine(7)) = 0), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TD-15 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.staff_time_entries', 'select') and not has_function_privilege('anon', 'public.direction_board(date)', 'execute')), false),'d',(null)::text));

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
