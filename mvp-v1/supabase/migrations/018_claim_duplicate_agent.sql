-- SOFA · Motor de posibles reclamaciones duplicadas antes de radicar
-- Señales principales solicitadas: NSS + fecha de servicio + fecha de autorización.
-- Nunca elimina automáticamente; propone solución y exige revisión humana.

create table if not exists public.claim_duplicate_reviews (
  id bigint generated always as identity primary key,
  line_a uuid not null references public.service_lines(id) on delete cascade,
  line_b uuid not null references public.service_lines(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  decision text not null check(decision in ('ambas_validas','duplicado_confirmado','dato_corregido','no_duplicado')),
  reason text not null,
  reviewed_by uuid not null default auth.uid(),
  reviewed_at timestamptz not null default now(),
  unique(line_a,line_b),
  check(line_a <> line_b)
);

alter table public.claim_duplicate_reviews enable row level security;
drop policy if exists claim_dup_reviews_read on public.claim_duplicate_reviews;
create policy claim_dup_reviews_read on public.claim_duplicate_reviews
for select to authenticated
using (organization_id in (select app.visible_org_ids()));

drop policy if exists claim_dup_reviews_manage on public.claim_duplicate_reviews;
create policy claim_dup_reviews_manage on public.claim_duplicate_reviews
for all to authenticated
using (app.can(organization_id,array['super_admin','admin','operations','billing']))
with check (app.can(organization_id,array['super_admin','admin','operations','billing']));

grant select,insert,update on public.claim_duplicate_reviews to authenticated;

create or replace function public.claim_duplicate_candidates(
  p_ids uuid[] default null,
  p_submission uuid default null
)
returns table(
  line_id uuid,
  other_line_id uuid,
  folio text,
  other_folio text,
  patient_name text,
  other_patient_name text,
  member_number text,
  service_date date,
  authorization_date date,
  authorization_number text,
  other_authorization_number text,
  service_name text,
  other_service_name text,
  risk text,
  matched_fields text[],
  suggested_solution text,
  review_decision text,
  blocks_radicacion boolean
)
language sql
stable
security definer
set search_path=''
as $$
with base as (
  select l.id,l.organization_id,l.submission_id,l.patient_name,l.member_number,l.service_date,
         l.authorization_date,l.authorization_number,l.procedure_id,
         coalesce(l.service_name_snapshot,p.description) service_name,
         l.claim_folio, l.claim_status,
         s.ars_id,s.status submission_status
  from public.service_lines l
  join public.submissions s on s.id=l.submission_id
  left join public.procedures p on p.id=l.procedure_id
  where l.organization_id in (select app.visible_org_ids())
    and l.member_number is not null and length(trim(l.member_number))>0
    and (p_ids is null or l.id=any(p_ids))
    and (p_submission is null or l.submission_id=p_submission)
),
pairs as (
  select
    a.id line_id,b.id other_line_id,
    a.claim_folio folio,b.claim_folio other_folio,
    a.patient_name,b.patient_name other_patient_name,
    a.member_number,a.service_date,a.authorization_date,
    a.authorization_number,b.authorization_number other_authorization_number,
    a.service_name,coalesce(b.service_name_snapshot,pb.description) other_service_name,
    case
      when a.authorization_date is not null
       and b.authorization_date=a.authorization_date
       and nullif(trim(a.authorization_number),'') is not null
       and b.authorization_number=a.authorization_number
       and b.procedure_id=a.procedure_id then 'critico'
      when a.authorization_date is not null
       and b.authorization_date=a.authorization_date then 'alto'
      when nullif(trim(a.authorization_number),'') is not null
       and b.authorization_number=a.authorization_number then 'alto'
      when b.procedure_id=a.procedure_id then 'medio'
      else 'bajo'
    end risk,
    array_remove(array[
      'NSS',
      'Fecha servicio',
      case when a.authorization_date is not null and b.authorization_date=a.authorization_date then 'Fecha autorización' end,
      case when nullif(trim(a.authorization_number),'') is not null and b.authorization_number=a.authorization_number then 'No. autorización' end,
      case when b.procedure_id=a.procedure_id then 'Servicio' end
    ],null) matched_fields,
    case
      when a.authorization_date is not null and b.authorization_date=a.authorization_date
       and nullif(trim(a.authorization_number),'') is not null and b.authorization_number=a.authorization_number
       and b.procedure_id=a.procedure_id
        then 'Probable duplicado: misma persona, fechas, autorización y servicio. Conserve la reclamación correcta y retire/corrija la otra antes de radicar.'
      when a.authorization_date is not null and b.authorization_date=a.authorization_date
        then 'Mismo NSS, fecha de servicio y fecha de autorización. Verifique si son servicios distintos realmente autorizados. Si ambos son válidos, márquelos como "Ambas válidas".'
      when nullif(trim(a.authorization_number),'') is not null and b.authorization_number=a.authorization_number
        then 'Mismo NSS, fecha de servicio y número de autorización. Compare servicio y expediente; corrija el dato digitado o conserve solo la reclamación correcta.'
      when b.procedure_id=a.procedure_id
        then 'Mismo NSS, fecha de servicio y servicio. Revise número/fecha de autorización; puede ser duplicado de captura o dos autorizaciones legítimas.'
      else 'Revise manualmente antes de radicar.'
    end suggested_solution,
    r.decision review_decision
  from base a
  join public.service_lines b on b.organization_id=a.organization_id
    and b.id<>a.id
    and lower(trim(b.member_number))=lower(trim(a.member_number))
    and b.service_date=a.service_date
  join public.submissions sb on sb.id=b.submission_id and sb.ars_id=a.ars_id
  left join public.procedures pb on pb.id=b.procedure_id
  left join public.claim_duplicate_reviews r
    on r.line_a=least(a.id,b.id) and r.line_b=greatest(a.id,b.id)
  where b.claim_status not in ('cerrada','devuelta')
    and sb.status not in ('rechazada','cerrada')
)
select *,
  (risk in ('critico','alto') and coalesce(review_decision,'') not in ('ambas_validas','dato_corregido','no_duplicado')) blocks_radicacion
from pairs
order by
  case risk when 'critico' then 1 when 'alto' then 2 when 'medio' then 3 else 4 end,
  service_date desc, line_id, other_line_id
$$;

revoke all on function public.claim_duplicate_candidates(uuid[],uuid) from public,anon;
grant execute on function public.claim_duplicate_candidates(uuid[],uuid) to authenticated;

create or replace function public.review_claim_duplicate(
  p_line_a uuid,
  p_line_b uuid,
  p_decision text,
  p_reason text
)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare
  v_a uuid:=least(p_line_a,p_line_b);
  v_b uuid:=greatest(p_line_a,p_line_b);
  v_org uuid;
  v_id bigint;
begin
  if p_decision not in ('ambas_validas','duplicado_confirmado','dato_corregido','no_duplicado') then
    raise exception 'Decisión inválida.' using errcode='22023';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then
    raise exception 'Indique el motivo de la decisión (mínimo 5 caracteres).' using errcode='22023';
  end if;

  select a.organization_id into v_org
  from public.service_lines a join public.service_lines b on b.id=v_b
  where a.id=v_a and b.organization_id=a.organization_id;

  if v_org is null or not app.can(v_org,array['super_admin','admin','operations','billing']) then
    raise exception 'Sin permiso para revisar este posible duplicado.' using errcode='42501';
  end if;

  insert into public.claim_duplicate_reviews(line_a,line_b,organization_id,decision,reason,reviewed_by,reviewed_at)
  values(v_a,v_b,v_org,p_decision,trim(p_reason),auth.uid(),now())
  on conflict(line_a,line_b) do update set
    decision=excluded.decision,reason=excluded.reason,reviewed_by=auth.uid(),reviewed_at=now()
  returning id into v_id;

  insert into public.audit_log(user_id,organization_id,table_name,record_id,operation,new_values)
  values(auth.uid(),v_org,'claim_duplicate_reviews',v_id::text,'REVISION_POSIBLE_DUPLICADO',
    jsonb_build_object('line_a',v_a,'line_b',v_b,'decision',p_decision,'reason',trim(p_reason)));

  return v_id;
end
$$;

revoke all on function public.review_claim_duplicate(uuid,uuid,text,text) from public,anon;
grant execute on function public.review_claim_duplicate(uuid,uuid,text,text) to authenticated;

create or replace function app.submission_has_blocking_duplicates(p_submission uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1 from public.claim_duplicate_candidates(null,p_submission)
    where blocks_radicacion
  )
$$;

revoke all on function app.submission_has_blocking_duplicates(uuid) from public,anon;
grant execute on function app.submission_has_blocking_duplicates(uuid) to authenticated;

create or replace function app.guard_submission_duplicate_status()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.status in ('lista_para_radicar','radicada') and new.status is distinct from old.status then
    if app.submission_has_blocking_duplicates(new.id) then
      raise exception 'La radicación contiene posibles duplicados de alto riesgo sin resolver. Revise NSS, fecha de servicio y fecha/autorización antes de continuar.' using errcode='23505';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists trg_guard_submission_duplicates on public.submissions;
create trigger trg_guard_submission_duplicates
before update of status on public.submissions
for each row execute function app.guard_submission_duplicate_status();
