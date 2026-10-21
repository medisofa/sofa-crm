-- 221 · Documento D independiente por cada ARS del cliente
begin;

create table if not exists public.client_document_ars (
  document_id uuid primary key references public.documents(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  ars_id uuid not null references public.ars(id),
  created_at timestamptz not null default now(),
  unique (organization_id, document_id, ars_id)
);

create index if not exists client_document_ars_org_idx
  on public.client_document_ars(organization_id, ars_id, created_at desc);

alter table public.client_document_ars enable row level security;

drop policy if exists client_document_ars_select on public.client_document_ars;
create policy client_document_ars_select
on public.client_document_ars
for select to authenticated
using (organization_id in (select app.visible_org_ids()));

grant select on public.client_document_ars to authenticated;

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

  if not exists(select 1 from public.ars a where a.id=p_ars and a.is_active) then
    raise exception 'ARS inválida o inactiva' using errcode='22023';
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
     and p_org in (select app.visible_org_ids())
   order by a.name
$$;

grant execute on function public.client_document_ars_options(uuid) to authenticated;

commit;
