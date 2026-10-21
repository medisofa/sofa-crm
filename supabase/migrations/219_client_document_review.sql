-- 219 · Revisión SOFA de documentos A–E cargados por el cliente
begin;

create table if not exists public.client_document_reviews (
  document_id uuid primary key references public.documents(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  status text not null default 'en_revision'
    check (status in ('en_revision','aprobado','requiere_correccion')),
  notes text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists client_document_reviews_org_idx
  on public.client_document_reviews(organization_id, updated_at desc);

alter table public.client_document_reviews enable row level security;

drop policy if exists client_document_reviews_select on public.client_document_reviews;
create policy client_document_reviews_select
on public.client_document_reviews
for select to authenticated
using (organization_id in (select app.visible_org_ids()));

drop policy if exists client_document_reviews_insert on public.client_document_reviews;
create policy client_document_reviews_insert
on public.client_document_reviews
for insert to authenticated
with check (
  app.can(organization_id,array['super_admin','admin','assistant','operations'])
  and reviewed_by = auth.uid()
);

drop policy if exists client_document_reviews_update on public.client_document_reviews;
create policy client_document_reviews_update
on public.client_document_reviews
for update to authenticated
using (app.can(organization_id,array['super_admin','admin','assistant','operations']))
with check (
  app.can(organization_id,array['super_admin','admin','assistant','operations'])
  and reviewed_by = auth.uid()
);

grant select,insert,update on public.client_document_reviews to authenticated;

create or replace function public.review_client_document(
  p_document uuid,
  p_status text,
  p_notes text default null
)
returns public.client_document_reviews
language plpgsql security definer set search_path=''
as $$
declare
  d public.documents;
  r public.client_document_reviews;
begin
  if p_status not in ('en_revision','aprobado','requiere_correccion') then
    raise exception 'Estado de revisión inválido' using errcode='22023';
  end if;

  select * into d from public.documents where id=p_document;
  if not found then raise exception 'Documento no encontrado' using errcode='P0002'; end if;

  if d.entity_type <> 'organization'
     or d.document_type_code not in (
       'contrato_sofa','autorizacion_representacion','carta_clinica','carta_ars','formulario_implementacion'
     ) then
    raise exception 'Este archivo no pertenece al flujo documental A–E' using errcode='23514';
  end if;

  if not app.can(d.organization_id,array['super_admin','admin','assistant','operations']) then
    raise exception 'Sin permiso para revisar documentos del cliente' using errcode='42501';
  end if;

  if p_status='requiere_correccion' and length(trim(coalesce(p_notes,''))) < 5 then
    raise exception 'Indique qué debe corregir el cliente' using errcode='22023';
  end if;

  insert into public.client_document_reviews(
    document_id,organization_id,status,notes,reviewed_by,reviewed_at,updated_at
  )
  values(
    d.id,d.organization_id,p_status,nullif(trim(coalesce(p_notes,'')),''),
    auth.uid(),now(),now()
  )
  on conflict(document_id) do update set
    status=excluded.status,
    notes=excluded.notes,
    reviewed_by=excluded.reviewed_by,
    reviewed_at=excluded.reviewed_at,
    updated_at=now()
  returning * into r;

  insert into public.audit_log(
    user_id,organization_id,table_name,record_id,operation,new_values
  )
  values(
    auth.uid(),d.organization_id,'client_document_reviews',d.id::text,'UPDATE',
    jsonb_build_object('status',r.status,'notes',r.notes)
  );

  return r;
end $$;

grant execute on function public.review_client_document(uuid,text,text) to authenticated;

commit;
