-- 234 · Resolución segura del prestador médico para Hospitalización
begin;

create or replace function app.hospital_my_provider()
returns uuid
language sql
stable security definer
set search_path=''
as $$
  with direct as (
    select p.id
      from public.providers p
     where p.user_id=auth.uid()
       and p.is_active
     order by p.created_at
     limit 1
  ),
  fallback as (
    select p.id
      from public.organization_users ou
      join public.providers p
        on p.organization_id=ou.organization_id
       and p.is_active
     where ou.user_id=auth.uid()
       and ou.role_code='client'
       and coalesce(ou.is_active,true)
       and not exists (
         select 1
           from public.providers p2
          where p2.organization_id=ou.organization_id
            and p2.is_active
            and p2.id<>p.id
       )
  ),
  fallback_unique as (
    select min(id::text)::uuid as id
      from fallback
    having count(*)=1
  )
  select id from direct
  union all
  select id from fallback_unique
   where not exists(select 1 from direct)
  limit 1
$$;

commit;
