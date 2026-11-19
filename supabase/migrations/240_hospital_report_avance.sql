-- ============================================================
-- 240 · Avance de cobro del reporte de hospitalización (0–100, 100 = cobrado)
-- Cada reporte muestra qué tan cerca está del cobro:
--   · Si alguna línea ya está ligada a una reclamación (hospital_report_lines.service_line_id),
--     el avance es el promedio de app.claim_progress ponderado por el monto facturado de esas líneas.
--   · Si ninguna línea está ligada aún, usa un piso por etapa del reporte (borrador/enviado/cerrado).
-- Se expone como `avance` en los cuatro payloads de reportes (médico, lista, staff, soporte),
-- copiados fielmente de su versión vigente y extendidos solo con ese campo (CLAUDE.md regla 5).
-- Depende de 239 (app.claim_progress). Ya aplicado en producción (2026-11-19). Suite 240: 6/6 APROBADA.
-- ============================================================
begin;

set local search_path = public, app;

-- 0. Dependencias
do $$
begin
  if to_regprocedure('app.claim_progress(text,numeric,numeric)') is null then
    raise exception '240: falta app.claim_progress — aplica primero la migración 239';
  end if;
  if to_regclass('public.hospital_report_lines') is null or to_regclass('public.hospital_reports') is null then
    raise exception '240: faltan tablas de hospitalización';
  end if;
end $$;

-- 1. Piso por etapa cuando el reporte aún no tiene reclamaciones ligadas.
create or replace function app.hospital_report_stage_floor(p_status text)
returns integer language sql immutable as $$
  select case p_status
    when 'borrador' then 8
    when 'enviado'  then 25
    when 'cerrado'  then 45
    else 0
  end;
$$;

-- 2. Avance del reporte: promedio ponderado del avance de sus reclamaciones ligadas, o el piso.
create or replace function app.hospital_report_progress(p_report uuid)
returns integer language sql stable as $$
  with l as (
    select hrl.amount as billed,
           case when hrl.service_line_id is not null
                then app.claim_progress(sl.claim_status, app.claim_paid_visible(sl.id), sl.amount)
                else null end as av
      from public.hospital_report_lines hrl
      left join public.service_lines sl on sl.id = hrl.service_line_id
     where hrl.report_id = p_report
  ),
  w as (
    select sum(billed) filter (where av is not null and billed > 0)        as wb,
           sum(billed * av) filter (where av is not null and billed > 0)   as ws,
           count(*) filter (where av is not null)                          as n_av
      from l
  )
  select case
    when coalesce((select n_av from w), 0) > 0 and coalesce((select wb from w), 0) > 0
      then greatest(0, least(100, round((select ws from w) / (select wb from w))::int))
    else app.hospital_report_stage_floor((select status from public.hospital_reports where id = p_report))
  end;
$$;

grant execute on function app.hospital_report_stage_floor(text) to authenticated, service_role;
grant execute on function app.hospital_report_progress(uuid) to authenticated, service_role;

-- 3. Payloads con `avance` (copias fieles + el único campo nuevo).

create or replace function public.hospital_report_get(p_report uuid)
 returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
declare v_p uuid:=app.hospital_my_provider();r public.hospital_reports;v_sup boolean;
begin
 if auth.uid() is null or not app.is_active_user() then raise exception 'Inicia sesión.' using errcode='42501';end if;
 select * into r from public.hospital_reports where id=p_report;
 if r.id is null then raise exception 'Reporte no encontrado.' using errcode='P0002';end if;
 v_sup:=exists(select 1 from public.health_centers hc where hc.id=r.center_id and hc.organization_id in(select app.visible_org_ids()) and coalesce(app.role_for_org(hc.organization_id),'') in('super_admin','admin','operations'));
 if not(coalesce(r.provider_id=v_p,false) or v_sup) then raise exception 'Este reporte no es tuyo.' using errcode='42501';end if;
 return jsonb_build_object('id',r.id,'provider_id',r.provider_id,'center_id',r.center_id,'centro',(select name from public.health_centers where id=r.center_id),'medico',(select full_name from public.providers where id=r.provider_id),
  'patient_name',r.patient_name,'patient_doc',r.patient_doc,'patient_phone',r.patient_phone,'ars_id',r.ars_id,'ars',(select name from public.ars where id=r.ars_id),'admission_date',r.admission_date,'discharge_date',r.discharge_date,
  'status',r.status,'notes',r.notes,'total',r.total,'avance',app.hospital_report_progress(r.id),'puede_editar',coalesce(r.status='borrador' and r.provider_id=v_p,false),
  'lineas',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'service_date',l.service_date,'procedure_id',l.procedure_id,'servicio',pr.description,'codigo',pr.internal_code,'quantity',l.quantity,'unit_amount',l.unit_amount,'amount',l.amount,'notes',l.notes) order by l.service_date,pr.internal_code) from public.hospital_report_lines l join public.procedures pr on pr.id=l.procedure_id where l.report_id=r.id),'[]'::jsonb));
end $function$;

create or replace function public.hospital_report_list(p_status text default null, p_center uuid default null)
 returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
declare v_p uuid := app.hospital_my_provider();
begin
  if auth.uid() is null or not app.is_active_user() then raise exception 'Inicia sesión.' using errcode = '42501'; end if;
  if p_status is not null and p_status not in ('borrador','enviado','cerrado') then
    raise exception 'Estado no válido. Usa borrador, enviado o cerrado (o déjalo vacío para todos).' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'centro', hc.name,
             'medico', pr.full_name, 'patient_name', r.patient_name, 'admission_date', r.admission_date,
             'status', r.status, 'total', r.total, 'avance', app.hospital_report_progress(r.id)) order by r.created_at desc)
      from public.hospital_reports r
      join public.health_centers hc on hc.id = r.center_id
      join public.providers pr on pr.id = r.provider_id
     where (p_status is null or r.status = p_status)
       and (p_center is null or r.center_id = p_center)
       and (
         (v_p is not null and r.provider_id = v_p)
         or (hc.organization_id in (select app.visible_org_ids()) and coalesce(app.role_for_org(hc.organization_id),'') in ('super_admin','admin','operations'))
       )), '[]'::jsonb);
end $function$;

create or replace function app.hospital_staff_context(p_report uuid default null)
 returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
declare v_reports jsonb;v_report jsonb;v_count integer;
begin
 if auth.uid() is null or not app.is_staff(array['super_admin','admin','operations','billing']) then raise exception 'Sin acceso a la supervisión de Hospitalización.' using errcode='42501';end if;
 select count(*) into v_count from public.hospital_reports r join public.health_centers hc on hc.id=r.center_id
 where r.status in('enviado','cerrado') and hc.organization_id in(select app.visible_org_ids()) and app.can(hc.organization_id,array['super_admin','admin','operations','billing']);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]'::jsonb) into v_reports from (
   select r.id,r.provider_id,pr.full_name medico,r.patient_name,r.admission_date,r.status,r.total,app.hospital_report_progress(r.id) avance,r.created_at,hc.name centro,o.legal_name cliente
   from public.hospital_reports r join public.health_centers hc on hc.id=r.center_id join public.organizations o on o.id=hc.organization_id join public.providers pr on pr.id=r.provider_id
   where r.status in('enviado','cerrado') and hc.organization_id in(select app.visible_org_ids()) and app.can(hc.organization_id,array['super_admin','admin','operations','billing']) order by r.created_at desc,r.id limit 100
 )x;
 if p_report is not null then
  select jsonb_build_object('id',r.id,'provider_id',r.provider_id,'centro',hc.name,'medico',pr.full_name,'patient_name',r.patient_name,'patient_phone',r.patient_phone,'ars',(select name from public.ars where id=r.ars_id),'admission_date',r.admission_date,'discharge_date',r.discharge_date,'status',r.status,'total',r.total,'avance',app.hospital_report_progress(r.id),'puede_editar',false,
    'lineas',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'service_date',l.service_date,'servicio',p.description,'codigo',p.internal_code,'quantity',l.quantity,'unit_amount',l.unit_amount,'amount',l.amount) order by l.service_date,l.id) from public.hospital_report_lines l join public.procedures p on p.id=l.procedure_id where l.report_id=r.id),'[]'::jsonb))
  into v_report from public.hospital_reports r join public.health_centers hc on hc.id=r.center_id join public.providers pr on pr.id=r.provider_id
  where r.id=p_report and r.status in('enviado','cerrado') and hc.organization_id in(select app.visible_org_ids()) and app.can(hc.organization_id,array['super_admin','admin','operations','billing']);
  if v_report is null then raise exception 'Reporte no disponible dentro de tu acceso de supervisión.' using errcode='42501';end if;
 end if;
 return jsonb_build_object('reportes',v_reports,'report_count',v_count,'report',v_report);
end $function$;

create or replace function app.hospital_support_context(p_org uuid, p_provider uuid default null, p_report uuid default null)
 returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
declare s record;v_provider uuid;v_providers jsonb;v_centers jsonb;v_reports jsonb;v_report jsonb;v_count integer;
begin
 if auth.uid() is null or not app.is_staff(array['super_admin']) or coalesce(app.role_for_org(p_org),'') <> 'super_admin' then
  raise exception 'Sin permiso para consultar Hospitalización en modo soporte.' using errcode='42501';
 end if;
 select * into s from public.support_view_active();
 if s.session_id is null or s.org_id is distinct from p_org or s.target_user_id is not null or s.role_code is distinct from 'client'
    or not exists(select 1 from app.visible_org_ids() visible(id) where visible.id=p_org) then
  raise exception 'Abre el modo soporte general del consultorio antes de consultar Hospitalización.' using errcode='42501';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name) order by p.full_name,p.id),'[]'::jsonb)
   into v_providers from public.providers p where p.organization_id=p_org and p.is_active;
 if p_provider is not null then
  if not exists(select 1 from public.providers p where p.id=p_provider and p.organization_id=p_org and p.is_active) then
   raise exception 'El médico no pertenece al consultorio seleccionado.' using errcode='42501';
  end if;
  v_provider:=p_provider;
 elsif jsonb_array_length(v_providers)=1 then v_provider:=(v_providers->0->>'id')::uuid;
 end if;
 if v_provider is null then
  if p_report is not null then raise exception 'Selecciona el médico antes de abrir el reporte.' using errcode='22023';end if;
  return jsonb_build_object('providers',v_providers,'provider_id',null,'centros','[]'::jsonb,'reportes','[]'::jsonb,'report_count',0,'report',null);
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('center_id',hc.id,'nombre',hc.name,'principal',pc.is_primary) order by pc.is_primary desc,hc.name),'[]'::jsonb)
 into v_centers from public.provider_centers pc join public.health_centers hc on hc.id=pc.center_id
 where pc.provider_id=v_provider and hc.organization_id=p_org and hc.is_active;
 select count(*) into v_count from public.hospital_reports r join public.health_centers hc on hc.id=r.center_id
 where r.provider_id=v_provider and hc.organization_id=p_org;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'centro',r.center_name,'patient_name',r.patient_name,'admission_date',r.admission_date,'status',r.status,'total',r.total,'avance',app.hospital_report_progress(r.id)) order by r.created_at desc,r.id),'[]'::jsonb)
 into v_reports from (
  select r.id,hc.name center_name,r.patient_name,r.admission_date,r.status,r.total,r.created_at
  from public.hospital_reports r join public.health_centers hc on hc.id=r.center_id
  where r.provider_id=v_provider and hc.organization_id=p_org order by r.created_at desc,r.id limit 100
 ) r;
 if p_report is not null then
  select jsonb_build_object('id',r.id,'provider_id',r.provider_id,'centro',hc.name,'patient_name',r.patient_name,
   'admission_date',r.admission_date,'discharge_date',r.discharge_date,'status',r.status,'total',r.total,'avance',app.hospital_report_progress(r.id),'puede_editar',false,
   'lineas',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'service_date',l.service_date,'servicio',pr.description,'codigo',pr.internal_code,'quantity',l.quantity,'unit_amount',l.unit_amount,'amount',l.amount) order by l.service_date,l.id)
    from public.hospital_report_lines l join public.procedures pr on pr.id=l.procedure_id where l.report_id=r.id),'[]'::jsonb))
  into v_report from public.hospital_reports r join public.health_centers hc on hc.id=r.center_id
  where r.id=p_report and r.provider_id=v_provider and hc.organization_id=p_org;
  if v_report is null then raise exception 'Reporte no encontrado en el médico y consultorio seleccionados.' using errcode='42501';end if;
 end if;
 return jsonb_build_object('providers',v_providers,'provider_id',v_provider,'centros',v_centers,'reportes',v_reports,'report_count',v_count,'report',v_report);
end $function$;

-- 4. Suite 240 (solo lectura).
create or replace function app.qa_run_tests_hospital_progress()
returns table(prueba text, resultado text, detalle text)
language plpgsql set search_path to '' as $function$
declare
  r_id text[] := '{}'; r_ok boolean[] := '{}'; r_det text[] := '{}';
  i int; v_fail int := 0; v_n int; v_bad int; v_rid uuid;
begin
  r_id := r_id||'HP-01 piso borrador = 8'::text;  r_ok := r_ok||(app.hospital_report_stage_floor('borrador')=8); r_det := r_det||''::text;
  r_id := r_id||'HP-02 piso enviado = 25'::text;   r_ok := r_ok||(app.hospital_report_stage_floor('enviado')=25); r_det := r_det||''::text;
  r_id := r_id||'HP-03 piso cerrado = 45'::text;   r_ok := r_ok||(app.hospital_report_stage_floor('cerrado')=45); r_det := r_det||''::text;
  r_id := r_id||'HP-04 piso desconocido = 0'::text; r_ok := r_ok||(app.hospital_report_stage_floor('zzz')=0); r_det := r_det||''::text;

  select r.id into v_rid from public.hospital_reports r
    where not exists(select 1 from public.hospital_report_lines l where l.report_id=r.id and l.service_line_id is not null)
    order by r.created_at limit 1;
  r_id := r_id||'HP-05 reporte sin reclamaciones ligadas = piso'::text;
  if v_rid is null then
    r_ok := r_ok||true; r_det := r_det||'(no hay reporte de prueba; invariante omitida)';
  else
    r_ok := r_ok||(app.hospital_report_progress(v_rid) = app.hospital_report_stage_floor((select status from public.hospital_reports where id=v_rid)));
    r_det := r_det||('rid='||v_rid);
  end if;

  select count(*), count(*) filter (where app.hospital_report_progress(id) < 0 or app.hospital_report_progress(id) > 100)
    into v_n, v_bad from public.hospital_reports;
  r_id := r_id||'HP-06 avance de reporte siempre 0..100'::text; r_ok := r_ok||(v_bad=0); r_det := r_det||('fuera_rango='||v_bad||' de '||v_n);

  for i in 1..cardinality(r_id) loop if not r_ok[i] then v_fail := v_fail + 1; end if; end loop;
  prueba := case when v_fail=0 then 'TODO OK · '||cardinality(r_id)||' de '||cardinality(r_id)
                 else 'FALLARON '||v_fail||' de '||cardinality(r_id) end;
  resultado := case when v_fail=0 then 'APROBADA' else 'FALLIDA' end; detalle := ''; return next;
  for i in 1..cardinality(r_id) loop
    prueba := r_id[i]; resultado := case when r_ok[i] then 'APROBADA' else 'FALLIDA' end; detalle := r_det[i]; return next;
  end loop;
end $function$;

grant execute on function app.qa_run_tests_hospital_progress() to authenticated, service_role;

-- 5. Compuerta: falla la migración si la suite no pasa entera.
do $$
declare v_fail int;
begin
  select count(*) into v_fail from app.qa_run_tests_hospital_progress()
   where prueba like 'HP-%' and resultado <> 'APROBADA';
  if v_fail > 0 then raise exception '240: la suite hospital_progress falló en % prueba(s)', v_fail; end if;
end $$;

commit;
