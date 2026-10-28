-- 224 · Tiempos por etapa de clientes reales (excluye organizaciones DEMO)
begin;

create or replace view public.v_stage_times_real as
with l as materialized (
  select x.id,
         x.created_at as m01,
         s.ars_id
    from public.service_lines x
    join public.submissions s on s.id=x.submission_id
    join public.organizations o on o.id=s.organization_id
   where x.created_at >= now() - interval '365 days'
     and coalesce(o.is_demo,false)=false
),
h as materialized (
  select hh.service_line_id,
         min(hh.changed_at) filter(where hh.to_status='retirada') as m03,
         min(hh.changed_at) filter(where hh.to_status='radicada') as m08,
         min(hh.changed_at) filter(where hh.to_status='pagada') as m13,
         min(hh.changed_at) filter(where hh.to_status='cerrada') as m14
    from public.claim_status_history hh
    join l on l.id=hh.service_line_id
   group by hh.service_line_id
),
au as materialized (
  select a.service_line_id,min(a.audited_at) as m05
    from public.claim_audits a
    join l on l.id=a.service_line_id
   where a.result='validada'
   group by a.service_line_id
),
g as materialized (
  select gi.service_line_id,min(gl.notified_on)::timestamptz as m10
    from public.glosa_items gi
    join l on l.id=gi.service_line_id
    join public.glosas gl on gl.id=gi.glosa_id
   group by gi.service_line_id
),
gr as materialized (
  select gi.service_line_id,min(gh.changed_at) as m11
    from public.glosa_items gi
    join l on l.id=gi.service_line_id
    join public.glosa_status_history gh on gh.glosa_id=gi.glosa_id
   where gh.to_status=any(array['apelada','aceptada','revertida','parcial'])
   group by gi.service_line_id
),
pg as materialized (
  select pl.service_line_id,min(p.paid_on)::timestamptz as m12
    from public.payment_line_allocations pl
    join l on l.id=pl.service_line_id
    join public.payments p on p.id=pl.payment_id
   where pl.superseded_at is null and pl.amount>0
   group by pl.service_line_id
),
d as (
  select l.ars_id,
         extract(epoch from (h.m03-l.m01))/86400::numeric as captura_retiro,
         extract(epoch from (au.m05-h.m03))/86400::numeric as retiro_validacion,
         extract(epoch from (h.m08-au.m05))/86400::numeric as validacion_radicacion,
         extract(epoch from (pg.m12-h.m08))/86400::numeric as radicacion_primer_pago,
         extract(epoch from (h.m13-h.m08))/86400::numeric as radicacion_pago_total,
         extract(epoch from (gr.m11-g.m10))/86400::numeric as glosa_respuesta,
         extract(epoch from (coalesce(h.m13,h.m14)-l.m01))/86400::numeric as ciclo_total
    from l
    left join h on h.service_line_id=l.id
    left join au on au.service_line_id=l.id
    left join g on g.service_line_id=l.id
    left join gr on gr.service_line_id=l.id
    left join pg on pg.service_line_id=l.id
)
select d.ars_id,
       coalesce(a.name,'Todas las ARS') as ars_name,
       count(*) as claims,
       round(avg(d.captura_retiro),1) as captura_retiro,
       round(avg(d.retiro_validacion),1) as retiro_validacion,
       round(avg(d.validacion_radicacion),1) as validacion_radicacion,
       round(avg(d.radicacion_primer_pago),1) as radicacion_primer_pago,
       round(avg(d.radicacion_pago_total),1) as radicacion_pago_total,
       round(avg(d.glosa_respuesta),1) as glosa_respuesta,
       round(avg(d.ciclo_total),1) as ciclo_total,
       round((percentile_cont(0.5) within group(order by d.radicacion_primer_pago::double precision))::numeric,1) as mediana_radicacion_pago
  from d
  left join public.ars a on a.id=d.ars_id
 group by grouping sets ((d.ars_id,a.name),());

grant select on public.v_stage_times_real to authenticated;

commit;
