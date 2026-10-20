-- SOFA · Certificados de pago SeNaSa
-- Modelo basado en el "Certificado de Pago Prestador de Servicios de Salud":
-- cabecera, detalle de facturas y detalle de autorizaciones por factura.

create table if not exists public.senasa_payment_certificates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id uuid references public.providers(id) on delete set null,
  ars_id uuid not null references public.ars(id),
  provider_code text not null,
  provider_name_snapshot text not null,
  rnc text,
  ovp_number text not null,
  subtotal numeric(14,2) not null default 0,
  invoice_objection_amount numeric(14,2) not null default 0,
  authorization_objection_amount numeric(14,2) not null default 0,
  total_payable numeric(14,2) not null default 0,
  status text not null default 'pendiente' check(status in ('pendiente','revisado','conciliado','con_diferencias')),
  source_file_name text,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique(organization_id,ars_id,ovp_number)
);

create table if not exists public.senasa_certificate_invoices (
  id uuid primary key default gen_random_uuid(),
  certificate_id uuid not null references public.senasa_payment_certificates(id) on delete cascade,
  internal_number text,
  ncf text,
  receipt_date date,
  invoice_date date,
  invoice_amount numeric(14,2) not null default 0,
  invoice_objection_amount numeric(14,2) not null default 0,
  authorization_objection_amount numeric(14,2) not null default 0,
  amount_payable numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.senasa_certificate_authorizations (
  id uuid primary key default gen_random_uuid(),
  certificate_id uuid not null references public.senasa_payment_certificates(id) on delete cascade,
  invoice_number text,
  authorization_number text not null,
  authorization_date date,
  affiliate_name text,
  service_name text,
  claimed_amount numeric(14,2) not null default 0,
  objected_amount numeric(14,2) not null default 0,
  paid_amount numeric(14,2) not null default 0,
  service_line_id uuid references public.service_lines(id) on delete set null,
  match_status text not null default 'pendiente' check(match_status in ('pendiente','coincidencia','diferencia','no_encontrada')),
  created_at timestamptz not null default now(),
  unique(certificate_id,authorization_number)
);

alter table public.senasa_payment_certificates enable row level security;
alter table public.senasa_certificate_invoices enable row level security;
alter table public.senasa_certificate_authorizations enable row level security;

drop policy if exists senasa_cert_read on public.senasa_payment_certificates;
create policy senasa_cert_read on public.senasa_payment_certificates for select to authenticated
using (organization_id in (select app.visible_org_ids()));

drop policy if exists senasa_cert_manage on public.senasa_payment_certificates;
create policy senasa_cert_manage on public.senasa_payment_certificates for all to authenticated
using (app.can(organization_id,array['super_admin','admin','glosas']))
with check (app.can(organization_id,array['super_admin','admin','glosas']));

drop policy if exists senasa_inv_read on public.senasa_certificate_invoices;
create policy senasa_inv_read on public.senasa_certificate_invoices for select to authenticated
using (certificate_id in (select id from public.senasa_payment_certificates where organization_id in (select app.visible_org_ids())));

drop policy if exists senasa_auth_read on public.senasa_certificate_authorizations;
create policy senasa_auth_read on public.senasa_certificate_authorizations for select to authenticated
using (certificate_id in (select id from public.senasa_payment_certificates where organization_id in (select app.visible_org_ids())));

grant select,insert,update on public.senasa_payment_certificates to authenticated;
grant select,insert,update,delete on public.senasa_certificate_invoices to authenticated;
grant select,insert,update,delete on public.senasa_certificate_authorizations to authenticated;

create or replace function public.save_senasa_payment_certificate(
  p_org uuid,
  p_provider uuid,
  p_ars uuid,
  p_provider_code text,
  p_provider_name text,
  p_rnc text,
  p_ovp text,
  p_subtotal numeric,
  p_invoice_obj numeric,
  p_auth_obj numeric,
  p_total numeric,
  p_source_file text,
  p_invoices jsonb,
  p_authorizations jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id uuid;
  x jsonb;
  v_line uuid;
  v_match text;
begin
  if not app.can(p_org,array['super_admin','admin','glosas']) then
    raise exception 'Sin permiso para registrar certificados SeNaSa.' using errcode='42501';
  end if;
  if length(trim(coalesce(p_ovp,'')))<3 then
    raise exception 'Indique el número de certificado OVP.' using errcode='22023';
  end if;

  insert into public.senasa_payment_certificates(
    organization_id,provider_id,ars_id,provider_code,provider_name_snapshot,rnc,ovp_number,
    subtotal,invoice_objection_amount,authorization_objection_amount,total_payable,source_file_name,updated_by
  )
  values(
    p_org,p_provider,p_ars,trim(p_provider_code),trim(p_provider_name),nullif(trim(p_rnc),''),
    trim(p_ovp),coalesce(p_subtotal,0),coalesce(p_invoice_obj,0),coalesce(p_auth_obj,0),coalesce(p_total,0),nullif(trim(p_source_file),''),auth.uid()
  )
  on conflict(organization_id,ars_id,ovp_number) do update set
    provider_id=excluded.provider_id,provider_code=excluded.provider_code,provider_name_snapshot=excluded.provider_name_snapshot,
    rnc=excluded.rnc,subtotal=excluded.subtotal,invoice_objection_amount=excluded.invoice_objection_amount,
    authorization_objection_amount=excluded.authorization_objection_amount,total_payable=excluded.total_payable,
    source_file_name=excluded.source_file_name,updated_at=now(),updated_by=auth.uid()
  returning id into v_id;

  delete from public.senasa_certificate_invoices where certificate_id=v_id;
  delete from public.senasa_certificate_authorizations where certificate_id=v_id;

  for x in select * from jsonb_array_elements(coalesce(p_invoices,'[]'::jsonb)) loop
    insert into public.senasa_certificate_invoices(
      certificate_id,internal_number,ncf,receipt_date,invoice_date,invoice_amount,
      invoice_objection_amount,authorization_objection_amount,amount_payable
    ) values(
      v_id,nullif(x->>'internal_number',''),nullif(x->>'ncf',''),nullif(x->>'receipt_date','')::date,
      nullif(x->>'invoice_date','')::date,coalesce((x->>'invoice_amount')::numeric,0),
      coalesce((x->>'invoice_objection_amount')::numeric,0),coalesce((x->>'authorization_objection_amount')::numeric,0),
      coalesce((x->>'amount_payable')::numeric,0)
    );
  end loop;

  for x in select * from jsonb_array_elements(coalesce(p_authorizations,'[]'::jsonb)) loop
    v_line:=null;
    v_match:='no_encontrada';
    select sl.id into v_line
      from public.service_lines sl
      join public.submissions s on s.id=sl.submission_id
     where sl.organization_id=p_org
       and s.ars_id=p_ars
       and sl.authorization_number=(x->>'authorization_number')
     order by sl.service_date desc
     limit 1;
    if v_line is not null then
      if abs(coalesce((x->>'claimed_amount')::numeric,0) - coalesce((select amount from public.service_lines where id=v_line),0)) < 0.01 then
        v_match:='coincidencia';
      else
        v_match:='diferencia';
      end if;
    end if;

    insert into public.senasa_certificate_authorizations(
      certificate_id,invoice_number,authorization_number,authorization_date,affiliate_name,service_name,
      claimed_amount,objected_amount,paid_amount,service_line_id,match_status
    ) values(
      v_id,nullif(x->>'invoice_number',''),trim(x->>'authorization_number'),nullif(x->>'authorization_date','')::date,
      nullif(x->>'affiliate_name',''),nullif(x->>'service_name',''),
      coalesce((x->>'claimed_amount')::numeric,0),coalesce((x->>'objected_amount')::numeric,0),
      coalesce((x->>'paid_amount')::numeric,0),v_line,v_match
    );
  end loop;

  update public.senasa_payment_certificates
     set status=case
       when exists(select 1 from public.senasa_certificate_authorizations where certificate_id=v_id and match_status in ('diferencia','no_encontrada'))
         then 'con_diferencias'
       else 'revisado'
     end
   where id=v_id;

  insert into public.audit_log(user_id,organization_id,table_name,record_id,operation,new_values)
  values(auth.uid(),p_org,'senasa_payment_certificates',v_id::text,'REGISTRO_CERTIFICADO_SENASA',
         jsonb_build_object('ovp',p_ovp,'total',p_total,'invoice_objection',p_invoice_obj,'authorization_objection',p_auth_obj));

  return v_id;
end
$$;

revoke all on function public.save_senasa_payment_certificate(uuid,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,text,jsonb,jsonb) from public,anon;
grant execute on function public.save_senasa_payment_certificate(uuid,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,text,jsonb,jsonb) to authenticated;
