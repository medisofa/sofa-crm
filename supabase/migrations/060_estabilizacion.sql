-- ============================================================================
-- SOFA 1.7.7 · 060_estabilizacion.sql
-- Deja en verde la regresión SQL después de las decisiones del 01/10/2026 y de
-- las Iteraciones 12–17, sin cambiar ninguna regla de negocio de las suites:
--   1. app.qa_patch(): parcha una suite reemplazando un fragmento EXACTO. Si el
--      fragmento no está una sola vez, falla y dice qué hacer (nunca adivina).
--      Si el parche ya se aplicó, lo salta (idempotente).
--   2. Suites corregidas: los pasos que la decisión del 01/10/2026 reservó a la
--      Administración (radicar, factura fiscal, envío y pagos de las ARS) los hace
--      el usuario Admin de cada suite; las pruebas de bloqueo vuelven a fallar por
--      su propia regla; los clientes de prueba quedan sin obligación de e-CF.
--   3. public.remove_service_line(): quitar un servicio de un lote por función.
--   4. public.import_claims(): mensaje claro cuando la fila no trae servicio.
--   5. search_path fijo en las suites (aviso del asesor de seguridad).
-- Depende de: 058 (delete_submission) y 056 (import_claims).
-- ============================================================================

do $$
begin
  if not exists (select 1 from app.schema_migrations where version = '058') then
    raise exception 'Falta la migración 058_delete_submission.sql. Aplíquela primero y vuelva a correr la 060.';
  end if;
  if not exists (select 1 from app.schema_migrations where version = '056') then
    raise exception 'Falta la migración 056 (import_claims). Aplíquela primero y vuelva a correr la 060.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Parche exacto de suites
-- ---------------------------------------------------------------------------
create or replace function app.qa_patch(p_fn regprocedure, p_old text, p_new text)
returns text
language plpgsql
set search_path = ''
as $$
declare
  src text := pg_get_functiondef(p_fn);
  n_old int := (length(src) - length(replace(src, p_old, ''))) / greatest(length(p_old), 1);
  n_new int := (length(src) - length(replace(src, p_new, ''))) / greatest(length(p_new), 1);
begin
  -- Ya aplicado (también cuando el fragmento nuevo contiene al viejo, como en los parches que agregan líneas antes)
  if n_new >= 1 and (n_old = 0 or strpos(p_new, p_old) > 0) then
    return 'ya estaba';
  elsif n_old = 1 then
    execute replace(src, p_old, p_new);
    return 'aplicado';
  end if;
  raise exception 'No se pudo parchar %: el fragmento aparece % veces (debe aparecer 1). Revise que la suite sea la de su migración original: «%»',
    p_fn, n_old, left(p_old, 120);
end $$;
revoke all on function app.qa_patch(regprocedure, text, text) from public;

-- Los usuarios de prueba de cada suite
--   a0…01 Admin, a0…02 Facturación (qa_run_tests)   · a2… radicaciones · a3… finanzas
--   a1… crm · a4… tarifarios · a8… reclamaciones / expediente / postradicación / reinicio

-- ---------------------------------------------------------------------------
-- 2a. qa_run_tests (base)
-- ---------------------------------------------------------------------------
select app.qa_patch('app.qa_run_tests()',
$o$    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values ('d0000000-0000-4000-8000-00000000000a'$o$,
$n$    -- 060: desde la Iteración 12 la reclamación exige contrato Médico × ARS vigente
    perform public.create_contract_tariff('c0000000-0000-4000-8000-00000000000a', (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P02'), 1500, date_trunc('month', current_date)::date - 100, null, 'CT-QA-BASE');
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount) values ('d0000000-0000-4000-8000-00000000000a'$n$);

select app.qa_patch('app.qa_run_tests()',
$o$where l.submission_id = 'd0000000-0000-4000-8000-00000000000a';$o$,
$n$where l.submission_id = 'd0000000-0000-4000-8000-00000000000a';
    -- 060: la factura fiscal del lote la registra la Administración (decisión 01/10/2026)
    perform set_config('request.jwt.claims', json_build_object('sub','a0000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    update public.submissions set fiscal_invoice_number = 'F-B0100000125', fiscal_amount = 3000, accountant_name = 'Lic. QA' where id = 'd0000000-0000-4000-8000-00000000000a';
    perform set_config('request.jwt.claims', json_build_object('sub','a0000000-0000-4000-8000-000000000002','role','authenticated')::text, true);$n$);

select app.qa_patch('app.qa_run_tests()',
$o$    perform public.change_submission_status('d0000000-0000-4000-8000-00000000000a', 'radicada', null, null, current_date, 'R-QA-001');$o$,
$n$    -- 060: radicar y registrar pagos de las ARS es de la Administración (decisión 01/10/2026)
    perform set_config('request.jwt.claims', json_build_object('sub','a0000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform public.change_submission_status('d0000000-0000-4000-8000-00000000000a', 'radicada', null, null, current_date, 'R-QA-001');$n$);

select app.qa_patch('app.qa_run_tests()',
$o$    select coalesce(((select count(*) = 0 from public.sofa_fees)$o$,
$n$    perform set_config('request.jwt.claims', json_build_object('sub','a0000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    select coalesce(((select count(*) = 0 from public.sofa_fees)$n$);

-- La prueba de "cambio de estado directo" la hace el Admin, para que falle por su propia regla
select app.qa_patch('app.qa_run_tests()',
$o$      execute $q$update public.submissions set status = 'radicada' where id = 'd0000000-0000-4000-8000-00000000000a'$q$;$o$,
$n$      perform set_config('request.jwt.claims', json_build_object('sub','a0000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
      execute $q$update public.submissions set status = 'radicada' where id = 'd0000000-0000-4000-8000-00000000000a'$q$;$n$);

select app.qa_patch('app.qa_run_tests()',
$o$'Cambio de estado directo (sin la función) se bloquea','ok',true,'d','Bloqueado: ' || left(sqlerrm, 110)));
    end;$o$,
$n$'Cambio de estado directo (sin la función) se bloquea','ok',true,'d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub','a0000000-0000-4000-8000-000000000002','role','authenticated')::text, true);$n$);

-- La tarifa general se cuenta sin las contractuales (Iteración 12 las guarda en la misma tabla)
select app.qa_patch('app.qa_run_tests()',
$o$(select count(*) = 2 from public.tariffs where procedure_id = (select id from public.procedures where internal_code='SOFA-P02') and ars_id = (select id from public.ars where code='humano'))$o$,
$n$(select count(*) = 1 from public.tariffs where procedure_id = (select id from public.procedures where internal_code='SOFA-P02') and ars_id = (select id from public.ars where code='humano') and provider_id is null and organization_id is null and plan_id is null and amount = 1700 and lower(valid_during) = current_date + 1) and (select count(*) = 0 from public.tariffs where procedure_id = (select id from public.procedures where internal_code='SOFA-P02') and ars_id = (select id from public.ars where code='humano') and provider_id is null and organization_id is null and plan_id is null and amount <> 1700 and valid_during @> (current_date + 1))$n$);

-- ---------------------------------------------------------------------------
-- 2b. qa_run_tests_radicaciones
-- ---------------------------------------------------------------------------
-- Contrato Médico × ARS antes de cargar (Iteración 12)
select app.qa_patch('app.qa_run_tests_radicaciones()',
$o$    v_imp := public.import_service_lines(v_s1, jsonb_build_array($o$,
$n$    -- 060: desde la Iteración 12 la reclamación exige contrato Médico × ARS vigente
    perform public.create_contract_tariff('c2000000-0000-4000-8000-00000000000a', (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P02'), 1500, date_trunc('month', current_date)::date - 100, null, 'CT-QA-RAD');
    perform public.create_contract_tariff('c2000000-0000-4000-8000-00000000000a', (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), 900, date_trunc('month', current_date)::date - 100, null, 'CT-QA-RAD');
    v_imp := public.import_service_lines(v_s1, jsonb_build_array($n$);

-- La validación creció de 10 a 13 reglas (e-CF, factura fiscal, auditoría): se exige al menos 10
select app.qa_patch('app.qa_run_tests_radicaciones()',
$o$jsonb_array_length(public.validate_submission(v_s1, false)->'items') = 10 and$o$,
$n$jsonb_array_length(public.validate_submission(v_s1, false)->'items') >= 10 and$n$);
select app.qa_patch('app.qa_run_tests_radicaciones()',
$o$'Validación sin guardar devuelve 10 reglas y no pasa (faltan documentos)'$o$,
$n$'Validación sin guardar devuelve sus reglas y no pasa (faltan documentos)'$n$);

-- Factura fiscal y radicación por la Administración (decisión 01/10/2026)
select app.qa_patch('app.qa_run_tests_radicaciones()',
$o$    perform public.change_submission_status(v_s1, 'lista_para_radicar');$o$,
$n$    perform set_config('request.jwt.claims', json_build_object('sub','a2000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    update public.submissions set fiscal_invoice_number = 'F-B0100000777', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_s1), accountant_name = 'Lic. QA' where id = v_s1;
    perform set_config('request.jwt.claims', json_build_object('sub','a2000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    perform public.change_submission_status(v_s1, 'lista_para_radicar');$n$);
select app.qa_patch('app.qa_run_tests_radicaciones()',
$o$    perform public.change_submission_status(v_s1, 'radicada', null, null, current_date, 'R-QA-500');$o$,
$n$    perform set_config('request.jwt.claims', json_build_object('sub','a2000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform public.change_submission_status(v_s1, 'radicada', null, null, current_date, 'R-QA-500');
    perform set_config('request.jwt.claims', json_build_object('sub','a2000000-0000-4000-8000-000000000002','role','authenticated')::text, true);$n$);

-- ---------------------------------------------------------------------------
-- 2c. qa_run_tests_crm · el pipeline real usa "Contratado" al convertir (Iteración 16)
-- ---------------------------------------------------------------------------
select app.qa_patch('app.qa_run_tests_crm()',
$o$    select coalesce((select stage = 'cliente' and probability = 100 and organization_id = v_org from public.opportunities where id = v_opp), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','Oportunidad queda como Cliente (100%) enlazada','ok',v_ok));$o$,
$n$    select coalesce((select stage = 'contratado' and organization_id = v_org from public.opportunities where id = v_opp), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','Oportunidad queda en Contratado y enlazada al cliente','ok',v_ok));$n$);
-- "Convertir dos veces" vuelve a fallar por su propia regla (antes fallaba por "Oportunidad no encontrada")
select app.qa_patch('app.qa_run_tests_crm()',
$o$(select id from public.opportunities where stage = 'cliente' order by updated_at desc limit 1)$o$,
$n$(select id from public.opportunities where stage = 'contratado' and organization_id is not null order by updated_at desc limit 1)$n$);

-- ---------------------------------------------------------------------------
-- 2d. qa_run_tests_tarifarios · la brecha se prueba con datos propios de la suite
--     (antes dependía del tarifario de ejemplo SOFA-P04, que el reinicio de datos puede borrar)
-- ---------------------------------------------------------------------------
select app.qa_patch('app.qa_run_tests_tarifarios()',
$o$    select coalesce((select gap_pct = 44.2 and lowest_ars = 'ARS Humano' from public.v_tariff_gaps where internal_code = 'SOFA-P04'), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','Brechas: la interconsulta paga 44.2% más en SENASA que en Humano','ok',v_ok,'d',null));$o$,
$n$    perform set_config('request.jwt.claims', json_build_object('sub','a4000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    insert into public.procedures (internal_code, description, service_type_code, family) values ('QA-BRECHA-01', 'QA INTERCONSULTA BRECHA', 'consulta', 'Medicina y hospitalización');
    perform public.create_tariff((select id from public.procedures where internal_code='QA-BRECHA-01'), (select id from public.ars where code='humano'), 1000, current_date);
    perform public.create_tariff((select id from public.procedures where internal_code='QA-BRECHA-01'), (select id from public.ars where code='senasa_contributivo'), 1442, current_date);
    select coalesce((select gap_pct = 44.2 and lowest_ars = 'ARS Humano' and highest_ars = (select name from public.ars where code='senasa_contributivo') from public.v_tariff_gaps where internal_code = 'QA-BRECHA-01'), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','Brechas: el mismo servicio paga 44.2% más en SENASA que en Humano','ok',v_ok,'d',null));$n$);

-- ---------------------------------------------------------------------------
-- 2e. qa_run_tests_reinicio · el reporte de roles se revisa sin depender de los usuarios reales
--     (en producción hay un Super Admin y una secretaria reales además de los de la suite)
-- ---------------------------------------------------------------------------
select app.qa_patch('app.qa_run_tests_reinicio()',
$o$(v_js->'secretaria_sin_medicos'->>'n')::int = 1 and$o$,
$n$(v_js->'secretaria_sin_medicos'->>'n')::int >= 1 and$n$);
select app.qa_patch('app.qa_run_tests_reinicio()',
$o$    select coalesce((select (v_js->'super_admin'->>'n')::int = 1 and v_js->'super_admin'->>'sev' = 'ok'), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','Super Admin: hay 1 (correcto)','ok',v_ok,'d',null));$o$,
$n$    select coalesce((select (v_js->'super_admin'->>'n')::int between 1 and 2 and v_js->'super_admin'->>'sev' = 'ok' and (v_js->'super_admin'->'users')::text like '%super@qa.test%'), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','Super Admin: 1 o 2 activos se marca como correcto','ok',v_ok,'d',null));$n$);

-- ---------------------------------------------------------------------------
-- 2f. qa_run_tests_finanzas · los pagos de las ARS los registra la Administración
-- ---------------------------------------------------------------------------
select app.qa_patch('app.qa_run_tests_finanzas()',
$o$-- ===== 2. Pagos y honorarios =====
    perform set_config('request.jwt.claims', json_build_object('sub','a3000000-0000-4000-8000-000000000002'$o$,
$n$-- ===== 2. Pagos y honorarios =====
    -- 060: los pagos de las ARS los registra la Administración (decisión 01/10/2026)
    perform set_config('request.jwt.claims', json_build_object('sub','a3000000-0000-4000-8000-000000000001'$n$);
-- Que Facturación no vea el honorario del pago se sigue comprobando con el usuario de Facturación
select app.qa_patch('app.qa_run_tests_finanzas()',
$o$    select coalesce((select allocated = 1200 and allocations = 1 and folios like 'RAD-%' and sofa_fee is null from public.v_payments where id = v_p), false) into v_ok;$o$,
$n$    perform set_config('request.jwt.claims', json_build_object('sub','a3000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    select coalesce((select allocated = 1200 and allocations = 1 and folios like 'RAD-%' and sofa_fee is null from public.v_payments where id = v_p), false) into v_ok;
    perform set_config('request.jwt.claims', json_build_object('sub','a3000000-0000-4000-8000-000000000001','role','authenticated')::text, true);$n$);
select app.qa_patch('app.qa_run_tests_finanzas()',
$o$    select coalesce((select count(*) = 0 from public.sofa_fees), false) into v_ok;$o$,
$n$    perform set_config('request.jwt.claims', json_build_object('sub','a3000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    select coalesce((select count(*) = 0 from public.sofa_fees), false) into v_ok;$n$);
select app.qa_patch('app.qa_run_tests_finanzas()',
$o$    perform public.register_payment('b3000000-0000-4000-8000-00000000000a', (select id from public.ars where code='humano'), current_date, 800, 'cheque'$o$,
$n$    perform set_config('request.jwt.claims', json_build_object('sub','a3000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform public.register_payment('b3000000-0000-4000-8000-00000000000a', (select id from public.ars where code='humano'), current_date, 800, 'cheque'$n$);

-- ---------------------------------------------------------------------------
-- 2g. qa_run_tests_reclamaciones · factura fiscal, radicación y pagos por la Administración
-- ---------------------------------------------------------------------------
select app.qa_patch('app.qa_run_tests_reclamaciones()',
$o$    update public.submissions set fiscal_invoice_number = 'F-900', fiscal_amount = 3900, accountant_name = 'Lic. Contador QA', fiscal_requested_on = current_date, fiscal_received_on = current_date where id = v_s;$o$,
$n$    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    update public.submissions set fiscal_invoice_number = 'F-900', fiscal_amount = 3900, accountant_name = 'Lic. Contador QA', fiscal_requested_on = current_date, fiscal_received_on = current_date where id = v_s;
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000002','role','authenticated')::text, true);$n$);
-- "Radicar con diferencia fiscal" lo intenta el Admin, para que falle por la diferencia y no por el rol
select app.qa_patch('app.qa_run_tests_reclamaciones()',
$o$      execute $q$select public.change_submission_status((select id from public.submissions where ncf = 'B0100000900'), 'radicada', null, null, current_date, 'R-FIS-1')$q$;$o$,
$n$      perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
      execute $q$select public.change_submission_status((select id from public.submissions where ncf = 'B0100000900'), 'radicada', null, null, current_date, 'R-FIS-1')$q$;$n$);
select app.qa_patch('app.qa_run_tests_reclamaciones()',
$o$'D2 · Radicar con diferencia fiscal se bloquea','ok',true,'d','Bloqueado: ' || left(sqlerrm, 110)));
    end;$o$,
$n$'D2 · Radicar con diferencia fiscal se bloquea','ok',true,'d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000002','role','authenticated')::text, true);$n$);
select app.qa_patch('app.qa_run_tests_reclamaciones()',
$o$json_build_object('sub','a8000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.change_submission_status(v_s, 'radicada', null, null, current_date, 'R-FIS-1', 'plataforma', 'LOTE-77');$o$,
$n$json_build_object('sub','a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.change_submission_status(v_s, 'radicada', null, null, current_date, 'R-FIS-1', 'plataforma', 'LOTE-77');$n$);
select app.qa_patch('app.qa_run_tests_reclamaciones()',
$o$json_build_object('sub','a8000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_p := public.register_payment($o$,
$n$json_build_object('sub','a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_p := public.register_payment($n$);

-- ---------------------------------------------------------------------------
-- 2h. qa_run_tests_expediente · el bloque final (envío y radicación) lo hace la Administración;
--     "los datos de envío no se editan directamente" vuelve a fallar por su propia regla
-- ---------------------------------------------------------------------------
select app.qa_patch('app.qa_run_tests_expediente()',
$o$'a8000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      execute $q$update public.submissions set sent_via = 'Otro'$o$,
$n$'a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      execute $q$update public.submissions set sent_via = 'Otro'$n$);

-- ---------------------------------------------------------------------------
-- 2i. qa_run_tests_postradicacion · radicación y pagos por la Administración
-- ---------------------------------------------------------------------------
select app.qa_patch('app.qa_run_tests_postradicacion()',
$o$'a8000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.change_submission_status(v_lote, 'radicada'$o$,
$n$'a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.change_submission_status(v_lote, 'radicada'$n$);
select app.qa_patch('app.qa_run_tests_postradicacion()',
$o$'a8000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.change_submission_status(v_new, 'radicada'$o$,
$n$'a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.change_submission_status(v_new, 'radicada'$n$);
select app.qa_patch('app.qa_run_tests_postradicacion()',
$o$    v_pay := public.register_payment($o$,
$n$    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    v_pay := public.register_payment($n$);

-- ---------------------------------------------------------------------------
-- 3. Trabajo de hoy: se recupera la alerta "Facturas SOFA sin NCF" (Iteración 14).
--    Una migración posterior reemplazó work_queue() sin este bloque; la pantalla
--    Trabajo de hoy todavía tiene su etiqueta (today.js: sofa_ncf).
--    Aviso a los 2 días de emitida la factura sin el NCF del sistema fiscal externo.
-- ---------------------------------------------------------------------------
select app.qa_patch('public.work_queue()',
$o$  union all
  select 'factura_sofa',$o$,
$n$  union all
  -- 060: Factura SOFA emitida sin el NCF del sistema fiscal externo
  select 'sofa_ncf', 'media', 'Factura ' || i.folio || ' · ' || i.client_name,
         'Emitida el ' || to_char(i.issued_on, 'DD/MM/YYYY') || ' sin NCF: registre el comprobante emitido en el sistema fiscal',
         i.issued_on, 'sofa_invoice', i.id, i.organization_id, i.client_name, i.total, false
    from public.v_sofa_invoices i where i.ncf is null and i.status <> 'anulada' and i.issued_on <= current_date - 2
  union all
  select 'factura_sofa',$n$);

-- ---------------------------------------------------------------------------
-- 2j. Clientes de prueba sin obligación de e-CF (regla de las pruebas en CLAUDE.md).
--     Sin esto, desde el 15/11/2026 (fecha general de e-CF) las suites que radican
--     fallarían por la fecha y no por su regla.
-- ---------------------------------------------------------------------------
do $$
declare s text;
begin
  foreach s in array array['app.qa_run_tests()', 'app.qa_run_tests_radicaciones()', 'app.qa_run_tests_reclamaciones()',
                           'app.qa_run_tests_expediente()', 'app.qa_run_tests_postradicacion()', 'app.qa_run_tests_reinicio()',
                           'app.qa_run_tests_glosas_normativa()', 'app.qa_run_tests_finanzas()', 'app.qa_run_tests_bi()'] loop
    perform app.qa_patch(s::regprocedure,
$o$    insert into public.providers (id, organization_id, full_name) values ($o$,
$n$    -- 060: clientes de prueba sin obligación de e-CF
    update public.organizations set ecf_required_from = date '2099-12-31' where kind = 'client' and ecf_required_from is distinct from date '2099-12-31';
    insert into public.providers (id, organization_id, full_name) values ($n$);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 4. public.remove_service_line · quitar una reclamación de un lote por función
--    (el frontend dejaba de usar delete directo sobre service_lines)
-- ---------------------------------------------------------------------------
create or replace function public.remove_service_line(p_line uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare l public.service_lines; s public.submissions; v_role text; v_files jsonb; v_n int;
begin
  select * into l from public.service_lines where id = p_line for update;
  if not found then raise exception 'Reclamación no encontrada: puede que otra persona ya la haya quitado. Recargue la radicación.' using errcode = 'P0002'; end if;
  select * into s from public.submissions where id = l.submission_id;
  v_role := app.claim_access_role(s.organization_id, s.provider_id);
  if coalesce(v_role, '') not in ('super_admin','admin','billing','assistant','client') then
    raise exception 'Su rol no quita reclamaciones de un lote. Pida a Facturación o a la Administración de SOFA que la quite.' using errcode = '42501';
  end if;
  if not app.is_editable_status(s.status) then
    raise exception 'El lote % ya fue radicado (estado: %): sus reclamaciones no se quitan. Si la ARS la devolvió, use "Reenviar en radicación complementaria".', s.folio, replace(s.status, '_', ' ') using errcode = '23514';
  end if;
  if exists (select 1 from public.payment_line_allocations where service_line_id = l.id) then
    raise exception 'La reclamación % tiene pagos registrados: no se quita.', l.claim_folio using errcode = '23514';
  end if;
  if exists (select 1 from public.glosa_items where service_line_id = l.id) then
    raise exception 'La reclamación % tiene glosas registradas: no se quita.', l.claim_folio using errcode = '23514';
  end if;
  if exists (select 1 from public.claim_resubmissions where service_line_id = l.id) then
    raise exception 'La reclamación % está ligada a un reenvío: no se quita (se perdería su historial).', l.claim_folio using errcode = '23514';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 10 then
    raise exception 'Indique el motivo para quitar la reclamación (mínimo 10 caracteres)' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('bucket', d.bucket, 'path', d.storage_path)), '[]'::jsonb), count(*)
    into v_files, v_n
    from public.documents d where d.entity_type = 'service_line' and d.service_line_id = l.id;
  insert into public.activities (operator_id, organization_id, entity_type, entity_id, activity_type, body)
  select o.operator_id, s.organization_id, 'organization', s.organization_id, 'sistema',
         'Reclamación ' || l.claim_folio || ' (' || coalesce(l.patient_name, 'sin paciente') || ', ' || to_char(l.service_date, 'DD/MM/YYYY')
         || ') quitada del lote ' || s.folio || ' · ' || trim(p_reason)
    from public.organizations o where o.id = s.organization_id;
  -- Primero los documentos (si no, quedarían huérfanos con service_line_id nulo) y después la reclamación.
  -- El disparador app.guard_service_line() sigue validando el estado de la reclamación y el acceso del usuario.
  delete from public.documents where entity_type = 'service_line' and service_line_id = l.id;
  delete from public.service_lines where id = l.id;
  return jsonb_build_object('folio', l.claim_folio, 'submission_folio', s.folio, 'documents', v_n, 'files', v_files);
end $$;
revoke all on function public.remove_service_line(uuid, text) from public, anon;
grant execute on function public.remove_service_line(uuid, text) to authenticated;
comment on function public.remove_service_line(uuid, text) is
  '1.7.7 · Quita una reclamación de un lote no radicado, con sus documentos; deja la actividad en el cliente y devuelve los archivos a borrar de Storage.';

-- ---------------------------------------------------------------------------
-- 5. public.import_claims · mensaje claro cuando la fila no trae servicio
--    (antes: "Servicio no encontrado (…): " sin decir qué faltaba)
-- ---------------------------------------------------------------------------
select app.qa_patch('public.import_claims(jsonb, boolean)',
$o$    if v_proc is null then v_msgs := array_append(v_msgs, (('Servicio no encontrado (código interno, nombre, SIMON o CUPS): ' || coalesce(nullif(v_txt, ''), e->>'simon', e->>'cups', '—')))::text); end if;$o$,
$n$    if v_proc is null then
      if coalesce(nullif(v_txt, ''), nullif(trim(coalesce(e->>'simon', '')), ''), nullif(trim(coalesce(e->>'cups', '')), '')) is null then
        v_msgs := array_append(v_msgs, 'Falta el servicio: indique el código interno, el nombre, el SIMON o el CUPS'::text);
      else
        v_msgs := array_append(v_msgs, (('Servicio no encontrado (código interno, nombre, SIMON o CUPS): ' || coalesce(nullif(v_txt, ''), nullif(trim(coalesce(e->>'simon', '')), ''), nullif(trim(coalesce(e->>'cups', '')), ''))))::text);
      end if;
    end if;$n$);

-- ---------------------------------------------------------------------------
-- 6. search_path fijo en las suites (aviso "Function Search Path Mutable" del asesor).
--    Las suites usan nombres calificados (public., app., auth.).
-- ---------------------------------------------------------------------------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname like 'qa\_run\_tests%' and p.proconfig is null loop
    execute format('alter function %s set search_path = %L', f, '');
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Registro
-- ---------------------------------------------------------------------------
insert into app.schema_migrations (version) values ('060') on conflict (version) do nothing;
