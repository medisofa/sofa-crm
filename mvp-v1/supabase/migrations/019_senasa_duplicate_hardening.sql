-- SOFA · Endurecimiento final SeNaSa + anti-duplicados

create index if not exists service_lines_dup_lookup_idx
  on public.service_lines(organization_id, member_number, service_date);

create index if not exists service_lines_dup_auth_date_idx
  on public.service_lines(organization_id, authorization_date);

create index if not exists service_lines_dup_auth_number_idx
  on public.service_lines(organization_id, authorization_number);

create index if not exists senasa_auth_match_idx
  on public.senasa_certificate_authorizations(certificate_id, match_status);

create or replace function public.claim_duplicate_summary()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  with d as (
    select distinct least(line_id,other_line_id) a, greatest(line_id,other_line_id) b, risk, blocks_radicacion, review_decision
    from public.claim_duplicate_candidates(null,null)
  )
  select jsonb_build_object(
    'total',count(*),
    'blocking',count(*) filter(where blocks_radicacion),
    'critical',count(*) filter(where risk='critico'),
    'high',count(*) filter(where risk='alto'),
    'reviewed',count(*) filter(where review_decision is not null)
  ) from d
$$;

revoke all on function public.claim_duplicate_summary() from public,anon;
grant execute on function public.claim_duplicate_summary() to authenticated;

create or replace function public.senasa_certificate_reconciliation(p_certificate uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  with c as (
    select * from public.senasa_payment_certificates
    where id=p_certificate and organization_id in (select app.visible_org_ids())
  ),
  a as (
    select x.*
    from public.senasa_certificate_authorizations x
    join c on c.id=x.certificate_id
  )
  select jsonb_build_object(
    'certificate_id',(select id from c),
    'status',(select status from c),
    'ovp',(select ovp_number from c),
    'total_payable',(select total_payable from c),
    'authorizations',count(*),
    'matched',count(*) filter(where match_status='coincidencia'),
    'differences',count(*) filter(where match_status='diferencia'),
    'not_found',count(*) filter(where match_status='no_encontrada'),
    'objected_total',coalesce(sum(objected_amount),0),
    'paid_total',coalesce(sum(paid_amount),0),
    'claimed_total',coalesce(sum(claimed_amount),0),
    'ready_to_apply',count(*)>0 and count(*) filter(where match_status in ('diferencia','no_encontrada'))=0
  )
  from a
$$;

revoke all on function public.senasa_certificate_reconciliation(uuid) from public,anon;
grant execute on function public.senasa_certificate_reconciliation(uuid) to authenticated;
