-- SOFA RBAC + autoentrenamiento persistente
-- Safe additive migration. No destructive data changes.

create schema if not exists app;

create or replace function app.rbac_admin_ok(p_roles text[] default array['super_admin','admin'])
returns boolean
language sql stable security definer set search_path=''
as $$
  select exists (
    select 1
    from public.organization_users ou
    join public.organizations o on o.id=ou.organization_id and o.kind='operator'
    join public.profiles p on p.id=ou.user_id and p.is_active
    where ou.user_id=auth.uid()
      and ou.is_active
      and ou.role_code=any(p_roles)
      and coalesce(auth.jwt()->>'aal','aal1')='aal2'
  )
$$;

revoke all on function app.rbac_admin_ok(text[]) from public,anon;
grant execute on function app.rbac_admin_ok(text[]) to authenticated;

create table if not exists public.role_capabilities (
  role_code text not null references public.roles(code) on update cascade on delete cascade,
  capability_code text not null,
  can_view boolean not null default true,
  can_create boolean not null default false,
  can_edit boolean not null default false,
  can_approve boolean not null default false,
  requires_mfa boolean not null default false,
  risk_level text not null default 'low' check (risk_level in ('low','medium','high','critical')),
  training_required boolean not null default false,
  training_version integer not null default 1 check (training_version > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key (role_code, capability_code)
);

alter table public.role_capabilities enable row level security;

drop policy if exists role_capabilities_read on public.role_capabilities;
create policy role_capabilities_read on public.role_capabilities
for select to authenticated using (true);

drop policy if exists role_capabilities_manage on public.role_capabilities;
create policy role_capabilities_manage on public.role_capabilities
for all to authenticated
using (app.rbac_admin_ok(array['super_admin','admin']))
with check (app.rbac_admin_ok(array['super_admin','admin']));

grant select on public.role_capabilities to authenticated;
grant insert,update,delete on public.role_capabilities to authenticated;

create table if not exists public.user_training_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null references public.roles(code) on update cascade,
  training_key text not null,
  training_version integer not null default 1 check (training_version > 0),
  status text not null default 'pending' check (status in ('pending','in_progress','completed','expired')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  completed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  primary key (user_id, role_code, training_key)
);

alter table public.user_training_progress enable row level security;

drop policy if exists training_self_read on public.user_training_progress;
create policy training_self_read on public.user_training_progress
for select to authenticated using (user_id = auth.uid());

drop policy if exists training_self_insert on public.user_training_progress;
create policy training_self_insert on public.user_training_progress
for insert to authenticated with check (user_id = auth.uid());

drop policy if exists training_self_update on public.user_training_progress;
create policy training_self_update on public.user_training_progress
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists training_staff_read on public.user_training_progress;
create policy training_staff_read on public.user_training_progress
for select to authenticated using (app.rbac_admin_ok(array['super_admin','admin','auditor']));

grant select,insert,update on public.user_training_progress to authenticated;

-- Core capability matrix. UI remains backward compatible; this becomes the governed source.
insert into public.role_capabilities
(role_code,capability_code,can_view,can_create,can_edit,can_approve,requires_mfa,risk_level,training_required,training_version)
values
('super_admin','users.manage',true,true,true,true,true,'critical',true,1),
('super_admin','security.manage',true,true,true,true,true,'critical',true,1),
('super_admin','claims.manage',true,true,true,true,true,'high',true,1),
('super_admin','submissions.manage',true,true,true,true,true,'high',true,1),
('super_admin','payments.manage',true,true,true,true,true,'critical',true,1),
('super_admin','denials.manage',true,true,true,true,true,'high',true,1),

('admin','users.manage',true,true,true,false,true,'high',true,1),
('admin','claims.manage',true,true,true,true,true,'high',true,1),
('admin','submissions.manage',true,true,true,true,true,'high',true,1),
('admin','payments.manage',true,true,true,false,true,'critical',true,1),
('admin','denials.manage',true,true,true,false,true,'high',true,1),

('operations','claims.manage',true,true,true,false,true,'high',true,1),
('operations','submissions.prepare',true,true,true,false,true,'medium',true,1),
('operations','documents.manage',true,true,true,false,true,'medium',true,1),

('billing','claims.manage',true,true,true,false,true,'high',true,1),
('billing','submissions.manage',true,true,true,false,true,'high',true,1),
('billing','payments.manage',false,false,false,false,true,'critical',true,1),
('billing','denials.read',true,false,false,false,true,'medium',true,1),

('glosas','claims.read',true,false,false,false,true,'medium',true,1),
('glosas','payments.manage',true,true,true,true,true,'critical',true,1),
('glosas','denials.manage',true,true,true,true,true,'high',true,1),

('assistant','crm.manage',true,true,true,false,true,'medium',true,1),
('assistant','onboarding.manage',true,true,true,false,true,'medium',true,1),
('assistant','claims.read',true,false,false,false,true,'medium',true,1),

('auditor','audit.read',true,false,false,false,true,'high',true,1),
('auditor','claims.read',true,false,false,false,true,'medium',true,1),
('auditor','payments.read',true,false,false,false,true,'high',true,1),
('auditor','denials.read',true,false,false,false,true,'medium',true,1),

('client','practice.read',true,false,false,false,false,'low',true,1),
('client','claims.capture',true,true,true,false,false,'medium',true,1),
('client','claims.read',true,false,false,false,false,'low',true,1),
('client','results.read',true,false,false,false,false,'low',true,1),

('capturer','agenda.manage',true,true,true,false,false,'low',true,1),
('capturer','patients.manage',true,true,true,false,false,'medium',true,1),
('capturer','claims.capture',true,true,true,false,false,'medium',true,1),

('prospect','onboarding.read',true,false,false,false,false,'low',true,1)
on conflict(role_code,capability_code) do update set
  can_view=excluded.can_view,
  can_create=excluded.can_create,
  can_edit=excluded.can_edit,
  can_approve=excluded.can_approve,
  requires_mfa=excluded.requires_mfa,
  risk_level=excluded.risk_level,
  training_required=excluded.training_required,
  training_version=excluded.training_version,
  updated_at=now();

create or replace function public.my_role_capabilities()
returns table(
  capability_code text,
  can_view boolean,
  can_create boolean,
  can_edit boolean,
  can_approve boolean,
  requires_mfa boolean,
  risk_level text,
  training_required boolean,
  training_version integer
)
language sql stable security definer set search_path=''
as $$
  select rc.capability_code,rc.can_view,rc.can_create,rc.can_edit,rc.can_approve,
         rc.requires_mfa,rc.risk_level,rc.training_required,rc.training_version
  from public.role_capabilities rc
  where rc.role_code in (
    select ou.role_code
    from public.organization_users ou
    join public.profiles p on p.id=ou.user_id and p.is_active
    where ou.user_id=auth.uid() and ou.is_active
  )
  order by rc.capability_code
$$;

revoke all on function public.my_role_capabilities() from public,anon;
grant execute on function public.my_role_capabilities() to authenticated;

create or replace function public.users_access_readiness()
returns table(
  user_id uuid,
  email text,
  email_confirmed boolean,
  profile_active boolean,
  membership_active boolean,
  role_code text,
  role_valid boolean,
  organization_id uuid,
  organization_name text,
  organization_kind text,
  readiness text
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not app.rbac_admin_ok(array['super_admin','admin']) then
    raise exception 'Solo Super Admin o Administrador pueden revisar accesos' using errcode='42501';
  end if;

  return query
  select
    u.id,
    u.email::text,
    (u.email_confirmed_at is not null),
    coalesce(p.is_active,false),
    coalesce(ou.is_active,false),
    ou.role_code,
    (r.code is not null),
    ou.organization_id,
    coalesce(o.trade_name,o.legal_name)::text,
    o.kind::text,
    case
      when u.email_confirmed_at is null then 'email_pending'
      when not coalesce(p.is_active,false) then 'profile_inactive'
      when ou.user_id is null then 'no_membership'
      when not coalesce(ou.is_active,false) then 'membership_inactive'
      when r.code is null then 'invalid_role'
      when r.is_staff and o.kind <> 'operator' then 'role_org_mismatch'
      when not r.is_staff and ou.role_code in ('client','capturer') and o.kind <> 'client' then 'role_org_mismatch'
      else 'ready'
    end::text
  from auth.users u
  left join public.profiles p on p.id=u.id
  left join public.organization_users ou on ou.user_id=u.id
  left join public.roles r on r.code=ou.role_code
  left join public.organizations o on o.id=ou.organization_id
  order by u.email, o.kind desc nulls last;
end
$$;

revoke all on function public.users_access_readiness() from public,anon;
grant execute on function public.users_access_readiness() to authenticated;
