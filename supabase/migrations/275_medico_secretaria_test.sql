-- PENDIENTE de aplicar en producción. No fusionar así.
-- 275 · Suite: el médico solo ve su información (274) y la secretaria edita pero no borra. Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_medico_secretaria();
create or replace function app.qa_run_tests_medico_secretaria()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql set search_path = '' as $function$
declare
  v_res jsonb := '[]'::jsonb; v_n int; v_m int; v_t text;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_da  constant uuid := '27500000-0000-4000-8000-000000000001';
  v_db  constant uuid := '27500000-0000-4000-8000-000000000002';
  v_sec constant uuid := '27500000-0000-4000-8000-000000000003';
  v_org constant uuid := '27500000-0000-4000-8000-0000000000a1';
  v_pa  constant uuid := '27500000-0000-4000-8000-0000000000b1';
  v_pb  constant uuid := '27500000-0000-4000-8000-0000000000b2';
  v_ars uuid; v_p uuid; v_sa uuid; v_sb uuid; v_la uuid; v_lb uuid; v_m1 date;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    v_m1 := (date_trunc('month', current_date) - interval '1 month')::date;
    insert into auth.users (id, email, encrypted_password) values
      (v_da,'qa.ms.a@sofa.test','x'), (v_db,'qa.ms.b@sofa.test','x'), (v_sec,'qa.ms.s@sofa.test','x');
    insert into public.profiles (id, full_name) values (v_da,'qa.ms.a'), (v_db,'qa.ms.b'), (v_sec,'qa.ms.s') on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', v_sofa, 'QA MS Clinica', '00000027501', 'Médico independiente', 'activo', current_date - 200, '8095552751');
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      (v_org, v_da, 'client', true), (v_org, v_db, 'client', true), (v_org, v_sec, 'capturer', true);
    insert into public.providers (id, organization_id, full_name, specialty, is_active, user_id) values
      (v_pa, v_org, 'Dr. MS A', 'Cardiología', true, v_da), (v_pb, v_org, 'Dr. MS B', 'Cardiología', true, v_db);
    insert into public.capturer_scopes (organization_id, user_id, provider_id) values (v_org, v_sec, v_pa);
    insert into public.ars (code, name, regime_default, is_active) values ('qa275_ars', 'ARS QA MS Ficticia', 'Contributivo', true) returning id into v_ars;
    insert into public.procedures (internal_code, description, service_type_code, is_active)
    values ('QA275-P1', 'SERVICIO QA MS', (select service_type_code from public.procedures where is_active limit 1), true) returning id into v_p;
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, status, contract_ref)
    values (v_ars, v_org, v_pa, v_p, 700, daterange(current_date - 400, null), 'vigente', 'QA-MS-A'),
           (v_ars, v_org, v_pb, v_p, 900, daterange(current_date - 400, null), 'vigente', 'QA-MS-B');
    insert into public.provider_ars_codes (organization_id, provider_id, ars_id) values (v_org, v_pa, v_ars), (v_org, v_pb, v_ars);
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_pa, v_ars, v_m1, 1, 'borrador') returning id into v_sa;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_org, v_pb, v_ars, v_m1, 1, 'borrador') returning id into v_sb;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_sa, v_org, v_m1 + 5, 'Paciente MS A', '100275001', v_p, 1, 700) returning id into v_la;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, member_number, procedure_id, quantity, unit_amount)
    values (v_sb, v_org, v_m1 + 5, 'Paciente MS B', '100275002', v_p, 1, 900) returning id into v_lb;
    insert into storage.objects (bucket_id, name) values
      ('claim-documents', v_org || '/' || v_sa || '/qa-a.pdf'), ('claim-documents', v_org || '/' || v_sb || '/qa-b.pdf');

    -- Médico A
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_da, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) filter (where t.provider_id = v_pa), count(*) filter (where t.provider_id = v_pb) into v_n, v_m from public.tariffs t where t.organization_id = v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · El médico ve sus tarifas y no las de su colega','ok',v_n = 1 and v_m = 0,'d',format('propias %s, ajenas %s', v_n, v_m)));
    select count(*) filter (where c.provider_id = v_pa), count(*) filter (where c.provider_id = v_pb) into v_n, v_m from public.provider_ars_codes c where c.organization_id = v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Igual con los códigos de prestador','ok',v_n = 1 and v_m = 0,'d',format('propios %s, ajenos %s', v_n, v_m)));
    select count(*) filter (where o.name like '%qa-a.pdf'), count(*) filter (where o.name like '%qa-b.pdf') into v_n, v_m from storage.objects o where o.bucket_id = 'claim-documents' and o.name like v_org || '/%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · El médico abre sus archivos y no los de su colega','ok',v_n = 1 and v_m = 0,'d',format('propios %s, ajenos %s', v_n, v_m)));
    select count(*) into v_n from public.service_lines l where l.id = v_lb;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · El médico no ve reclamaciones de su colega','ok',v_n = 0,'d',v_n::text));

    -- Secretaria del médico A
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    update public.service_lines set patient_name = 'Paciente MS Corregido' where id = v_la;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · La secretaria corrige una reclamación de su médico','ok',v_n = 1,'d',v_n::text));
    update public.service_lines set patient_name = 'No debe cambiar' where id = v_lb;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · No corrige las de un médico que no tiene asignado','ok',v_n = 0,'d',v_n::text));
    delete from public.service_lines where id = v_la;
    get diagnostics v_n = row_count;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · No puede borrar una reclamación','ok',v_n = 0,'d',v_n::text));
    v_t := 'sin error';
    begin perform public.remove_service_line(v_la, 'motivo de prueba QA'); exception when others then v_t := sqlstate; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · No puede quitarla del lote','ok',v_t = '42501','d',v_t));
    v_t := 'sin error';
    begin perform public.delete_submission(v_sa, 'motivo de prueba QA', 'x'); exception when others then v_t := sqlstate; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · No puede borrar el lote','ok',v_t = '42501','d',v_t));

    -- Ya retirada: no la modifica
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    perform set_config('app.claim_change', 'on', true);
    update public.service_lines set claim_status = 'retirada' where id = v_la;
    perform set_config('app.claim_change', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_t := 'sin error';
    begin update public.service_lines set patient_name = 'Tarde' where id = v_la; exception when others then v_t := sqlstate; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Una reclamación ya retirada no la cambia','ok',v_t = '42501','d',v_t));

    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
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
revoke execute on function app.qa_run_tests_medico_secretaria() from public, anon, authenticated;

delete from app.schema_migrations where version = '275';
insert into app.schema_migrations (version, report) values ('275', jsonb_build_object('tema', 'suite médico y secretaria'));
