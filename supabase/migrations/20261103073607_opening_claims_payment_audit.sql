-- Baselines are an audit ledger, never new operational claims or fee-generating payments.
create table app.opening_history_clients (
 organization_id uuid primary key references public.organizations(id), service_start date not null,
 created_by uuid not null, created_at timestamptz not null default now()
);
create table app.opening_history_loads (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 provider_id uuid not null references public.providers(id), ars_id uuid not null references public.ars(id),
 payload jsonb not null, expected_hash text not null, reason text not null,
 authorized_by uuid not null, authorized_at timestamptz not null default now(), committed_at timestamptz
);
create table app.opening_history_items (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 provider_id uuid not null references public.providers(id), ars_id uuid not null references public.ars(id),
 load_id uuid not null references app.opening_history_loads(id), external_ref text not null,
 submitted_on date not null, service_start date not null, as_of date not null,
 check(submitted_on<service_start and submitted_on<=as_of),
 billed numeric(16,2) not null check(billed>0), paid numeric(16,2) check(paid>=0),
 retained numeric(16,2) not null default 0 check(retained>=0), accepted_glosa numeric(16,2) not null default 0 check(accepted_glosa>=0),
 recovered numeric(16,2) not null default 0 check(recovered>=0), revision integer not null default 1,
 details jsonb not null, flags jsonb not null default '[]',
 audit_status text not null default 'pendiente' check(audit_status in ('pendiente','conforme','observado','ya_en_sofa')),
 review_note text, reviewed_by uuid, reviewed_at timestamptz,
 created_by uuid not null, created_at timestamptz not null default now()
);
create unique index opening_history_items_ref_uq on app.opening_history_items(organization_id,provider_id,ars_id,lower(trim(external_ref)));
create index opening_history_items_provider_idx on app.opening_history_items(provider_id);
create index opening_history_items_ars_idx on app.opening_history_items(ars_id);
create index opening_history_items_load_idx on app.opening_history_items(load_id);
create index opening_history_loads_org_idx on app.opening_history_loads(organization_id);
create index opening_history_loads_provider_idx on app.opening_history_loads(provider_id);
create index opening_history_loads_ars_idx on app.opening_history_loads(ars_id);
create table app.opening_history_recoveries (
 id uuid primary key default gen_random_uuid(), item_id uuid not null references app.opening_history_items(id),
 organization_id uuid not null references public.organizations(id), amount numeric(16,2) not null check(amount>0),
 reference text not null, paid_on date not null, note text not null, created_by uuid not null, created_at timestamptz not null default now()
);
create unique index opening_history_recoveries_ref_uq on app.opening_history_recoveries(item_id,lower(trim(reference)),paid_on);
create index opening_history_recoveries_org_idx on app.opening_history_recoveries(organization_id);

alter table app.opening_history_clients enable row level security;
alter table app.opening_history_loads enable row level security;
alter table app.opening_history_items enable row level security;
alter table app.opening_history_recoveries enable row level security;
-- All writes use guarded functions in the private schema; no direct API table privileges.
revoke all on app.opening_history_clients,app.opening_history_loads,app.opening_history_items,app.opening_history_recoveries from public,anon,authenticated;
create policy opening_history_clients_read on app.opening_history_clients for select to authenticated using (coalesce(app.role_for_org(organization_id) = any(array['super_admin','admin','billing','auditor','glosas','client']),false));
create policy opening_history_loads_read on app.opening_history_loads for select to authenticated using (coalesce(app.role_for_org(organization_id) = any(array['super_admin','admin','billing','auditor','glosas']),false));
create policy opening_history_items_read on app.opening_history_items for select to authenticated using (coalesce(app.role_for_org(organization_id) = any(array['super_admin','admin','billing','auditor','glosas','client']),false));
create policy opening_history_recoveries_read on app.opening_history_recoveries for select to authenticated using (coalesce(app.role_for_org(organization_id) = any(array['super_admin','admin','billing','auditor','glosas','client']),false));
create trigger opening_history_clients_audit after insert or update on app.opening_history_clients for each row execute function app.audit();
create trigger opening_history_loads_audit after insert or update on app.opening_history_loads for each row execute function app.audit();
create trigger opening_history_items_audit after insert or update on app.opening_history_items for each row execute function app.audit();
create trigger opening_history_recoveries_audit after insert on app.opening_history_recoveries for each row execute function app.audit();

create function app.opening_history_access(p_org uuid,p_action text default 'read') returns text
language plpgsql stable security definer set search_path = '' as $$
declare r text;
begin
 r:=app.role_for_org(p_org);
 if auth.uid() is null or not coalesce(app.is_active_user(),false) or not coalesce(r=any(case p_action
  when 'prepare' then array['super_admin','admin','billing']
  when 'authorize' then array['super_admin','admin']
  when 'review' then array['super_admin','admin','auditor','glosas']
  else array['super_admin','admin','billing','auditor','glosas','client'] end),false) then
  raise exception 'Sin permiso para % la cartera anterior de este cliente.',p_action using errcode='42501';
 end if;
 return r;
end $$;
revoke all on function app.opening_history_access(uuid,text) from public,anon,authenticated;

create function app.opening_history_build(p_org uuid,p_provider uuid,p_ars uuid,p_start date,p_asof date,p_code text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare e jsonb;n jsonb;g record;d jsonb;q jsonb;msgs text[];flag text[];errors jsonb:='[]';normalized jsonb:='[]';groups jsonb:='[]';
 i int:=0;k text;ref text;claim text;v_date date;v_service date;v_paydate date;v_billed numeric;v_paid numeric;v_ret numeric;v_glosa numeric;
 controls jsonb;claims jsonb;payments jsonb;ctrl jsonb;detail_billed numeric;detail_paid numeric;detail_ret numeric;detail_glosa numeric;
 events_paid numeric;events_before numeric;events_after numeric;dates int;submitted date;unknown_paid boolean;v_balance numeric;complete boolean;
 v_rows jsonb[]:='{}';v_errors jsonb[]:='{}';v_groups jsonb[]:='{}';
 existing_code text;existing_start date;v_native jsonb;row_errors text[];v_fields text[];v_value text;v_num numeric;existing_status text;
begin
 perform app.opening_history_access(p_org,'prepare');
 if p_start is null or p_start>current_date or p_asof is null or p_asof>current_date then
  raise exception 'Indique el inicio de gestión SOFA y una fecha de corte no futura.' using errcode='22023';end if;
 if not exists(select 1 from public.providers where id=p_provider and organization_id=p_org and is_active)
 or not exists(select 1 from public.ars where id=p_ars and is_active) then raise exception 'Seleccione un médico del cliente y una ARS activa.' using errcode='22023';end if;
 select service_start into existing_start from app.opening_history_clients where organization_id=p_org;
 if existing_start is not null and existing_start<>p_start then raise exception 'La cartera de este cliente ya usa el inicio SOFA %. No mezcle fechas de inicio.',existing_start using errcode='22023';end if;
 select code,status into existing_code,existing_status from public.provider_ars_codes where provider_id=p_provider and ars_id=p_ars;
 if nullif(trim(p_code),'') is null and nullif(trim(existing_code),'') is null then raise exception 'Indique el código de prestador ya otorgado por la ARS.' using errcode='22023';end if;
 if nullif(trim(p_code),'') is not null and nullif(trim(existing_code),'') is not null and upper(trim(p_code))<>upper(trim(existing_code)) then
  raise exception 'El código de prestador no coincide con el registrado (%). Revíselo en Códigos ARS; no se sobrescribe en esta carga.',existing_code using errcode='22023';end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 5000 then raise exception 'Cargue entre 1 y 5,000 filas por lote.' using errcode='22023';end if;
 for e in select x from jsonb_array_elements(p_rows) x loop
  i:=i+1;msgs:='{}';k:=lower(trim(coalesce(e->>'tipo','')));ref:=trim(coalesce(e->>'radicacion',''));claim:=trim(coalesce(e->>'reclamacion',''));
  if k not in ('resumen','reclamacion','pago','codigo') then msgs:=array_append(msgs,'Tipo: use resumen, reclamacion, pago o codigo.');end if;
  if k<>'codigo' and (length(ref) not between 1 and 120) then msgs:=array_append(msgs,'Falta la referencia original de radicación (máximo 120 caracteres).');end if;

  if nullif(trim(e->>'codigo_prestador'),'') is not null and upper(trim(e->>'codigo_prestador'))<>upper(trim(coalesce(nullif(trim(p_code),''),existing_code))) then msgs:=array_append(msgs,'El código de prestador de esta fila no coincide con el seleccionado.');end if;
  v_date:=app.parse_date_do(e->>'fecha_radicacion');v_service:=app.parse_date_do(e->>'fecha_servicio');v_paydate:=app.parse_date_do(e->>'fecha_pago');
  if k='reclamacion' and claim='' and nullif(trim(e->>'nss'),'') is not null and nullif(trim(e->>'autorizacion'),'') is not null and v_service is not null
    and coalesce(nullif(trim(e->>'servicio'),''),nullif(trim(e->>'simon'),''),nullif(trim(e->>'cups'),'')) is not null then
    claim:='CLAVE-'||md5(upper(trim(e->>'nss'))||'|'||upper(trim(e->>'autorizacion'))||'|'||v_service::text||'|'||upper(coalesce(nullif(trim(e->>'servicio'),''),nullif(trim(e->>'simon'),''),trim(e->>'cups'))));
  end if;
  if k='reclamacion' and (length(claim) not between 1 and 120) then msgs:=array_append(msgs,'Indique la referencia original de reclamación o NSS, autorización, fecha de servicio y servicio/código para construir una clave de cotejo.');end if;
  if nullif(e->>'fecha_radicacion','') is not null and (v_date is null or v_date>=p_start or v_date>p_asof) then msgs:=array_append(msgs,'La fecha de radicación debe ser válida, anterior al inicio SOFA y no posterior al corte.');end if;
  if nullif(e->>'fecha_servicio','') is not null and (v_service is null or v_service>=p_start) then msgs:=array_append(msgs,'La fecha de servicio debe ser válida y anterior al inicio de SOFA.');end if;
  if k='pago' and (v_paydate is null or v_paydate>p_asof or length(trim(coalesce(e->>'referencia_pago',''))) not between 1 and 120) then msgs:=array_append(msgs,'Cada pago necesita fecha válida no posterior al corte y referencia original (máximo 120 caracteres).');end if;
  v_billed:=app.pm_parse_amount(e->>'facturado');v_paid:=app.pm_parse_amount(e->>'pagado');v_ret:=coalesce(app.pm_parse_amount(e->>'retencion'),0);v_glosa:=coalesce(app.pm_parse_amount(e->>'glosa_aceptada'),0);
  foreach v_value in array array['facturado','pagado','retencion','glosa_aceptada'] loop
   v_num:=app.pm_parse_amount(e->>v_value);
   if coalesce(e->>v_value,'') ~* '(US\$|USD|EUR|€)' then msgs:=array_append(msgs,'Use importes en DOP/RD$; moneda no admitida en '||v_value);end if;
   if nullif(trim(e->>v_value),'') is not null and (v_num is null or v_num<0 or v_num>999999999999.99 or round(v_num,2)<>v_num) then msgs:=array_append(msgs,'Monto inválido en '||v_value||': '||coalesce(e->>v_value,''));end if;
  end loop;
  if k in ('resumen','reclamacion') and (v_billed is null or v_billed<=0) then msgs:=array_append(msgs,'Facturado debe ser mayor que cero.');end if;
  if k='pago' and (v_paid is null or v_paid<=0) then msgs:=array_append(msgs,'Pagado debe ser mayor que cero en una fila de pago.');end if;
  if cardinality(msgs)>0 then v_errors:=array_append(v_errors,jsonb_build_object('row',i,'data',e,'errors',msgs));end if;
  n:=jsonb_build_object('row',i,'type',k,'ref',ref,'claim',claim,'submitted_on',v_date,'service_date',v_service,'paid_on',v_paydate,
   'billed',v_billed,'paid',v_paid,'retained',v_ret,'accepted_glosa',v_glosa,'reference',trim(coalesce(e->>'referencia_pago','')),'source',e);
  v_rows:=array_append(v_rows,n);
 end loop;
 normalized:=to_jsonb(v_rows);errors:=to_jsonb(v_errors);
 if jsonb_array_length(errors)>0 then return jsonb_build_object('errors',errors,'groups','[]'::jsonb,'total',i);end if;
 for g in select lower(x->>'ref') key,jsonb_agg(x order by (x->>'row')::int) rows from jsonb_array_elements(normalized) x where x->>'type'<>'codigo' group by lower(x->>'ref') order by lower(x->>'ref') loop
  msgs:='{}';flag:='{}';complete:=false;
  select coalesce(jsonb_agg(x),'[]') into controls from jsonb_array_elements(g.rows) x where x->>'type'='resumen';
  select coalesce(jsonb_agg(x),'[]') into claims from jsonb_array_elements(g.rows) x where x->>'type'='reclamacion';
  select coalesce(jsonb_agg(x),'[]') into payments from jsonb_array_elements(g.rows) x where x->>'type'='pago';
  ctrl:=controls->0;ref:=g.rows->0->>'ref';
  if jsonb_array_length(controls)>1 then msgs:=array_append(msgs,'Hay más de un resumen para esta radicación. Conserve un solo total de control.');end if;
  if ctrl is null and jsonb_array_length(claims)=0 then msgs:=array_append(msgs,'El pago no tiene un resumen ni reclamaciones de respaldo.');end if;
  select count(distinct x->>'submitted_on'),min((x->>'submitted_on')::date) into dates,submitted from jsonb_array_elements(g.rows) x;
  if dates<>1 then msgs:=array_append(msgs,'Indique una única fecha original de radicación por grupo.');end if;
  if exists(select 1 from jsonb_array_elements(claims) x where (x->>'service_date')::date>submitted) then msgs:=array_append(msgs,'Una fecha de servicio es posterior a la radicación.');end if;
  if exists(select 1 from jsonb_array_elements(payments) x where (x->>'paid_on')::date<submitted) then msgs:=array_append(msgs,'Un pago es anterior a la radicación. Revise las fechas originales.');end if;
  if exists(select 1 from jsonb_array_elements(claims) x group by lower(x->>'claim') having count(*)>1) then msgs:=array_append(msgs,'La referencia de reclamación se repite dentro de la radicación.');end if;
  if exists(select 1 from jsonb_array_elements(payments) x group by lower(x->>'reference'),x->>'paid_on',lower(x->>'claim') having count(*)>1) then msgs:=array_append(msgs,'Un pago con igual referencia, fecha y reclamación está repetido.');end if;
  if exists(select 1 from jsonb_array_elements(payments) x where x->>'claim'<>'' and not exists(select 1 from jsonb_array_elements(claims) c where lower(c->>'claim')=lower(x->>'claim'))) then msgs:=array_append(msgs,'Un pago apunta a una reclamación ausente del detalle. Déjela vacía solo si el pago corresponde al total de la radicación.');end if;
  detail_billed:=0;detail_paid:=0;detail_ret:=0;detail_glosa:=0;unknown_paid:=false;
  for d in select x from jsonb_array_elements(claims) x loop
   select sum((x->>'paid')::numeric) into events_paid from jsonb_array_elements(payments) x where lower(x->>'claim')=lower(d->>'claim');
   v_paid:=coalesce((d->>'paid')::numeric,events_paid);
   if v_paid is null then unknown_paid:=true;end if;
   if events_paid>v_paid then msgs:=array_append(msgs,'Los pagos detallados superan el acumulado de la reclamación '||(d->>'claim'));end if;
   detail_billed:=detail_billed+(d->>'billed')::numeric;detail_paid:=detail_paid+coalesce(v_paid,0);detail_ret:=detail_ret+(d->>'retained')::numeric;detail_glosa:=detail_glosa+(d->>'accepted_glosa')::numeric;
  end loop;
  select coalesce(sum((x->>'paid')::numeric),0),coalesce(sum((x->>'paid')::numeric) filter(where (x->>'paid_on')::date<p_start),0),coalesce(sum((x->>'paid')::numeric) filter(where (x->>'paid_on')::date>=p_start),0)
   into events_paid,events_before,events_after from jsonb_array_elements(payments) x;
  v_billed:=coalesce((ctrl->>'billed')::numeric,detail_billed);v_ret:=coalesce((ctrl->>'retained')::numeric,detail_ret);v_glosa:=coalesce((ctrl->>'accepted_glosa')::numeric,detail_glosa);
  if ctrl->>'paid' is not null then v_paid:=(ctrl->>'paid')::numeric;
  elsif jsonb_array_length(claims)>0 and not unknown_paid then
   select detail_paid+coalesce(sum((x->>'paid')::numeric),0) into v_paid from jsonb_array_elements(payments) x where x->>'claim'='';
  elsif jsonb_array_length(payments)>0 and jsonb_array_length(claims)=0 then v_paid:=events_paid;
  else v_paid:=null;end if;
  if detail_billed>v_billed or detail_ret>v_ret or detail_glosa>v_glosa or (v_paid is not null and (detail_paid>v_paid or events_paid>v_paid)) then msgs:=array_append(msgs,'El detalle supera el total de control: revise facturado, pagado, retención y glosa aceptada.');end if;
  if exists(select 1 from app.opening_history_items where organization_id=p_org and provider_id=p_provider and ars_id=p_ars and lower(trim(external_ref))=g.key) then msgs:=array_append(msgs,'Esta radicación ya fue cargada. Use su auditoría para registrar seguimientos y cobros posteriores.');end if;
  select coalesce(jsonb_agg(s.id order by s.id),'[]') into v_native from public.submissions s where s.organization_id=p_org and s.provider_id=p_provider and s.ars_id=p_ars
   and (lower(s.folio)=g.key or lower(s.ars_receipt_number)=g.key or exists(select 1 from public.service_lines l join jsonb_array_elements(claims) c on
    (lower(l.claim_folio)=lower(c->>'claim') or (nullif(c->'source'->>'nss','') is not null and nullif(c->'source'->>'autorizacion','') is not null and l.service_date=(c->>'service_date')::date and upper(trim(l.member_number))=upper(trim(c->'source'->>'nss')) and upper(trim(l.authorization_number))=upper(trim(c->'source'->>'autorizacion')))) where l.submission_id=s.id));
  if jsonb_array_length(v_native)>0 then flag:=array_append(flag,'Posible coincidencia con radicación/reclamación ya registrada en SOFA; resolver antes de cobrar.');end if;
  complete:=jsonb_array_length(claims)>0 and detail_billed=v_billed;
  if exists(select 1 from jsonb_array_elements(claims) x where coalesce(x->'source'->>'reclamacion','')='') then flag:=array_append(flag,'Hay claves de cotejo derivadas de NSS, autorización, fecha y servicio; no se generaron folios de reclamación nuevos.');end if;
  if not complete then flag:=array_append(flag,case when jsonb_array_length(claims)=0 then 'Solo totales por radicación; falta el desglose por reclamación.' else 'Desglose de reclamaciones incompleto respecto al total.' end);end if;
  if jsonb_array_length(claims)>0 and v_paid is not null and detail_paid<v_paid then flag:=array_append(flag,'El pago acumulado no está completamente distribuido por reclamación; no se repartió automáticamente.');end if;
  if unknown_paid then flag:=array_append(flag,'Falta el pago acumulado de alguna reclamación.');end if;
  if v_paid is null then flag:=array_append(flag,'Pago acumulado no informado: el saldo aún no se puede determinar.');
  elsif events_paid<v_paid then flag:=array_append(flag,'El acumulado pagado no tiene todo el detalle de pagos; solicitar relación/soportes.');end if;
  if events_after>0 then flag:=array_append(flag,'Incluye pagos posteriores al inicio SOFA: revisar el alcance y los honorarios según contrato.');end if;
  v_balance:=v_billed-v_paid-v_ret-v_glosa;
  if v_balance<0 then flag:=array_append(flag,'Exceso de pago o ajustes: revisar crédito a favor; no convertirlo en glosa.');end if;
  if cardinality(msgs)>0 then v_errors:=array_append(v_errors,jsonb_build_object('row',(g.rows->0->>'row')::int,'data',g.rows->0->'source','errors',msgs));end if;
  v_groups:=array_append(v_groups,jsonb_build_object('external_ref',ref,'submitted_on',submitted,'billed',v_billed,'paid',v_paid,'retained',v_ret,'accepted_glosa',v_glosa,'balance',v_balance,
   'status',case when v_paid is null then 'sin_datos_pago' when v_balance<0 then 'exceso' when v_balance=0 and v_paid>0 then 'pagada_total' when v_balance=0 then 'cerrada_por_ajustes' when v_paid>0 or v_ret>0 then 'pago_parcial' else 'sin_pago' end,
   'detail_level',case when complete then 'completo' when jsonb_array_length(claims)=0 then 'resumen' else 'incompleto' end,
   'claims_count',jsonb_array_length(claims),'documented_paid',events_paid,'paid_before_sofa',events_before,'paid_after_sofa',events_after,'native_candidates',v_native,'flags',to_jsonb(flag),'rows',g.rows));
 end loop;
 errors:=to_jsonb(v_errors);groups:=to_jsonb(v_groups);
 return jsonb_build_object('errors',errors,'groups',groups,'total',i,'provider_code',coalesce(nullif(trim(p_code),''),existing_code),
  'hash',md5(jsonb_build_object('org',p_org,'provider',p_provider,'ars',p_ars,'start',p_start,'asof',p_asof,'code',coalesce(nullif(trim(p_code),''),existing_code),'rows',p_rows,'groups',groups)::text));
end $$;
revoke all on function app.opening_history_build(uuid,uuid,uuid,date,date,text,jsonb) from public,anon,authenticated;
create function app.opening_history_context(p_org uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r text;v_start date;
begin
 r:=app.opening_history_access(p_org,'read');
 select coalesce((select service_start from app.opening_history_clients where organization_id=p_org),started_on) into v_start from public.organizations where id=p_org and kind='client';
 return jsonb_build_object('start',v_start,'can_prepare',r=any(array['super_admin','admin','billing']),'can_authorize',r=any(array['super_admin','admin']),
 'can_review',r=any(array['super_admin','admin','auditor','glosas']),
 'providers',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name),'[]') from public.providers p where organization_id=p_org and is_active),
 'ars',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name) order by a.name),'[]') from public.ars a where is_active),
 'codes',(select coalesce(jsonb_agg(jsonb_build_object('provider',provider_id,'ars',ars_id,'code',code,'status',status)),'[]') from public.provider_ars_codes where organization_id=p_org));
end $$;
create function app.opening_history_preview(p_org uuid,p_provider uuid,p_ars uuid,p_start date,p_asof date,p_code text,p_rows jsonb)
returns jsonb language sql security definer set search_path='' as $$ select app.opening_history_build(p_org,p_provider,p_ars,p_start,p_asof,p_code,p_rows) $$;

create function app.opening_history_authorize(p_org uuid,p_provider uuid,p_ars uuid,p_start date,p_asof date,p_code text,p_rows jsonb,p_expected text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rep jsonb;v_id uuid;
begin
 perform app.opening_history_access(p_org,'authorize');
 if length(trim(coalesce(p_reason,''))) not between 10 and 1000 then raise exception 'Indique el soporte y motivo de autorización (10 a 1,000 caracteres).' using errcode='22023';end if;
 rep:=app.opening_history_build(p_org,p_provider,p_ars,p_start,p_asof,p_code,p_rows);
 if jsonb_array_length(rep->'errors')>0 then raise exception 'Corrija todas las filas antes de autorizar la carga.' using errcode='23514';end if;
 if rep->>'hash' is distinct from p_expected then raise exception 'La carga o sus coincidencias cambió. Revise la vista previa nuevamente.' using errcode='40001';end if;
 insert into app.opening_history_loads(organization_id,provider_id,ars_id,payload,expected_hash,reason,authorized_by)
 values(p_org,p_provider,p_ars,jsonb_build_object('start',p_start,'asof',p_asof,'code',p_code,'rows',p_rows),p_expected,trim(p_reason),auth.uid()) returning id into v_id;
 return jsonb_build_object('id',v_id,'hash',p_expected,'authorized_by',auth.uid());
end $$;

create function app.opening_history_commit(p_authorization uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare b app.opening_history_loads%rowtype;rep jsonb;g jsonb;v_count int:=0;v_id uuid;v_start date;v_code public.provider_ars_codes%rowtype;
begin
 select * into b from app.opening_history_loads where id=p_authorization for update;
 if b.id is null or b.authorized_by is distinct from auth.uid() then raise exception 'Autorización de carga no disponible para este usuario.' using errcode='42501';end if;
 perform app.opening_history_access(b.organization_id,'authorize');
 if b.committed_at is not null then return jsonb_build_object('imported',(select count(*) from app.opening_history_items where load_id=b.id),'already_committed',true);end if;
 perform pg_advisory_xact_lock(hashtextextended('sofa.opening-history|'||b.organization_id::text,0));
 rep:=app.opening_history_build(b.organization_id,b.provider_id,b.ars_id,(b.payload->>'start')::date,(b.payload->>'asof')::date,b.payload->>'code',b.payload->'rows');
 if jsonb_array_length(rep->'errors')>0 or rep->>'hash' is distinct from b.expected_hash then raise exception 'Los datos, las coincidencias o la cartera cambiaron. Revise y autorice una carga actualizada; no se guardó ninguna fila.' using errcode='40001';end if;
 insert into app.opening_history_clients(organization_id,service_start,created_by) values(b.organization_id,(b.payload->>'start')::date,auth.uid()) on conflict do nothing;
 select service_start into v_start from app.opening_history_clients where organization_id=b.organization_id;
 if v_start<>(b.payload->>'start')::date then raise exception 'El inicio SOFA no coincide con la cartera ya confirmada.' using errcode='40001';end if;
 select * into v_code from public.provider_ars_codes where provider_id=b.provider_id and ars_id=b.ars_id for update;
 if nullif(trim(v_code.code),'') is not null and upper(trim(v_code.code))<>upper(trim(rep->>'provider_code')) then raise exception 'Otro usuario modificó el código de prestador. Revise y autorice la carga nuevamente.' using errcode='40001';end if;
 if v_code.id is null then
  insert into public.provider_ars_codes(organization_id,provider_id,ars_id,code,status,notes) values(b.organization_id,b.provider_id,b.ars_id,rep->>'provider_code','codificado','Código previo verificado en carga de apertura '||b.id::text||'. '||b.reason);
 elsif v_code.status<>'codificado' or nullif(trim(v_code.code),'') is null then
  update public.provider_ars_codes set code=rep->>'provider_code',status='codificado',updated_by=auth.uid(),updated_at=now(),notes=concat_ws(E'\n',notes,'Código previo verificado en carga de apertura '||b.id::text||'. '||b.reason) where id=v_code.id;
 end if;
 for g in select x from jsonb_array_elements(rep->'groups') x loop
  insert into app.opening_history_items(organization_id,provider_id,ars_id,load_id,external_ref,submitted_on,service_start,as_of,billed,paid,retained,accepted_glosa,details,flags,created_by)
  values(b.organization_id,b.provider_id,b.ars_id,b.id,g->>'external_ref',(g->>'submitted_on')::date,(b.payload->>'start')::date,(b.payload->>'asof')::date,
   (g->>'billed')::numeric,(g->>'paid')::numeric,(g->>'retained')::numeric,(g->>'accepted_glosa')::numeric,g,g->'flags',auth.uid());
  v_count:=v_count+1;
 end loop;
 update app.opening_history_loads set committed_at=now() where id=b.id;
 return jsonb_build_object('imported',v_count,'code_registered',true,'fees_generated',0);
end $$;

create function app.opening_history_board(p_org uuid,p_offset int default 0,p_limit int default 100,p_status text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r text;v_items jsonb;v_summary jsonb;
begin
 r:=app.opening_history_access(p_org,'read');
 select jsonb_build_object('radicaciones',count(*),'pendientes_auditoria',count(*) filter(where audit_status in ('pendiente','observado')),
  'facturado',coalesce(sum(billed) filter(where audit_status<>'ya_en_sofa'),0),
  'pagado_inicial',coalesce(sum(paid) filter(where audit_status<>'ya_en_sofa'),0),
  'recuperado',coalesce(sum(recovered) filter(where audit_status<>'ya_en_sofa'),0),
  'saldo_confirmado',coalesce(sum(billed-paid-retained-accepted_glosa-recovered) filter(where audit_status='conforme' and paid is not null),0),
  'sin_datos_pago',count(*) filter(where paid is null),'sin_desglose',count(*) filter(where details->>'detail_level'<>'completo'),
  'posibles_duplicados',count(*) filter(where jsonb_array_length(details->'native_candidates')>0 and audit_status<>'ya_en_sofa')) into v_summary
 from app.opening_history_items where organization_id=p_org;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_items from (
 select i.id,i.external_ref,i.submitted_on,i.as_of,i.billed,i.paid,i.retained,i.accepted_glosa,i.recovered,
 i.billed-i.paid-i.retained-i.accepted_glosa-i.recovered balance,
 case when i.paid is null then 'sin_datos_pago' when i.billed-i.paid-i.retained-i.accepted_glosa-i.recovered<0 then 'exceso'
 when i.billed-i.paid-i.retained-i.accepted_glosa-i.recovered=0 and i.paid+i.recovered>0 then 'pagada_total'
 when i.billed-i.paid-i.retained-i.accepted_glosa-i.recovered=0 then 'cerrada_por_ajustes' when i.paid+i.recovered>0 or i.retained>0 then 'pago_parcial' else 'sin_pago' end payment_status,
 i.audit_status,i.review_note,i.flags,p.full_name provider,a.name ars,i.details->>'detail_level' detail_level,
 (i.details->>'claims_count')::int claims_count from app.opening_history_items i join public.providers p on p.id=i.provider_id join public.ars a on a.id=i.ars_id
 where i.organization_id=p_org and (p_status is null or i.audit_status=p_status) order by i.created_at desc,i.id
 offset greatest(coalesce(p_offset,0),0) limit least(greatest(coalesce(p_limit,100),1),200)) x;
 return jsonb_build_object('summary',v_summary,'items',v_items,'count',(select count(*) from app.opening_history_items where organization_id=p_org and (p_status is null or audit_status=p_status)),
 'can_review',r=any(array['super_admin','admin','auditor','glosas']),'can_authorize',r=any(array['super_admin','admin']));
end $$;

create function app.opening_history_item(p_item uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare i app.opening_history_items%rowtype;
begin
 select * into i from app.opening_history_items where id=p_item;
 if i.id is null then raise exception 'Antecedente no encontrado.' using errcode='P0002';end if;
 perform app.opening_history_access(i.organization_id,'read');
 return jsonb_build_object('item',to_jsonb(i),'recoveries',(select coalesce(jsonb_agg(to_jsonb(r) order by paid_on,created_at),'[]') from app.opening_history_recoveries r where item_id=p_item));
end $$;

create function app.opening_history_review(p_item uuid,p_status text,p_note text,p_expected_revision integer) returns void language plpgsql security definer set search_path='' as $$
declare i app.opening_history_items%rowtype;
begin
 select * into i from app.opening_history_items where id=p_item for update;
 if i.id is null then raise exception 'Antecedente no encontrado.' using errcode='P0002';end if;
 perform app.opening_history_access(i.organization_id,'review');
 if i.revision is distinct from p_expected_revision then raise exception 'El antecedente cambió. Abra nuevamente la auditoría antes de confirmar.' using errcode='40001';end if;
 if p_status not in ('conforme','observado','ya_en_sofa') or length(trim(coalesce(p_note,''))) not between 10 and 2000 then raise exception 'Seleccione el resultado e indique el soporte o hallazgo (10 a 2,000 caracteres).' using errcode='22023';end if;
 if p_status='conforme' and i.paid is null then raise exception 'No puede confirmar el saldo sin el acumulado pagado. Registre el hallazgo y solicite los datos faltantes.' using errcode='23514';end if;
 if p_status='ya_en_sofa' and i.recovered>0 then raise exception 'Esta cartera tiene cobros posteriores registrados. Revise su conciliación antes de marcarla como ya existente.' using errcode='23514';end if;
 update app.opening_history_items set revision=revision+1,audit_status=p_status,review_note=trim(p_note),reviewed_by=auth.uid(),reviewed_at=now() where id=p_item;
end $$;

create function app.opening_history_recovery_add(p_item uuid,p_amount numeric,p_reference text,p_paid_on date,p_note text) returns uuid
language plpgsql security definer set search_path='' as $$
declare i app.opening_history_items%rowtype;v_id uuid;
begin
 select * into i from app.opening_history_items where id=p_item for update;
 if i.id is null then raise exception 'Antecedente no encontrado.' using errcode='P0002';end if;
 perform app.opening_history_access(i.organization_id,'authorize');
 if i.audit_status<>'conforme' or i.paid is null then raise exception 'Primero confirme la auditoría y descarte duplicados. No registre otro cobro sobre un saldo sin revisar.' using errcode='23514';end if;
 if p_amount is null or p_amount<=0 or p_amount>999999999999.99 or round(p_amount,2)<>p_amount or length(trim(coalesce(p_reference,''))) not between 1 and 120
 or p_paid_on is null or p_paid_on<=i.as_of or p_paid_on>current_date or length(trim(coalesce(p_note,''))) not between 10 and 2000 then
 raise exception 'Indique monto positivo, referencia, fecha posterior al corte y no futura, y soporte del cobro (mínimo 10 caracteres).' using errcode='22023';end if;
 if exists(select 1 from public.payments where organization_id=i.organization_id and ars_id=i.ars_id and upper(trim(reference))=upper(trim(p_reference)) and paid_on=p_paid_on) then
 raise exception 'Ese pago ya aparece en Pagos de SOFA. Concílielo; no lo vuelva a cargar como recuperación histórica.' using errcode='23505';end if;
 insert into app.opening_history_recoveries(item_id,organization_id,amount,reference,paid_on,note,created_by) values(i.id,i.organization_id,p_amount,trim(p_reference),p_paid_on,trim(p_note),auth.uid()) returning id into v_id;
 update app.opening_history_items set revision=revision+1,recovered=recovered+p_amount,flags=flags||jsonb_build_array(case when p_paid_on>=i.service_start then 'Cobro posterior al inicio SOFA: revisar honorarios conforme al contrato; no se generó una factura automáticamente.' else 'Cobro anterior al inicio SOFA agregado con soporte; no se generaron honorarios retrospectivos.' end) where id=i.id;
 return v_id;
end $$;

-- Only guarded private implementations are executable through thin invoker RPCs.
revoke all on function app.opening_history_context(uuid),app.opening_history_preview(uuid,uuid,uuid,date,date,text,jsonb),app.opening_history_authorize(uuid,uuid,uuid,date,date,text,jsonb,text,text),app.opening_history_commit(uuid),app.opening_history_board(uuid,int,int,text),app.opening_history_item(uuid),app.opening_history_review(uuid,text,text,integer),app.opening_history_recovery_add(uuid,numeric,text,date,text) from public,anon;
grant execute on function app.opening_history_context(uuid),app.opening_history_preview(uuid,uuid,uuid,date,date,text,jsonb),app.opening_history_authorize(uuid,uuid,uuid,date,date,text,jsonb,text,text),app.opening_history_commit(uuid),app.opening_history_board(uuid,int,int,text),app.opening_history_item(uuid),app.opening_history_review(uuid,text,text,integer),app.opening_history_recovery_add(uuid,numeric,text,date,text) to authenticated;
create function public.opening_history_context(p_org uuid) returns jsonb language sql security invoker set search_path='' as $$ select app.opening_history_context(p_org) $$;
create function public.opening_history_preview(p_org uuid,p_provider uuid,p_ars uuid,p_start date,p_asof date,p_code text,p_rows jsonb) returns jsonb language sql security invoker set search_path='' as $$ select app.opening_history_preview(p_org,p_provider,p_ars,p_start,p_asof,p_code,p_rows) $$;
create function public.opening_history_authorize(p_org uuid,p_provider uuid,p_ars uuid,p_start date,p_asof date,p_code text,p_rows jsonb,p_expected text,p_reason text) returns jsonb language sql security invoker set search_path='' as $$ select app.opening_history_authorize(p_org,p_provider,p_ars,p_start,p_asof,p_code,p_rows,p_expected,p_reason) $$;
create function public.opening_history_commit(p_authorization uuid) returns jsonb language sql security invoker set search_path='' as $$ select app.opening_history_commit(p_authorization) $$;
create function public.opening_history_board(p_org uuid,p_offset int default 0,p_limit int default 100,p_status text default null) returns jsonb language sql security invoker set search_path='' as $$ select app.opening_history_board(p_org,p_offset,p_limit,p_status) $$;
create function public.opening_history_item(p_item uuid) returns jsonb language sql security invoker set search_path='' as $$ select app.opening_history_item(p_item) $$;
create function public.opening_history_review(p_item uuid,p_status text,p_note text,p_expected_revision integer) returns void language sql security invoker set search_path='' as $$ select app.opening_history_review(p_item,p_status,p_note,p_expected_revision) $$;
create function public.opening_history_recovery_add(p_item uuid,p_amount numeric,p_reference text,p_paid_on date,p_note text) returns uuid language sql security invoker set search_path='' as $$ select app.opening_history_recovery_add(p_item,p_amount,p_reference,p_paid_on,p_note) $$;
revoke all on function public.opening_history_context(uuid),public.opening_history_preview(uuid,uuid,uuid,date,date,text,jsonb),public.opening_history_authorize(uuid,uuid,uuid,date,date,text,jsonb,text,text),public.opening_history_commit(uuid),public.opening_history_board(uuid,int,int,text),public.opening_history_item(uuid),public.opening_history_review(uuid,text,text,integer),public.opening_history_recovery_add(uuid,numeric,text,date,text) from public,anon;
grant execute on function public.opening_history_context(uuid),public.opening_history_preview(uuid,uuid,uuid,date,date,text,jsonb),public.opening_history_authorize(uuid,uuid,uuid,date,date,text,jsonb,text,text),public.opening_history_commit(uuid),public.opening_history_board(uuid,int,int,text),public.opening_history_item(uuid),public.opening_history_review(uuid,text,text,integer),public.opening_history_recovery_add(uuid,numeric,text,date,text) to authenticated;
-- Rectifications preserve original source rows and are audited; a new review is required.
create function app.opening_history_rectify(p_item uuid,p_billed numeric,p_paid numeric,p_retained numeric,p_glosa numeric,p_reason text,p_expected_revision integer)
returns void language plpgsql security definer set search_path='' as $$
declare i app.opening_history_items%rowtype;v numeric;
begin
 select * into i from app.opening_history_items where id=p_item for update;
 if i.id is null then raise exception 'Antecedente no encontrado.' using errcode='P0002';end if;
 perform app.opening_history_access(i.organization_id,'authorize');
 if i.revision is distinct from p_expected_revision then raise exception 'El saldo cambió. Abra nuevamente el antecedente antes de rectificar.' using errcode='40001';end if;
 if length(trim(coalesce(p_reason,''))) not between 10 and 2000 or p_billed is null or p_billed<=0 or p_paid is null or p_retained is null or p_glosa is null then
 raise exception 'Complete las cifras corregidas y explique el soporte de la rectificación (10 a 2,000 caracteres).' using errcode='22023';end if;
 foreach v in array array[p_billed,p_paid,p_retained,p_glosa] loop
 if v<0 or v>999999999999.99 or round(v,2)<>v then raise exception 'Los montos deben ser no negativos y tener hasta dos decimales.' using errcode='22023';end if;end loop;
 if p_paid<(i.details->>'documented_paid')::numeric then raise exception 'El pagado corregido no puede ser inferior a los pagos detallados importados. Revise sus soportes.' using errcode='23514';end if;
 update app.opening_history_items set revision=revision+1,billed=p_billed,paid=p_paid,retained=p_retained,accepted_glosa=p_glosa,
 audit_status='observado',review_note='Rectificación autorizada: '||trim(p_reason),reviewed_by=auth.uid(),reviewed_at=now(),
 flags=flags||jsonb_build_array('Cifras rectificadas por Administración. Las filas originales se conservan; requiere nueva auditoría.') where id=i.id;
end $$;
revoke all on function app.opening_history_rectify(uuid,numeric,numeric,numeric,numeric,text,integer) from public,anon;
grant execute on function app.opening_history_rectify(uuid,numeric,numeric,numeric,numeric,text,integer) to authenticated;
create function public.opening_history_rectify(p_item uuid,p_billed numeric,p_paid numeric,p_retained numeric,p_glosa numeric,p_reason text,p_expected_revision integer)
returns void language sql security invoker set search_path='' as $$ select app.opening_history_rectify(p_item,p_billed,p_paid,p_retained,p_glosa,p_reason,p_expected_revision) $$;
revoke all on function public.opening_history_rectify(uuid,numeric,numeric,numeric,numeric,text,integer) from public,anon;
grant execute on function public.opening_history_rectify(uuid,numeric,numeric,numeric,numeric,text,integer) to authenticated;
-- Expose only the existence of reviewed opening data, never amounts, to onboarding roles.
create function app.opening_history_has_reviewed(p_org uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not coalesce(app.is_active_user(),false) or app.role_for_org(p_org) is null then return false;end if;
 return exists(select 1 from app.opening_history_items where organization_id=p_org and audit_status='conforme');
end $$;
revoke all on function app.opening_history_has_reviewed(uuid) from public,anon;
grant execute on function app.opening_history_has_reviewed(uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.onboarding_status(p_org uuid)
 RETURNS TABLE(step integer, code text, label text, done boolean, source text, detail text, done_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with ranked_docs as (
    select d.id,d.document_type_code,d.uploaded_at,
           row_number() over(
             partition by d.document_type_code
             order by d.uploaded_at desc,d.id desc
           ) rn
      from public.documents d
     where d.organization_id=p_org
       and d.entity_type='organization'
       and d.entity_id=p_org
       and d.document_type_code in (
         'contrato_sofa','autorizacion_representacion','carta_clinica','formulario_implementacion'
       )
  ),
  doc as (
    select
      case rd.document_type_code
        when 'contrato_sofa' then 'A'
        when 'autorizacion_representacion' then 'B'
        when 'carta_clinica' then 'C'
        when 'formulario_implementacion' then 'E'
      end template_code,
      rd.id document_id,
      rd.uploaded_at,
      coalesce(r.status,'cargado') review_status,
      r.reviewed_at,
      r.notes
    from ranked_docs rd
    left join public.client_document_reviews r on r.document_id=rd.id
    where rd.rn=1
  ),
  dstat as (
    select app.client_ars_letters_status(p_org) j
  ),
  prov as (
    select * from public.providers
    where organization_id=p_org and is_active
  ),
  auto as (
    select 'contrato' code,
      coalesce((select review_status='aprobado' from doc where template_code='A'),false) ok,
      case
        when not exists(select 1 from doc where template_code='A') then 'Documento A pendiente de carga'
        when exists(select 1 from doc where template_code='A' and review_status='requiere_correccion') then 'Documento A requiere corrección'
        when exists(select 1 from doc where template_code='A' and review_status='aprobado') then 'Documento A cargado y aprobado por SOFA'
        else 'Documento A cargado; pendiente de revisión SOFA'
      end how
    union all
    select 'autorizacion',
      coalesce((select review_status='aprobado' from doc where template_code='B'),false),
      case
        when not exists(select 1 from doc where template_code='B') then 'Documento B pendiente de carga'
        when exists(select 1 from doc where template_code='B' and review_status='requiere_correccion') then 'Documento B requiere corrección'
        when exists(select 1 from doc where template_code='B' and review_status='aprobado') then 'Documento B cargado y aprobado por SOFA'
        else 'Documento B cargado; pendiente de revisión SOFA'
      end
    union all
    select 'datos_medico',
      exists(select 1 from prov)
      and not exists(select 1 from prov where tax_id is null or exequatur is null or specialty is null),
      'Cédula, exequátur y especialidad de cada médico'
    union all
    select 'ars_cartas',
      coalesce(((select j->>'ok' from dstat))::boolean,false),
      coalesce((select j->>'detail' from dstat),'Cartas D pendientes')
    union all
    select 'carta_clinica',
      coalesce((select review_status='aprobado' from doc where template_code='C'),false),
      case
        when not exists(select 1 from doc where template_code='C') then 'Documento C pendiente de carga'
        when exists(select 1 from doc where template_code='C' and review_status='requiere_correccion') then 'Documento C requiere corrección'
        when exists(select 1 from doc where template_code='C' and review_status='aprobado') then 'Documento C cargado y aprobado por SOFA'
        else 'Documento C cargado; pendiente de revisión SOFA'
      end
    union all
    select 'tarifario',
      exists(select 1 from prov)
      and not exists(
        select 1 from prov p
        where not exists(
          select 1 from public.tariffs t
           where t.provider_id=p.id
             and t.status<>'suspendida'
             and t.valid_during @> current_date
        )
      ),
      'Tarifa vigente para cada médico'
    union all
    select 'secretaria',
      exists(select 1 from public.capturer_scopes cs where cs.organization_id=p_org)
      or exists(
        select 1 from public.contacts c
         where c.organization_id=p_org
           and c.contact_role='secretaria'
           and c.inducted_on is not null
      ),
      'Capturador asignado o secretaria inducida'
    union all
    select 'formulario',
      coalesce((select review_status='aprobado' from doc where template_code='E'),false),
      case
        when not exists(select 1 from doc where template_code='E') then 'Documento E pendiente de carga'
        when exists(select 1 from doc where template_code='E' and review_status='requiere_correccion') then 'Documento E requiere corrección'
        when exists(select 1 from doc where template_code='E' and review_status='aprobado') then 'Documento E cargado y aprobado por SOFA'
        else 'Documento E cargado; pendiente de revisión SOFA'
      end
    union all
    select 'primera_reclamacion',
      (exists(select 1 from public.service_lines l where l.organization_id=p_org)
       or app.opening_history_has_reviewed(p_org)),
      'Primera reclamación capturada o cartera anterior revisada'
  )
  select
    x.ord,x.code,x.label,
    (a.ok or coalesce(oi.done,false)) done,
    case
      when a.ok then 'automatico'
      when coalesce(oi.done,false) then 'manual'
      else 'pendiente'
    end source,
    case
      when a.ok then a.how
      when coalesce(oi.done,false) then coalesce('Marcado a mano: '||oi.notes,'Marcado a mano')
      else a.how
    end detail,
    case
      when a.ok and x.code='contrato' then (select reviewed_at from doc where template_code='A')
      when a.ok and x.code='autorizacion' then (select reviewed_at from doc where template_code='B')
      when a.ok and x.code='carta_clinica' then (select reviewed_at from doc where template_code='C')
      when a.ok and x.code='formulario' then (select reviewed_at from doc where template_code='E')
      when coalesce(oi.done,false) then oi.done_at
      else null
    end done_at
  from (values
    (1,'contrato','Contrato de servicios firmado (A)'),
    (2,'autorizacion','Autorización de representación firmada (B)'),
    (3,'datos_medico','Datos completos del médico'),
    (4,'ars_cartas','Cartas de representación ante ARS (D)'),
    (5,'carta_clinica','Carta de presentación a la clínica (C)'),
    (6,'tarifario','Tarifario contractual cargado'),
    (7,'secretaria','Secretaria registrada e inducida'),
    (8,'formulario','Formulario de implementación (E)'),
    (9,'primera_reclamacion','Primera reclamación capturada')
  ) x(ord,code,label)
  join auto a on a.code=x.code
  left join public.onboarding_items oi
    on oi.organization_id=p_org and oi.step_code=x.code
  order by x.ord;
$function$
;

CREATE OR REPLACE FUNCTION app.golive_auto(p_org uuid, p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  case p_code
    when 'contrato_firmado' then
      return exists (select 1 from public.commercial_documents d where d.organization_id = p_org and d.template_code = 'A' and d.status = 'firmado');
    when 'datos_medico' then
      return exists (select 1 from public.providers p where p.organization_id = p_org and p.is_active)
         and not exists (select 1 from public.providers p where p.organization_id = p_org and p.is_active and (p.tax_id is null or p.exequatur is null or p.specialty is null));
    when 'usuarios' then
      return exists (select 1 from public.organization_users ou join public.profiles pr on pr.id = ou.user_id and pr.is_active
                      where ou.organization_id = p_org and ou.role_code = 'client' and ou.is_active);
    when 'tarifario' then
      return exists (select 1 from public.providers p where p.organization_id = p_org and p.is_active)
         and not exists (select 1 from public.providers p where p.organization_id = p_org and p.is_active and not exists (
               select 1 from public.tariffs t where t.provider_id = p.id and t.status <> 'suspendida' and t.valid_during @> current_date));
    when 'ars_cartas' then
      return exists (select 1 from public.commercial_documents d where d.organization_id = p_org and d.template_code = 'D' and d.status in ('entregado','firmado'))
         and not exists (select 1 from public.tariffs t where t.organization_id = p_org and t.provider_id is not null and t.status <> 'suspendida'
                            and t.ars_id not in (select d.ars_id from public.commercial_documents d where d.organization_id = p_org and d.template_code = 'D'
                                                    and d.status in ('entregado','firmado') and d.ars_id is not null));
    when 'carga_pacientes' then
      return exists (select 1 from public.golive_load_batches b where b.organization_id = p_org and b.kind = 'pacientes' and b.rows_accepted > 0);
    when 'carga_citas' then
      return exists (select 1 from public.golive_load_batches b where b.organization_id = p_org and b.kind = 'citas' and b.rows_accepted > 0);
    when 'carga_cuentas' then
      return exists (select 1 from public.golive_load_batches b where b.organization_id = p_org and b.kind = 'cuentas' and b.rows_accepted > 0)
          or exists(select 1 from app.opening_history_items h where h.organization_id=p_org);
    else
      return null;
  end case;
end $function$
;

