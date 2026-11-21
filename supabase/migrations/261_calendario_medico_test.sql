-- 261 · Suite de la 260 (calendario iCal del médico). Se deshace sola.
-- Ya aplicado en producción (2026-11-20): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_calendario();
create or replace function app.qa_run_tests_calendario()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_n int; v_tok text; v_tok2 text; v_ics text;
  o   constant uuid := 'b9000000-0000-4000-8000-0000000000ab';
  p1  constant uuid := 'c9000000-0000-4000-8000-0000000000ab';
  p2  constant uuid := 'c9000000-0000-4000-8000-0000000000ac';
  u1  constant text := 'a9000000-0000-4000-8000-0000000000ab';
  u2  constant text := 'a9000000-0000-4000-8000-0000000000ac';
  us  constant text := 'a9000000-0000-4000-8000-0000000000ad';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email) values (u1::uuid,'qa.ca.u1@sofa.test'),(u2::uuid,'qa.ca.u2@sofa.test'),(us::uuid,'qa.ca.sec@sofa.test');
    insert into public.profiles (id, full_name) select id, email from auth.users where email like 'qa.ca.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
      values (o,'client','00000000-0000-4000-8000-000000000001','QA CA Clinica','00000000221','Clínica','activo',current_date-90,'8095550095');
    insert into public.providers (id, organization_id, full_name) values (p1,o,'Dr. CA Uno'),(p2,o,'Dra. CA Dos');
    insert into public.organization_users (organization_id, user_id, role_code) values (o,u1::uuid,'client'),(o,u2::uuid,'client'),(o,us::uuid,'capturer');
    update public.providers set user_id = case id when p1 then u1::uuid when p2 then u2::uuid end where id in (p1, p2);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp, can_payments) values (us::uuid, p1, o, true, true, true);
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type, status, reason) values
      (o, p1, current_date + 3, '08:00', 'Rosa María Peña', 'privado', 'programada', 'Consulta, control'),
      (o, p1, current_date + 4, '09:00', 'Cita Cancelada', 'privado', 'cancelada', null);

    -- Dr. Uno crea su enlace
    perform set_config('request.jwt.claims', json_build_object('sub',u1,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    v_tok := public.calendar_feed_create(p1);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-01 · El médico crea el enlace de su calendario (64 caracteres)','ok',v_tok ~ '^[0-9a-f]{64}$','d',length(v_tok)::text));
    begin perform public.calendar_feed_create(p2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-02 · No crea el calendario de su colega de clínica','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-02 · No crea el calendario de su colega de clínica','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    begin perform 1 from public.provider_calendar_feeds;
      get diagnostics v_n = row_count;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-03 · Nadie lee la tabla de enlaces (ni el hash)','ok',v_n = 0,'d',v_n || ' filas'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-03 · Nadie lee la tabla de enlaces (ni el hash)','ok',true,'d',left(sqlerrm,120))); end;
    begin perform public.calendar_feed_ics(v_tok);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-04 · Un usuario no lee el iCal directo (solo la función pública)','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-04 · Un usuario no lee el iCal directo (solo la función pública)','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    -- Secretaria (con todos los permisos) no maneja el calendario personal del médico
    perform set_config('request.jwt.claims', json_build_object('sub',us,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    begin perform public.calendar_feed_create(p1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-05 · La secretaria no crea el calendario del médico','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-05 · La secretaria no crea el calendario del médico','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    -- Contenido (como la Edge Function)
    v_ics := app.calendar_feed_ics(v_tok);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-06 · El iCal trae la cita con iniciales, sin nombre y sin la cancelada','ok',
      v_ics like 'BEGIN:VCALENDAR%' and position(E'SUMMARY:Cita · R. P. · Consulta\\, control' in v_ics) > 0 and v_ics not like '%Rosa%' and v_ics not like '%Cancelada%'
      and v_ics like '%TRIGGER:-PT30M%' and v_ics like '%STATUS:TENTATIVE%','d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-07 · Token falso o mal formado → sin calendario','ok',
      app.calendar_feed_ics(repeat('0', 64)) is null and app.calendar_feed_ics('abc') is null and app.calendar_feed_ics(null) is null,'d',null));

    -- Rotar y revocar
    perform set_config('request.jwt.claims', json_build_object('sub',u1,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    v_tok2 := public.calendar_feed_create(p1);
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);
    select count(*) into v_n from public.provider_calendar_feeds where provider_id = p1 and revoked_at is null;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-08 · Un enlace nuevo invalida el anterior (uno solo activo)','ok',
      v_n = 1 and app.calendar_feed_ics(v_tok) is null and app.calendar_feed_ics(v_tok2) is not null,'d',v_n || ' activos'));
    perform set_config('request.jwt.claims', json_build_object('sub',u1,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    perform public.calendar_feed_revoke(p1);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-09 · Revocar apaga el calendario','ok',
      not (public.calendar_feed_status(p1)->>'active')::boolean,'d',public.calendar_feed_status(p1)::text));
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CA-10 · Sin acceso anónimo; el iCal solo para service_role','ok',
      not has_function_privilege('anon','public.calendar_feed_create(uuid)','EXECUTE')
      and not has_function_privilege('authenticated','public.calendar_feed_ics(text)','EXECUTE')
      and has_function_privilege('service_role','public.calendar_feed_ics(text)','EXECUTE'),'d',null));

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
revoke execute on function app.qa_run_tests_calendario() from public, anon, authenticated;
