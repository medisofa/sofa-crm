-- 213 · Dependencias para reclamaciones sin radicación
-- Hace que controles existentes usen las claves estructurales de service_lines cuando submission_id es NULL.
begin;

CREATE OR REPLACE FUNCTION app.guard_service_line()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.submissions; t public.tariffs; v_role text; v_track boolean := coalesce(current_setting('app.claim_change', true), '') = 'on';
        v_content boolean; v_op uuid; v_org uuid; v_prov uuid; v_r text; v_chg_auth boolean; v_chg_pat boolean; v_chg_cen boolean; v_dup record;
begin
  -- Iteración 14: reenvío controlado a una radicación complementaria (public.resubmit_claims). Solo cambia el lote.
  if tg_op = 'UPDATE' and coalesce(current_setting('app.claim_resubmit', true), '') = 'on' then
    -- amount es columna calculada: en un BEFORE UPDATE todavía no está recalculada (se excluye de la comparación)
    if (to_jsonb(new) - 'submission_id' - 'updated_at' - 'updated_by' - 'amount') is distinct from (to_jsonb(old) - 'submission_id' - 'updated_at' - 'updated_by' - 'amount') then
      raise exception 'El reenvío solo cambia la radicación de la reclamación (cambió: %)',
        (select string_agg(k.key, ', ') from jsonb_each(to_jsonb(new)) k where k.value is distinct from to_jsonb(old) -> k.key and k.key not in ('submission_id','updated_at','updated_by','amount'))
        using errcode = '42501';
    end if;
    return new;
  end if;
  -- 4.5.1 (SEG-08) · paciente y centro deben ser del mismo cliente; fecha de autorización, paciente y centro se protegen por estado
  if tg_op in ('INSERT','UPDATE') then
    v_org := coalesce(new.organization_id, (select s0.organization_id from public.submissions s0 where s0.id = new.submission_id));
    if new.patient_id is not null and (tg_op = 'INSERT' or new.patient_id is distinct from old.patient_id)
       and not exists (select 1 from public.patients pa where pa.id = new.patient_id and pa.organization_id = v_org) then
      raise exception 'Ese paciente no pertenece a este cliente. Elija un paciente de la lista del mismo consultorio.' using errcode = '23514';
    end if;
    if new.center_id is not null and (tg_op = 'INSERT' or new.center_id is distinct from old.center_id)
       and not exists (select 1 from public.health_centers hc where hc.id = new.center_id and hc.organization_id = v_org) then
      raise exception 'Ese centro no pertenece a este cliente. Elija un centro de la lista del mismo consultorio.' using errcode = '23514';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    v_chg_auth := old.authorization_date is not null and new.authorization_date is distinct from old.authorization_date;
    v_chg_pat  := old.patient_id is not null and new.patient_id is not null and new.patient_id is distinct from old.patient_id;
    v_chg_cen  := old.center_id is not null and new.center_id is not null and new.center_id is distinct from old.center_id;
    if v_chg_auth or v_chg_pat or v_chg_cen then
      if not (old.claim_status = any (array['pendiente_configuracion','capturada','pendiente_retiro','retirada','en_validacion','con_inconsistencia','validada','lista_para_radicar'])) then
        raise exception 'La reclamación % está en "%": la fecha de autorización, el paciente y el centro ya no se cambian. Si hay un error, pida a Operaciones que la devuelva.', old.claim_folio, old.claim_status using errcode = '42501';
      end if;
      if v_chg_auth and auth.uid() is not null and coalesce(current_setting('app.claim_authdate', true), '') <> 'on' then
        raise exception 'La fecha de autorización se cambia desde el botón «Fecha de autorización» de la reclamación, que verifica su permiso.' using errcode = '42501';
      end if;
      if (v_chg_pat or v_chg_cen) and auth.uid() is not null then
        v_prov := coalesce(old.provider_id, (select s1.provider_id from public.submissions s1 where s1.id = old.submission_id));
        v_r := app.claim_access_role(old.organization_id, v_prov);
        if v_r in ('client','capturer') and not (old.claim_status = any (app.claim_capture_states())) then
          raise exception 'La reclamación % está en "%": ya no puede cambiar su paciente ni su centro desde el consultorio.', old.claim_folio, old.claim_status using errcode = '42501';
        end if;
      end if;
    end if;
  end if;
  -- Cambios de seguimiento (estado, ubicación, responsable): solo con las funciones de reclamación
  if tg_op = 'UPDATE' and (new.claim_status, new.location_code, new.custodian_id, new.custodian_label, new.status_changed_at,
                           new.contract_override_reason, new.contract_override_by, new.claim_folio)
       is distinct from (old.claim_status, old.location_code, old.custodian_id, old.custodian_label, old.status_changed_at,
                         old.contract_override_reason, old.contract_override_by, old.claim_folio) and not v_track then
    raise exception 'El estado, la ubicación y el responsable de una reclamación solo cambian con las funciones de seguimiento' using errcode = '42501';
  end if;
  v_content := tg_op <> 'UPDATE' or coalesce(current_setting('app.claim_recheck', true), '') = 'on' or (new.service_date, new.patient_name, new.patient_doc, new.member_number, new.authorization_number, new.procedure_id,
                                      new.quantity, new.unit_amount, new.notes, new.care_mode, new.clinic_name, new.submission_id, new.plan_id)
                          is distinct from (old.service_date, old.patient_name, old.patient_doc, old.member_number, old.authorization_number, old.procedure_id,
                                            old.quantity, old.unit_amount, old.notes, old.care_mode, old.clinic_name, old.submission_id, old.plan_id);
  if tg_op = 'UPDATE' and not v_content then
    if (new.provider_id,new.ars_id) is distinct from (old.provider_id,old.ars_id) then
      raise exception 'El médico y la ARS de una reclamación no se cambian después de capturarla' using errcode='42501';
    end if;
    if (new.tariff_id, new.tariff_amount, new.contracted, new.amount_ok, new.service_name_snapshot, new.simon_code_snapshot, new.cups_code_snapshot,
        new.contract_ref_snapshot, new.tariff_valid_from, new.tariff_valid_to, new.captured_via, new.organization_id, new.created_by)
       is distinct from (old.tariff_id, old.tariff_amount, old.contracted, old.amount_ok, old.service_name_snapshot, old.simon_code_snapshot, old.cups_code_snapshot,
        old.contract_ref_snapshot, old.tariff_valid_from, old.tariff_valid_to, old.captured_via, old.organization_id, old.created_by)
       and coalesce(current_setting('app.claim_reprice', true), '') <> 'on' then
      raise exception 'La tarifa y la fotografía contractual de una reclamación no se editan' using errcode = '42501';
    end if;
    return new;   -- solo seguimiento (o recálculo controlado)
  end if;

  if coalesce(new.submission_id, old.submission_id) is null then
    s.organization_id := coalesce(new.organization_id, old.organization_id);
    s.provider_id := coalesce(new.provider_id, old.provider_id);
    s.ars_id := coalesce(new.ars_id, old.ars_id);
    s.plan_id := coalesce(new.plan_id, old.plan_id);
    s.period := date_trunc('month', coalesce(new.service_date, old.service_date))::date;
    s.status := 'borrador';
    if s.organization_id is null or s.provider_id is null or s.ars_id is null then
      raise exception 'La reclamación sin lote requiere cliente, médico y ARS' using errcode = '23514';
    end if;
  else
    s := app.assert_submission_editable(coalesce(new.submission_id, old.submission_id));
  end if;
  -- Estados de la reclamación que admiten cambios de contenido
  if auth.uid() is not null then
    v_role := app.claim_access_role(s.organization_id, s.provider_id);
    if v_role is null then raise exception 'Sin acceso a las reclamaciones de este médico' using errcode = '42501'; end if;
    if tg_op in ('UPDATE','DELETE') then
      if v_role in ('client','capturer') and not (old.claim_status = any (app.claim_capture_states())) then
        raise exception 'La reclamación % está en "%": ya no la puede modificar el consultorio', old.claim_folio, old.claim_status using errcode = '42501';
      elsif not (old.claim_status = any (app.claim_staff_edit_states())) then
        raise exception 'La reclamación % está en "%" y no admite cambios', old.claim_folio, old.claim_status using errcode = '23514';
      end if;
      if tg_op = 'DELETE' and not (old.claim_status = any (app.claim_capture_states())) then
        raise exception 'Solo se eliminan reclamaciones que aún no fueron retiradas' using errcode = '23514';
      end if;
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;

  -- 4.7.0 (SEG-34) · cantidad: entero positivo con tope (las filas antiguas con decimales no se tocan si no se cambia la cantidad)
  if tg_op = 'INSERT' or new.quantity is distinct from old.quantity then
    if new.quantity is null or new.quantity <> trunc(new.quantity) or new.quantity < 1 or new.quantity > 999 then
      raise exception 'La cantidad debe ser un número entero entre 1 y 999 (recibió %). Si es un paquete, regístrelo como una unidad con el monto del paquete.', new.quantity using errcode = '22023';
    end if;
  end if;
  -- 4.7.0 (SEG-34) · inserción directa (sin capture_claim): no se salta los controles de la captura
  if tg_op = 'INSERT' and auth.uid() is not null and coalesce(current_setting('app.claim_capture', true), '') <> 'on' then
    new.captured_via := 'manual';   -- solo capture_claim marca «captura_rapida»
    if new.member_number is not null and length(trim(new.member_number)) < 3 then
      raise exception 'El NSS o número de afiliado debe tener al menos 3 caracteres (o déjelo vacío y complételo antes de radicar).' using errcode = '22023';
    end if;
    if new.center_id is not null and not exists (select 1 from public.provider_centers pc where pc.provider_id = s.provider_id and pc.center_id = new.center_id) then
      raise exception 'El centro de salud elegido no está asignado a este médico. Elija uno de su lista o pida al Administrador que lo asigne.' using errcode = '23514';
    end if;
    select l2.claim_folio, l2.patient_name, l2.service_date into v_dup
      from public.service_lines l2 left join public.submissions s2 on s2.id = l2.submission_id
     where l2.organization_id = s.organization_id and coalesce(l2.ars_id,s2.ars_id) = s.ars_id and (s2.id is null or s2.status not in ('rechazada','cerrada'))
       and ((nullif(trim(coalesce(new.member_number, '')), '') is not null and l2.member_number = trim(new.member_number) and l2.service_date = new.service_date and l2.procedure_id = new.procedure_id)
            or (nullif(trim(coalesce(new.authorization_number, '')), '') is not null and l2.authorization_number = trim(new.authorization_number)))
     limit 1;
    if found and coalesce(v_role, '') not in ('super_admin','admin','billing') then
      raise exception 'Posible reclamación duplicada: % (%, %). Pida a Facturación o a un Administrador que la registre si de verdad corresponde.', v_dup.claim_folio, v_dup.patient_name, to_char(v_dup.service_date, 'DD/MM/YYYY') using errcode = '23505';
    end if;
  end if;

  if new.service_date < s.period or new.service_date >= (s.period + interval '1 month')::date then
    raise exception 'La fecha % está fuera del período de la radicación (%)', new.service_date, to_char(s.period, 'MM/YYYY') using errcode = '23514';
  end if;
  if new.service_date > current_date then
    raise exception 'La fecha del servicio no puede ser futura' using errcode = '23514';
  end if;

  -- Tarifa: la contractual del médico manda; se congela con su fotografía al crear o si cambian servicio o fecha
  if tg_op = 'INSERT' or new.procedure_id is distinct from old.procedure_id or new.service_date is distinct from old.service_date
     or coalesce(current_setting('app.claim_recheck', true), '') = 'on' then
    t := app.contract_tariff_for(s.provider_id, s.ars_id, new.procedure_id, new.service_date, coalesce(new.plan_id, s.plan_id));
    if t.id is not null then
      new.contracted := true; new.tariff_id := t.id; new.tariff_amount := t.amount;
      new.contract_ref_snapshot := t.contract_ref; new.tariff_valid_from := lower(t.valid_during); new.tariff_valid_to := upper(t.valid_during) - 1;
    else
      t := app.tariff_for(new.procedure_id, s.ars_id, new.service_date, s.provider_id, coalesce(new.plan_id, s.plan_id));   -- referencia (no contractual)
      new.contracted := false; new.tariff_id := t.id; new.tariff_amount := t.amount;
      new.contract_ref_snapshot := null; new.tariff_valid_from := lower(t.valid_during); new.tariff_valid_to := upper(t.valid_during) - 1;
    end if;
    select p.description,
           (select string_agg(c.code, ' · ' order by c.code) from public.procedure_codes c where c.procedure_id = p.id and c.code_system = 'SIMON'),
           (select string_agg(c.code, ' · ' order by c.code) from public.procedure_codes c where c.procedure_id = p.id and c.code_system = 'CUPS')
      into new.service_name_snapshot, new.simon_code_snapshot, new.cups_code_snapshot
      from public.procedures p where p.id = new.procedure_id;
  elsif (new.tariff_id, new.tariff_amount) is distinct from (old.tariff_id, old.tariff_amount) then
    raise exception 'La tarifa congelada de una línea no se edita' using errcode = '42501';
  end if;
  if new.unit_amount is null then new.unit_amount := new.tariff_amount; end if;
  new.amount_ok := new.contracted and new.tariff_amount is not null and new.unit_amount = new.tariff_amount;

  if tg_op = 'INSERT' then
    select o.operator_id into v_op from public.organizations o where o.id = s.organization_id;
    new.claim_folio := coalesce(new.claim_folio, app.next_folio(coalesce(v_op, s.organization_id), 'REC'));
    if not v_track then
      new.claim_status := case when not new.contracted and coalesce(current_setting('app.contract_override', true), '') <> 'on'
                               then 'pendiente_configuracion' else 'capturada' end;
      new.location_code := 'consultorio'; new.custodian_id := null;
      new.custodian_label := coalesce(nullif(new.clinic_name, ''), 'Consultorio');
      new.status_changed_at := now();
    end if;
    new.created_by := coalesce(new.created_by, auth.uid());
  end if;
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end $function$


create or replace function app.service_line_plan()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare v_ars uuid;
begin
  if new.plan_id is null and new.patient_id is not null
     and (tg_op='INSERT' or new.patient_id is distinct from old.patient_id) then
    v_ars := coalesce(new.ars_id,(select s.ars_id from public.submissions s where s.id=new.submission_id));
    select p.plan_id into new.plan_id
      from public.patients p
      join public.ars_plans ap on ap.id=p.plan_id
     where p.id=new.patient_id and ap.ars_id=v_ars;
  end if;
  return new;
end $$;

create or replace function app.guard_plan_claims()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare v_prov uuid; v_org uuid; v_name text; v_used integer; v_old_prov uuid;
begin
  if auth.uid() is null then return new; end if;
  v_prov := coalesce(new.provider_id,(select s.provider_id from public.submissions s where s.id=new.submission_id));
  v_org  := coalesce(new.organization_id,(select s.organization_id from public.submissions s where s.id=new.submission_id));
  if v_prov is null or not app.plans_enforced(v_org) then return new; end if;

  if tg_op='UPDATE' then
    if new.created_at is distinct from old.created_at then
      raise exception 'La fecha en que se capturó la reclamación no se modifica: con ella se cuenta el límite mensual de su plan.' using errcode='42501';
    end if;
    if new.submission_id is not distinct from old.submission_id
       and new.provider_id is not distinct from old.provider_id then return new; end if;
    v_old_prov := coalesce(old.provider_id,(select s.provider_id from public.submissions s where s.id=old.submission_id));
    if v_old_prov is not distinct from v_prov then return new; end if;
  else
    new.created_at := now();
  end if;

  perform pg_advisory_xact_lock(hashtextextended('plan:'||v_org::text,0));
  select p.full_name into v_name from public.providers p where p.id=v_prov;
  select count(*)::int into v_used
    from public.service_lines sl
    left join public.submissions s on s.id=sl.submission_id
   where coalesce(sl.provider_id,s.provider_id)=v_prov
     and sl.created_at>=app.plan_month_start()
     and sl.id<>new.id;
  perform app.plan_guard(v_org,'reclamaciones_mes_por_medico',v_used+1,v_name);
  return new;
end $$;

create or replace function app.plan_claims_used(p_provider uuid)
returns integer
language sql stable security definer set search_path=''
as $$
  select count(*)::int
    from public.service_lines sl
    left join public.submissions s on s.id=sl.submission_id
   where coalesce(sl.provider_id,s.provider_id)=p_provider
     and sl.created_at>=app.plan_month_start()
$$;

create or replace function app.claim_role(p_line uuid)
returns text
language sql stable security definer set search_path=''
as $$
  select app.claim_access_role(l.organization_id,coalesce(l.provider_id,s.provider_id))
    from public.service_lines l
    left join public.submissions s on s.id=l.submission_id
   where l.id=p_line
$$;

create or replace function app.claim_dossier_items(p_line uuid)
returns table(document_type_code text,name text,sort_order integer,mandatory boolean,checked boolean,files integer,present boolean,rule_id uuid)
language plpgsql stable set search_path=''
as $$
begin
  return query
  select r.document_type_code,dt.name,dt.sort_order::int,r.requirement='obligatorio',
         coalesce(ck.present,false),
         (select count(*)::int from public.documents d where d.service_line_id=l.id and d.document_type_code=r.document_type_code),
         coalesce(ck.present,false) or exists(select 1 from public.documents d where d.service_line_id=l.id and d.document_type_code=r.document_type_code),
         r.rule_id
    from public.service_lines l
    left join public.submissions s on s.id=l.submission_id
    cross join lateral app.required_docs(l.procedure_id,coalesce(l.ars_id,s.ars_id),l.care_mode) r
    join public.document_types dt on dt.code=r.document_type_code
    left join public.line_document_checks ck on ck.service_line_id=l.id and ck.document_type_code=r.document_type_code
   where l.id=p_line and r.requirement<>'no_requerido';
end $$;

create or replace function public.check_duplicate_line(
  p_org uuid,p_ars uuid,p_member text,p_date date,p_procedure uuid,p_authorization text default null
)
returns table(folio text,service_line_id uuid,patient_name text,service_date date,status text,match_type text)
language sql stable set search_path=''
as $$
  select coalesce(s.folio,l.claim_folio),l.id,l.patient_name,l.service_date,
         coalesce(s.status,'sin_lote'),
         case when l.member_number=p_member and l.service_date=p_date and l.procedure_id=p_procedure
              then 'afiliado+fecha+concepto' else 'autorización' end
    from public.service_lines l
    left join public.submissions s on s.id=l.submission_id
   where l.organization_id=p_org
     and coalesce(l.ars_id,s.ars_id)=p_ars
     and (s.id is null or s.status not in ('rechazada','cerrada'))
     and ((l.member_number=p_member and l.service_date=p_date and l.procedure_id=p_procedure)
       or (p_authorization is not null and l.authorization_number=p_authorization))
$$;

create or replace function public.claim_checks(p_line uuid)
returns jsonb
language plpgsql stable set search_path=''
as $$
declare l public.service_lines; s public.submissions; v_missing text[]; v_dup boolean; v_code boolean; v_exc boolean; v_ars uuid;
begin
  select * into l from public.service_lines where id=p_line;
  if not found then raise exception 'Reclamación no encontrada o sin acceso' using errcode='P0002'; end if;
  if l.submission_id is not null then select * into s from public.submissions where id=l.submission_id; end if;
  v_ars := coalesce(l.ars_id,s.ars_id);
  v_missing := app.claim_missing_docs(l.id);
  v_exc := exists(select 1 from public.claim_dossier_exceptions e where e.service_line_id=l.id and e.revoked_at is null);
  select exists(
    select 1 from public.service_lines l2
    left join public.submissions s2 on s2.id=l2.submission_id
    where l2.id<>l.id and l2.organization_id=l.organization_id
      and coalesce(l2.ars_id,s2.ars_id)=v_ars
      and (s2.id is null or s2.status not in ('rechazada','cerrada'))
      and ((l2.member_number=l.member_number and l2.service_date=l.service_date and l2.procedure_id=l.procedure_id)
        or (l.authorization_number is not null and l2.authorization_number=l.authorization_number))
  ) into v_dup;
  v_code := exists(select 1 from public.procedure_codes pc where pc.procedure_id=l.procedure_id and (pc.code_system in ('CUPS','UNIVERSAL','SIMON') or pc.ars_id=v_ars));
  return jsonb_build_object(
    'contracted',l.contracted or l.contract_override_reason is not null,
    'tariff',app.claim_tariff_ok(l.id),
    'ident',l.member_number is not null and length(trim(l.member_number))>0 and length(trim(l.patient_name))>=3,
    'auth',l.authorization_number is not null and length(trim(l.authorization_number))>0,
    'code',v_code,'docs',(coalesce(array_length(v_missing,1),0)=0 or v_exc),
    'missing_documents',to_jsonb(v_missing),'docs_exception',v_exc,'duplicate',v_dup,
    'date',l.service_date<=current_date,
    'ok',(l.contracted or l.contract_override_reason is not null) and app.claim_tariff_ok(l.id)
      and l.member_number is not null and length(trim(l.member_number))>0
      and l.authorization_number is not null and v_code
      and (coalesce(array_length(v_missing,1),0)=0 or v_exc)
      and not v_dup and l.service_date<=current_date
  );
end $$;

commit;
