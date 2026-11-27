-- Ya aplicado en producción (27/11/2026). Se guarda aquí como documentación.
-- 276 · Horas por usuario (27/11/2026): tiempo de conexión medido por la app, visible solo para
-- Super Admin y Administrador SOFA. Una fila por usuario y día (hora de Santo Domingo). Cada minuto
-- cuenta una sola vez aunque haya varias pestañas o equipos abiertos.
begin;
do $dep$
begin
  if to_regprocedure('app.is_staff(text[])') is null then
    raise exception 'Falta app.is_staff: aplique primero las migraciones base.';
  end if;
end $dep$;

create table if not exists public.user_connection_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  connected_minutes integer not null default 0 check (connected_minutes between 0 and 1440),
  active_minutes integer not null default 0 check (active_minutes between 0 and 1440),
  first_at timestamptz not null default now(),
  last_at timestamptz not null default now(),
  last_active_at timestamptz,
  primary key (user_id, day)
);
comment on table public.user_connection_days is 'Minutos conectados y activos por usuario y día. Sin acceso directo: solo por usage_ping y usage_hours_report.';
alter table public.user_connection_days enable row level security;
revoke all on public.user_connection_days from anon, authenticated;
create index if not exists user_connection_days_day on public.user_connection_days (day);

-- Latido de la app (una vez por minuto). Solo escribe la fila propia; la hora la pone el servidor.
create or replace function public.usage_ping(p_active boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_day date := (clock_timestamp() at time zone 'America/Santo_Domingo')::date;
begin
  if v_uid is null or not exists (select 1 from public.profiles p where p.id = v_uid and p.is_active) then return; end if;
  insert into public.user_connection_days as d (user_id, day, connected_minutes, active_minutes, first_at, last_at, last_active_at)
  values (v_uid, v_day, 1, case when p_active then 1 else 0 end, v_now, v_now, case when p_active then v_now end)
  on conflict (user_id, day) do update set
    connected_minutes = least(1440, d.connected_minutes
      + case when date_trunc('minute', v_now) > date_trunc('minute', d.last_at) then 1 else 0 end),
    active_minutes = least(1440, d.active_minutes
      + case when p_active and (d.last_active_at is null or date_trunc('minute', v_now) > date_trunc('minute', d.last_active_at)) then 1 else 0 end),
    last_at = greatest(d.last_at, v_now),
    last_active_at = case when p_active then v_now else d.last_active_at end;
end $$;
revoke all on function public.usage_ping(boolean) from public, anon;
grant execute on function public.usage_ping(boolean) to authenticated;

-- Reporte semanal (lunes a domingo). Solo Super Admin y Administrador SOFA.
create or replace function public.usage_hours_report(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_staff(array['super_admin','admin']) then
    raise exception 'Solo la Administración de SOFA puede ver las horas por usuario.' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then
    raise exception 'Elija un período válido de hasta 93 días.' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'since', (select min(day) from public.user_connection_days),
    'rows', coalesce((
      with weeks as (
        select c.user_id, date_trunc('week', c.day)::date as week_start,
               sum(c.connected_minutes)::int as connected_minutes, sum(c.active_minutes)::int as active_minutes,
               count(*)::int as days, max(c.last_at) as last_at
          from public.user_connection_days c where c.day between p_from and p_to group by 1, 2),
      filed as (
        select s.submitted_by as user_id, date_trunc('week', s.submitted_on)::date as week_start, count(*)::int as n
          from public.submissions s join public.organizations o on o.id = s.organization_id and not o.is_demo
         where s.submitted_on::date between p_from and p_to and s.submitted_by is not null group by 1, 2),
      keys as (select user_id, week_start from weeks union select user_id, week_start from filed),
      access as (
        select ou.user_id, bool_or(o.kind = 'operator') as is_sofa,
               string_agg(distinct r.name, ', ' order by r.name) as roles
          from public.organization_users ou
          join public.organizations o on o.id = ou.organization_id and not o.is_demo
          join public.roles r on r.code = ou.role_code
         where ou.is_active group by ou.user_id)
      select jsonb_agg(jsonb_build_object(
               'user_id', p.id, 'name', p.full_name, 'is_sofa', coalesce(a.is_sofa, false), 'roles', a.roles,
               'week_start', k.week_start, 'connected_minutes', coalesce(w.connected_minutes, 0),
               'active_minutes', coalesce(w.active_minutes, 0), 'days', coalesce(w.days, 0), 'last_at', w.last_at,
               'filed', coalesce(f.n, 0))
             order by k.week_start desc nulls last, coalesce(a.is_sofa, false) desc, coalesce(w.active_minutes, 0) desc, p.full_name)
        from public.profiles p
        left join access a on a.user_id = p.id
        left join keys k on k.user_id = p.id
        left join weeks w on w.user_id = k.user_id and w.week_start = k.week_start
        left join filed f on f.user_id = k.user_id and f.week_start = k.week_start
       where (k.user_id is not null or (a.is_sofa and p.is_active))
         -- fuera las cuentas que solo existen en la demostración
         and (a.user_id is not null or not exists (select 1 from public.organization_users x
               join public.organizations xo on xo.id = x.organization_id and xo.is_demo where x.user_id = p.id))
    ), '[]'::jsonb));
end $$;
revoke all on function public.usage_hours_report(date, date) from public, anon;
grant execute on function public.usage_hours_report(date, date) to authenticated;

delete from app.schema_migrations where version = '276';
insert into app.schema_migrations (version, report) values ('276', jsonb_build_object('tema', 'horas por usuario'));
commit;
