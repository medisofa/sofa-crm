-- 139 · Suite de la 138 (cuenta del cliente con SOFA y casos de servicio). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_cuenta_sofa();
create or replace function app.qa_run_tests_cuenta_sofa()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-000000000401'; v_org2 constant uuid := 'b7000000-0000-4000-8000-000000000402';
  v_prov constant uuid := 'c7000000-0000-4000-8000-000000000401';
  v_sa constant text := 'a7000000-0000-4000-8000-000000000401'; v_ops constant text := 'a7000000-0000-4000-8000-000000000402';
  v_med constant text := 'a7000000-0000-4000-8000-000000000403'; v_sec constant text := 'a7000000-0000-4000-8000-000000000404';
  v_otro constant text := 'a7000000-0000-4000-8000-000000000405';
  v_ars uuid; v_p1 uuid; v_inv uuid; v_case uuid; v_case2 uuid; v_cnt int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.cs.sa@sofa.test','x'),(v_ops::uuid,'qa.cs.ops@sofa.test','x'),(v_med::uuid,'qa.cs.med@sofa.test','x'),(v_sec::uuid,'qa.cs.sec@sofa.test','x'),(v_otro::uuid,'qa.cs.otro@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.cs.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA CS Consultorio', '00000000791', 'Médico independiente', 'activo', current_date - 90, '8095550791');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA CS Otro', '00000000792', 'Médico independiente', 'activo', current_date - 90, '8095550792');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. Cuenta', 'Cardiología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'),
      (v_org2, v_otro::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin'), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_cs_ars', 'QA ARS Cuenta', 'Contributivo', true) returning id into v_ars;
    select id into v_p1 from public.procedures where is_active and internal_code is not null order by internal_code limit 1;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status, contract_ref)
    values (v_ars, v_org, v_prov, v_p1, 900, daterange((current_date - interval '2 years')::date + 20, null), 'vigente', 'QA-CS-CT');
    insert into public.provider_contracts (organization_id, service_code, folio, start_date, status, signed_on) values (v_org, 'facturacion', 'QA-CS-CON-1', current_date - 200, 'firmado', current_date - 200);
    insert into public.sofa_invoices (organization_id, folio, ncf, period, issued_on, due_on, total, status)
    values (v_org, 'QA-CS-F1', 'B0100000001', date_trunc('month', current_date - 60)::date, current_date - 45, current_date - 15, 5000, 'emitida') returning id into v_inv;
    insert into public.sofa_invoices (organization_id, folio, period, issued_on, due_on, total, status)
    values (v_org, 'QA-CS-F2', date_trunc('month', current_date - 30)::date, current_date - 10, current_date + 20, 3000, 'emitida'),
           (v_org, 'QA-CS-F3', date_trunc('month', current_date - 90)::date, current_date - 80, current_date - 50, 999, 'anulada');
    insert into public.sofa_invoice_payments (sofa_invoice_id, organization_id, paid_on, amount, method) values (v_inv, v_org, current_date - 20, 2000, 'transferencia');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.client_account(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-01 · El Médico ve su cuenta: contrato, facturas sin anuladas y saldo','ok',coalesce((jsonb_array_length(v_x->'contracts') = 1 and jsonb_array_length(v_x->'invoices') = 2 and (v_x->'summary'->>'balance')::numeric = 6000), false),'d',(v_x->>'summary')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-02 · Distingue lo vencido (factura 1: RD$ 3,000 tras abono)','ok',coalesce(((v_x->'summary'->>'overdue')::numeric = 3000 and (v_x->'summary'->>'overdue_count')::int = 1), false),'d',(v_x->>'summary')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.client_account(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-03 · La Secretaria no ve la cuenta con SOFA','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-03 · La Secretaria no ve la cuenta con SOFA','ok',sqlerrm like 'Sin acceso a la cuenta%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.client_account(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-04 · Otro cliente no ve esta cuenta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-04 · Otro cliente no ve esta cuenta','ok',sqlerrm like 'Sin acceso a la cuenta%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.service_case_request(v_org, 'codificacion', 'ayuda');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-05 · Solicitud sin detalle: pide explicar','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-05 · Solicitud sin detalle: pide explicar','ok',sqlerrm like 'Cuente en una o dos frases%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.service_case_request(v_org, 'nada', 'Necesito algo que no existe');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-06 · Servicio inexistente: pide elegir de la lista','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-06 · Servicio inexistente: pide elegir de la lista','ok',sqlerrm like 'Elija el servicio de la lista%','d',left(sqlerrm,120)));
    end;
    v_case := (public.service_case_request(v_org, 'codificacion', 'Necesito los códigos de la ARS para mi cardiólogo nuevo', v_prov, v_ars)->>'id')::uuid;
    begin
      perform public.service_case_request(v_org, 'codificacion', 'Necesito los códigos otra vez', v_prov, v_ars);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-07 · No duplica una solicitud igual en espera','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-07 · No duplica una solicitud igual en espera','ok',sqlerrm like 'Ya tiene una solicitud igual%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-08 · La solicitud crea el caso con folio y la tarea para SOFA','ok',coalesce(((select folio like 'SRV-%' and status = 'solicitado' and origin = 'cliente' from public.sofa_service_cases where id = v_case) and exists (select 1 from public.tasks t join public.sofa_service_cases c on c.task_id = t.id where c.id = v_case and t.status = 'abierta' and t.title like 'Solicitud de servicio SRV-%')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.service_case_update(v_case, 'en_proceso', 'x');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-09 · El Médico no actualiza el caso','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-09 · El Médico no actualiza el caso','ok',sqlerrm like 'Solo el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    begin
      perform public.service_case_update(v_case, 'en_espera_cliente', '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-10 · «En espera» exige explicar al cliente qué falta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-10 · «En espera» exige explicar al cliente qué falta','ok',sqlerrm like 'Explique en la nota el motivo%','d',left(sqlerrm,120)));
    end;
    perform public.service_case_update(v_case, 'en_espera_cliente', 'Envíe copia del exequátur del médico', true, 4500, 'Pago único', null, current_date + 10);
    perform public.service_case_update(v_case, null, 'Nota interna: revisar con la ARS', false);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-11 · El cliente recibe aviso solo de lo visible','ok',coalesce(((select count(*) from public.notifications where user_id = v_med::uuid and title like 'SRV-%') = 1 and not exists (select 1 from public.notifications where user_id = v_sec::uuid and title like 'SRV-%')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.service_case_detail(v_case);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-12 · El cliente ve la bitácora sin las notas internas, con el honorario','ok',coalesce((jsonb_array_length(v_x->'events') = 2 and (v_x->>'fee_amount')::numeric = 4500 and v_x->>'status_label' = 'Esperando documentos suyos'), false),'d',(v_x->>'events')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    v_x := public.service_case_detail(v_case);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-13 · SOFA ve la bitácora completa','ok',coalesce((jsonb_array_length(v_x->'events') = 3), false),'d',(jsonb_array_length(v_x->'events'))::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.service_case_cancel(v_case);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-14 · El cliente no cancela un caso que SOFA ya trabaja','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-14 · El cliente no cancela un caso que SOFA ya trabaja','ok',sqlerrm like 'SOFA ya está trabajando%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    perform public.service_case_update(v_case, 'cerrado', 'Códigos cargados');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-15 · Al cerrar el caso se completa su tarea','ok',coalesce(((select closed_at is not null from public.sofa_service_cases where id = v_case) and exists (select 1 from public.tasks t join public.sofa_service_cases c on c.task_id = t.id where c.id = v_case and t.status = 'completada')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    v_x := public.tariffs_expiring(60, v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-16 · «Renegociación de tarifarios» trae los datos para abrir el caso','ok',coalesce(((v_x->'tariffs'->0->>'provider_id')::uuid = v_prov and (v_x->'tariffs'->0->>'ars_id')::uuid = v_ars and v_x->'tariffs'->0->'case' = 'null'::jsonb), false),'d',(v_x->>'tariffs')::text));
    v_x := public.tariff_renewal_open_case(v_org, v_prov, v_ars, null);
    v_case2 := (v_x->>'id')::uuid;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-17 · Abre el caso de renegociación y lo repite si se pide otra vez','ok',coalesce((not (v_x->>'existing')::boolean and (public.tariff_renewal_open_case(v_org, v_prov, v_ars, null)->>'existing')::boolean and (public.tariffs_expiring(60, v_org)->'tariffs'->0->'case'->>'id')::uuid = v_case2), false),'d',(null)::text));
    v_x := public.service_cases_board();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-18 · El tablero de SOFA muestra los casos abiertos y su equipo','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'cases') c where (c->>'id')::uuid = v_case2) and not exists (select 1 from jsonb_array_elements(v_x->'cases') c where (c->>'id')::uuid = v_case) and jsonb_array_length(v_x->'staff') >= 2), false),'d',(jsonb_array_length(v_x->'cases'))::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.service_cases_board();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-19 · El Médico no ve el tablero de SOFA','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-19 · El Médico no ve el tablero de SOFA','ok',sqlerrm like 'Los casos de servicio son del equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CS-20 · Las tablas solo se usan por funciones (sin acceso directo)','ok',coalesce((not has_table_privilege('authenticated', 'public.sofa_service_cases', 'select') and not has_function_privilege('anon', 'public.client_account(uuid)', 'execute')), false),'d',(null)::text));

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

-- ===== Suite 131 corregida (conciliación bancaria: envíos con secuencia 1, 2 y 3) =====
-- 131 · Suite de la 130 (conciliación bancaria de los pagos de las ARS). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_conciliacion_bancaria();
create or replace function app.qa_run_tests_conciliacion_bancaria()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000003c1';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000003c1';
  v_adm constant text := 'a7000000-0000-4000-8000-0000000003c1'; v_glo constant text := 'a7000000-0000-4000-8000-0000000003c2';
  v_aud constant text := 'a7000000-0000-4000-8000-0000000003c3'; v_med constant text := 'a7000000-0000-4000-8000-0000000003c4';
  v_ars uuid; v_proc uuid; v_s1 uuid; v_s2 uuid; v_s3 uuid; v_p1 uuid; v_p2 uuid; v_p3 uuid; v_rows jsonb; v_m uuid; v_per date;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_adm::uuid,'qa.cb.adm@sofa.test','x'),(v_glo::uuid,'qa.cb.glo@sofa.test','x'),(v_aud::uuid,'qa.cb.aud@sofa.test','x'),(v_med::uuid,'qa.cb.med@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.cb.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA CB Consultorio', '00000000751', 'Médico independiente', 'activo', current_date - 90, '8095550751');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. CB', 'Cardiología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin'), ('00000000-0000-4000-8000-000000000001'::uuid, v_glo::uuid, 'glosas'), ('00000000-0000-4000-8000-000000000001'::uuid, v_aud::uuid, 'auditor');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_banco_uno', 'ARS QA Banco Uno', 'Contributivo', true) returning id into v_ars;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    v_per := date_trunc('month', current_date - 120)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_ars, v_per, 1, 'borrador', current_date - 60) returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_ars, v_per, 2, 'borrador', current_date - 100) returning id into v_s2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_ars, v_per, 3, 'borrador', current_date - 100) returning id into v_s3;
    -- amount es columna calculada en producción (quantity × unit_amount): no se inserta
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_s1, v_org, v_per + 3, 'Paciente CB 1', v_proc, 1, 10000), (v_s2, v_org, v_per + 4, 'Paciente CB 2', v_proc, 1, 5000), (v_s3, v_org, v_per + 5, 'Paciente CB 3', v_proc, 1, 5000);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_p1 := public.register_payment(v_org, v_ars, current_date - 10, 4000, 'transferencia', 'PAGO-QA-1', jsonb_build_array(jsonb_build_object('submission_id', v_s1, 'amount', 4000)));
    v_p3 := public.register_payment(v_org, v_ars, current_date - 20, 999, 'transferencia', 'PAGO-QA-3', jsonb_build_array(jsonb_build_object('submission_id', v_s1, 'amount', 999)));
    v_rows := jsonb_build_array(
      jsonb_build_object('fecha', to_char(current_date - 9, 'DD/MM/YYYY'), 'descripcion', 'TRANSF ARS QA BANCO UNO', 'referencia', 'TRX1', 'monto', '4,000.00'),
      jsonb_build_object('fecha', to_char(current_date - 5, 'DD/MM/YYYY'), 'descripcion', 'DEP ARS QA BANCO UNO LOTE', 'referencia', 'TRX2', 'credito', 'RD$ 2,500.00'),
      jsonb_build_object('fecha', to_char(current_date - 3, 'DD/MM/YYYY'), 'descripcion', 'PAGO PACIENTE JUAN', 'monto', '1500'),
      jsonb_build_object('fecha', to_char(current_date - 2, 'DD/MM/YYYY'), 'descripcion', 'COMISION', 'debito', '150'),
      jsonb_build_object('fecha', to_char(current_date - 9, 'DD/MM/YYYY'), 'descripcion', 'TRANSF ARS QA BANCO UNO', 'referencia', 'TRX1', 'monto', '4000'));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.bank_import(v_org, 'Banreservas', '1234', v_rows, false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-01 · El Médico no carga estados de cuenta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-01 · El Médico no carga estados de cuenta','ok',sqlerrm like 'La conciliación bancaria la hace el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_glo, 'role', 'authenticated')::text, true);
    v_x := public.bank_import(v_org, 'Banreservas', '1234', v_rows || jsonb_build_array(jsonb_build_object('fecha', 'ayer', 'monto', 'x')), false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-02 · Fila con fecha y monto inválidos: dice qué corregir','ok',coalesce((jsonb_array_length(v_x->'errors') = 1 and jsonb_array_length(v_x->'errors'->0->'errors') = 2), false),'d',(v_x->'errors')::text));
    v_x := public.bank_import(v_org, 'Banreservas', '1234', v_rows, false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-03 · Vista previa: 3 depósitos, 1 cargo omitido, 1 repetido; adivina la ARS','ok',coalesce(((v_x->>'deposits')::int = 3 and (v_x->>'withdrawals_skipped')::int = 1 and (v_x->>'duplicates')::int = 1 and exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'reference' = 'TRX2' and r->>'ars' = 'ARS QA Banco Uno')), false),'d',(v_x::text)::text));
    v_x := public.bank_import(v_org, 'Banreservas', '1234', v_rows, true, 'estado.csv');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-04 · Al cargar concilia solo el depósito que coincide con un pago','ok',coalesce(((v_x->>'auto_matched')::int = 1 and exists (select 1 from public.bank_movements where organization_id = v_org and reference = 'TRX1' and payment_id = v_p1 and match_method = 'auto')), false),'d',(v_x->>'auto_matched')::text));
    v_x := public.bank_import(v_org, 'Banreservas', '1234', v_rows, false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-05 · Cargar el mismo archivo otra vez no duplica','ok',coalesce(((v_x->>'deposits')::int = 0 and (v_x->>'duplicates')::int = 4), false),'d',(v_x::text)::text));
    select id into v_m from public.bank_movements where organization_id = v_org and reference = 'TRX2';
    begin
      perform public.bank_register_payment(v_m, v_ars, jsonb_build_array(jsonb_build_object('submission_id', v_s1, 'amount', 2500)));
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-06a · Glosas concilia pero no registra pagos de ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-06a · Glosas concilia pero no registra pagos de ARS','ok',sqlerrm like 'Registrar pagos de ARS es del Super Admin%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_p2 := public.bank_register_payment(v_m, v_ars, jsonb_build_array(jsonb_build_object('submission_id', v_s1, 'amount', 2500)));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-06 · Registra el pago desde el depósito y lo aplica a la radicación','ok',coalesce(((select amount from public.payments where id = v_p2) = 2500 and (select status = 'conciliado' and match_method = 'registrado' from public.bank_movements where id = v_m) and (select paid from public.v_submission_balance where id = v_s1) = 7499), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_glo, 'role', 'authenticated')::text, true);
    select id into v_m from public.bank_movements where organization_id = v_org and description = 'PAGO PACIENTE JUAN';
    begin
      perform public.bank_ignore(v_m, '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-07 · «No es de ARS» pide de dónde viene el depósito','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-07 · «No es de ARS» pide de dónde viene el depósito','ok',sqlerrm like 'Escriba de dónde viene%','d',left(sqlerrm,120)));
    end;
    perform public.bank_ignore(v_m, 'Pago de paciente privado');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-08 · Marca el depósito como «no es de ARS»','ok',coalesce(((select status from public.bank_movements where id = v_m) = 'no_ars'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_p2 := public.register_payment(v_org, v_ars, current_date - 1, 3000, 'transferencia', 'PAGO-QA-2', jsonb_build_array(jsonb_build_object('submission_id', v_s2, 'amount', 3000)));
    perform public.bank_import(v_org, 'Banreservas', '1234', jsonb_build_array(jsonb_build_object('fecha', to_char(current_date, 'DD/MM/YYYY'), 'descripcion', 'ARS QA BANCO UNO NETO', 'monto', '2700')), true);
    select id into v_m from public.bank_movements where organization_id = v_org and description = 'ARS QA BANCO UNO NETO';
    begin
      perform public.bank_match(v_m, v_p2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-09 · Si el monto no coincide exige la causa (retención, comisión)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-09 · Si el monto no coincide exige la causa (retención, comisión)','ok',sqlerrm like 'El depósito%no coinciden%','d',left(sqlerrm,120)));
    end;
    v_x := public.bank_match(v_m, v_p2, 'Retención del ISR 10%');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-10 · Concilia con la diferencia anotada','ok',coalesce(((v_x->>'difference')::numeric = -300), false),'d',(v_x::text)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_aud, 'role', 'authenticated')::text, true);
    v_x := public.bank_reconciliation(v_org, current_date - 90, current_date);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-11 · Tablero: pagos parciales y radicación sin pago vencida','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'partial') p where (p->>'id')::uuid = v_s1) and exists (select 1 from jsonb_array_elements(v_x->'unpaid_overdue') p where (p->>'id')::uuid = v_s3)), false),'d',(v_x->'unpaid_overdue')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-12 · Tablero: pago registrado que no aparece en el banco','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'payments_without_deposit') p where (p->>'id')::uuid = v_p3)), false),'d',(v_x->'payments_without_deposit')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-13 · Resumen: depósitos, conciliados y diferencia','ok',coalesce(((v_x->'summary'->>'deposits')::int = 4 and (v_x->'summary'->>'matched')::int = 3 and (v_x->'summary'->>'differences')::numeric = -300), false),'d',(v_x->>'summary')::text));
    begin
      perform public.bank_ignore(v_m, 'Prueba de auditor');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-14 · El Auditor solo consulta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-14 · El Auditor solo consulta','ok',sqlerrm like 'La conciliación bancaria la hace el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_glo, 'role', 'authenticated')::text, true);
    begin
      perform public.bank_unmatch(v_m);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-15 · Deshacer una conciliación es del Administrador','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-15 · Deshacer una conciliación es del Administrador','ok',sqlerrm like 'Solo el Super Admin o un Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform public.bank_unmatch(v_m);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-16 · El Administrador deshace la conciliación','ok',coalesce(((select status = 'sin_conciliar' and payment_id is null from public.bank_movements where id = v_m)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-17 · El resumen general muestra el depósito pendiente del cliente','ok',coalesce((exists (select 1 from jsonb_array_elements(public.bank_overview()) o where (o->>'organization_id')::uuid = v_org and (o->>'pending')::int = 1)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BK-18 · Lee montos dominicanos e internacionales','ok',coalesce((app.parse_amount_do('12.500,00') = 12500 and app.parse_amount_do('(1,200.00)') = -1200 and app.parse_amount_do('RD$ 3,450.50') = 3450.50), false),'d',(null)::text));

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
