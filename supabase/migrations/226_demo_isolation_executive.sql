-- 226 · Métricas ejecutivas reales (excluye organizaciones DEMO)
begin;

create or replace view public.v_mrr_real as
select
  o.operator_id,
  coalesce(sum(fr.fixed_amount) filter (
    where fr.basis='cuota_mensual'
      and fr.valid_during @> current_date
      and o.status in ('activo','incorporacion')
  ),0::numeric) as fixed_monthly,
  coalesce((
    select round(sum(f.amount)/2::numeric,2)
    from public.sofa_fees f
    join public.organizations o2 on o2.id=f.organization_id
    where o2.operator_id=o.operator_id
      and coalesce(o2.is_demo,false)=false
      and f.source_type='pago'
      and f.calculated_at>=now()-interval '60 days'
  ),0::numeric) as success_monthly_avg,
  count(distinct o.id) filter (
    where o.status in ('activo','incorporacion')
  ) as active_clients
from public.organizations o
left join public.fee_rules fr on fr.organization_id=o.id
where o.kind='client'
  and coalesce(o.is_demo,false)=false
group by o.operator_id;

create or replace view public.v_growth_monthly_real as
with months as (
  select generate_series(
    date_trunc('month',current_date)-interval '11 months',
    date_trunc('month',current_date),
    interval '1 month'
  )::date as month
)
select
  m.month,
  coalesce((
    select sum(f.amount)
    from public.sofa_fees f
    join public.organizations o on o.id=f.organization_id
    where f.period=m.month and coalesce(o.is_demo,false)=false
  ),0)::numeric(14,2) as fees,
  coalesce((
    select sum(f.amount)
    from public.sofa_fees f
    join public.organizations o on o.id=f.organization_id
    where f.period=m.month and f.source_type='cuota' and coalesce(o.is_demo,false)=false
  ),0)::numeric(14,2) as fees_fixed,
  coalesce((
    select sum(f.amount)
    from public.sofa_fees f
    join public.organizations o on o.id=f.organization_id
    where f.period=m.month and f.source_type<>'cuota' and coalesce(o.is_demo,false)=false
  ),0)::numeric(14,2) as fees_variable,
  (
    select count(*)
    from public.organizations o
    where o.kind='client'
      and coalesce(o.is_demo,false)=false
      and date_trunc('month',o.started_on)=m.month
  ) as new_clients,
  (
    select count(*) from public.leak_diagnostics d
    where date_trunc('month',d.created_at)::date=m.month
  ) as diagnostics,
  (
    select count(*) from public.leads l
    where date_trunc('month',l.created_at)::date=m.month
  ) as new_leads
from months m;

grant select on public.v_mrr_real to authenticated;
grant select on public.v_growth_monthly_real to authenticated;

commit;
