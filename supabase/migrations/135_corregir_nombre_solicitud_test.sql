-- 135 · Suite de la 134 (nombre del usuario al aprobar una solicitud). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_nombre_solicitud();
create or replace function app.qa_run_tests_nombre_solicitud()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000003e1'; v_prov constant uuid := 'c7000000-0000-4000-8000-0000000003e1';
  v_sa constant text := 'a7000000-0000-4000-8000-0000000003e1'; v_med constant text := 'a7000000-0000-4000-8000-0000000003e2';
  v_nuevo constant uuid := 'a7000000-0000-4000-8000-0000000003e3'; v_req uuid;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.ns.sa@sofa.test','x'),(v_med::uuid,'qa.ns.med@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.ns.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA NS Consultorio', '00000000771', 'Médico independiente', 'activo', current_date - 90, '8095550771');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. NS', 'Pediatría');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_req := public.request_user(v_org, 'marta.ns@sofa.test', 'Marta Núñez Secretaria', 'capturer', array[v_prov]);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into auth.users (id, email, encrypted_password) values (v_nuevo, 'marta.ns@sofa.test', 'x');   -- Supabase crea el perfil «marta.ns»
    insert into public.profiles (id, full_name) values (v_nuevo, 'marta.ns') on conflict (id) do nothing;
    perform public.complete_user_request(v_req, v_nuevo, v_sa::uuid);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','NS-01 · Al aprobar, el perfil toma el nombre de la solicitud (no la parte del correo)','ok',coalesce(((select full_name from public.profiles where id = v_nuevo) = 'Marta Núñez Secretaria'), false),'d',((select full_name from public.profiles where id = v_nuevo))::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','NS-02 · La solicitud queda aprobada y su tarea cerrada','ok',coalesce(((select status = 'aprobada' from public.user_requests where id = v_req) and not exists (select 1 from public.tasks where organization_id = v_org and title like 'Autorizar usuario%' and status = 'abierta')), false),'d',(null)::text));

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
