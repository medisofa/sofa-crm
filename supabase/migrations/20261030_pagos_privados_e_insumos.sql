-- Ya aplicado en producción (30/10/2026), en 4 pasos:
-- 1) pagos_privados_paciente, 2) capturer_scope_payments_toggle, 3) insumos_existencias,
-- 4) supply_save_reorder_point, 5) mis_secretarias_can_payments_v2.
--
-- Módulo 1: Pagos de pacientes (no ARS). El médico siempre puede registrar los suyos; una
-- secretaria solo si el médico la autorizó (can_payments, mismo patrón que can_book/can_whatsapp).
alter table public.capturer_scopes add column if not exists can_payments boolean not null default false;

create table if not exists public.patient_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  provider_id uuid not null references public.providers(id),
  patient_id uuid references public.patients(id),
  patient_name text not null,
  concept text not null,
  amount numeric not null check (amount > 0),
  method text not null check (method in ('efectivo','tarjeta','transferencia','cheque','otro')),
  paid_on date not null default current_date,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_by uuid references public.profiles(id),
  void_reason text
);
create index if not exists patient_payments_org_idx on public.patient_payments(organization_id, paid_on desc);
create index if not exists patient_payments_provider_idx on public.patient_payments(provider_id, paid_on desc);
alter table public.patient_payments enable row level security;
-- Sin políticas: todo el acceso pasa por las funciones SECURITY DEFINER de abajo, mismo
-- patrón ya usado por supply_usage/supply_catalog.

create or replace function app.payments_write_ok(p_provider uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $function$
  select exists (
    select 1 from public.providers p where p.id = p_provider and (
         app.can(p.organization_id, array['super_admin','admin'])
      or app.can(p.organization_id, array['client'])
      or exists (select 1 from public.capturer_scopes cs where cs.user_id = auth.uid() and cs.provider_id = p_provider and cs.can_payments)
    )
  );
$function$;

create or replace function app.payments_read_ok(p_org uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $function$
  select app.can(p_org, array['super_admin','admin','operations','billing','auditor','client'])
      or exists (select 1 from public.capturer_scopes cs where cs.user_id = auth.uid() and cs.organization_id = p_org);
$function$;

create or replace function public.patient_payments_board(p_org uuid)
returns jsonb
language plpgsql stable security definer
set search_path to ''
as $function$
begin
  if not app.payments_read_ok(p_org) then raise exception 'Sin permiso para los pagos de este cliente.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'providers', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', full_name, 'can_write', app.payments_write_ok(id)) order by full_name)
                   from public.providers where organization_id = p_org and is_active), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', pp.id, 'paid_on', pp.paid_on, 'provider', pr.full_name, 'provider_id', pp.provider_id,
                   'patient', pp.patient_name, 'concept', pp.concept, 'amount', pp.amount, 'method', pp.method, 'notes', pp.notes,
                   'by', pf.full_name, 'voided', pp.voided_at is not null, 'void_reason', pp.void_reason) order by pp.paid_on desc, pp.created_at desc)
                   from (select * from public.patient_payments where organization_id = p_org order by paid_on desc, created_at desc limit 60) pp
                   left join public.providers pr on pr.id = pp.provider_id left join public.profiles pf on pf.id = pp.created_by), '[]'::jsonb),
    'total_mes', coalesce((select sum(amount) from public.patient_payments where organization_id = p_org and voided_at is null
                   and date_trunc('month', paid_on) = date_trunc('month', current_date)), 0),
    'total_hoy', coalesce((select sum(amount) from public.patient_payments where organization_id = p_org and voided_at is null and paid_on = current_date), 0),
    'can_void', app.can(p_org, array['super_admin','admin','client']));
end
$function$;

create or replace function public.patient_payment_add(
  p_org uuid, p_provider uuid, p_patient_name text, p_concept text, p_amount numeric,
  p_method text, p_paid_on date default null, p_patient uuid default null, p_notes text default null
)
returns uuid
language plpgsql security definer
set search_path to ''
as $function$
declare v_id uuid;
begin
  if not app.payments_write_ok(p_provider) then raise exception 'Sin permiso para registrar pagos de este médico.' using errcode = '42501'; end if;
  if length(trim(coalesce(p_patient_name, ''))) < 2 then raise exception 'Indique el nombre del paciente.' using errcode = '22023'; end if;
  if length(trim(coalesce(p_concept, ''))) < 2 then raise exception 'Indique el concepto del servicio.' using errcode = '22023'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Indique un monto mayor a cero.' using errcode = '22023'; end if;
  if p_method not in ('efectivo','tarjeta','transferencia','cheque','otro') then raise exception 'Método de pago no reconocido.' using errcode = '22023'; end if;
  if coalesce(p_paid_on, current_date) > current_date then raise exception 'La fecha de pago no puede ser futura.' using errcode = '22023'; end if;
  if not exists (select 1 from public.providers where id = p_provider and organization_id = p_org) then
    raise exception 'El médico no pertenece a este cliente.' using errcode = '22023';
  end if;
  if p_patient is not null and not exists (select 1 from public.patients where id = p_patient and organization_id = p_org) then
    raise exception 'El paciente no pertenece a este cliente.' using errcode = '22023';
  end if;
  insert into public.patient_payments (organization_id, provider_id, patient_id, patient_name, concept, amount, method, paid_on, notes, created_by)
  values (p_org, p_provider, p_patient, trim(p_patient_name), trim(p_concept), p_amount, p_method, coalesce(p_paid_on, current_date), nullif(trim(coalesce(p_notes, '')), ''), auth.uid())
  returning id into v_id;
  return v_id;
end
$function$;

create or replace function public.patient_payment_void(p_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path to ''
as $function$
declare v_org uuid;
begin
  select organization_id into v_org from public.patient_payments where id = p_id;
  if v_org is null then raise exception 'Pago no encontrado.' using errcode = '22023'; end if;
  if not app.can(v_org, array['super_admin','admin','client']) then raise exception 'Solo un administrador o el médico puede anular un pago.' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'Indique el motivo de la anulación.' using errcode = '22023'; end if;
  update public.patient_payments set voided_at = now(), voided_by = auth.uid(), void_reason = trim(p_reason) where id = p_id and voided_at is null;
end
$function$;

-- El médico (o un administrador) autoriza can_payments desde el mismo flujo de "Mis secretarias".
create or replace function public.list_assistants(p_provider uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_org uuid;
begin
  select organization_id into v_org from public.providers where id = p_provider;
  if v_org is null then
    raise exception 'El médico no existe. Elija un médico de la lista.' using errcode = 'P0002';
  end if;
  if not app.can(v_org, array['super_admin','admin','client']) then
    raise exception 'Solo el médico o el Administrador pueden ver los permisos de las secretarias.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', cs.user_id, 'name', pr.full_name, 'active', pr.is_active,
                                                      'can_book', cs.can_book, 'can_whatsapp', cs.can_whatsapp, 'can_payments', cs.can_payments) order by pr.full_name)
                     from public.capturer_scopes cs join public.profiles pr on pr.id = cs.user_id
                    where cs.provider_id = p_provider), '[]'::jsonb);
end
$function$;

create or replace function public.set_assistant_permissions(p_user uuid, p_provider uuid, p_can_book boolean, p_can_whatsapp boolean, p_can_payments boolean default null)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_org uuid;
begin
  select organization_id into v_org from public.providers where id = p_provider;
  if v_org is null then
    raise exception 'El médico no existe. Elija un médico de la lista.' using errcode = 'P0002';
  end if;
  if not app.can(v_org, array['super_admin','admin','client']) then
    raise exception 'Solo el médico o el Administrador pueden cambiar los permisos de la secretaria.' using errcode = '42501';
  end if;
  if p_can_book is null or p_can_whatsapp is null then
    raise exception 'Indique cada permiso como sí o no.' using errcode = '22023';
  end if;
  update public.capturer_scopes set can_book = p_can_book, can_whatsapp = p_can_whatsapp, can_payments = coalesce(p_can_payments, can_payments)
   where user_id = p_user and provider_id = p_provider;
  if not found then
    raise exception 'Esa secretaria no está asignada a este médico. Asígnela primero desde Usuarios.' using errcode = 'P0002';
  end if;
end
$function$;

-- Módulo 2: existencias sobre el catálogo de insumos ya existente (no lo duplica, lo extiende).
alter table public.supplies add column if not exists stock_on_hand numeric not null default 0;
alter table public.supplies add column if not exists reorder_point numeric not null default 0;

create table if not exists public.supply_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  supply_id uuid not null references public.supplies(id),
  kind text not null check (kind in ('entrada','ajuste')),
  quantity numeric not null,
  moved_on date not null default current_date,
  reference text,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists supply_movements_org_idx on public.supply_movements(organization_id, moved_on desc);
alter table public.supply_movements enable row level security;

create or replace function public.supply_usage_add(p_org uuid, p_supply uuid, p_qty numeric, p_used_on date DEFAULT NULL::date, p_provider uuid DEFAULT NULL::uuid, p_patient text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  perform app.supply_access(p_org, 'consumo');
  if p_provider is not null and not app.consultorio_access(p_provider, true) then
    raise exception 'Sin acceso a ese médico: elija uno de los médicos que tiene asignados.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.supplies where id = p_supply and organization_id = p_org and is_active) then raise exception 'Elija un insumo activo del catálogo.' using errcode = '22023'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'Indique la cantidad usada.' using errcode = '22023'; end if;
  if coalesce(p_used_on, current_date) > current_date then raise exception 'La fecha de uso no puede ser futura.' using errcode = '22023'; end if;
  if p_provider is not null and not exists (select 1 from public.providers where id = p_provider and organization_id = p_org) then
    raise exception 'El médico no pertenece a este cliente.' using errcode = '22023';
  end if;
  insert into public.supply_usage (organization_id, provider_id, supply_id, used_on, quantity, patient_name, procedure_note, created_by)
  values (p_org, p_provider, p_supply, coalesce(p_used_on, current_date), p_qty, nullif(trim(coalesce(p_patient, '')), ''), nullif(trim(coalesce(p_note, '')), ''), auth.uid())
  returning id into v_id;
  update public.supplies set stock_on_hand = stock_on_hand - p_qty where id = p_supply;
  return v_id;
end
$function$;

create or replace function public.supply_movement_add(p_org uuid, p_supply uuid, p_kind text, p_qty numeric, p_moved_on date default null, p_reference text default null, p_notes text default null)
returns uuid
language plpgsql security definer
set search_path to ''
as $function$
declare v_id uuid; v_delta numeric;
begin
  perform app.supply_access(p_org, 'admin');
  if not exists (select 1 from public.supplies where id = p_supply and organization_id = p_org) then raise exception 'Insumo no encontrado en este cliente.' using errcode = '22023'; end if;
  if p_kind not in ('entrada','ajuste') then raise exception 'Tipo de movimiento no reconocido.' using errcode = '22023'; end if;
  if p_qty is null or p_qty = 0 then raise exception 'Indique una cantidad distinta de cero.' using errcode = '22023'; end if;
  if p_kind = 'entrada' and p_qty < 0 then raise exception 'Una entrada no puede ser negativa; use «ajuste» para corregir.' using errcode = '22023'; end if;
  if coalesce(p_moved_on, current_date) > current_date then raise exception 'La fecha no puede ser futura.' using errcode = '22023'; end if;
  v_delta := p_qty;
  insert into public.supply_movements (organization_id, supply_id, kind, quantity, moved_on, reference, notes, created_by)
  values (p_org, p_supply, p_kind, p_qty, coalesce(p_moved_on, current_date), nullif(trim(coalesce(p_reference, '')), ''), nullif(trim(coalesce(p_notes, '')), ''), auth.uid())
  returning id into v_id;
  update public.supplies set stock_on_hand = stock_on_hand + v_delta where id = p_supply;
  return v_id;
end
$function$;

create or replace function public.supply_catalog(p_org uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform app.supply_access(p_org, 'consumo');
  return jsonb_build_object(
    'supplies', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'name', s.name, 'unit', s.unit, 'unit_cost', s.unit_cost, 'billable', s.billable,
                   'procedure_id', s.procedure_id, 'procedure', p.description, 'is_active', s.is_active,
                   'stock_on_hand', s.stock_on_hand, 'reorder_point', s.reorder_point, 'low_stock', s.stock_on_hand <= s.reorder_point) order by s.name)
                   from public.supplies s left join public.procedures p on p.id = s.procedure_id where s.organization_id = p_org), '[]'::jsonb),
    'providers', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', full_name) order by full_name) from public.providers where organization_id = p_org and is_active), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('used_on', u.used_on, 'supply', s.name, 'quantity', u.quantity, 'patient', u.patient_name, 'provider', pr.full_name,
                   'by', pf.full_name) order by u.used_on desc, u.created_at desc)
                   from (select * from public.supply_usage where organization_id = p_org order by used_on desc, created_at desc limit 30) u
                   join public.supplies s on s.id = u.supply_id left join public.providers pr on pr.id = u.provider_id left join public.profiles pf on pf.id = u.created_by), '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(jsonb_build_object('moved_on', m.moved_on, 'supply', s.name, 'kind', m.kind, 'quantity', m.quantity, 'reference', m.reference, 'by', pf.full_name) order by m.moved_on desc, m.created_at desc)
                   from (select * from public.supply_movements where organization_id = p_org order by moved_on desc, created_at desc limit 30) m
                   join public.supplies s on s.id = m.supply_id left join public.profiles pf on pf.id = m.created_by), '[]'::jsonb),
    'low_stock_count', coalesce((select count(*) from public.supplies where organization_id = p_org and is_active and stock_on_hand <= reorder_point), 0),
    'can_admin', app.can(p_org, array['super_admin','admin','operations','client']));
end
$function$;

create or replace function public.supply_save(p_org uuid, p_id uuid, p_code text, p_name text, p_unit text DEFAULT 'unidad'::text, p_unit_cost numeric DEFAULT NULL::numeric, p_billable boolean DEFAULT true, p_procedure uuid DEFAULT NULL::uuid, p_active boolean DEFAULT true, p_reorder_point numeric DEFAULT NULL::numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  perform app.supply_access(p_org, 'admin');
  if length(trim(coalesce(p_code, ''))) < 1 or length(trim(coalesce(p_name, ''))) < 2 then raise exception 'Escriba el código y el nombre del insumo.' using errcode = '22023'; end if;
  if coalesce(p_billable, true) and p_procedure is null then
    raise exception 'Un insumo facturable necesita el servicio del catálogo con que se reclama a la ARS (o márquelo como no facturable).' using errcode = '22023';
  end if;
  if p_reorder_point is not null and p_reorder_point < 0 then raise exception 'El punto de reorden no puede ser negativo.' using errcode = '22023'; end if;
  if exists (select 1 from public.supplies where organization_id = p_org and lower(code) = lower(trim(p_code)) and id is distinct from p_id) then
    raise exception 'Ya existe un insumo con el código %.', trim(p_code) using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.supplies (organization_id, code, name, unit, unit_cost, billable, procedure_id, is_active, reorder_point)
    values (p_org, trim(p_code), trim(p_name), coalesce(nullif(trim(p_unit), ''), 'unidad'), p_unit_cost, coalesce(p_billable, true), case when coalesce(p_billable, true) then p_procedure end, coalesce(p_active, true), coalesce(p_reorder_point, 0))
    returning id into v_id;
  else
    update public.supplies set code = trim(p_code), name = trim(p_name), unit = coalesce(nullif(trim(p_unit), ''), 'unidad'), unit_cost = p_unit_cost,
           billable = coalesce(p_billable, true), procedure_id = case when coalesce(p_billable, true) then p_procedure end, is_active = coalesce(p_active, true),
           reorder_point = coalesce(p_reorder_point, reorder_point)
     where id = p_id and organization_id = p_org returning id into v_id;
    if v_id is null then raise exception 'Insumo no encontrado.' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end
$function$;
