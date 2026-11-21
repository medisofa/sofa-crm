-- 253 · Suite de la 252 (clínica: cada médico ve solo sus reclamaciones, glosas, pagos y documentos). Se deshace sola.
-- Ya aplicado en producción (2026-11-20): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_clinica_reclamaciones();
create or replace function app.qa_run_tests_clinica_reclamaciones()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_n int; v_m int; v_x jsonb;
  oC  constant uuid := 'b9000000-0000-4000-8000-0000000000d1';
  oS  constant uuid := 'b9000000-0000-4000-8000-0000000000d2';
  pC1 constant uuid := 'c9000000-0000-4000-8000-0000000000d1';
  pC2 constant uuid := 'c9000000-0000-4000-8000-0000000000d2';
  pS  constant uuid := 'c9000000-0000-4000-8000-0000000000d3';
  s1 constant uuid := 'f9000000-0000-4000-8000-0000000000d1';
  s2 constant uuid := 'f9000000-0000-4000-8000-0000000000d2';
  sS constant uuid := 'f9000000-0000-4000-8000-0000000000d3';
  l1 constant uuid := 'f9000000-0000-4000-8000-0000000000e1';
  l2 constant uuid := 'f9000000-0000-4000-8000-0000000000e2';
  pay1 constant uuid := 'f9000000-0000-4000-8000-0000000000f1';
  pay2 constant uuid := 'f9000000-0000-4000-8000-0000000000f2';
  uC1 constant text := 'a9000000-0000-4000-8000-0000000000d1';
  uC2 constant text := 'a9000000-0000-4000-8000-0000000000d2';
  uDir constant text := 'a9000000-0000-4000-8000-0000000000d3';
  uS  constant text := 'a9000000-0000-4000-8000-0000000000d4';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_ars uuid := (select id from public.ars where is_active order by name limit 1);
  v_proc uuid := (select id from public.procedures limit 1);
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email) values (uC1::uuid,'qa.cr.c1@sofa.test'),(uC2::uuid,'qa.cr.c2@sofa.test'),(uDir::uuid,'qa.cr.dir@sofa.test'),(uS::uuid,'qa.cr.s@sofa.test');
    insert into public.profiles (id, full_name) select id, email from auth.users where email like 'qa.cr.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (oC,'client',v_op,'QA CR Clinica','00000000191','Clínica','activo',current_date-90,'8095550061'),
      (oS,'client',v_op,'QA CR Solo','00000000192','Consultorio','activo',current_date-90,'8095550062');
    insert into public.providers (id, organization_id, full_name) values (pC1,oC,'Dr. CR Uno'),(pC2,oC,'Dra. CR Dos'),(pS,oS,'Dr. CR Solo');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (oC,uC1::uuid,'client'),(oC,uC2::uuid,'client'),(oC,uDir::uuid,'client'),(oS,uS::uuid,'client');
    update public.organization_users set sees_all_providers = true where organization_id = oC and user_id = uDir::uuid;
    update public.providers set user_id = case id when pC1 then uC1::uuid when pC2 then uC2::uuid end where id in (pC1, pC2);
    insert into public.submissions (id, organization_id, provider_id, ars_id, period) values
      (s1,oC,pC1,v_ars,date_trunc('month', current_date)::date),(s2,oC,pC2,v_ars,date_trunc('month', current_date)::date),(sS,oS,pS,v_ars,date_trunc('month', current_date)::date);
    insert into public.service_lines (id, submission_id, organization_id, service_date, patient_name, procedure_id, unit_amount) values
      (l1,s1,oC,current_date-3,'Paciente CR Uno',v_proc,1000),(l2,s2,oC,current_date-3,'Paciente CR Dos',v_proc,2000);
    perform set_config('app.status_change', 'on', true);
    update public.submissions set status = 'radicada', submitted_on = current_date, ars_receipt_number = 'QA-CR-' || right(id::text, 2),
           ncf = case id when s1 then 'E310000000011' when s2 then 'E310000000012' else 'E310000000013' end, ecf_security_code = 'ABC123', ecf_dgii_status = 'aceptado' where id in (s1, s2, sS);
    perform set_config('app.status_change', '', true);
    insert into public.glosas (organization_id, submission_id, notified_on, appeal_deadline) values (oC,s1,current_date,current_date+30),(oC,s2,current_date,current_date+30);
    insert into public.payments (id, organization_id, ars_id, paid_on, amount, reference) values (pay1,oC,v_ars,current_date,1000,'QA-CR-1'),(pay2,oC,v_ars,current_date,2000,'QA-CR-2');
    insert into public.payment_allocations (payment_id, organization_id, submission_id, amount) values (pay1,oC,s1,1000),(pay2,oC,s2,2000);
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, storage_path, file_name, mime_type, size_bytes) values
      (oC,'service_line',l1,l1,oC::text || '/qa/cr1.pdf','cr1.pdf','application/pdf',10),(oC,'service_line',l2,l2,oC::text || '/qa/cr2.pdf','cr2.pdf','application/pdf',10);

    -- Dr. C1 (médico de clínica)
    perform set_config('request.jwt.claims', json_build_object('sub',uC1,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    select count(*) into v_n from public.submissions where id in (s1,s2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-01 · Ve solo sus radicaciones','ok',v_n = 1,'d',v_n || ' visibles'));
    select count(*) into v_n from public.service_lines where id in (l1,l2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-02 · Ve solo sus reclamaciones (líneas)','ok',v_n = 1,'d',v_n || ' visibles'));
    select count(*) into v_n from public.glosas where submission_id in (s1,s2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-03 · Ve solo sus glosas','ok',v_n = 1,'d',v_n || ' visibles'));
    select count(*) into v_n from public.payments where id in (pay1,pay2);
    select count(*) into v_m from public.payment_allocations where payment_id in (pay1,pay2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-04 · Ve solo los pagos de ARS que incluyen sus radicaciones','ok',v_n = 1 and v_m = 1,'d',v_n || ' pagos, ' || v_m || ' asignaciones'));
    select count(*) into v_n from public.documents where service_line_id in (l1,l2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-05 · Ve solo los documentos de sus reclamaciones','ok',v_n = 1,'d',v_n || ' visibles'));
    begin perform public.remove_service_line(l2, 'Prueba QA de acceso');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-06 · No puede anular una reclamación de su colega','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-06 · No puede anular una reclamación de su colega','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    begin perform public.preaudit_submission(s2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-07 · No abre la preauditoría del lote de su colega','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-07 · No abre la preauditoría del lote de su colega','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    begin perform public.glosa_response_board(oC);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-08 · El tablero de glosas de toda la clínica queda para el director','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-08 · El tablero de glosas de toda la clínica queda para el director','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    begin
      insert into public.submissions (organization_id, provider_id, ars_id, period, status) values (oC, pC2, v_ars, date_trunc('month', current_date)::date, 'borrador');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-09 · No crea radicaciones a nombre de su colega','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-09 · No crea radicaciones a nombre de su colega','ok',true,'d',left(sqlerrm,120))); end;
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    -- Directora de la clínica
    perform set_config('request.jwt.claims', json_build_object('sub',uDir,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    select count(*) into v_n from public.service_lines where id in (l1,l2);
    select count(*) into v_m from public.payments where id in (pay1,pay2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-10 · La directora ve las reclamaciones y pagos de toda la clínica','ok',v_n = 2 and v_m = 2,'d',v_n || ' líneas, ' || v_m || ' pagos'));
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    -- Médico de un consultorio de un solo médico: sin cambios
    perform set_config('request.jwt.claims', json_build_object('sub',uS,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    select count(*) into v_n from public.submissions where id = sS;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CR-11 · Consultorio de un solo médico: sigue viendo sus radicaciones','ok',v_n = 1,'d',v_n || ' visibles'));
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('role', 'none', true);
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
revoke execute on function app.qa_run_tests_clinica_reclamaciones() from public, anon, authenticated;
