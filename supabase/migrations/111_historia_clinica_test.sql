-- 111 · Suite de la 110 (historia clínica con salvaguardas). Se deshace sola: no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_historia_clinica();
create or replace function app.qa_run_tests_historia_clinica()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_t text; v_ok boolean;
  v_p uuid; v_note uuid; v_note2 uuid; v_b bytea;
  v_org  constant uuid := 'b7000000-0000-4000-8000-0000000001a1';
  v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000001a2';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000001a1';
  v_op   constant uuid := '00000000-0000-4000-8000-000000000001';
  v_med  constant text := 'a7000000-0000-4000-8000-0000000001a1';
  v_sec  constant text := 'a7000000-0000-4000-8000-0000000001a2';
  v_otro constant text := 'a7000000-0000-4000-8000-0000000001a3';
  v_adm  constant text := 'a7000000-0000-4000-8000-0000000001a4';
  v_sa   constant text := 'a7000000-0000-4000-8000-0000000001a5';
  v_full jsonb := '{"motivo":"Dolor torácico QA-SECRETO","enfermedad_actual":"3 días de evolución","pa":"120/80","fc":"72",
                    "examen_fisico":"Normal","diagnosticos":"R07.4, I10","plan":"Reposo y control"}';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.hc.med@sofa.test','x'),(v_sec::uuid,'qa.hc.sec@sofa.test','x'),
      (v_otro::uuid,'qa.hc.otro@sofa.test','x'),(v_adm::uuid,'qa.hc.adm@sofa.test','x'),(v_sa::uuid,'qa.hc.sa@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.hc.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_org, 'client', v_op, 'QA HC A', '00000000301', 'Médico independiente', 'activo', current_date - 90, '8095550031'),
      (v_org2, 'client', v_op, 'QA HC B', '00000000302', 'Médico independiente', 'activo', current_date - 90, '8095550032');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. HC', 'Cardiología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'),
      (v_org2, v_otro::uuid, 'client'), (v_op, v_adm::uuid, 'admin'), (v_op, v_sa::uuid, 'super_admin');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (v_sec::uuid, v_prov, v_org, true, false);
    insert into public.patients (organization_id, full_name, doc_number) values (v_org, 'Paciente HC Prueba', '00100000001') returning id into v_p;
    perform set_config('role', 'authenticated', true);

    -- CT-01 · Nace desactivada
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.save_clinical_note(null, v_p, 'general_soap', v_full);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Desactivada: no deja escribir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Desactivada: no deja escribir','ok',sqlerrm like 'La historia clínica no está activada%','d',left(sqlerrm,110)));
    end;

    -- CT-02/03 · Solo el Super Admin cambia el modo
    begin
      perform public.clinical_set_mode(v_org, 'prueba');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · El médico no cambia el modo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · El médico no cambia el modo','ok',sqlerrm like 'Solo el Super Admin%','d',left(sqlerrm,110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    begin
      perform public.clinical_set_mode(v_org, 'activa', false, 'corto');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Activa exige constancia legal','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Activa exige constancia legal','ok',sqlerrm like 'Para activar con pacientes reales%','d',left(sqlerrm,110)));
    end;
    v_x := public.clinical_set_mode(v_org, 'prueba');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Super Admin pone el consultorio en prueba','ok',v_x->>'mode' = 'prueba','d',v_x::text));

    -- CT-05 · El Super Admin, sin emergencia, NO lee
    begin
      perform public.clinical_record(v_p);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Super Admin sin emergencia no lee','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Super Admin sin emergencia no lee','ok',sqlerrm like 'Sin acceso a la historia clínica%','d',left(sqlerrm,110)));
    end;

    -- CT-06 · El médico crea un borrador y queda cifrado
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_note := public.save_clinical_note(null, v_p, 'general_soap', v_full - 'plan', current_date, v_prov);
    perform set_config('role', 'none', true);
    select content_enc into v_b from public.clinical_notes where id = v_note;
    perform set_config('role', 'authenticated', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El contenido se guarda cifrado (no se lee el texto en la tabla)','ok',
      v_b is not null and position(convert_to('QA-SECRETO', 'UTF8') in v_b) = 0,'d',null));

    -- CT-07 · Firmar exige los obligatorios
    begin
      perform public.sign_clinical_note(v_note);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · No firma si falta un obligatorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · No firma si falta un obligatorio','ok',sqlerrm like 'Falta «Plan y tratamiento»%','d',left(sqlerrm,110)));
    end;
    -- CT-08 · CIE-10 inválido
    begin
      perform public.save_clinical_note(v_note, v_p, 'general_soap', jsonb_set(v_full, '{diagnosticos}', '"dolor"'));
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Rechaza un código CIE-10 mal escrito','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Rechaza un código CIE-10 mal escrito','ok',sqlerrm like 'El código CIE-10 «DOLOR» no es válido%','d',left(sqlerrm,110)));
    end;
    perform public.save_clinical_note(v_note, v_p, 'general_soap', v_full, current_date, v_prov);
    v_x := public.sign_clinical_note(v_note);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Firma con huella SHA-256','ok',length(v_x->>'hash') = 64,'d',v_x::text));

    -- CT-10/11 · La firmada no se edita (ni por función ni directo en la tabla)
    begin
      perform public.save_clinical_note(v_note, v_p, 'general_soap', v_full);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · La nota firmada no se edita','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · La nota firmada no se edita','ok',sqlerrm like 'La nota ya está firmada%','d',left(sqlerrm,110)));
    end;
    perform set_config('role', 'none', true);
    begin
      update public.clinical_notes set encounter_date = current_date - 1 where id = v_note;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · Ni el dueño de la base altera una nota firmada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · Ni el dueño de la base altera una nota firmada','ok',sqlerrm like 'La nota firmada no se modifica%','d',left(sqlerrm,110)));
    end;
    perform set_config('role', 'authenticated', true);

    -- CT-12 · Adenda y verificación de la huella
    perform public.add_clinical_addendum(v_note, 'Se corrige: la PA fue 130/85.');
    v_x := public.clinical_note(v_note);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · La nota trae su adenda y la huella verifica','ok',
      jsonb_array_length(v_x->'addenda') = 1 and (v_x->>'hash_ok')::boolean and v_x->'content'->>'motivo' = 'Dolor torácico QA-SECRETO','d',left((v_x->'addenda')::text,120)));

    -- CT-13/14/15 · Secretaria, otro médico y Administrador SOFA no leen
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.clinical_note(v_note);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-13 · La Secretaria no ve nada clínico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-13 · La Secretaria no ve nada clínico','ok',sqlerrm like 'Sin acceso a la historia clínica%','d',left(sqlerrm,110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.clinical_record(v_p);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14 · Otro médico no ve la historia','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14 · Otro médico no ve la historia','ok',sqlerrm like 'Sin acceso a la historia clínica%','d',left(sqlerrm,110)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    begin
      perform public.clinical_export(v_p);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-15 · El Administrador SOFA no exporta','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-15 · El Administrador SOFA no exporta','ok',sqlerrm like 'Sin acceso a la historia clínica%','d',left(sqlerrm,110)));
    end;
    begin
      select count(*) into v_n from public.clinical_notes;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-16 · Nadie lee la tabla directamente','ok',false,'d',v_n::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-16 · Nadie lee la tabla directamente','ok',sqlstate = '42501','d',left(sqlerrm,110)));
    end;

    -- CT-17/18 · Emergencia: con motivo, solo lectura y queda registrada
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    begin
      perform public.clinical_break_glass(v_org, 'urgente');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-17 · Emergencia exige motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-17 · Emergencia exige motivo','ok',sqlerrm like 'Escriba el motivo%','d',left(sqlerrm,110)));
    end;
    perform public.clinical_break_glass(v_org, 'Paciente en emergencia en clínica externa, médico sin respuesta');
    v_x := public.clinical_record(v_p);
    v_ok := v_x->>'role' = 'emergencia';
    begin
      perform public.add_clinical_addendum(v_note, 'Intento de escritura en emergencia');
      v_ok := false;
    exception when others then
      v_ok := v_ok and sqlerrm like 'El acceso de emergencia es solo de lectura%';
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-18 · Emergencia lee pero no escribe','ok',v_ok,'d',v_x->>'role'));

    -- CT-19 · El médico ve la bitácora con la emergencia
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.clinical_access_report(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-19 · El médico ve quién entró (incluida la emergencia)','ok',
      exists (select 1 from jsonb_array_elements(v_x) e where e->>'action' = 'acceso_emergencia')
      and exists (select 1 from jsonb_array_elements(v_x) e where e->>'action' = 'firmar')
      and exists (select 1 from jsonb_array_elements(v_x) e where e->>'action' = 'ver'),'d',jsonb_array_length(v_x)::text || ' registros'));

    -- CT-20/21 · Bitácora encadenada e inborrable
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_x := public.clinical_verify_log();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-20 · La cadena de la bitácora verifica','ok',(v_x->>'ok')::boolean,'d',v_x::text));
    begin
      delete from public.clinical_access_log where organization_id = v_org;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-21 · La bitácora no se borra','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-21 · La bitácora no se borra','ok',sqlerrm like 'Registro clínico protegido%','d',left(sqlerrm,110)));
    end;
    perform set_config('role', 'authenticated', true);

    -- CT-22 · En modo activa exige consentimiento
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    perform public.clinical_set_mode(v_org, 'activa', false, 'Revisado por Lic. QA Prueba, abogado de salud, 08/10/2026, memo QA-1');
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.save_clinical_note(null, v_p, 'general_soap', '{"motivo":"Control"}'::jsonb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-22 · Activa: sin consentimiento no deja escribir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-22 · Activa: sin consentimiento no deja escribir','ok',sqlerrm like 'Falta el consentimiento del paciente%','d',left(sqlerrm,110)));
    end;
    perform public.record_clinical_consent(v_p, 'tratamiento_datos', 'firma_papel');
    v_note2 := public.save_clinical_note(null, v_p, 'general_soap', '{"motivo":"Control"}'::jsonb);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-23 · Con consentimiento sí guarda el borrador','ok',v_note2 is not null,'d',null));

    -- CT-24 · El borrador de un médico no lo ve otro; el autor lo borra
    perform public.delete_clinical_draft(v_note2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-24 · El autor borra su borrador','ok',not exists (select 1 from public.clinical_record(v_p) r, jsonb_array_elements(r->'notes') e where e->>'id' = v_note2::text),'d',null));

    -- CT-25 · Exportar trae la nota firmada con su adenda
    v_x := public.clinical_export(v_p);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-25 · Exportar trae la nota firmada y su adenda','ok',
      jsonb_array_length(v_x->'notes') = 1 and jsonb_array_length(v_x->'notes'->0->'addenda') = 1,'d',null));

    -- CT-26 · Resumen clínico (alergias) versionado
    perform public.save_clinical_summary(v_p, '{"alergias":"Penicilina"}'::jsonb);
    perform public.save_clinical_summary(v_p, '{"alergias":"Penicilina, AINES"}'::jsonb);
    v_x := public.clinical_record(v_p);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-26 · El resumen muestra la última versión','ok',v_x->'summary'->>'alergias' = 'Penicilina, AINES','d',v_x->>'summary'));

    -- CT-27 · Adjunto: la ruta debe ser del paciente
    begin
      perform public.register_clinical_attachment(v_p, v_org2::text || '/' || v_p::text || '/x.pdf', 'x.pdf');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-27 · Rechaza un adjunto con ruta de otro consultorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-27 · Rechaza un adjunto con ruta de otro consultorio','ok',sqlerrm like 'La ruta del archivo no corresponde%','d',left(sqlerrm,110)));
    end;

    -- CT-28 · MFA obligatorio
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    perform public.clinical_set_mode(v_org, 'activa', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.clinical_record(v_p);
      v_ok := false;
    exception when others then
      v_ok := sqlerrm like 'Este consultorio exige verificación en dos pasos%';
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_x := public.clinical_record(v_p);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-28 · Con MFA obligatorio: aal1 no entra, aal2 sí','ok',v_ok and v_x->>'role' = 'medico','d',null));

    -- CT-29 · No se desactiva si ya hay notas
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    begin
      perform public.clinical_set_mode(v_org, 'desactivada');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-29 · No se desactiva con notas existentes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-29 · No se desactiva con notas existentes','ok',sqlerrm like 'El consultorio ya tiene notas clínicas%','d',left(sqlerrm,110)));
    end;

    -- CT-30 · Plantillas de las 4 especialidades
    select count(*) into v_n from public.clinical_templates where code in ('general_soap','gineco_obstetricia','pediatria','cardiologia') and is_active;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-30 · Están las 4 plantillas','ok',v_n = 4,'d',v_n::text));

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
