-- 149 · Suite de la 148 (brechas de tarifa y carpeta de negociación). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_brechas_tarifarias();
create or replace function app.qa_run_tests_brechas_tarifarias()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01490000-0000-4000-8000-000000000001'; v_org2 constant uuid := '01490000-0000-4000-8000-000000000002'; v_prov constant uuid := '01490000-0000-4000-8000-000000000003'; v_prov2 constant uuid := '01490000-0000-4000-8000-000000000004';
  v_ops constant text := '01490000-0000-4000-8000-000000000011'; v_med constant text := '01490000-0000-4000-8000-000000000012'; v_sec constant text := '01490000-0000-4000-8000-000000000013'; v_otro constant text := '01490000-0000-4000-8000-000000000014';
  v_a1 uuid; v_a2 uuid; v_a3 uuid; v_p1 uuid; v_p2 uuid; v_s uuid; v_case uuid; v_per date;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_ops::uuid,'qa.bt.ops@sofa.test','x'),(v_med::uuid,'qa.bt.med@sofa.test','x'),(v_sec::uuid,'qa.bt.sec@sofa.test','x'),(v_otro::uuid,'qa.bt.otro@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.bt.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA BT Consultorio', '00000000841', 'Médico independiente', 'activo', current_date - 90, '8095550841');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA BT Otro', '00000000842', 'Médico independiente', 'activo', current_date - 90, '8095550842');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. Brecha', 'Dermatología'), (v_prov2, v_org2, 'Dr. Ajeno', 'Dermatología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'),
      (v_org2, v_otro::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_bt_a', 'QA ARS A', 'Contributivo', true) returning id into v_a1;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_bt_b', 'QA ARS B', 'Contributivo', true) returning id into v_a2;
    insert into public.ars (code, name, regime_default, is_active) values ('qa_bt_c', 'QA ARS C', 'Contributivo', true) returning id into v_a3;
    select p.id into v_p1 from public.procedures p where p.is_active order by p.internal_code limit 1;
    select p.id into v_p2 from public.procedures p where p.is_active and p.id <> v_p1 order by p.internal_code limit 1;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status) values
      (v_a1, v_org, v_prov, v_p1, 1000, daterange(current_date - 400, null), 'vigente'), (v_a2, v_org, v_prov, v_p1, 1500, daterange(current_date - 400, null), 'vigente'),
      (v_a1, v_org, v_prov, v_p2, 700, daterange(current_date - 400, null), 'vigente'),
      (v_a1, v_org2, v_prov2, v_p1, 9999, daterange(current_date - 400, null), 'vigente');   -- otro cliente: nunca debe influir
    insert into public.provider_ars_codes (organization_id, provider_id, ars_id, code, status) values (v_org, v_prov, v_a3, 'C-77', 'codificado');
    v_per := date_trunc('month', current_date - 40)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_a1, v_per, 1, 'borrador', current_date - 10) returning id into v_s;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_s, v_org, v_per + 1, 'Paciente BT', v_p1, 4, 1000);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.tariff_gaps(v_org, null)->'providers'->0;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-01 · Brecha: ARS A paga 1,000 y ARS B 1,500 por lo mismo; 4 radicados = RD$ 2,000 al año','ok',coalesce((jsonb_array_length(v_x->'gaps') = 1 and (v_x->'gaps'->0->>'gap')::numeric = 500 and v_x->'gaps'->0->>'best_ars' = 'QA ARS B' and (v_x->>'annual_total')::numeric = 2000), false),'d',(v_x->>'gaps')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-02 · Nunca usa tarifas de otro cliente (9,999 no aparece)','ok',coalesce((not (v_x::text like '%9999%')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-03 · Procedimientos por contratar con la ARS donde ya está codificado','ok',coalesce((jsonb_array_length(v_x->'not_contracted') = 2 and v_x->'not_contracted'->0->>'ars' = 'QA ARS C'), false),'d',(v_x->>'not_contracted')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-04 · Volumen aportado por ARS','ok',coalesce(((v_x->'volume'->0->>'claimed')::numeric = 4000), false),'d',(v_x->>'volume')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.tariff_gaps(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-05 · La Secretaria no ve tarifas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-05 · La Secretaria no ve tarifas','ok',sqlerrm like 'Sin acceso a las tarifas%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.tariff_gaps(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-06 · Otro cliente no ve estas brechas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-06 · Otro cliente no ve estas brechas','ok',sqlerrm like 'Sin acceso a las tarifas%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    v_case := (public.tariff_renewal_open_case(v_org, v_prov, v_a1, null)->>'id')::uuid;
    v_x := public.negotiation_folder(v_case);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-07 · Carpeta: propone 1,500 para el procedimiento y calcula el aumento anual','ok',coalesce(((v_x->>'annual_increase')::numeric = 2000 and exists (select 1 from jsonb_array_elements(v_x->'tariffs') t where (t->>'current')::numeric = 1000 and (t->>'proposed')::numeric = 1500)), false),'d',(v_x::text)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-08 · La carpeta queda en la bitácora interna del caso','ok',coalesce((exists (select 1 from public.sofa_service_case_events where case_id = v_case and note = 'Carpeta de negociación generada' and not visible)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.negotiation_folder(v_case);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-09 · El Médico no genera la carpeta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-09 · El Médico no genera la carpeta','ok',sqlerrm like 'La carpeta de negociación es del equipo SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BT-10 · Sin sesión no se usa','ok',coalesce((not has_function_privilege('anon', 'public.tariff_gaps(uuid,uuid)', 'execute')), false),'d',(null)::text));

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
