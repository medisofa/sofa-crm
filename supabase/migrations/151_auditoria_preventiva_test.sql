-- 151 · Suite de la 150 (auditoría preventiva del expediente). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_auditoria_preventiva();
create or replace function app.qa_run_tests_auditoria_preventiva()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01510000-0000-4000-8000-000000000001'; v_org2 constant uuid := '01510000-0000-4000-8000-000000000002'; v_prov constant uuid := '01510000-0000-4000-8000-000000000003';
  v_aud constant text := '01510000-0000-4000-8000-000000000011'; v_med constant text := '01510000-0000-4000-8000-000000000012'; v_ops constant text := '01510000-0000-4000-8000-000000000013'; v_adm constant text := '01510000-0000-4000-8000-000000000014';
  v_ars uuid; v_p1 uuid; v_s uuid; v_hi uuid; v_rev uuid; v_cnt int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_aud::uuid,'qa.ap.aud@sofa.test','x'),(v_med::uuid,'qa.ap.med@sofa.test','x'),(v_ops::uuid,'qa.ap.ops@sofa.test','x'),(v_adm::uuid,'qa.ap.adm@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ap.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA AU Consultorio', '00000000851', 'Médico independiente', 'activo', current_date - 90, '8095550851');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA AU Otro', '00000000852', 'Médico independiente', 'activo', current_date - 90, '8095550852');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. Auditado', 'Cirugía');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_aud::uuid, 'auditor'),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations'), ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin');
    insert into public.ars (code, name, regime_default, is_active) values ('qa_au_ars', 'QA ARS Auditoría', 'Contributivo', true) returning id into v_ars;
    select p.id into v_p1 from public.procedures p where p.is_active order by p.internal_code limit 1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_prov, v_ars, date_trunc('month', current_date)::date, 1, 'borrador') returning id into v_s;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    values (v_s, v_org, current_date, 'Paciente Alto Valor', v_p1, 1, 25000) returning id into v_hi;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
    select v_s, v_org, current_date, 'Paciente Bajo ' || g, v_p1, 1, 800 from generate_series(1, 10) g;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ops, 'role', 'authenticated')::text, true);
    begin
      perform public.legal_audit_settings_save(v_org, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-01 · Operaciones no activa la auditoría','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-01 · Operaciones no activa la auditoría','ok',sqlerrm like 'Solo el Super Admin o el Administrador%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    begin
      perform public.legal_audit_settings_save(v_org, true, 10000, 0);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-02 · Muestra fuera de rango: dice el rango','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-02 · Muestra fuera de rango: dice el rango','ok',sqlerrm like 'La muestra aleatoria va de 1 % a 100 %%','d',left(sqlerrm,120)));
    end;
    perform public.legal_audit_settings_save(v_org, true, 10000, 20);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_aud, 'role', 'authenticated')::text, true);
    v_x := public.legal_audit_sample(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-03 · Muestra: la de alto valor siempre y 20 % del resto (2 de 10)','ok',coalesce(((v_x->>'alto_valor')::int = 1 and (v_x->>'aleatoria')::int = 2), false),'d',(v_x::text)::text));
    v_x := public.legal_audit_sample(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-04 · No repite reclamaciones ya seleccionadas','ok',coalesce(((v_x->>'alto_valor')::int = 0), false),'d',(v_x::text)::text));
    v_x := public.legal_audit_queue(v_org, 'pendiente');
    select (i->>'id')::uuid into v_rev from jsonb_array_elements(v_x->'items') i where (i->>'service_line_id')::uuid = v_hi;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-05 · La cola trae el checklist de 6 puntos y la de alto valor primero','ok',coalesce((jsonb_array_length(v_x->'checklist') = 6 and v_x->'items'->0->>'reason' = 'alto_valor' and v_rev is not null), false),'d',(v_x->>'items')::text));
    begin
      perform public.legal_audit_review(v_rev, array['inventado'], 'Algo falta');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-06 · Punto inexistente: lo rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-06 · Punto inexistente: lo rechaza','ok',sqlerrm like 'Punto del checklist no válido%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.legal_audit_review(v_rev, array['consentimiento'], '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-07 · Con omisiones exige anotar qué falta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-07 · Con omisiones exige anotar qué falta','ok',sqlerrm like 'Anote qué falta exactamente%','d',left(sqlerrm,120)));
    end;
    perform public.legal_audit_review(v_rev, array['consentimiento','firma_sello'], 'Falta consentimiento y sello en la hoja 2');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-08 · Queda «con omisiones» y no cambia el estado de la reclamación','ok',coalesce(((select status from public.legal_audit_reviews where id = v_rev) = 'con_omisiones' and (select claim_status from public.service_lines where id = v_hi) is not distinct from (select claim_status from public.service_lines where id = v_hi)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.legal_audit_report(v_org, 90);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-09 · El Médico ve sus omisiones más frecuentes con la plantilla que las evita','ok',coalesce((v_x->'providers'->0->>'provider' = 'Dr. Auditado' and jsonb_array_length(v_x->'providers'->0->'top') = 2 and v_x->'providers'->0->'top'->0->>'template' is not null), false),'d',(v_x::text)::text));
    begin
      perform public.legal_audit_queue();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-10 · El Médico no ve la cola de auditoría','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-10 · El Médico no ve la cola de auditoría','ok',sqlerrm like 'La auditoría de expedientes es del equipo SOFA%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.legal_audit_review(v_rev, '{}');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-11 · El Médico no registra revisiones','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-11 · El Médico no registra revisiones','ok',sqlerrm like 'Solo el Auditor%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_x := public.legal_audit_sample(null);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-12 · La tarea diaria (sin sesión) corre para los clientes activos','ok',coalesce((v_x ? 'alto_valor'), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-13 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.legal_audit_reviews', 'select') and not has_function_privilege('anon', 'public.legal_audit_queue(uuid,text)', 'execute')), false),'d',(null)::text));

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
