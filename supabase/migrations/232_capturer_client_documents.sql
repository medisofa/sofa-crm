-- 232 · Portal documental limitado para Secretaria/Capturista
-- Permite gestionar únicamente documentos A–E de su propia organización.
begin;

create or replace function public.client_document_portal_context(p_org uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  o public.organizations;
begin
  if p_org is null or not app.can(
    p_org,
    array['client','capturer','super_admin','admin','assistant','operations']
  ) then
    raise exception 'Sin acceso al portal documental de este consultorio' using errcode='42501';
  end if;

  select * into o from public.organizations where id=p_org and kind='client';
  if not found then
    raise exception 'Consultorio no encontrado' using errcode='P0002';
  end if;

  return jsonb_build_object(
    'id',o.id,
    'legal_name',o.legal_name,
    'trade_name',o.trade_name,
    'tax_id',o.tax_id,
    'address',o.address,
    'city',o.city,
    'email',o.email,
    'phone',o.phone,
    'whatsapp',o.whatsapp,
    'status',o.status,
    'org_type',o.org_type,
    'specialty',o.specialty
  );
end $$;

grant execute on function public.client_document_portal_context(uuid) to authenticated;

drop policy if exists client_contract_documents_select_capturer on public.documents;
create policy client_contract_documents_select_capturer
on public.documents
for select to authenticated
using (
  app.can(organization_id,array['capturer'])
  and entity_type='organization'
  and entity_id=organization_id
  and document_type_code in (
    'contrato_sofa',
    'autorizacion_representacion',
    'carta_clinica',
    'carta_ars',
    'formulario_implementacion'
  )
);

drop policy if exists client_contract_documents_insert_capturer on public.documents;
create policy client_contract_documents_insert_capturer
on public.documents
for insert to authenticated
with check (
  app.can(organization_id,array['capturer'])
  and uploaded_by=auth.uid()
  and entity_type='organization'
  and entity_id=organization_id
  and service_line_id is null
  and document_type_code in (
    'contrato_sofa',
    'autorizacion_representacion',
    'carta_clinica',
    'carta_ars',
    'formulario_implementacion'
  )
);

drop policy if exists client_document_reviews_select_capturer on public.client_document_reviews;
create policy client_document_reviews_select_capturer
on public.client_document_reviews
for select to authenticated
using (app.can(organization_id,array['capturer']));

drop policy if exists client_document_ars_select_capturer on public.client_document_ars;
create policy client_document_ars_select_capturer
on public.client_document_ars
for select to authenticated
using (app.can(organization_id,array['capturer']));

drop policy if exists sofa_contracts_insert_capturer on storage.objects;
create policy sofa_contracts_insert_capturer
on storage.objects
for insert to authenticated
with check (
  bucket_id='contracts'
  and app.can(app.try_uuid((storage.foldername(name))[1]),array['capturer'])
);

drop policy if exists sofa_contracts_select_capturer on storage.objects;
create policy sofa_contracts_select_capturer
on storage.objects
for select to authenticated
using (
  bucket_id='contracts'
  and app.can(app.try_uuid((storage.foldername(name))[1]),array['capturer'])
);

create or replace function public.client_document_ars_options(p_org uuid)
returns table(ars_id uuid, ars_name text)
language sql stable security definer set search_path=''
as $$
  with ids as (
    select distinct t.ars_id
      from public.tariffs t
     where t.organization_id=p_org
       and t.status<>'suspendida'
    union
    select distinct s.ars_id
      from public.submissions s
     where s.organization_id=p_org
  )
  select a.id,a.name
    from ids i
    join public.ars a on a.id=i.ars_id
   where a.is_active
     and (
       p_org in (select app.visible_org_ids())
       or app.can(p_org,array['capturer'])
     )
   order by a.name
$$;

grant execute on function public.client_document_ars_options(uuid) to authenticated;

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

  if not app.can(d.organization_id,array['client','capturer','super_admin','admin','assistant','operations']) then
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

grant execute on function public.link_client_document_ars(uuid,uuid) to authenticated;

commit;
