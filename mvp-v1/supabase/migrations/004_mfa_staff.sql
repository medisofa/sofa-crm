-- SOFA MVP v1 — personal SOFA requiere sesión AAL2 (MFA verificado).
-- Requiere 001_core.sql.

create or replace function app.mfa_ok_v1()
returns boolean language sql stable security definer set search_path=''
as $$
  select coalesce(auth.jwt()->>'aal','aal1')='aal2'
$$;

create or replace function app.is_staff_v1()
returns boolean language sql stable security definer set search_path=''
as $$
  select app.mfa_ok_v1() and exists (
    select 1 from public.organization_users_v1 ou
    join public.organizations_v1 o on o.id=ou.organization_id and o.kind='operator'
    where ou.user_id=auth.uid() and ou.is_active
      and ou.role_code in ('super_admin','admin','operations','billing','glosas','assistant','auditor')
  )
$$;

create or replace function app.staff_role_v1()
returns text language sql stable security definer set search_path=''
as $$
  select case when app.mfa_ok_v1() then (
    select ou.role_code from public.organization_users_v1 ou
    join public.organizations_v1 o on o.id=ou.organization_id and o.kind='operator'
    where ou.user_id=auth.uid() and ou.is_active
      and ou.role_code in ('super_admin','admin','operations','billing','glosas','assistant','auditor')
    order by case ou.role_code when 'super_admin' then 1 when 'admin' then 2 else 3 end
    limit 1
  ) end
$$;

create or replace function app.visible_org_ids_v1()
returns setof uuid language sql stable security definer set search_path=''
as $$
  with staff as (
    select ou.organization_id operator_id, ou.role_code
    from public.organization_users_v1 ou
    join public.organizations_v1 o on o.id=ou.organization_id and o.kind='operator'
    where ou.user_id=auth.uid() and ou.is_active and app.mfa_ok_v1()
  ),
  external_direct as (
    select ou.organization_id
    from public.organization_users_v1 ou
    join public.organizations_v1 o on o.id=ou.organization_id and o.kind='client'
    where ou.user_id=auth.uid() and ou.is_active
      and (
        exists(select 1 from public.external_access_home_v1 h where h.user_id=auth.uid() and h.organization_id=ou.organization_id)
        or exists(select 1 from public.external_multi_org_exceptions_v1 e
                  where e.user_id=auth.uid() and e.organization_id=ou.organization_id
                    and e.revoked_at is null and e.valid_until > now())
      )
  ),
  staff_clients as (
    select c.id organization_id
    from public.organizations_v1 c
    join staff s on s.operator_id=c.operator_id
    where c.kind='client' and c.status='active'
      and (
        s.role_code in ('super_admin','admin')
        or exists(select 1 from public.staff_client_access_v1 a where a.user_id=auth.uid() and a.client_org_id=c.id)
      )
  )
  select organization_id from external_direct
  union
  select organization_id from staff_clients
$$;

revoke all on function app.mfa_ok_v1() from public,anon,authenticated;
