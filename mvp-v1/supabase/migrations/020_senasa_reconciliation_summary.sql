-- SOFA · Resumen de conciliación de certificado SeNaSa
create or replace function public.senasa_certificate_reconciliation(p_certificate uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  with c as (
    select * from public.senasa_payment_certificates
    where id=p_certificate and organization_id in (select app.visible_org_ids())
  ),
  a as (
    select x.*
    from public.senasa_certificate_authorizations x
    join c on c.id=x.certificate_id
  )
  select jsonb_build_object(
    'certificate_id',(select id from c),
    'status',(select status from c),
    'ovp',(select ovp_number from c),
    'total_payable',(select total_payable from c),
    'authorizations',count(*),
    'matched',count(*) filter(where match_status='coincidencia'),
    'differences',count(*) filter(where match_status='diferencia'),
    'not_found',count(*) filter(where match_status='no_encontrada'),
    'objected_total',coalesce(sum(objected_amount),0),
    'paid_total',coalesce(sum(paid_amount),0),
    'claimed_total',coalesce(sum(claimed_amount),0),
    'ready_to_apply',count(*)>0 and count(*) filter(where match_status in ('diferencia','no_encontrada'))=0
  )
  from a
$$;

revoke all on function public.senasa_certificate_reconciliation(uuid) from public,anon;
grant execute on function public.senasa_certificate_reconciliation(uuid) to authenticated;
