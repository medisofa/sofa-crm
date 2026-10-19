-- SOFA MVP v1 — schema nuevo y aislado.
-- NO ejecutar en producción sin backup restaurable y pruebas de aislamiento.
-- Diseñado para Supabase/PostgreSQL. No contiene secretos.

create schema if not exists app;

create extension if not exists pgcrypto;

create table if not exists public.organizations_v1 (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('operator','client')),
  operator_id uuid references public.organizations_v1(id),
  legal_name text not null,
  trade_name text,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now()
);

create table if not exists public.organization_users_v1 (
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null check (role_code in ('super_admin','admin','operations','billing','glosas','assistant','auditor','client','capturer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (organization_id,user_id)
);

create table if not exists public.external_access_home_v1 (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz not null default now()
);

create table if not exists public.external_multi_org_exceptions_v1 (
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  approved_by uuid not null references auth.users(id),
  reason text not null check (length(btrim(reason)) >= 12),
  valid_until timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id,organization_id)
);

create table if not exists public.staff_client_access_v1 (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_org_id uuid not null references public.organizations_v1(id) on delete cascade,
  granted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(user_id,client_org_id)
);

create table if not exists public.providers_v1 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  full_name text not null,
  specialty text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.capturer_scopes_v1 (
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_id uuid not null references public.providers_v1(id) on delete cascade,
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  can_capture boolean not null default true,
  primary key(user_id,provider_id)
);

create table if not exists public.ars_v1 (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true
);

create table if not exists public.procedures_v1 (
  id uuid primary key default gen_random_uuid(),
  internal_code text not null unique,
  name text not null,
  simon_code text,
  cups_code text,
  is_active boolean not null default true
);

create table if not exists public.tariffs_v1 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  provider_id uuid not null references public.providers_v1(id) on delete cascade,
  ars_id uuid not null references public.ars_v1(id),
  procedure_id uuid not null references public.procedures_v1(id),
  amount numeric(12,2) not null check(amount >= 0),
  valid_from date not null,
  valid_to date,
  status text not null default 'active' check(status in ('active','inactive')),
  created_at timestamptz not null default now(),
  check(valid_to is null or valid_to >= valid_from)
);
create index if not exists tariffs_v1_lookup_ix on public.tariffs_v1(organization_id,provider_id,ars_id,procedure_id,valid_from desc);

create sequence if not exists public.claim_folio_v1_seq;

create table if not exists public.claims_v1 (
  id uuid primary key default gen_random_uuid(),
  folio text not null unique,
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  provider_id uuid not null references public.providers_v1(id),
  ars_id uuid not null references public.ars_v1(id),
  procedure_id uuid not null references public.procedures_v1(id),
  service_date date not null,
  patient_name text not null,
  member_number text not null,
  authorization_number text,
  quantity int not null default 1 check(quantity between 1 and 99),
  unit_amount numeric(12,2) not null check(unit_amount >= 0),
  amount numeric(12,2) generated always as (quantity * unit_amount) stored,
  status text not null default 'captured' check(status in ('captured','received','validated','submitted','observed','denied','paid','closed')),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists claims_v1_org_status_ix on public.claims_v1(organization_id,status,created_at desc);
create index if not exists claims_v1_provider_date_ix on public.claims_v1(provider_id,service_date desc);
create unique index if not exists claims_v1_soft_dup_ux on public.claims_v1(organization_id,provider_id,ars_id,service_date,member_number,procedure_id,authorization_number)
where status <> 'closed';

create table if not exists public.claim_events_v1 (
  id bigint generated always as identity primary key,
  claim_id uuid not null references public.claims_v1(id) on delete cascade,
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  note text,
  actor_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists claim_events_v1_claim_ix on public.claim_events_v1(claim_id,created_at);

create table if not exists public.claim_documents_v1 (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references public.claims_v1(id) on delete cascade,
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  kind text not null,
  object_path text not null unique,
  mime_type text,
  size_bytes bigint check(size_bytes is null or size_bytes >= 0),
  uploaded_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.submissions_v1 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  provider_id uuid not null references public.providers_v1(id),
  ars_id uuid not null references public.ars_v1(id),
  period date not null,
  sequence int not null default 1,
  status text not null default 'draft' check(status in ('draft','submitted','accepted','partial','closed')),
  submitted_on date,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,provider_id,ars_id,period,sequence)
);

create table if not exists public.submission_claims_v1 (
  submission_id uuid not null references public.submissions_v1(id) on delete cascade,
  claim_id uuid not null references public.claims_v1(id) on delete restrict,
  primary key(submission_id,claim_id)
);

create table if not exists public.payments_v1 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  ars_id uuid not null references public.ars_v1(id),
  paid_on date not null,
  amount numeric(12,2) not null check(amount > 0),
  reference text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.payment_allocations_v1 (
  payment_id uuid not null references public.payments_v1(id) on delete cascade,
  claim_id uuid not null references public.claims_v1(id) on delete restrict,
  amount numeric(12,2) not null check(amount > 0),
  primary key(payment_id,claim_id)
);

create table if not exists public.denials_v1 (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references public.claims_v1(id) on delete cascade,
  organization_id uuid not null references public.organizations_v1(id) on delete cascade,
  reason_code text,
  reason text not null,
  denied_amount numeric(12,2) not null check(denied_amount >= 0),
  status text not null default 'open' check(status in ('open','appealed','accepted','recovered','closed')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_events_v1 (
  id bigint generated always as identity primary key,
  organization_id uuid references public.organizations_v1(id),
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_events_v1_org_ix on public.audit_events_v1(organization_id,created_at desc);

create or replace function app.is_staff_v1()
returns boolean language sql stable security definer set search_path=''
as $$
  select exists (
    select 1 from public.organization_users_v1 ou
    join public.organizations_v1 o on o.id=ou.organization_id and o.kind='operator'
    where ou.user_id=auth.uid() and ou.is_active
      and ou.role_code in ('super_admin','admin','operations','billing','glosas','assistant','auditor')
  )
$$;

create or replace function app.staff_role_v1()
returns text language sql stable security definer set search_path=''
as $$
  select ou.role_code from public.organization_users_v1 ou
  join public.organizations_v1 o on o.id=ou.organization_id and o.kind='operator'
  where ou.user_id=auth.uid() and ou.is_active
    and ou.role_code in ('super_admin','admin','operations','billing','glosas','assistant','auditor')
  order by case ou.role_code when 'super_admin' then 1 when 'admin' then 2 else 3 end
  limit 1
$$;

create or replace function app.visible_org_ids_v1()
returns setof uuid language sql stable security definer set search_path=''
as $$
  with staff as (
    select ou.organization_id operator_id, ou.role_code
    from public.organization_users_v1 ou
    join public.organizations_v1 o on o.id=ou.organization_id and o.kind='operator'
    where ou.user_id=auth.uid() and ou.is_active
  ),
  external_direct as (
    select ou.organization_id
    from public.organization_users_v1 ou
    join public.organizations_v1 o on o.id=ou.organization_id and o.kind='client'
    where ou.user_id=auth.uid() and ou.is_active
      and (
        exists(select 1 from public.external_access_home_v1 h where h.user_id=auth.uid() and h.organization_id=ou.organization_id)
        or exists(select 1 from public.external_multi_org_exceptions_v1 e
                  where e.user_id=auth.uid() and e.organization_id=ou.organization_id
                    and e.revoked_at is null and e.valid_until > now())
      )
  ),
  staff_clients as (
    select c.id organization_id
    from public.organizations_v1 c
    join staff s on s.operator_id=c.operator_id
    where c.kind='client' and c.status='active'
      and (
        s.role_code in ('super_admin','admin')
        or exists(select 1 from public.staff_client_access_v1 a where a.user_id=auth.uid() and a.client_org_id=c.id)
      )
  )
  select organization_id from external_direct
  union
  select organization_id from staff_clients
$$;

create or replace function app.role_for_org_v1(p_org uuid)
returns text language plpgsql stable security definer set search_path=''
as $$
declare v text;
begin
  if p_org not in (select app.visible_org_ids_v1()) then return null; end if;
  select ou.role_code into v
  from public.organization_users_v1 ou
  where ou.user_id=auth.uid() and ou.organization_id=p_org and ou.is_active
  limit 1;
  if v is not null then return v; end if;
  return app.staff_role_v1();
end
$$;

create or replace function app.can_claim_v1(p_org uuid,p_provider uuid,p_write boolean default false)
returns boolean language plpgsql stable security definer set search_path=''
as $$
declare v_role text;
begin
  v_role := app.role_for_org_v1(p_org);
  if v_role is null then return false; end if;
  if v_role='capturer' then
    return exists(select 1 from public.capturer_scopes_v1 s
      where s.user_id=auth.uid() and s.organization_id=p_org and s.provider_id=p_provider
        and (not p_write or s.can_capture));
  end if;
  return v_role in ('super_admin','admin','operations','billing','glosas','assistant','auditor','client');
end
$$;

create or replace function public.my_context_v1()
returns jsonb language sql stable security definer set search_path=''
as $$
  select jsonb_build_object(
    'user_id', auth.uid(),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organization_id', o.id,
        'organization_name', coalesce(o.trade_name,o.legal_name),
        'kind', o.kind,
        'role_code', ou.role_code
      ) order by o.kind desc,coalesce(o.trade_name,o.legal_name))
      from public.organization_users_v1 ou
      join public.organizations_v1 o on o.id=ou.organization_id
      where ou.user_id=auth.uid() and ou.is_active
        and (o.kind='operator' or o.id in (select app.visible_org_ids_v1()))
    ),'[]'::jsonb)
  )
$$;

create or replace function public.claim_create_v1(p_input jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_org uuid := (p_input->>'organization_id')::uuid;
  v_provider uuid := (p_input->>'provider_id')::uuid;
  v_ars uuid := (p_input->>'ars_id')::uuid;
  v_proc uuid := (p_input->>'procedure_id')::uuid;
  v_date date := (p_input->>'service_date')::date;
  v_qty int := coalesce((p_input->>'quantity')::int,1);
  v_requested numeric := (p_input->>'unit_amount')::numeric;
  v_tariff numeric;
  v_claim public.claims_v1;
begin
  if not app.can_claim_v1(v_org,v_provider,true) then raise exception 'Sin acceso a este médico.' using errcode='42501'; end if;
  if not exists(select 1 from public.providers_v1 p where p.id=v_provider and p.organization_id=v_org and p.is_active) then
    raise exception 'Médico no válido para este cliente.' using errcode='22023';
  end if;
  select t.amount into v_tariff from public.tariffs_v1 t
   where t.organization_id=v_org and t.provider_id=v_provider and t.ars_id=v_ars and t.procedure_id=v_proc
     and t.status='active' and t.valid_from<=v_date and (t.valid_to is null or t.valid_to>=v_date)
   order by t.valid_from desc limit 1;
  if v_tariff is null then raise exception 'No existe tarifa vigente para ese servicio.' using errcode='23514'; end if;
  if abs(v_requested-v_tariff)>0.01 then raise exception 'El monto no coincide con la tarifa vigente.' using errcode='23514'; end if;

  insert into public.claims_v1(folio,organization_id,provider_id,ars_id,procedure_id,service_date,patient_name,member_number,authorization_number,quantity,unit_amount,notes)
  values('REC-'||to_char(current_date,'YY')||'-'||lpad(nextval('public.claim_folio_v1_seq')::text,7,'0'),
         v_org,v_provider,v_ars,v_proc,v_date,left(btrim(p_input->>'patient_name'),150),left(btrim(p_input->>'member_number'),60),
         nullif(left(btrim(coalesce(p_input->>'authorization_number','')),80),''),
         v_qty,v_tariff,nullif(left(btrim(coalesce(p_input->>'notes','')),500),''))
  returning * into v_claim;

  insert into public.claim_events_v1(claim_id,organization_id,event_type,to_status,note,actor_id)
  values(v_claim.id,v_org,'created','captured','Reclamación capturada',auth.uid());
  insert into public.audit_events_v1(organization_id,actor_id,action,entity_type,entity_id,metadata)
  values(v_org,auth.uid(),'claim.created','claim',v_claim.id,jsonb_build_object('folio',v_claim.folio,'status',v_claim.status));

  return jsonb_build_object('id',v_claim.id,'folio',v_claim.folio,'status',v_claim.status,'amount',v_claim.amount);
end
$$;

create or replace function public.claim_transition_v1(p_claim uuid,p_to_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare c public.claims_v1; v_role text; v_allowed boolean := false;
begin
  select * into c from public.claims_v1 where id=p_claim for update;
  if c.id is null or not app.can_claim_v1(c.organization_id,c.provider_id,true) then
    raise exception 'Reclamación no encontrada.' using errcode='P0002';
  end if;
  v_role := app.role_for_org_v1(c.organization_id);

  v_allowed := case c.status
    when 'captured' then p_to_status='received' and v_role in ('super_admin','admin','operations','billing')
    when 'received' then p_to_status='validated' and v_role in ('super_admin','admin','operations','billing','auditor')
    when 'validated' then p_to_status='submitted' and v_role in ('super_admin','admin','billing')
    when 'submitted' then p_to_status in ('observed','denied','paid') and v_role in ('super_admin','admin','glosas')
    when 'observed' then p_to_status in ('submitted','denied','paid') and v_role in ('super_admin','admin','glosas','billing')
    when 'denied' then p_to_status in ('submitted','closed') and v_role in ('super_admin','admin','glosas')
    when 'paid' then p_to_status='closed' and v_role in ('super_admin','admin','glosas')
    else false end;
  if not v_allowed then raise exception 'Transición no permitida para el estado o rol.' using errcode='42501'; end if;

  update public.claims_v1 set status=p_to_status,updated_at=now() where id=p_claim;
  insert into public.claim_events_v1(claim_id,organization_id,event_type,from_status,to_status,note,actor_id)
  values(p_claim,c.organization_id,'status_changed',c.status,p_to_status,nullif(left(btrim(coalesce(p_note,'')),500),''),auth.uid());
  insert into public.audit_events_v1(organization_id,actor_id,action,entity_type,entity_id,metadata)
  values(c.organization_id,auth.uid(),'claim.status_changed','claim',p_claim,jsonb_build_object('from',c.status,'to',p_to_status));
  return jsonb_build_object('id',p_claim,'from',c.status,'to',p_to_status);
end
$$;

alter table public.organizations_v1 enable row level security;
alter table public.organization_users_v1 enable row level security;
alter table public.providers_v1 enable row level security;
alter table public.capturer_scopes_v1 enable row level security;
alter table public.ars_v1 enable row level security;
alter table public.procedures_v1 enable row level security;
alter table public.tariffs_v1 enable row level security;
alter table public.claims_v1 enable row level security;
alter table public.claim_events_v1 enable row level security;
alter table public.claim_documents_v1 enable row level security;
alter table public.submissions_v1 enable row level security;
alter table public.submission_claims_v1 enable row level security;
alter table public.payments_v1 enable row level security;
alter table public.payment_allocations_v1 enable row level security;
alter table public.denials_v1 enable row level security;
alter table public.audit_events_v1 enable row level security;
alter table public.external_access_home_v1 enable row level security;
alter table public.external_multi_org_exceptions_v1 enable row level security;
alter table public.staff_client_access_v1 enable row level security;

create policy claims_v1_select on public.claims_v1 for select to authenticated
using(app.can_claim_v1(organization_id,provider_id,false));
create policy claims_v1_insert on public.claims_v1 for insert to authenticated
with check(app.can_claim_v1(organization_id,provider_id,true) and created_by=auth.uid());

create policy claim_events_v1_select on public.claim_events_v1 for select to authenticated
using(exists(select 1 from public.claims_v1 c where c.id=claim_id and app.can_claim_v1(c.organization_id,c.provider_id,false)));

create policy providers_v1_select on public.providers_v1 for select to authenticated
using(organization_id in(select app.visible_org_ids_v1()) and
      (app.role_for_org_v1(organization_id)<>'capturer' or exists(select 1 from public.capturer_scopes_v1 s where s.user_id=auth.uid() and s.provider_id=id)));

create policy tariffs_v1_select on public.tariffs_v1 for select to authenticated
using(organization_id in(select app.visible_org_ids_v1()) and
      (app.role_for_org_v1(organization_id)<>'capturer' or exists(
        select 1 from public.capturer_scopes_v1 s
        where s.user_id=auth.uid()
          and s.provider_id=tariffs_v1.provider_id
          and s.organization_id=tariffs_v1.organization_id
      )));

create policy ars_v1_read on public.ars_v1 for select to authenticated using(true);
create policy procedures_v1_read on public.procedures_v1 for select to authenticated using(true);

create policy documents_v1_select on public.claim_documents_v1 for select to authenticated
using(exists(select 1 from public.claims_v1 c where c.id=claim_id and app.can_claim_v1(c.organization_id,c.provider_id,false)));
create policy documents_v1_insert on public.claim_documents_v1 for insert to authenticated
with check(exists(select 1 from public.claims_v1 c where c.id=claim_id and c.organization_id=organization_id and app.can_claim_v1(c.organization_id,c.provider_id,true)));

revoke all on public.external_access_home_v1,public.external_multi_org_exceptions_v1,public.staff_client_access_v1 from anon,authenticated;
revoke update,delete on public.claims_v1 from authenticated;
revoke all on function app.is_staff_v1(),app.staff_role_v1(),app.visible_org_ids_v1(),app.role_for_org_v1(uuid),app.can_claim_v1(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.my_context_v1(),public.claim_create_v1(jsonb),public.claim_transition_v1(uuid,text,text) from public,anon;
grant execute on function public.my_context_v1(),public.claim_create_v1(jsonb),public.claim_transition_v1(uuid,text,text) to authenticated;
