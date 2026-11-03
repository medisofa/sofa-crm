-- ARS-scoped SIMON/CUPS: explicit authorization, then atomic application with tariffs.
-- A code exception is authorized first and applied with the tariff transaction.
create table app.tariff_code_authorizations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  provider_id uuid not null references public.providers(id),
  ars_id uuid not null references public.ars(id),
  procedure_id uuid not null references public.procedures(id),
  proposal jsonb not null,
  reason text not null check (length(trim(reason)) between 8 and 1000),
  authorized_by uuid not null,
  authorized_at timestamptz not null default now(),
  applied_at timestamptz
);
create index tariff_code_authorizations_org_idx on app.tariff_code_authorizations(organization_id);
create index tariff_code_authorizations_provider_idx on app.tariff_code_authorizations(provider_id);
create index tariff_code_authorizations_ars_idx on app.tariff_code_authorizations(ars_id);
create index tariff_code_authorizations_procedure_idx on app.tariff_code_authorizations(procedure_id);
alter table app.tariff_code_authorizations enable row level security;
create policy tariff_code_authorizations_actor_read on app.tariff_code_authorizations for select to authenticated
  using (authorized_by = (select auth.uid()) and app.is_staff(array['super_admin','admin','billing'])
    and coalesce(app.role_for_org(organization_id) = any(array['super_admin','admin','billing']), false));
revoke all on app.tariff_code_authorizations from public, anon, authenticated;
create trigger tariff_code_authorizations_audit after insert or update on app.tariff_code_authorizations
  for each row execute function app.audit();

create or replace function app.tariff_code_exception_prepare(p_org uuid, p_row jsonb, p_systems text[], p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_provider uuid; v_ars uuid; v_proc public.procedures%rowtype; v_ars_name text;
  v_codes jsonb := '[]'; v_system text; v_code text; v_specific public.procedure_codes%rowtype;
  v_general public.procedure_codes%rowtype;
begin
  if auth.uid() is null or not coalesce(app.is_staff(array['super_admin','admin','billing']), false)
     or not coalesce(app.role_for_org(p_org) = any(array['super_admin','admin','billing']), false) then
    raise exception 'Solo Administración o Facturación con acceso al cliente puede autorizar códigos exclusivos.' using errcode = '42501';
  end if;
  if p_systems is null or cardinality(p_systems) not between 1 and 2
     or exists (select 1 from unnest(p_systems) s where s is null or s not in ('SIMON','CUPS')) then
    raise exception 'Seleccione SIMON, CUPS o ambos.' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason, ''))) not between 8 and 1000 then
    raise exception 'Explique el motivo de la excepción (entre 8 y 1,000 caracteres).' using errcode = '22023';
  end if;
  select id into v_provider from public.providers where id::text = p_row->>'medico' and organization_id = p_org and is_active;
  select id, name into v_ars, v_ars_name from public.ars where id::text = p_row->>'ars' and is_active;
  select * into v_proc from public.procedures where is_active
    and (internal_code = upper(trim(p_row->>'servicio')) or lower(description) = lower(trim(p_row->>'servicio'))) limit 1;
  if v_provider is null or v_ars is null or v_proc.id is null then
    raise exception 'Indique un médico del cliente, una ARS activa y un Servicio/Código válido antes de proponer la excepción.' using errcode = '22023';
  end if;
  for v_system in select distinct s from unnest(p_systems) s order by s loop
    v_code := upper(trim(coalesce(p_row->>lower(v_system), '')));
    if length(v_code) not between 1 and 120 then
      raise exception 'El código % debe contener entre 1 y 120 caracteres.', v_system using errcode = '22023';
    end if;
    select * into v_specific from public.procedure_codes where code_system = v_system and ars_id = v_ars and upper(code) = v_code;
    select * into v_general from public.procedure_codes where code_system = v_system and ars_id is null and upper(code) = v_code;
    v_codes := v_codes || jsonb_build_array(jsonb_build_object('system', v_system, 'code', v_code,
      'previous_id', v_specific.id, 'previous_procedure_id', v_specific.procedure_id,
      'previous_description', (select description from public.procedures where id = v_specific.procedure_id),
      'general_procedure_id', v_general.procedure_id,
      'general_description', (select description from public.procedures where id = v_general.procedure_id)));
  end loop;
  return jsonb_build_object('organization_id', p_org, 'provider_id', v_provider, 'ars_id', v_ars, 'ars_name', v_ars_name,
    'procedure_id', v_proc.id, 'service_code', v_proc.internal_code, 'service_description', v_proc.description,
    'codes', v_codes, 'reason', trim(p_reason), 'source_file', p_row->>'source_file', 'source_line', p_row->>'source_line');
end $$;
revoke all on function app.tariff_code_exception_prepare(uuid,jsonb,text[],text) from public, anon;
grant execute on function app.tariff_code_exception_prepare(uuid,jsonb,text[],text) to authenticated;

create or replace function app.tariff_code_exception_authorize(p_org uuid, p_row jsonb, p_systems text[], p_reason text, p_expected jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_proposal jsonb; v_id uuid; v_at timestamptz;
begin
  v_proposal := app.tariff_code_exception_prepare(p_org, p_row, p_systems, p_reason);
  if p_expected is distinct from v_proposal then
    raise exception 'La propuesta o el catálogo cambió. Revise nuevamente la propuesta antes de autorizar.' using errcode = '40001';
  end if;
  insert into app.tariff_code_authorizations(organization_id,provider_id,ars_id,procedure_id,proposal,reason,authorized_by)
  values(p_org,(v_proposal->>'provider_id')::uuid,(v_proposal->>'ars_id')::uuid,(v_proposal->>'procedure_id')::uuid,v_proposal,trim(p_reason),auth.uid())
  returning id, authorized_at into v_id, v_at;
  return jsonb_build_object('id',v_id,'authorized_at',v_at,'authorized_by',auth.uid(),'proposal',v_proposal);
end $$;
revoke all on function app.tariff_code_exception_authorize(uuid,jsonb,text[],text,jsonb) from public, anon;
grant execute on function app.tariff_code_exception_authorize(uuid,jsonb,text[],text,jsonb) to authenticated;

create or replace function public.tariff_code_exception_prepare(p_org uuid, p_row jsonb, p_systems text[], p_reason text)
returns jsonb language sql security invoker set search_path = '' as $$
  select app.tariff_code_exception_prepare(p_org,p_row,p_systems,p_reason);
$$;
create or replace function public.tariff_code_exception_authorize(p_org uuid, p_row jsonb, p_systems text[], p_reason text, p_expected jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select app.tariff_code_exception_authorize(p_org,p_row,p_systems,p_reason,p_expected);
$$;
revoke all on function public.tariff_code_exception_prepare(uuid,jsonb,text[],text) from public, anon;
revoke all on function public.tariff_code_exception_authorize(uuid,jsonb,text[],text,jsonb) from public, anon;
grant execute on function public.tariff_code_exception_prepare(uuid,jsonb,text[],text) to authenticated;
grant execute on function public.tariff_code_exception_authorize(uuid,jsonb,text[],text,jsonb) to authenticated;

create or replace function app.tariff_resolve_code(p_ars uuid, p_provider uuid, p_system text, p_code text, p_authorization uuid default null)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_auth app.tariff_code_authorizations%rowtype; v_entry jsonb; v_result uuid;
begin
  if auth.uid() is null or not coalesce(app.is_active_user(),false) then
    raise exception 'Inicie sesión para consultar códigos de servicio.' using errcode = '42501';
  end if;
  if p_authorization is not null then
    select * into v_auth from app.tariff_code_authorizations where id = p_authorization and authorized_by = auth.uid()
      and ars_id = p_ars and provider_id = p_provider;
    if v_auth.id is null or not coalesce(app.is_staff(array['super_admin','admin','billing']),false)
       or not coalesce(app.role_for_org(v_auth.organization_id) = any(array['super_admin','admin','billing']),false) then
      raise exception 'La autorización no corresponde a este usuario, cliente, médico o ARS. Vuelva a autorizar la excepción.' using errcode = '42501';
    end if;
    select x into v_entry from jsonb_array_elements(v_auth.proposal->'codes') x where x->>'system' = p_system;
    if v_entry is not null then
      if v_entry->>'code' is distinct from upper(trim(p_code)) then
        raise exception 'El código cambió después de autorizar. Revise y autorice nuevamente.' using errcode = '22023';
      end if;
      return v_auth.procedure_id;
    end if;
  end if;
  -- A different ARS's code must never participate in this lookup.
  select procedure_id into v_result from public.procedure_codes
    where code_system = p_system and upper(code) = upper(trim(p_code)) and (ars_id = p_ars or ars_id is null)
    order by (ars_id is not null) desc limit 1;
  return v_result;
end $$;
revoke all on function app.tariff_resolve_code(uuid,uuid,text,text,uuid) from public, anon;
grant execute on function app.tariff_resolve_code(uuid,uuid,text,text,uuid) to authenticated;

create or replace function app.tariff_apply_code_authorizations(p_rows jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare e jsonb; v_auth app.tariff_code_authorizations%rowtype; v_entry jsonb;
  v_current public.procedure_codes%rowtype; v_proc uuid; v_provider uuid; v_ars uuid;
begin
  if not exists (select 1 from jsonb_array_elements(p_rows) x where nullif(x->>'code_authorization','') is not null) then return; end if;
  if auth.uid() is null or not coalesce(app.is_staff(array['super_admin','admin','billing']),false) then
    raise exception 'No tiene permiso para aplicar códigos exclusivos.' using errcode = '42501';
  end if;
  -- Infrequent catalog writes are serialized; tariff rows remain one atomic transaction.
  perform pg_advisory_xact_lock(hashtextextended('sofa.tariff_code_authorizations',0));
  for e in select x from jsonb_array_elements(p_rows) x where nullif(x->>'code_authorization','') is not null loop
    select * into v_auth from app.tariff_code_authorizations where id = (e->>'code_authorization')::uuid for update;
    if v_auth.id is null or v_auth.authorized_by <> auth.uid()
      or not coalesce(app.role_for_org(v_auth.organization_id) = any(array['super_admin','admin','billing']),false) then
      raise exception 'La autorización no está disponible para este usuario o cliente.' using errcode = '42501';
    end if;
    select id into v_provider from public.providers where id::text = e->>'medico' and organization_id = v_auth.organization_id and is_active;
    select id into v_ars from public.ars where id::text = e->>'ars' and is_active;
    select id into v_proc from public.procedures where is_active and (internal_code = upper(trim(e->>'servicio')) or lower(description) = lower(trim(e->>'servicio'))) limit 1;
    if v_provider is distinct from v_auth.provider_id or v_ars is distinct from v_auth.ars_id or v_proc is distinct from v_auth.procedure_id then
      raise exception 'El médico, ARS o servicio cambió después de autorizar. Revise la excepción.' using errcode = '22023';
    end if;
    for v_entry in select x from jsonb_array_elements(v_auth.proposal->'codes') x loop
      if upper(trim(coalesce(e->>lower(v_entry->>'system'),''))) is distinct from v_entry->>'code' then
        raise exception 'Un código cambió después de autorizar. Autorice nuevamente.' using errcode = '22023';
      end if;
      select * into v_current from public.procedure_codes where code_system = v_entry->>'system'
        and ars_id = v_auth.ars_id and upper(code) = v_entry->>'code' for update;
      if v_auth.applied_at is not null then
        if v_current.procedure_id is distinct from v_auth.procedure_id then
          raise exception 'El código exclusivo cambió desde su autorización. Revise nuevamente.' using errcode = '40001';
        end if;
      else
        if v_current.id is distinct from nullif(v_entry->>'previous_id','')::uuid
          or v_current.procedure_id is distinct from nullif(v_entry->>'previous_procedure_id','')::uuid then
          raise exception 'Otro usuario modificó el código exclusivo. Revise y autorice la propuesta actualizada.' using errcode = '40001';
        end if;
        if v_current.id is null then
          insert into public.procedure_codes(procedure_id,code_system,ars_id,code)
          values(v_auth.procedure_id,v_entry->>'system',v_auth.ars_id,v_entry->>'code');
        else
          update public.procedure_codes set procedure_id = v_auth.procedure_id where id = v_current.id;
        end if;
      end if;
    end loop;
    update app.tariff_code_authorizations set applied_at = coalesce(applied_at,now()) where id = v_auth.id;
  end loop;
end $$;
revoke all on function app.tariff_apply_code_authorizations(jsonb) from public, anon;
grant execute on function app.tariff_apply_code_authorizations(jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.import_contract_tariffs(p_rows jsonb, p_commit boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare e jsonb; i int := 0; v_err jsonb := '[]'::jsonb; v_ok jsonb := '[]'::jsonb; v_prov uuid; v_ars uuid; v_proc uuid; v_proc2 uuid;
        v_amount numeric; v_from date; v_to date; v_key text; v_keys jsonb := '{}'::jsonb; v_msgs text[]; r jsonb; v_n int := 0; v_txt text;
        v_plan uuid;   -- 2.6.1: plan opcional
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'No hay filas para importar' using errcode = '22023'; end if;
  if jsonb_array_length(p_rows) > 5000 then raise exception 'Máximo 5,000 filas por importación' using errcode = '22023'; end if;
  for e in select * from jsonb_array_elements(p_rows) loop
    i := i + 1; v_msgs := '{}'; v_prov := null; v_ars := null; v_proc := null; v_proc2 := null; v_amount := null; v_from := null; v_to := null; v_plan := null;
    -- Médico: id, cédula/RNC, exequátur o nombre exacto
    v_txt := trim(coalesce(e->>'medico', ''));
    select id into v_prov from public.providers pr
     where pr.is_active and (pr.id::text = v_txt or pr.tax_id = v_txt or pr.exequatur = v_txt or lower(pr.full_name) = lower(v_txt)) limit 2;
    if v_prov is null then v_msgs := array_append(v_msgs, (('Médico inexistente: ' || v_txt))::text); end if;
    v_txt := trim(coalesce(e->>'ars', ''));
    select id into v_ars from public.ars a where a.is_active and (a.id::text = v_txt or lower(a.code) = lower(v_txt) or lower(a.name) = lower(v_txt)) limit 1;
    if v_ars is null then v_msgs := array_append(v_msgs, (('ARS inexistente: ' || v_txt))::text); end if;
    -- 2.6.1 · Plan (opcional): id o nombre de un plan activo de esa ARS
    v_txt := trim(coalesce(e->>'plan', ''));
    if v_txt <> '' then
      select ap.id into v_plan from public.ars_plans ap where ap.ars_id = v_ars and ap.is_active and (ap.id::text = v_txt or lower(ap.name) = lower(v_txt)) limit 1;
      if v_plan is null then v_msgs := array_append(v_msgs, (('Plan inexistente para esa ARS: ' || v_txt))::text); end if;
    end if;
    -- Servicio: código interno o nombre; y/o SIMON / CUPS (deben coincidir entre sí)
    v_txt := trim(coalesce(e->>'servicio', ''));
    if v_txt <> '' then
      select id into v_proc from public.procedures p where p.is_active and (p.internal_code = upper(v_txt) or lower(p.description) = lower(v_txt)) limit 1;
      if v_proc is null then v_msgs := array_append(v_msgs, (('Servicio inexistente en el catálogo: ' || v_txt))::text); end if;
    end if;
    if nullif(trim(coalesce(e->>'simon', '')), '') is not null then
      v_proc2 := app.tariff_resolve_code(v_ars, v_prov, 'SIMON', e->>'simon', nullif(e->>'code_authorization','')::uuid);
      if v_proc2 is null then v_msgs := array_append(v_msgs, (('Código SIMON inexistente: ' || trim(e->>'simon')))::text);
      elsif v_proc is not null and v_proc <> v_proc2 then v_msgs := array_append(v_msgs, ('El código SIMON corresponde a otro servicio')::text);
      else v_proc := coalesce(v_proc, v_proc2); end if;
    end if;
    v_proc2 := null;
    if nullif(trim(coalesce(e->>'cups', '')), '') is not null then
      v_proc2 := app.tariff_resolve_code(v_ars, v_prov, 'CUPS', e->>'cups', nullif(e->>'code_authorization','')::uuid);
      if v_proc2 is null then v_msgs := array_append(v_msgs, (('Código CUPS inexistente: ' || trim(e->>'cups')))::text);
      elsif v_proc is not null and v_proc <> v_proc2 then v_msgs := array_append(v_msgs, ('El código CUPS corresponde a otro servicio')::text);
      else v_proc := coalesce(v_proc, v_proc2); end if;
    end if;
    if v_proc is null and v_txt = '' and nullif(trim(coalesce(e->>'simon', '')), '') is null and nullif(trim(coalesce(e->>'cups', '')), '') is null then
      v_msgs := array_append(v_msgs, ('Falta el servicio (código interno, nombre, SIMON o CUPS)')::text);
    end if;
    begin v_amount := replace(replace(trim(coalesce(e->>'tarifa', '')), 'RD$', ''), ',', '')::numeric; exception when others then v_amount := null; end;
    if v_amount is null or v_amount <= 0 or v_amount > 10000000 then v_msgs := array_append(v_msgs, (('Tarifa inválida: ' || coalesce(e->>'tarifa', '')))::text); end if;
    v_from := app.parse_date_do(e->>'desde');
    if v_from is null then v_msgs := array_append(v_msgs, (('Fecha de inicio inválida: ' || coalesce(e->>'desde', '')))::text); end if;
    if nullif(trim(coalesce(e->>'hasta', '')), '') is not null then
      v_to := app.parse_date_do(e->>'hasta');
      if v_to is null then v_msgs := array_append(v_msgs, (('Fecha fin inválida: ' || (e->>'hasta')))::text);
      elsif v_from is not null and v_to < v_from then v_msgs := array_append(v_msgs, ('La fecha fin es anterior al inicio')::text); end if;
    end if;
    if v_prov is not null and v_ars is not null and v_proc is not null and v_from is not null and (v_to is null or v_to >= v_from) then
      v_key := v_prov || '|' || v_ars || '|' || v_proc || '|' || coalesce(v_plan::text, '');
      -- Duplicados y superposición dentro del archivo
      for r in select * from jsonb_array_elements(coalesce(v_keys->v_key, '[]'::jsonb)) loop
        if daterange(v_from, case when v_to is null then null else v_to + 1 end) && daterange((r->>'f')::date, case when r->>'t' is null then null else (r->>'t')::date + 1 end) then
          v_msgs := array_append(v_msgs, (('Duplicado o vigencia superpuesta con la fila ' || (r->>'row')))::text);
        end if;
      end loop;
      v_keys := jsonb_set(v_keys, array[v_key], coalesce(v_keys->v_key, '[]'::jsonb) || jsonb_build_object('row', i, 'f', v_from, 't', v_to));
      -- Contra lo existente (mismo plan; sin plan = tarifa general del médico)
      if v_to is not null and exists (select 1 from public.tariffs t where t.provider_id = v_prov and t.ars_id = v_ars and t.procedure_id = v_proc and t.plan_id is not distinct from v_plan
                                        and t.valid_during && daterange(v_from, v_to + 1)) then
        v_msgs := array_append(v_msgs, 'Vigencia superpuesta con una tarifa existente del mismo médico, ARS y servicio'::text);
      elsif v_to is null and exists (select 1 from public.tariffs t where t.provider_id = v_prov and t.ars_id = v_ars and t.procedure_id = v_proc and t.plan_id is not distinct from v_plan
                                        and lower(t.valid_during) >= v_from) then
        v_msgs := array_append(v_msgs, 'Ya existe una vigencia que inicia en o después de esta fecha para el mismo médico, ARS y servicio'::text);
      end if;
    end if;
    if array_length(v_msgs, 1) is not null then
      v_err := v_err || jsonb_build_object('row', i, 'errors', to_jsonb(v_msgs), 'data', e);
    else
      v_ok := v_ok || jsonb_build_object('row', i, 'provider_id', v_prov, 'ars_id', v_ars, 'procedure_id', v_proc, 'amount', v_amount,
                                        'valid_from', v_from, 'valid_to', v_to, 'contract', nullif(trim(coalesce(e->>'contrato', '')), ''),
                                        'provider', (select full_name from public.providers where id = v_prov), 'ars', (select name from public.ars where id = v_ars),
                                        'service', (select description from public.procedures where id = v_proc),
                                        'plan_id', v_plan, 'plan', (select name from public.ars_plans where id = v_plan));
    end if;
  end loop;
  if p_commit then
    if jsonb_array_length(v_err) > 0 then raise exception 'Corrija las % filas con errores antes de importar', jsonb_array_length(v_err) using errcode = '23514'; end if;
    perform app.tariff_apply_code_authorizations(p_rows);
    for r in select * from jsonb_array_elements(v_ok) x order by (x->>'valid_from')::date loop
      perform public.create_contract_tariff_plan((r->>'provider_id')::uuid, (r->>'ars_id')::uuid, nullif(r->>'plan_id', '')::uuid, (r->>'procedure_id')::uuid,
                                                 (r->>'amount')::numeric, (r->>'valid_from')::date, (r->>'valid_to')::date, r->>'contract', null, 'Importación');
      v_n := v_n + 1;
    end loop;
  end if;
  return jsonb_build_object('total', i, 'valid', jsonb_array_length(v_ok), 'errors', v_err, 'rows', v_ok, 'imported', v_n);
end $function$
;

CREATE OR REPLACE FUNCTION public.import_contract_tariffs_v2(p_rows jsonb, p_commit boolean DEFAULT false, p_file text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_rep jsonb; r jsonb; v_cur numeric; v_status text; v_rows jsonb := '[]'::jsonb; v_keep jsonb := '[]'::jsonb;
        n_new int := 0; n_chg int := 0; n_same int := 0; v_imp int := 0; v_org uuid; v_prov uuid; v_ars uuid; v_plan uuid; i int;
begin
  v_rep := public.import_contract_tariffs(p_rows, false);
  for r in select * from jsonb_array_elements(v_rep->'rows') loop
    select t.amount into v_cur from public.tariffs t
     where t.provider_id = (r->>'provider_id')::uuid and t.ars_id = (r->>'ars_id')::uuid and t.procedure_id = (r->>'procedure_id')::uuid
       and t.plan_id is not distinct from nullif(r->>'plan_id', '')::uuid and t.valid_during @> current_date and t.status = 'vigente'
     order by lower(t.valid_during) desc limit 1;
    v_status := case when v_cur is null then 'nueva' when v_cur = (r->>'amount')::numeric then 'igual' else 'cambia' end;
    if v_status = 'nueva' then n_new := n_new + 1; elsif v_status = 'cambia' then n_chg := n_chg + 1; else n_same := n_same + 1; end if;
    v_rows := v_rows || (r || jsonb_build_object('current', v_cur, 'change', v_status,
                         'diff_pct', case when v_cur > 0 and v_status = 'cambia' then round(((r->>'amount')::numeric - v_cur) / v_cur * 100, 1) end));
    if v_status <> 'igual' then v_keep := v_keep || jsonb_build_array(p_rows->((r->>'row')::int - 1)); end if;
    v_prov := coalesce(v_prov, (r->>'provider_id')::uuid); v_ars := coalesce(v_ars, (r->>'ars_id')::uuid); v_plan := coalesce(v_plan, nullif(r->>'plan_id', '')::uuid);
  end loop;
  if p_commit then
    if jsonb_array_length(v_rep->'errors') > 0 then
      raise exception 'Corrija las % filas con errores antes de importar (las filas con error no se guardan).', jsonb_array_length(v_rep->'errors') using errcode = '23514';
    end if;
    perform app.tariff_apply_code_authorizations(p_rows);
    if jsonb_array_length(v_keep) > 0 then
      v_imp := (public.import_contract_tariffs(v_keep, true)->>'imported')::int;
    end if;
    select organization_id into v_org from public.providers where id = v_prov;
    if v_org is not null then
      perform app.tariff_import_log_add2(v_org, v_prov, v_ars, v_plan, p_file, (select nullif(trim(coalesce(p_rows->0->>'contrato', '')), '')),
        app.parse_date_do(p_rows->0->>'desde'), app.parse_date_do(nullif(p_rows->0->>'hasta', '')),
        jsonb_array_length(p_rows), n_new, n_chg, n_same, v_imp);
    end if;
  end if;
  return jsonb_build_object('total', v_rep->'total', 'valid', v_rep->'valid', 'errors', v_rep->'errors', 'rows', v_rows,
                            'new', n_new, 'changed', n_chg, 'same', n_same, 'imported', v_imp);
end
$function$
;

