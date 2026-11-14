-- SOFA · 5.35.0 · Dashboard operativo del super_admin/admin: alertas, break-even, pipeline.
-- Complementa direction_board (que mide el negocio) con datos de la semana accionables.
-- La v2 (abajo) corrige el join con `leads` (no tiene columna status, sí converted_org_id).
--
-- Ya aplicado en producción (mcp__Supabase__apply_migration 14/11/2026, revisión v2).
create or replace function public.direction_operations_overview()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  v_breakeven_target int := 60;
  v_clients_active int;
  v_clients_total int;
  v_invoices_due_soon jsonb;
  v_clients_at_risk jsonb;
  v_clients_activating jsonb;
  v_pipeline jsonb;
  v_billing jsonb;
begin
  if not app.is_staff(array['super_admin','admin']) then
    raise exception 'Solo el Super Admin o el Administrador ven este tablero.' using errcode = '42501';
  end if;

  select count(*) into v_clients_active
  from public.organizations o
  where o.kind = 'client'
    and exists (select 1 from public.providers p where p.organization_id = o.id and p.is_active);

  select count(*) into v_clients_total
  from public.organizations where kind = 'client';

  with inv as (
    select i.id, i.folio, i.total,
           coalesce((select sum(p.amount) from public.sofa_invoice_payments p where p.sofa_invoice_id = i.id), 0) as pagado,
           i.due_on, o.legal_name as client, o.id as client_id
      from public.sofa_invoices i
      join public.organizations o on o.id = i.organization_id
     where i.status not in ('anulada','pagada')
       and i.due_on between current_date and current_date + interval '7 days'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'folio', folio, 'client', client, 'client_id', client_id,
    'saldo', greatest(total - pagado, 0),
    'due_on', due_on::text,
    'days_left', (due_on - current_date)
  ) order by due_on), '[]'::jsonb)
    into v_invoices_due_soon
    from inv where (total - pagado) > 0.005;

  with ultima as (
    select o.id, o.legal_name, o.created_at,
           (select max(v.service_date) from public.v_claims v where v.organization_id = o.id) as ult_servicio,
           (select max(u.last_sign_in_at) from public.organization_users ou join auth.users u on u.id = ou.user_id
            where ou.organization_id = o.id) as ult_login
      from public.organizations o
     where o.kind = 'client'
       and exists (select 1 from public.providers p where p.organization_id = o.id and p.is_active)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'client', legal_name, 'client_id', id,
    'ult_servicio', ult_servicio::text,
    'ult_login', coalesce(ult_login::text, '—'),
    'dias_sin_servicio', case when ult_servicio is null then null else (current_date - ult_servicio) end,
    'razon', case
      when ult_servicio is null and ult_login is null then 'sin actividad'
      when ult_servicio is null then 'nunca ha radicado'
      when (current_date - ult_servicio) > 15 then 'inactivo desde hace >15 días'
      when ult_login is null or (now() - ult_login) > interval '30 days' then 'sin login reciente'
      else null end
  ) order by (current_date - coalesce(ult_servicio, created_at::date)) desc), '[]'::jsonb)
    into v_clients_at_risk
    from ultima where
      (ult_servicio is null and ult_login is null)
      or (ult_servicio is null and (now() - created_at) > interval '14 days')
      or (ult_servicio is not null and (current_date - ult_servicio) > 15)
      or (ult_servicio is not null and (ult_login is null or (now() - ult_login) > interval '30 days'));

  with act as (
    select o.id, o.legal_name, o.created_at::date as alta,
           (select count(*) from public.v_claims v where v.organization_id = o.id) as reclamaciones,
           (select count(*) from public.organization_users ou where ou.organization_id = o.id and ou.is_active) as users_count
      from public.organizations o
     where o.kind = 'client'
       and o.created_at > now() - interval '30 days'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'client', legal_name, 'client_id', id, 'alta', alta::text,
    'dias', (current_date - alta), 'users', users_count, 'reclamaciones', reclamaciones
  ) order by alta desc), '[]'::jsonb)
    into v_clients_activating
    from act where reclamaciones = 0;

  select jsonb_build_object(
    'clientes_pagando', (select count(distinct organization_id) from public.sofa_invoices where status in ('pagada','pagada_parcial')),
    'facturas_emitidas', (select count(*) from public.sofa_invoices where status not in ('anulada')),
    'facturas_cobradas', (select count(*) from public.sofa_invoices where status = 'pagada'),
    'organizaciones_cliente', v_clients_total,
    'organizaciones_activas', v_clients_active,
    'prospectos', coalesce((select count(*) from public.leads where converted_org_id is null), 0),
    'leads_convertidos', coalesce((select count(*) from public.leads where converted_org_id is not null), 0)
  ) into v_pipeline;

  select jsonb_build_object(
    'mes_actual_mrr', coalesce((select sum(total) from public.sofa_invoices where status not in ('anulada') and date_trunc('month', issued_on) = date_trunc('month', current_date)), 0),
    'mes_actual_cobrado', coalesce((select sum(p.amount) from public.sofa_invoice_payments p where date_trunc('month', p.paid_on) = date_trunc('month', current_date)), 0),
    'total_vencido', coalesce((select sum(greatest(i.total - coalesce((select sum(p.amount) from public.sofa_invoice_payments p where p.sofa_invoice_id = i.id), 0), 0))
                              from public.sofa_invoices i where i.status not in ('anulada','pagada') and i.due_on < current_date), 0)
  ) into v_billing;

  return jsonb_build_object(
    'breakeven_target', v_breakeven_target,
    'clients_active', v_clients_active,
    'clients_total', v_clients_total,
    'gap_to_breakeven', greatest(v_breakeven_target - v_clients_active, 0),
    'pct_to_breakeven', least(100, round(100.0 * v_clients_active / v_breakeven_target)),
    'invoices_due_soon', v_invoices_due_soon,
    'clients_at_risk', v_clients_at_risk,
    'clients_activating', v_clients_activating,
    'pipeline', v_pipeline,
    'billing', v_billing,
    'generated_at', now()
  );
end
$$;

revoke all on function public.direction_operations_overview() from public;
revoke execute on function public.direction_operations_overview() from anon;
grant execute on function public.direction_operations_overview() to authenticated;

comment on function public.direction_operations_overview() is
  'Tablero operativo semanal del Super Admin/Admin: alertas, break-even, pipeline, facturación agregada.';
