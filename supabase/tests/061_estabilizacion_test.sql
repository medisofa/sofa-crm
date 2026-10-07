-- ============================================================================
-- SOFA 1.7.7 · 061_estabilizacion_test.sql · suite de la migración 060
-- Ejecutar en el SQL Editor:  select * from app.qa_run_tests_estabilizacion();
-- Todo se deshace al terminar (no deja datos).
-- CT-01…CT-08  public.remove_service_line
-- CT-09        public.import_claims: fila sin servicio
-- CT-10…CT-11  search_path de las suites y app.qa_patch
-- CT-12        Regresión SQL completa: las 21 suites en TODO OK
-- ============================================================================
do $$
begin
  if not exists (select 1 from app.schema_migrations where version = '060') then
    raise exception 'Falta la migración 060_estabilizacion.sql. Aplíquela antes de instalar esta suite.';
  end if;
end $$;

create or replace function app.qa_run_tests_estabilizacion()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_ok boolean; v_n int;
  v_a jsonb; v_b jsonb; v_c jsonb; v_d jsonb; v_x jsonb; v_lote uuid; v_lote2 uuid; v_f text; v_bad text;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin

    -- ===== Datos =====
    insert into auth.users (id, email) values ('a8000000-0000-4000-8000-000000000001','qa.est.admin@sofa.test'), ('a8000000-0000-4000-8000-000000000002','qa.est.fact@sofa.test'), ('a8000000-0000-4000-8000-000000000006','qa.est.cliA@sofa.test'), ('a8000000-0000-4000-8000-000000000007','qa.est.capA@sofa.test'), ('a8000000-0000-4000-8000-000000000008','qa.est.cliB@sofa.test');
    insert into public.profiles (id, full_name) select id, replace(email, '@sofa.test', '') from auth.users where email like 'qa.est.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on) values ('b8000000-0000-4000-8000-00000000000a','client','00000000-0000-4000-8000-000000000001','QA EST A','00000000091','Centro médico','activo', current_date - 90), ('b8000000-0000-4000-8000-00000000000b','client','00000000-0000-4000-8000-000000000001','QA EST B','00000000092','Consultorio','activo', current_date - 90);
    update public.organizations set ecf_required_from = date '2099-12-31' where kind = 'client' and ecf_required_from is distinct from date '2099-12-31';
    insert into public.providers (id, organization_id, full_name) values ('c8000000-0000-4000-8000-00000000000a','b8000000-0000-4000-8000-00000000000a','Dr. Médico A QA'), ('c8000000-0000-4000-8000-00000000000b','b8000000-0000-4000-8000-00000000000b','Dr. Otro Cliente QA');
    insert into public.organization_users (organization_id, user_id, role_code) values ('00000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','admin'), ('00000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000002','billing'), ('b8000000-0000-4000-8000-00000000000a','a8000000-0000-4000-8000-000000000006','client'), ('b8000000-0000-4000-8000-00000000000a','a8000000-0000-4000-8000-000000000007','capturer'), ('b8000000-0000-4000-8000-00000000000b','a8000000-0000-4000-8000-000000000008','client');
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.set_capturer_scope('a8000000-0000-4000-8000-000000000007', array['c8000000-0000-4000-8000-00000000000a']::uuid[]);
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    perform public.create_contract_tariff('c8000000-0000-4000-8000-00000000000a', (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), 1200, date_trunc('month', current_date)::date - 100, null, 'CT-EST');
    perform public.create_contract_tariff('c8000000-0000-4000-8000-00000000000a', (select id from public.ars where code='universal'), (select id from public.procedures where internal_code='SOFA-P07'), 1200, date_trunc('month', current_date)::date - 100, null, 'CT-EST');
    v_a := public.capture_claim('c8000000-0000-4000-8000-00000000000a', (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), date_trunc('month', current_date)::date, 'Paciente Quitar A', 'NSS-EST-1', 'AUT-EST-1', null, null, 1, 'ambulatorio');
    v_b := public.capture_claim('c8000000-0000-4000-8000-00000000000a', (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), date_trunc('month', current_date)::date, 'Paciente Quitar B', 'NSS-EST-2', 'AUT-EST-2', null, null, 1, 'ambulatorio');
    v_c := public.capture_claim('c8000000-0000-4000-8000-00000000000a', (select id from public.ars where code='humano'), (select id from public.procedures where internal_code='SOFA-P07'), date_trunc('month', current_date)::date, 'Paciente Quitar C', 'NSS-EST-3', 'AUT-EST-3', null, null, 1, 'ambulatorio');
    v_lote := (v_a->>'submission_id')::uuid;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_f := 'b8000000-0000-4000-8000-00000000000a/' || v_lote || '/' || (v_a->>'id') || '/qa_autorizacion.pdf';
    insert into public.documents (organization_id, entity_type, entity_id, service_line_id, document_type_code, bucket, storage_path, file_name, mime_type, size_bytes)
    values ('b8000000-0000-4000-8000-00000000000a', 'service_line', (v_a->>'id')::uuid, (v_a->>'id')::uuid, 'autorizacion', 'claim-documents', v_f, 'qa_autorizacion.pdf', 'application/pdf', 10);

    -- ===== CT-01 · La secretaria no quita reclamaciones =====
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000007','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.remove_service_line((v_a->>'id')::uuid, 'QA: la secretaria intenta quitarla');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · La secretaria no quita reclamaciones del lote','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · La secretaria no quita reclamaciones del lote','ok',sqlerrm like 'Su rol no quita%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    -- ===== CT-02 · Otro cliente no quita reclamaciones ajenas =====
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000008','role','authenticated')::text, true);
    begin
      perform public.remove_service_line((v_a->>'id')::uuid, 'QA: otro cliente intenta quitarla');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Otro cliente no quita reclamaciones ajenas','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Otro cliente no quita reclamaciones ajenas','ok',sqlerrm like 'Su rol no quita%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    -- ===== CT-03 · El motivo es obligatorio =====
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000002','role','authenticated')::text, true);
    begin
      perform public.remove_service_line((v_a->>'id')::uuid, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · El motivo es obligatorio','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · El motivo es obligatorio','ok',sqlerrm like 'Indique el motivo%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    -- ===== CT-04 · Facturación quita una reclamación con su documento =====
    v_x := public.remove_service_line((v_a->>'id')::uuid, 'QA: reclamación capturada dos veces');
    select coalesce((select v_x->>'folio' = v_a->>'folio' and (v_x->>'documents')::int = 1 and jsonb_array_length(v_x->'files') = 1
                            and v_x->'files'->0->>'path' = v_f and v_x->'files'->0->>'bucket' = 'claim-documents'), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Devuelve el folio y los archivos a borrar de Storage','ok',v_ok,'d',v_x::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select coalesce((select not exists (select 1 from public.service_lines where id = (v_a->>'id')::uuid)
                            and not exists (select 1 from public.documents where storage_path = v_f)
                            and exists (select 1 from public.service_lines where id = (v_b->>'id')::uuid)), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Se van la reclamación y su documento (sin huérfanos); las demás quedan','ok',v_ok,'d',null));
    select coalesce((select exists (select 1 from public.activities where organization_id = 'b8000000-0000-4000-8000-00000000000a' and activity_type = 'sistema'
                                     and body like 'Reclamación ' || (v_a->>'folio') || '%quitada del lote%capturada dos veces')), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Queda la actividad en el cliente con folio, lote y motivo','ok',v_ok,'d',null));

    -- ===== CT-07 · El médico (cliente) quita una de su lote en borrador =====
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000006','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      v_x := public.remove_service_line((v_c->>'id')::uuid, 'QA: el paciente no asistió, se capturó por error');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · El médico quita una reclamación de su lote mientras es suyo','ok',v_x->>'folio' = v_c->>'folio','d',null));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · El médico quita una reclamación de su lote mientras es suyo','ok',false,'d',left(sqlerrm, 200)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);

    -- ===== CT-08 · Un lote radicado no suelta reclamaciones =====
    perform set_config('request.jwt.claims', json_build_object('sub','a8000000-0000-4000-8000-000000000001','role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    update public.submissions set ncf = 'B0100000601', invoice_date = current_date where id = v_lote;
    perform public.change_submission_status(v_lote, 'recibida');
    perform public.change_submission_status(v_lote, 'en_depuracion');
    perform public.change_submission_status(v_lote, 'lista_para_radicar', null, 'QA: lote de prueba autorizado por administración');
    update public.submissions set fiscal_invoice_number = 'F-B0100000601', accountant_name = 'Lic. QA', fiscal_amount = (select sum(amount) from public.service_lines where submission_id = v_lote) where id = v_lote;
    perform public.change_submission_status(v_lote, 'radicada', null, null, current_date, 'R-EST-1', 'fisico', 'LOTE-EST-1');
    begin
      perform public.remove_service_line((v_b->>'id')::uuid, 'QA: intento de quitar una radicada');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Un lote radicado no suelta reclamaciones (ni el Admin)','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Un lote radicado no suelta reclamaciones (ni el Admin)','ok',sqlerrm like 'El lote % ya fue radicado%','d','Bloqueado: ' || left(sqlerrm, 140)));
    end;

    -- ===== CT-09 · import_claims: fila sin servicio =====
    v_x := public.import_claims(jsonb_build_array(jsonb_build_object('medico','Dr. Médico A QA','ars','humano','fecha',to_char(current_date,'DD/MM/YYYY'),'paciente','Paciente Sin Servicio','nss','NSS-EST-9','autorizacion','AUT-9')), false);
    select coalesce((select (v_x->'errors'->0->'errors')::text like '%Falta el servicio: indique el código interno, el nombre, el SIMON o el CUPS%'
                            and (v_x->'errors'->0->'errors')::text not like '%Servicio no encontrado%'), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Importación: una fila sin servicio dice qué falta','ok',v_ok,'d',(v_x->'errors'->0->'errors')::text));
    v_x := public.import_claims(jsonb_build_array(jsonb_build_object('medico','Dr. Médico A QA','ars','humano','servicio','NO-EXISTE-QA','fecha',to_char(current_date,'DD/MM/YYYY'),'paciente','Paciente Sin Servicio','nss','NSS-EST-9','autorizacion','AUT-9')), false);
    select coalesce((select (v_x->'errors'->0->'errors')::text like '%Servicio no encontrado (código interno, nombre, SIMON o CUPS): NO-EXISTE-QA%'), false) into v_ok;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09b · Un servicio inexistente nombra el valor recibido','ok',v_ok,'d',null));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);

    -- ===== CT-10 · search_path fijo en todas las suites =====
    select string_agg(p.proname, ', ') into v_bad from pg_catalog.pg_proc p join pg_catalog.pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'app' and p.proname like 'qa\_run\_tests%' and p.proconfig is null;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Todas las suites tienen search_path fijo','ok',v_bad is null,'d',v_bad));

    -- ===== CT-11 · app.qa_patch no adivina =====
    begin
      perform app.qa_patch('app.qa_run_tests_estabilizacion()', 'v_res', 'v_res');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · El parche se niega si el fragmento aparece más de una vez','ok',false,'d','Se permitió y debía bloquearse'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · El parche se niega si el fragmento aparece más de una vez','ok',sqlerrm like 'No se pudo parchar%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception
    when others then
      if sqlerrm <> 'sofa_qa_rollback' then
        v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
      end if;
  end;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);

  -- ===== CT-12 · Regresión SQL: las 21 suites en TODO OK (cada una se deshace sola) =====
  v_bad := null; v_n := 0;
  declare f record; r record;
  begin
    for f in select p.proname from pg_catalog.pg_proc p join pg_catalog.pg_namespace s on s.oid = p.pronamespace
              where s.nspname = 'app' and p.proname like 'qa\_run\_tests%' and p.proname <> 'qa_run_tests_estabilizacion' order by 1 loop
      v_n := v_n + 1;
      begin
        execute format('select resultado, prueba from app.%I() where n = 0', f.proname) into r;
        if r.resultado is distinct from 'TODO OK' then v_bad := concat_ws(' · ', v_bad, f.proname || ': ' || coalesce(r.prueba, 'sin resumen')); end if;
      exception when others then
        v_bad := concat_ws(' · ', v_bad, f.proname || ': ' || left(sqlerrm, 80));
      end;
    end loop;
  end;
  v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · Regresión SQL: ' || v_n || ' suites en TODO OK','ok',v_bad is null and v_n >= 21,'d',v_bad));

  return query
    select 0, case when bool_and((e->>'ok')::boolean) then 'TODO OK' else 'REVISAR' end,
           format('%s de %s pruebas aprobadas', count(*) filter (where (e->>'ok')::boolean), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;
revoke all on function app.qa_run_tests_estabilizacion() from public, anon, authenticated;

