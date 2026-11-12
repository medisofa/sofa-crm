-- SOFA · 5.31.0 · «Mi cuenta con SOFA» ampliada: pagos recibidos, bitácora de actividad y
-- resumen de ARS que el cliente ya tiene en uso. Es un complemento de client_account que no
-- toca su contrato; aquí solo se agregan datos de lectura.
-- SECURITY DEFINER con la misma guarda que client_account: staff visible o rol client del org.
--
-- Ya aplicado en producción (mcp__Supabase__apply_migration 12/11/2026).
create or replace function public.client_account_detail(p_org uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_staff boolean := app.case_staff(false) and p_org in (select app.visible_org_ids());
  v_result jsonb;
begin
  if not (v_staff or app.can(p_org, array['client'])) then
    raise exception 'Sin acceso a la cuenta de este cliente.' using errcode = '42501';
  end if;

  with pagos as (
    select p.paid_on, p.amount, p.method, p.reference, i.folio, i.period, p.created_at
      from public.sofa_invoice_payments p
      join public.sofa_invoices i on i.id = p.sofa_invoice_id
     where p.organization_id = p_org
     order by p.paid_on desc, p.created_at desc
     limit 60
  ),
  eventos as (
    -- avances visibles de casos de servicio
    select e.at, 'caso' as kind, c.folio as ref, c.title as title,
           'Avance en «' || c.title || '»: ' || coalesce(e.note, app.case_status_label(e.to_status)) as description,
           e.by_user
      from public.sofa_service_case_events e
      join public.sofa_service_cases c on c.id = e.case_id
     where c.organization_id = p_org and e.visible
     order by e.at desc
     limit 30
  ),
  facturas_emitidas as (
    -- factura nueva o anulada
    select i.created_at as at, 'factura' as kind, i.folio as ref, null::text as title,
           case when i.status = 'anulada'
                then 'Factura ' || coalesce(i.folio, '—') || ' anulada'
                else 'Factura ' || coalesce(i.folio, '—') || ' emitida por ' || to_char(i.total, 'FM999,999,990.00') end as description,
           null::uuid as by_user
      from public.sofa_invoices i
     where i.organization_id = p_org
     order by i.created_at desc
     limit 30
  ),
  pagos_feed as (
    select p.created_at as at, 'pago' as kind, p.reference as ref, null::text as title,
           'Pago aplicado por ' || to_char(p.amount, 'FM999,999,990.00') ||
             coalesce(' · ' || p.method, '') || coalesce(' (ref. ' || p.reference || ')', '') as description,
           null::uuid as by_user
      from public.sofa_invoice_payments p
     where p.organization_id = p_org
     order by p.created_at desc
     limit 30
  ),
  feed as (
    select * from eventos
    union all select * from facturas_emitidas
    union all select * from pagos_feed
    order by at desc
    limit 50
  ),
  ars_rows as (
    -- Cada par (médico, ARS) con estado del código
    select pr.full_name as provider_name, a.name as ars_name,
           coalesce(c.status, 'sin_codigo') as status,
           c.requested_on, c.granted_on,
           case when c.status in ('solicitado','pendiente_respuesta')
                 and current_date - coalesce(c.requested_on, c.status_changed_at::date) > 30
                then true else false end as alert
      from public.providers pr
      join public.ars a on a.is_active
      left join public.provider_ars_codes c on c.provider_id = pr.id and c.ars_id = a.id
     where pr.organization_id = p_org and pr.is_active
  ),
  ars_resumen as (
    select
      (select count(*) from ars_rows where status = 'aprobado') as con_codigo,
      (select count(*) from ars_rows where status in ('solicitado','pendiente_respuesta','en_preparacion')) as en_tramite,
      (select count(*) from ars_rows where alert) as alertas,
      (select jsonb_agg(jsonb_build_object('ars', ars_name, 'provider', provider_name, 'status', status, 'alert', alert)
                        order by alert desc, status)
         from (select distinct on (ars_name, provider_name) ars_name, provider_name, status, alert, requested_on
                 from ars_rows where status <> 'sin_codigo'
                 order by ars_name, provider_name, requested_on desc nulls last) sub) as items
  )
  select jsonb_build_object(
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'paid_on', paid_on, 'amount', amount, 'method', method, 'reference', reference,
        'folio', folio, 'period', period
      ) order by paid_on desc) from pagos), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object(
        'at', at, 'kind', kind, 'ref', ref, 'title', title, 'description', description
      ) order by at desc) from feed), '[]'::jsonb),
    'ars_summary', (select jsonb_build_object(
        'con_codigo', con_codigo, 'en_tramite', en_tramite, 'alertas', alertas,
        'items', coalesce(items, '[]'::jsonb)
      ) from ars_resumen)
  ) into v_result;

  return v_result;
end
$$;

revoke all on function public.client_account_detail(uuid) from public;
grant execute on function public.client_account_detail(uuid) to authenticated;

comment on function public.client_account_detail(uuid) is
  'Complemento de client_account: pagos recibidos, bitácora de actividad (casos, facturas, pagos) y resumen de ARS en uso.';
