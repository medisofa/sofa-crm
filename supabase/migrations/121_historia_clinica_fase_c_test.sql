-- 121 · Suite de la 120 (recetas, órdenes y diagnóstico a la reclamación). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_historia_clinica_c();
create or replace function app.qa_run_tests_historia_clinica_c()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000002c1';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000002c1';
  v_med constant text := 'a7000000-0000-4000-8000-0000000002c1'; v_sec constant text := 'a7000000-0000-4000-8000-0000000002c2';
  v_sa constant text := 'a7000000-0000-4000-8000-0000000002c3';
  v_p uuid; v_note uuid; v_apt uuid; v_ord uuid; v_line uuid; v_sub uuid; v_ars uuid; v_proc uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.hcc.med@sofa.test','x'),(v_sec::uuid,'qa.hcc.sec@sofa.test','x'),(v_sa::uuid,'qa.hcc.sa@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.hcc.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA HCC', '00000000721', 'Médico independiente', 'activo', current_date - 90, '8095550721');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. HCC', 'Medicina Interna');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'), ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin');
    insert into public.patients (organization_id, full_name, doc_number) values (v_org, 'Paciente HCC', '00100000721') returning id into v_p;
    insert into public.clinical_settings (organization_id, mode) values (v_org, 'prueba');
    select id into v_ars from public.ars where code = 'humano';
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, patient_doc, member_number, payer_type, ars_id, authorization_number, status, patient_id)
    values (v_org, v_prov, current_date, '10:00', 'Paciente HCC', '00100000721', 'NSS-HCC-1', 'ars', v_ars, 'AUT-HCC-1', 'en_espera', v_p) returning id into v_apt;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_note := public.save_clinical_note(null, v_p, 'general_soap', '{"motivo":"Fiebre","enfermedad_actual":"2 días","examen_fisico":"Normal","diagnosticos":"r50.9, j06.9","plan":"Control"}'::jsonb, current_date, v_prov, v_apt);
    perform public.sign_clinical_note(v_note);
    begin
      perform public.create_clinical_order(v_p, 'receta', '{"items":[{"medicamento":"Acetaminofén"}]}'::jsonb, v_note);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Receta sin dosis se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Receta sin dosis se rechaza','ok',sqlerrm like 'Cada medicamento necesita%','d',left(sqlerrm,120)));
    end;
    v_x := public.create_clinical_order(v_p, 'receta', '{"items":[{"medicamento":"Acetaminofén 500 mg","dosis":"1 tableta","frecuencia":"cada 8 horas","duracion":"5 días"}],"indicaciones":"Hidratación"}'::jsonb, v_note);
    v_ord := (v_x->>'id')::uuid;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Receta firmada con huella','ok',coalesce((length(v_x->>'hash') = 64), false),'d',(null)::text));
    perform public.create_clinical_order(v_p, 'laboratorio', '{"items":[{"estudio":"Hemograma"},{"estudio":"Glucosa"}],"indicacion":"Fiebre"}'::jsonb, v_note);
    v_x := public.clinical_orders_for(v_p);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Lista receta y laboratorio','ok',coalesce((jsonb_array_length(v_x) = 2 and exists (select 1 from jsonb_array_elements(v_x) o where o->>'summary' = 'Hemograma, Glucosa')), false),'d',(v_x::text)::text));
    v_x := public.clinical_order(v_ord);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · La receta abre para imprimir y la huella verifica','ok',coalesce(((v_x->>'hash_ok')::boolean and v_x->'content'->'items'->0->>'medicamento' = 'Acetaminofén 500 mg' and v_x->'patient'->>'name' = 'Paciente HCC'), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      update public.clinical_orders set kind = 'imagen' where id = v_ord;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · La receta no se modifica','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · La receta no se modifica','ok',sqlerrm like 'Registro clínico protegido%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.clinical_orders_for(v_p);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · La Secretaria no ve las órdenes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · La Secretaria no ve las órdenes','ok',sqlerrm like 'Sin acceso a la historia clínica%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.note_diagnosis_to_claim(v_note);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Sin reclamación en la cita: dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Sin reclamación en la cita: dice qué hacer','ok',sqlerrm like 'La cita todavía no tiene reclamación%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.app_settings set require_delivery_evidence = false where operator_id = '00000000-0000-4000-8000-000000000001'::uuid;
    select id into v_proc from public.procedures where internal_code = 'SOFA-P07';
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    perform public.create_contract_tariff(v_prov, v_ars, v_proc, 1300, current_date - 30, null, 'CT-HCC');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.attend_appointment(v_apt, v_proc);
    v_line := (v_x->>'id')::uuid;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.note_diagnosis_to_claim(v_note);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · El diagnóstico pasa a la reclamación','ok',coalesce(((select codes from public.claim_diagnoses where service_line_id = v_line) = 'R50.9, J06.9'), false),'d',(v_x::text)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · La cita aparece con reclamación','ok',coalesce((exists (select 1 from jsonb_array_elements(public.clinical_appointments(v_p)) a where (a->>'has_claim')::boolean)), false),'d',(null)::text));

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
