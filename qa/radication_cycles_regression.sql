-- SOFA · Regresión de ciclos sugeridos (solo lectura, ejecutar DESPUÉS de migración 212)

-- A. Contrato estructural
select
  max(case when column_name='submission_id' then is_nullable end) as submission_nullable,
  count(*) filter (where column_name in ('provider_id','ars_id')) as direct_cycle_keys
from information_schema.columns
where table_schema='public' and table_name='service_lines';

-- Aceptación: submission_nullable='YES' y direct_cycle_keys=2.

-- B. Ninguna reclamación histórica pierde médico/ARS después del backfill.
select count(*) as claims_missing_cycle_keys
from public.service_lines
where provider_id is null or ars_id is null;

-- Aceptación: 0 para los datos existentes.

-- C. Las reclamaciones sin lote siguen visibles en v_claims.
select
  count(*) filter (where l.submission_id is null) as unassigned_base,
  count(*) filter (where v.submission_id is null) as unassigned_view
from public.service_lines l
left join public.v_claims v on v.id=l.id;

-- Aceptación: ambos conteos coinciden.

-- D. Los ciclos sugeridos se agrupan por cliente + médico + ARS + mes.
select organization_id, provider_id, ars_id, period, claims, ready, pending, claimed, ready_amount, prior_cycle
from public.v_claim_cycle_suggestions
order by period desc, provider_name, ars_name;

-- E. No debe existir una reclamación asignada a un lote cuyo médico/ARS contradiga su clave estructural.
select count(*) as assignment_mismatch
from public.service_lines l
join public.submissions s on s.id=l.submission_id
where coalesce(l.provider_id,s.provider_id)<>s.provider_id
   or coalesce(l.ars_id,s.ars_id)<>s.ars_id;

-- Aceptación: 0.

-- F. Confirmar que las radicaciones existentes conservan exactamente sus líneas.
select s.id, s.folio, count(l.id) as lines, coalesce(sum(l.amount),0) as amount
from public.submissions s
left join public.service_lines l on l.submission_id=s.id
group by s.id,s.folio
order by s.created_at desc
limit 100;

-- G. Seguridad de capturador: helper debe conocer reclamaciones sin lote.
select pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='app' and p.proname='capturer_line_ok';

-- H. Funciones nuevas instaladas.
select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('capture_claim_unassigned','create_submission_from_claims')
order by p.proname;
