-- 245 · Suite de la 244 (agenda por médico y centro: opciones B + C). Se deshace sola.
-- Ya aplicado en producción (2026-11-20): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_agenda_centros();
create or replace function app.qa_run_tests_agenda_centros()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_ok boolean; v_n int; v_x jsonb; v_a1 uuid; v_a2 uuid; v_msg text;
  v_orgA constant uuid := 'b9000000-0000-4000-8000-0000000000e1';
  v_orgB constant uuid := 'b9000000-0000-4000-8000-0000000000e2';
  v_pA   constant uuid := 'c9000000-0000-4000-8000-0000000000e1';
  v_pA2  constant uuid := 'c9000000-0000-4000-8000-0000000000e3';
  v_pB   constant uuid := 'c9000000-0000-4000-8000-0000000000e2';
  v_cX   constant uuid := 'd9000000-0000-4000-8000-0000000000e1';
  v_cY   constant uuid := 'd9000000-0000-4000-8000-0000000000e2';
  v_cZ   constant uuid := 'd9000000-0000-4000-8000-0000000000e3';
  v_op   constant uuid := '00000000-0000-4000-8000-000000000001';
  v_admin constant text := 'a9000000-0000-4000-8000-0000000000e1';
  v_cap   constant text := 'a9000000-0000-4000-8000-0000000000e2';
  v_rec   constant text := 'a9000000-0000-4000-8000-0000000000e3';
  v_out   constant text := 'a9000000-0000-4000-8000-0000000000e4';
  v_day   constant date := current_date + 7;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    -- Datos de prueba desechables (se deshacen al final)
    insert into auth.users (id, email) values (v_admin::uuid,'qa.ag.admin@sofa.test'), (v_cap::uuid,'qa.ag.cap@sofa.test'), (v_rec::uuid,'qa.ag.rec@sofa.test'), (v_out::uuid,'qa.ag.out@sofa.test');
    insert into public.profiles (id, full_name) select id, replace(email, '@sofa.test', '') from auth.users where email like 'qa.ag.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_orgA, 'client', v_op, 'QA AG A', '00000000141', 'Consultorio', 'activo', current_date - 90, '8095550011'),
      (v_orgB, 'client', v_op, 'QA AG B', '00000000142', 'Consultorio', 'activo', current_date - 90, '8295550012');
    insert into public.providers (id, organization_id, full_name) values (v_pA, v_orgA, 'Dra. AG A'), (v_pA2, v_orgA, 'Dr. AG A2'), (v_pB, v_orgB, 'Dr. AG B');
    insert into public.health_centers (id, organization_id, name) values (v_cX, v_orgA, 'Centro QA X'), (v_cY, v_orgA, 'Centro QA Y'), (v_cZ, v_orgB, 'Centro QA Z');
    insert into public.provider_centers (provider_id, center_id, is_primary) values (v_pA, v_cX, true), (v_pA, v_cY, false), (v_pA2, v_cX, true),
      (v_pB, v_cX, false);   -- enlace "intruso": médico de otra organización apuntando a un centro de A
    insert into public.organization_users (organization_id, user_id, role_code) values
      (v_op, v_admin::uuid, 'super_admin'), (v_orgA, v_cap::uuid, 'capturer'), (v_orgA, v_rec::uuid, 'capturer'), (v_orgB, v_out::uuid, 'capturer');
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp, can_payments) values (v_cap::uuid, v_pA, v_orgA, true, false, false);

    -- Como Administrador
    perform set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated','aal','aal2')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.set_assistant_center(v_cap::uuid, v_pA, v_cX);
    v_a1 := public.save_appointment(null, v_pA, v_day, time '09:00', 'Paciente AG Uno', null, null, '8095551111', 'privado', null, null, 'Consulta', null, v_cX, 30);
    v_a2 := public.save_appointment(null, v_pA, v_day, time '10:00', 'Paciente AG Dos', null, null, '8095552222', 'privado', null, null, 'Consulta', null, v_cY, 30);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-01 · El Administrador agenda a la doctora en sus dos centros','ok',v_a1 is not null and v_a2 is not null,'d',null));

    -- AG-02 · Cita encimada en OTRO centro se rechaza
    begin
      perform public.save_appointment(null, v_pA, v_day, time '09:15', 'Paciente AG Tres', null, null, null, 'privado', null, null, 'Consulta', null, v_cY, 30);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-02 · Cita encimada (otro centro) se rechaza','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-02 · Cita encimada (otro centro) se rechaza','ok',sqlstate = '23P01','d',left(sqlerrm, 120)));
    end;

    -- AG-03 · Recepción: no se puede asignar a una usuaria de otra organización
    begin
      perform public.reception_scope_set(v_out::uuid, v_cX, true, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-03 · Recepción no se asigna a usuaria de otra organización','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-03 · Recepción no se asigna a usuaria de otra organización','ok',sqlstate = '42501','d',left(sqlerrm, 120)));
    end;
    perform public.reception_scope_set(v_rec::uuid, v_cX, true, true);
    v_x := public.reception_staff(v_cX);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-14 · La Administración lista las secretarias del centro y quién atiende la recepción (246)','ok',
      jsonb_array_length(v_x) = 2 and exists (select 1 from jsonb_array_elements(v_x) u where u->>'user_id' = v_rec and (u->>'assigned')::boolean)
      and not (v_x::text like '%qa.ag.out%'),'d',left(v_x::text, 200)));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- Como Secretaria limitada al Centro X
    perform set_config('request.jwt.claims', json_build_object('sub',v_cap,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    select count(*) into v_n from public.appointments where provider_id = v_pA;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-04 · La secretaria del Centro X solo ve las citas del Centro X','ok',v_n = 1,'d',v_n || ' visibles'));
    begin
      perform public.save_appointment(null, v_pA, v_day, time '15:00', 'Paciente AG Cuatro', null, null, null, 'privado', null, null, 'Consulta', null, v_cY, 30);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-05 · La secretaria del Centro X no agenda en el Centro Y','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-05 · La secretaria del Centro X no agenda en el Centro Y','ok',sqlstate = '42501','d',left(sqlerrm, 120)));
    end;
    v_x := public.agenda_week(v_pA, v_cX, v_day, 1);
    v_ok := jsonb_array_length(v_x->'appointments') = 1
        and exists (select 1 from jsonb_array_elements(v_x->'busy') b where b->>'start' = '10:00' and b->>'kind' = 'otro_centro')
        and not (v_x::text like '%Paciente AG Dos%') and not (v_x::text like '%Centro QA Y%');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-06 · La semana marca 10:00 como «otro centro» sin paciente ni nombre del centro','ok',v_ok,'d',left(v_x::text, 200)));
    begin
      perform public.agenda_week(v_pA, v_cY, v_day, 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-07 · La secretaria no abre la semana del Centro Y','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-07 · La secretaria no abre la semana del Centro Y','ok',sqlstate = '42501','d',left(sqlerrm, 120)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- Como Recepción del Centro X
    perform set_config('request.jwt.claims', json_build_object('sub',v_rec,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.reception_day(v_cX, v_day);
    v_ok := jsonb_array_length(v_x->'providers') = 2 and not (v_x::text like '%Dr. AG B%') and not (v_x::text like '%Paciente AG Dos%');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-08 · Recepción ve solo los 2 médicos de su organización (no el de B) y sin citas del Centro Y','ok',v_ok,'d',left(v_x::text, 200)));
    v_a1 := public.save_appointment(null, v_pA2, v_day, time '11:00', 'Paciente AG Cinco', null, null, null, 'privado', null, null, 'Consulta', null, v_cX, 30);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-09 · Recepción agenda a otro médico de su centro','ok',v_a1 is not null,'d',null));
    begin
      perform public.save_appointment(null, v_pB, v_day, time '11:00', 'Paciente AG Seis', null, null, null, 'privado', null, null, 'Consulta', null, v_cX, 30);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-10 · Recepción no agenda al médico de otra organización','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-10 · Recepción no agenda al médico de otra organización','ok',true,'d',left(sqlerrm, 120)));
    end;
    select count(*) into v_n from public.appointments where provider_id in (v_pA, v_pA2, v_pB) and center_id is distinct from v_cX;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-11 · Recepción no lee citas fuera de su centro','ok',v_n = 0,'d',v_n || ' visibles'));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- Como usuaria de otra organización
    perform set_config('request.jwt.claims', json_build_object('sub',v_out,'role','authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin
      perform public.reception_day(v_cX, v_day);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-12 · Usuaria de otra organización no abre la recepción','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-12 · Usuaria de otra organización no abre la recepción','ok',sqlstate = '42501','d',left(sqlerrm, 120)));
    end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    -- AG-13 · Sin acceso anónimo y con search_path fijo
    v_ok := not has_function_privilege('anon', 'public.agenda_week(uuid,uuid,date,integer)'::regprocedure, 'EXECUTE')
        and not has_function_privilege('anon', 'public.reception_day(uuid,date)'::regprocedure, 'EXECUTE')
        and not has_function_privilege('anon', 'public.reception_scope_set(uuid,uuid,boolean,boolean)'::regprocedure, 'EXECUTE')
        and not has_function_privilege('anon', 'public.save_appointment(uuid,uuid,date,time,text,text,text,text,text,uuid,text,text,text,uuid,integer)'::regprocedure, 'EXECUTE')
        and (select bool_and(coalesce(p.proconfig::text, '') like '%search_path%') from pg_proc p join pg_namespace s on s.oid = p.pronamespace
              where (s.nspname, p.proname) in (('public','agenda_week'),('public','reception_day'),('public','save_appointment'),('public','reception_scope_set'),
                                               ('app','appointment_access'),('app','reception_centers'),('app','agenda_busy')));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AG-13 · Sin acceso anónimo y con search_path fijo','ok',v_ok,'d',null));

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
revoke execute on function app.qa_run_tests_agenda_centros() from public, anon, authenticated;
