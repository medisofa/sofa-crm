-- 260_calendario_medico.sql
-- Ya aplicado en producción (2026-11-20, mcp__Supabase__apply_migration «calendario_medico_260»).
--
-- Opción 1: calendario del médico (iCal). El médico se suscribe UNA vez desde su iPhone, Google Calendar u
-- Outlook a un enlace privado y sus citas aparecen en su teléfono con los avisos nativos (30 min antes).
-- Seguridad y privacidad (decisiones de diseño):
--   · El enlace lleva un token aleatorio de 32 bytes; en la base solo se guarda su SHA-256. Mostrarlo de nuevo es
--     imposible: si se pierde, se genera otro y el anterior deja de funcionar.
--   · Revocable en cualquier momento. Un médico tiene a lo sumo UN enlace activo.
--   · Solo el médico (su usuario), el director de su clínica o la Administración de SOFA lo crean o revocan.
--     La secretaria no (el calendario sale de SOFA hacia la cuenta personal del médico).
--   · El paciente va en iniciales («Cita · R. P.»); nunca nombre completo, cédula ni teléfono.
--   · Rango: 30 días atrás a 90 días adelante; sin citas canceladas ni «no asistió».
--   · Lo sirve la función pública calendario-medico (Supabase Edge Function, sin JWT: los calendarios no
--     inician sesión). app.calendar_feed_ics solo la puede ejecutar service_role.
-- Idempotente. Suite: 261_calendario_medico_test.sql.

do $$ begin
  if to_regprocedure('app.initials(text)') is null then raise exception 'Falta la 258 (app.initials)'; end if;
  if to_regprocedure('app.client_provider_ok(uuid)') is null then raise exception 'Falta la 248'; end if;
end $$;

create table if not exists public.provider_calendar_feeds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id uuid not null references public.providers(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) default auth.uid(),
  revoked_at timestamptz,
  revoked_by uuid references public.profiles(id),
  last_access_at timestamptz,
  access_count integer not null default 0
);
create unique index if not exists provider_calendar_feeds_activo_uq on public.provider_calendar_feeds (provider_id) where revoked_at is null;
alter table public.provider_calendar_feeds enable row level security;
-- Sin políticas: nadie la lee directo (ni siquiera el hash). Todo pasa por las RPC de abajo.

-- ¿Puede el usuario actual manejar el calendario de este médico?
create or replace function app.calendar_feed_can(p_provider uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.providers p where p.id = p_provider and (
           app.can(p.organization_id, array['super_admin','admin'])
        or (app.can(p.organization_id, array['client']) and app.client_provider_ok(p.id)
            and (p.user_id = auth.uid() or p.user_id is null or not app.client_limited(p.organization_id)))));
$$;

create or replace function public.calendar_feed_status(p_provider uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare f public.provider_calendar_feeds;
begin
  if not app.calendar_feed_can(p_provider) then
    raise exception 'Solo el médico, el director de la clínica o la Administración de SOFA manejan este calendario.' using errcode = '42501';
  end if;
  select * into f from public.provider_calendar_feeds where provider_id = p_provider and revoked_at is null;
  return jsonb_build_object('active', f.id is not null, 'created_at', f.created_at, 'last_access_at', f.last_access_at, 'access_count', coalesce(f.access_count, 0));
end $$;

-- Crea un enlace nuevo (revoca el anterior). Devuelve el token en claro UNA sola vez.
create or replace function public.calendar_feed_create(p_provider uuid)
returns text language plpgsql security definer set search_path to '' as $$
declare v_org uuid; v_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  select organization_id into v_org from public.providers where id = p_provider and is_active;
  if v_org is null then raise exception 'El médico no existe o está inactivo.' using errcode = 'P0002'; end if;
  if not app.calendar_feed_can(p_provider) then
    raise exception 'Solo el médico, el director de la clínica o la Administración de SOFA crean el enlace de su calendario.' using errcode = '42501';
  end if;
  update public.provider_calendar_feeds set revoked_at = now(), revoked_by = auth.uid() where provider_id = p_provider and revoked_at is null;
  insert into public.provider_calendar_feeds (organization_id, provider_id, token_hash)
  values (v_org, p_provider, encode(extensions.digest(v_token, 'sha256'), 'hex'));
  return v_token;
end $$;

create or replace function public.calendar_feed_revoke(p_provider uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not app.calendar_feed_can(p_provider) then
    raise exception 'Solo el médico, el director de la clínica o la Administración de SOFA revocan este calendario.' using errcode = '42501';
  end if;
  update public.provider_calendar_feeds set revoked_at = now(), revoked_by = auth.uid() where provider_id = p_provider and revoked_at is null;
end $$;

-- Texto iCal seguro: escapa \ ; , y saltos de línea (RFC 5545 §3.3.11)
create or replace function app.ics_esc(p text)
returns text language sql immutable set search_path to '' as $$
  select replace(replace(replace(replace(coalesce(p, ''), E'\\', E'\\\\'), ';', E'\\;'), ',', E'\\,'), E'\n', E'\\n');
$$;

-- El calendario en formato iCal (solo service_role: lo llama la Edge Function calendario-medico)
create or replace function app.calendar_feed_ics(p_token text)
returns text language plpgsql security definer set search_path to '' as $$
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
     || 'SUMMARY:' || app.ics_esc('Cita · ' || app.initials(a.patient_name) || coalesce(' · ' || a.reason, '')) || nl
     || coalesce('LOCATION:' || app.ics_esc(hc.name) || nl, '')
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
end $$;

revoke execute on function app.calendar_feed_ics(text) from public, anon, authenticated;
grant execute on function app.calendar_feed_ics(text) to service_role;
revoke execute on function public.calendar_feed_status(uuid), public.calendar_feed_create(uuid), public.calendar_feed_revoke(uuid) from public, anon;
grant execute on function public.calendar_feed_status(uuid), public.calendar_feed_create(uuid), public.calendar_feed_revoke(uuid) to authenticated;
-- La Edge Function llama por PostgREST: expone un envoltorio en public, solo para service_role.
create or replace function public.calendar_feed_ics(p_token text)
returns text language sql security definer set search_path to '' as $$ select app.calendar_feed_ics(p_token); $$;
revoke execute on function public.calendar_feed_ics(text) from public, anon, authenticated;
grant execute on function public.calendar_feed_ics(text) to service_role;

-- 260b · (aplicado en producción como «calendario_medico_260b») Iniciales: solo palabras que empiezan con letra.
-- Hallazgo de la prueba con la demo: «Wanda Pérez (demo)» daba «W. (.».
create or replace function app.initials(p_name text)
returns text language sql immutable set search_path to '' as $$
  select coalesce((select string_agg(upper(left(w, 1)) || '.', ' ' order by o)
                     from (select w, row_number() over (order by o) o, count(*) over () c
                             from unnest(regexp_split_to_array(trim(coalesce(p_name, '')), '\s+')) with ordinality as t(w, o)
                            where w ~ '^[[:alpha:]]') x
                    where o = 1 or o = c), '—');
$$;
