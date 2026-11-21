-- 258_agenda_diaria_medico.sql
-- Ya aplicado en producción (2026-11-20, mcp__Supabase__apply_migration «agenda_diaria_medico_258»).
--
-- Recordatorio de la agenda al médico (opciones 2 y 4 aprobadas el 20/11/2026):
--   · Opción 2 · WhatsApp: cada día a las 6:00 p. m. (RD) SOFA prepara en «Mensajes» la agenda de mañana de cada
--     médico (tipo «agenda_medico»), lista para enviarla con un toque. Gratis: nada se envía solo.
--   · Opción 4 · Correo: el mismo texto va a la cola de correos (aviso «agenda_diaria»). Mientras el proveedor de
--     correo siga «simulado» (enviar-correos), no sale ningún correo real; queda listo para cuando se conecte.
--   · Aviso dentro de SOFA (notifications) para el usuario del médico.
-- Privacidad: el paciente va en iniciales («R. P.»), igual que en el calendario (260).
-- El teléfono es el del consultorio (organizations.whatsapp/phone), igual que el resumen semanal.
-- Idempotente. Suite: 259_agenda_diaria_medico_test.sql.

do $$ begin
  if to_regclass('public.email_topics') is null or to_regprocedure('app.email_enqueue(uuid,text,jsonb,text,uuid,timestamp with time zone)') is null then
    raise exception 'Falta la cola de correos (iteración 63)';
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'appointments' and column_name = 'center_id') then
    raise exception 'Falta la 244';
  end if;
end $$;

-- 1. Nuevo tipo de mensaje
alter table public.message_queue drop constraint if exists message_queue_kind_check;
alter table public.message_queue add constraint message_queue_kind_check check (kind = any (array[
  'resumen_semanal','recordatorio_cita','seguimiento_cita','control_pendiente','reprogramar_cita','cobro_pendiente','agenda_medico']));
create unique index if not exists message_queue_agenda_medico_uq on public.message_queue (provider_id, scheduled_for) where kind = 'agenda_medico';

-- El médico y sus secretarias con permiso de WhatsApp ven «agenda_medico» (misma regla que los recordatorios).
drop policy if exists message_queue_select on public.message_queue;
create policy message_queue_select on public.message_queue for select using (
  ((kind = any (array['recordatorio_cita','seguimiento_cita','control_pendiente','reprogramar_cita','cobro_pendiente','agenda_medico']))
     and app.consultorio_access(provider_id, false) and app.capturer_can(provider_id, 'whatsapp'))
  or ((kind = 'resumen_semanal') and (organization_id in (select app.can_orgs(array['super_admin','admin','client','assistant','operations','glosas','auditor'])))));

-- 2. Iniciales del paciente: «Rosa María Peña» → «R. P.»
create or replace function app.initials(p_name text)
returns text language sql immutable set search_path to '' as $$
  select coalesce((select string_agg(upper(left(w, 1)) || '.', ' ' order by o)
                     from (select w, o, count(*) over () c
                             from unnest(regexp_split_to_array(trim(coalesce(p_name, '')), '\s+')) with ordinality as t(w, o)
                            where w <> '') x
                    where o = 1 or o = c), '—');
$$;

-- 3. Texto de la agenda de un médico para un día
create or replace function app.doctor_agenda_text(p_provider uuid, p_date date)
returns text language sql stable security definer set search_path to '' as $$
  with a as (
    select a.appointment_time t, a.duration_min, a.reason, a.status, a.payer_type, hc.name centro, app.initials(a.patient_name) ini
      from public.appointments a left join public.health_centers hc on hc.id = a.center_id
     where a.provider_id = p_provider and a.appointment_date = p_date and a.status not in ('cancelada','no_asistio'))
  select 'Agenda de ' || (array['lunes','martes','miércoles','jueves','viernes','sábado','domingo'])[extract(isodow from p_date)::int] || ' '
         || to_char(p_date, 'DD/MM') || ' · ' || (select full_name from public.providers where id = p_provider) || E'\n\n'
         || coalesce((select string_agg(coalesce(to_char(t, 'HH24:MI'), 'Sin hora') || '  ' || ini
                                      || coalesce(' · ' || reason, '') || coalesce(' (' || centro || ')', '')
                                      || case when status = 'programada' then ' · sin confirmar' else '' end, E'\n' order by t nulls last) from a), 'Sin citas.')
         || E'\n\nTotal: ' || (select count(*) from a) || ' citas'
         || case when (select count(*) from a where status = 'programada') > 0
                 then ' (' || (select count(*) from a where status = 'programada') || ' sin confirmar)' else '' end
         || E'\nDetalle en SOFA › Agenda.';
$$;

-- 4. Aviso de correo «agenda_diaria» y su plantilla
insert into public.email_topics (code, label, description, default_enabled, default_frequency, frequencies, can_disable, audience, sort_order)
values ('agenda_diaria', 'Agenda de mañana', 'Sus citas del día siguiente, con la hora, las iniciales del paciente y si ya confirmó.',
        true, 'diaria', array['diaria'], true, array['client'], 5)
on conflict (code) do nothing;
insert into public.email_templates (code, version, subject, body_html, body_text, is_active, note)
select 'agenda_diaria', 1, 'SOFA · Su agenda de {{fecha}}',
       '<h2 style="margin:0 0 12px">Su agenda de {{fecha}}</h2><p>Hola, {{nombre}}.</p><div style="white-space:pre-line;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:14px">{{agenda}}</div><p>Entre a SOFA para ver el detalle o mover una cita.</p>',
       E'Su agenda de {{fecha}}\n\nHola, {{nombre}}.\n\n{{agenda}}\n\nEntre a SOFA para ver el detalle o mover una cita.',
       true, 'Versión inicial (258)'
where not exists (select 1 from public.email_templates where code = 'agenda_diaria');

-- 5. Generador diario (lo llama pg_cron; el personal SOFA también puede llamarlo a mano)
create or replace function public.generate_doctor_agendas(p_date date default current_date + 1)
returns integer language plpgsql security definer set search_path to '' as $$
declare r record; v_text text; v_id uuid; v_n integer := 0; v_date date := coalesce(p_date, current_date + 1);
begin
  if auth.uid() is not null and not app.is_staff(array['super_admin','admin']) then
    raise exception 'Solo Super Admin o Administrador SOFA genera las agendas del médico a mano; se generan solas cada tarde.' using errcode = '42501';
  end if;
  for r in select pr.id provider_id, pr.full_name, pr.organization_id, pr.user_id, coalesce(o.whatsapp, o.phone) phone
             from public.providers pr join public.organizations o on o.id = pr.organization_id
            where pr.is_active and o.kind = 'client' and o.status = 'activo' and coalesce(o.is_demo, false) = false
              and exists (select 1 from public.appointments a where a.provider_id = pr.id and a.appointment_date = v_date
                             and a.status not in ('cancelada','no_asistio'))
            order by pr.full_name loop
    v_text := app.doctor_agenda_text(r.provider_id, v_date);
    v_id := null;
    insert into public.message_queue (organization_id, provider_id, kind, to_phone, subject, body, scheduled_for)
    values (r.organization_id, r.provider_id, 'agenda_medico', r.phone, 'Agenda de mañana · ' || r.full_name, v_text, v_date)
    on conflict do nothing returning id into v_id;
    if v_id is not null then
      v_n := v_n + 1;
      if r.user_id is not null then
        insert into public.notifications (user_id, title, body, link) values (r.user_id, 'Su agenda de mañana', v_text, '#/agenda-semana');
        perform app.email_enqueue(r.user_id, 'agenda_diaria',
          jsonb_build_object('nombre', r.full_name, 'fecha', to_char(v_date, 'DD/MM/YYYY'), 'agenda', v_text),
          'agenda_diaria:' || r.provider_id || ':' || v_date, r.organization_id, null);
      end if;
    end if;
  end loop;
  return v_n;
end $$;
revoke execute on function public.generate_doctor_agendas(date) from public, anon;
grant execute on function public.generate_doctor_agendas(date) to authenticated;

-- 6. Programación: 22:00 UTC = 6:00 p. m. en RD (fecha UTC = fecha RD a esa hora) → agenda de mañana
do $$ begin
  if exists (select 1 from cron.job where jobname = 'sofa_agenda_medico') then perform cron.unschedule('sofa_agenda_medico'); end if;
  perform cron.schedule('sofa_agenda_medico', '0 22 * * *', 'select public.generate_doctor_agendas(current_date + 1)');
end $$;

-- 258b · (aplicado en producción como «agenda_diaria_medico_258b», mismo día)
-- Hallazgo al probar la plantilla: (1) las variables de correo se declaran por aviso en app.email_template_vars;
-- (2) regla de SOFA: «Este correo solo trae conteos y montos: nunca datos de pacientes». El correo de la agenda
-- lleva SOLO conteos y horas (cuántas citas, cuántas sin confirmar, primera y última). Iniciales y motivos quedan
-- en el WhatsApp que envía el propio consultorio y dentro de SOFA.
create or replace function app.email_template_vars(p_code text)
returns text[] language sql immutable set search_path to '' as $function$
  select case p_code
    when 'seguridad' then array['nombre','evento','fecha_hora']
    when 'glosas_por_vencer' then array['nombre','n_glosas','monto_glosado','proximo_vencimiento','dias_aviso','detalle_html','detalle_text']
    when 'pago_recibido' then array['nombre','n_pagos','monto_total','arss','detalle_html','detalle_text']
    when 'resumen_semanal' then array['nombre','periodo','n_radicadas','monto_radicado','n_pagos','monto_pagado','n_glosas_nuevas','monto_glosas_nuevas','n_glosas_abiertas','n_glosas_por_vencer']
    when 'agenda_diaria' then array['nombre','fecha','n_citas','n_sin_confirmar','primera','ultima']
  end;
$function$;

update public.email_templates set
  subject = 'SOFA · Su agenda de {{fecha}}: {{n_citas}} citas',
  body_html = '<h2 style="margin:0 0 12px">Su agenda de {{fecha}}</h2><p>Hola, {{nombre}}.</p><ul style="padding-left:18px"><li>Citas: <strong>{{n_citas}}</strong></li><li>Sin confirmar todavía: <strong>{{n_sin_confirmar}}</strong></li><li>Primera cita: <strong>{{primera}}</strong> · última: <strong>{{ultima}}</strong></li></ul><p>Entre a SOFA › Agenda para ver el detalle o mover una cita.</p>',
  body_text = E'Su agenda de {{fecha}}\n\nHola, {{nombre}}.\n- Citas: {{n_citas}}\n- Sin confirmar todavía: {{n_sin_confirmar}}\n- Primera cita: {{primera}} · última: {{ultima}}\n\nEntre a SOFA › Agenda para ver el detalle o mover una cita.',
  note = 'Versión inicial (258b): solo conteos y horas, sin datos de pacientes'
 where code = 'agenda_diaria' and version = 1;

do $$ declare d text; begin
  d := pg_get_functiondef('public.generate_doctor_agendas(date)'::regprocedure);
  if position('n_sin_confirmar' in d) = 0 then
    d := replace(d, $r$jsonb_build_object('nombre', r.full_name, 'fecha', to_char(v_date, 'DD/MM/YYYY'), 'agenda', v_text)$r$,
      $r$(select jsonb_build_object('nombre', r.full_name, 'fecha', to_char(v_date, 'DD/MM/YYYY'),
                'n_citas', count(*), 'n_sin_confirmar', count(*) filter (where a.status = 'programada'),
                'primera', coalesce(to_char(min(a.appointment_time), 'HH24:MI'), '—'), 'ultima', coalesce(to_char(max(a.appointment_time), 'HH24:MI'), '—'))
            from public.appointments a where a.provider_id = r.provider_id and a.appointment_date = v_date and a.status not in ('cancelada','no_asistio'))$r$);
    if position('n_sin_confirmar' in d) = 0 then raise exception 'No se pudo ajustar generate_doctor_agendas'; end if;
    execute d;
  end if;
end $$;
