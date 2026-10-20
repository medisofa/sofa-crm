-- SOFA · Detector preventivo de reclamaciones duplicadas
-- Clave solicitada: NSS + fecha de servicio + fecha de autorización.
-- No elimina ni fusiona automáticamente. Clasifica riesgo y propone una acción.

create index if not exists service_lines_duplicate_probe_idx
on public.service_lines (
  organization_id,
  (regexp_replace(lower(trim(coalesce(member_number,''))),'[^0-9a-z]','','g')),
  service_date,
  authorization_date
)
where nullif(trim(coalesce(member_number,'')),'') is not null
  and authorization_date is not null;

create table if not exists public.claim_duplicate_reviews (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  duplicate_key text not null,
  decision text not null check(decision in ('pendiente','duplicado_confirmado','servicios_distintos','corregido')),
  keep_line_id uuid references public.service_lines(id) on delete set null,
  notes text,
  reviewed_by uuid default auth.uid(),
  reviewed_at timestamptz not null default now(),
  unique(organization_id,duplicate_key)
);

alter table public.claim_duplicate_reviews enable row level security;
drop policy if exists claim_duplicate_reviews_read on public.claim_duplicate_reviews;
create policy claim_duplicate_reviews_read on public.claim_duplicate_reviews
for select to authenticated using (organization_id in (select app.visible_org_ids()));
drop policy if exists claim_duplicate_reviews_manage on public.claim_duplicate_reviews;
create policy claim_duplicate_reviews_manage on public.claim_duplicate_reviews
for all to authenticated
using (app.can(organization_id,array['super_admin','admin','operations','billing']))
with check (app.can(organization_id,array['super_admin','admin','operations','billing']));
grant select,insert,update on public.claim_duplicate_reviews to authenticated;

create or replace function public.claim_duplicate_candidates(
  p_submission uuid default null,
  p_org uuid default null
)
returns table(
  duplicate_key text,
  risk text,
  suggested_action text,
  group_count bigint,
  line_id uuid,
  claim_folio text,
  submission_id uuid,
  submission_folio text,
  organization_id uuid,
  provider_id uuid,
  ars_id uuid,
  patient_name text,
  member_number text,
  service_date date,
  authorization_date date,
  authorization_number text,
  procedure_id uuid,
  service_name text,
  amount numeric,
  claim_status text,
  reviewed_decision text
)
language sql
stable
security definer
set search_path=''
as $$
with base as (
  select
    sl.*,
    regexp_replace(lower(trim(coalesce(sl.member_number,''))),'[^0-9a-z]','','g') as member_key,
    md5(
      sl.organization_id::text || '|' ||
      regexp_replace(lower(trim(coalesce(sl.member_number,''))),'[^0-9a-z]','','g') || '|' ||
      sl.service_date::text || '|' || sl.authorization_date::text
    ) as dup_key
  from public.service_lines sl
  where nullif(trim(coalesce(sl.member_number,'')),'') is not null
    and sl.authorization_date is not null
    and sl.organization_id in (select app.visible_org_ids())
    and (p_org is null or sl.organization_id=p_org)
),
groups as (
  select
    b.organization_id,b.member_key,b.service_date,b.authorization_date,b.dup_key,
    count(*) as n,
    count(distinct nullif(trim(b.authorization_number),'')) as auth_n,
    count(distinct b.procedure_id) as proc_n,
    count(distinct round(coalesce(b.amount,b.unit_amount*b.quantity,0)::numeric,2)) as amount_n
  from base b
  group by b.organization_id,b.member_key,b.service_date,b.authorization_date,b.dup_key
  having count(*)>1
),
eligible as (
  select g.*
  from groups g
  where p_submission is null
     or exists(select 1 from base bx where bx.dup_key=g.dup_key and bx.submission_id=p_submission)
)
select
  e.dup_key,
  case
    when e.auth_n<=1 and e.proc_n=1 and e.amount_n=1 then 'alta'
    when e.proc_n=1 and e.amount_n=1 then 'media'
    else 'baja'
  end::text as risk,
  case
    when e.auth_n<=1 and e.proc_n=1 and e.amount_n=1
      then 'Posible duplicado real: conservar el registro correcto/más completo y retirar el repetido antes de radicar.'
    when e.proc_n=1 and e.amount_n=1
      then 'Mismo NSS, fechas, procedimiento y monto: revisar números de autorización y evidencia antes de radicar.'
    else
      'Coincidencia administrativa: confirmar si son servicios distintos del mismo paciente y fecha; no eliminar automáticamente.'
  end::text as suggested_action,
  e.n,
  b.id,
  b.claim_folio,
  b.submission_id,
  s.folio,
  b.organization_id,
  s.provider_id,
  s.ars_id,
  b.patient_name,
  b.member_number,
  b.service_date,
  b.authorization_date,
  b.authorization_number,
  b.procedure_id,
  coalesce(b.service_name_snapshot,p.description),
  coalesce(b.amount,b.unit_amount*b.quantity),
  b.claim_status,
  r.decision
from eligible e
join base b on b.dup_key=e.dup_key
join public.submissions s on s.id=b.submission_id
left join public.procedures p on p.id=b.procedure_id
left join public.claim_duplicate_reviews r on r.organization_id=e.organization_id and r.duplicate_key=e.dup_key
order by
  case when e.auth_n<=1 and e.proc_n=1 and e.amount_n=1 then 1 when e.proc_n=1 and e.amount_n=1 then 2 else 3 end,
  b.service_date desc,b.patient_name,b.claim_folio;
$$;

revoke all on function public.claim_duplicate_candidates(uuid,uuid) from public,anon;
grant execute on function public.claim_duplicate_candidates(uuid,uuid) to authenticated;

create or replace function public.review_claim_duplicate(
  p_key text,
  p_org uuid,
  p_decision text,
  p_keep uuid default null,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
begin
  if not app.can(p_org,array['super_admin','admin','operations','billing']) then
    raise exception 'Sin permiso para revisar duplicados.' using errcode='42501';
  end if;
  if p_decision not in ('pendiente','duplicado_confirmado','servicios_distintos','corregido') then
    raise exception 'Decisión inválida.' using errcode='22023';
  end if;
  if p_decision='duplicado_confirmado' and p_keep is null then
    raise exception 'Indique cuál reclamación se conservará.' using errcode='22023';
  end if;

  insert into public.claim_duplicate_reviews(organization_id,duplicate_key,decision,keep_line_id,notes,reviewed_by,reviewed_at)
  values(p_org,p_key,p_decision,p_keep,nullif(trim(p_notes),''),auth.uid(),now())
  on conflict(organization_id,duplicate_key) do update set
    decision=excluded.decision,keep_line_id=excluded.keep_line_id,notes=excluded.notes,
    reviewed_by=auth.uid(),reviewed_at=now();

  insert into public.audit_log(user_id,organization_id,table_name,record_id,operation,new_values)
  values(auth.uid(),p_org,'claim_duplicate_reviews',p_key,'REVISION_DUPLICADO_RECLAMACION',
    jsonb_build_object('decision',p_decision,'keep_line_id',p_keep,'notes',p_notes));
  return true;
end
$$;

revoke all on function public.review_claim_duplicate(text,uuid,text,uuid,text) from public,anon;
grant execute on function public.review_claim_duplicate(text,uuid,text,uuid,text) to authenticated;
