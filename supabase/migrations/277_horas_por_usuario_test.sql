-- PENDIENTE de aplicar en producción. No fusionar así.
-- 277 · Suite de la 276 (horas por usuario). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_horas_usuarios();
create or replace function app.qa_run_tests_horas_usuarios()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql set search_path = '' as $function$
declare
  v_res jsonb := '[]'::jsonb; v_msg text; v_n int; v_m int; v_x jsonb; v_today date; v_row jsonb;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_ad  constant uuid := '27600000-0000-4000-8000-000000000001';
  v_bi  constant uuid := '27600000-0000-4000-8000-000000000002';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    v_today := (clock_timestamp() at time zone 'America/Santo_Domingo')::date;
    insert into auth.users (id, email, encrypted_password) values (v_ad,'qa.hu.ad@sofa.test','x'),(v_bi,'qa.hu.bi@sofa.test','x');
    insert into public.profiles (id, full_name) values (v_ad,'qa.hu.ad'),(v_bi,'qa.hu.bi') on conflict (id) do nothing;
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values (v_sofa, v_ad, 'admin', true), (v_sofa, v_bi, 'billing', true);

    perform set_config('request.jwt.claims', json_build_object('sub', v_bi, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.usage_ping(true);
    perform public.usage_ping(true);
    begin perform public.usage_hours_report(v_today - 7, v_today);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-01 · Facturación no ve el reporte','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-01 · Facturación no ve el reporte','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    begin select count(*) into v_n from public.user_connection_days;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-02 · La tabla no se lee directo','ok',v_n = 0,'d',v_n::text));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-02 · La tabla no se lee directo','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);

    select c.connected_minutes, c.active_minutes into v_n, v_m from public.user_connection_days c where c.user_id = v_bi and c.day = v_today;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-03 · Dos latidos seguidos no duplican el minuto','ok',coalesce(v_n between 1 and 2 and v_m between 1 and 2, false),'d',format('%s %s', v_n, v_m)));

    update public.user_connection_days set last_at = last_at - interval '2 minutes', last_active_at = last_active_at - interval '2 minutes' where user_id = v_bi;
    perform set_config('request.jwt.claims', json_build_object('sub', v_bi, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('role', 'authenticated', true);
    perform public.usage_ping(false);
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    select c.connected_minutes - v_n, c.active_minutes - v_m into v_n, v_m from public.user_connection_days c where c.user_id = v_bi and c.day = v_today;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-04 · Sin actividad suma conexión pero no tiempo activo','ok',coalesce(v_n = 1 and v_m = 0, false),'d',format('+%s +%s', v_n, v_m)));

    perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.usage_hours_report(v_today - 7, v_today);
    select e into v_row from jsonb_array_elements(v_x->'rows') e where e->>'user_id' = v_bi::text;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-05 · El administrador ve las horas del usuario','ok',coalesce((v_row->>'connected_minutes')::int >= 2 and (v_row->>'is_sofa')::boolean, false),'d',coalesce(v_row::text,'sin fila')));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-06 · El personal sin conexión sale en cero','ok',exists(select 1 from jsonb_array_elements(v_x->'rows') e where e->>'user_id' = v_ad::text and (e->>'connected_minutes')::int = 0),'d','admin sin latidos'));
    begin perform public.usage_hours_report(v_today - 200, v_today);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-07 · Rechaza períodos demasiado largos','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-07 · Rechaza períodos demasiado largos','ok',sqlstate = '22023','d',left(sqlerrm,120))); end;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HU-08 · Sin sesión no se puede ni latir ni consultar','ok',not has_function_privilege('anon','public.usage_ping(boolean)','execute') and not has_function_privilege('anon','public.usage_hours_report(date,date)','execute'),'d','anon'));
    raise exception 'qa_rollback';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    if v_msg <> 'qa_rollback' then v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error general de la suite','ok',false,'d',v_msg)); end if;
  end;
  return query select t.ord::int, case when (t.e->>'ok')::boolean then 'OK' else 'FALLA' end, t.e->>'p', t.e->>'d'
    from jsonb_array_elements(v_res) with ordinality as t(e, ord);
end $function$;
revoke all on function app.qa_run_tests_horas_usuarios() from public, anon, authenticated;
