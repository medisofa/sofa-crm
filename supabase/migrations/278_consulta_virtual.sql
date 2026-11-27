-- PENDIENTE de aplicar en producción. No fusionar así.
-- 278 · Consulta virtual en el calendario (27/11/2026). Cada cita es presencial o virtual; la virtual
-- puede llevar el enlace de la videollamada (solo https). No cambia tarifas, reclamaciones ni cobros.
begin;
do $dep$
begin
  if to_regprocedure('public.save_appointment(uuid,uuid,date,time without time zone,text,text,text,text,text,uuid,text,text,text,uuid,integer)') is null
     or to_regprocedure('app.calendar_feed_ics(text)') is null then
    raise exception 'Faltan la 244 y la 260: aplíquelas antes de la 278.';
  end if;
end $dep$;

alter table public.appointments add column if not exists modality text not null default 'presencial';
alter table public.appointments add column if not exists virtual_link text;
alter table public.appointments drop constraint if exists appointments_modality_check;
alter table public.appointments add constraint appointments_modality_check check (modality in ('presencial', 'virtual'));
alter table public.appointments drop constraint if exists appointments_virtual_link_check;
alter table public.appointments add constraint appointments_virtual_link_check
  check (virtual_link is null or (modality = 'virtual' and length(virtual_link) <= 500 and virtual_link ~ '^https://[^[:space:]<>"]+$'));

-- Guarda la cita y su modalidad en una sola operación. Los permisos los decide save_appointment,
-- que se ejecuta primero: si rechaza, no se escribe nada.
create or replace function public.save_appointment_modality(p_id uuid, p_provider uuid, p_date date, p_time time without time zone,
  p_patient text, p_doc text, p_member text, p_phone text, p_payer text, p_ars uuid, p_authorization text, p_reason text,
  p_notes text, p_center uuid, p_duration integer, p_modality text, p_link text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_link text := nullif(trim(coalesce(p_link, '')), '');
begin
  if coalesce(p_modality, '') not in ('presencial', 'virtual') then
    raise exception 'Elija la modalidad: presencial o virtual.' using errcode = '22023';
  end if;
  if p_modality = 'presencial' then v_link := null; end if;
  if v_link is not null and (length(v_link) > 500 or v_link !~ '^https://[^[:space:]<>"]+$') then
    raise exception 'El enlace de la videollamada debe empezar por https:// y no llevar espacios. Cópielo completo.' using errcode = '22023';
  end if;
  v_id := public.save_appointment(p_id, p_provider, p_date, p_time, p_patient, p_doc, p_member, p_phone, p_payer, p_ars,
                                  p_authorization, p_reason, p_notes, p_center, p_duration);
  update public.appointments set modality = p_modality, virtual_link = v_link where id = v_id;
  return v_id;
end $$;
revoke all on function public.save_appointment_modality(uuid,uuid,date,time,text,text,text,text,text,uuid,text,text,text,uuid,integer,text,text) from public, anon;
grant execute on function public.save_appointment_modality(uuid,uuid,date,time,text,text,text,text,text,uuid,text,text,text,uuid,integer,text,text) to authenticated;

-- 244 · agenda_week, igual que antes más modality y virtual_link.
CREATE OR REPLACE FUNCTION public.agenda_week(p_provider uuid, p_center uuid, p_from date, p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_to date := p_from + greatest(1, least(coalesce(p_days, 7), 14)) - 1;
begin
  if not app.appointment_access(p_provider, p_center, false) then
    raise exception 'Sin acceso a la agenda de este médico en ese centro. Elija su centro en la lista.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'from', p_from, 'to', v_to,
    'schedule', coalesce((select jsonb_agg(jsonb_build_object('center_id', ps.center_id, 'weekday', ps.weekday, 'start', to_char(ps.start_time, 'HH24:MI'),
                                  'end', to_char(ps.end_time, 'HH24:MI'), 'slot_min', ps.slot_min) order by ps.weekday, ps.start_time)
                            from public.provider_schedules ps where ps.provider_id = p_provider and (p_center is null or ps.center_id = p_center)), '[]'::jsonb),
    'appointments', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'date', a.appointment_date, 'time', to_char(a.appointment_time, 'HH24:MI'),
                                  'duration_min', a.duration_min, 'patient_name', a.patient_name, 'phone', a.phone, 'payer_type', a.payer_type,
                                  'ars_name', ar.name, 'reason', a.reason, 'status', a.status, 'eligibility_status', a.eligibility_status,
                                  'center_id', a.center_id, 'modality', a.modality, 'virtual_link', a.virtual_link) order by a.appointment_date, a.appointment_time nulls last)
                            from public.appointments a left join public.ars ar on ar.id = a.ars_id
                           where a.provider_id = p_provider and a.appointment_date between p_from and v_to
                             and (p_center is null or a.center_id = p_center)
                             and app.appointment_access(a.provider_id, a.center_id, false)), '[]'::jsonb),
    'busy', app.agenda_busy(p_provider, p_from, v_to, p_center));
end $function$;

-- 260 · Calendario del teléfono: la cita virtual se marca como tal. El enlace NO viaja en el calendario.
CREATE OR REPLACE FUNCTION app.calendar_feed_ics(p_token text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.provider_calendar_feeds; v_name text; v_out text; nl constant text := E'\r\n';
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
  select * into f from public.provider_calendar_feeds
   where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and revoked_at is null;
  if not found then return null; end if;
  select full_name into v_name from public.providers where id = f.provider_id and is_active;
  if v_name is null then return null; end if;
  update public.provider_calendar_feeds set last_access_at = now(), access_count = access_count + 1 where id = f.id;
  v_out := 'BEGIN:VCALENDAR' || nl || 'VERSION:2.0' || nl || 'PRODID:-//SOFA//Agenda del medico//ES' || nl
        || 'CALSCALE:GREGORIAN' || nl || 'METHOD:PUBLISH' || nl
        || 'X-WR-CALNAME:' || app.ics_esc('SOFA · ' || v_name) || nl
        || 'X-WR-TIMEZONE:America/Santo_Domingo' || nl || 'REFRESH-INTERVAL;VALUE=DURATION:PT1H' || nl || 'X-PUBLISHED-TTL:PT1H' || nl
        || 'BEGIN:VTIMEZONE' || nl || 'TZID:America/Santo_Domingo' || nl || 'BEGIN:STANDARD' || nl || 'DTSTART:19700101T000000' || nl
        || 'TZOFFSETFROM:-0400' || nl || 'TZOFFSETTO:-0400' || nl || 'TZNAME:AST' || nl || 'END:STANDARD' || nl || 'END:VTIMEZONE' || nl;
  v_out := v_out || coalesce((select string_agg(
        'BEGIN:VEVENT' || nl
     || 'UID:' || a.id || '@sofamedica.com' || nl
     || 'DTSTAMP:' || to_char(coalesce(a.status_changed_at, a.created_at) at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"') || nl
     || 'DTSTART;TZID=America/Santo_Domingo:' || to_char(a.appointment_date + coalesce(a.appointment_time, time '08:00'), 'YYYYMMDD"T"HH24MISS') || nl
     || 'DTEND;TZID=America/Santo_Domingo:' || to_char(a.appointment_date + coalesce(a.appointment_time, time '08:00') + make_interval(mins => a.duration_min), 'YYYYMMDD"T"HH24MISS') || nl
     || 'SUMMARY:' || app.ics_esc(case when a.modality = 'virtual' then 'Virtual · ' else 'Cita · ' end || app.initials(a.patient_name) || coalesce(' · ' || a.reason, '')) || nl
     || coalesce('LOCATION:' || app.ics_esc(case when a.modality = 'virtual' then 'Consulta virtual' else hc.name end) || nl, '')
     || 'DESCRIPTION:' || app.ics_esc(case a.status when 'programada' then 'Sin confirmar' when 'confirmada' then 'Confirmada'
                                       when 'en_espera' then 'El paciente llegó' when 'en_consulta' then 'En consulta' when 'atendida' then 'Atendida' else a.status end
                                  || case when a.payer_type = 'ars' then ' · ARS' else ' · Privado' end || '. Detalle en SOFA.') || nl
     || 'STATUS:' || case when a.status = 'programada' then 'TENTATIVE' else 'CONFIRMED' end || nl
     || 'BEGIN:VALARM' || nl || 'ACTION:DISPLAY' || nl || 'DESCRIPTION:' || app.ics_esc('Cita en 30 minutos') || nl || 'TRIGGER:-PT30M' || nl || 'END:VALARM' || nl
     || 'END:VEVENT' || nl, '' order by a.appointment_date, a.appointment_time)
       from public.appointments a left join public.health_centers hc on hc.id = a.center_id
      where a.provider_id = f.provider_id and a.status not in ('cancelada','no_asistio')
        and a.appointment_date between current_date - 30 and current_date + 90), '');
  return v_out || 'END:VCALENDAR' || nl;
end $function$;

delete from app.schema_migrations where version = '278';
insert into app.schema_migrations (version, report) values ('278', jsonb_build_object('tema', 'consulta virtual en el calendario'));
commit;
