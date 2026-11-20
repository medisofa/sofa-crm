-- 244_agenda_centros.sql
-- Ya aplicado en producción (2026-11-20, mcp__Supabase__apply_migration «agenda_centros_244»).
--
-- Agenda por médico y centro (opciones B + C aprobadas el 20/11/2026):
--   B · la secretaria maneja la agenda del médico solo en su centro (capturer_scopes.center_id;
--       null = todos los centros, como hasta hoy: nada cambia para las asignaciones existentes).
--   C · recepción del centro: una usuaria ve a TODOS los médicos de SU organización que atienden
--       en ese centro (reception_scopes). Nunca médicos de otra organización.
--
-- Contenido:
--   1. appointments.center_id y appointments.duration_min (+ índice y relleno con el centro principal).
--   2. provider_schedules (horario por médico, centro y día) y provider_blocks (bloqueos).
--   3. capturer_scopes.center_id y tabla reception_scopes.
--   4. app.reception_centers(), app.appointment_access(): acceso por médico Y centro.
--   5. Política appointments_select usa app.appointment_access (la secretaria por centro deja de ver
--      citas de otros centros).
--   6. Guardia de citas encimadas (trigger) para el mismo médico en cualquier centro.
--   7. save_appointment (con centro y duración), set_appointment_status (acceso por centro).
--   8. RPC: agenda_week, reception_day, my_agenda_scopes, provider_schedule_set, provider_block_set,
--      set_assistant_center, reception_scope_set; list_assistants devuelve el centro.
-- Idempotente. Suite: 245_agenda_centros_test.sql.

-- 0. Dependencias
do $$ begin
  if to_regclass('public.appointments') is null or to_regclass('public.health_centers') is null
     or to_regclass('public.provider_centers') is null or to_regclass('public.capturer_scopes') is null then
    raise exception 'Faltan tablas base (appointments, health_centers, provider_centers, capturer_scopes)';
  end if;
  if to_regprocedure('app.capturer_providers()') is null or to_regprocedure('app.assistant_providers()') is null
     or to_regprocedure('app.can(uuid,text[])') is null or to_regprocedure('app.view_as_user()') is null then
    raise exception 'Faltan funciones app.* de permisos';
  end if;
end $$;

-- 1. Citas: centro y duración
alter table public.appointments add column if not exists center_id uuid references public.health_centers(id) on delete set null;
alter table public.appointments add column if not exists duration_min smallint not null default 30;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'appointments_duration_check') then
    alter table public.appointments add constraint appointments_duration_check check (duration_min between 5 and 480);
  end if;
end $$;
create index if not exists appointments_provider_date_idx on public.appointments (provider_id, appointment_date);
create index if not exists appointments_center_date_idx on public.appointments (center_id, appointment_date);

update public.appointments a set center_id = pc.center_id
  from public.provider_centers pc
 where pc.provider_id = a.provider_id and pc.is_primary and a.center_id is null;

-- 2. Horario y bloqueos
create table if not exists public.provider_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id uuid not null references public.providers(id) on delete cascade,
  center_id uuid not null references public.health_centers(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),          -- ISO: 1 = lunes
  start_time time not null,
  end_time time not null,
  slot_min smallint not null default 30 check (slot_min between 5 and 240),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) default auth.uid(),
  check (end_time > start_time)
);
create index if not exists provider_schedules_provider_idx on public.provider_schedules (provider_id, weekday);
alter table public.provider_schedules enable row level security;

create table if not exists public.provider_blocks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id uuid not null references public.providers(id) on delete cascade,
  block_date date not null,
  start_time time,                                                    -- null = todo el día
  end_time time,
  reason text check (reason is null or length(reason) <= 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) default auth.uid(),
  check ((start_time is null and end_time is null) or (start_time is not null and end_time is not null and end_time > start_time))
);
create index if not exists provider_blocks_provider_idx on public.provider_blocks (provider_id, block_date) where is_active;
alter table public.provider_blocks enable row level security;
drop policy if exists provider_blocks_select on public.provider_blocks;
create policy provider_blocks_select on public.provider_blocks for select using (app.consultorio_access(provider_id, false));

-- 3. Alcance por centro
alter table public.capturer_scopes add column if not exists center_id uuid references public.health_centers(id) on delete cascade;

create table if not exists public.reception_scopes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  center_id uuid not null references public.health_centers(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  can_book boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) default auth.uid(),
  primary key (user_id, center_id)
);
alter table public.reception_scopes enable row level security;
drop policy if exists reception_scopes_select on public.reception_scopes;
create policy reception_scopes_select on public.reception_scopes for select
  using (user_id = auth.uid() or organization_id in (select app.can_orgs(array['super_admin','admin'])));

-- 4. Funciones de acceso
-- Centros de recepción del usuario: la usuaria debe estar activa en la MISMA organización del centro.
create or replace function app.reception_centers()
returns setof uuid language sql stable security definer set search_path to '' as $$
  select rs.center_id
    from public.reception_scopes rs
    join public.health_centers hc on hc.id = rs.center_id and hc.organization_id = rs.organization_id and hc.is_active
    join public.organization_users ou on ou.user_id = rs.user_id and ou.organization_id = rs.organization_id and ou.is_active
    join public.profiles p on p.id = rs.user_id and p.is_active
   where rs.user_id = app.view_as_user() and rs.is_active;
$$;

-- Acceso a citas de un médico en un centro. p_center null = "todos los centros" (solo quien no está limitado a uno).
create or replace function app.appointment_access(p_provider uuid, p_center uuid, p_write boolean default false)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (
    select 1 from public.providers p where p.id = p_provider and (
         app.can(p.organization_id, array['super_admin','admin','assistant','operations','client'])
      or (not p_write and app.can(p.organization_id, array['billing','glosas','auditor']))
      or p.id in (select app.assistant_providers())
      or (p.id in (select app.capturer_providers())
          and exists (select 1 from public.capturer_scopes cs
                       where cs.user_id = app.view_as_user() and cs.provider_id = p.id
                         and (cs.center_id is null or cs.center_id = p_center)))
      or (p_center is not null and p_center in (select app.reception_centers())
          and exists (select 1 from public.provider_centers pc join public.health_centers hc on hc.id = pc.center_id
                       where pc.provider_id = p.id and pc.center_id = p_center and hc.organization_id = p.organization_id))
    ));
$$;

-- Puede agendar: secretaria con can_book en ese centro, recepción con can_book, o roles de la organización.
create or replace function app.appointment_can_book(p_provider uuid, p_center uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.providers p where p.id = p_provider and (
         app.can(p.organization_id, array['super_admin','admin','assistant','operations','client'])
      or p.id in (select app.assistant_providers())
      or (p.id in (select app.capturer_providers())
          and exists (select 1 from public.capturer_scopes cs where cs.user_id = app.view_as_user() and cs.provider_id = p.id
                         and cs.can_book and (cs.center_id is null or cs.center_id = p_center)))
      or (p_center is not null and exists (select 1 from public.reception_scopes rs
                         where rs.user_id = app.view_as_user() and rs.center_id = p_center and rs.can_book and rs.is_active
                           and rs.center_id in (select app.reception_centers()))
          and app.appointment_access(p.id, p_center, true))));
$$;

-- 5. Políticas de lectura
drop policy if exists provider_schedules_select on public.provider_schedules;
create policy provider_schedules_select on public.provider_schedules for select
  using (app.consultorio_access(provider_id, false) or center_id in (select app.reception_centers()));

drop policy if exists appointments_select on public.appointments;
create policy appointments_select on public.appointments for select
  using (app.appointment_access(provider_id, center_id, false));

-- 6. Guardia de citas encimadas (mismo médico, cualquier centro)
create or replace function app.appointment_overlap_guard()
returns trigger language plpgsql security definer set search_path to '' as $$
declare v_other record; v_start timestamp; v_end timestamp;
begin
  if new.appointment_time is null or new.status in ('cancelada','no_asistio') then return new; end if;
  if tg_op = 'UPDATE' and new.appointment_date is not distinct from old.appointment_date
     and new.appointment_time is not distinct from old.appointment_time and new.duration_min = old.duration_min
     and new.provider_id = old.provider_id
     and not (old.status in ('cancelada','no_asistio')) then
    return new;
  end if;
  v_start := new.appointment_date + new.appointment_time;
  v_end := v_start + make_interval(mins => new.duration_min);
  select a.appointment_time, a.center_id into v_other from public.appointments a
   where a.provider_id = new.provider_id and a.appointment_date = new.appointment_date and a.id <> new.id
     and a.appointment_time is not null and a.status not in ('cancelada','no_asistio')
     and (a.appointment_date + a.appointment_time) < v_end
     and (a.appointment_date + a.appointment_time) + make_interval(mins => a.duration_min) > v_start
   limit 1;
  if found then
    raise exception 'Ese horario ya está ocupado (cita de las %). Elija otro hueco libre o mueva la otra cita primero.',
      to_char(v_other.appointment_time, 'HH24:MI') using errcode = '23P01';
  end if;
  if exists (select 1 from public.provider_blocks b where b.provider_id = new.provider_id and b.is_active
               and b.block_date = new.appointment_date
               and (b.start_time is null or ((b.block_date + b.start_time) < v_end and (b.block_date + b.end_time) > v_start))) then
    raise exception 'El médico tiene ese horario bloqueado. Elija otro día u hora.' using errcode = '23P01';
  end if;
  return new;
end $$;
drop trigger if exists appointments_overlap_guard on public.appointments;
create trigger appointments_overlap_guard before insert or update on public.appointments
  for each row execute function app.appointment_overlap_guard();

-- 7. Guardar cita (copiada de su versión vigente y extendida con centro y duración)
drop function if exists public.save_appointment(uuid,uuid,date,time without time zone,text,text,text,text,text,uuid,text,text,text);
create or replace function public.save_appointment(p_id uuid, p_provider uuid, p_date date, p_time time without time zone, p_patient text, p_doc text, p_member text, p_phone text, p_payer text, p_ars uuid, p_authorization text, p_reason text, p_notes text default null::text, p_center uuid default null, p_duration integer default null)
returns uuid language plpgsql security definer set search_path to '' as $function$
declare v_org uuid; v_id uuid; a public.appointments; v_center uuid := p_center; v_dur integer;
begin
  select organization_id into v_org from public.providers where id = p_provider;
  if v_org is null then raise exception 'El médico no existe. Elija un médico de la lista.' using errcode = 'P0002'; end if;
  if p_id is not null then
    select * into a from public.appointments where id = p_id and provider_id = p_provider for update;
    if not found then raise exception 'Cita no encontrada' using errcode = 'P0002'; end if;
    if not app.appointment_access(p_provider, a.center_id, true) then raise exception 'Sin acceso a esta cita: es de otro centro.' using errcode = '42501'; end if;
    v_center := coalesce(v_center, a.center_id);
  end if;
  if v_center is null then   -- centro por defecto: el de la secretaria, si está limitada a uno; si no, el principal del médico
    select cs.center_id into v_center from public.capturer_scopes cs where cs.user_id = app.view_as_user() and cs.provider_id = p_provider;
    if v_center is null then select pc.center_id into v_center from public.provider_centers pc where pc.provider_id = p_provider and pc.is_primary; end if;
  end if;
  if v_center is not null and not exists (select 1 from public.provider_centers pc join public.health_centers hc on hc.id = pc.center_id
                                             where pc.provider_id = p_provider and pc.center_id = v_center and hc.organization_id = v_org) then
    raise exception 'El médico no atiende en ese centro. Elija uno de sus centros.' using errcode = '22023';
  end if;
  if not app.appointment_access(p_provider, v_center, true) then raise exception 'Sin acceso a la agenda de este médico en ese centro' using errcode = '42501'; end if;
  if not app.appointment_can_book(p_provider, v_center) then
    raise exception 'El médico no le ha autorizado dar o cambiar citas. Pídale que lo active en Mis secretarias.' using errcode = '42501';
  end if;
  if p_date is null then raise exception 'Indique la fecha de la cita' using errcode = '22023'; end if;
  if p_payer = 'ars' and p_ars is null then raise exception 'Indique la ARS del paciente (o márquelo como privado)' using errcode = '22023'; end if;
  v_dur := coalesce(p_duration, a.duration_min, (select ps.slot_min from public.provider_schedules ps
            where ps.provider_id = p_provider and ps.center_id = v_center and ps.weekday = extract(isodow from p_date) limit 1), 30);
  if v_dur not between 5 and 480 then raise exception 'La duración va de 5 a 480 minutos' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, patient_doc, member_number, phone, payer_type, ars_id, authorization_number, reason, notes, center_id, duration_min)
    values (v_org, p_provider, p_date, p_time, trim(p_patient), nullif(trim(coalesce(p_doc, '')), ''), nullif(trim(coalesce(p_member, '')), ''), nullif(trim(coalesce(p_phone, '')), ''),
            p_payer, case when p_payer = 'ars' then p_ars end, nullif(trim(coalesce(p_authorization, '')), ''), nullif(trim(coalesce(p_reason, '')), ''), nullif(trim(coalesce(p_notes, '')), ''), v_center, v_dur)
    returning id into v_id;
  else
    if a.status in ('atendida','cancelada','no_asistio') then raise exception 'La cita ya está cerrada (%): no se edita', a.status using errcode = '23514'; end if;
    update public.appointments set appointment_date = p_date, appointment_time = p_time, patient_name = trim(p_patient), patient_doc = nullif(trim(coalesce(p_doc, '')), ''),
           member_number = nullif(trim(coalesce(p_member, '')), ''), phone = nullif(trim(coalesce(p_phone, '')), ''), payer_type = p_payer, ars_id = case when p_payer = 'ars' then p_ars end,
           authorization_number = nullif(trim(coalesce(p_authorization, '')), ''), reason = nullif(trim(coalesce(p_reason, '')), ''), notes = nullif(trim(coalesce(p_notes, '')), ''),
           center_id = v_center, duration_min = v_dur
     where id = p_id returning id into v_id;
  end if;
  return v_id;
end $function$;
grant execute on function public.save_appointment(uuid,uuid,date,time without time zone,text,text,text,text,text,uuid,text,text,text,uuid,integer) to authenticated;

create or replace function public.set_appointment_status(p_id uuid, p_status text, p_note text default null::text)
returns void language plpgsql security definer set search_path to '' as $function$
declare a public.appointments;
begin
  select * into a from public.appointments where id = p_id for update;
  if not found then raise exception 'Cita no encontrada' using errcode = 'P0002'; end if;
  if not app.appointment_access(a.provider_id, a.center_id, true) then raise exception 'Sin acceso a la agenda de este médico' using errcode = '42501'; end if;
  if p_status not in ('programada', 'confirmada', 'en_espera', 'en_consulta', 'no_asistio', 'cancelada') then
    raise exception '"Atendida" se registra al capturar la reclamación o el cobro del paciente' using errcode = '22023';
  end if;
  if a.status = 'atendida' then raise exception 'La cita ya fue atendida' using errcode = '23514'; end if;
  update public.appointments set status = p_status, status_changed_at = now(),
         notes = coalesce(nullif(trim(coalesce(p_note, '')), ''), notes)
   where id = p_id;
end $function$;

-- 8. RPC de lectura para las pantallas
-- Ocupado "sin detalle": horas en que el médico no está disponible para quien mira (otro centro, citas que no ve, bloqueos).
create or replace function app.agenda_busy(p_provider uuid, p_from date, p_to date, p_center uuid)
returns jsonb language sql stable security definer set search_path to '' as $$
  select coalesce(jsonb_agg(x order by x->>'date', x->>'start'), '[]'::jsonb) from (
    select jsonb_build_object('date', a.appointment_date, 'start', to_char(a.appointment_time, 'HH24:MI'),
                              'end', to_char(a.appointment_time + make_interval(mins => a.duration_min), 'HH24:MI'), 'kind', 'otro_centro') x
      from public.appointments a
     where a.provider_id = p_provider and a.appointment_date between p_from and p_to and a.appointment_time is not null
       and a.status not in ('cancelada','no_asistio')
       and not (app.appointment_access(a.provider_id, a.center_id, false) and (p_center is null or a.center_id is not distinct from p_center))
    union all
    select jsonb_build_object('date', d::date, 'start', to_char(ps.start_time, 'HH24:MI'), 'end', to_char(ps.end_time, 'HH24:MI'), 'kind', 'otro_centro')
      from public.provider_schedules ps cross join generate_series(p_from, p_to, interval '1 day') d
     where ps.provider_id = p_provider and p_center is not null and ps.center_id <> p_center and ps.weekday = extract(isodow from d)
    union all
    select jsonb_build_object('date', b.block_date, 'start', coalesce(to_char(b.start_time, 'HH24:MI'), '00:00'), 'end', coalesce(to_char(b.end_time, 'HH24:MI'), '23:59'),
                              'kind', 'bloqueo', 'reason', case when app.consultorio_access(p_provider, false) then b.reason end)
      from public.provider_blocks b
     where b.provider_id = p_provider and b.is_active and b.block_date between p_from and p_to
  ) s;
$$;

create or replace function public.agenda_week(p_provider uuid, p_center uuid, p_from date, p_days integer default 7)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
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
                                  'center_id', a.center_id) order by a.appointment_date, a.appointment_time nulls last)
                            from public.appointments a left join public.ars ar on ar.id = a.ars_id
                           where a.provider_id = p_provider and a.appointment_date between p_from and v_to
                             and (p_center is null or a.center_id = p_center)
                             and app.appointment_access(a.provider_id, a.center_id, false)), '[]'::jsonb),
    'busy', app.agenda_busy(p_provider, p_from, v_to, p_center));
end $$;

create or replace function public.reception_day(p_center uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.health_centers where id = p_center and is_active;
  if v_org is null then raise exception 'El centro no existe o está inactivo.' using errcode = 'P0002'; end if;
  if not (p_center in (select app.reception_centers()) or app.can(v_org, array['super_admin','admin','assistant','operations','client'])) then
    raise exception 'No tiene asignada la recepción de este centro. Pida al Administrador que se la asigne.' using errcode = '42501';
  end if;
  return jsonb_build_object('center', (select jsonb_build_object('id', id, 'name', name) from public.health_centers where id = p_center),
    'date', p_date,
    'providers', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'full_name', p.full_name, 'specialty', p.specialty,
        'schedule', coalesce((select jsonb_agg(jsonb_build_object('start', to_char(ps.start_time, 'HH24:MI'), 'end', to_char(ps.end_time, 'HH24:MI'), 'slot_min', ps.slot_min))
                               from public.provider_schedules ps where ps.provider_id = p.id and ps.center_id = p_center and ps.weekday = extract(isodow from p_date)), '[]'::jsonb),
        'appointments', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'time', to_char(a.appointment_time, 'HH24:MI'), 'duration_min', a.duration_min,
                               'patient_name', a.patient_name, 'phone', a.phone, 'payer_type', a.payer_type, 'ars_name', ar.name, 'reason', a.reason,
                               'status', a.status, 'eligibility_status', a.eligibility_status, 'status_changed_at', a.status_changed_at) order by a.appointment_time nulls last)
                               from public.appointments a left join public.ars ar on ar.id = a.ars_id
                              where a.provider_id = p.id and a.center_id = p_center and a.appointment_date = p_date), '[]'::jsonb),
        'busy', app.agenda_busy(p.id, p_date, p_date, p_center)) order by p.full_name)
      from public.providers p join public.provider_centers pc on pc.provider_id = p.id and pc.center_id = p_center
     where p.organization_id = v_org and p.is_active), '[]'::jsonb));
end $$;

create or replace function public.my_agenda_scopes()
returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object(
    'centers_by_provider', coalesce((select jsonb_object_agg(x.provider_id, x.centers) from (
        select pc.provider_id, jsonb_agg(jsonb_build_object('id', hc.id, 'name', hc.name, 'is_primary', pc.is_primary) order by pc.is_primary desc, hc.name) centers
          from public.provider_centers pc join public.health_centers hc on hc.id = pc.center_id and hc.is_active
          join public.providers p on p.id = pc.provider_id and p.organization_id = hc.organization_id
         where app.appointment_access(pc.provider_id, pc.center_id, false)
         group by pc.provider_id) x), '{}'::jsonb),
    'reception', coalesce((select jsonb_agg(jsonb_build_object('id', hc.id, 'name', hc.name) order by hc.name)
                             from public.health_centers hc where hc.id in (select app.reception_centers())), '[]'::jsonb));
$$;

-- Horario: reemplaza el de un médico en un centro. Rechaza choques con su horario en otro centro.
create or replace function public.provider_schedule_set(p_provider uuid, p_center uuid, p_rows jsonb)
returns void language plpgsql security definer set search_path to '' as $$
declare v_org uuid; r jsonb; v_wd int; v_s time; v_e time; v_slot int;
begin
  select organization_id into v_org from public.providers where id = p_provider;
  if v_org is null then raise exception 'El médico no existe.' using errcode = 'P0002'; end if;
  if not app.can(v_org, array['super_admin','admin','client']) and p_provider not in (select app.assistant_providers()) then
    raise exception 'Solo el médico, su asistente o el Administrador definen el horario.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.provider_centers pc join public.health_centers hc on hc.id = pc.center_id
                  where pc.provider_id = p_provider and pc.center_id = p_center and hc.organization_id = v_org) then
    raise exception 'El médico no atiende en ese centro. Agréguelo primero a sus centros.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then raise exception 'Horario inválido' using errcode = '22023'; end if;
  delete from public.provider_schedules where provider_id = p_provider and center_id = p_center;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_wd := (r->>'weekday')::int; v_s := (r->>'start')::time; v_e := (r->>'end')::time; v_slot := coalesce((r->>'slot_min')::int, 30);
    if v_wd not between 1 and 7 or v_s is null or v_e is null or v_e <= v_s then
      raise exception 'Revise el horario: cada bloque necesita día, hora de inicio y una hora de fin posterior.' using errcode = '22023';
    end if;
    if exists (select 1 from public.provider_schedules ps where ps.provider_id = p_provider and ps.weekday = v_wd and ps.start_time < v_e and ps.end_time > v_s) then
      raise exception 'Ese horario choca con otro bloque del médico ese mismo día (puede ser en otro centro).' using errcode = '23P01';
    end if;
    insert into public.provider_schedules (organization_id, provider_id, center_id, weekday, start_time, end_time, slot_min)
    values (v_org, p_provider, p_center, v_wd, v_s, v_e, v_slot);
  end loop;
end $$;

create or replace function public.provider_block_set(p_id uuid, p_provider uuid, p_date date, p_start time, p_end time, p_reason text, p_active boolean default true)
returns uuid language plpgsql security definer set search_path to '' as $$
declare v_org uuid; v_id uuid;
begin
  select organization_id into v_org from public.providers where id = p_provider;
  if v_org is null then raise exception 'El médico no existe.' using errcode = 'P0002'; end if;
  if not app.can(v_org, array['super_admin','admin','client']) and p_provider not in (select app.assistant_providers())
     and not app.appointment_can_book(p_provider, null) then
    raise exception 'No tiene permiso para bloquear la agenda de este médico.' using errcode = '42501';
  end if;
  if p_date is null then raise exception 'Indique la fecha del bloqueo' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.provider_blocks (organization_id, provider_id, block_date, start_time, end_time, reason)
    values (v_org, p_provider, p_date, p_start, p_end, nullif(trim(coalesce(p_reason, '')), '')) returning id into v_id;
  else
    update public.provider_blocks set block_date = p_date, start_time = p_start, end_time = p_end,
           reason = nullif(trim(coalesce(p_reason, '')), ''), is_active = coalesce(p_active, true)
     where id = p_id and provider_id = p_provider returning id into v_id;
    if v_id is null then raise exception 'Bloqueo no encontrado' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end $$;

-- Centro de la secretaria (null = todos los centros del médico)
create or replace function public.set_assistant_center(p_user uuid, p_provider uuid, p_center uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.providers where id = p_provider;
  if v_org is null then raise exception 'El médico no existe. Elija un médico de la lista.' using errcode = 'P0002'; end if;
  if not app.can(v_org, array['super_admin','admin','client']) then
    raise exception 'Solo el médico o el Administrador pueden cambiar el centro de la secretaria.' using errcode = '42501';
  end if;
  if p_center is not null and not exists (select 1 from public.provider_centers pc join public.health_centers hc on hc.id = pc.center_id
                                           where pc.provider_id = p_provider and pc.center_id = p_center and hc.organization_id = v_org) then
    raise exception 'El médico no atiende en ese centro. Elija uno de sus centros.' using errcode = '22023';
  end if;
  update public.capturer_scopes set center_id = p_center where user_id = p_user and provider_id = p_provider;
  if not found then raise exception 'Esa secretaria no está asignada a este médico. Asígnela primero desde Usuarios.' using errcode = 'P0002'; end if;
end $$;

-- Recepción del centro: solo Administración, y solo para usuarias activas de la MISMA organización del centro.
create or replace function public.reception_scope_set(p_user uuid, p_center uuid, p_active boolean, p_can_book boolean default true)
returns void language plpgsql security definer set search_path to '' as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.health_centers where id = p_center;
  if v_org is null then raise exception 'El centro no existe.' using errcode = 'P0002'; end if;
  if not app.can(v_org, array['super_admin','admin']) then
    raise exception 'Solo la Administración asigna la recepción de un centro.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.organization_users ou where ou.user_id = p_user and ou.organization_id = v_org and ou.is_active) then
    raise exception 'Esa usuaria no pertenece a la organización del centro. Agréguela primero desde Usuarios.' using errcode = '42501';
  end if;
  insert into public.reception_scopes (user_id, center_id, organization_id, can_book, is_active)
  values (p_user, p_center, v_org, coalesce(p_can_book, true), coalesce(p_active, true))
  on conflict (user_id, center_id) do update set is_active = excluded.is_active, can_book = excluded.can_book;
end $$;

-- list_assistants: copiada de su versión vigente y extendida con el centro
create or replace function public.list_assistants(p_provider uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare v_org uuid;
begin
  select organization_id into v_org from public.providers where id = p_provider;
  if v_org is null then
    raise exception 'El médico no existe. Elija un médico de la lista.' using errcode = 'P0002';
  end if;
  if not app.can(v_org, array['super_admin','admin','client']) then
    raise exception 'Solo el médico o el Administrador pueden ver los permisos de las secretarias.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', cs.user_id, 'name', pr.full_name, 'active', pr.is_active,
                                                      'can_book', cs.can_book, 'can_whatsapp', cs.can_whatsapp, 'can_payments', cs.can_payments,
                                                      'center_id', cs.center_id, 'center_name', hc.name) order by pr.full_name)
                     from public.capturer_scopes cs join public.profiles pr on pr.id = cs.user_id
                     left join public.health_centers hc on hc.id = cs.center_id
                    where cs.provider_id = p_provider), '[]'::jsonb);
end
$function$;

revoke execute on function app.appointment_overlap_guard() from public;
revoke execute on function public.save_appointment(uuid,uuid,date,time without time zone,text,text,text,text,text,uuid,text,text,text,uuid,integer),
  public.agenda_week(uuid,uuid,date,integer), public.reception_day(uuid,date), public.my_agenda_scopes(),
  public.provider_schedule_set(uuid,uuid,jsonb), public.provider_block_set(uuid,uuid,date,time,time,text,boolean),
  public.set_assistant_center(uuid,uuid,uuid), public.reception_scope_set(uuid,uuid,boolean,boolean) from public, anon;
grant execute on function public.agenda_week(uuid,uuid,date,integer), public.reception_day(uuid,date), public.my_agenda_scopes(),
  public.provider_schedule_set(uuid,uuid,jsonb), public.provider_block_set(uuid,uuid,date,time,time,text,boolean),
  public.set_assistant_center(uuid,uuid,uuid), public.reception_scope_set(uuid,uuid,boolean,boolean) to authenticated;
