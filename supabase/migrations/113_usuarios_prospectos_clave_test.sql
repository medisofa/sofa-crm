-- 113 · Suite de la 112 (restablecer contraseña y usuarios de prospectos). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_usuarios_prospectos();
create or replace function app.qa_run_tests_usuarios_prospectos()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_lead uuid; v_org uuid := 'b7000000-0000-4000-8000-0000000001c1';
  v_op  constant uuid := '00000000-0000-4000-8000-000000000001';
  v_sa  constant text := 'a7000000-0000-4000-8000-0000000001c1';
  v_adm constant text := 'a7000000-0000-4000-8000-0000000001c2';
  v_pro constant text := 'a7000000-0000-4000-8000-0000000001c3';
  v_med constant text := 'a7000000-0000-4000-8000-0000000001c4';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.up.sa@sofa.test','x'),(v_adm::uuid,'qa.up.adm@sofa.test','x'),
      (v_pro::uuid,'qa.up.pro@sofa.test','hash-temporal'),(v_med::uuid,'qa.up.med@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.up.%@sofa.test' on conflict (id) do nothing;
    insert into public.organization_users (organization_id, user_id, role_code) values (v_op, v_sa::uuid, 'super_admin'), (v_op, v_adm::uuid, 'admin');
    insert into public.leads (operator_id, company, contact_name) values (v_op, 'QA Prospecto Clínica', 'Dra. QA') returning id into v_lead;
    perform set_config('role', 'authenticated', true);

    -- Restablecer contraseña
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    begin
      perform public.authorize_password_reset(v_pro::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · El Administrador no restablece contraseñas','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · El Administrador no restablece contraseñas','ok',sqlerrm like 'Solo el Super Admin restablece%','d',left(sqlerrm,100)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    begin
      perform public.authorize_password_reset(v_sa::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · No se restablece la propia (usa Cambiar contraseña)','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · No se restablece la propia (usa Cambiar contraseña)','ok',sqlerrm like 'Para cambiar su propia contraseña%','d',left(sqlerrm,100)));
    end;
    v_x := public.authorize_password_reset(v_pro::uuid);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · El Super Admin puede restablecer a otro usuario','ok',v_x->>'email' = 'qa.up.pro@sofa.test','d',v_x::text));
    begin
      perform public.mark_password_reset(v_pro::uuid, v_sa::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Con sesión nadie llama el registro interno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Con sesión nadie llama el registro interno','ok',sqlstate = '42501','d',left(sqlerrm,100)));
    end;
    perform set_config('role', 'none', true);
    perform public.mark_password_reset(v_pro::uuid, v_sa::uuid);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Tras restablecer, debe cambiar la clave y queda en la bitácora','ok',
      (select must_change_password from public.profiles where id = v_pro::uuid) and exists (select 1 from app.password_stamps where user_id = v_pro::uuid)
      and exists (select 1 from public.user_admin_log where target_id = v_pro::uuid and action = 'restablecer_clave'),'d',null));
    begin
      delete from public.user_admin_log where target_id = v_pro::uuid;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · La bitácora de usuarios no se borra','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · La bitácora de usuarios no se borra','ok',sqlerrm like 'La bitácora de usuarios no se modifica%','d',left(sqlerrm,100)));
    end;

    -- Prospectos
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    begin
      perform public.authorize_prospect_user(v_lead);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Un usuario sin rol SOFA no crea prospectos','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Un usuario sin rol SOFA no crea prospectos','ok',sqlerrm like 'Solo Administración o Comercial%','d',left(sqlerrm,100)));
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.authorize_prospect_user(v_lead);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Administración autoriza el usuario del prospecto','ok',(v_x->>'ok')::boolean,'d',v_x::text));
    v_x := public.prospect_options();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · La lista de prospectos trae el prospecto','ok',exists (select 1 from jsonb_array_elements(v_x) e where e->>'id' = v_lead::text),'d',null));
    perform set_config('role', 'none', true);
    perform public.register_prospect_user(v_pro::uuid, v_lead, v_adm::uuid);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_pro, 'role', 'authenticated')::text, true);
    v_x := public.my_context();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-10 · El prospecto entra con el rol Prospecto','ok',
      exists (select 1 from jsonb_array_elements(v_x->'memberships') m where m->>'role' = 'prospect' and m->>'organization' = 'QA Prospecto Clínica'),'d',(v_x->'memberships')::text));
    v_x := public.prospect_portal();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-11 · Ve su portal de incorporación','ok',v_x->>'company' = 'QA Prospecto Clínica','d',null));
    begin
      perform public.authorize_password_reset(v_med::uuid);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · El prospecto no administra usuarios','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-12 · El prospecto no administra usuarios','ok',sqlstate = '42501','d',left(sqlerrm,100)));
    end;

    -- Conversión a cliente
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', v_op, 'QA Prospecto Clínica', '00000000501', 'Clínica', 'incorporacion', current_date, '8095550051');
    update public.leads set converted_org_id = v_org where id = v_lead;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-13 · Al convertir, el usuario pasa a Médico del cliente','ok',
      exists (select 1 from public.organization_users where organization_id = v_org and user_id = v_pro::uuid and role_code = 'client')
      and not exists (select 1 from public.lead_users where user_id = v_pro::uuid and is_active),'d',null));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_pro, 'role', 'authenticated')::text, true);
    v_x := public.my_context();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-14 · Ya no aparece como Prospecto','ok',
      not exists (select 1 from jsonb_array_elements(v_x->'memberships') m where m->>'role' = 'prospect'),'d',(v_x->'memberships')::text));
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    begin
      perform public.authorize_prospect_user(v_lead);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-15 · Prospecto convertido: se crea como Médico del cliente','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-15 · Prospecto convertido: se crea como Médico del cliente','ok',sqlerrm like 'Ese prospecto ya es cliente%','d',left(sqlerrm,100)));
    end;

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
