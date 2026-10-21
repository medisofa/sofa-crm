-- 222 · Integridad y onboarding de Documento D por ARS
begin;

create or replace function public.link_client_document_ars(
  p_document uuid,
  p_ars uuid
)
returns public.client_document_ars
language plpgsql security definer set search_path=''
as $$
declare
  d public.documents;
  r public.client_document_ars;
begin
  select * into d from public.documents where id=p_document;
  if not found then raise exception 'Documento no encontrado' using errcode='P0002'; end if;

  if d.entity_type<>'organization'
     or d.document_type_code<>'carta_ars'
     or d.entity_id<>d.organization_id then
    raise exception 'El archivo no corresponde a una carta D del cliente' using errcode='23514';
  end if;

  if not app.can(d.organization_id,array['client','super_admin','admin','assistant','operations']) then
    raise exception 'Sin permiso para asociar esta carta a una ARS' using errcode='42501';
  end if;

  if not exists(
    select 1
      from public.ars a
     where a.id=p_ars and a.is_active
       and (
         exists(select 1 from public.tariffs t where t.organization_id=d.organization_id and t.ars_id=p_ars and t.status<>'suspendida')
         or exists(select 1 from public.submissions s where s.organization_id=d.organization_id and s.ars_id=p_ars)
       )
  ) then
    raise exception 'La ARS no está vinculada a este cliente' using errcode='23514';
  end if;

  insert into public.client_document_ars(document_id,organization_id,ars_id)
  values(d.id,d.organization_id,p_ars)
  on conflict(document_id) do update set
    organization_id=excluded.organization_id,
    ars_id=excluded.ars_id
  returning * into r;

  return r;
end $$;

create or replace function app.client_ars_letters_status(p_org uuid)
returns jsonb
language sql stable set search_path=''
as $$
  with relevant as (
    select distinct t.ars_id
      from public.tariffs t
     where t.organization_id=p_org and t.status<>'suspendida'
    union
    select distinct s.ars_id
      from public.submissions s
     where s.organization_id=p_org
  ),
  ranked as (
    select cda.ars_id,d.id,d.uploaded_at,r.status,
           row_number() over(partition by cda.ars_id order by d.uploaded_at desc,d.id desc) rn
      from public.client_document_ars cda
      join public.documents d on d.id=cda.document_id
      left join public.client_document_reviews r on r.document_id=d.id
     where cda.organization_id=p_org
       and d.document_type_code='carta_ars'
  ),
  latest as (
    select ars_id,id,status from ranked where rn=1
  ),
  counts as (
    select
      count(*)::int total,
      count(*) filter(where l.id is not null)::int loaded,
      count(*) filter(where l.status='aprobado')::int approved,
      count(*) filter(where l.status='requiere_correccion')::int corrections
    from relevant x
    left join latest l on l.ars_id=x.ars_id
  )
  select jsonb_build_object(
    'total',c.total,
    'loaded',c.loaded,
    'approved',c.approved,
    'corrections',c.corrections,
    'ok',(c.total>0 and c.approved=c.total),
    'detail',
      case
        when c.total=0 then 'No hay ARS vinculadas todavía'
        when c.approved=c.total then c.approved||' de '||c.total||' cartas D aprobadas'
        when c.corrections>0 then c.corrections||' carta(s) requieren corrección · '||c.approved||' de '||c.total||' aprobadas'
        else c.approved||' de '||c.total||' cartas D aprobadas'
      end
  )
  from counts c
$$;

grant execute on function app.client_ars_letters_status(uuid) to authenticated;

create or replace function public.onboarding_status(p_org uuid)
returns table(
  step integer, code text, label text, done boolean, source text, detail text, done_at timestamptz
)
language sql stable set search_path=''
as $$
  with ranked_docs as (
    select d.id,d.document_type_code,d.uploaded_at,
           row_number() over(
             partition by d.document_type_code
             order by d.uploaded_at desc,d.id desc
           ) rn
      from public.documents d
     where d.organization_id=p_org
       and d.entity_type='organization'
       and d.entity_id=p_org
       and d.document_type_code in (
         'contrato_sofa','autorizacion_representacion','carta_clinica','formulario_implementacion'
       )
  ),
  doc as (
    select
      case rd.document_type_code
        when 'contrato_sofa' then 'A'
        when 'autorizacion_representacion' then 'B'
        when 'carta_clinica' then 'C'
        when 'formulario_implementacion' then 'E'
      end template_code,
      rd.id document_id,
      rd.uploaded_at,
      coalesce(r.status,'cargado') review_status,
      r.reviewed_at,
      r.notes
    from ranked_docs rd
    left join public.client_document_reviews r on r.document_id=rd.id
    where rd.rn=1
  ),
  dstat as (
    select app.client_ars_letters_status(p_org) j
  ),
  prov as (
    select * from public.providers
    where organization_id=p_org and is_active
  ),
  auto as (
    select 'contrato' code,
      coalesce((select review_status='aprobado' from doc where template_code='A'),false) ok,
      case
        when not exists(select 1 from doc where template_code='A') then 'Documento A pendiente de carga'
        when exists(select 1 from doc where template_code='A' and review_status='requiere_correccion') then 'Documento A requiere corrección'
        when exists(select 1 from doc where template_code='A' and review_status='aprobado') then 'Documento A cargado y aprobado por SOFA'
        else 'Documento A cargado; pendiente de revisión SOFA'
      end how
    union all
    select 'autorizacion',
      coalesce((select review_status='aprobado' from doc where template_code='B'),false),
      case
        when not exists(select 1 from doc where template_code='B') then 'Documento B pendiente de carga'
        when exists(select 1 from doc where template_code='B' and review_status='requiere_correccion') then 'Documento B requiere corrección'
        when exists(select 1 from doc where template_code='B' and review_status='aprobado') then 'Documento B cargado y aprobado por SOFA'
        else 'Documento B cargado; pendiente de revisión SOFA'
      end
    union all
    select 'datos_medico',
      exists(select 1 from prov)
      and not exists(select 1 from prov where tax_id is null or exequatur is null or specialty is null),
      'Cédula, exequátur y especialidad de cada médico'
    union all
    select 'ars_cartas',
      coalesce(((select j->>'ok' from dstat))::boolean,false),
      coalesce((select j->>'detail' from dstat),'Cartas D pendientes')
    union all
    select 'carta_clinica',
      coalesce((select review_status='aprobado' from doc where template_code='C'),false),
      case
        when not exists(select 1 from doc where template_code='C') then 'Documento C pendiente de carga'
        when exists(select 1 from doc where template_code='C' and review_status='requiere_correccion') then 'Documento C requiere corrección'
        when exists(select 1 from doc where template_code='C' and review_status='aprobado') then 'Documento C cargado y aprobado por SOFA'
        else 'Documento C cargado; pendiente de revisión SOFA'
      end
    union all
    select 'tarifario',
      exists(select 1 from prov)
      and not exists(
        select 1 from prov p
        where not exists(
          select 1 from public.tariffs t
           where t.provider_id=p.id
             and t.status<>'suspendida'
             and t.valid_during @> current_date
        )
      ),
      'Tarifa vigente para cada médico'
    union all
    select 'secretaria',
      exists(select 1 from public.capturer_scopes cs where cs.organization_id=p_org)
      or exists(
        select 1 from public.contacts c
         where c.organization_id=p_org
           and c.contact_role='secretaria'
           and c.inducted_on is not null
      ),
      'Capturador asignado o secretaria inducida'
    union all
    select 'formulario',
      coalesce((select review_status='aprobado' from doc where template_code='E'),false),
      case
        when not exists(select 1 from doc where template_code='E') then 'Documento E pendiente de carga'
        when exists(select 1 from doc where template_code='E' and review_status='requiere_correccion') then 'Documento E requiere corrección'
        when exists(select 1 from doc where template_code='E' and review_status='aprobado') then 'Documento E cargado y aprobado por SOFA'
        else 'Documento E cargado; pendiente de revisión SOFA'
      end
    union all
    select 'primera_reclamacion',
      exists(select 1 from public.service_lines l where l.organization_id=p_org),
      'Primera reclamación capturada'
  )
  select
    x.ord,x.code,x.label,
    (a.ok or coalesce(oi.done,false)) done,
    case
      when a.ok then 'automatico'
      when coalesce(oi.done,false) then 'manual'
      else 'pendiente'
    end source,
    case
      when a.ok then a.how
      when coalesce(oi.done,false) then coalesce('Marcado a mano: '||oi.notes,'Marcado a mano')
      else a.how
    end detail,
    case
      when a.ok and x.code='contrato' then (select reviewed_at from doc where template_code='A')
      when a.ok and x.code='autorizacion' then (select reviewed_at from doc where template_code='B')
      when a.ok and x.code='carta_clinica' then (select reviewed_at from doc where template_code='C')
      when a.ok and x.code='formulario' then (select reviewed_at from doc where template_code='E')
      when coalesce(oi.done,false) then oi.done_at
      else null
    end done_at
  from (values
    (1,'contrato','Contrato de servicios firmado (A)'),
    (2,'autorizacion','Autorización de representación firmada (B)'),
    (3,'datos_medico','Datos completos del médico'),
    (4,'ars_cartas','Cartas de representación ante ARS (D)'),
    (5,'carta_clinica','Carta de presentación a la clínica (C)'),
    (6,'tarifario','Tarifario contractual cargado'),
    (7,'secretaria','Secretaria registrada e inducida'),
    (8,'formulario','Formulario de implementación (E)'),
    (9,'primera_reclamacion','Primera reclamación capturada')
  ) x(ord,code,label)
  join auto a on a.code=x.code
  left join public.onboarding_items oi
    on oi.organization_id=p_org and oi.step_code=x.code
  order by x.ord;
$$;

commit;
