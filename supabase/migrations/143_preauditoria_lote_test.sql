-- 143 · Suite de la 142 (pre-auditoría del lote y glosa de primera pasada). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_preauditoria();
create or replace function app.qa_run_tests_preauditoria()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01430000-0000-4000-8000-000000000001'; v_org2 constant uuid := '01430000-0000-4000-8000-000000000002'; v_prov constant uuid := '01430000-0000-4000-8000-000000000003'; v_prov2 constant uuid := '01430000-0000-4000-8000-000000000004';
  v_med constant text := '01430000-0000-4000-8000-000000000013'; v_sec constant text := '01430000-0000-4000-8000-000000000014'; v_bil constant text := '01430000-0000-4000-8000-000000000015';
  v_ars uuid; v_p1 uuid; v_p2 uuid; v_s1 uuid; v_s2 uuid; v_s3 uuid; v_l1 uuid; v_l2 uuid; v_l3 uuid; v_g uuid; v_per date; v_per2 date;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.pa.med@sofa.test','x'),(v_sec::uuid,'qa.pa.sec@sofa.test','x'),(v_bil::uuid,'qa.pa.bil@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.pa.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA PA Consultorio', '00000000811', 'Médico independiente', 'activo', current_date - 90, '8095550811');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA PA Dos', '00000000812', 'Médico independiente', 'activo', current_date - 90, '8095550812');
    update public.organizations set ecf_required_from = current_date - 1 where id = v_org;
    update public.organizations set ecf_required_from = current_date + 20 where id = v_org2;
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. Pre', 'Cardiología'), (v_prov2, v_org2, 'Dra. Dos', 'Pediatría');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'), ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_pa_ars', 'QA ARS Pre', 'Contributivo', true) returning id into v_ars;
    select p.id into v_p1 from public.procedures p where p.is_active and exists (select 1 from public.procedure_codes c where c.procedure_id = p.id and c.code_system in ('CUPS','SIMON','UNIVERSAL')) order by p.internal_code limit 1;
    select p.id into v_p2 from public.procedures p where p.is_active and p.id <> v_p1 and exists (select 1 from public.procedure_codes c where c.procedure_id = p.id and c.code_system in ('CUPS','SIMON','UNIVERSAL')) order by p.internal_code limit 1;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status, contract_ref)
    values (v_ars, v_org, v_prov, v_p1, 1000, daterange(current_date - 400, null), 'vigente', 'QA-PA'), (v_ars, v_org2, v_prov2, v_p1, 1000, daterange(current_date - 400, null), 'vigente', 'QA-PA2');
    v_per := date_trunc('month', current_date)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_prov, v_ars, v_per, 1, 'borrador') returning id into v_s1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_org, current_date, 'Paciente Completo QA', '100200300', 'AUT-1', v_p1, 1, 1000) returning id into v_l1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_org, current_date, 'Paciente Sin Aut QA', '100200301', v_p1, 1, 1000) returning id into v_l2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s1, v_org, current_date, 'Paciente Sin Contrato QA', '100200302', 'AUT-3', v_p2, 1, 800) returning id into v_l3;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org2, v_prov2, v_ars, v_per, 1, 'borrador') returning id into v_s3;
    -- Lote ya radicado con glosa (primera pasada)
    v_per2 := date_trunc('month', current_date - 10)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_ars, v_per2, 2, 'borrador', current_date - 5) returning id into v_s2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, authorization_number, procedure_id, quantity, unit_amount)
    values (v_s2, v_org, v_per2 + 1, 'Paciente Glosado QA', '100200303', 'AUT-4', v_p1, 2, 1000) returning id into v_l3;
    insert into public.glosas (organization_id, submission_id, notified_on) values (v_org, v_s2, current_date - 2) returning id into v_g;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_g, v_org, v_l3, 'sin_autorizacion', 300);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.preaudit_submission(v_s1);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-01 · El Médico pre-audita su lote: 3 reclamaciones, no se puede radicar','ok',coalesce(((v_x->>'lines')::int = 3 and not (v_x->>'can_submit')::boolean and (v_x->>'score')::int < 100), false),'d',(v_x->>'score')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-02 · Agrupa «Sin autorización» con la reclamación que le falta y dice qué hacer','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'problems') p where p->>'code' = 'auth' and p->>'severity' = 'bloquea' and p->>'todo' like 'Registre el número%' and p->'claims' @> jsonb_build_array(jsonb_build_object('id', v_l2)) and not p->'claims' @> jsonb_build_array(jsonb_build_object('id', v_l1)))), false),'d',(v_x->>'problems')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-03 · Detecta el servicio no contratado','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'problems') p where p->>'code' = 'contracted' and jsonb_array_length(p->'claims') >= 1 and p->'claims'->0->>'patient' = 'Paciente Sin Contrato QA')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-04 · Cliente obligado a e-CF: el lote sin E31 bloquea','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'problems') p where p->>'code' = 'ecf' and p->>'severity' = 'bloquea' and p->>'scope' = 'lote')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.preaudit_submission(v_s1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-05 · La Secretaria no pre-audita lotes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-05 · La Secretaria no pre-audita lotes','ok',sqlerrm like 'Lote no encontrado o sin acceso%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_bil, 'role', 'authenticated')::text, true);
    v_x := public.preaudit_submission(v_s3);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-06 · Facturación ve el aviso de e-CF próximo (20 días) como advertencia','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'problems') p where p->>'code' = 'ecf_soon' and p->>'severity' = 'advierte') and (v_x->>'empty')::boolean), false),'d',(v_x->>'problems')::text));
    v_x := public.preaudit_open_lots(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-07 · Lista los lotes abiertos del cliente con su puntaje','ok',coalesce((jsonb_array_length(v_x) = 1 and v_x->0->>'provider' = 'Dr. Pre' and v_x->0 ? 'score'), false),'d',(v_x::text)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.first_pass_glosa(v_org, 6);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-08 · Glosa de primera pasada: RD$ 300 de RD$ 2,000 = 15 %','ok',coalesce(((v_x->'total'->>'pct')::numeric = 15.0 and (v_x->'total'->>'lots')::int = 1), false),'d',(v_x->>'total')::text));
    begin
      perform public.first_pass_glosa(null, 6);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-09 · El Médico no ve el indicador de toda la cartera','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-09 · El Médico no ve el indicador de toda la cartera','ok',sqlerrm like 'Elija su consultorio%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.first_pass_glosa(v_org, 30);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-10 · Meses fuera de rango: dice el rango','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-10 · Meses fuera de rango: dice el rango','ok',sqlerrm like 'Indique de 1 a 24 meses%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PA-11 · Sin sesión no se usa','ok',coalesce((not has_function_privilege('anon', 'public.preaudit_submission(uuid)', 'execute')), false),'d',(null)::text));

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
