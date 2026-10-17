-- 171 · Suite de la 170 (blindaje de seguridad 1: SEG-01 a SEG-09 y SEG-11). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_blindaje_1();
create or replace function app.qa_run_tests_blindaje_1()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '17100000-0000-4000-8000-000000000001'; v_orgb constant uuid := '17100000-0000-4000-8000-000000000002';
  v_pa1 constant uuid := '17100000-0000-4000-8000-000000000003'; v_pa2 constant uuid := '17100000-0000-4000-8000-000000000004'; v_pb constant uuid := '17100000-0000-4000-8000-000000000005';
  v_sa constant text := '17100000-0000-4000-8000-000000000011'; v_adm constant text := '17100000-0000-4000-8000-000000000012'; v_bil constant text := '17100000-0000-4000-8000-000000000013';
  v_glo constant text := '17100000-0000-4000-8000-000000000014'; v_ops constant text := '17100000-0000-4000-8000-000000000015';
  v_med1 constant text := '17100000-0000-4000-8000-000000000021'; v_med2 constant text := '17100000-0000-4000-8000-000000000022'; v_sec constant text := '17100000-0000-4000-8000-000000000023';
  v_medb constant text := '17100000-0000-4000-8000-000000000024'; v_nu1 constant text := '17100000-0000-4000-8000-000000000031'; v_nu2 constant text := '17100000-0000-4000-8000-000000000032';
  v_pwops constant text := '17100000-0000-4000-8000-000000000033'; v_pwmed constant text := '17100000-0000-4000-8000-000000000034';
  v_pat1 uuid; v_pat2 uuid; v_pat3 uuid; v_patb uuid; v_l4 uuid; v_s2 uuid; v_l5 uuid; v_sh1 boolean; v_sh2 boolean; v_sh3 boolean; v_note uuid; v_note2 uuid; v_tok text; v_tok2 text; v_ars uuid; v_arsb uuid; v_proc uuid; v_per date; v_s1 uuid; v_sb uuid; v_pay uuid; v_alloc uuid;
  v_l1 uuid; v_l2 uuid; v_l3 uuid; v_lb uuid; v_cen uuid; v_cenb uuid; v_msg uuid; v_cnt int; v_log0 int;
  v_full jsonb := '{"motivo":"Dolor torácico QA","enfermedad_actual":"3 días de evolución","pa":"120/80","fc":"72","examen_fisico":"Normal","diagnosticos":"R07.4, I10","plan":"Reposo y control"}';
  v_rx jsonb := '{"items":[{"medicamento":"Amoxicilina 500 mg","dosis":"1 cápsula","frecuencia":"cada 8 horas","duracion":"7 días"}],"indicaciones":"Con comida"}';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values ('17100000-0000-4000-8000-000000000011'::uuid,'qa.bs.sa@sofa.test','x'),('17100000-0000-4000-8000-000000000012'::uuid,'qa.bs.adm@sofa.test','x'),('17100000-0000-4000-8000-000000000013'::uuid,'qa.bs.bil@sofa.test','x'),
      ('17100000-0000-4000-8000-000000000014'::uuid,'qa.bs.glo@sofa.test','x'),('17100000-0000-4000-8000-000000000015'::uuid,'qa.bs.ops@sofa.test','x'),('17100000-0000-4000-8000-000000000021'::uuid,'qa.bs.med1@sofa.test','x'),('17100000-0000-4000-8000-000000000022'::uuid,'qa.bs.med2@sofa.test','x'),
      ('17100000-0000-4000-8000-000000000023'::uuid,'qa.bs.sec@sofa.test','x'),('17100000-0000-4000-8000-000000000024'::uuid,'qa.bs.medb@sofa.test','x'),('17100000-0000-4000-8000-000000000031'::uuid,'qa.bs.nu1@sofa.test','x'),('17100000-0000-4000-8000-000000000032'::uuid,'qa.bs.nu2@sofa.test','x'),
      ('17100000-0000-4000-8000-000000000033'::uuid,'qa.bs.pwops@sofa.test','x'),('17100000-0000-4000-8000-000000000034'::uuid,'qa.bs.pwmed@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.bs.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA BS Centro Médico', '00000000171', 'Médico independiente', 'activo', current_date - 90, '8095550171'),
           (v_orgb, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA BS Otro Consultorio', '00000000172', 'Médico independiente', 'activo', current_date - 90, '8095550172');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_pa1, v_org, 'Dr. Uno QA', 'Cardiología'), (v_pa2, v_org, 'Dra. Dos QA', 'Pediatría'), (v_pb, v_orgb, 'Dr. B QA', 'Ortopedia');
    insert into public.organization_users (organization_id, user_id, role_code) values
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin'), ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin'), ('00000000-0000-4000-8000-000000000001'::uuid, v_bil::uuid, 'billing'), ('00000000-0000-4000-8000-000000000001'::uuid, v_glo::uuid, 'glosas'), ('00000000-0000-4000-8000-000000000001'::uuid, v_ops::uuid, 'operations'), ('00000000-0000-4000-8000-000000000001'::uuid, v_pwops::uuid, 'operations'),
      (v_org, v_med1::uuid, 'client'), (v_org, v_med2::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'), (v_orgb, v_medb::uuid, 'client'), (v_orgb, v_pwmed::uuid, 'client');
    insert into public.clinical_settings (organization_id, mode) values (v_org, 'prueba');
    insert into public.patients (organization_id, full_name, doc_number, phone) values (v_org, 'Paciente Uno QA', '40200001711', '8095550171') returning id into v_pat1;
    insert into public.patients (organization_id, full_name, doc_number, phone) values (v_org, 'Paciente Dos QA', '40200001712', '8095550172') returning id into v_pat2;
    insert into public.patients (organization_id, full_name, doc_number) values (v_orgb, 'Paciente B QA', '40200001713') returning id into v_patb;
    insert into public.patients (organization_id, full_name, doc_number) values (v_org, 'Paciente Tres QA', '40200001714') returning id into v_pat3;
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type, status, patient_id)
    values (v_org, v_pa1, current_date + 3, '10:30', 'Paciente Uno QA', 'privado', 'programada', v_pat1),
           (v_org, v_pa2, current_date + 4, '11:30', 'Paciente Dos QA', 'privado', 'programada', v_pat2);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000024', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.clinical_access_report(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-01 · SEG-04 · El Médico de otro consultorio no lee la bitácora clínica ajena','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-01 · SEG-04 · El Médico de otro consultorio no lee la bitácora clínica ajena','ok',sqlerrm like 'Solo el médico del consultorio%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-02 · SEG-04 · El médico del consultorio sí lee su bitácora','ok',coalesce((jsonb_typeof(public.clinical_access_report(v_org)) = 'array'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-03 · SEG-04 · El Super Admin sí lee la bitácora','ok',coalesce((jsonb_typeof(public.clinical_access_report(v_org)) = 'array'), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000012'::uuid, '17100000-0000-4000-8000-000000000031'::uuid, 'client', v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-04 · SEG-01 · Con historia clínica activa, el Administrador no agrega Médicos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-04 · SEG-01 · Con historia clínica activa, el Administrador no agrega Médicos','ok',sqlerrm like 'Este consultorio tiene la historia clínica activa%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000012'::uuid, '17100000-0000-4000-8000-000000000031'::uuid, 'capturer', v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-05 · SEG-01 · Ni Secretarias','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-05 · SEG-01 · Ni Secretarias','ok',sqlerrm like 'Este consultorio tiene la historia clínica activa%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000012'::uuid, '17100000-0000-4000-8000-000000000031'::uuid, 'admin');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-06 · SEG-11 · El Administrador no nombra Administradores','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-06 · SEG-11 · El Administrador no nombra Administradores','ok',sqlerrm like 'Solo el Super Admin puede nombrar Administradores%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000012'::uuid, '17100000-0000-4000-8000-000000000031'::uuid, 'admin', null, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-07 · SEG-11 · Ni siquiera como simulación','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-07 · SEG-11 · Ni siquiera como simulación','ok',sqlerrm like 'Solo el Super Admin puede nombrar Administradores%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000012'::uuid, '17100000-0000-4000-8000-000000000022'::uuid, 'operations');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-08 · SEG-01 · No se da rol de personal a quien ya es Médico de un cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-08 · SEG-01 · No se da rol de personal a quien ya es Médico de un cliente','ok',sqlerrm like 'Ese usuario ya es Médico o Secretaria%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000011'::uuid, '17100000-0000-4000-8000-000000000023'::uuid, 'billing');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-09 · SEG-01 · Tampoco lo hace el Super Admin','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-09 · SEG-01 · Tampoco lo hace el Super Admin','ok',sqlerrm like 'Ese usuario ya es Médico o Secretaria%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000012'::uuid, '17100000-0000-4000-8000-000000000031'::uuid, 'operations');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-10 · Uso legítimo · El Administrador sigue asignando personal (Operaciones)','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-10 · Uso legítimo · El Administrador sigue asignando personal (Operaciones)','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000012'::uuid, '17100000-0000-4000-8000-000000000032'::uuid, 'client', v_orgb);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-11 · Uso legítimo · El Administrador agrega un Médico donde la historia clínica está desactivada','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-11 · Uso legítimo · El Administrador agrega un Médico donde la historia clínica está desactivada','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000011'::uuid, '17100000-0000-4000-8000-000000000032'::uuid, 'client', v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-12 · Uso legítimo · El Super Admin agrega un Médico con la historia clínica activa','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-12 · Uso legítimo · El Super Admin agrega un Médico con la historia clínica activa','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.admin_assign_role('17100000-0000-4000-8000-000000000011'::uuid, null, 'admin', null, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-13 · Uso legítimo · El Super Admin nombra un Administrador (simulación)','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-13 · Uso legítimo · El Super Admin nombra un Administrador (simulación)','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.authorize_user_creation(v_org, 'client');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-14 · SEG-01 · crear-usuario: el Administrador no crea Médicos con historia clínica activa','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-14 · SEG-01 · crear-usuario: el Administrador no crea Médicos con historia clínica activa','ok',sqlerrm like 'Este consultorio tiene la historia clínica activa%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.authorize_user_creation('00000000-0000-4000-8000-000000000001'::uuid, 'admin');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-15 · SEG-11 · crear-usuario: el Administrador no crea Administradores','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-15 · SEG-11 · crear-usuario: el Administrador no crea Administradores','ok',sqlerrm like 'Solo el Super Admin puede crear Administradores%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.authorize_user_creation('00000000-0000-4000-8000-000000000001'::uuid, 'assistant');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-16 · Uso legítimo · crear-usuario: el Administrador crea personal de Comercial','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-16 · Uso legítimo · crear-usuario: el Administrador crea personal de Comercial','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.authorize_user_creation(v_orgb, 'client');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-17 · Uso legítimo · crear-usuario: el Administrador crea un Médico donde no hay historia clínica','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-17 · Uso legítimo · crear-usuario: el Administrador crea un Médico donde no hay historia clínica','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.authorize_user_creation(v_org, 'client');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-18 · Uso legítimo · crear-usuario: el Super Admin crea un Médico con historia clínica activa','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-18 · Uso legítimo · crear-usuario: el Super Admin crea un Médico con historia clínica activa','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform public.create_clinical_order(v_pat1, 'receta', v_rx, null);
    v_note := public.save_clinical_note(null, v_pat1, 'general_soap', v_full, current_date, v_pa1);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.clinical_record(v_pat1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-19 · SEG-02 · Sin médicos enlazados (consultorio de un médico) todo sigue como antes','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-19 · SEG-02 · Sin médicos enlazados (consultorio de un médico) todo sigue como antes','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.link_provider_user(v_pa1, '17100000-0000-4000-8000-000000000021'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-20 · SEG-02 · El Médico no enlaza usuarios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-20 · SEG-02 · El Médico no enlaza usuarios','ok',sqlerrm like 'Solo el Super Admin o un Administrador%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000023', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.link_provider_user(v_pa1, '17100000-0000-4000-8000-000000000021'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-21 · SEG-02 · La Secretaria no enlaza usuarios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-21 · SEG-02 · La Secretaria no enlaza usuarios','ok',sqlerrm like 'Solo el Super Admin o un Administrador%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.link_provider_user(v_pa1, '17100000-0000-4000-8000-000000000023'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-22 · SEG-02 · No se enlaza a quien no es Médico del consultorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-22 · SEG-02 · No se enlaza a quien no es Médico del consultorio','ok',sqlerrm like 'Ese usuario no es Médico de este consultorio%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.link_provider_user(v_pa1, '17100000-0000-4000-8000-000000000024'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-23 · SEG-02 · No se enlaza a un Médico de otro consultorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-23 · SEG-02 · No se enlaza a un Médico de otro consultorio','ok',sqlerrm like 'Ese usuario no es Médico de este consultorio%','d',left(sqlerrm,160)));
    end;
    begin
      update public.providers set user_id = '17100000-0000-4000-8000-000000000021'::uuid where id = v_pa1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-24 · SEG-02 · Escribir user_id directo en providers se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-24 · SEG-02 · Escribir user_id directo en providers se rechaza','ok',sqlerrm like 'El usuario de un médico se enlaza%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.link_provider_user(v_pa1, '17100000-0000-4000-8000-000000000021'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-25 · SEG-02 · El Administrador enlaza al Dr. Uno','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-25 · SEG-02 · El Administrador enlaza al Dr. Uno','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.link_provider_user(v_pa2, '17100000-0000-4000-8000-000000000022'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-26 · SEG-02 · El Administrador enlaza a la Dra. Dos','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-26 · SEG-02 · El Administrador enlaza a la Dra. Dos','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-27 · SEG-02 · El enlace queda en audit_log','ok',coalesce((exists (select 1 from public.audit_log where table_name = 'providers' and record_id = v_pa1::text and operation = 'UPDATE' and new_values->>'user_id' = '17100000-0000-4000-8000-000000000021')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.link_provider_user(v_pa2, '17100000-0000-4000-8000-000000000021'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-28 · SEG-02 · Un usuario no se enlaza a dos médicos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-28 · SEG-02 · Un usuario no se enlaza a dos médicos','ok',sqlerrm like 'Ese usuario ya está enlazado%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.clinical_record(v_pat1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-29 · SEG-02 · ATAQUE: el segundo Médico no lee la historia del paciente ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-29 · SEG-02 · ATAQUE: el segundo Médico no lee la historia del paciente ajeno','ok',sqlerrm like 'Solo el médico que atiende a este paciente%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.clinical_orders_for(v_pat1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-30 · SEG-02 · Ni sus recetas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-30 · SEG-02 · Ni sus recetas','ok',sqlerrm like 'Solo el médico que atiende a este paciente%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.clinical_note(v_note);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-31 · SEG-02 · Ni una nota del otro médico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-31 · SEG-02 · Ni una nota del otro médico','ok',sqlerrm like 'Solo el médico que atiende a este paciente%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.clinical_export(v_pat1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-32 · SEG-02 · Ni exporta la historia','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-32 · SEG-02 · Ni exporta la historia','ok',sqlerrm like 'Solo el médico que atiende a este paciente%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.create_clinical_order(v_pat1, 'receta', v_rx, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-33 · SEG-02 · Ni escribe en ella','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-33 · SEG-02 · Ni escribe en ella','ok',sqlerrm like 'Solo el médico que atiende a este paciente%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.clinical_appointments(v_pat1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-34 · SEG-02 · Ni consulta sus citas clínicas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-34 · SEG-02 · Ni consulta sus citas clínicas','ok',sqlerrm like 'Solo el médico que atiende a este paciente%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.clinical_record(v_pat2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-35 · SEG-02 · Uso legítimo: la Dra. Dos lee a su propio paciente','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-35 · SEG-02 · Uso legítimo: la Dra. Dos lee a su propio paciente','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.clinical_record(v_pat1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-36 · SEG-02 · Uso legítimo: el Dr. Uno lee a su paciente','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-36 · SEG-02 · Uso legítimo: el Dr. Uno lee a su paciente','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.clinical_note(v_note);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-37 · SEG-02 · Uso legítimo: el Dr. Uno abre su nota','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-37 · SEG-02 · Uso legítimo: el Dr. Uno abre su nota','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.clinical_orders_for(v_pat1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-38 · SEG-02 · Uso legítimo: el Dr. Uno ve sus recetas','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-38 · SEG-02 · Uso legítimo: el Dr. Uno ve sus recetas','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.clinical_record(v_pat2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-39 · SEG-02 · El Dr. Uno no lee al paciente de la Dra. Dos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-39 · SEG-02 · El Dr. Uno no lee al paciente de la Dra. Dos','ok',sqlerrm like 'Solo el médico que atiende a este paciente%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.clinical_notes (organization_id, patient_id, provider_id, template_code, content_enc, status, author_id)
    values (v_org, v_pat3, null, 'general_soap', app.clinical_enc(v_full), 'borrador', '17100000-0000-4000-8000-000000000022'::uuid);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.clinical_record(v_pat3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-40 · SEG-02 · Uso legítimo: quien creó una nota del paciente sí lo ve','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-40 · SEG-02 · Uso legítimo: quien creó una nota del paciente sí lo ve','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.clinical_record(v_pat3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-40b · SEG-02 · Y el otro médico no ve a ese paciente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-40b · SEG-02 · Y el otro médico no ve a ese paciente','ok',sqlerrm like 'Solo el médico que atiende a este paciente%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform public.clinical_break_glass(v_org, 'Paciente en emergencia en clínica externa, médico sin respuesta');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-41 · SEG-02 · El acceso de emergencia del Super Admin sigue funcionando','ok',coalesce((public.clinical_record(v_pat1)->>'role' = 'emergencia'), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    begin
      insert into storage.objects (bucket_id, name) values ('clinical-records', v_org::text || '/' || v_pat1::text || '/a.pdf'), ('clinical-records', v_org::text || '/' || v_pat2::text || '/b.pdf');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
      select count(*) into v_cnt from storage.objects where bucket_id = 'clinical-records' and name = v_org::text || '/' || v_pat1::text || '/a.pdf';
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-42 · SEG-02 · ATAQUE: el segundo Médico no baja el archivo del paciente ajeno','ok',v_cnt = 0,'d',v_cnt::text));
      select count(*) into v_cnt from storage.objects where bucket_id = 'clinical-records' and name = v_org::text || '/' || v_pat2::text || '/b.pdf';
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-43 · SEG-02 · Uso legítimo: sí baja el de su paciente','ok',v_cnt = 1,'d',v_cnt::text));
      begin
        insert into storage.objects (bucket_id, name) values ('clinical-records', v_org::text || '/' || v_pat1::text || '/x.pdf');
        v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-44 · SEG-02 · El segundo Médico no sube archivos al paciente ajeno','ok',false,'d','Se permitió'));
      exception when others then
        v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-44 · SEG-02 · El segundo Médico no sube archivos al paciente ajeno','ok',sqlerrm like '%row-level security%','d',left(sqlerrm,160)));
      end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
      select count(*) into v_cnt from storage.objects where bucket_id = 'clinical-records' and name = v_org::text || '/' || v_pat1::text || '/a.pdf';
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-45 · SEG-02 · Uso legítimo: el Dr. Uno baja el archivo de su paciente','ok',v_cnt = 1,'d',v_cnt::text));
      begin
        insert into storage.objects (bucket_id, name) values ('clinical-records', v_org::text || '/' || v_pat1::text || '/c.pdf');
        v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-46 · SEG-02 · Uso legítimo: el Dr. Uno sube un archivo a su paciente','ok',true,'d',(null)::text));
      exception when others then
        v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-46 · SEG-02 · Uso legítimo: el Dr. Uno sube un archivo a su paciente','ok',false,'d',left(sqlerrm,160)));
      end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
      update public.clinical_settings set require_mfa = true where organization_id = v_org;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
      select count(*) into v_cnt from storage.objects where bucket_id = 'clinical-records' and name = v_org::text || '/' || v_pat1::text || '/a.pdf';
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-47 · SEG-06 · ATAQUE: con dos pasos exigidos y sesión de un paso, no se lista el archivo','ok',v_cnt = 0,'d',v_cnt::text));
      begin
        insert into storage.objects (bucket_id, name) values ('clinical-records', v_org::text || '/' || v_pat1::text || '/d.pdf');
        v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-48 · SEG-06 · Ni se sube con sesión de un paso','ok',false,'d','Se permitió'));
      exception when others then
        v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-48 · SEG-06 · Ni se sube con sesión de un paso','ok',sqlerrm like '%row-level security%','d',left(sqlerrm,160)));
      end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal2')::text, true);
      select count(*) into v_cnt from storage.objects where bucket_id = 'clinical-records' and name = v_org::text || '/' || v_pat1::text || '/a.pdf';
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-49 · SEG-06 · Uso legítimo: con dos pasos (aal2) sí se lista','ok',v_cnt = 1,'d',v_cnt::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-42 a 49 · Pruebas del almacén de archivos (no se pudieron correr)','ok',false,'d',left(sqlerrm,200)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.clinical_settings set require_mfa = false where organization_id = v_org;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.link_provider_user(v_pa1, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-50 · SEG-02 · Desenlazar (usuario vacío) al Dr. Uno','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-50 · SEG-02 · Desenlazar (usuario vacío) al Dr. Uno','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      perform public.link_provider_user(v_pa2, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-51 · SEG-02 · Desenlazar a la Dra. Dos','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-51 · SEG-02 · Desenlazar a la Dra. Dos','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000022', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.clinical_record(v_pat1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-52 · SEG-02 · Sin médicos enlazados vuelve el comportamiento de un solo consultorio','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-52 · SEG-02 · Sin médicos enlazados vuelve el comportamiento de un solo consultorio','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000023', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_x := public.portal_link_create(v_pat1, 30, true);
    v_tok := v_x->>'token';
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-53 · SEG-03 · ATAQUE: el enlace creado por la Secretaria no muestra órdenes','ok',coalesce(((v_x->>'show_orders')::boolean = false and (select show_orders from public.patient_portal_links where token_hash = app.sha256(v_tok)) = false), false),'d',(null)::text));
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-54 · SEG-03 · Abierto sin sesión, el portal no trae las recetas','ok',coalesce((jsonb_typeof(public.portal_view(v_tok)->'orders') = 'null'), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.portal_link_create(v_pat1, 30, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-55 · SEG-03 · ATAQUE: el Administrador no crea enlaces de pacientes de un consultorio','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-55 · SEG-03 · ATAQUE: el Administrador no crea enlaces de pacientes de un consultorio','ok',sqlerrm like 'Sin acceso a este paciente%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000011', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.portal_link_create(v_pat1, 30, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-56 · SEG-03 · Ni el Super Admin','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-56 · SEG-03 · Ni el Super Admin','ok',sqlerrm like 'Sin acceso a este paciente%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_x := public.portal_link_create(v_pat1, 30, true);
    v_tok2 := v_x->>'token';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-57 · SEG-03 · Uso legítimo: el médico sí deja las órdenes visibles','ok',coalesce(((v_x->>'show_orders')::boolean), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select count(*) into v_log0 from public.clinical_access_log where patient_id = v_pat1 and detail = 'portal del paciente';
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '', true);
    v_x := public.portal_view(v_tok2);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-58 · SEG-03 · Uso legítimo: el portal muestra la receta del médico','ok',coalesce((jsonb_array_length(v_x->'orders') = 1), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-59 · SEG-03 · Cada vista con órdenes queda en la bitácora clínica','ok',coalesce(((select count(*) from public.clinical_access_log where patient_id = v_pat1 and detail = 'portal del paciente') = v_log0 + 1), false),'d',(null)::text));
    insert into public.message_queue (organization_id, provider_id, kind, appointment_id, patient_id, to_phone, subject, body, scheduled_for, has_portal_link)
    values (v_org, v_pa1, 'recordatorio_cita', (select id from public.appointments where patient_id = v_pat1 limit 1), v_pat1, '8095550171', 'Recordatorio de cita', 'Hola, le recordamos su cita. {enlace}', current_date + 1, true) returning id into v_msg;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform public.portal_link_create(v_pat1, 30, false);
    v_tok := public.message_portal_link(v_msg)->>'token';
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select show_orders into v_sh1 from public.patient_portal_links where token_hash = app.sha256(v_tok);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-60 · SEG-03 · ATAQUE: el recordatorio no vuelve a activar las órdenes que el médico ocultó','ok',coalesce((v_sh1 = false), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    perform public.portal_link_create(v_pat1, 30, true);
    v_tok := public.message_portal_link(v_msg)->>'token';
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select show_orders into v_sh2 from public.patient_portal_links where token_hash = app.sha256(v_tok);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-61 · SEG-03 · Uso legítimo: el recordatorio hereda la elección del médico (órdenes visibles)','ok',coalesce((v_sh2 = true), false),'d',(null)::text));
    delete from public.patient_portal_links where patient_id = v_pat1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_tok := public.message_portal_link(v_msg)->>'token';
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select show_orders into v_sh3 from public.patient_portal_links where token_hash = app.sha256(v_tok);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-62 · SEG-03 · Sin enlace anterior, el recordatorio nace con las órdenes ocultas','ok',coalesce((v_sh3 = false), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-63 · SEG-05 · Interruptor apagado: el Administrador con un paso sigue como personal','ok',coalesce((app.is_staff() and app.role_for_org(v_org) = 'admin' and app.mfa_ok()), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-64 · SEG-05 · El interruptor nace apagado','ok',coalesce((not exists (select 1 from public.app_settings where require_staff_mfa)), false),'d',(null)::text));
    begin
      update public.app_settings set require_staff_mfa = true where true; if exists (select 1 from public.app_settings where require_staff_mfa) then raise exception 'cambio aplicado'; end if; raise exception 'sin cambio (la política o el disparador lo frenó)';
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-65 · SEG-05 · Encender el interruptor sin haber entrado con dos pasos se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-65 · SEG-05 · Encender el interruptor sin haber entrado con dos pasos se rechaza','ok',sqlerrm like 'sin cambio%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.app_settings set require_staff_mfa = true where true;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-66 · SEG-05 · ATAQUE: con el interruptor encendido, el Administrador con un paso no es personal','ok',coalesce((not app.is_staff() and app.role_for_org(v_org) is null and not app.mfa_ok()), false),'d',(null)::text));
    begin
      perform public.link_provider_user(v_pa1, '17100000-0000-4000-8000-000000000021'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-67 · SEG-05 · Ni administra (enlazar usuarios)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-67 · SEG-05 · Ni administra (enlazar usuarios)','ok',sqlerrm like 'Solo el Super Admin o un Administrador%','d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-68 · SEG-05 · Ni ve organizaciones de clientes','ok',coalesce((not exists (select 1 from app.visible_org_ids() o where o = v_org)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-69 · SEG-05 · Autoservicio: my_context sigue funcionando','ok',coalesce((jsonb_array_length(public.my_context()->'memberships') >= 1), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-70 · SEG-05 · Autoservicio: my_security_state sigue funcionando','ok',coalesce((public.my_security_state() ? 'must_change_password'), false),'d',(null)::text));
    begin
      perform public.confirm_password_changed();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-71 · SEG-05 · Autoservicio: confirm_password_changed sigue funcionando','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-71 · SEG-05 · Autoservicio: confirm_password_changed sigue funcionando','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-72 · SEG-05 · Uso legítimo: con dos pasos (aal2) el Administrador es personal','ok',coalesce((app.is_staff() and app.role_for_org(v_org) = 'admin'), false),'d',(null)::text));
    begin
      perform public.link_provider_user(v_pa1, '17100000-0000-4000-8000-000000000021'::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-73 · SEG-05 · Y administra','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-73 · SEG-05 · Y administra','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-74 · SEG-05 · El Médico (no es personal) no necesita dos pasos','ok',coalesce((app.role_for_org(v_org) = 'client'), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.app_settings set require_staff_mfa = false where true;
    update public.providers set user_id = null where id = v_pa1;
    update public.profiles set must_change_password = true where id in ('17100000-0000-4000-8000-000000000033'::uuid, '17100000-0000-4000-8000-000000000034'::uuid);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000033', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-75 · SEG-09 · ATAQUE: con clave temporal, el personal no es personal','ok',coalesce((not app.is_staff()), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000034', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-76 · SEG-09 · ATAQUE: con clave temporal, el Médico no ve su organización','ok',coalesce((app.role_for_org(v_orgb) is null and not exists (select 1 from app.visible_org_ids() o where o = v_orgb)), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-77 · SEG-09 · Autoservicio: my_context funciona y my_security_state dice que debe cambiarla','ok',coalesce((jsonb_array_length(public.my_context()->'memberships') >= 1 and (public.my_security_state()->>'must_change_password')::boolean), false),'d',(null)::text));
    begin
      perform public.confirm_password_changed();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-78 · SEG-09 · Autoservicio: confirm_password_changed funciona','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-78 · SEG-09 · Autoservicio: confirm_password_changed funciona','ok',false,'d',left(sqlerrm,160)));
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-79 · SEG-09 · Uso legítimo: al cambiar la clave recupera el acceso','ok',coalesce((app.role_for_org(v_orgb) = 'client' and exists (select 1 from app.visible_org_ids() o where o = v_orgb)), false),'d',(null)::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.ars (code, name, regime_default, is_active) values ('qa_bs_ars', 'ARS QA Blindaje', 'Contributivo', true) returning id into v_ars;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    v_per := date_trunc('month', current_date - 120)::date;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_pa1, v_ars, v_per, 1, 'borrador', current_date - 60) returning id into v_s1;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_org, v_pa1, v_ars, v_per, 2, 'borrador', current_date - 50) returning id into v_s2;
    insert into public.submissions (organization_id, provider_id, ars_id, period, sequence, status, submitted_on) values (v_orgb, v_pb, v_ars, v_per, 1, 'borrador', current_date - 60) returning id into v_sb;
    insert into public.health_centers (organization_id, name) values (v_org, 'Centro QA Uno') returning id into v_cen;
    insert into public.health_centers (organization_id, name) values (v_orgb, 'Centro QA B') returning id into v_cenb;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, patient_id, authorization_date)
    values (v_s1, v_org, v_per + 3, 'Paciente Uno QA', v_proc, 1, 1230, v_pat1, current_date - 40) returning id into v_l1;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, patient_id)
    values (v_s1, v_org, v_per + 4, 'Paciente Dos QA', v_proc, 1, 1800, v_pat2) returning id into v_l2;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, patient_id, authorization_date)
    values (v_s1, v_org, v_per + 5, 'Paciente Uno QA', v_proc, 1, 500, v_pat1, current_date - 40) returning id into v_l3;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, patient_id, authorization_date)
    values (v_s2, v_org, v_per + 7, 'Paciente Uno QA', v_proc, 1, 700, v_pat1, current_date - 40) returning id into v_l4;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, patient_id)
    values (v_s2, v_org, v_per + 8, 'Paciente Dos QA', v_proc, 1, 800, v_pat2) returning id into v_l5;
    perform set_config('app.claim_change', 'on', true);
    update public.service_lines set claim_status = 'radicada' where id = v_l3;
    perform set_config('app.claim_change', '', true);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_pay := public.register_payment(v_org, v_ars, current_date - 10, 3030, 'transferencia', 'PAGO-QA-BS', jsonb_build_array(jsonb_build_object('submission_id', v_s1, 'amount', 3030)));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    select id into v_alloc from public.payment_allocations where payment_id = v_pay limit 1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000013', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.adjust_payment_distribution(v_alloc, jsonb_build_array(jsonb_build_object('service_line_id', v_l1, 'amount', 1230), jsonb_build_object('service_line_id', v_l2, 'amount', 1800)), 'Ajuste de prueba QA');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-80 · SEG-07 · ATAQUE: Facturación no reparte pagos de las ARS','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-80 · SEG-07 · ATAQUE: Facturación no reparte pagos de las ARS','ok',sqlerrm like 'Solo Cobros o un administrador%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000013', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.payment_line_allocations set reason = 'manipulado' where allocation_id = v_alloc; if not found then raise exception 'sin filas visibles (política)'; end if; raise exception 'se actualizó';
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-81 · SEG-07 · ATAQUE: Facturación no toca payment_line_allocations directo (el guard actúa aunque la política se saltara)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-81 · SEG-07 · ATAQUE: Facturación no toca payment_line_allocations directo (el guard actúa aunque la política se saltara)','ok',sqlerrm like 'El rol Facturación no registra ni reparte%','d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000014', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      perform public.adjust_payment_distribution(v_alloc, jsonb_build_array(jsonb_build_object('service_line_id', v_l1, 'amount', 3030), jsonb_build_object('service_line_id', v_l2, 'amount', 0)), 'Todo a una sola reclamación');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-82 · SEG-07 · ATAQUE: no se asigna a una reclamación más de su monto','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-82 · SEG-07 · ATAQUE: no se asigna a una reclamación más de su monto','ok',sqlerrm like 'A la reclamación % se le asignan%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.adjust_payment_distribution(v_alloc, jsonb_build_array(jsonb_build_object('service_line_id', v_l1, 'amount', 1230), jsonb_build_object('service_line_id', v_l2, 'amount', 1800)), 'Relación de pago de la ARS');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-83 · SEG-07 · Uso legítimo: Cobros reparte según el monto de cada reclamación','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-83 · SEG-07 · Uso legítimo: Cobros reparte según el monto de cada reclamación','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-84 · SEG-07 · El reparto quedó igual al monto de cada reclamación','ok',coalesce(((select sum(amount) from public.payment_line_allocations where allocation_id = v_alloc and superseded_at is null and service_line_id = v_l1) = 1230 and (select sum(amount) from public.payment_line_allocations where allocation_id = v_alloc and superseded_at is null and service_line_id = v_l2) = 1800), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000012', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    begin
      update public.service_lines set patient_id = v_pat2 where id = v_l3;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-85 · SEG-08 · ATAQUE: no se cambia el paciente de una reclamación ya radicada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-85 · SEG-08 · ATAQUE: no se cambia el paciente de una reclamación ya radicada','ok',sqlerrm like 'La reclamación % está en%','d',left(sqlerrm,160)));
    end;
    begin
      update public.service_lines set patient_id = v_pat2 where id = v_l1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-85b · SEG-08 · ATAQUE: ni el de una reclamación ya pagada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-85b · SEG-08 · ATAQUE: ni el de una reclamación ya pagada','ok',sqlerrm like 'La reclamación % está en%','d',left(sqlerrm,160)));
    end;
    begin
      update public.service_lines set authorization_date = current_date - 5 where id = v_l1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-85c · SEG-08 · ATAQUE: ni la fecha de autorización de una reclamación pagada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-85c · SEG-08 · ATAQUE: ni la fecha de autorización de una reclamación pagada','ok',sqlerrm like 'La reclamación % está en%','d',left(sqlerrm,160)));
    end;
    begin
      update public.service_lines set authorization_date = current_date - 5 where id = v_l4;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-86 · SEG-08 · ATAQUE: ni la fecha de autorización con un update directo (aunque sea editable)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-86 · SEG-08 · ATAQUE: ni la fecha de autorización con un update directo (aunque sea editable)','ok',sqlerrm like 'La fecha de autorización se cambia desde%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.set_claim_authorization_date(v_l3, current_date - 3);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-87 · SEG-08 · ATAQUE: ni siquiera con la función cuando ya fue radicada','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-87 · SEG-08 · ATAQUE: ni siquiera con la función cuando ya fue radicada','ok',sqlerrm like 'La reclamación ya fue radicada%','d',left(sqlerrm,160)));
    end;
    begin
      update public.service_lines set patient_id = v_patb where id = v_l5;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-88 · SEG-08 · ATAQUE: no se enlaza un paciente de otro cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-88 · SEG-08 · ATAQUE: no se enlaza un paciente de otro cliente','ok',sqlerrm like 'Ese paciente no pertenece a este cliente%','d',left(sqlerrm,160)));
    end;
    begin
      update public.service_lines set center_id = v_cenb where id = v_l5;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-89 · SEG-08 · ATAQUE: ni un centro de otro cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-89 · SEG-08 · ATAQUE: ni un centro de otro cliente','ok',sqlerrm like 'Ese centro no pertenece a este cliente%','d',left(sqlerrm,160)));
    end;
    begin
      perform public.set_claim_authorization_date(v_l4, current_date - 5);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-90 · SEG-08 · Uso legítimo: la función cambia la fecha de autorización de una reclamación editable','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-90 · SEG-08 · Uso legítimo: la función cambia la fecha de autorización de una reclamación editable','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      update public.service_lines set patient_id = v_pat1 where id = v_l5;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-91 · SEG-08 · Uso legítimo: se corrige el paciente por otro del mismo cliente (reclamación editable)','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-91 · SEG-08 · Uso legítimo: se corrige el paciente por otro del mismo cliente (reclamación editable)','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      update public.service_lines set center_id = v_cen where id = v_l5;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-92 · SEG-08 · Uso legítimo: se asigna un centro del mismo cliente','ok',true,'d',(null)::text));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-92 · SEG-08 · Uso legítimo: se asigna un centro del mismo cliente','ok',false,'d',left(sqlerrm,160)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-93 · SEG-08 · La fecha de autorización editada quedó guardada','ok',coalesce(((select authorization_date from public.service_lines where id = v_l4) = current_date - 5), false),'d',(null)::text));
    alter table public.service_lines disable trigger service_lines_guard;
    insert into public.service_lines (submission_id, organization_id, service_date, patient_name, procedure_id, quantity, unit_amount, patient_id)
    values (v_sb, v_orgb, v_per + 6, 'Paciente Otro Cliente', v_proc, 1, 999, v_pat1) returning id into v_lb;
    alter table public.service_lines enable trigger service_lines_guard;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', '17100000-0000-4000-8000-000000000021', 'role', 'authenticated', 'aal', 'aal1')::text, true);
    v_x := public.patient_card(v_pat1);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-94 · SEG-08 · ATAQUE: la ficha no muestra reclamaciones de otro cliente enlazadas a su paciente','ok',coalesce((not exists (select 1 from jsonb_array_elements(v_x->'claims') c where c->>'folio' = (select claim_folio from public.service_lines where id = v_lb))), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-95 · SEG-08 · Uso legítimo: la ficha sí muestra las reclamaciones propias','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'claims') c where c->>'folio' = (select claim_folio from public.service_lines where id = v_l1))), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-96 · Permisos · Sin sesión no se ejecutan link_provider_user ni clinical_patient_ok','ok',coalesce((not has_function_privilege('anon', 'public.link_provider_user(uuid,uuid)', 'execute') and not has_function_privilege('anon', 'app.clinical_patient_ok(uuid,uuid)', 'execute')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','BS-97 · La migración 170 queda registrada','ok',coalesce((exists (select 1 from app.schema_migrations where version = '170')), false),'d',(null)::text));
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

revoke all on function app.qa_run_tests_blindaje_1() from public, anon, authenticated;
