-- 259 · Suite de la 258 (agenda diaria al médico por WhatsApp, correo y aviso en SOFA). Se deshace sola.
-- Ya aplicado en producción (2026-11-20): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_agenda_diaria();
create or replace function app.qa_run_tests_agenda_diaria()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_n int; v_body text; v_email_on boolean;
  o  constant uuid := 'b9000000-0000-4000-8000-0000000000aa';
  p  constant uuid := 'c9000000-0000-4000-8000-0000000000aa';
  u  constant uuid := 'a9000000-0000-4000-8000-0000000000aa';
  d  constant date := current_date + 30;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-01 · Iniciales: «Rosa María Peña» → «R. P.»','ok',app.initials('  Rosa  María Peña ') = 'R. P.' and app.initials('Juan') = 'J.' and app.initials(null) = '—','d',app.initials('Rosa María Peña')));
    insert into auth.users (id, email) values (u, 'qa.ad.medico@sofa.test');
    insert into public.profiles (id, full_name) values (u, 'QA AD Médico') on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
      values (o,'client','00000000-0000-4000-8000-000000000001','QA AD','00000000211','Consultorio','activo',current_date-90,'8095550091');
    insert into public.providers (id, organization_id, full_name) values (p, o, 'Dr. AD Prueba');
    insert into public.organization_users (organization_id, user_id, role_code) values (o, u, 'client');
    update public.providers set user_id = u where id = p;
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type, status, reason) values
      (o, p, d, '08:00', 'Rosa María Peña', 'privado', 'confirmada', 'Consulta'),
      (o, p, d, '09:00', 'Juan Almonte', 'privado', 'programada', 'Control'),
      (o, p, d, '10:00', 'Cancelado Prueba', 'privado', 'cancelada', null);

    v_n := public.generate_doctor_agendas(d);
    select body into v_body from public.message_queue where provider_id = p and kind = 'agenda_medico' and scheduled_for = d;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-02 · Se prepara el WhatsApp de la agenda con hora, iniciales y confirmación','ok',
      v_body like '%08:00  R. P. · Consulta%' and v_body like '%09:00  J. A. · Control · sin confirmar%' and v_body like '%Total: 2 citas (1 sin confirmar)%','d',left(v_body, 200)));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-03 · No aparecen nombres completos ni citas canceladas','ok',
      v_body not like '%Rosa%' and v_body not like '%Almonte%' and v_body not like '%Cancelado%','d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-04 · Va al WhatsApp del consultorio','ok',
      exists (select 1 from public.message_queue where provider_id = p and kind = 'agenda_medico' and to_phone = '8095550091'),'d',null));
    perform public.generate_doctor_agendas(d);
    select count(*) into v_n from public.message_queue where provider_id = p and kind = 'agenda_medico' and scheduled_for = d;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-05 · Correr dos veces no duplica el mensaje','ok',v_n = 1,'d',v_n || ' mensajes'));
    select count(*) into v_n from public.notifications where user_id = u and title = 'Su agenda de mañana';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-06 · El médico recibe el aviso dentro de SOFA','ok',v_n = 1,'d',v_n || ' avisos'));
    select coalesce(s.enabled, false) into v_email_on from public.email_settings s where s.operator_id = '00000000-0000-4000-8000-000000000001';
    select count(*) into v_n from public.email_queue where dedupe_key = 'agenda_diaria:' || p || ':' || d;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-07 · Correo: se encola si los correos están activos; si no, no falla','ok',
      case when coalesce(v_email_on, false) then v_n = 1 else v_n = 0 end,'d','correos activos: ' || coalesce(v_email_on, false) || ', encolados: ' || v_n));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-11 · El correo trae solo conteos y horas, nunca datos de pacientes','ok',
      (select r.r_subject = 'SOFA · Su agenda de 23/11/2026: 2 citas' and r.r_text like '%Sin confirmar todavía: 1%' and r.r_text not like '%{{%'
         from app.email_render('agenda_diaria', jsonb_build_object('nombre','Dr. AD','fecha','23/11/2026','n_citas',2,'n_sin_confirmar',1,'primera','08:00','ultima','09:00'), null, null) r)
      and app.email_template_vars('agenda_diaria') = array['nombre','fecha','n_citas','n_sin_confirmar','primera','ultima'],'d',null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-08 · La tarea programada existe (6:00 p. m. RD)','ok',
      exists (select 1 from cron.job where jobname = 'sofa_agenda_medico' and schedule = '0 22 * * *'),'d',null));

    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true); perform set_config('role', 'authenticated', true);
    select count(*) into v_n from public.message_queue where provider_id = p and kind = 'agenda_medico';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-09 · El médico ve su mensaje en «Mensajes»','ok',v_n = 1,'d',v_n || ' visibles'));
    begin perform public.generate_doctor_agendas(d);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-10 · Un médico no dispara el generador a mano','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','AD-10 · Un médico no dispara el generador a mano','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

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
revoke execute on function app.qa_run_tests_agenda_diaria() from public, anon, authenticated;
