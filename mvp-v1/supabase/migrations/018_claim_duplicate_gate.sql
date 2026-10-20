-- SOFA · Detección y control de reclamaciones duplicadas antes de radicar
create table if not exists public.claim_duplicate_resolutions (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  line_a uuid not null references public.service_lines(id) on delete cascade,
  line_b uuid not null references public.service_lines(id) on delete cascade,
  resolution text not null check(resolution in ('distinct_valid','duplicate_confirmed')),
  reason text not null,
  resolved_by uuid default auth.uid(),
  resolved_at timestamptz not null default now(),
  check(line_a <> line_b)
);

create unique index if not exists claim_duplicate_resolutions_pair_uq
on public.claim_duplicate_resolutions(
  organization_id,
  least(line_a::text,line_b::text),
  greatest(line_a::text,line_b::text)
);

alter table public.claim_duplicate_resolutions enable row level security;
drop policy if exists duplicate_resolution_read on public.claim_duplicate_resolutions;
create policy duplicate_resolution_read on public.claim_duplicate_resolutions
for select to authenticated using (organization_id in (select app.visible_org_ids()));

drop policy if exists duplicate_resolution_manage on public.claim_duplicate_resolutions;
create policy duplicate_resolution_manage on public.claim_duplicate_resolutions
for all to authenticated
using (app.can(organization_id,array['super_admin','admin','operations','billing','auditor']))
with check (app.can(organization_id,array['super_admin','admin','operations','billing','auditor']));

grant select,insert,update,delete on public.claim_duplicate_resolutions to authenticated;

create or replace function public.claim_duplicate_candidates(
  p_lines uuid[] default null,
  p_submission uuid default null
)
returns table(
  line_a uuid,line_b uuid,organization_id uuid,ars_id uuid,
  folio_a text,folio_b text,patient_a text,patient_b text,nss text,
  service_date date,authorization_date date,
  authorization_a text,authorization_b text,
  procedure_a uuid,procedure_b uuid,service_a text,service_b text,
  amount_a numeric,amount_b numeric,status_a text,status_b text,
  resolution text,resolution_reason text,suggested_solution text,risk_level text
)
language sql stable security definer set search_path=''
as $$
  with pairs as (
    select
      a.id line_a,b.id line_b,a.organization_id,sa.ars_id,
      a.claim_folio folio_a,b.claim_folio folio_b,
      a.patient_name patient_a,b.patient_name patient_b,
      trim(a.member_number) nss,a.service_date,a.authorization_date,
      a.authorization_number authorization_a,b.authorization_number authorization_b,
      a.procedure_id procedure_a,b.procedure_id procedure_b,
      coalesce(a.service_name_snapshot,pa.description) service_a,
      coalesce(b.service_name_snapshot,pb.description) service_b,
      coalesce(a.amount,a.unit_amount*a.quantity) amount_a,
      coalesce(b.amount,b.unit_amount*b.quantity) amount_b,
      a.claim_status status_a,b.claim_status status_b,
      r.resolution,r.reason resolution_reason
    from public.service_lines a
    join public.service_lines b
      on a.organization_id=b.organization_id
     and a.id::text < b.id::text
     and nullif(trim(a.member_number),'') is not null
     and lower(trim(a.member_number))=lower(trim(b.member_number))
     and a.service_date=b.service_date
     and a.authorization_date is not null
     and a.authorization_date=b.authorization_date
    join public.submissions sa on sa.id=a.submission_id
    join public.submissions sb on sb.id=b.submission_id and sb.ars_id=sa.ars_id
    left join public.procedures pa on pa.id=a.procedure_id
    left join public.procedures pb on pb.id=b.procedure_id
    left join public.claim_duplicate_resolutions r
      on r.organization_id=a.organization_id
     and least(r.line_a::text,r.line_b::text)=least(a.id::text,b.id::text)
     and greatest(r.line_a::text,r.line_b::text)=greatest(a.id::text,b.id::text)
    where a.organization_id in (select app.visible_org_ids())
      and (p_lines is null or a.id=any(p_lines) or b.id=any(p_lines))
      and (p_submission is null or a.submission_id=p_submission or b.submission_id=p_submission)
      and a.claim_status<>'cerrada' and b.claim_status<>'cerrada'
  )
  select
    p.*,
    case
      when p.resolution='distinct_valid' then 'Revisado: ambas reclamaciones fueron confirmadas como válidas.'
      when p.resolution='duplicate_confirmed' then 'Duplicado confirmado: elimine o corrija el registro repetido antes de radicar.'
      when coalesce(p.authorization_a,'')<>'' and lower(trim(p.authorization_a))=lower(trim(coalesce(p.authorization_b,''))) and p.procedure_a=p.procedure_b
        then 'Duplicado fuerte: misma NSS, fechas, autorización y servicio. Conserve la reclamación correcta y elimine/corrija la repetida.'
      when coalesce(p.authorization_a,'')<>'' and lower(trim(p.authorization_a))=lower(trim(coalesce(p.authorization_b,'')))
        then 'Misma autorización con servicios distintos. Verifique si la autorización cubre ambos servicios; si es correcto, marque ambas como válidas.'
      when p.procedure_a=p.procedure_b
        then 'Mismo NSS, fecha de servicio, fecha de autorización y servicio. Compare autorización y monto; probablemente debe conservarse una sola.'
      else 'Coinciden NSS y fechas, pero los servicios difieren. Revise la documentación y, si ambos corresponden, confirme ambas como válidas.'
    end::text,
    case
      when p.resolution='distinct_valid' then 'resuelto'
      when p.resolution='duplicate_confirmed' then 'alto'
      when coalesce(p.authorization_a,'')<>'' and lower(trim(p.authorization_a))=lower(trim(coalesce(p.authorization_b,''))) and p.procedure_a=p.procedure_b then 'alto'
      when p.procedure_a=p.procedure_b then 'alto'
      else 'medio'
    end::text
  from pairs p
  order by p.service_date desc,p.nss,p.folio_a,p.folio_b
$$;

revoke all on function public.claim_duplicate_candidates(uuid[],uuid) from public,anon;
grant execute on function public.claim_duplicate_candidates(uuid[],uuid) to authenticated;

create or replace function public.resolve_claim_duplicate(
  p_line_a uuid,p_line_b uuid,p_resolution text,p_reason text
)
returns bigint
language plpgsql security definer set search_path=''
as $$
declare v_org uuid; v_id bigint;
begin
  if p_line_a=p_line_b then raise exception 'Seleccione dos reclamaciones distintas.' using errcode='22023'; end if;
  if p_resolution not in ('distinct_valid','duplicate_confirmed') then raise exception 'Resolución inválida.' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,'')))<8 then raise exception 'Indique el motivo de la decisión (mínimo 8 caracteres).' using errcode='22023'; end if;

  select a.organization_id into v_org
  from public.service_lines a join public.service_lines b on b.id=p_line_b and b.organization_id=a.organization_id
  where a.id=p_line_a;
  if v_org is null then raise exception 'Las reclamaciones no pertenecen al mismo cliente.' using errcode='23514'; end if;
  if not app.can(v_org,array['super_admin','admin','operations','billing','auditor']) then raise exception 'Sin permiso para resolver duplicados.' using errcode='42501'; end if;

  insert into public.claim_duplicate_resolutions(organization_id,line_a,line_b,resolution,reason,resolved_by,resolved_at)
  values(v_org,p_line_a,p_line_b,p_resolution,trim(p_reason),auth.uid(),now())
  on conflict(organization_id,(least(line_a::text,line_b::text)),(greatest(line_a::text,line_b::text)))
  do update set resolution=excluded.resolution,reason=excluded.reason,resolved_by=auth.uid(),resolved_at=now()
  returning id into v_id;

  insert into public.audit_log(user_id,organization_id,table_name,record_id,operation,new_values)
  values(auth.uid(),v_org,'claim_duplicate_resolutions',v_id::text,'RESOLUCION_POSIBLE_DUPLICADO',
    jsonb_build_object('line_a',p_line_a,'line_b',p_line_b,'resolution',p_resolution,'reason',trim(p_reason)));
  return v_id;
end
$$;

revoke all on function public.resolve_claim_duplicate(uuid,uuid,text,text) from public,anon;
grant execute on function public.resolve_claim_duplicate(uuid,uuid,text,text) to authenticated;

create or replace function public.submission_duplicate_gate(p_submission uuid)
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare v_org uuid; v_rows jsonb; v_unresolved int; v_confirmed int; v_resolved int;
begin
  select organization_id into v_org from public.submissions where id=p_submission;
  if v_org is null then raise exception 'Radicación no encontrada.' using errcode='P0002'; end if;
  if not app.can(v_org,array['super_admin','admin','operations','billing','auditor','client']) then raise exception 'Sin acceso a esta radicación.' using errcode='42501'; end if;

  select
    coalesce(jsonb_agg(to_jsonb(x) order by x.risk_level desc,x.folio_a,x.folio_b),'[]'::jsonb),
    count(*) filter(where x.resolution is null),
    count(*) filter(where x.resolution='duplicate_confirmed'),
    count(*) filter(where x.resolution='distinct_valid')
  into v_rows,v_unresolved,v_confirmed,v_resolved
  from public.claim_duplicate_candidates(null,p_submission) x;

  return jsonb_build_object(
    'ok',coalesce(v_unresolved,0)=0 and coalesce(v_confirmed,0)=0,
    'unresolved',coalesce(v_unresolved,0),
    'confirmed_duplicates',coalesce(v_confirmed,0),
    'resolved_valid',coalesce(v_resolved,0),
    'candidates',coalesce(v_rows,'[]'::jsonb)
  );
end
$$;

revoke all on function public.submission_duplicate_gate(uuid) from public,anon;
grant execute on function public.submission_duplicate_gate(uuid) to authenticated;

create or replace function public.enforce_submission_duplicate_gate()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare v jsonb;
begin
  if new.status='radicada' and old.status is distinct from new.status then
    v:=public.submission_duplicate_gate(new.id);
    if not coalesce((v->>'ok')::boolean,false) then
      raise exception 'No se puede radicar: hay % posible(s) duplicado(s) sin resolver y % duplicado(s) confirmado(s). Revise Posibles duplicados antes de radicar.',
        v->>'unresolved',v->>'confirmed_duplicates'
        using errcode='23514',hint='duplicados_pendientes';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists trg_submission_duplicate_gate on public.submissions;
create trigger trg_submission_duplicate_gate
before update of status on public.submissions
for each row execute function public.enforce_submission_duplicate_gate();
