-- 209 · Prueba de la 208 (Alcance del Auditor · I70). app.qa_run_tests_alcance_auditor()
-- Se deshace sola (rollback por excepción). No deja datos.
create or replace function app.qa_run_tests_alcance_auditor()
returns table(n int, resultado text, prueba text, detalle text)
language plpgsql
as $function$
declare
  v_res jsonb := '[]'::jsonb;
  v_op  constant uuid := '00000000-0000-4000-8000-000000000001';
  v_org uuid;
  v_aud constant uuid := '20800000-0000-4000-8000-0000000000a1';   -- Auditor
  v_adm constant uuid := '20800000-0000-4000-8000-0000000000a2';   -- Administrador
  v_sa  constant uuid := '20800000-0000-4000-8000-0000000000a3';   -- Super Admin
  v_ok boolean; v_n int; v_t text;
begin
  if not exists (select 1 from app.schema_migrations where version = '208') then
    raise exception 'Falta la migración 208. Aplícala y vuelve a correr las pruebas.';
  end if;

  begin
    -- Fixtures: un consultorio del operador y tres usuarios de SOFA con doble factor al día
    insert into public.organizations (id, kind, legal_name, operator_id)
      values (gen_random_uuid(), 'client', 'QA I70 Consultorio', v_op)
      returning id into v_org;
    insert into auth.users (id, email) values
      (v_aud, 'qa.i70.auditor@sofa.do'), (v_adm, 'qa.i70.admin@sofa.do'), (v_sa, 'qa.i70.sa@sofa.do')
      on conflict (id) do nothing;
    insert into public.profiles (id, full_name, is_active, must_change_password) values
      (v_aud, 'QA I70 Auditor', true, false), (v_adm, 'QA I70 Admin', true, false), (v_sa, 'QA I70 SuperAdmin', true, false)
      on conflict (id) do update set is_active = true, must_change_password = false;
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values
      (v_op, v_aud, 'auditor', true), (v_op, v_adm, 'admin', true), (v_op, v_sa, 'super_admin', true)
      on conflict do nothing;

    -- AU-01 · La migración 208 queda registrada
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-01 · La migración 208 queda registrada','ok',
      exists(select 1 from app.schema_migrations where version='208'),'d',null));

    -- ── Usuarios ────────────────────────────────────────────────────────────────────────────────
    -- AU-02 · El Auditor ya NO lee la membresía de un consultorio
    perform set_config('request.jwt.claims', json_build_object('sub',v_aud,'role','authenticated','aal','aal2')::text, true);
    perform set_config('role','authenticated',true);
    select count(*) into v_n from public.organization_users where organization_id = v_org;
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-02 · El Auditor no lee la membresía de un consultorio','ok',
      v_n = 0,'d','filas visibles: '||v_n));

    -- AU-03 · El Auditor SÍ sigue viendo su propia fila (no se le rompe la sesión)
    perform set_config('role','authenticated',true);
    select count(*) into v_n from public.organization_users where user_id = v_aud;
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-03 · El Auditor sigue viendo su propia membresía','ok',
      v_n >= 1,'d','filas propias: '||v_n));

    -- AU-04 · El Administrador SÍ lee la membresía
    perform set_config('request.jwt.claims', json_build_object('sub',v_adm,'role','authenticated','aal','aal2')::text, true);
    perform set_config('role','authenticated',true);
    select count(*) into v_n from public.organization_users where organization_id = v_op;
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-04 · El Administrador sigue leyendo la membresía','ok',
      v_n >= 3,'d','filas visibles: '||v_n));

    -- AU-05 · El Super Admin SÍ lee la membresía
    perform set_config('request.jwt.claims', json_build_object('sub',v_sa,'role','authenticated','aal','aal2')::text, true);
    perform set_config('role','authenticated',true);
    select count(*) into v_n from public.organization_users where organization_id = v_op;
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-05 · El Super Admin sigue leyendo la membresía','ok',
      v_n >= 3,'d','filas visibles: '||v_n));

    -- ── Parámetros ──────────────────────────────────────────────────────────────────────────────
    -- AU-06 · El Auditor ya NO obtiene los parámetros del operador
    perform set_config('request.jwt.claims', json_build_object('sub',v_aud,'role','authenticated','aal','aal2')::text, true);
    perform set_config('role','authenticated',true);
    select count(*) into v_n from public.app_settings_staff();
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-06 · El Auditor no obtiene los parámetros (app_settings_staff)','ok',
      v_n = 0,'d','filas: '||v_n));

    -- AU-07 · El Administrador SÍ los obtiene
    perform set_config('request.jwt.claims', json_build_object('sub',v_adm,'role','authenticated','aal','aal2')::text, true);
    perform set_config('role','authenticated',true);
    select count(*) into v_n from public.app_settings_staff();
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-07 · El Administrador sigue obteniendo los parámetros','ok',
      v_n >= 1,'d','filas: '||v_n));

    -- AU-08 · El Super Admin SÍ los obtiene
    perform set_config('request.jwt.claims', json_build_object('sub',v_sa,'role','authenticated','aal','aal2')::text, true);
    perform set_config('role','authenticated',true);
    select count(*) into v_n from public.app_settings_staff();
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-08 · El Super Admin sigue obteniendo los parámetros','ok',
      v_n >= 1,'d','filas: '||v_n));

    -- ── Lo que NO se puede romper ───────────────────────────────────────────────────────────────
    -- AU-09 · La configuración general sigue abierta para el Auditor
    perform set_config('request.jwt.claims', json_build_object('sub',v_aud,'role','authenticated','aal','aal2')::text, true);
    perform set_config('role','authenticated',true);
    v_ok := public.app_settings_public() is not null;
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-09 · El Auditor conserva la configuración general (app_settings_public)','ok',
      v_ok,'d',null));

    -- AU-10 · El Auditor sigue leyendo los nombres (profiles), sus pantallas no se quedan en blanco
    perform set_config('role','authenticated',true);
    select count(*) into v_n from public.profiles where id in (v_adm, v_sa);
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-10 · El Auditor sigue resolviendo nombres (profiles)','ok',
      v_n = 2,'d','perfiles visibles: '||v_n));

    -- AU-11 · ATAQUE: el Auditor tampoco puede escribir la membresía
    perform set_config('role','authenticated',true);
    begin
      insert into public.organization_users (organization_id, user_id, role_code, is_active)
        values (v_org, v_aud, 'auditor', true);
      v_ok := false; v_t := 'pudo insertar (no debía)';
    exception when others then v_ok := true; v_t := left(sqlerrm, 120);
    end;
    perform set_config('role','none',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-11 · ATAQUE: el Auditor no puede escribir la membresía','ok',v_ok,'d',v_t));

    -- AU-12 · app_settings_staff sigue blindada: SECURITY DEFINER, search_path vacío y cerrada a anon
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AU-12 · app_settings_staff sigue blindada (definer, search_path, sin anon)','ok',
      (select p.prosecdef and array_to_string(coalesce(p.proconfig,array[]::text[]),',') like '%search_path=%'
         from pg_proc p join pg_namespace nx on nx.oid=p.pronamespace
        where nx.nspname='public' and p.proname='app_settings_staff')
      and not has_function_privilege('anon','public.app_settings_staff()','execute')
      and has_function_privilege('authenticated','public.app_settings_staff()','execute'),'d',null));

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('role','none',true);
  perform set_config('request.jwt.claims','',true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,   -- una prueba NULL cuenta como fallo
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;

revoke all on function app.qa_run_tests_alcance_auditor() from public, anon, authenticated;
