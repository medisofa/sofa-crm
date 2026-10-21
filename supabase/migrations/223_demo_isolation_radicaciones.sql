-- 223 · Aislamiento de organizaciones DEMO en vistas operativas de radicaciones
begin;

create or replace view public.v_submissions as
select
  b.id,
  b.organization_id,
  o.legal_name as client_name,
  b.provider_id,
  p.full_name as provider_name,
  b.ars_id,
  a.name as ars_name,
  s.plan_id,
  b.period,
  s.sequence,
  b.folio,
  s.status,
  st.name as status_name,
  b.display_status,
  coalesce(ds.name, st.name) as display_status_name,
  st.is_pre_submission,
  s.ncf,
  s.invoice_date,
  s.ars_receipt_number,
  b.submitted_on,
  s.notes,
  b.lines,
  b.claimed,
  b.paid,
  b.glosado,
  b.glosa_accepted,
  b.glosa_in_dispute,
  b.balance,
  b.payment_deadline,
  b.age_days,
  b.aging_bucket,
  coalesce((select d.pct from app.submission_docs(b.id) d(pct, complete_lines)), 0::numeric) as docs_pct,
  coalesce((select d.complete_lines from app.submission_docs(b.id) d(pct, complete_lines)), 0::bigint) as complete_lines,
  pac.status as provider_code_status,
  pac.code as provider_code,
  lv.passed as last_passed,
  lv.total as last_total,
  lv.critical_ok as last_critical_ok,
  lv.run_at as last_validated_at,
  s.created_at,
  s.updated_at,
  coalesce(o.is_demo,false) as is_demo
from public.v_submission_balance b
join public.submissions s on s.id=b.id
join public.organizations o on o.id=b.organization_id
join public.providers p on p.id=b.provider_id
join public.ars a on a.id=b.ars_id
join public.submission_statuses st on st.code=s.status
left join public.submission_statuses ds on ds.code=b.display_status
left join public.provider_ars_codes pac on pac.provider_id=s.provider_id and pac.ars_id=s.ars_id
left join lateral (
  select vr.passed,vr.total,vr.critical_ok,vr.run_at
  from public.validation_runs vr
  where vr.submission_id=s.id
  order by vr.run_at desc
  limit 1
) lv on true;

commit;
