-- 217 · Preferencia de dashboard por usuario y cliente
begin;

create table if not exists public.user_dashboard_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  dashboard_code text not null default 'ejecutivo'
    check (dashboard_code in ('ejecutivo','operativo','compacto')),
  updated_at timestamptz not null default now(),
  primary key (user_id, organization_id)
);

alter table public.user_dashboard_preferences enable row level security;

drop policy if exists user_dashboard_preferences_select on public.user_dashboard_preferences;
create policy user_dashboard_preferences_select
on public.user_dashboard_preferences
for select to authenticated
using (
  user_id = auth.uid()
  and organization_id in (select app.visible_org_ids())
);

drop policy if exists user_dashboard_preferences_insert on public.user_dashboard_preferences;
create policy user_dashboard_preferences_insert
on public.user_dashboard_preferences
for insert to authenticated
with check (
  user_id = auth.uid()
  and organization_id in (select app.visible_org_ids())
);

drop policy if exists user_dashboard_preferences_update on public.user_dashboard_preferences;
create policy user_dashboard_preferences_update
on public.user_dashboard_preferences
for update to authenticated
using (
  user_id = auth.uid()
  and organization_id in (select app.visible_org_ids())
)
with check (
  user_id = auth.uid()
  and organization_id in (select app.visible_org_ids())
);

grant select,insert,update on public.user_dashboard_preferences to authenticated;

commit;
