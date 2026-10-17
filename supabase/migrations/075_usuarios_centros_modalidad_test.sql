-- 075 · Suite de la 074 (usuarios con clave temporal, centros por médico, modalidad por especialidad). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_usuarios_centros();
create or replace function app.qa_run_tests_usuarios_centros()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_ok boolean; v_n int; v_k int; v_x jsonb; v_c1 uuid; v_c2 uuid; v_cb uuid; v_msg text;
  v_orgA constant uuid := 'b7000000-0000-4000-8000-0000000000e1';
  v_orgB constant uuid := 'b7000000-0000-4000-8000-0000000000e2';
  v_pA constant uuid := 'c7000000-0000-4000-8000-0000000000e1';
  v_pB constant uuid := 'c7000000-0000-4000-8000-0000000000e2';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_admin constant text := 'a7000000-0000-4000-8000-0000000000e1';
  v_fact constant text := 'a7000000-0000-4000-8000-0000000000e2';
  v_cliA constant text := 'a7000000-0000-4000-8000-0000000000e3';
  v_cliB constant text := 'a7000000-0000-4000-8000-0000000000e4';
  v_s1 constant text := 'a7000000-0000-4000-8000-0000000000e5';
  v_s2 constant text := 'a7000000-0000-4000-8000-0000000000e6';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values
      (v_admin::uuid,'qa.uc.admin@sofa.test','hash-inicial'), (v_fact::uuid,'qa.uc.fact@sofa.test','hash-inicial'), (v_cliA::uuid,'qa.uc.cliA@sofa.test','hash-inicial'),
      (v_cliB::uuid,'qa.uc.cliB@sofa.test','hash-inicial'), (v_s1::uuid,'qa.uc.s1@sofa.test','hash-inicial'), (v_s2::uuid,'qa.uc.s2@sofa.test','hash-inicial');
    insert into public.profiles (id, full_name) select id, replace(email, '@sofa.test', '') from auth.users where email like 'qa.uc.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_orgA, 'client', v_op, 'QA UC A', '00000000141', 'Médico independiente', 'activo', current_date - 90, '8095550001'),
      (v_orgB, 'client', v_op, 'QA UC B', '00000000142', 'Médico independiente', 'activo', current_date - 90, '8295550002');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_pA, v_orgA, 'Dr. UC A', 'Cirugía General'), (v_pB, v_orgB, 'Dr. UC B', 'Pediatría');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (v_op, v_admin::uuid, 'admin'), (v_op, v_fact::uuid, 'billing'), (v_orgA, v_cliA::uuid, 'client'), (v_orgB, v_cliB::uuid, 'client');

    -- CT-01 · SOFA (Administrador) puede autorizar el alta de Facturación en la operadora
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.authorize_user_creation(v_op, 'billing');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · El Administrador de SOFA autoriza crear Facturación','ok',(v_x->>'ok')::boolean,'d',v_x::text));

    -- CT-02 · El Administrador no crea Super Admin
    begin
      perform public.authorize_user_creation(v_op, 'super_admin');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · El Administrador no crea Super Admin','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · El Administrador no crea Super Admin','ok',sqlerrm like 'Solo el Super Admin%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    -- CT-03 · Rol de personal SOFA no se crea dentro de un cliente
    begin
      perform public.authorize_user_creation(v_orgA, 'billing');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Un rol de SOFA no se crea dentro de un cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Un rol de SOFA no se crea dentro de un cliente','ok',sqlerrm like '%solo se crea en la organización operadora%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-04 · El médico autoriza crear una Secretaria para su propio médico
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.authorize_user_creation(v_orgA, 'capturer', array[v_pA]);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · El médico autoriza crear una secretaria suya','ok',(v_x->>'ok')::boolean,'d',v_x::text));

    -- CT-05 · El médico no crea Administradores ni Médicos
    begin
      perform public.authorize_user_creation(v_orgA, 'client');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · El médico solo crea Secretarias','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · El médico solo crea Secretarias','ok',sqlerrm like 'No tiene permiso para crear este usuario%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;

    -- CT-06 · Secretaria sin médico se rechaza
    begin
      perform public.authorize_user_creation(v_orgA, 'capturer', '{}'::uuid[]);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · La secretaria necesita al menos un médico','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · La secretaria necesita al menos un médico','ok',sqlerrm like 'Indique al menos un médico%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-07 · Otro médico no crea secretarias del médico A
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.authorize_user_creation(v_orgA, 'capturer', array[v_pA]);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro médico no crea secretarias ajenas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Otro médico no crea secretarias ajenas','ok',sqlerrm like 'No tiene permiso para crear este usuario%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-08 · Facturación no autoriza ningún alta
    perform set_config('request.jwt.claims', json_build_object('sub',v_fact,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.authorize_user_creation(v_op, 'billing');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no crea usuarios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Facturación no crea usuarios','ok',sqlerrm like 'No tiene permiso para crear este usuario%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-09 · Alta efectiva: dos secretarias para el mismo médico, marcadas para cambiar la clave
    perform public.register_new_user(v_s1::uuid, v_orgA, 'capturer', array[v_pA], true, false, v_cliA::uuid);
    perform public.register_new_user(v_s2::uuid, v_orgA, 'capturer', array[v_pA], true, true, v_cliA::uuid);
    select count(*) into v_n from public.capturer_scopes where provider_id = v_pA;
    select count(*) into v_k from public.profiles where id in (v_s1::uuid, v_s2::uuid) and must_change_password;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Dos secretarias para el mismo médico, ambas con cambio de clave pendiente','ok',v_n = 2 and v_k = 2,'d',v_n || ' secretarias · ' || v_k || ' con cambio pendiente'));

    -- CT-10 · Los permisos por secretaria se guardan como se indicaron
    select count(*) into v_n from public.capturer_scopes where user_id = v_s2::uuid and can_book and can_whatsapp;
    select count(*) into v_k from public.capturer_scopes where user_id = v_s1::uuid and can_book and not can_whatsapp;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · Cada secretaria queda con los permisos indicados','ok',v_n = 1 and v_k = 1,'d',null));

    -- CT-11 · Mientras la clave sea la temporal, no se libera el cambio; después de cambiarla, sí
    perform set_config('request.jwt.claims', json_build_object('sub',v_s1,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.my_security_state();
    begin
      perform public.confirm_password_changed();
      v_ok := false; v_msg := 'Se permitió con la clave temporal';
    exception when others then
      v_ok := (v_x->>'must_change_password')::boolean and sqlerrm like 'La contraseña todavía es la temporal%'; v_msg := 'Bloqueado: ' || left(sqlerrm, 100);
    end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11a · Con la clave temporal no se libera el cambio obligatorio','ok',v_ok,'d',v_msg));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    update auth.users set encrypted_password = 'hash-nuevo' where id = v_s1::uuid;
    perform set_config('request.jwt.claims', json_build_object('sub',v_s1,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.confirm_password_changed();
    v_x := public.my_security_state();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11b · Cambiada la clave, el cambio obligatorio se libera','ok',not (v_x->>'must_change_password')::boolean,'d',v_x::text));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-12 · Centros de salud: el médico registra dos y se los asigna, con uno principal
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_c1 := public.save_health_center(null, v_orgA, 'Centro Médico Norte', '101010101');
    v_c2 := public.save_health_center(null, v_orgA, 'Clínica Cibao Sur', null);
    perform public.set_provider_centers(v_pA, array[v_c1, v_c2], v_c2);
    v_x := public.provider_centers_of(v_pA);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · Un médico con dos centros y el principal primero','ok',jsonb_array_length(v_x) = 2 and (v_x->0->>'primary')::boolean and v_x->0->>'name' = 'Clínica Cibao Sur','d',v_x::text));

    -- CT-13 · Nombre de centro repetido se rechaza
    begin
      perform public.save_health_center(null, v_orgA, 'centro médico norte', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-13 · No se repite el nombre de un centro','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-13 · No se repite el nombre de un centro','ok',sqlerrm like 'Ya existe un centro con ese nombre%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-14 · Otro médico no asigna centros ni usa centros ajenos
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.set_provider_centers(v_pA, array[v_c1], null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14a · Otro médico no asigna centros al médico A','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14a · Otro médico no asigna centros al médico A','ok',sqlerrm like 'Solo el médico o el Administrador%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    v_cb := public.save_health_center(null, v_orgB, 'Centro de B', null);
    begin
      perform public.set_provider_centers(v_pB, array[v_c1], null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14b · Un médico no usa centros de otro cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14b · Un médico no usa centros de otro cliente','ok',sqlerrm like 'Alguno de los centros no existe%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    select count(*) into v_n from public.health_centers where organization_id = v_orgA;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14c · RLS: el médico B no ve los centros del A','ok',v_n = 0,'d',v_n || ' visibles'));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-15 · Modalidad por especialidad: lista configurada para Cirugía General, resto con todas
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.set_specialty_care_modes('Cirugía General', array['consultorio','hospitalizacion','cirugia','uci']);
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliA,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.care_modes_for(v_pA);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-15a · Cirugía General ve consultorio, hospitalización, cirugía y UCI (sin emergencia)','ok',jsonb_array_length(v_x) = 4 and not (v_x::text like '%emergencia%'),'d',v_x::text));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claims', json_build_object('sub',v_cliB,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.care_modes_for(v_pB);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-15b · Una especialidad sin lista configurada ve las cinco modalidades vigentes','ok',jsonb_array_length(v_x) = 5 and not (v_x::text like '%"ambulatorio"%'),'d',v_x::text));
    begin
      perform public.set_specialty_care_modes('Pediatría', array['consultorio']);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-15c · Un médico no define modalidades','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-15c · Un médico no define modalidades','ok',sqlerrm like 'Solo SOFA%','d','Bloqueado: ' || left(sqlerrm, 110)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- CT-16 · Equivalencias con las modalidades originales y valores permitidos en la reclamación
    v_ok := app.care_mode_base('consultorio') = 'ambulatorio' and app.care_mode_base('uci') = 'internamiento' and app.care_mode_base('cirugia') = 'internamiento'
        and app.care_mode_base('emergencia') = 'emergencia' and app.care_mode_base(null) = 'ambulatorio'
        and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'service_lines_care_mode_chk' and conrelid = 'public.service_lines'::regclass) like '%cirugia%'
        and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'service_lines_care_mode_chk' and conrelid = 'public.service_lines'::regclass) like '%uci%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-16 · Las modalidades nuevas equivalen a las originales y la reclamación las acepta','ok',v_ok,'d',null));

    -- CT-17 · Permisos de ejecución: el alta efectiva solo para service_role; nada para anon
    v_ok := not has_function_privilege('authenticated', 'public.register_new_user(uuid,uuid,text,uuid[],boolean,boolean,uuid)'::regprocedure, 'EXECUTE')
        and not has_function_privilege('anon', 'public.register_new_user(uuid,uuid,text,uuid[],boolean,boolean,uuid)'::regprocedure, 'EXECUTE')
        and has_function_privilege('service_role', 'public.register_new_user(uuid,uuid,text,uuid[],boolean,boolean,uuid)'::regprocedure, 'EXECUTE')
        and not has_function_privilege('anon', 'public.authorize_user_creation(uuid,text,uuid[])'::regprocedure, 'EXECUTE')
        and not has_function_privilege('anon', 'public.set_provider_centers(uuid,uuid[],uuid)'::regprocedure, 'EXECUTE')
        and not has_function_privilege('anon', 'public.care_modes_for(uuid)'::regprocedure, 'EXECUTE');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-17 · register_new_user solo para service_role; anon sin acceso','ok',v_ok,'d',null));

    -- CT-18 · Las funciones nuevas tienen search_path fijo
    v_ok := (select bool_and(coalesce(p.proconfig::text, '') like '%search_path%') from pg_proc p where p.oid in (
        'public.my_security_state()'::regprocedure, 'public.confirm_password_changed()'::regprocedure, 'public.authorize_user_creation(uuid,text,uuid[])'::regprocedure,
        'public.register_new_user(uuid,uuid,text,uuid[],boolean,boolean,uuid)'::regprocedure, 'public.save_health_center(uuid,uuid,text,text,boolean)'::regprocedure,
        'public.set_provider_centers(uuid,uuid[],uuid)'::regprocedure, 'public.provider_centers_of(uuid)'::regprocedure, 'public.care_modes_for(uuid)'::regprocedure,
        'public.set_specialty_care_modes(text,text[])'::regprocedure, 'app.care_mode_base(text)'::regprocedure));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-18 · Las funciones nuevas tienen search_path fijo','ok',v_ok,'d',null));

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
