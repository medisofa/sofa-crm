-- 263 · Suite de la 262 (plantillas de nutrición, especialidades y plantilla sugerida). Se deshace sola.
-- Ya aplicado en producción (2026-11-20): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_hc_nutricion();
create or replace function app.qa_run_tests_hc_nutricion()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_n int; v_t text; v_p uuid; v_apt uuid; v_id uuid;
  o   constant uuid := 'b9000000-0000-4000-8000-0000000000c1';
  o2  constant uuid := 'b9000000-0000-4000-8000-0000000000c2';
  p1  constant uuid := 'c9000000-0000-4000-8000-0000000000c1';
  p2  constant uuid := 'c9000000-0000-4000-8000-0000000000c2';
  u1  constant text := 'a9000000-0000-4000-8000-0000000000c1';
  us  constant text := 'a9000000-0000-4000-8000-0000000000c2';
  uo  constant text := 'a9000000-0000-4000-8000-0000000000c3';
  sa  constant text := 'a9000000-0000-4000-8000-0000000000c4';
  v_nut jsonb := '{"motivo":"Bajar de peso","peso":"82.5","talla":"165","cintura":"96","imc":"30.3","ict":"0.58 · Riesgo aumentado",
                   "bia_grasa_pct":"34.2","masa_grasa_kg":"28.2","get":"2310 kcal/día (Mifflin × 1.375)",
                   "diagnostico_nutricional":"Obesidad grado I","diagnosticos":"E66.0","meta_kcal":"1800","plan":"Plan de 1800 kcal"}';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email) values (u1::uuid,'qa.hn.u1@sofa.test'),(us::uuid,'qa.hn.sec@sofa.test'),(uo::uuid,'qa.hn.otro@sofa.test'),(sa::uuid,'qa.hn.sa@sofa.test');
    insert into public.profiles (id, full_name) select id, email from auth.users where email like 'qa.hn.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (o,'client','00000000-0000-4000-8000-000000000001','QA HN Clinica','00000000231','Clínica','activo',current_date-90,'8095550231'),
      (o2,'client','00000000-0000-4000-8000-000000000001','QA HN Otra','00000000232','Médico independiente','activo',current_date-90,'8095550232');
    insert into public.providers (id, organization_id, full_name, specialty, specialty_code) values
      (p1,o,'Lic. HN Adultos','Nutrióloga Clínica','nutricion'),(p2,o,'Lic. HN Niños','Nutrición Pediátrica','nutricion_pediatrica');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (o,u1::uuid,'client'),(o,us::uuid,'capturer'),(o2,uo::uuid,'client'),('00000000-0000-4000-8000-000000000001',sa::uuid,'super_admin');
    update public.providers set user_id = u1::uuid where id = p1;
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (us::uuid,p2,o,true,false);
    insert into public.patients (organization_id, full_name, doc_number, birth_date, sex) values (o,'Paciente HN','00100000231',current_date - 3650,'F') returning id into v_p;
    insert into public.appointments (organization_id, provider_id, patient_id, appointment_date, appointment_time, patient_name, payer_type, status)
      values (o,p2,v_p,current_date,'08:00','Paciente HN','privado','programada') returning id into v_apt;
    insert into public.appointments (organization_id, provider_id, patient_id, appointment_date, appointment_time, patient_name, payer_type, status)
      values (o,p1,v_p,current_date,'09:00','Paciente HN','privado','programada');
    perform set_config('role','authenticated',true);
    perform set_config('request.jwt.claims', json_build_object('sub',sa,'role','authenticated','aal','aal2')::text, true);
    perform public.clinical_set_mode(o, 'prueba');

    -- Catálogo
    select count(*) into v_n from public.clinical_templates where code in ('nutricion','nutricion_pediatrica') and is_active;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-01 · Existen las plantillas de nutrición de adultos y pediátrica','ok',v_n = 2,'d',v_n::text));
    select count(*) into v_n from public.clinical_templates t, jsonb_array_elements(t.fields) f
     where t.code in ('nutricion','nutricion_pediatrica','pediatria')
       and (f->>'type' not in ('text','textarea','number','select','date','cie10','calc','heading')
            or (f->>'type' <> 'heading' and coalesce(f->>'key','') = '')
            or (f->>'type' = 'calc' and coalesce(f->>'formula','') not in ('edad','imc','imc_clasif','icc','ict','masa_grasa_kg','masa_libre_grasa_kg',
                'geb_mifflin','geb_harris','get','z_peso_edad','z_talla_edad','z_imc_edad','z_peso_talla','z_pc_edad')));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-02 · Todos los campos tienen tipo y fórmula que la pantalla conoce','ok',v_n = 0,'d',v_n || ' inválidos'));
    select count(*) into v_n from (select t.code, f->>'key' k from public.clinical_templates t, jsonb_array_elements(t.fields) f
      where f ? 'key' group by 1,2 having count(*) > 1) d;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-03 · Ninguna plantilla repite una clave','ok',v_n = 0,'d',v_n || ' repetidas'));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-04 · Pediatría pasó a versión 2 con puntaje Z y «Medido»','ok',
      exists (select 1 from public.clinical_templates where code = 'pediatria' and version >= 2 and fields @> '[{"key":"z_talla_edad"},{"key":"medicion"}]'),'d',null));

    -- Plantilla sugerida
    perform set_config('request.jwt.claims', json_build_object('sub',u1,'role','authenticated')::text, true);
    v_t := public.clinical_default_template(v_p);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-05 · La nutrióloga de adultos recibe su plantilla','ok',v_t = 'nutricion','d',v_t));
    v_id := public.save_clinical_note(null, v_p, 'nutricion', v_nut);
    perform public.sign_clinical_note(v_id);
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-06 · Nota de nutrición con cálculos y bioimpedancia se guarda y firma','ok',
      exists (select 1 from public.clinical_notes where id = v_id and status = 'firmada'),'d',null));
    perform set_config('role','authenticated',true);
    begin
      v_id := public.save_clinical_note(null, v_p, 'nutricion', v_nut - 'peso');
      perform public.sign_clinical_note(v_id);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-07 · No firma sin el peso (obligatorio)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-07 · No firma sin el peso (obligatorio)','ok',sqlerrm like 'Falta «Peso (kg)»%','d',left(sqlerrm,110)));
    end;
    begin
      perform public.save_clinical_note(null, v_p, 'nutricion', v_nut || '{"bia_grasa_pct":"34,2"}');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-08 · Bioimpedancia con coma decimal → mensaje claro','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-08 · Bioimpedancia con coma decimal → mensaje claro','ok',sqlerrm like '%use punto para decimales%','d',left(sqlerrm,110)));
    end;

    perform set_config('request.jwt.claims', json_build_object('sub',us,'role','authenticated')::text, true);
    begin
      v_t := public.clinical_default_template(v_p, v_apt);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-09 · Sin médico propio, usa el de la cita (nutrición pediátrica)','ok',v_t = 'nutricion_pediatrica','d',v_t));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-09 · Sin médico propio, usa el de la cita (si la secretaria tiene acceso)','ok',sqlstate = '42501','d',left(sqlerrm,110)));
    end;

    perform set_config('request.jwt.claims', json_build_object('sub',uo,'role','authenticated')::text, true);
    begin
      perform public.clinical_default_template(v_p);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-10 · Otro consultorio no consulta pacientes ajenos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-10 · Otro consultorio no consulta pacientes ajenos','ok',true,'d',left(sqlerrm,110)));
    end;
    begin
      update public.specialties set template_code = 'general_soap' where code = 'nutricion';
      get diagnostics v_n = row_count;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-11 · Nadie cambia el catálogo de especialidades desde la app','ok',v_n = 0,'d',v_n || ' filas'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-11 · Nadie cambia el catálogo de especialidades desde la app','ok',true,'d',left(sqlerrm,110)));
    end;
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-12 · Sin acceso anónimo a la plantilla sugerida','ok',
      not has_function_privilege('anon','public.clinical_default_template(uuid,uuid)','EXECUTE'),'d',null));
    select count(*) into v_n from public.providers where specialty ~* 'nutri' and specialty_code is null and organization_id not in (o, o2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HN-13 · Todos los nutriólogos existentes quedaron normalizados','ok',v_n = 0,'d',v_n || ' sin código'));

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
revoke execute on function app.qa_run_tests_hc_nutricion() from public, anon, authenticated;
