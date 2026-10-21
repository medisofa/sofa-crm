-- 220 · Onboarding A–E basado en archivos reales cargados y aprobados
begin;

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
         'contrato_sofa','autorizacion_representacion','carta_clinica',
         'carta_ars','formulario_implementacion'
       )
  ),
  doc as (
    select
      case rd.document_type_code
        when 'contrato_sofa' then 'A'
        when 'autorizacion_representacion' then 'B'
        when 'carta_clinica' then 'C'
        when 'carta_ars' then 'D'
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
      coalesce((select review_status='aprobado' from doc where template_code='D'),false),
      case
        when not exists(select 1 from doc where template_code='D') then 'Documento D pendiente de carga'
        when exists(select 1 from doc where template_code='D' and review_status='requiere_correccion') then 'Documento D requiere corrección'
        when exists(select 1 from doc where template_code='D' and review_status='aprobado') then 'Documento D cargado y aprobado por SOFA'
        else 'Documento D cargado; pendiente de revisión SOFA'
      end
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
      when a.ok and x.code='ars_cartas' then (select reviewed_at from doc where template_code='D')
      when a.ok and x.code='carta_clinica' then (select reviewed_at from doc where template_code='C')
      when a.ok and x.code='formulario' then (select reviewed_at from doc where template_code='E')
      when coalesce(oi.done,false) then oi.done_at
      else null
    end done_at
  from (values
    (1,'contrato','Contrato de servicios firmado (A)'),
    (2,'autorizacion','Autorización de representación firmada (B)'),
    (3,'datos_medico','Datos completos del médico'),
    (4,'ars_cartas','Carta de representación ante ARS (D)'),
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
