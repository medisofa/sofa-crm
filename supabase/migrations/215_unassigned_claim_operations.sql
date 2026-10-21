-- 215 · Operación previa a radicación sin submission_id
begin;

create or replace function app.claim_paid_visible(p_line uuid)
returns numeric
language plpgsql stable security definer set search_path=''
as $$
declare v_org uuid; v_prov uuid; v_rol text;
begin
  select l.organization_id,coalesce(l.provider_id,s.provider_id)
    into v_org,v_prov
    from public.service_lines l
    left join public.submissions s on s.id=l.submission_id
   where l.id=p_line;
  if not found then return null; end if;
  v_rol:=app.claim_access_role(v_org,v_prov);
  if v_rol is null or v_rol='capturer' then return null; end if;
  return app.claim_paid(p_line);
end $$;

create or replace function public.patient_lookup(p_provider uuid,p_q text)
returns table(patient_name text,member_number text,patient_doc text,last_service date,ars_id uuid)
language sql stable security definer set search_path=''
as $$
  select distinct on (l.member_number)
         l.patient_name,l.member_number,l.patient_doc,l.service_date,coalesce(l.ars_id,s.ars_id)
    from public.service_lines l
    left join public.submissions s on s.id=l.submission_id
   where coalesce(l.provider_id,s.provider_id)=p_provider
     and app.claim_access_role(l.organization_id,coalesce(l.provider_id,s.provider_id)) is not null
     and length(trim(coalesce(p_q,'')))>=2
     and (
       l.member_number ilike trim(p_q)||'%'
       or l.patient_name ilike '%'||trim(p_q)||'%'
       or l.patient_doc ilike trim(p_q)||'%'
     )
   order by l.member_number,l.service_date desc
   limit 10
$$;

create or replace function public.create_pickup(p_provider uuid,p_lines uuid[],p_notes text default null)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare pr public.providers; v_role text; v_id uuid:=gen_random_uuid(); v_bad text; v_line uuid;
begin
  select * into pr from public.providers where id=p_provider;
  if not found then raise exception 'Médico no encontrado' using errcode='P0002'; end if;
  v_role:=app.role_for_org(pr.organization_id);
  if v_role is null or v_role not in ('super_admin','admin','billing','assistant','operations') then
    raise exception 'Solo el personal de SOFA programa retiros' using errcode='42501';
  end if;
  if p_lines is null or array_length(p_lines,1) is null then
    raise exception 'Seleccione las reclamaciones a retirar' using errcode='22023';
  end if;

  select string_agg(coalesce(l.claim_folio,'?'),', ') into v_bad
    from unnest(p_lines) x(id)
    left join public.service_lines l on l.id=x.id
    left join public.submissions s on s.id=l.submission_id
   where l.id is null
      or coalesce(l.provider_id,s.provider_id)<>p_provider
      or l.claim_status not in ('capturada','pendiente_retiro')
      or exists(
        select 1 from public.reception_items ri
        join public.receptions r on r.id=ri.reception_id
        where ri.service_line_id=l.id and r.status='borrador'
      );

  if v_bad is not null then
    raise exception 'No se pueden incluir en el retiro (otro médico, ya retiradas o en otro retiro abierto): %',v_bad using errcode='23514';
  end if;

  insert into public.receptions(id,organization_id,provider_id,received_on,channel,status,expected_count,notes)
  values(v_id,pr.organization_id,p_provider,current_date,'fisico','borrador',array_length(p_lines,1),nullif(trim(coalesce(p_notes,'')),''));

  insert into public.reception_items(reception_id,service_line_id,organization_id)
  select v_id,x.id,pr.organization_id from unnest(p_lines) x(id);

  foreach v_line in array p_lines loop
    if (select claim_status from public.service_lines where id=v_line)='capturada' then
      perform app.claim_set_status(v_line,'pendiente_retiro','Incluida en el retiro '||(select folio from public.receptions where id=v_id));
    end if;
  end loop;
  return v_id;
end $$;

create or replace function public.day_summary(p_provider uuid,p_date date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare r jsonb;
begin
  if not app.consultorio_access(p_provider,false) then raise exception 'Sin acceso a este médico' using errcode='42501'; end if;
  select jsonb_build_object(
    'date',p_date,
    'appointments',(select jsonb_build_object(
      'total',count(*),'atendida',count(*) filter(where status='atendida'),
      'no_asistio',count(*) filter(where status='no_asistio'),
      'cancelada',count(*) filter(where status='cancelada'),
      'pendiente',count(*) filter(where status in ('programada','confirmada','en_espera')),
      'ars',count(*) filter(where payer_type='ars' and status<>'cancelada'),
      'privado',count(*) filter(where payer_type='privado' and status<>'cancelada')
    ) from public.appointments where provider_id=p_provider and appointment_date=p_date),
    'ars_claims',(select jsonb_build_object('count',count(*),'claimed',coalesce(sum(l.amount),0))
      from public.service_lines l left join public.submissions s on s.id=l.submission_id
      where coalesce(l.provider_id,s.provider_id)=p_provider and l.service_date=p_date),
    'private',(select jsonb_build_object(
      'count',count(*) filter(where status<>'anulado'),
      'billed',coalesce(sum(amount) filter(where status<>'anulado'),0),
      'pending',coalesce(sum(amount) filter(where status='pendiente'),0),
      'voided',count(*) filter(where status='anulado')
    ) from public.private_charges where provider_id=p_provider and charge_date=p_date and charge_type='privado'),
    'copays',(select jsonb_build_object(
      'count',count(*) filter(where status<>'anulado'),
      'amount',coalesce(sum(amount) filter(where status<>'anulado'),0),
      'pending',coalesce(sum(amount) filter(where status='pendiente'),0)
    ) from public.private_charges where provider_id=p_provider and charge_date=p_date and charge_type in ('copago','diferencia')),
    'collected',(select jsonb_build_object(
      'efectivo',coalesce(sum(amount) filter(where payment_method='efectivo'),0),
      'tarjeta',coalesce(sum(amount) filter(where payment_method='tarjeta'),0),
      'transferencia',coalesce(sum(amount) filter(where payment_method='transferencia'),0),
      'cheque',coalesce(sum(amount) filter(where payment_method='cheque'),0),
      'total',coalesce(sum(amount),0)
    ) from public.private_charges where provider_id=p_provider and collected_on=p_date and status='cobrado'),
    'voided_collected',(select jsonb_build_object(
      'count',count(*),'amount',coalesce(sum(amount),0),
      'efectivo',coalesce(sum(amount) filter(where payment_method='efectivo'),0)
    ) from public.private_charges where provider_id=p_provider and collected_on=p_date and status='anulado'),
    'unregistered',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'time',a.appointment_time,'patient',a.patient_name,'payer',a.payer_type) order by a.appointment_time)
      from public.appointments a where a.provider_id=p_provider and a.appointment_date=p_date and a.status='en_espera'),'[]'::jsonb),
    'closing',(select to_jsonb(c)-'organization_id' from public.cash_closings c where c.provider_id=p_provider and c.closing_date=p_date)
  ) into r;
  return r;
end $$;

create or replace function public.claim_duplicate_candidates(p_ids uuid[] default null::uuid[],p_submission uuid default null::uuid)
returns table(
  line_id uuid,other_line_id uuid,folio text,other_folio text,patient_name text,other_patient_name text,
  member_number text,service_date date,authorization_date date,authorization_number text,other_authorization_number text,
  service_name text,other_service_name text,risk text,matched_fields text[],suggested_solution text,review_decision text,blocks_radicacion boolean
)
language sql stable security definer set search_path=''
as $$
with base as (
  select l.id,l.organization_id,l.submission_id,l.patient_name,l.member_number,l.service_date,
         l.authorization_date,l.authorization_number,l.procedure_id,
         coalesce(l.service_name_snapshot,p.description) service_name,
         l.claim_folio,l.claim_status,
         coalesce(l.ars_id,s.ars_id) ars_id,s.status submission_status
    from public.service_lines l
    left join public.submissions s on s.id=l.submission_id
    left join public.procedures p on p.id=l.procedure_id
   where l.organization_id in (select app.visible_org_ids())
     and l.member_number is not null and length(trim(l.member_number))>0
     and (p_ids is null or l.id=any(p_ids))
     and (p_submission is null or l.submission_id=p_submission)
), pairs as (
  select a.id,b.id,a.claim_folio,b.claim_folio,a.patient_name,b.patient_name,
         a.member_number,a.service_date,a.authorization_date,a.authorization_number,b.authorization_number,
         a.service_name,coalesce(b.service_name_snapshot,pb.description),
         case
           when a.authorization_date is not null and b.authorization_date=a.authorization_date
             and nullif(trim(a.authorization_number),'') is not null and b.authorization_number=a.authorization_number
             and b.procedure_id=a.procedure_id then 'critico'
           when a.authorization_date is not null and b.authorization_date=a.authorization_date then 'alto'
           when nullif(trim(a.authorization_number),'') is not null and b.authorization_number=a.authorization_number then 'alto'
           when b.procedure_id=a.procedure_id then 'medio'
           else 'bajo'
         end,
         array_remove(array[
           'NSS','Fecha servicio',
           case when a.authorization_date is not null and b.authorization_date=a.authorization_date then 'Fecha autorización' end,
           case when nullif(trim(a.authorization_number),'') is not null and b.authorization_number=a.authorization_number then 'No. autorización' end,
           case when b.procedure_id=a.procedure_id then 'Servicio' end
         ],null),
         case
           when a.authorization_date is not null and b.authorization_date=a.authorization_date
             and nullif(trim(a.authorization_number),'') is not null and b.authorization_number=a.authorization_number
             and b.procedure_id=a.procedure_id then 'Probable duplicado: misma persona, fechas, autorización y servicio. Conserve la reclamación correcta y retire/corrija la otra antes de radicar.'
           when a.authorization_date is not null and b.authorization_date=a.authorization_date then 'Mismo NSS, fecha de servicio y fecha de autorización. Verifique si ambos servicios son válidos.'
           when nullif(trim(a.authorization_number),'') is not null and b.authorization_number=a.authorization_number then 'Mismo NSS, fecha de servicio y número de autorización. Revise el expediente.'
           when b.procedure_id=a.procedure_id then 'Mismo NSS, fecha de servicio y servicio. Revise número/fecha de autorización.'
           else 'Revise manualmente antes de radicar.'
         end,
         r.decision
    from base a
    join public.service_lines b on b.organization_id=a.organization_id
      and b.id<>a.id and lower(trim(b.member_number))=lower(trim(a.member_number))
      and b.service_date=a.service_date
    left join public.submissions sb on sb.id=b.submission_id
    left join public.procedures pb on pb.id=b.procedure_id
    left join public.claim_duplicate_reviews r on r.line_a=least(a.id,b.id) and r.line_b=greatest(a.id,b.id)
   where coalesce(b.ars_id,sb.ars_id)=a.ars_id
     and b.claim_status not in ('cerrada','devuelta')
     and (sb.id is null or sb.status not in ('rechazada','cerrada'))
)
select *,
  (risk in ('critico','alto') and coalesce(review_decision,'') not in ('ambas_validas','dato_corregido','no_duplicado'))
from pairs
order by case risk when 'critico' then 1 when 'alto' then 2 when 'medio' then 3 else 4 end,
         service_date desc,line_id,other_line_id
$$;

commit;
