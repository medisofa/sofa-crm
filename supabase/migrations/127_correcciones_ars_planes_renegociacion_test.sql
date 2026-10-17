-- 127 · Suite de la 126 (usuarios de Auth, ARS y planes, tarifa por plan y renegociación). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_correcciones_261();
create or replace function app.qa_run_tests_correcciones_261()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000003a1';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000003a1';
  v_sa constant text := 'a7000000-0000-4000-8000-0000000003a1'; v_adm constant text := 'a7000000-0000-4000-8000-0000000003a2';
  v_med constant text := 'a7000000-0000-4000-8000-0000000003a3'; v_sec constant text := 'a7000000-0000-4000-8000-0000000003a4';
  v_bad constant uuid := 'a7000000-0000-4000-8000-0000000003a5';
  v_pat uuid; v_pat2 uuid; v_ars uuid; v_ars2 uuid; v_pl1 uuid; v_plx uuid; v_p1 uuid; v_p2 uuid; v_c2 text; v_sub uuid; v_line uuid; v_line2 uuid; v_cnt int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.c1.sa@sofa.test','x'),(v_adm::uuid,'qa.c1.adm@sofa.test','x'),(v_med::uuid,'qa.c1.med@sofa.test','x'),(v_sec::uuid,'qa.c1.sec@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.c1.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA C1 Consultorio', '00000000731', 'Médico independiente', 'activo', current_date - 90, '8095550731');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. C1', 'Medicina Interna');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin'), ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin');
    insert into public.patients (organization_id, full_name, doc_number) values (v_org, 'Paciente C1 Uno', '40200000731') returning id into v_pat;
    insert into public.patients (organization_id, full_name, doc_number) values (v_org, 'Paciente C1 Dos', '40200000732') returning id into v_pat2;
    select id into v_p1 from public.procedures where is_active and internal_code is not null order by internal_code limit 1;
    select id, internal_code into v_p2, v_c2 from public.procedures where is_active and internal_code is not null and id <> v_p1 order by internal_code limit 1;
    -- Usuario creado por SQL a la antigua (campos de Auth en blanco y sin identidad)
    insert into auth.users (id, email, encrypted_password) values (v_bad, 'qa.c1.roto@sofa.test', 'x');
    update auth.users set confirmation_token = null, recovery_token = null where id = v_bad;
    insert into public.profiles (id, full_name) values (v_bad, 'QA roto') on conflict (id) do nothing;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    v_x := public.auth_users_health();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-01 · La revisión detecta un usuario creado por SQL (sin identidad ni campos de acceso)','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x) e where e->>'email' = 'qa.c1.roto@sofa.test' and jsonb_array_length(e->'problems') >= 2)), false),'d',(v_x::text)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.auth_users_health();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-02 · El Médico no puede revisar las cuentas de acceso','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-02 · El Médico no puede revisar las cuentas de acceso','ok',sqlerrm like 'Solo el Super Admin%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.ars_save(null, 'QA ARS Prohibida', null, 'Contributivo');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','ARS-01 · El Médico no edita ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','ARS-01 · El Médico no edita ARS','ok',sqlerrm like 'Solo el Super Admin o un Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_ars := public.ars_save(null, 'QA ARS Planes C1', null, 'Contributivo', 'Portal PSS', 'Prueba', true);
    v_ars2 := public.ars_save(null, 'QA ARS Dos C1', null, 'Contributivo', null, null, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','ARS-02 · El Administrador crea una ARS (código automático)','ok',coalesce(((select code from public.ars where id = v_ars) = 'qa_ars_planes_c1'), false),'d',((select code from public.ars where id = v_ars))::text));
    perform public.ars_save(v_ars, 'QA ARS Planes C1', null, 'Contributivo', 'Física + portal PSS', 'Editada', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','ARS-03 · Edita el canal y las notas de la ARS','ok',coalesce(((select submission_channel || '/' || notes from public.ars where id = v_ars) = 'Física + portal PSS/Editada'), false),'d',(null)::text));
    begin
      perform public.ars_save(null, 'qa ars planes c1');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','ARS-04 · No permite dos ARS con el mismo nombre','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','ARS-04 · No permite dos ARS con el mismo nombre','ok',sqlerrm like 'Ya existe una ARS%','d',left(sqlerrm,120)));
    end;
    v_pl1 := public.ars_plan_save(null, v_ars, 'QA Royal', 'Complementario', null, true, 20);
    v_plx := public.ars_plan_save(null, v_ars2, 'QA Otro Plan', 'Complementario');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-01 · Agrega planes a la ARS','ok',coalesce((v_pl1 is not null and v_plx is not null), false),'d',(null)::text));
    begin
      perform public.ars_plan_save(null, v_ars, 'qa royal');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-02 · No repite el nombre de un plan en la misma ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-02 · No repite el nombre de un plan en la misma ARS','ok',sqlerrm like 'Esa ARS ya tiene un plan%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.ars_plan_save(null, v_ars, 'QA Malo', 'Oro');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-03 · Tipo de plan no válido: dice cuáles se aceptan','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-03 · Tipo de plan no válido: dice cuáles se aceptan','ok',sqlerrm like 'Tipo de plan no válido%','d',left(sqlerrm,120)));
    end;
    v_x := public.ars_catalog(true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-04 · El catálogo trae la ARS con su plan','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x) a, jsonb_array_elements(a->'plans') p where a->>'name' = 'QA ARS Planes C1' and p->>'name' = 'QA Royal')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PL-05 · Todas las ARS tienen precargado el Plan Básico (PDSS)','ok',coalesce((not exists (select 1 from public.ars a where a.code not like 'qa\_%' and coalesce(a.regime_default, 'Contributivo') in ('Contributivo','Subsidiado','Pensionados','Plan voluntario') and not exists (select 1 from public.ars_plans p where p.ars_id = a.id and p.name = 'Plan Básico de Salud (PDSS)'))), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.set_patient_plan(v_pat, v_ars, v_plx);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PT-01 · Plan de otra ARS en el paciente: dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PT-01 · Plan de otra ARS en el paciente: dice qué hacer','ok',sqlerrm like 'El plan elegido no pertenece%','d',left(sqlerrm,120)));
    end;
    v_x := public.set_patient_plan(v_pat, v_ars, v_pl1);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PT-02 · El Médico guarda la ARS y el plan del paciente','ok',coalesce((v_x->>'plan' = 'QA Royal'), false),'d',(v_x::text)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PT-03 · La Secretaria ve el plan del paciente','ok',coalesce((public.patient_plan(v_pat)->>'plan' = 'QA Royal'), false),'d',(null)::text));
    perform public.set_patient_plan(v_pat2, v_ars, null);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform public.create_contract_tariff_plan(v_prov, v_ars, null, v_p1, 1000, current_date - 10);
    perform public.create_contract_tariff_plan(v_prov, v_ars, v_pl1, v_p1, 1500, current_date - 10);
    begin
      perform public.create_contract_tariff_plan(v_prov, v_ars, v_plx, v_p1, 900, current_date - 10);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TP-01 · Tarifa con un plan de otra ARS: no se guarda','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','TP-01 · Tarifa con un plan de otra ARS: no se guarda','ok',sqlerrm like 'El plan no pertenece%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.submissions (organization_id, provider_id, ars_id, period) values (v_org, v_prov, v_ars, date_trunc('month', current_date)::date) returning id into v_sub;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, patient_id)
    values (v_sub, v_org, current_date, 'Paciente C1 Uno', v_p1, v_pat) returning id into v_line;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, patient_id)
    values (v_sub, v_org, current_date, 'Paciente C1 Dos', v_p1, v_pat2) returning id into v_line2;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TP-02 · La reclamación toma el plan del paciente y su tarifa (1,500)','ok',coalesce(((select plan_id = v_pl1 and tariff_amount = 1500 and contracted from public.service_lines where id = v_line)), false),'d',((select coalesce(plan_id::text,'-') || ' ' || coalesce(tariff_amount::text,'-') from public.service_lines where id = v_line))::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TP-03 · Sin plan usa la tarifa general del médico (1,000)','ok',coalesce(((select plan_id is null and tariff_amount = 1000 from public.service_lines where id = v_line2)), false),'d',((select coalesce(tariff_amount::text,'-') from public.service_lines where id = v_line2))::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TP-04 · El guardián de reclamaciones quedó ajustado al plan','ok',coalesce((position('coalesce(new.plan_id, s.plan_id)' in pg_get_functiondef('app.guard_service_line()'::regprocedure)) > 0), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.import_contract_tariffs_v2(jsonb_build_array(jsonb_build_object('medico', v_prov::text, 'ars', v_ars::text, 'plan', 'QA Royal', 'servicio', v_c2,
             'tarifa', '800', 'desde', to_char(current_date, 'DD/MM/YYYY'))), false, 'qa.csv');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TI-01 · Carga de tarifario con plan: vista previa «nueva» con el plan','ok',coalesce(((v_x->>'new')::int = 1 and v_x->'rows'->0->>'plan' = 'QA Royal'), false),'d',(v_x::text)::text));
    v_x := public.import_contract_tariffs_v2(jsonb_build_array(jsonb_build_object('medico', v_prov::text, 'ars', v_ars::text, 'plan', 'No existe', 'servicio', v_c2,
             'tarifa', '800', 'desde', to_char(current_date, 'DD/MM/YYYY'))), false, 'qa.csv');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TI-02 · Plan inexistente: dice cuál fila corregir','ok',coalesce((jsonb_array_length(v_x->'errors') = 1 and v_x->'errors'->0->'errors'->>0 like 'Plan inexistente%'), false),'d',(v_x->'errors')::text));
    v_x := public.import_contract_tariffs_v2(jsonb_build_array(jsonb_build_object('medico', v_prov::text, 'ars', v_ars::text, 'plan', 'QA Royal', 'servicio', v_c2,
             'tarifa', '800', 'desde', to_char(current_date, 'DD/MM/YYYY'))), true, 'qa.csv');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','TI-03 · Guarda la tarifa del plan y la registra en el historial','ok',coalesce(((v_x->>'imported')::int = 1 and exists (select 1 from public.tariffs where plan_id = v_pl1 and procedure_id = v_p2) and public.tariff_import_history(v_org)->0->>'plan' = 'QA Royal'), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status, contract_ref)
    values (v_ars2, v_org, v_prov, v_p1, 700, daterange((current_date - interval '2 years')::date + 30, null), 'vigente', 'QA-CT-VIEJO');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.tariffs_expiring(90, v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RN-01 · El Médico ya no ve la renegociación de tarifas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RN-01 · El Médico ya no ve la renegociación de tarifas','ok',sqlerrm like 'La renegociación de tarifarios la gestiona SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.tariff_renewal_followup(90);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RN-02 · El Médico no genera tareas de renegociación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','RN-02 · El Médico no genera tareas de renegociación','ok',sqlerrm like 'Solo el equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.tariffs_expiring(90, v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RN-03 · Tarifario sin fecha fin: renegociar a los 2 años (faltan 30 días)','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'tariffs') t where t->>'ars' = 'QA ARS Dos C1' and t->>'kind' = 'renegociar' and (t->>'days_left')::int = 30)), false),'d',(v_x->'tariffs')::text));
    perform public.tariff_renewal_followup(90);
    perform public.tariff_renewal_followup(90);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select count(*) into v_cnt from public.tasks where organization_id = v_org and title like 'Renegociar tarifario · QA ARS Dos C1%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','RN-04 · Crea una sola tarea «Renegociar tarifario» aunque la tarea diaria corra dos veces','ok',coalesce((v_cnt = 1), false),'d',(v_cnt)::text));

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

-- La 126 deja la renegociación solo para SOFA: la suite 117 se actualiza (CT-08 ahora la consulta un Administrador)
-- 117 · Suite de la 116 (tarifario desde Excel, historial y vencimientos). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_tarifario_excel();
create or replace function app.qa_run_tests_tarifario_excel()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000002a1'; v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000002a2';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000002a1';
  v_med constant text := 'a7000000-0000-4000-8000-0000000002a1'; v_otro constant text := 'a7000000-0000-4000-8000-0000000002a2';
  v_adm constant text := 'a7000000-0000-4000-8000-0000000002a3';
  v_ars uuid; v_ars_name text; v_p1 uuid; v_p2 uuid; v_c1 text; v_c2 text; v_rows jsonb;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.te.med@sofa.test','x'),(v_otro::uuid,'qa.te.otro@sofa.test','x'),(v_adm::uuid,'qa.te.adm@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.te.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA TE A', '00000000701', 'Médico independiente', 'activo', current_date - 90, '8095550701');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA TE B', '00000000702', 'Médico independiente', 'activo', current_date - 90, '8095550702');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. TE', 'Pediatría');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org2, v_otro::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin');
    select id, name into v_ars, v_ars_name from public.ars where is_active order by name limit 1;
    select id, internal_code into v_p1, v_c1 from public.procedures where is_active and internal_code is not null order by internal_code limit 1;
    select id, internal_code into v_p2, v_c2 from public.procedures where is_active and internal_code is not null and id <> v_p1 order by internal_code limit 1;
    -- Tarifa vigente previa para el primer servicio (para probar «cambia» e «igual»)
    perform public.create_contract_tariff(v_prov, v_ars, v_p1, 1000, current_date - 30, null, 'CT-VIEJO');
    v_rows := jsonb_build_array(
      jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', v_c1, 'tarifa', '1,200.00', 'desde', to_char(current_date, 'DD/MM/YYYY'), 'contrato', 'CT-2026'),
      jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', v_c2, 'tarifa', 'RD$850', 'desde', to_char(current_date, 'DD/MM/YYYY'), 'contrato', 'CT-2026'));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.import_contract_tariffs_v2(v_rows, false, 'tarifario.xlsx');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Vista previa: 1 nueva y 1 que cambia (+20 %)','ok',coalesce(((v_x->>'new')::int = 1 and (v_x->>'changed')::int = 1 and exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'change' = 'cambia' and (r->>'diff_pct')::numeric = 20)), false),'d',(v_x->>'new' || ' nuevas, ' || (v_x->>'changed') || ' cambian')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · La vista previa no guarda nada','ok',coalesce(((select count(*) from public.tariffs where provider_id = v_prov) = 1), false),'d',(null)::text));
    v_x := public.import_contract_tariffs_v2(v_rows, true, 'tarifario.xlsx');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Al confirmar importa 2 y cierra la tarifa anterior','ok',coalesce(((v_x->>'imported')::int = 2 and (select amount from public.tariffs where provider_id = v_prov and procedure_id = v_p1 and valid_during @> current_date) = 1200), false),'d',(v_x->>'imported')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Queda en el historial de cargas','ok',coalesce((exists (select 1 from jsonb_array_elements(public.tariff_import_history(v_org)) h where h->>'file' = 'tarifario.xlsx' and (h->>'imported')::int = 2 and h->>'contract' = 'CT-2026')), false),'d',(null)::text));
    v_rows := jsonb_build_array(jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', v_c1, 'tarifa', '1200', 'desde', to_char(current_date + 1, 'DD/MM/YYYY'), 'contrato', 'CT-2026'));
    v_x := public.import_contract_tariffs_v2(v_rows, false, 'otra.csv');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Misma tarifa: se marca «igual» y no se vuelve a cargar','ok',coalesce(((v_x->>'same')::int = 1), false),'d',(v_x::text)::text));
    v_x := public.import_contract_tariffs_v2(jsonb_build_array(jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', 'NO-EXISTE-QA', 'tarifa', '0', 'desde', 'ayer')), false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Filas con error se explican','ok',coalesce((jsonb_array_length(v_x->'errors') = 1), false),'d',(v_x->'errors')::text));
    begin
      perform public.import_contract_tariffs_v2(jsonb_build_array(jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', 'NO-EXISTE-QA', 'tarifa', '0', 'desde', 'ayer')), true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · No confirma si hay errores','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · No confirma si hay errores','ok',sqlerrm like 'Corrija las 1 filas con errores%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, source, contract_ref)
    select v_ars, v_org, v_prov, p.id, 777, daterange(current_date - 10, current_date + 21), 'Contrato', 'CT-VENCE'
      from public.procedures p where p.is_active and p.id not in (v_p1, v_p2) order by p.internal_code limit 1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.tariffs_expiring(60, v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Aviso a SOFA de tarifas que vencen en 60 días','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'tariffs') t where t->>'contract' = 'CT-VENCE' and (t->>'days_left')::int = 20) or not exists (select 1 from public.procedures p where p.is_active and p.id not in (v_p1, v_p2))), false),'d',(v_x->'tariffs')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.tariff_import_history(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Otro médico no ve el historial ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Otro médico no ve el historial ajeno','ok',sqlerrm like 'Sin acceso a este cliente%','d',left(sqlerrm,120)));
    end;

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
