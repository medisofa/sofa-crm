-- 236 · Preferencia de vista del dashboard por usuario
begin;

alter table public.profiles
  add column if not exists dashboard_view text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='profiles_dashboard_view_chk'
      and conrelid='public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_dashboard_view_chk
      check (dashboard_view is null or dashboard_view in ('operativo','ejecutivo','visual'));
  end if;
end $$;

create or replace function public.my_dashboard_view()
returns text
language sql
stable
security definer
set search_path=''
as $$
  select p.dashboard_view
  from public.profiles p
  where p.id=auth.uid()
$$;

create or replace function public.set_my_dashboard_view(p_view text)
returns text
language plpgsql
security definer
set search_path=''
as $$
begin
  if p_view not in ('operativo','ejecutivo','visual') then
    raise exception 'Vista de dashboard no válida' using errcode='22023';
  end if;

  update public.profiles
     set dashboard_view=p_view,
         updated_at=now()
   where id=auth.uid();

  if not found then
    raise exception 'Perfil no encontrado' using errcode='P0002';
  end if;

  return p_view;
end
$$;

revoke all on function public.my_dashboard_view() from public,anon;
revoke all on function public.set_my_dashboard_view(text) from public,anon;
grant execute on function public.my_dashboard_view() to authenticated;
grant execute on function public.set_my_dashboard_view(text) to authenticated;

commit;
