-- SOFA demo-isolation regression audit
-- Read-only. Safe to run against any environment.
-- Purpose: detect whether DEMO organizations contaminate production-facing aggregates.
-- Generated 2026-10-20; does not modify data.

with orgs as (
  select id, operator_id, is_demo
  from public.organizations
  where kind='client'
),
base as (
  select
    (select count(*) from orgs where is_demo=false) as real_clients,
    (select count(*) from orgs where is_demo=true) as demo_clients,
    (select count(*) from public.service_lines l join orgs o on o.id=l.organization_id where o.is_demo=false) as real_service_lines,
    (select count(*) from public.service_lines l join orgs o on o.id=l.organization_id where o.is_demo=true) as demo_service_lines,
    (select count(*) from public.submissions s join orgs o on o.id=s.organization_id where o.is_demo=false) as real_submissions,
    (select count(*) from public.submissions s join orgs o on o.id=s.organization_id where o.is_demo=true) as demo_submissions,
    (select count(*) from public.payments p join orgs o on o.id=p.organization_id where o.is_demo=false) as real_payments,
    (select count(*) from public.payments p join orgs o on o.id=p.organization_id where o.is_demo=true) as demo_payments
)
select * from base;

-- Views touching organizations that do not explicitly reference is_demo.
-- Every production-facing aggregate returned here requires manual classification.
select
  c.relname as view_name,
  position('is_demo' in lower(pg_get_viewdef(c.oid,true))) > 0 as mentions_is_demo
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public'
  and c.relkind in ('v','m')
  and lower(pg_get_viewdef(c.oid,true)) like '%organizations%'
  and position('is_demo' in lower(pg_get_viewdef(c.oid,true))) = 0
order by c.relname;

-- Acceptance criterion:
-- 1) Demo rows remain queryable inside the DEMO organization.
-- 2) Production KPI/report views explicitly exclude organizations.is_demo=true
--    or are organization-scoped so cross-organization aggregation is impossible.
-- 3) Automated jobs that calculate KPIs, invoices, notifications, fees or alerts
--    apply the same rule.
