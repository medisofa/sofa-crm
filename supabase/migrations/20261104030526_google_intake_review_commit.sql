-- Atomic external-claim creation and source-row idempotency; no changes to capture APIs.
create table app.google_intake_commits (
 record_id text primary key check(length(record_id) between 3 and 160),
 created_by uuid not null references public.profiles(id),
 organization_id uuid not null references public.organizations(id),
 payload_hash bytea not null,
 claim_id uuid not null, -- Deliberately no FK: existing authorized claim removal must remain possible.
 result jsonb not null,
 removed boolean not null default false,
 created_at timestamptz not null default now()
);
create index google_intake_commits_creator_idx on app.google_intake_commits(created_by);
create index google_intake_commits_org_idx on app.google_intake_commits(organization_id);
alter table app.google_intake_commits enable row level security;
create policy google_intake_commits_owner on app.google_intake_commits for select to authenticated
 using(created_by=(select auth.uid()) and organization_id in (select app.visible_org_ids()));
revoke all on app.google_intake_commits from public,anon,authenticated;

create function public.google_intake_review_v1(p_record_id text,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_provider public.providers; v_old app.google_intake_commits; v_result jsonb;
 v_org uuid; v_ars uuid; v_proc uuid; v_date date; v_member text; v_auth text;
 v_reason text; v_amount numeric; v_tariff public.tariffs; v_duplicate jsonb; v_hash bytea; v_folio text;
begin
 if auth.uid() is null or not app.is_staff(array['super_admin','admin','operations','billing']) then
  raise exception using errcode='42501',message='Su usuario no puede revisar cargas externas.';
 end if;
 if length(btrim(coalesce(p_record_id,''))) not between 3 and 160 or p_data is null or jsonb_typeof(p_data)<>'object' then
  raise exception using errcode='22023',message='Solicitud de revisión inválida.';
 end if;
 if p_action='remove' then
  select * into v_old from app.google_intake_commits where record_id=p_record_id for update;
  if not found or v_old.created_by<>auth.uid() or v_old.organization_id not in(select app.visible_org_ids()) then
   raise exception using errcode='42501',message='No tiene acceso a esta fila de carga.';
  end if;
  if v_old.removed then return v_old.result||jsonb_build_object('removed',true);end if;
  v_reason:=btrim(coalesce(p_data->>'reason',''));
  if length(v_reason)<10 then raise exception using errcode='22023',message='Indique el motivo para eliminar (mínimo 10 caracteres).';end if;
  if exists(select 1 from public.documents where service_line_id=v_old.claim_id) then
   raise exception using errcode='23514',message='La reclamación tiene documentos. Gestione su retiro desde la radicación para conservar la trazabilidad documental.';
  end if;
  v_result:=public.remove_service_line(v_old.claim_id,v_reason);
  insert into public.audit_log(user_id,organization_id,table_name,record_id,operation,old_values,new_values)
   values(auth.uid(),v_old.organization_id,'google_claim_intake',p_record_id,'ELIMINACION_CARGA_EXTERNA',v_old.result,jsonb_build_object('claim_id',v_old.claim_id,'removed',true,'reason',v_reason));
  update app.google_intake_commits set removed=true where record_id=p_record_id;
  return v_old.result||jsonb_build_object('removed',true);
 end if;
 if p_action not in ('duplicates','commit') or p_action is null then
  raise exception using errcode='22023',message='Acción de revisión inválida.';
 end if;
 select * into v_provider from public.providers where id=(p_data->>'provider')::uuid and is_active;
 if not found then raise exception using errcode='22023',message='Médico no encontrado o inactivo.';end if;
 v_org:=v_provider.organization_id;
 if v_org not in(select app.visible_org_ids()) or coalesce(app.claim_access_role(v_org,v_provider.id),'') not in ('super_admin','admin','billing','operations','assistant','client','capturer') then
  raise exception using errcode='42501',message='No tiene acceso a las reclamaciones de este médico.';
 end if;
 v_ars:=(p_data->>'ars')::uuid;v_proc:=(p_data->>'procedure')::uuid;v_date:=(p_data->>'service_date')::date;
 v_member:=btrim(coalesce(p_data->>'member',''));v_auth:=nullif(btrim(coalesce(p_data->>'authorization','')),'');
 if v_ars is null or v_proc is null or v_date is null or length(v_member)<3 then
  raise exception using errcode='22023',message='Complete ARS, servicio, fecha y afiliado antes de revisar duplicados.';
 end if;
 if p_action='duplicates' then
  select * into v_old from app.google_intake_commits where record_id=p_record_id and created_by=auth.uid() and organization_id=v_org;
  if found then return jsonb_build_object('duplicate',false,'already_imported',true,'result',v_old.result,
    'removed',v_old.removed or not exists(select 1 from public.service_lines where id=v_old.claim_id));end if;
 end if;
 if p_action='commit' then
  if coalesce((p_data->>'review_confirmed')::boolean,false) is not true then
   raise exception using errcode='22023',message='La fila debe estar revisada y aprobada antes de importar.';
  end if;
  v_hash:=sha256(convert_to(p_data::text,'UTF8'));
  perform pg_advisory_xact_lock(hashtextextended('google-row:'||p_record_id,0));
  select * into v_old from app.google_intake_commits where record_id=p_record_id;
  if found then
   if v_old.created_by<>auth.uid() or v_old.organization_id<>v_org then raise exception using errcode='42501',message='La fila pertenece a otra carga.';end if;
   if v_old.payload_hash<>v_hash then raise exception using errcode='40001',message='Esta fila ya fue importada con otros valores. Revise la reclamación existente.';end if;
   return v_old.result||jsonb_build_object('removed',v_old.removed or not exists(select 1 from public.service_lines where id=v_old.claim_id));
  end if;
  -- Serializes commits through this new intake flow for the same organization/ARS.
  perform pg_advisory_xact_lock(hashtextextended('google-scope:'||v_org::text||':'||v_ars::text,0));
 end if;
 select coalesce(jsonb_agg(d.claim_folio),'[]'::jsonb) into v_duplicate from (
  select l.claim_folio from public.service_lines l join public.submissions s on s.id=l.submission_id
  where l.organization_id=v_org and s.ars_id=v_ars and s.status not in ('rechazada','cerrada')
   and ((l.member_number=v_member and l.service_date=v_date and l.procedure_id=v_proc)
    or (v_auth is not null and l.authorization_number=v_auth)) limit 5) d;
 if p_action='duplicates' then return jsonb_build_object('duplicate',jsonb_array_length(v_duplicate)>0,'folios',v_duplicate);end if;
 if jsonb_array_length(v_duplicate)>0 then raise exception using errcode='23505',message='Posible reclamación duplicada. Revise los folios existentes antes de continuar.';end if;
 v_amount:=nullif(p_data->>'amount','')::numeric;
 if v_amount is not null and (v_amount<=0 or v_amount*100<>trunc(v_amount*100) or v_amount::text in ('NaN','Infinity','-Infinity')) then
  raise exception using errcode='22023',message='El monto debe ser mayor que cero.';
 end if;
 v_tariff:=app.contract_tariff_for(v_provider.id,v_ars,v_proc,v_date);
 if v_tariff.id is null or (p_data->>'expected_tariff')::numeric is distinct from v_tariff.amount then
  raise exception using errcode='40001',message='La tarifa cambió o ya no está vigente. Vuelva a validar y aprobar la fila.';
 end if;
 if v_amount is not null and v_amount<>v_tariff.amount and not app.is_staff(array['super_admin','admin','billing']) then
  raise exception using errcode='42501',message='El ajuste de monto requiere autorización de Administración o Facturación.';
 end if;
 v_reason:=nullif(btrim(coalesce(p_data->>'discrepancy_reason','')),'');
 if v_reason is not null and length(v_reason)<10 then raise exception using errcode='22023',message='El motivo del ajuste requiere al menos 10 caracteres.';end if;
 v_result:=public.capture_claim_dx(
  p_provider=>v_provider.id,p_ars=>v_ars,p_procedure=>v_proc,p_service_date=>v_date,
  p_patient_name=>p_data->>'patient',p_member=>v_member,p_authorization=>v_auth,
  p_patient_doc=>nullif(p_data->>'patient_doc',''),p_amount=>v_amount,
  p_quantity=>coalesce((p_data->>'quantity')::numeric,1),p_care_mode=>p_data->>'care_mode',
  p_clinic=>nullif(p_data->>'clinic',''),p_notes=>p_data->>'notes',p_discrepancy_reason=>v_reason,
  p_not_contracted=>'bloquear',p_exception_reason=>null,p_allow_duplicate=>false,p_center=>null,p_diagnosis=>nullif(p_data->>'diagnosis',''));
 perform public.log_google_intake_import(p_record_id,v_org,(v_result->>'id')::uuid,v_result->>'folio');
 insert into public.audit_log(user_id,organization_id,table_name,record_id,operation,old_values,new_values)
 values(auth.uid(),v_org,'google_claim_intake',p_record_id,'CONFIRMACION_CARGA_EXTERNA',jsonb_build_object('source_amount',p_data#>'{source_original,Monto a reclamar}','source_quantity',p_data#>'{source_original,Cantidad}'),
  jsonb_build_object('claim_id',v_result->>'id','folio',v_result->>'folio','quantity',p_data->'quantity','unit_amount',p_data->'amount','expected_tariff',p_data->'expected_tariff','result',v_result,'discrepancy_reason',v_reason,'review_confirmed',true));
 insert into app.google_intake_commits(record_id,created_by,organization_id,payload_hash,claim_id,result)
  values(p_record_id,auth.uid(),v_org,v_hash,(v_result->>'id')::uuid,v_result);
 return v_result;
end$$;
revoke all on function public.google_intake_review_v1(text,text,jsonb) from public,anon;
grant execute on function public.google_intake_review_v1(text,text,jsonb) to authenticated;

-- Invoker preserves the existing tariff RLS and permissions; audit is part of the same transaction.
create function public.google_intake_tariff_v1(p_record_id text,p_data jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_org uuid;v_id uuid;v_before jsonb;v_reason text;begin
 if auth.uid() is null or not app.is_staff(array['super_admin','admin','billing']) then
  raise exception using errcode='42501',message='Solo Administración o Facturación autoriza cambios contractuales.';
 end if;
 if length(btrim(coalesce(p_record_id,''))) not between 3 and 160 or jsonb_typeof(p_data) is distinct from 'object' then raise exception using errcode='22023',message='Solicitud tarifaria inválida.';end if;
 select organization_id into v_org from public.providers where id=(p_data->>'provider')::uuid and is_active;
 if v_org is null or v_org not in(select app.visible_org_ids()) then raise exception using errcode='42501',message='No tiene acceso al médico de este tarifario.';end if;
 if nullif(p_data->>'amount','') is null or (p_data->>'amount')::numeric<=0 or (p_data->>'amount')::numeric*100<>trunc((p_data->>'amount')::numeric*100) or (p_data->>'amount') in ('NaN','Infinity','-Infinity') then
  raise exception using errcode='22023',message='La tarifa debe ser positiva y tener como máximo dos decimales.';
 end if;
 v_reason:=btrim(coalesce(p_data->>'notes',''));
 if length(v_reason)<10 then raise exception using errcode='22023',message='Indique el motivo del cambio contractual (mínimo 10 caracteres).';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'amount',t.amount,'valid_during',t.valid_during)),'[]'::jsonb) into v_before
 from public.tariffs t where t.provider_id=(p_data->>'provider')::uuid and t.ars_id=(p_data->>'ars')::uuid and t.procedure_id=(p_data->>'procedure')::uuid and t.plan_id is null;
 v_id:=public.create_contract_tariff(p_provider=>(p_data->>'provider')::uuid,p_ars=>(p_data->>'ars')::uuid,p_procedure=>(p_data->>'procedure')::uuid,
  p_amount=>(p_data->>'amount')::numeric,p_valid_from=>(p_data->>'validFrom')::date,p_valid_to=>nullif(p_data->>'validTo','')::date,
  p_contract_ref=>p_data->>'contractRef',p_ars_code=>p_data->>'arsCode',p_notes=>v_reason,p_currency=>'DOP');
 perform public.log_google_intake_edit(p_record_id,v_org,jsonb_build_object('tarifas',v_before),
  jsonb_build_object('tariff_id',v_id,'new_values',p_data,'authorized_by',auth.uid()),array['tarifa_contractual','motivo','vigencia']);
 return v_id;
end$$;
revoke all on function public.google_intake_tariff_v1(text,jsonb) from public,anon;
grant execute on function public.google_intake_tariff_v1(text,jsonb) to authenticated;
