-- 159 · Suite de la 158 (escala y blindaje). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_escala_blindaje();
create or replace function app.qa_run_tests_escala_blindaje()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := '01590000-0000-4000-8000-000000000001';
  v_sa constant text := '01590000-0000-4000-8000-000000000011'; v_adm constant text := '01590000-0000-4000-8000-000000000012'; v_med constant text := '01590000-0000-4000-8000-000000000013'; v_viejo constant text := '01590000-0000-4000-8000-000000000014';
  v_rev uuid; v_item uuid; v_self uuid; v_cnt int;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_sa::uuid,'qa.eb.sa@sofa.test','x'),(v_adm::uuid,'qa.eb.adm@sofa.test','x'),(v_med::uuid,'qa.eb.med@sofa.test','x'),(v_viejo::uuid,'qa.eb.viejo@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.eb.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA EB Consultorio', '00000000891', 'Médico independiente', 'activo', current_date - 90, '8095550891');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_viejo::uuid, 'capturer'),
      ('00000000-0000-4000-8000-000000000001'::uuid, v_sa::uuid, 'super_admin'), ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin');
    update auth.users set last_sign_in_at = now() - interval '200 days' where id = v_viejo::uuid;
    update auth.users set last_sign_in_at = now() where id in (v_sa::uuid, v_med::uuid);
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-01 · Índices de rendimiento presentes en las columnas más consultadas','ok',coalesce((exists (select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0] where i.indrelid = 'public.service_lines'::regclass and a.attname = 'submission_id')), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    begin
      perform public.system_health();
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-02 · El Administrador no ve la salud del sistema','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-02 · El Administrador no ve la salud del sistema','ok',sqlerrm like 'Solo el Super Admin%','d',left(sqlerrm,120)));
    end;
    perform public.log_export('reclamaciones', 'reclamaciones.csv', 120, v_org);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    v_x := public.system_health();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-03 · Salud: última migración, tablas, exportación registrada y avisos pendientes','ok',coalesce((v_x->>'last_migration' >= '158' and jsonb_array_length(v_x->'tables') > 0 and exists (select 1 from jsonb_array_elements(v_x->'exports_30d') e where e->>'file' = 'reclamaciones.csv' and (e->>'rows')::int = 120) and v_x ? 'drill_due'), false),'d',(left(v_x::text, 300))::text));
    v_rev := public.access_review_start();
    v_x := public.access_review_get(v_rev);
    select (i->>'id')::uuid into v_item from jsonb_array_elements(v_x->'items') i where i->>'email' = 'qa.eb.viejo@sofa.test';
    select (i->>'id')::uuid into v_self from jsonb_array_elements(v_x->'items') i where i->>'email' = 'qa.eb.sa@sofa.test';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-04 · La revisión toma la foto de accesos y marca los que no entran hace 90 días','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'items') i where (i->>'id')::uuid = v_item and (i->>'stale')::boolean)), false),'d',(v_item::text)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-05 · Iniciarla otra vez en el mismo trimestre devuelve la misma','ok',coalesce((public.access_review_start() = v_rev), false),'d',(null)::text));
    begin
      perform public.access_review_decide(v_item, 'quitar', '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-06 · Quitar exige el motivo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-06 · Quitar exige el motivo','ok',sqlerrm like 'Anote por qué se quita%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.access_review_decide(v_self, 'quitar', 'Prueba de seguridad');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-07 · No puede quitarse su propio acceso','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-07 · No puede quitarse su propio acceso','ok',sqlerrm like 'No puede quitarse su propio acceso%','d',left(sqlerrm,120)));
    end;
    perform public.access_review_decide(v_item, 'quitar', 'No entra hace más de 6 meses');
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-08 · Quitar desactiva el acceso (no borra al usuario)','ok',coalesce((not (select is_active from public.organization_users where user_id = v_viejo::uuid and organization_id = v_org) and exists (select 1 from public.profiles where id = v_viejo::uuid)), false),'d',(null)::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    begin
      perform public.access_review_complete(v_rev);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-09 · No se cierra con accesos sin decidir','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-09 · No se cierra con accesos sin decidir','ok',sqlerrm like 'Faltan%acceso(s) por decidir%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.access_review_items set decision = 'mantener' where review_id = v_rev and decision is null;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    perform public.access_review_complete(v_rev);
    begin
      perform public.backup_drill_add('restauracion_prueba', 'con_problemas', '');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-10 · Simulacro con problemas exige describirlo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-10 · Simulacro con problemas exige describirlo','ok',sqlerrm like 'Describa el problema%','d',left(sqlerrm,120)));
    end;
    perform public.backup_drill_add('restauracion_prueba', 'ok', 'Restaurado en proyecto de pruebas');
    v_x := public.system_health();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-11 · Con revisión cerrada y simulacro ok ya no hay avisos','ok',coalesce((not (v_x->>'drill_due')::boolean and not (v_x->>'access_review_due')::boolean), false),'d',(v_x->>'access_review')::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    delete from public.backup_drills where note = 'Restaurado en proyecto de pruebas';
    v_cnt := app.security_followup();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-12 · Sin simulacro en 90 días: tarea de recordatorio (una sola)','ok',coalesce((app.security_followup() = 0 and exists (select 1 from public.tasks where title = 'Simulacro de respaldo y restauración' and status = 'abierta')), false),'d',(null)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EB-13 · Tablas solo por funciones','ok',coalesce((not has_table_privilege('authenticated', 'public.export_log', 'select') and not has_function_privilege('anon', 'public.log_export(text,text,integer,uuid)', 'execute')), false),'d',(null)::text));

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
