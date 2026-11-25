-- Ya aplicado en producción (24/11/2026). Se guarda aquí como documentación.
-- 267 · Suite de la 266 (corregir una tarifa y recalcular las reclamaciones no radicadas). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_correccion_tarifa();
create or replace function app.qa_run_tests_correccion_tarifa()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_rl text;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_sa  constant uuid := '26600000-0000-4000-8000-000000000001';
  v_ad  constant uuid := '26600000-0000-4000-8000-000000000002';
  v_bil constant uuid := '26600000-0000-4000-8000-000000000003';
  v_med constant uuid := '26600000-0000-4000-8000-000000000004';
  v_org constant uuid := '26600000-0000-4000-8000-0000000000a1';
  v_prov constant uuid := '26600000-0000-4000-8000-0000000000b1';
  v_ars uuid; v_p1 uuid; v_p2 uuid; v_t uuid; v_t2 uuid; v_sub uuid; v_per date;
  v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid; v_l5 uuid; v_l6 uuid; v_f4 text;
  v_mig boolean; v_amt numeric; v_notes text; v_u1 numeric; v_a1 numeric; v_ok1 boolean; v_u2 numeric; v_a2 numeric; v_u3 numeric; v_ok3 boolean;
  v_u5 numeric; v_a5 numeric; v_u4 numeric; v_a4 numeric; v_a6 numeric; v_d2 text; v_d3 text; v_d5 text; v_dn int; v_h int; v_c int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    -- Lo que se espera de las tablas del sistema se calcula ANTES del primer cambio de rol
    v_mig := exists (select 1 from app.schema_migrations where version = '266');

    insert into auth.users (id, email, encrypted_password) values
      (v_sa,'qa.ct.sa@sofa.test','x'), (v_ad,'qa.ct.ad@sofa.test','x'), (v_bil,'qa.ct.bil@sofa.test','x'), (v_med,'qa.ct.med@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ct.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', v_sofa, 'QA CT Consultorio', '00000026601', 'Médico independiente', 'activo', current_date - 90, '8095552601');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_prov, v_org, 'Dr. CT QA', 'Cardiología', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      (v_sofa, v_sa, 'super_admin', true), (v_sofa, v_ad, 'admin', true), (v_sofa, v_bil, 'billing', true), (v_org, v_med, 'client', true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa266_ars', 'ARS QA Corrección Ficticia', 'Contributivo', true) returning id into v_ars;
    insert into public.procedures (internal_code, description, service_type_code, is_active)
    select 'QA266-P' || g, 'SERVICIO QA CORRECCION ' || g, (select service_type_code from public.procedures where is_active limit 1), true from generate_series(1, 2) g;
    select (a)[1], (a)[2] into v_p1, v_p2 from (select array_agg(id order by internal_code) a from public.procedures where internal_code like 'QA266-P%') y;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status, contract_ref)
    values (v_ars, v_org, v_prov, v_p1, 750, daterange(current_date - 400, null), 'vigente', 'QA-CT-1') returning id into v_t;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status, contract_ref)
    values (v_ars, v_org, v_prov, v_p2, 750, daterange(current_date - 400, null), 'vigente', 'QA-CT-2') returning id into v_t2;
    v_per := date_trunc('month', current_date)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_prov, v_ars, v_per, 1, 'borrador') returning id into v_sub;
    -- L1 alineada (750) · L2 monto propio (700) · L3 ya tiene el monto nuevo (850) · L4 radicada · L5 validada (750) · L6 otra tarifa
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_sub, v_org, current_date, 'Paciente CT Uno', '100260001', v_p1, 1, 750) returning id into v_l1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_sub, v_org, current_date, 'Paciente CT Dos', '100260002', v_p1, 1, 700) returning id into v_l2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_sub, v_org, current_date, 'Paciente CT Tres', '100260003', v_p1, 1, 850) returning id into v_l3;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_sub, v_org, current_date, 'Paciente CT Cuatro', '100260004', v_p1, 1, 750) returning id into v_l4;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_sub, v_org, current_date, 'Paciente CT Cinco', '100260005', v_p1, 1, 750) returning id into v_l5;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_sub, v_org, current_date, 'Paciente CT Seis', '100260006', v_p2, 1, 750) returning id into v_l6;
    perform set_config('app.claim_change', 'on', true);
    update public.service_lines set claim_status = 'radicada' where id = v_l4;
    update public.service_lines set claim_status = 'validada' where id = v_l5;
    perform set_config('app.claim_change', '', true);
    select claim_folio into v_f4 from public.service_lines where id = v_l4;

    v_rl := current_setting('role');
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · La migración 266 queda registrada','ok',coalesce(v_mig, false),'d',null));
    perform set_config('role', v_rl, true);

    -- ── Vista previa (Super Admin): no cambia nada ────────────────────────────────────────────────
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.tariff_correction_preview(v_t, 850);
    perform set_config('role', 'none', true);
    select amount into v_amt from public.tariffs where id = v_t;
    select unit_amount into v_u1 from public.service_lines where id = v_l1;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · La vista previa cuenta: 1 a realinear, 1 resuelta, 2 con decisión, 1 sin tocar (radicada)','ok',
      coalesce(((v_x->'counts'->>'total')::int = 5 and (v_x->'counts'->>'realinear')::int = 1 and (v_x->'counts'->>'resuelta')::int = 1
        and (v_x->'counts'->>'decision')::int = 2 and (v_x->'counts'->>'sin_tocar')::int = 1 and (v_x->>'valid')::boolean), false),'d',(v_x->'counts')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · La vista previa no cambia la tarifa ni las reclamaciones','ok',coalesce((v_amt = 750 and v_u1 = 750), false),'d',v_amt::text));

    perform set_config('role', 'authenticated', true);
    v_x := public.tariff_correction_preview(v_t, 750);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Con el mismo monto de hoy la vista previa dice que no es válido y por qué','ok',
      coalesce((not (v_x->>'valid')::boolean and (v_x->>'message') like 'Es el monto vigente%'), false),'d',(v_x->>'message')));

    -- ── Quién puede ───────────────────────────────────────────────────────────────────────────────
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_correct(v_t, 850, 'Corrección de prueba por Facturación', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Facturación no corrige tarifas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Facturación no corrige tarifas','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA corrigen tarifas%','d',left(sqlerrm,120)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_correction_preview(v_t, 850);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El Médico no ve ni corrige tarifas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El Médico no ve ni corrige tarifas','ok',sqlerrm like 'Solo el Super Admin o el Administrador de SOFA corrigen tarifas%','d',left(sqlerrm,120)));
    end;

    -- ── Validaciones de entrada ───────────────────────────────────────────────────────────────────
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_correct(v_t, 850, 'corto', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Sin motivo suficiente no se corrige','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Sin motivo suficiente no se corrige','ok',sqlerrm like 'Indique el motivo de la corrección%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_correct(v_t, 850.123, 'Monto con tres decimales, debe rechazarse', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · El monto lleva máximo dos decimales','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · El monto lleva máximo dos decimales','ok',sqlerrm like 'Indique un monto mayor que cero%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_correct(v_t, 850, 'Alcance distinto al de la vista previa', jsonb_build_object('old_amount', 750, 'total', 99));
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Si el alcance cambió desde la vista previa, no aplica','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Si el alcance cambió desde la vista previa, no aplica','ok',sqlerrm like 'El alcance cambió desde la vista previa%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    select amount into v_amt from public.tariffs where id = v_t;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Los rechazos no dejaron la tarifa a medias','ok',coalesce((v_amt = 750), false),'d',v_amt::text));

    -- ── Aplicar (Administrador) ───────────────────────────────────────────────────────────────────
    perform set_config('role', 'authenticated', true);
    v_x := public.tariff_correct(v_t, 850, 'El contrato dice 850; se cargó 750 por error', jsonb_build_object('old_amount', 750, 'total', 5));
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · Aplica: 1 realineada, 1 resuelta, 2 con decisión, 1 sin tocar, 0 omitidas','ok',
      coalesce(((v_x->>'realinear')::int = 1 and (v_x->>'resuelta')::int = 1 and (v_x->>'decision')::int = 2 and (v_x->>'sin_tocar')::int = 1 and (v_x->>'omitidas')::int = 0), false),'d',v_x::text));
    select amount, notes into v_amt, v_notes from public.tariffs where id = v_t;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · La tarifa queda en 850 y la nota dice qué cambió y por qué','ok',
      coalesce((v_amt = 850 and v_notes like '%750%850%El contrato dice 850%'), false),'d',v_notes));

    select unit_amount, tariff_amount, amount_ok into v_u1, v_a1, v_ok1 from public.service_lines where id = v_l1;
    select count(*) into v_dn from public.tariff_discrepancies where service_line_id = v_l1 and status = 'pendiente';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-13 · L1 (monto = tarifa vieja): pasa a 850, cuadra y no abre diferencia','ok',
      coalesce((v_u1 = 850 and v_a1 = 850 and v_ok1 and v_dn = 0), false),'d',format('unit %s tarifa %s ok %s dif %s', v_u1, v_a1, v_ok1, v_dn)));

    select unit_amount, tariff_amount, amount_ok into v_u3, v_a2, v_ok3 from public.service_lines where id = v_l3;
    select string_agg(status, ',' order by tariff_amount) into v_d3 from public.tariff_discrepancies where service_line_id = v_l3;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14 · L3 (ya registrada en 850): cuadra y su diferencia pendiente queda superada','ok',
      coalesce((v_u3 = 850 and v_a2 = 850 and v_ok3 and v_d3 = 'superada'), false),'d',v_d3));

    select unit_amount, tariff_amount into v_u2, v_a2 from public.service_lines where id = v_l2;
    select string_agg(status || ':' || trim_scale(tariff_amount)::text, ',' order by tariff_amount) into v_d2 from public.tariff_discrepancies where service_line_id = v_l2;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-15 · L2 (monto propio 700): conserva 700, la tarifa pasa a 850 y la diferencia nueva queda PENDIENTE','ok',
      coalesce((v_u2 = 700 and v_a2 = 850 and v_d2 = 'superada:750,pendiente:850'), false),'d',v_d2));

    select unit_amount, tariff_amount into v_u5, v_a5 from public.service_lines where id = v_l5;
    select string_agg(status || ':' || trim_scale(tariff_amount)::text, ',' order by tariff_amount) into v_d5 from public.tariff_discrepancies where service_line_id = v_l5;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-16 · L5 (validada): no cambia su monto; abre diferencia pendiente para que Facturación decida','ok',
      coalesce((v_u5 = 750 and v_a5 = 850 and v_d5 = 'pendiente:850'), false),'d',v_d5));

    select unit_amount, tariff_amount into v_u4, v_a4 from public.service_lines where id = v_l4;
    select count(*) into v_dn from public.tariff_discrepancies where service_line_id = v_l4;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-17 · L4 (radicada): no se toca; conserva su fotografía','ok',coalesce((v_u4 = 750 and v_a4 = 750 and v_dn = 0), false),'d',format('unit %s tarifa %s', v_u4, v_a4)));

    select tariff_amount into v_a6 from public.service_lines where id = v_l6;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-18 · Una reclamación de otra tarifa no se toca','ok',coalesce((v_a6 = 750), false),'d',v_a6::text));

    select count(*) into v_h from public.claim_status_history where service_line_id in (v_l1, v_l2, v_l3, v_l5) and comment like 'Tarifa corregida de 750 a 850%';
    select count(*) into v_c from public.claim_status_history where service_line_id = v_l4 and comment like 'Tarifa corregida%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-19 · Cada reclamación tocada deja nota en su historial; la radicada, ninguna','ok',coalesce((v_h = 4 and v_c = 0), false),'d',format('tocadas %s, radicada %s', v_h, v_c)));

    select count(*) into v_n from app.tariff_corrections where tariff_id = v_t and old_amount = 750 and new_amount = 850 and lines_total = 5 and lines_skipped = 0;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-20 · La corrección queda en la bitácora con sus cifras','ok',coalesce((v_n = 1), false),'d',null));

    -- La radicada sigue visible en «precio vencido» para que Facturación decida
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.tariff_stale_claims(v_org, v_ars, v_per, null, 'todas', 100);
    perform set_config('role', 'none', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-21 · La radicada aparece en «precio vencido» (cerrada, 750 vs 850)','ok',
      coalesce((exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'folio' = v_f4 and (r->>'closed')::boolean and (r->>'frozen_amount')::numeric = 750 and (r->>'current_amount')::numeric = 850)), false),'d',left((v_x->'total')::text, 40)));

    -- ── Mismo monto, y reversión ──────────────────────────────────────────────────────────────────
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.tariff_correct(v_t, 850, 'Repetir el mismo monto no tiene sentido', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-22 · Corregir al mismo monto vigente se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-22 · Corregir al mismo monto vigente se rechaza','ok',sqlerrm like 'El monto es igual al vigente%','d',left(sqlerrm,120)));
    end;
    v_x := public.tariff_correct(v_t, 750, 'Reversión de prueba de la corrección anterior', null);
    perform set_config('role', 'none', true);
    select amount into v_amt from public.tariffs where id = v_t;
    select unit_amount into v_u1 from public.service_lines where id = v_l1;
    select count(*) into v_n from app.tariff_corrections where tariff_id = v_t;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-23 · Revertir = corregir de vuelta: tarifa 750, L1 vuelve a 750, dos filas en la bitácora','ok',
      coalesce((v_amt = 750 and v_u1 = 750 and v_n = 2), false),'d',format('tarifa %s, L1 %s, bitácora %s', v_amt, v_u1, v_n)));

    -- ── Ataques y puertas cerradas ────────────────────────────────────────────────────────────────
    begin
      update public.tariffs set amount = 999 where id = v_t;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-24 · ATAQUE: el UPDATE directo del monto sigue bloqueado fuera de la función','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-24 · ATAQUE: el UPDATE directo del monto sigue bloqueado fuera de la función','ok',sqlerrm like 'Una tarifa no se modifica%','d',left(sqlerrm,120)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-25 · Funciones cerradas a anon; lo interno y la bitácora no se abren a authenticated','ok',
      coalesce((not has_function_privilege('anon','public.tariff_correct(uuid,numeric,text,jsonb)','execute')
        and not has_function_privilege('anon','public.tariff_correction_preview(uuid,numeric)','execute')
        and has_function_privilege('authenticated','public.tariff_correct(uuid,numeric,text,jsonb)','execute')
        and not has_function_privilege('authenticated','app.tariff_correct_core(uuid,numeric,text,jsonb)','execute')
        and not has_table_privilege('authenticated','app.tariff_corrections','select')), false),'d',null));

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;
revoke execute on function app.qa_run_tests_correccion_tarifa() from public, anon, authenticated;

delete from app.schema_migrations where version = '267';
insert into app.schema_migrations (version, report) values ('267', jsonb_build_object('iteracion', 'I90', 'tema', 'suite de la 266: corrección de tarifa con recálculo'));
