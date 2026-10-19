-- STAGING ONLY — role subsystem harness for admin-users/role matrix tests.
-- Never apply to production.

create schema if not exists app;

create table if not exists public.roles(
  code text primary key,
  name text not null,
  description text,
  is_staff boolean not null,
  sort_order smallint not null default 0
);

create table if not exists public.organizations(
  id uuid primary key default gen_random_uuid(),
  kind text not null check(kind in ('operator','client')),
  operator_id uuid,
  legal_name text not null,
  trade_name text,
  status text not null default 'activo',
  created_at timestamptz not null default now()
);

create table if not exists public.profiles(
  id uuid primary key,
  full_name text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.organization_users(
  organization_id uuid not null references public.organizations(id),
  user_id uuid not null,
  role_code text not null references public.roles(code),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid,
  primary key(organization_id,user_id)
);

create table if not exists public.clinical_settings(
  organization_id uuid primary key references public.organizations(id),
  mode text not null default 'desactivada',
  require_mfa boolean not null default false,
  set_by uuid,
  set_at timestamptz not null default now()
);

create table if not exists public.leads(
  id uuid primary key default gen_random_uuid(),
  operator_id uuid not null references public.organizations(id),
  company text not null,
  converted_org_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.lead_users(
  lead_id uuid not null references public.leads(id),
  user_id uuid not null,
  is_active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  primary key(lead_id,user_id)
);

create table if not exists public.app_modules(
  code text primary key,
  label text not null,
  sort_order smallint not null default 100
);

create table if not exists public.role_modules(
  role_code text not null references public.roles(code),
  module_code text not null references public.app_modules(code),
  primary key(role_code,module_code)
);

create or replace function app.clinical_mode(p_org uuid)
returns text language sql stable security definer set search_path=''
as $$
  select coalesce((select mode from public.clinical_settings where organization_id=p_org),'desactivada')
$$;
