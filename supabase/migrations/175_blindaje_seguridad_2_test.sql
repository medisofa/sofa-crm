-- 175 · Suite de la 174 (blindaje de seguridad 2: SEG-10, SEG-12 a SEG-20, SEG-26 a SEG-28). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_blindaje_2();
create or replace function app.qa_run_tests_blindaje_2()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_log bigint;
  v_a constant uuid := '17400000-0000-4000-8000-000000000001'; v_b constant uuid := '17400000-0000-4000-8000-000000000002';
  v_pa constant uuid := '17400000-0000-4000-8000-000000000003'; v_pb constant uuid := '17400000-0000-4000-8000-000000000004';
  v_ars uuid; v_proc uuid; v_per date; v_dt1 text; v_dt2 text; v_s1 uuid; v_s2 uuid; v_sr uuid; v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid;
  v_rec uuid; v_pay uuid; v_inv uuid; v_glo uuid; v_ch1 uuid; v_ch2 uuid; v_ch3 uuid; v_pat uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  if not exists (select 1 from app.schema_migrations where version = '174') then
    raise exception 'Falta la migración 174. Aplícala y vuelve a correr las pruebas.';
  end if;
  begin
    insert into auth.users (id, email, encrypted_password)
    select u::uuid, 'qa.b2.' || right(u, 2) || '@sofa.test', 'x' from unnest(array['17400000-0000-4000-8000-000000000011','17400000-0000-4000-8000-000000000012','17400000-0000-4000-8000-000000000013','17400000-0000-4000-8000-000000000014','17400000-0000-4000-8000-000000000015','17400000-0000-4000-8000-000000000016','17400000-0000-4000-8000-000000000017','17400000-0000-4000-8000-000000000021','17400000-0000-4000-8000-000000000022','17400000-0000-4000-8000-000000000024']) u;
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.b2.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_a, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA B2 Centro Médico', '00000000174', 'Médico independiente', 'activo', current_date - 90, '8095550174'),
           (v_b, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA B2 Otro Consultorio', '00000000175', 'Médico independiente', 'activo', current_date - 90, '8095550175');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_pa, v_a, 'Dr. Uno QA', 'Cardiología'), (v_pb, v_b, 'Dr. B QA', 'Ortopedia');
    insert into public.organization_users (organization_id, user_id, role_code) values
      ('00000000-0000-4000-8000-000000000001'::uuid, '17400000-0000-4000-8000-000000000011'::uuid, 'super_admin'), ('00000000-0000-4000-8000-000000000001'::uuid, '17400000-0000-4000-8000-000000000012'::uuid, 'admin'), ('00000000-0000-4000-8000-000000000001'::uuid, '17400000-0000-4000-8000-000000000013'::uuid, 'billing'), ('00000000-0000-4000-8000-000000000001'::uuid, '17400000-0000-4000-8000-000000000014'::uuid, 'glosas'),
      ('00000000-0000-4000-8000-000000000001'::uuid, '17400000-0000-4000-8000-000000000015'::uuid, 'operations'), ('00000000-0000-4000-8000-000000000001'::uuid, '17400000-0000-4000-8000-000000000016'::uuid, 'auditor'), ('00000000-0000-4000-8000-000000000001'::uuid, '17400000-0000-4000-8000-000000000017'::uuid, 'assistant'),
      (v_a, '17400000-0000-4000-8000-000000000021'::uuid, 'client'), (v_a, '17400000-0000-4000-8000-000000000022'::uuid, 'capturer'), (v_b, '17400000-0000-4000-8000-000000000024'::uuid, 'client');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values ('17400000-0000-4000-8000-000000000022'::uuid, v_pa, v_a, true, true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_b2_ars', 'ARS QA Blindaje 2', 'Contributivo', true) returning id into v_ars;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    select code into v_dt1 from public.document_types order by sort_order limit 1;
    select code into v_dt2 from public.document_types where code <> v_dt1 order by sort_order limit 1;
    v_per := date_trunc('month', current_date - 120)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_ars, v_per, 1, 'borrador') returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_ars, v_per, 2, 'borrador') returning id into v_s2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_ars, v_per, 3, 'borrador') returning id into v_sr;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_s1, v_a, v_per + 3, 'Paciente Uno QA', v_proc, 1, 1230) returning id into v_l1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_s1, v_a, v_per + 4, 'Paciente Dos QA', v_proc, 1, 1800) returning id into v_l2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_s1, v_a, v_per + 5, 'Paciente Tres QA', v_proc, 1, 500) returning id into v_l3;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount)
      values (v_sr, v_a, v_per + 6, 'Paciente Cuatro QA', v_proc, 1, 700) returning id into v_l4;
    perform set_config('app.claim_change', 'on', true);
    update public.service_lines set claim_status = 'capturada' where id in (v_l1, v_l2);
    update public.service_lines set claim_status = 'validada' where id = v_l3;
    perform set_config('app.claim_change', '', true);
    perform set_config('app.status_change', 'on', true);
    update public.submissions set status = 'radicada', submitted_on = current_date - 5, ars_receipt_number = 'QA174', ncf = 'B0100000174' where id = v_sr;
    perform set_config('app.status_change', '', true);
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.roles set is_staff = false where code = 'super_admin';
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-01 · SEG-10 · ATAQUE: el Administrador no le quita a un rol su condición de personal','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-01 · SEG-10 · ATAQUE: el Administrador no le quita a un rol su condición de personal','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.roles set name = 'Hackeado' where code = 'client'; get diagnostics v_n = row_count;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-02 · SEG-10 · ATAQUE: el Administrador no cambia el catálogo (la política lo filtra)','ok',coalesce((v_n = 0 and (select name from public.roles where code = 'client') = 'Médico'), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-02 · SEG-10 · ATAQUE: el Administrador no cambia el catálogo (la política lo filtra)','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.roles set is_staff = false where code = 'admin';
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-03 · SEG-10 · ATAQUE: ni el Super Admin cambia code o is_staff por la API','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-03 · SEG-10 · ATAQUE: ni el Super Admin cambia code o is_staff por la API','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.roles (code, name, is_staff) values ('qa_super', 'QA', true);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-04 · SEG-10 · ATAQUE: nadie crea roles por la API','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-04 · SEG-10 · ATAQUE: nadie crea roles por la API','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.roles set description = coalesce(description, 'Rol de prueba') where code = 'client'; get diagnostics v_n = row_count;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-05 · SEG-10 · Uso legítimo: el Super Admin edita la descripción de un rol','ok',coalesce((v_n = 1), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-05 · SEG-10 · Uso legítimo: el Super Admin edita la descripción de un rol','ok',false,'d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-06 · SEG-10 · El Super Admin sigue siendo personal','ok',coalesce(((select is_staff from public.roles where code = 'super_admin')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000017', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.submissions set ecf_dgii_status = 'aceptado' where id = v_s1; get diagnostics v_n = row_count; if v_n = 0 then raise exception 'sin filas visibles'; end if;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-07 · SEG-12 · ATAQUE: Comercial no marca un e-CF como aceptado en un lote','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-07 · SEG-12 · ATAQUE: Comercial no marca un e-CF como aceptado en un lote','ok',sqlerrm like 'Los datos del e-CF%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000013', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.submissions set ecf_security_code = 'ABC123' where id = v_s1; get diagnostics v_n = row_count; if v_n = 0 then raise exception 'sin filas visibles'; end if;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-08 · SEG-12 · ATAQUE: Facturación no escribe el código de seguridad del e-CF','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-08 · SEG-12 · ATAQUE: Facturación no escribe el código de seguridad del e-CF','ok',sqlerrm like 'Los datos del e-CF%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000017', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.submissions set ncf = 'E310000000999' where id = v_s1; get diagnostics v_n = row_count; if v_n = 0 then raise exception 'sin filas visibles'; end if;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-09 · SEG-12 · ATAQUE: Comercial no pone un e-NCF a mano en un lote','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-09 · SEG-12 · ATAQUE: Comercial no pone un e-NCF a mano en un lote','ok',sqlerrm like 'Los datos del e-CF%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, ecf_dgii_status, ecf_security_code) values (v_a, v_pa, v_ars, v_per, 4, 'borrador', 'aceptado', 'ABC123');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-10 · SEG-12 · ATAQUE: el Médico no crea un lote con el e-CF ya aceptado','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-10 · SEG-12 · ATAQUE: el Médico no crea un lote con el e-CF ya aceptado','ok',sqlerrm like 'Los datos del e-CF%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, fiscal_exception_amount, fiscal_exception_reason) values (v_a, v_pa, v_ars, v_per, 4, 'borrador', 100, 'autorizada por mí mismo');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-11 · SEG-12 · ATAQUE: el Médico no crea un lote con excepción fiscal','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-11 · SEG-12 · ATAQUE: el Médico no crea un lote con excepción fiscal','ok',sqlerrm like 'La excepción fiscal no se carga%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, sent_on, sent_by) values (v_a, v_pa, v_ars, v_per, 4, 'borrador', current_date, '17400000-0000-4000-8000-000000000011');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-12 · SEG-12 · ATAQUE: el Médico no crea un lote ya «enviado por» otra persona','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-12 · SEG-12 · ATAQUE: el Médico no crea un lote ya «enviado por» otra persona','ok',sqlerrm like 'El envío del lote no se carga%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_by) values (v_a, v_pa, v_ars, v_per, 4, 'borrador', '17400000-0000-4000-8000-000000000011');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-13 · SEG-12 · ATAQUE: el Médico no crea un lote ya «radicado por» otra persona','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-13 · SEG-12 · ATAQUE: el Médico no crea un lote ya «radicado por» otra persona','ok',sqlerrm like 'El campo «radicado por»%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000017', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.submissions set submitted_by = '17400000-0000-4000-8000-000000000011' where id = v_s1; get diagnostics v_n = row_count; if v_n = 0 then raise exception 'sin filas visibles'; end if;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-14 · SEG-12 · ATAQUE: nadie cambia «radicado por» a mano en un lote existente','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-14 · SEG-12 · ATAQUE: nadie cambia «radicado por» a mano en un lote existente','ok',sqlerrm like 'El campo «radicado por»%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status) values (v_a, v_pa, v_ars, v_per, 4, 'borrador');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-15 · SEG-12 · Uso legítimo: el Médico crea un lote normal en borrador','ok',coalesce((exists (select 1 from public.submissions where organization_id = v_a and sequence = 4)), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-15 · SEG-12 · Uso legítimo: el Médico crea un lote normal en borrador','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.set_submission_ecf(v_s1, 'E310000000174', 'ABC123', current_date, 'aceptado');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-16 · SEG-12 · Uso legítimo: el Administrador registra el e-CF con set_submission_ecf','ok',coalesce(((select ecf_dgii_status from public.submissions where id = v_s1) = 'aceptado' and (select ncf from public.submissions where id = v_s1) = 'E310000000174'), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-16 · SEG-12 · Uso legítimo: el Administrador registra el e-CF con set_submission_ecf','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.set_submission_ecf(v_s2, 'E310000000174', 'ABC123', current_date, 'aceptado');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-17 · SEG-12 · ATAQUE: el mismo e-NCF no se registra en otro lote del cliente','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-17 · SEG-12 · ATAQUE: el mismo e-NCF no se registra en otro lote del cliente','ok',sqlerrm like 'Ese e-NCF ya está usado%','d',left(sqlerrm,160)));
    end;
    
    begin
      update public.submissions set ncf = 'E310000000174' where id = v_s2;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-18 · SEG-12 · ATAQUE: el índice único del e-NCF frena el duplicado aunque se escriba directo','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-18 · SEG-12 · ATAQUE: el índice único del e-NCF frena el duplicado aunque se escriba directo','ok',sqlerrm like '%submissions_org_ecf_ncf_uidx%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000017', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.submissions set notes = 'nota QA' where id = v_s2; get diagnostics v_n = row_count;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-19 · SEG-12 · Uso legítimo: Comercial sigue editando notas del lote (columnas ajenas al e-CF)','ok',coalesce((v_n = 1), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-19 · SEG-12 · Uso legítimo: Comercial sigue editando notas del lote (columnas ajenas al e-CF)','ok',false,'d',left(sqlerrm,160)));
    end;
    insert into public.receptions (organization_id, provider_id, received_on, channel, status, expected_count) values (v_a, v_pa, current_date, 'fisico', 'borrador', 1) returning id into v_rec;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.receptions (organization_id, provider_id, received_on, channel, status, expected_count, received_by) values (v_a, v_pa, current_date, 'fisico', 'confirmada', 1, '17400000-0000-4000-8000-000000000011');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-20 · SEG-13 · ATAQUE: el Médico no crea retiros a nombre del personal','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-20 · SEG-13 · ATAQUE: el Médico no crea retiros a nombre del personal','ok',sqlerrm like '%row-level security%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.receptions set status = 'anulado' where id = v_rec; get diagnostics v_n = row_count;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-21 · SEG-13 · ATAQUE: el Médico no anula ni confirma retiros directamente','ok',coalesce((v_n = 0 and (select status from public.receptions where id = v_rec) = 'borrador'), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-21 · SEG-13 · ATAQUE: el Médico no anula ni confirma retiros directamente','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.receptions set status = 'anulado' where id = v_rec; get diagnostics v_n = row_count;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-22 · SEG-13 · ATAQUE: ni el Administrador escribe directo en retiros','ok',coalesce((v_n = 0 and (select status from public.receptions where id = v_rec) = 'borrador'), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-22 · SEG-13 · ATAQUE: ni el Administrador escribe directo en retiros','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000015', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_x := to_jsonb(public.create_pickup(v_pa, array[v_l1], 'QA'));
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-23 · SEG-13 · Uso legítimo: Operaciones programa un retiro con create_pickup','ok',coalesce((exists (select 1 from public.receptions r where r.id::text = (v_x #>> '{}'))), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-23 · SEG-13 · Uso legítimo: Operaciones programa un retiro con create_pickup','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000015', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.cancel_pickup((v_x #>> '{}')::uuid, 'Se programó por error en la prueba');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-24 · SEG-13 · Uso legítimo: Operaciones anula ese retiro con cancel_pickup','ok',coalesce(((select status from public.receptions r where r.id::text = (v_x #>> '{}')) = 'anulado'), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-24 · SEG-13 · Uso legítimo: Operaciones anula ese retiro con cancel_pickup','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_pay := public.register_payment(v_a, v_ars, current_date - 10, 700, 'transferencia', 'PAGO-QA-B2', jsonb_build_array(jsonb_build_object('submission_id', v_sr, 'amount', 700)));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    insert into public.sofa_invoices (organization_id, ncf, period, due_on, total, status) values (v_a, 'B0100000174', v_per, current_date + 10, 3030, 'emitida') returning id into v_inv;
    insert into public.glosas (organization_id, submission_id, notified_on) values (v_a, v_sr, current_date - 3) returning id into v_glo;
    insert into public.glosa_items (glosa_id, organization_id, service_line_id, reason_code, amount) values (v_glo, v_a, v_l4, 'otro', 700);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-25 · SEG-14 · El pago se registró con la función (legítimo)','ok',coalesce((exists (select 1 from public.payments where id = v_pay and amount = 700)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.payments set amount = 1 where id = v_pay; get diagnostics v_n = row_count;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-26 · SEG-14 · ATAQUE: el Administrador no baja el monto de un pago directo','ok',coalesce((v_n = 0 and (select amount from public.payments where id = v_pay) = 700), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-26 · SEG-14 · ATAQUE: el Administrador no baja el monto de un pago directo','ok',false,'d',left(sqlerrm,160)));
    end;
    
    begin
      update public.payments set amount = 1 where id = v_pay;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-27 · SEG-14 · ATAQUE: guard_payment no deja el pago por debajo de lo asignado (aunque se saltara la política)','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-27 · SEG-14 · ATAQUE: guard_payment no deja el pago por debajo de lo asignado (aunque se saltara la política)','ok',sqlerrm like 'El pago no puede quedar por debajo%','d',left(sqlerrm,160)));
    end;
    
    begin
      update public.payments set amount = 800 where id = v_pay;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-28 · SEG-14 · Uso legítimo: subir el monto de un pago (por encima de lo asignado) sigue permitido al sistema','ok',coalesce(((select amount from public.payments where id = v_pay) = 800), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-28 · SEG-14 · Uso legítimo: subir el monto de un pago (por encima de lo asignado) sigue permitido al sistema','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.sofa_invoices set total = 1, status = 'pagada' where id = v_inv; get diagnostics v_n = row_count;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-29 · SEG-14 · ATAQUE: el Administrador no deja una factura SOFA «pagada» en cero','ok',coalesce((v_n = 0 and (select total from public.sofa_invoices where id = v_inv) = 3030), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-29 · SEG-14 · ATAQUE: el Administrador no deja una factura SOFA «pagada» en cero','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.payment_allocations set amount = 1 where payment_id = v_pay; get diagnostics v_n = row_count;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-30 · SEG-14 · ATAQUE: el Administrador no cambia las asignaciones de pago directo','ok',coalesce((v_n = 0 and (select sum(amount) from public.payment_allocations where payment_id = v_pay) = 700), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-30 · SEG-14 · ATAQUE: el Administrador no cambia las asignaciones de pago directo','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000014', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.glosas set status = 'cerrada' where id = v_glo; get diagnostics v_n = row_count;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-31 · SEG-14 · ATAQUE: Cobros y glosas no cambia el estado de una glosa directo','ok',coalesce((v_n = 0 and (select status from public.glosas where id = v_glo) <> 'cerrada'), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-31 · SEG-14 · ATAQUE: Cobros y glosas no cambia el estado de una glosa directo','ok',false,'d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-32 · SEG-14 · Ninguna de las 6 tablas conserva política de UPDATE','ok',coalesce(((select count(*) from pg_policies where schemaname = 'public' and cmd = 'UPDATE' and tablename in ('payments','sofa_invoices','sofa_fees','payment_allocations','sofa_invoice_payments','glosas')) = 0), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000014', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_x := to_jsonb(public.appeal_glosa(v_glo, 'Argumento de apelación de prueba QA', current_date));
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-33 · SEG-14 · Uso legítimo: Cobros y glosas apela una glosa con appeal_glosa','ok',coalesce(((select status from public.glosas where id = v_glo) = 'apelada' and exists (select 1 from public.glosa_appeals where id::text = (v_x #>> '{}'))), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-33 · SEG-14 · Uso legítimo: Cobros y glosas apela una glosa con appeal_glosa','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000015', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.appeal_glosa(v_glo, 'Argumento de apelación de prueba QA', current_date);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-34 · SEG-14 · ATAQUE: Operaciones no apela glosas','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-34 · SEG-14 · ATAQUE: Operaciones no apela glosas','ok',sqlerrm like 'Su rol no puede apelar glosas%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000024', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.appeal_glosa(v_glo, 'Argumento de apelación de prueba QA', current_date);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-35 · SEG-14 · ATAQUE: el Médico de otro cliente no apela glosas ajenas','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-35 · SEG-14 · ATAQUE: el Médico de otro cliente no apela glosas ajenas','ok',sqlerrm like 'Glosa no encontrada%','d',left(sqlerrm,160)));
    end;
    
    begin
      insert into public.sofa_invoices (organization_id, ncf, period, due_on, total, status) values (v_b, 'B0100000174', v_per, current_date + 10, 100, 'emitida');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-36 · SEG-14 · ATAQUE: dos facturas SOFA no comparten NCF','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-36 · SEG-14 · ATAQUE: dos facturas SOFA no comparten NCF','ok',(sqlerrm like '%sofa_invoices_ncf_uidx%' or sqlerrm like '%sofa_invoices_ncf_uq%'),'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.sofa_invoices (organization_id, ncf, period, due_on, total, status) values (v_a, 'B0100000175', v_per, current_date + 10, 100, 'emitida');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-37 · SEG-14 · Uso legítimo: una factura con NCF distinto se crea normal','ok',coalesce((exists (select 1 from public.sofa_invoices where ncf = 'B0100000175')), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-37 · SEG-14 · Uso legítimo: una factura con NCF distinto se crea normal','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.line_document_checks (service_line_id, organization_id, document_type_code, present) values (v_l1, v_a, v_dt1, true);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-38 · SEG-15 · ATAQUE: la Secretaria no marca «presente» sin archivo','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-38 · SEG-15 · ATAQUE: la Secretaria no marca «presente» sin archivo','ok',sqlerrm like 'La marca «presente» sin archivo%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.line_document_checks (service_line_id, organization_id, document_type_code, present) values (v_l1, v_a, v_dt1, true);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-39 · SEG-15 · ATAQUE: el Médico no marca «presente» sin archivo','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-39 · SEG-15 · ATAQUE: el Médico no marca «presente» sin archivo','ok',sqlerrm like 'La marca «presente» sin archivo%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000015', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.line_document_checks (service_line_id, organization_id, document_type_code, present) values (v_l1, v_a, v_dt1, true);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-40 · SEG-15 · Uso legítimo: Operaciones sí marca «presente» (recibido en físico)','ok',coalesce((exists (select 1 from public.line_document_checks where service_line_id = v_l1 and document_type_code = v_dt1 and present)), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-40 · SEG-15 · Uso legítimo: Operaciones sí marca «presente» (recibido en físico)','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.line_document_checks set present = true where service_line_id = v_l1 and document_type_code = v_dt1; get diagnostics v_n = row_count; if v_n = 0 then raise exception 'sin filas visibles'; end if;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-41 · SEG-15 · ATAQUE: la Secretaria no reescribe como «presente» una marca existente sin archivo','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-41 · SEG-15 · ATAQUE: la Secretaria no reescribe como «presente» una marca existente sin archivo','ok',sqlerrm like 'La marca «presente» sin archivo%','d',left(sqlerrm,160)));
    end;
    insert into public.line_document_checks (service_line_id, organization_id, document_type_code, present) values (v_l3, v_a, v_dt1, false);
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.line_document_checks set present = true where service_line_id = v_l3 and document_type_code = v_dt1; get diagnostics v_n = row_count; if v_n = 0 then raise exception 'sin filas visibles'; end if;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-42 · SEG-15 · ATAQUE: ni el Administrador cambia el expediente de una reclamación ya validada','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-42 · SEG-15 · ATAQUE: ni el Administrador cambia el expediente de una reclamación ya validada','ok',sqlerrm like 'El expediente de una reclamación ya validada%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000015', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.line_document_checks (service_line_id, organization_id, document_type_code, present) values (v_l3, v_a, v_dt2, true);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-43 · SEG-15 · ATAQUE: no se agregan marcas a una reclamación validada','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-43 · SEG-15 · ATAQUE: no se agregan marcas a una reclamación validada','ok',sqlerrm like 'El expediente de una reclamación ya validada%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000015', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      delete from public.line_document_checks where service_line_id = v_l3 and document_type_code = v_dt1; get diagnostics v_n = row_count; if v_n = 0 then raise exception 'sin filas visibles'; end if;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-44 · SEG-15 · ATAQUE: no se borran marcas de una reclamación validada','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-44 · SEG-15 · ATAQUE: no se borran marcas de una reclamación validada','ok',sqlerrm like 'El expediente de una reclamación ya validada%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_x := to_jsonb(public.register_captured_document(v_a, v_s1, v_l2, v_dt2, v_a::text || '/' || v_s1::text || '/qa174-cam.jpg', 'foto.jpg', 'image/jpeg', 20000, encode(sha256(convert_to('qa174-cam','utf8')), 'hex'), 'camara', null::jsonb));
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-45 · SEG-15 · Cámara: la Secretaria registra un documento con archivo real (register_captured_document)','ok',coalesce((exists (select 1 from public.documents where id::text = (v_x #>> '{}') and capture_origin = 'camara')), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-45 · SEG-15 · Cámara: la Secretaria registra un documento con archivo real (register_captured_document)','ok',false,'d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-46 · SEG-15 · Cámara: el documento con archivo queda como presente en el expediente','ok',coalesce((exists (select 1 from public.line_document_checks where service_line_id = v_l2 and document_type_code = v_dt2 and present)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      insert into public.line_document_checks (service_line_id, organization_id, document_type_code, present) values (v_l2, v_a, v_dt2, true) on conflict (service_line_id, document_type_code) do update set present = true;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-47 · SEG-15 · Uso legítimo: con archivo ya subido, la Secretaria sí puede dejar la marca','ok',coalesce((true), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-47 · SEG-15 · Uso legítimo: con archivo ya subido, la Secretaria sí puede dejar la marca','ok',false,'d',left(sqlerrm,160)));
    end;
    insert into public.private_charges (organization_id, provider_id, charge_date, patient_name, procedure_id, service_name, quantity, unit_amount, payment_method, status, collected_on, charge_type)
      values (v_a, v_pa, current_date, 'Paciente Efectivo QA', v_proc, 'Consulta QA', 1, 2500, 'efectivo', 'cobrado', current_date, 'privado') returning id into v_ch1;
    insert into public.private_charges (organization_id, provider_id, charge_date, patient_name, procedure_id, service_name, quantity, unit_amount, payment_method, status, charge_type)
      values (v_a, v_pa, current_date, 'Paciente Pendiente QA', v_proc, 'Consulta QA', 1, 1500, 'pendiente', 'pendiente', 'privado') returning id into v_ch2;
    insert into public.private_charges (organization_id, provider_id, charge_date, patient_name, procedure_id, service_name, quantity, unit_amount, payment_method, status, collected_on, charge_type)
      values (v_a, v_pa, current_date, 'Paciente Tarjeta QA', v_proc, 'Consulta QA', 1, 900, 'tarjeta', 'cobrado', current_date, 'privado') returning id into v_ch3;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.void_private_charge(v_ch1, 'Anulación de prueba sin autorización');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-48 · SEG-16 · ATAQUE: la Secretaria no anula un cobro cobrado en efectivo','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-48 · SEG-16 · ATAQUE: la Secretaria no anula un cobro cobrado en efectivo','ok',sqlerrm like 'Un cobro ya cobrado solo lo anula%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000015', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.void_private_charge(v_ch1, 'Anulación de prueba sin autorización');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-49 · SEG-16 · ATAQUE: Operaciones tampoco anula cobros ya cobrados','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-49 · SEG-16 · ATAQUE: Operaciones tampoco anula cobros ya cobrados','ok',sqlerrm like 'Un cobro ya cobrado solo lo anula%','d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-50 · SEG-16 · El cobro en efectivo sigue cobrado tras los ataques','ok',coalesce(((select status from public.private_charges where id = v_ch1) = 'cobrado'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.void_private_charge(v_ch2, 'Cobro pendiente registrado por error');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-51 · SEG-16 · Uso legítimo: la Secretaria anula un cobro pendiente','ok',coalesce(((select status from public.private_charges where id = v_ch2) = 'anulado'), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-51 · SEG-16 · Uso legítimo: la Secretaria anula un cobro pendiente','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.void_private_charge(v_ch1, 'El paciente pidió devolución del efectivo');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-52 · SEG-16 · Uso legítimo: el Médico anula un cobro cobrado','ok',coalesce(((select status from public.private_charges where id = v_ch1) = 'anulado'), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-52 · SEG-16 · Uso legítimo: el Médico anula un cobro cobrado','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.void_private_charge(v_ch3, 'Cobro duplicado con la tarjeta');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-53 · SEG-16 · Uso legítimo: la Administración anula un cobro cobrado','ok',coalesce(((select status from public.private_charges where id = v_ch3) = 'anulado'), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-53 · SEG-16 · Uso legítimo: la Administración anula un cobro cobrado','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_x := public.day_summary(v_pa, current_date);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-54 · SEG-16 · El cuadre muestra las anulaciones del día (cantidad y monto en efectivo)','ok',coalesce(((v_x #>> '{voided_collected,count}')::int = 2 and (v_x #>> '{voided_collected,amount}')::numeric = 3400 and (v_x #>> '{voided_collected,efectivo}')::numeric = 2500), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-54 · SEG-16 · El cuadre muestra las anulaciones del día (cantidad y monto en efectivo)','ok',false,'d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-55 · SEG-17 · No existe public.purge_erroneous_submissions','ok',coalesce((not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'purge_erroneous_submissions')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      execute 'select public.purge_erroneous_submissions(''BORRAR'')';
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-56 · SEG-17 · ATAQUE: el Administrador no puede borrar todos los lotes','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-56 · SEG-17 · ATAQUE: el Administrador no puede borrar todos los lotes','ok',sqlerrm like '%does not exist%','d',left(sqlerrm,160)));
    end;
    
    begin
      perform 1 from pg_proc where proname = 'delete_submission' and pronamespace = 'public'::regnamespace; if not found then raise exception 'falta delete_submission'; end if;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-57 · SEG-17 · Uso legítimo: delete_submission sigue existiendo para lotes erróneos','ok',coalesce((true), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-57 · SEG-17 · Uso legítimo: delete_submission sigue existiendo para lotes erróneos','ok',false,'d',left(sqlerrm,160)));
    end;
    insert into storage.objects (bucket_id, name, owner) values
      ('claim-documents', v_a::text || '/' || v_s1::text || '/qa174-borrador.jpg', '17400000-0000-4000-8000-000000000022'::uuid),
      ('claim-documents', v_a::text || '/' || v_sr::text || '/qa174-radicada.jpg', '17400000-0000-4000-8000-000000000022'::uuid),
      ('claim-documents', v_a::text || '/' || v_s1::text || '/qa174-validada.jpg', '17400000-0000-4000-8000-000000000022'::uuid);
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, bucket, storage_path, file_name, mime_type, size_bytes, uploaded_by)
      values (v_a, 'submission', v_s1, v_l3, v_dt1, 'claim-documents', v_a::text || '/' || v_s1::text || '/qa174-validada.jpg', 'validada.jpg', 'image/jpeg', 100, '17400000-0000-4000-8000-000000000022'::uuid);
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      select case when app.capturer_storage_delete_ok(v_a::text || '/' || v_sr::text || '/qa174-radicada.jpg') then 1 else 0 end into v_n; -- Supabase no deja borrar directo en storage.objects: se evalúa la regla de la política
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-58 · SEG-18 · ATAQUE: la Secretaria no borra soportes de un lote ya radicado','ok',coalesce((v_n = 0 and exists (select 1 from storage.objects where name = v_a::text || '/' || v_sr::text || '/qa174-radicada.jpg')), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-58 · SEG-18 · ATAQUE: la Secretaria no borra soportes de un lote ya radicado','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      select case when app.capturer_storage_delete_ok(v_a::text || '/' || v_s1::text || '/qa174-validada.jpg') then 1 else 0 end into v_n; -- Supabase no deja borrar directo en storage.objects: se evalúa la regla de la política
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-59 · SEG-18 · ATAQUE: la Secretaria no borra el archivo de una reclamación ya validada','ok',coalesce((v_n = 0 and exists (select 1 from storage.objects where name = v_a::text || '/' || v_s1::text || '/qa174-validada.jpg')), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-59 · SEG-18 · ATAQUE: la Secretaria no borra el archivo de una reclamación ya validada','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      select case when app.capturer_storage_delete_ok(v_a::text || '/' || v_s1::text || '/qa174-borrador.jpg') then 1 else 0 end into v_n; -- Supabase no deja borrar directo en storage.objects: se evalúa la regla de la política
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-60 · SEG-18 · Uso legítimo: la Secretaria borra su archivo de un lote en borrador','ok',coalesce((v_n = 1), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-60 · SEG-18 · Uso legítimo: la Secretaria borra su archivo de un lote en borrador','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      select case when app.can(v_a, array['super_admin','admin']) then 1 else 0 end into v_n; -- Supabase no deja borrar directo en storage.objects: se evalúa la regla de la política (admin)
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-61 · SEG-18 · Uso legítimo: el Administrador sí borra un soporte de un lote radicado (con control)','ok',coalesce((v_n = 1), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-61 · SEG-18 · Uso legítimo: el Administrador sí borra un soporte de un lote radicado (con control)','ok',false,'d',left(sqlerrm,160)));
    end;
    insert into public.patients (organization_id, full_name, doc_number, phone) values (v_a, 'Paciente Bitácora QA', '40200001741', '8095550174') returning id into v_pat;
    perform app.clinical_log(v_a, v_pat, null, 'ver', 'QA 1');
    perform app.clinical_log(v_a, v_pat, null, 'ver', 'QA 2');
    insert into public.clinical_access_log (id, user_id, organization_id, patient_id, action, detail, prev_hash, hash) overriding system value
      values (-5, '17400000-0000-4000-8000-000000000011'::uuid, v_a, v_pat, 'ver', 'QA registro con número fuera de orden', '', '');
    v_log := (select max(id) from public.clinical_access_log);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-62 · SEG-19 · El registro con número fuera de orden recibió un número nuevo dentro del candado','ok',coalesce((not exists (select 1 from public.clinical_access_log where id = -5) and (select count(*) from public.clinical_access_log where detail like 'QA registro con número%') = 1), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-63 · SEG-19 · La verificación de la cadena sigue en ok con registros fuera de orden','ok',coalesce(((public.clinical_verify_log() ->> 'ok')::boolean), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-64 · SEG-19 · El último registro tiene el número más alto y encadena con el anterior','ok',coalesce(((select prev_hash from public.clinical_access_log where id = v_log) = (select hash from public.clinical_access_log where id < v_log order by id desc limit 1)), false),'d',(null)::text));
    insert into public.patient_notice_settings (organization_id, balance_auto, balance_min, balance_every_days) values (v_a, true, 0, 7) on conflict (organization_id) do update set balance_auto = true, balance_min = 0;
    insert into public.patients (organization_id, full_name, phone) values (v_a, 'Juan Gemelo', '8095551111'), (v_a, 'Juan Gemelo', '8095552222');
    insert into public.patients (organization_id, full_name, phone) values (v_a, 'Maria Unica', '8095553333');
    insert into public.patients (organization_id, full_name, doc_number, phone) values (v_a, 'Pedro Con Cedula', '40200001749', '8095554444');
    insert into public.private_charges (organization_id, provider_id, charge_date, patient_name, procedure_id, service_name, quantity, unit_amount, payment_method, status, charge_type)
      values (v_a, v_pa, current_date - 5, 'Juan Gemelo', v_proc, 'Consulta QA', 1, 1000, 'pendiente', 'pendiente', 'privado'),
             (v_a, v_pa, current_date - 5, 'Maria Unica', v_proc, 'Consulta QA', 1, 1100, 'pendiente', 'pendiente', 'privado');
    insert into public.private_charges (organization_id, provider_id, charge_date, patient_name, patient_doc, procedure_id, service_name, quantity, unit_amount, payment_method, status, charge_type)
      values (v_a, v_pa, current_date - 5, 'Pedro Con Cedula', '402-0000174-9', v_proc, 'Consulta QA', 1, 1200, 'pendiente', 'pendiente', 'privado');
    v_n := public.generate_balance_reminders(v_a);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-65 · SEG-20 · ATAQUE: no se genera el aviso automático de saldo para dos «Juan Gemelo» sin cédula','ok',coalesce((not exists (select 1 from public.message_queue where organization_id = v_a and kind = 'cobro_pendiente' and subject = 'Saldo pendiente · N:juan gemelo')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-66 · SEG-20 · Uso legítimo: sí se genera para un nombre sin homónimos','ok',coalesce((exists (select 1 from public.message_queue where organization_id = v_a and kind = 'cobro_pendiente' and subject = 'Saldo pendiente · N:maria unica' and to_phone = '8095553333')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-67 · SEG-20 · Uso legítimo: sí se genera para un paciente con cédula','ok',coalesce((exists (select 1 from public.message_queue where organization_id = v_a and kind = 'cobro_pendiente' and subject = 'Saldo pendiente · 40200001749' and to_phone = '8095554444')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.queue_balance_reminder(v_pa, null, 'Juan Gemelo');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-68 · SEG-20 · ATAQUE: el recordatorio manual tampoco adivina entre homónimos','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-68 · SEG-20 · ATAQUE: el recordatorio manual tampoco adivina entre homónimos','ok',sqlerrm like 'Hay más de un paciente con el nombre%','d',left(sqlerrm,160)));
    end;
    insert into public.patients (organization_id, full_name, doc_number, phone) values (v_a, 'Luis Manual', '40200001748', '8095556666');
    insert into public.private_charges (organization_id, provider_id, charge_date, patient_name, patient_doc, procedure_id, service_name, quantity, unit_amount, payment_method, status, charge_type)
      values (v_a, v_pa, current_date - 2, 'Luis Manual', '402-0000174-8', v_proc, 'Consulta QA', 1, 800, 'pendiente', 'pendiente', 'privado');
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      v_x := to_jsonb(public.queue_balance_reminder(v_pa, '402-0000174-8', 'Luis Manual'));
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-69 · SEG-20 · Uso legítimo: el recordatorio manual de un paciente sin homónimos','ok',coalesce((exists (select 1 from public.message_queue where id::text = (v_x #>> '{}') and to_phone = '8095556666')), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-69 · SEG-20 · Uso legítimo: el recordatorio manual de un paciente sin homónimos','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform app.bootstrap_super_admin('qa@sofa.test', 'x');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-70 · SEG-26 · ATAQUE: un usuario con sesión no ejecuta app.bootstrap_super_admin','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-70 · SEG-26 · ATAQUE: un usuario con sesión no ejecuta app.bootstrap_super_admin','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform app.distribute_allocation(gen_random_uuid(), 'x');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-71 · SEG-26 · ATAQUE: un usuario con sesión no ejecuta app.distribute_allocation','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-71 · SEG-26 · ATAQUE: un usuario con sesión no ejecuta app.distribute_allocation','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform app.claim_set_status(v_l1, 'validada', 'x');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-72 · SEG-26 · ATAQUE: un usuario con sesión no ejecuta app.claim_set_status','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-72 · SEG-26 · ATAQUE: un usuario con sesión no ejecuta app.claim_set_status','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'anon', true); perform set_config('request.jwt.claims', '', true);
    begin
      perform app.can(v_a, array['admin']);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-73 · SEG-26 · ATAQUE: sin sesión (anon) no ejecuta app.can','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-73 · SEG-26 · ATAQUE: sin sesión (anon) no ejecuta app.can','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-74 · SEG-26 · Las funciones de políticas siguen con EXECUTE para authenticated (can, visible_org_ids, is_staff, clinical_role, capturer_line_ok)','ok',coalesce((has_function_privilege('authenticated','app.can(uuid,text[])','execute') and has_function_privilege('authenticated','app.visible_org_ids()','execute') and has_function_privilege('authenticated','app.is_staff(text[])','execute') and has_function_privilege('authenticated','app.clinical_role(uuid)','execute') and has_function_privilege('authenticated','app.capturer_line_ok(uuid)','execute')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-75 · SEG-26 · Solo quedan abiertas a authenticated las funciones conservadas del esquema app (menos de 50)','ok',coalesce(((select count(*) from pg_proc where pronamespace = 'app'::regnamespace and prokind = 'f' and proname not like 'qa\_%' and has_function_privilege('authenticated', oid, 'execute')) < 50), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-76 · SEG-26 · anon no ejecuta ninguna función del esquema app (incluidas las de prueba)','ok',coalesce(((select count(*) from pg_proc where pronamespace = 'app'::regnamespace and prokind = 'f' and has_function_privilege('anon', oid, 'execute')) = 0), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      select count(*) into v_n from public.patients where organization_id = v_a;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-77 · SEG-26 · Uso legítimo: el Médico lee sus pacientes (las políticas usan funciones de app)','ok',coalesce((v_n >= 1), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-77 · SEG-26 · Uso legítimo: el Médico lee sus pacientes (las políticas usan funciones de app)','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      select count(*) into v_n from public.submissions; select count(*) into v_n from public.v_claim_dossier;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-78 · SEG-26 · Uso legítimo: el Super Admin lee reclamaciones, lotes y la vista del expediente','ok',coalesce((v_n >= 1), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-78 · SEG-26 · Uso legítimo: el Super Admin lee reclamaciones, lotes y la vista del expediente','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      select count(*) into v_n from public.submissions where provider_id = v_pa;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-79 · SEG-26 · Uso legítimo: la Secretaria lee sus reclamaciones (política de Secretaria)','ok',coalesce((v_n >= 1), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-79 · SEG-26 · Uso legítimo: la Secretaria lee sus reclamaciones (política de Secretaria)','ok',false,'d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-80 · SEG-26 · pg_net cerrado a authenticated (si existe)','ok',coalesce((not exists (select 1 from pg_namespace where nspname = 'net') or not has_schema_privilege('authenticated', 'net', 'usage') or (select pg_get_userbyid(nspowner) from pg_namespace where nspname = 'net') = 'supabase_admin'), false),'d',(case when exists (select 1 from pg_namespace where nspname = 'net') and has_schema_privilege('authenticated', 'net', 'usage') then 'Limitación de Supabase: el esquema net es de supabase_admin y no se puede cerrar desde el SQL Editor. Verifique en Settings › API que solo se exponen public y graphql_public.' else null end)));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      truncate public.patients;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-81 · SEG-27 · ATAQUE: un usuario con sesión no vacía una tabla (TRUNCATE)','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-81 · SEG-27 · ATAQUE: un usuario con sesión no vacía una tabla (TRUNCATE)','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      create trigger qa_x before insert on public.patients for each row execute function app.audit_log_protect();
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-82 · SEG-27 · ATAQUE: un usuario con sesión no crea disparadores en tablas ajenas','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-82 · SEG-27 · ATAQUE: un usuario con sesión no crea disparadores en tablas ajenas','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-83 · SEG-27 · Nadie con sesión (anon/authenticated) conserva TRUNCATE, TRIGGER ni REFERENCES en tablas de public','ok',coalesce(((select count(*) from pg_class c cross join (values ('anon'),('authenticated')) r(rol) cross join (values ('TRUNCATE'),('TRIGGER'),('REFERENCES')) p(priv) where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p') and has_table_privilege(r.rol, c.oid, p.priv)) = 0), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      delete from public.audit_log where true;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-84 · SEG-27 · ATAQUE: ni el Super Admin borra de audit_log','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-84 · SEG-27 · ATAQUE: ni el Super Admin borra de audit_log','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    
    begin
      update public.audit_log set operation = 'X' where id = (select min(id) from public.audit_log);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-85 · SEG-27 · ATAQUE: ni siquiera el dueño modifica audit_log (disparador)','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-85 · SEG-27 · ATAQUE: ni siquiera el dueño modifica audit_log (disparador)','ok',sqlerrm like 'La bitácora de auditoría no se modifica%','d',left(sqlerrm,160)));
    end;
    
    begin
      delete from public.audit_log where id = (select min(id) from public.audit_log);
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-86 · SEG-27 · ATAQUE: ni el dueño borra de audit_log (disparador)','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-86 · SEG-27 · ATAQUE: ni el dueño borra de audit_log (disparador)','ok',sqlerrm like 'La bitácora de auditoría no se modifica%','d',left(sqlerrm,160)));
    end;
    
    begin
      truncate public.audit_log;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-87 · SEG-27 · ATAQUE: ni el dueño vacía audit_log (TRUNCATE)','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-87 · SEG-27 · ATAQUE: ni el dueño vacía audit_log (TRUNCATE)','ok',sqlerrm like 'La bitácora de auditoría no se modifica%','d',left(sqlerrm,160)));
    end;
    v_n := (select count(*) from public.audit_log);
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.providers set specialty = 'Cardiología QA2' where id = v_pa;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-88 · SEG-27 · Uso legítimo: un cambio normal sigue dejando su registro en audit_log','ok',coalesce(((select count(*) from public.audit_log) > v_n), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-88 · SEG-27 · Uso legítimo: un cambio normal sigue dejando su registro en audit_log','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true); perform set_config('request.jwt.claims', json_build_object('sub', '17400000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      select count(*) into v_n from public.audit_log;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-89 · SEG-27 · Uso legítimo: el Super Admin sigue leyendo audit_log','ok',coalesce((v_n >= 1), false),'d',(null)::text));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-89 · SEG-27 · Uso legítimo: el Super Admin sigue leyendo audit_log','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'anon', true); perform set_config('request.jwt.claims', '', true);
    begin
      perform count(*) from public.v_claims;
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-90 · SEG-28 · ATAQUE: sin sesión (anon) no lee la vista de reclamaciones','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-90 · SEG-28 · ATAQUE: sin sesión (anon) no lee la vista de reclamaciones','ok',sqlerrm like '%permission denied%','d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-91 · SEG-28 · anon no tiene ningún permiso sobre las vistas de public','ok',coalesce(((select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('v','m') and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert') or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'))) = 0), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-92 · SEG-28 · Las vistas siguen legibles para authenticated','ok',coalesce(((select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'v' and not has_table_privilege('authenticated', c.oid, 'select')) = 0), false),'d',(null)::text));
    perform set_config('role', 'anon', true); perform set_config('request.jwt.claims', '', true);
    begin
      perform public.portal_view('token-que-no-existe');
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-93 · SEG-28 · Uso legítimo: anon sigue llegando a portal_view (rechaza el enlace inválido, no el permiso)','ok',false,'d','Se permitió'));
    exception when others then
      perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-93 · SEG-28 · Uso legítimo: anon sigue llegando a portal_view (rechaza el enlace inválido, no el permiso)','ok',sqlerrm like 'Enlace no válido%','d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-94 · Registro · La migración 174 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '174')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','B2-95 · Registro · Triggers e índices nuevos presentes','ok',coalesce(((select count(*) from pg_trigger where tgname in ('submissions_ecf_cols_guard','line_document_checks_manual_guard','audit_log_protect','audit_log_protect_trunc') and not tgisinternal) = 4 and exists (select 1 from pg_indexes where indexname = 'submissions_org_ecf_ncf_uidx') and exists (select 1 from pg_indexes where indexname in ('sofa_invoices_ncf_uidx','sofa_invoices_ncf_uq'))), false),'d',(null)::text));
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
revoke all on function app.qa_run_tests_blindaje_2() from public, anon, authenticated;
