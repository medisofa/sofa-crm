-- Ya aplicado en producción (25/11/2026). Se guarda aquí como documentación.
-- 269 · Suite de la 268 (unir radicaciones de varios meses). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_unir_radicaciones();
create or replace function app.qa_run_tests_unir_radicaciones()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql set search_path = '' as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_msg text;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_ad  constant uuid := '26800000-0000-4000-8000-000000000002';
  v_bil constant uuid := '26800000-0000-4000-8000-000000000003';
  v_org constant uuid := '26800000-0000-4000-8000-0000000000a1';
  v_prov constant uuid := '26800000-0000-4000-8000-0000000000b1';
  v_ars uuid; v_p uuid; v_old uuid; v_new uuid; v_m0 date; v_m1 date; v_f date; v_n int; v_n0 int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    v_m1 := (date_trunc('month', current_date) - interval '1 month')::date;
    v_m0 := (v_m1 - interval '1 month')::date;
    insert into auth.users (id, email, encrypted_password) values (v_ad,'qa.ur.ad@sofa.test','x'), (v_bil,'qa.ur.bil@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ur.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', v_sofa, 'QA UR Consultorio', '00000026801', 'Médico independiente', 'activo', current_date - 90, '8095552681');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_prov, v_org, 'Dr. UR QA', 'Cardiología', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values (v_sofa, v_ad, 'admin', true), (v_sofa, v_bil, 'billing', true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa268_ars', 'ARS QA Unión Ficticia', 'Contributivo', true) returning id into v_ars;
    insert into public.procedures (internal_code, description, service_type_code, is_active)
    values ('QA268-P1', 'SERVICIO QA UNION', (select service_type_code from public.procedures where is_active limit 1), true) returning id into v_p;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status, contract_ref)
    values (v_ars, v_org, v_prov, v_p, 750, daterange(current_date - 400, null), 'vigente', 'QA-UR-1');
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_prov, v_ars, v_m0, 1, 'borrador') returning id into v_old;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_prov, v_ars, v_m1, 1, 'borrador') returning id into v_new;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_old, v_org, v_m0 + 5, 'Paciente UR Uno', '100268001', v_p, 1, 750), (v_new, v_org, v_m1 + 5, 'Paciente UR Dos', '100268002', v_p, 1, 750);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_msg := null; begin perform public.merge_submissions(v_new, array[v_old], 'motivo de prueba QA'); exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Facturación no une radicaciones','ok',coalesce(v_msg like '%Solo Admin%', false),'d',v_msg));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_msg := null; begin update public.submissions set period_from = v_m0 where id = v_new; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · El mes inicial no se cambia a mano','ok',coalesce(v_msg like '%solo cambia al usar%', false),'d',v_msg));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.merge_submissions(v_new, array[v_old], 'motivo de prueba QA');
    v_n := (public.validate_submission(v_new, false)->'items'->7->>'ok_count')::int;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select period_from into v_f from public.submissions where id = v_new;
    select count(*) into v_n0 from public.service_lines where submission_id = v_old;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · El Admin une: 2 reclamaciones, RD$1,500, el lote viejo queda vacío','ok',coalesce((v_x->>'lines')::int = 2 and (v_x->>'total')::numeric = 1500 and v_n0 = 0, false),'d',v_x::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Queda el mes inicial y la validación acepta ambas fechas','ok',coalesce(v_f = v_m0 and v_n = 2, false),'d',v_f::text || ' · ' || v_n));
    v_msg := null; begin insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount) values (v_new, v_org, v_m0 - 1, 'Paciente UR Tres', '100268003', v_p, 1, 750); exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Una fecha anterior al mes inicial sigue rechazada','ok',coalesce(v_msg like '%fuera del período%', false),'d',v_msg));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_msg := null; begin perform public.merge_submissions(v_new, array[v_old], 'motivo de prueba QA'); exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Repetir la unión se rechaza','ok',coalesce(v_msg like '%no tiene reclamaciones%', false),'d',v_msg));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · anon no ejecuta la unión','ok',coalesce(not has_function_privilege('anon','public.merge_submissions(uuid,uuid[],text)','execute'), false),'d',null));
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
revoke execute on function app.qa_run_tests_unir_radicaciones() from public, anon, authenticated;

delete from app.schema_migrations where version in ('268', '269');
insert into app.schema_migrations (version, report) values
  ('268', jsonb_build_object('tema', 'unir radicaciones de varios meses')),
  ('269', jsonb_build_object('tema', 'suite de la 268'));
