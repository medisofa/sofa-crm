-- SOFA · 5.41.0 · Duplicados: Administración ejecuta la exclusión solicitada quitando la reclamación del lote.
-- Ya aplicado en producción con mcp__Supabase__apply_migration (2026-11-16), en dos partes:
--   1) duplicate_exclusion_remove_from_lot: la función y la suite.
--   2) retire_cancel_design_and_hospital_notes: el bloque «Retiro del diseño anterior» de este archivo
--      (ver 20261116_retire_cancel_design_and_hospital_notes.sql). Suite en producción: 15 de 15.
--
-- Estado neto. Entre el 13 y el 16/11/2026 se aplicaron pasos intermedios que este archivo reemplaza:
--   · SQL directo, registrado solo en app.schema_migrations como 230–233: cancel_duplicate_line,
--     la vista v_canceled_duplicates y el estado 'anulada_duplicado'. Se retiran aquí: una reclamación
--     «anulada» seguía en su lote y app.sync_claims_from_submission la habría radicado.
--   · duplicate_exclusion_execute y duplicate_cancel_disable_until_lot_audit (historial de Supabase).
-- De aquellos pasos queda vigente un único cambio: claim_duplicate_candidates también descarta, en el
-- lado principal del par, las reclamaciones 'cerrada' y 'devuelta'.
--
-- Regla: Operaciones y Facturación SOLICITAN (request_claim_duplicate_exclusion, sin cambios).
-- Administración y Super Admin EJECUTAN: la reclamación excluida sale del lote con
-- public.remove_service_line (lote editable, sin pagos ni glosas, motivo en la bitácora del cliente y
-- fila completa en audit_log) y la solicitud pasa a 'ejecutada'.
-- La transacción solo se confirma si app.qa_run_tests_exclusion_duplicados() pasa completa; la suite
-- crea sus datos y los deshace, no deja nada en producción.

alter table app.claim_duplicate_resolution_requests
  add column if not exists executed_by uuid,
  add column if not exists executed_at timestamptz;
alter table app.claim_duplicate_resolution_requests
  drop constraint if exists claim_duplicate_resolution_requests_status_check;
alter table app.claim_duplicate_resolution_requests
  add constraint claim_duplicate_resolution_requests_status_check check (status in ('pendiente','ejecutada'));
create index if not exists claim_duplicate_resolution_requests_org_idx
  on app.claim_duplicate_resolution_requests (organization_id);

-- Retiro del diseño anterior (anulación por estado).
drop view if exists public.v_canceled_duplicates;
drop function if exists public.cancel_duplicate_line(uuid, uuid);
drop function if exists app.qa_run_tests_anulacion_blindaje();
do $$
begin
  if exists (select 1 from public.service_lines where claim_status = 'anulada_duplicado') then
    raise exception 'Hay reclamaciones en estado anulada_duplicado. Revíselas antes de retirar el estado.';
  end if;
  delete from public.claim_statuses where code = 'anulada_duplicado';
end $$;

create or replace function public.execute_claim_duplicate_exclusion(p_request uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  r app.claim_duplicate_resolution_requests;
  v_keep_folio text; v_ex_folio text; v_ex_status text; v_review bigint; v_removed jsonb;
begin
  if auth.uid() is null or not app.is_active_user()
     or exists (select 1 from public.support_view_active()) then
    raise exception 'Inicie sesión con un perfil autorizado y salga del modo soporte.' using errcode = '42501';
  end if;

  select * into r from app.claim_duplicate_resolution_requests where id = p_request for update;
  -- Mismo mensaje si no existe o si no es de una organización suya: no se revela cuál de las dos.
  if not found or not app.can(r.organization_id, array['super_admin','admin','operations','billing']) then
    raise exception 'La solicitud de exclusión no existe o no está disponible. Vuelva a comprobar la coincidencia.' using errcode = 'P0002';
  end if;
  if not app.can(r.organization_id, array['super_admin','admin']) then
    raise exception 'Solo Administración o Super Admin pueden ejecutar la exclusión de un duplicado. Pida a un Administrador que la ejecute desde «Gestionar duplicado».'
      using errcode = '42501';
  end if;
  if r.status <> 'pendiente' then
    raise exception 'Esta solicitud de exclusión ya fue ejecutada. Vuelva a comprobar la coincidencia.' using errcode = '22023';
  end if;

  select claim_folio into v_keep_folio from public.service_lines
   where id = r.keep_line and organization_id = r.organization_id;
  if v_keep_folio is null then
    raise exception 'La reclamación que la solicitud pedía conservar ya no existe. No se quita la otra: revise el par antes de continuar.' using errcode = '22023';
  end if;
  select claim_folio, claim_status into v_ex_folio, v_ex_status from public.service_lines
   where id = r.exclude_line and organization_id = r.organization_id;
  if v_ex_folio is null then
    raise exception 'La reclamación a excluir ya no está en el lote: alguien la quitó antes. Vuelva a comprobar la coincidencia.' using errcode = '22023';
  end if;

  select id into v_review from public.claim_duplicate_reviews
   where line_a = r.line_a and line_b = r.line_b and decision = 'duplicado_confirmado';
  if v_review is null then
    raise exception 'El par ya no está marcado como «Duplicado confirmado». Revise la decisión antes de ejecutar la exclusión.' using errcode = '22023';
  end if;

  if not (v_ex_status = any (app.claim_capture_states())) then
    raise exception 'La reclamación % está en «%»: ya salió de captura y no se quita del lote. Devuélvala a «Capturada» desde su ficha y vuelva a ejecutar la exclusión.',
      v_ex_folio, replace(v_ex_status, '_', ' ') using errcode = '23514';
  end if;

  -- Quita la reclamación por la vía ya existente: valida lote editable, pagos, glosas y reenvíos,
  -- deja la actividad con el motivo y la fila completa en audit_log (disparador de auditoría).
  v_removed := public.remove_service_line(r.exclude_line,
    'Duplicado confirmado de ' || v_keep_folio || '. ' || r.reason);

  update app.claim_duplicate_resolution_requests
     set status = 'ejecutada', executed_by = auth.uid(), executed_at = now()
   where id = r.id;

  insert into public.audit_log(user_id, organization_id, table_name, record_id, operation, new_values)
  values (auth.uid(), r.organization_id, 'claim_duplicate_resolution_requests', r.id::text,
    'EXCLUSION_DUPLICADO_EJECUTADA',
    jsonb_build_object('request_id', r.id, 'review_id', v_review, 'requested_by', r.created_by,
      'keep_line', r.keep_line, 'keep_folio', v_keep_folio,
      'exclude_line', r.exclude_line, 'exclude_folio', v_ex_folio,
      'submission_folio', v_removed->>'submission_folio', 'documents', v_removed->'documents'));

  return jsonb_build_object('ok', true, 'status', 'ejecutada', 'request_id', r.id,
    'excluded_folio', v_ex_folio, 'kept_folio', v_keep_folio,
    'submission_folio', v_removed->>'submission_folio', 'files', v_removed->'files',
    'message', 'Reclamación ' || v_ex_folio || ' quitada del lote ' || coalesce(v_removed->>'submission_folio', '') || ' por duplicado. Se conserva ' || v_keep_folio || '.');
end
$function$;

revoke all on function public.execute_claim_duplicate_exclusion(uuid) from public, anon;
grant execute on function public.execute_claim_duplicate_exclusion(uuid) to authenticated, service_role;

create or replace function app.qa_run_tests_exclusion_duplicados()
returns table(prueba text, resultado text, detalle text)
language plpgsql
set search_path = ''
as $suite$
declare
  r_id text[] := '{}'; r_ok boolean[] := '{}'; r_det text[] := '{}';
  v_ok boolean; v_det text; v_n int; v_m int; v_txt text; v_res jsonb; v_req uuid; v_req2 uuid; v_by uuid;
  u_adm uuid := 'a0000000-0000-0000-0000-000000000233';
  u_bil uuid := 'b0000000-0000-0000-0000-000000000233';
  u_out uuid := 'c0000000-0000-0000-0000-000000000233';
  org_id uuid := 'd0000000-0000-0000-0000-000000000233';
  ars_id uuid := 'e0000000-0000-0000-0000-000000000233';
  sub_id uuid := 'f0000000-0000-0000-0000-000000000233';
  l_a uuid := '10000000-0000-0000-0000-000000000233';
  l_b uuid := '20000000-0000-0000-0000-000000000233';
  l_c uuid := '30000000-0000-0000-0000-000000000233';
  proc_id uuid := '40000000-0000-0000-0000-000000000233';
  prov_id uuid := '50000000-0000-0000-0000-000000000233';
  v_operator uuid := '00000000-0000-4000-8000-000000000001';
  i int; v_fail int := 0;
begin
  v_ok := not has_function_privilege('anon','public.execute_claim_duplicate_exclusion(uuid)','execute')
      and has_function_privilege('authenticated','public.execute_claim_duplicate_exclusion(uuid)','execute');
  r_id := r_id||'ED-01 solo usuarios con sesión pueden llamar la función'::text; r_ok := r_ok||v_ok; r_det := r_det||''::text;

  v_ok := to_regprocedure('public.cancel_duplicate_line(uuid,uuid)') is null
      and to_regclass('public.v_canceled_duplicates') is null
      and not exists (select 1 from public.claim_statuses where code = 'anulada_duplicado');
  r_id := r_id||'ED-02 el diseño anterior (anulación por estado) quedó retirado'::text; r_ok := r_ok||v_ok; r_det := r_det||''::text;

  begin
    insert into auth.users(id,email,role) values
      (u_adm,'qa233_admin@test.local','authenticated'),
      (u_bil,'qa233_billing@test.local','authenticated'),
      (u_out,'qa233_ajeno@test.local','authenticated');
    insert into public.profiles(id,full_name) values
      (u_adm,'QA233 Admin'),(u_bil,'QA233 Facturación'),(u_out,'QA233 Ajeno')
    on conflict(id) do update set full_name=excluded.full_name;
    insert into public.organizations(id,kind,operator_id,legal_name,tax_id)
      values (org_id,'client',v_operator,'QA233 Clínica Test','000000233');
    insert into public.organization_users(organization_id,user_id,role_code,is_active) values
      (v_operator,u_adm,'admin',true),(v_operator,u_bil,'billing',true);
    insert into public.staff_client_access(user_id,client_org_id) values (u_adm,org_id),(u_bil,org_id);
    insert into public.ars(id,code,name) values (ars_id,'qa233','QA233 ARS Test');
    insert into public.procedures(id,description,service_type_code) values (proc_id,'Consulta QA233','consulta');
    insert into public.providers(id,organization_id,full_name) values (prov_id,org_id,'Dr. QA233 Test');
    insert into public.submissions(id,organization_id,provider_id,ars_id,period,status,created_by)
      values (sub_id,org_id,prov_id,ars_id,'2026-10-01','borrador',u_adm);

    perform set_config('request.jwt.claims', json_build_object('sub',u_adm,'role','authenticated','aal','aal2')::text, true);
    perform set_config('request.jwt.claim.sub', u_adm::text, true);

    insert into public.service_lines(id,submission_id,organization_id,claim_folio,
      patient_name,member_number,service_date,authorization_number,procedure_id,quantity,unit_amount,claim_status) values
      (l_a,sub_id,org_id,'REC-QA233-000001','Paciente QA233','099900233','2026-10-15','AUTH233001',proc_id,1,500,'capturada'),
      (l_b,sub_id,org_id,'REC-QA233-000002','Paciente QA233','099900233','2026-10-15','AUTH233001',proc_id,1,500,'capturada'),
      (l_c,sub_id,org_id,'REC-QA233-000003','Paciente QA233','099900233','2026-10-15','AUTH233001',proc_id,1,500,'capturada');

    perform set_config('request.jwt.claims','',true);
    perform set_config('request.jwt.claim.sub','',true);
    perform set_config('app.claim_change','on',true);
    update public.service_lines set claim_status='capturada' where id in (l_a,l_b,l_c);
    perform set_config('app.claim_change','',true);
    perform set_config('request.jwt.claims', json_build_object('sub',u_adm,'role','authenticated','aal','aal2')::text, true);
    perform set_config('request.jwt.claim.sub', u_adm::text, true);

    insert into public.claim_duplicate_reviews(line_a,line_b,organization_id,decision,reason,reviewed_by,reviewed_at) values
      (l_a,l_b,org_id,'duplicado_confirmado','QA233 par a-b',u_adm,now()),
      (l_a,l_c,org_id,'duplicado_confirmado','QA233 par a-c',u_adm,now());

    -- Facturación solicita por la vía real: conservar A, excluir B.
    perform set_config('request.jwt.claims', json_build_object('sub',u_bil,'role','authenticated','aal','aal2')::text, true);
    perform set_config('request.jwt.claim.sub', u_bil::text, true);
    begin
      v_res := public.request_claim_duplicate_exclusion(l_a, l_b, l_a, 'QA233 se conserva la A por evidencia');
      v_req := (v_res->>'id')::uuid;
      v_ok := v_res->>'status'='pendiente'; v_det := left(v_res::text,160);
    exception when others then v_ok := false; v_det := left(sqlerrm,160);
    end;
    r_id := r_id||'ED-03 Facturación puede solicitar la exclusión'::text; r_ok := r_ok||v_ok; r_det := r_det||v_det;

    begin
      perform public.execute_claim_duplicate_exclusion(v_req);
      v_ok := false; v_det := 'No lanzó error';
    exception when others then
      v_ok := sqlerrm like 'Solo Administración o Super Admin%'; v_det := left(sqlerrm,160);
    end;
    r_id := r_id||'ED-04 Facturación no puede ejecutar'::text; r_ok := r_ok||v_ok; r_det := r_det||v_det;

    perform set_config('request.jwt.claims', json_build_object('sub',u_out,'role','authenticated','aal','aal2')::text, true);
    perform set_config('request.jwt.claim.sub', u_out::text, true);
    begin
      perform public.execute_claim_duplicate_exclusion(v_req);
      v_ok := false; v_det := 'No lanzó error';
    exception when others then
      v_ok := sqlerrm like 'La solicitud de exclusión no existe o no está disponible%'; v_det := left(sqlerrm,160);
    end;
    r_id := r_id||'ED-05 un usuario ajeno ni ejecuta ni se entera de que existe'::text; r_ok := r_ok||v_ok; r_det := r_det||v_det;

    perform set_config('request.jwt.claims', json_build_object('sub',u_adm,'role','authenticated','aal','aal2')::text, true);
    perform set_config('request.jwt.claim.sub', u_adm::text, true);

    begin
      perform public.execute_claim_duplicate_exclusion('99999999-0000-0000-0000-000000000233');
      v_ok := false; v_det := 'No lanzó error';
    exception when others then
      v_ok := sqlerrm like 'La solicitud de exclusión no existe o no está disponible%'; v_det := left(sqlerrm,160);
    end;
    r_id := r_id||'ED-06 una solicitud inexistente se rechaza'::text; r_ok := r_ok||v_ok; r_det := r_det||v_det;

    select count(*) into v_n from public.service_lines where id in (l_a,l_b,l_c);
    r_id := r_id||'ED-07 tras los rechazos siguen las tres reclamaciones'::text; r_ok := r_ok||(v_n=3); r_det := r_det||('reclamaciones='||v_n);

    -- Segunda solicitud (A-C) cuya excluida ya salió de captura.
    begin
      v_res := public.request_claim_duplicate_exclusion(l_a, l_c, l_a, 'QA233 se conserva la A, la C es repetida');
      v_req2 := (v_res->>'id')::uuid;
      perform set_config('app.claim_change','on',true);
      update public.service_lines set claim_status='retirada' where id=l_c;
      perform set_config('app.claim_change','',true);
      perform public.execute_claim_duplicate_exclusion(v_req2);
      v_ok := false; v_det := 'No lanzó error';
    exception when others then
      v_ok := sqlerrm like '%ya salió de captura y no se quita del lote%'; v_det := left(sqlerrm,160);
    end;
    select count(*) into v_n from public.service_lines where id=l_c;
    r_id := r_id||'ED-08 no quita una reclamación que ya salió de captura'::text; r_ok := r_ok||(v_ok and v_n=1); r_det := r_det||v_det;

    -- Admin ejecuta la primera solicitud.
    begin
      v_res := public.execute_claim_duplicate_exclusion(v_req);
      v_ok := (v_res->>'ok')::boolean and v_res->>'excluded_folio'='REC-QA233-000002' and v_res->>'kept_folio'='REC-QA233-000001'; v_det := left(v_res::text,160);
    exception when others then v_ok := false; v_det := left(sqlerrm,160);
    end;
    r_id := r_id||'ED-09 Admin ejecuta la exclusión solicitada'::text; r_ok := r_ok||v_ok; r_det := r_det||v_det;

    select count(*) filter (where id=l_b), count(*) filter (where id=l_a and claim_status='capturada') into v_n, v_m from public.service_lines where id in (l_a,l_b);
    r_id := r_id||'ED-10 la excluida sale del lote y la conservada queda intacta'::text; r_ok := r_ok||(v_n=0 and v_m=1); r_det := r_det||('excluida='||v_n||' conservada='||v_m);

    select status, executed_by into v_txt, v_by from app.claim_duplicate_resolution_requests where id=v_req;
    r_id := r_id||'ED-11 la solicitud queda ejecutada, con quién'::text; r_ok := r_ok||(v_txt='ejecutada' and v_by=u_adm); r_det := r_det||('estado='||coalesce(v_txt,'NULL'));

    select count(*) filter (where operation='DELETE' and table_name='service_lines' and record_id=l_b::text and old_values->>'claim_folio'='REC-QA233-000002'),
           count(*) filter (where operation='EXCLUSION_DUPLICADO_EJECUTADA' and record_id=v_req::text and new_values->>'exclude_folio'='REC-QA233-000002')
      into v_n, v_m from public.audit_log where organization_id=org_id;
    r_id := r_id||'ED-12 la auditoría guarda la reclamación completa y la ejecución'::text; r_ok := r_ok||(v_n=1 and v_m=1); r_det := r_det||('borrado='||v_n||' ejecucion='||v_m);

    select count(*) into v_n from public.activities where organization_id=org_id and body like '%REC-QA233-000002%Duplicado confirmado de REC-QA233-000001%';
    r_id := r_id||'ED-13 la bitácora del cliente registra el motivo'::text; r_ok := r_ok||(v_n=1); r_det := r_det||('actividades='||v_n);

    begin
      perform public.execute_claim_duplicate_exclusion(v_req);
      v_ok := false; v_det := 'No lanzó error';
    exception when others then
      v_ok := sqlerrm like 'Esta solicitud de exclusión ya fue ejecutada%'; v_det := left(sqlerrm,160);
    end;
    r_id := r_id||'ED-14 una solicitud ejecutada no se repite'::text; r_ok := r_ok||v_ok; r_det := r_det||v_det;

    select count(*) into v_n from public.claim_duplicate_candidates(null, sub_id) where line_id=l_b or other_line_id=l_b;
    r_id := r_id||'ED-15 el par deja de aparecer como duplicado'::text; r_ok := r_ok||(v_n=0); r_det := r_det||('pares='||v_n);

    raise exception 'QA_DESHACER';
  exception when others then
    if sqlerrm <> 'QA_DESHACER' then
      r_id := r_id||'ED-XX la suite se interrumpió'::text; r_ok := r_ok||false; r_det := r_det||left(sqlerrm,300);
    end if;
  end;

  for i in 1..cardinality(r_id) loop if not r_ok[i] then v_fail := v_fail + 1; end if; end loop;
  prueba := case when v_fail=0 then 'TODO OK · '||cardinality(r_id)||' de '||cardinality(r_id)
                 else 'FALLARON '||v_fail||' de '||cardinality(r_id) end;
  resultado := case when v_fail=0 then 'APROBADA' else 'FALLIDA' end; detalle := ''; return next;
  for i in 1..cardinality(r_id) loop
    prueba := r_id[i]; resultado := case when r_ok[i] then 'APROBADA' else 'FALLIDA' end; detalle := r_det[i]; return next;
  end loop;
end
$suite$;

revoke all on function app.qa_run_tests_exclusion_duplicados() from public, anon, authenticated;

-- Compuerta: si alguna prueba falla, la migración entera se deshace.
do $$
declare v_mal text;
begin
  select string_agg(prueba||coalesce(' ['||nullif(detalle,'')||']',''), E'\n') into v_mal
    from app.qa_run_tests_exclusion_duplicados() where resultado <> 'APROBADA';
  if v_mal is not null then
    raise exception E'La suite no pasó; no se aplicó nada:\n%', v_mal;
  end if;
end $$;
