-- 167 · Suite de la 166 (casos de éxito y referidos). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_casos_referidos();
create or replace function app.qa_run_tests_casos_referidos()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01670000-0000-4000-8000-000000000001'; v_prov constant uuid := '01670000-0000-4000-8000-000000000003';
  v_as constant text := '01670000-0000-4000-8000-000000000011'; v_med constant text := '01670000-0000-4000-8000-000000000012'; v_aud constant text := '01670000-0000-4000-8000-000000000013';
  v_ars uuid; v_p1 uuid; v_s1 uuid; v_s2 uuid; v_l1 uuid; v_l2 uuid; v_g uuid; v_case uuid; v_ref uuid; v_t0 date;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_as::uuid,'qa.cr.as@sofa.test','x'),(v_med::uuid,'qa.cr.med@sofa.test','x'),(v_aud::uuid,'qa.cr.aud@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.cr.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA CR Consultorio', '00000000921', 'Médico independiente', 'activo', current_date - 90, '8095550921');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. Éxito', 'Ginecología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_as::uuid, 'assistant'), ('00000000-0000-4000-8000-000000000001'::uuid, v_aud::uuid, 'auditor');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_cr_ars', 'QA ARS Éxito', 'Contributivo', true) returning id into v_ars;
    select p.id into v_p1 from public.procedures p where p.is_active order by p.internal_code limit 1;
    v_t0 := date_trunc('month', current_date - 200)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_ars, v_t0, 1, 'borrador', v_t0 + 5) returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_prov, v_ars, date_trunc('month', current_date - 20)::date, 2, 'borrador', current_date - 10) returning id into v_s2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_s1, v_org, v_t0 + 1, 'Paciente CR 1', v_p1, 1, 10000) returning id into v_l1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount) values (v_s2, v_org, date_trunc('month', current_date - 20)::date + 1, 'Paciente CR 2', v_p1, 1, 10000) returning id into v_l2;
    insert into public.glosas (organization_id, submission_id, notified_on) values (v_org, v_s1, v_t0 + 20) returning id into v_g;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount, recovered_amount) values (v_g, v_org, v_l1, 'documentacion', 3000, 2000);
    insert into public.glosas (organization_id, submission_id, notified_on) values (v_org, v_s2, current_date - 5) returning id into v_g;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_g, v_org, v_l2, 'documentacion', 500);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_as, 'role', 'authenticated')::text, true);
    v_x := public.success_case_suggest(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-01 · Sugiere el caso con sus números: glosa de 30 % a 5 % y RD$ 2,000 recuperados','ok',coalesce(((v_x->>'ready')::boolean and v_x->>'headline' like '%La glosa bajó de 30.0 % a 5.0 %%' and v_x->>'headline' like '%RD$ 2,000.00%'), false),'d',(v_x->>'headline')::text));
    begin
      perform public.success_case_save(null, v_org, 'Consultorio bajó su glosa', 'Historia', null, 'publicable');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-02 · Publicable sin consentimiento: lo pide','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-02 · Publicable sin consentimiento: lo pide','ok',sqlerrm like 'Para publicar hace falta el consentimiento%','d',left(sqlerrm,120)));
    end;
    v_case := public.success_case_save(null, v_org, 'Consultorio bajó su glosa a 5 %', 'Historia del caso', 'Ahora cobro a tiempo', 'publicable', 'Dra. Éxito', current_date, 'Correo del 09/10');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-03 · Con consentimiento queda publicable y guarda los números','ok',coalesce((exists (select 1 from jsonb_array_elements(public.success_cases_list()) c where (c->>'id')::uuid = v_case and c->>'status' = 'publicable' and c->'metrics' ? 'before')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.success_case_suggest(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-04 · El Médico no prepara casos de éxito','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-04 · El Médico no prepara casos de éxito','ok',sqlerrm like 'Los casos de éxito los prepara%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.client_referral_add(v_org, 'Dr. Colega', '123');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-05 · Referido sin teléfono: lo pide','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-05 · Referido sin teléfono: lo pide','ok',sqlerrm like 'Escriba el teléfono o WhatsApp%','d',left(sqlerrm,120)));
    end;
    v_ref := public.client_referral_add(v_org, 'Dr. Colega Referido', '809-555-4433', 'Urología', 'Le interesa la facturación');
    begin
      perform public.client_referral_add(v_org, 'Otro nombre', '8095554433');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-06 · No duplica un colega que ya está en contacto','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-06 · No duplica un colega que ya está en contacto','ok',sqlerrm like 'Ese colega ya está en contacto con SOFA%','d',left(sqlerrm,120)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-07 · El Médico ve su referido «En contacto»','ok',coalesce((public.my_referrals(v_org)->0->>'status' = 'En contacto'), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-08 · Se crea el prospecto con quién lo refirió y una tarea para llamar en 24 horas','ok',coalesce((exists (select 1 from public.leads where id = v_ref and referred_by_org = v_org and source = 'Cliente actual (venta cruzada)') and exists (select 1 from public.tasks where entity_type = 'lead' and entity_id = v_ref and title like 'Contactar referido%')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_as, 'role', 'authenticated')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-09 · Tablero de referidos por cliente','ok',coalesce((exists (select 1 from jsonb_array_elements(public.referrals_board()->'clients') c where (c->>'organization_id')::uuid = v_org and (c->>'referrals')::int = 1)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_aud, 'role', 'authenticated')::text, true);
    begin
      perform public.referrals_board();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-10 · Auditoría no ve el tablero comercial de referidos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-10 · Auditoría no ve el tablero comercial de referidos','ok',sqlerrm like 'El tablero de referidos es del equipo comercial%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-11 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.success_cases', 'select')), false),'d',(null)::text));

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
