-- 123 · Suite de la 122 (importar historias de otros sistemas). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_importar_historias();
create or replace function app.qa_run_tests_importar_historias()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000002d1';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000002d1';
  v_med constant text := 'a7000000-0000-4000-8000-0000000002d1'; v_sec constant text := 'a7000000-0000-4000-8000-0000000002d2';
  v_sa constant text := 'a7000000-0000-4000-8000-0000000002d3';
  v_rows jsonb; v_p uuid; v_note uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.ih.med@sofa.test','x'),(v_sec::uuid,'qa.ih.sec@sofa.test','x'),(v_sa::uuid,'qa.ih.sa@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ih.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA IH', '00000000731', 'Médico independiente', 'activo', current_date - 90, '8095550731');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. IH', 'Ginecología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'), ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin');
    insert into public.patients (organization_id, full_name, doc_number) values (v_org, 'Paciente IH Existente', '00100000731') returning id into v_p;
    insert into public.clinical_settings (organization_id, mode) values (v_org, 'prueba');
    v_rows := jsonb_build_array(
      jsonb_build_object('documento', '001-0000073-1', 'nombre', 'Paciente IH Existente', 'fecha', '15/03/2024', 'texto', 'Control prenatal. Todo normal.', 'diagnosticos', 'z34.9'),
      jsonb_build_object('documento', '00100000732', 'nombre', 'Paciente IH Nueva', 'fecha', '2023-11-02', 'texto', 'Primera consulta ginecológica.'),
      jsonb_build_object('documento', '00100000732', 'nombre', 'Paciente IH Nueva', 'fecha', '10/01/2024', 'texto', 'Seguimiento.'));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    begin
      perform public.clinical_import(v_org, v_rows, '', false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Exige el sistema de origen','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Exige el sistema de origen','ok',sqlerrm like 'Escriba el nombre del sistema de origen%','d',left(sqlerrm,120)));
    end;
    v_x := public.clinical_import(v_org, v_rows, 'Sistema anterior QA', false, 'historias.xlsx');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select count(*) into v_n from public.clinical_notes where organization_id = v_org;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Vista previa: 3 válidas, 2 de paciente nuevo, nada guardado','ok',coalesce(((v_x->>'valid')::int = 3 and (v_x->>'new_patients')::int = 2 and v_n = 0), false),'d',(v_x->>'valid')::text));
    v_x := public.clinical_import(v_org, v_rows || jsonb_build_array(jsonb_build_object('documento','x','fecha','mañana','texto','')), 'Sistema anterior QA', false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Explica la fila con errores','ok',coalesce((jsonb_array_length(v_x->'errors') = 1 and jsonb_array_length(v_x->'errors'->0->'errors') = 4), false),'d',(v_x->'errors')::text));
    v_x := public.clinical_import(v_org, v_rows, 'Sistema anterior QA', true, 'historias.xlsx');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Importa 3 notas y crea 1 paciente','ok',coalesce(((v_x->>'imported')::int = 3 and (v_x->>'patients_created')::int = 1), false),'d',(v_x::text)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select id into v_note from public.clinical_notes where patient_id = v_p and template_code = 'historia_importada';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.clinical_note(v_note);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · La nota importada queda firmada, con origen y huella válida','ok',coalesce((v_x->>'status' = 'firmada' and (v_x->>'hash_ok')::boolean and v_x->'content'->>'sistema_origen' = 'Sistema anterior QA' and v_x->>'date' = '2024-03-15'), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Queda en la bitácora clínica','ok',coalesce((exists (select 1 from jsonb_array_elements(public.clinical_access_report(v_org)) r where r->>'action' = 'importar')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.clinical_import(v_org, v_rows, 'X', false);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · La Secretaria no importa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · La Secretaria no importa','ok',sqlerrm like 'La importación de historias la hace SOFA%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.clinical_settings set mode = 'activa', legal_ack = 'Revisado por Lic. QA, abogado de salud, memo QA-2026' where organization_id = v_org;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    v_x := public.clinical_import(v_org, v_rows, 'Sistema anterior QA', false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · En modo activa exige consentimiento','ok',coalesce((jsonb_array_length(v_x->'errors') = 3), false),'d',(v_x->'errors'->0)::text));

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
