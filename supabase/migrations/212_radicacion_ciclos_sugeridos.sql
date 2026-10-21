-- 212 · Radicaciones por ciclos sugeridos + reclamaciones desacopladas
-- Fase compatible + fase estructural. No elimina datos ni modifica radicaciones ya creadas.

begin;

-- 1) La reclamación conserva médico/ARS aunque todavía no pertenezca a una radicación.
alter table public.service_lines add column if not exists provider_id uuid;
alter table public.service_lines add column if not exists ars_id uuid;

update public.service_lines l
set provider_id = s.provider_id,
    ars_id = s.ars_id
from public.submissions s
where s.id = l.submission_id
  and (l.provider_id is null or l.ars_id is null);

do $$
begin
  if not exists (select 1 from pg_constraint where conname='service_lines_provider_id_fkey') then
    alter table public.service_lines
      add constraint service_lines_provider_id_fkey foreign key (provider_id) references public.providers(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='service_lines_ars_id_fkey') then
    alter table public.service_lines
      add constraint service_lines_ars_id_fkey foreign key (ars_id) references public.ars(id) on delete restrict;
  end if;
end $$;

create index if not exists service_lines_cycle_idx
  on public.service_lines (organization_id, provider_id, ars_id, service_date)
  where submission_id is null;
create index if not exists service_lines_unassigned_status_idx
  on public.service_lines (claim_status, service_date)
  where submission_id is null;

-- Estructural: una reclamación puede existir antes de ser asignada a un lote.
alter table public.service_lines alter column submission_id drop not null;

-- 2) v_claims sigue mostrando las reclamaciones históricas y también las aún no asignadas.
create or replace view public.v_claims as
select l.id,
    l.claim_folio as folio,
    l.organization_id,
    o.legal_name as client_name,
    coalesce(l.provider_id, s.provider_id) as provider_id,
    pr.full_name as provider_name,
    coalesce(l.ars_id, s.ars_id) as ars_id,
    a.name as ars_name,
    l.submission_id,
    s.folio as submission_folio,
    s.status as submission_status,
    coalesce(s.period, date_trunc('month', l.service_date)::date) as period,
    l.service_date,
    l.patient_name,
    l.patient_doc,
    l.member_number,
    l.authorization_number,
    l.care_mode,
    l.clinic_name,
    l.procedure_id,
    coalesce(l.service_name_snapshot, p.description) as service_name,
    p.internal_code,
    l.simon_code_snapshot as simon,
    l.cups_code_snapshot as cups,
    l.quantity,
    l.unit_amount,
    l.tariff_amount,
    l.amount as claimed,
    l.contracted,
    l.amount_ok,
    l.contract_ref_snapshot as contract_ref,
    l.tariff_valid_from,
    l.tariff_valid_to,
    l.contract_override_reason,
    l.claim_status,
    cs.name as status_name,
    cs.stage,
    l.status_changed_at,
    l.location_code,
    loc.name as location_name,
    l.custodian_id,
    coalesce(l.custodian_label, cp.full_name) as custodian_name,
    (select d.status from public.tariff_discrepancies d
      where d.service_line_id=l.id order by d.created_at desc limit 1) as discrepancy_status,
    app.claim_paid_visible(l.id) as paid,
    coalesce((select sum(gi.amount) from public.glosa_items gi where gi.service_line_id=l.id),0::numeric) as glosado,
    coalesce((select sum(gi.accepted_amount) from public.glosa_items gi where gi.service_line_id=l.id),0::numeric) as glosa_accepted,
    coalesce((select sum(gi.recovered_amount) from public.glosa_items gi where gi.service_line_id=l.id),0::numeric) as recovered,
    l.amount - coalesce((select sum(gi.accepted_amount) from public.glosa_items gi where gi.service_line_id=l.id),0::numeric) as recognized,
    l.amount - app.claim_paid_visible(l.id)
      - coalesce((select sum(gi.accepted_amount) from public.glosa_items gi where gi.service_line_id=l.id),0::numeric) as balance,
    (select gr.name
       from public.glosa_items gi join public.glosa_reasons gr on gr.code=gi.reason_code
      where gi.service_line_id=l.id order by gi.created_at desc limit 1) as glosa_reason,
    (select max(py.paid_on)
       from public.payment_line_allocations pla join public.payments py on py.id=pla.payment_id
      where pla.service_line_id=l.id and pla.superseded_at is null and pla.amount>0) as last_paid_on,
    (select string_agg(distinct py.reference, ', ')
       from public.payment_line_allocations pla join public.payments py on py.id=pla.payment_id
      where pla.service_line_id=l.id and pla.superseded_at is null and pla.amount>0) as payment_refs,
    (select h.comment from public.claim_status_history h
      where h.service_line_id=l.id order by h.changed_at desc,h.id desc limit 1) as last_action,
    (select h.changed_at from public.claim_status_history h
      where h.service_line_id=l.id order by h.changed_at desc,h.id desc limit 1) as last_action_at,
    case l.claim_status
      when 'pendiente_configuracion' then 'Configurar el tarifario contractual del médico o autorizar la excepción'
      when 'capturada' then 'Completar documentos y programar el retiro'
      when 'pendiente_retiro' then 'Retirar en el consultorio'
      when 'retirada' then 'Entregar a auditoría para validar'
      when 'en_validacion' then 'Auditar el expediente'
      when 'con_inconsistencia' then 'Corregir lo señalado por auditoría'
      when 'validada' then 'Disponible para el ciclo sugerido de radicación'
      when 'lista_para_radicar' then 'Lista para incluir en una radicación'
      when 'radicada' then 'Dar seguimiento a la ARS'
      when 'en_proceso_ars' then 'Esperar pago o glosa; registrar la respuesta'
      when 'devuelta' then 'Corregir y volver a validar'
      when 'pago_parcial' then 'Conciliar la diferencia o gestionar la glosa'
      when 'glosada' then 'Responder la glosa dentro del plazo'
      when 'pagada' then 'Conciliar y cerrar'
      else '—'
    end as next_step,
    l.created_at,
    l.created_by,
    cb.full_name as created_by_name,
    l.updated_at,
    l.updated_by,
    app.claim_dossier_ok(l.id) as dossier_ok,
    cardinality(app.claim_missing_docs(l.id)) as dossier_missing,
    l.authorization_date
from public.service_lines l
left join public.submissions s on s.id=l.submission_id
left join public.organizations o on o.id=l.organization_id
left join public.providers pr on pr.id=coalesce(l.provider_id,s.provider_id)
left join public.ars a on a.id=coalesce(l.ars_id,s.ars_id)
left join public.procedures p on p.id=l.procedure_id
left join public.claim_statuses cs on cs.code=l.claim_status
left join public.claim_locations loc on loc.code=l.location_code
left join public.profiles cp on cp.id=l.custodian_id
left join public.profiles cb on cb.id=l.created_by;

-- 3) Bandeja de ciclos: sólo reclamaciones todavía no asignadas a una radicación.
create or replace view public.v_claim_cycle_suggestions
with (security_invoker=true) as
select
  l.organization_id,
  l.provider_id,
  pr.full_name as provider_name,
  l.ars_id,
  a.name as ars_name,
  date_trunc('month',l.service_date)::date as period,
  count(*)::int as claims,
  count(*) filter (where l.claim_status in ('validada','lista_para_radicar'))::int as ready,
  count(*) filter (where l.claim_status not in ('validada','lista_para_radicar'))::int as pending,
  coalesce(sum(l.amount),0)::numeric as claimed,
  coalesce(sum(l.amount) filter (where l.claim_status in ('validada','lista_para_radicar')),0)::numeric as ready_amount,
  min(l.service_date) as first_service_date,
  max(l.service_date) as last_service_date,
  (date_trunc('month',l.service_date)::date < date_trunc('month',current_date)::date) as prior_cycle
from public.service_lines l
join public.providers pr on pr.id=l.provider_id
join public.ars a on a.id=l.ars_id
where l.submission_id is null
group by l.organization_id,l.provider_id,pr.full_name,l.ars_id,a.name,date_trunc('month',l.service_date)::date;

-- 4) Captura nueva: reutiliza todas las validaciones existentes y, al final,
-- deja la reclamación sin lote. No cambia el contrato actual de capture_claim.
create or replace function public.capture_claim_unassigned(
  p_provider uuid, p_ars uuid, p_procedure uuid, p_service_date date,
  p_patient_name text, p_member text, p_authorization text default null,
  p_patient_doc text default null, p_amount numeric default null,
  p_quantity numeric default 1, p_care_mode text default null,
  p_clinic text default null, p_notes text default null,
  p_discrepancy_reason text default null, p_not_contracted text default 'bloquear',
  p_exception_reason text default null, p_allow_duplicate boolean default false,
  p_center uuid default null, p_diagnosis text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  r jsonb; v_line uuid; v_sub uuid;
begin
  r := public.capture_claim_dx(
    p_provider,p_ars,p_procedure,p_service_date,p_patient_name,p_member,p_authorization,
    p_patient_doc,p_amount,p_quantity,p_care_mode,p_clinic,p_notes,p_discrepancy_reason,
    p_not_contracted,p_exception_reason,p_allow_duplicate,p_center,p_diagnosis
  );
  v_line := (r->>'id')::uuid;
  v_sub := (r->>'submission_id')::uuid;

  perform set_config('app.claim_change','on',true);
  update public.service_lines
     set provider_id=p_provider, ars_id=p_ars, submission_id=null, updated_by=auth.uid(), updated_at=now()
   where id=v_line;
  perform set_config('app.claim_change','',true);

  -- El lote temporal creado por el flujo legado se elimina sólo si quedó vacío,
  -- sigue en borrador y fue creado por captura rápida.
  delete from public.submissions s
   where s.id=v_sub
     and s.status='borrador'
     and s.notes='Creada por captura rápida'
     and not exists (select 1 from public.service_lines l where l.submission_id=s.id);

  return (r - 'submission_id' - 'submission_folio')
         || jsonb_build_object('submission_id',null,'submission_folio',null,'cycle_period',date_trunc('month',p_service_date)::date);
end $$;

grant execute on function public.capture_claim_unassigned(uuid,uuid,uuid,date,text,text,text,text,numeric,numeric,text,text,text,text,text,text,boolean,uuid,text)
to authenticated;

-- 5) Convierte una selección del ciclo en borrador de radicación.
create or replace function public.create_submission_from_claims(
  p_claims uuid[], p_notes text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  v_org uuid; v_provider uuid; v_ars uuid; v_period date;
  v_id uuid := gen_random_uuid(); v_seq smallint; v_parent uuid; v_role text;
  v_count int; v_valid int;
begin
  if p_claims is null or cardinality(p_claims)=0 then
    raise exception 'Seleccione al menos una reclamación' using errcode='22023';
  end if;

  select count(*), count(distinct organization_id),
         min(organization_id), min(provider_id), min(ars_id),
         min(date_trunc('month',service_date)::date)
    into v_count, v_valid, v_org, v_provider, v_ars, v_period
    from public.service_lines
   where id=any(p_claims)
     and submission_id is null;

  if v_count <> cardinality(p_claims) then
    raise exception 'Una o más reclamaciones ya pertenecen a otra radicación o no existen' using errcode='23514';
  end if;
  if v_valid <> 1
     or (select count(distinct provider_id) from public.service_lines where id=any(p_claims)) <> 1
     or (select count(distinct ars_id) from public.service_lines where id=any(p_claims)) <> 1
     or (select count(distinct date_trunc('month',service_date)::date) from public.service_lines where id=any(p_claims)) <> 1 then
    raise exception 'Las reclamaciones seleccionadas deben pertenecer al mismo cliente, médico, ARS y mes de servicio' using errcode='23514';
  end if;

  if v_provider is null or v_ars is null then
    raise exception 'Las reclamaciones seleccionadas no tienen médico/ARS estructural asignado' using errcode='23514';
  end if;

  v_role := app.claim_access_role(v_org,v_provider);
  if v_role is null or v_role not in ('super_admin','admin','billing','assistant','operations','client') then
    raise exception 'Su usuario no puede preparar esta radicación' using errcode='42501';
  end if;

  if exists (
    select 1 from public.service_lines
     where id=any(p_claims)
       and claim_status not in ('validada','lista_para_radicar')
  ) then
    raise exception 'La selección contiene reclamaciones que todavía no están listas' using errcode='23514';
  end if;

  select coalesce(max(sequence),0)+1 into v_seq
    from public.submissions
   where provider_id=v_provider and ars_id=v_ars and period=v_period;
  if v_seq>99 then raise exception 'Demasiadas radicaciones para este ciclo' using errcode='23514'; end if;

  select id into v_parent
    from public.submissions
   where provider_id=v_provider and ars_id=v_ars and period=v_period
     and is_complementary=false
     and (submitted_on is not null or status in ('radicada','en_auditoria_ars','cerrada','rechazada'))
   order by sequence asc limit 1;

  insert into public.submissions(
    id,organization_id,provider_id,ars_id,period,sequence,status,notes,created_by,
    parent_submission_id,is_complementary
  ) values (
    v_id,v_org,v_provider,v_ars,v_period,v_seq,'borrador',
    coalesce(nullif(trim(p_notes),''),'Creada desde ciclo sugerido'),
    auth.uid(),v_parent,(v_parent is not null)
  );

  perform set_config('app.claim_change','on',true);
  update public.service_lines
     set submission_id=v_id, updated_by=auth.uid(), updated_at=now()
   where id=any(p_claims) and submission_id is null;
  perform set_config('app.claim_change','',true);

  return v_id;
end $$;

grant execute on function public.create_submission_from_claims(uuid[],text) to authenticated;

commit;
