-- Ya aplicado en producción (24/11/2026). Se guarda aquí como documentación.
-- 266 · Corrección de tarifa con recálculo de las reclamaciones no radicadas (acceso rápido del Super Admin y el Administrador).
-- Requiere la 184 (versiones de tarifario). Idempotente. Revierte con 266_revertir.sql.
--
-- Por qué existe
--   «Cambiar precio» (app.change_tariff_price_core) cierra la tarifa y abre otra con vigencia futura: sirve para un
--   aumento. NO sirve para corregir un error de carga (750 en vez de 850), porque el guardián app.guard_tariff prohíbe
--   cambiar el monto de una tarifa existente y las reclamaciones tienen su tarifa congelada (fotografía).
--
-- Qué hace
--   1. app.guard_tariff acepta el cambio de MONTO solo cuando la función de corrección lo autoriza
--      (app.tariff_correction = 'on', activado y desactivado dentro de la propia función). Cliente, ARS, plan,
--      médico, servicio y fecha de inicio nunca cambian.
--   2. public.tariff_correction_preview(tarifa, monto): efecto sin tocar nada (cuántas reclamaciones, de qué tipo).
--   3. public.tariff_correct(tarifa, monto, motivo, esperado): aplica. Solo super_admin y admin de SOFA.
--
-- Alcance (decisión del dueño, 24/11/2026): solo reclamaciones NO radicadas
--   (pendiente_configuracion, capturada, pendiente_retiro, retirada, en_validacion, con_inconsistencia, validada,
--   lista_para_radicar). Radicada, en proceso, devuelta, glosada, pagada, parcial, cerrada y cobro por la clínica
--   NO se tocan: conservan su fotografía y siguen apareciendo en public.tariff_stale_claims («precio vencido»).
--
-- Qué pasa con cada reclamación del alcance
--   · realinear  → el monto registrado era igual a la tarifa vieja y el estado admite edición: pasa al monto nuevo.
--   · resuelta   → el monto registrado ya era igual a la tarifa nueva: la diferencia pendiente queda superada.
--   · decisión   → el monto registrado se conserva (otro monto, o estado validada / lista para radicar, que no
--                  admiten cambios de contenido): la fotografía pasa a la tarifa nueva y, si difiere, se abre una
--                  diferencia tarifaria PENDIENTE para que Facturación decida. Nada se acepta en silencio.
--   Cada línea tocada deja una nota en su historial. Una línea que falle (periodo archivado, p. ej.) se omite y se
--   informa; no frena a las demás.

do $$ begin
  if not exists (select 1 from app.schema_migrations where version = '184') then
    raise exception 'Falta la migración 184 (versiones de tarifario). Aplica las migraciones en orden hasta la 184 y vuelve a correr esta.';
  end if;
  if to_regprocedure('app.is_staff(text[])') is null or to_regprocedure('app.visible_org_ids()') is null
     or to_regprocedure('app.is_active_user()') is null or to_regprocedure('public.support_view_active()') is null then
    raise exception '266 requiere las funciones de acceso de SOFA (is_staff, visible_org_ids, is_active_user, support_view_active).';
  end if;
end $$;

-- ── Bitácora de correcciones ───────────────────────────────────────────────────────────────────────
create table if not exists app.tariff_corrections (
  id uuid primary key default gen_random_uuid(),
  tariff_id uuid not null references public.tariffs(id) on delete restrict,
  old_amount numeric not null,
  new_amount numeric not null,
  reason text not null check (length(btrim(reason)) between 10 and 1000),
  corrected_by uuid default auth.uid(),
  corrected_at timestamptz not null default now(),
  lines_total int not null default 0,
  lines_realigned int not null default 0,
  lines_resolved int not null default 0,
  lines_decision int not null default 0,
  lines_untouched int not null default 0,
  lines_skipped int not null default 0,
  detail jsonb not null default '{}'::jsonb
);
create index if not exists tariff_corrections_tariff_idx on app.tariff_corrections (tariff_id, corrected_at desc);
alter table app.tariff_corrections enable row level security;
revoke all on app.tariff_corrections from public, anon, authenticated;

-- ── Guardián: el monto solo cambia dentro de la función de corrección ─────────────────────────────
-- (definición vigente de producción, copiada completa; se separa el monto del resto de los campos)
create or replace function app.guard_tariff()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if (new.ars_id, new.plan_id, new.organization_id, new.provider_id, new.procedure_id, lower(new.valid_during))
     is distinct from (old.ars_id, old.plan_id, old.organization_id, old.provider_id, old.procedure_id, lower(old.valid_during))
     or (new.amount is distinct from old.amount and coalesce(current_setting('app.tariff_correction', true), '') <> 'on') then
    raise exception 'Una tarifa no se modifica: cree una nueva con public.create_tariff() (la anterior se cierra). Para corregir un error de monto, el Super Admin o el Administrador usan «Corregir tarifa» desde la reclamación.' using errcode = '42501';
  end if;
  -- I57: publicar una versión (public.tariff_version_publish, que activa app.tariff_version_publish solo durante la publicación) con fecha anterior a servicios ya
  -- capturados está permitido; esas reclamaciones quedan en la alerta «precio vencido» (public.tariff_stale_claims) para que facturación decida.
  if upper(new.valid_during) is not null
     and coalesce(current_setting('app.tariff_version_publish', true), '') <> 'on'
     and exists (select 1 from public.service_lines l where l.tariff_id = new.id and l.service_date >= upper(new.valid_during)) then
    raise exception 'No se puede cerrar la tarifa antes de servicios que ya la usan' using errcode = '23514';
  end if;
  return new;
end $function$;

-- ── Permiso ───────────────────────────────────────────────────────────────────────────────────────
create or replace function app.tariff_correction_check(p_tariff uuid)
returns public.tariffs
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare t public.tariffs;
begin
  if auth.uid() is null or not app.is_active_user() then
    raise exception 'Inicie sesión para corregir una tarifa.' using errcode = '42501';
  end if;
  if exists (select 1 from public.support_view_active()) then
    raise exception 'Salga del modo soporte para corregir una tarifa.' using errcode = '42501';
  end if;
  if not app.is_staff(array['super_admin','admin']) then
    raise exception 'Solo el Super Admin o el Administrador de SOFA corrigen tarifas. Pida a una de esas personas que lo haga.' using errcode = '42501';
  end if;
  select * into t from public.tariffs where id = p_tariff;
  if t.id is null then
    raise exception 'La tarifa no existe. Actualice la pantalla y vuelva a intentar.' using errcode = 'P0002';
  end if;
  if t.organization_id is not null and not (t.organization_id in (select app.visible_org_ids())) then
    raise exception 'Sin acceso al cliente de esta tarifa.' using errcode = '42501';
  end if;
  return t;
end $function$;

-- ── Clasificación de las reclamaciones que usan la tarifa ─────────────────────────────────────────
create or replace function app.tariff_correction_lines(p_tariff uuid, p_amount numeric)
returns table(line_id uuid, organization_id uuid, claim_folio text, claim_status text, service_date date,
              unit_amount numeric, frozen_amount numeric, outcome text)
language sql
stable
security definer
set search_path to ''
as $function$
  select l.id, l.organization_id, l.claim_folio, l.claim_status, l.service_date, l.unit_amount, l.tariff_amount,
         case
           when not (l.claim_status = any (array['pendiente_configuracion','capturada','pendiente_retiro','retirada',
                                                 'en_validacion','con_inconsistencia','validada','lista_para_radicar'])) then 'sin_tocar'
           when l.unit_amount = p_amount then 'resuelta'
           when l.unit_amount = l.tariff_amount and l.claim_status = any (app.claim_staff_edit_states()) then 'realinear'
           else 'decision'
         end
    from public.service_lines l
   where l.tariff_id = p_tariff;
$function$;

-- ── Vista previa ──────────────────────────────────────────────────────────────────────────────────
create or replace function app.tariff_correction_preview_core(p_tariff uuid, p_amount numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare t public.tariffs; v_valid boolean; v_msg text; v_out jsonb;
begin
  t := app.tariff_correction_check(p_tariff);
  v_valid := p_amount is not null and p_amount > 0 and p_amount = round(p_amount, 2) and p_amount <> t.amount;
  v_msg := case when p_amount is null then null
                when p_amount <= 0 or p_amount <> round(p_amount, 2) then 'Indique un monto mayor que cero, con un máximo de dos decimales.'
                when p_amount = t.amount then 'Es el monto vigente. Escriba un importe diferente.' end;
  select jsonb_build_object(
    'tariff', jsonb_build_object('id', t.id, 'amount', t.amount, 'currency', t.currency, 'valid_from', lower(t.valid_during),
       'valid_to', case when upper(t.valid_during) is null then null else upper(t.valid_during) - 1 end, 'contract_ref', t.contract_ref,
       'scope', case when t.provider_id is null then 'general' else 'contrato' end,
       'service', (select p.description from public.procedures p where p.id = t.procedure_id),
       'ars', (select a.name from public.ars a where a.id = t.ars_id),
       'provider', (select pr.full_name from public.providers pr where pr.id = t.provider_id)),
    'new_amount', p_amount, 'valid', v_valid, 'message', v_msg,
    'counts', case when not v_valid then null else (
      select jsonb_build_object('total', count(*), 'realinear', count(*) filter (where outcome = 'realinear'),
             'resuelta', count(*) filter (where outcome = 'resuelta'), 'decision', count(*) filter (where outcome = 'decision'),
             'sin_tocar', count(*) filter (where outcome = 'sin_tocar'), 'clients', count(distinct organization_id),
             'sin_tocar_por_estado', coalesce((select jsonb_object_agg(s.claim_status, s.n) from (
                 select x.claim_status, count(*) n from app.tariff_correction_lines(p_tariff, p_amount) x where x.outcome = 'sin_tocar' group by 1) s), '{}'::jsonb))
        from app.tariff_correction_lines(p_tariff, p_amount)) end,
    'sample', case when not v_valid then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('folio', z.claim_folio, 'status', z.claim_status, 'unit_amount', z.unit_amount,
                                          'frozen_amount', z.frozen_amount, 'outcome', z.outcome) order by z.service_date desc, z.claim_folio)
        from (select * from app.tariff_correction_lines(p_tariff, p_amount) x where x.outcome <> 'sin_tocar'
               order by x.service_date desc, x.claim_folio limit 8) z), '[]'::jsonb) end,
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', h.corrected_at, 'old_amount', h.old_amount, 'new_amount', h.new_amount,
                                                              'reason', h.reason, 'lines', h.lines_total, 'by', (select pf.full_name from public.profiles pf where pf.id = h.corrected_by))
                                          order by h.corrected_at desc)
                          from (select * from app.tariff_corrections c where c.tariff_id = p_tariff order by c.corrected_at desc limit 5) h), '[]'::jsonb)
  ) into v_out;
  return v_out;
end $function$;

-- ── Aplicar ───────────────────────────────────────────────────────────────────────────────────────
-- p_expected = {"old_amount": …, "total": …} tal como lo mostró la vista previa; si el alcance cambió, no aplica.
create or replace function app.tariff_correct_core(p_tariff uuid, p_amount numeric, p_reason text, p_expected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  t public.tariffs; v_old numeric; v_reason text := btrim(coalesce(p_reason, '')); r record; v_total int := 0; v_untouched int := 0;
  v_real int := 0; v_res int := 0; v_dec int := 0; v_skip int := 0; v_skipped jsonb := '[]'::jsonb; v_id uuid := gen_random_uuid();
  v_today text := to_char((now() at time zone 'America/Santo_Domingo')::date, 'DD/MM/YYYY'); v_exp_total int;
begin
  t := app.tariff_correction_check(p_tariff);
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'Indique un monto mayor que cero, con un máximo de dos decimales.' using errcode = '22023';
  end if;
  if length(v_reason) not between 10 and 1000 then
    raise exception 'Indique el motivo de la corrección (entre 10 y 1000 caracteres).' using errcode = '22023';
  end if;
  select * into t from public.tariffs where id = p_tariff for update;
  v_old := t.amount;
  if p_amount = v_old then
    raise exception 'El monto es igual al vigente (%). Escriba un importe diferente.', trim_scale(v_old) using errcode = '23514';
  end if;
  select count(*) filter (where outcome <> 'sin_tocar'), count(*) filter (where outcome = 'sin_tocar'), count(*)
    into v_exp_total, v_untouched, v_total from app.tariff_correction_lines(p_tariff, p_amount);
  if p_expected is not null then
    if (p_expected->>'old_amount')::numeric is distinct from v_old then
      raise exception 'La tarifa cambió desde la vista previa (ahora % en lugar de %). Vuelva a ver el efecto y confirme de nuevo.', v_old, p_expected->>'old_amount' using errcode = '40001';
    end if;
    if (p_expected->>'total')::int is distinct from v_total then
      raise exception 'El alcance cambió desde la vista previa (antes % reclamaciones, ahora %). Vuelva a ver el efecto y confirme de nuevo.', p_expected->>'total', v_total using errcode = '40001';
    end if;
  end if;

  -- 1) El monto de la tarifa (el guardián lo permite solo con esta bandera)
  perform set_config('app.tariff_correction', 'on', true);
  update public.tariffs
     set amount = p_amount,
         notes = left(coalesce(nullif(notes, '') || E'\n', '') || format('Corrección %s: %s → %s. %s', v_today, trim_scale(v_old), trim_scale(p_amount), v_reason), 4000)
   where id = p_tariff;
  perform set_config('app.tariff_correction', '', true);

  -- 2) Las reclamaciones no radicadas, una por una (una que falle no frena a las demás)
  for r in select * from app.tariff_correction_lines(p_tariff, p_amount) x where x.outcome <> 'sin_tocar' order by x.claim_folio loop
    begin
      if r.outcome = 'realinear' then
        perform set_config('app.claim_recheck', 'on', true);
        update public.service_lines set unit_amount = p_amount where id = r.line_id;
        perform set_config('app.claim_recheck', '', true);
        v_real := v_real + 1;
      else
        perform set_config('app.claim_reprice', 'on', true);
        perform set_config('app.discrepancy_reason', 'Corrección de tarifa: ' || left(v_reason, 200), true);
        update public.service_lines set tariff_amount = p_amount, amount_ok = (contracted and unit_amount = p_amount) where id = r.line_id;
        perform set_config('app.claim_reprice', '', true);
        perform set_config('app.discrepancy_reason', '', true);
        if r.outcome = 'resuelta' then v_res := v_res + 1; else v_dec := v_dec + 1; end if;
      end if;
      insert into public.claim_status_history (service_line_id, organization_id, from_status, to_status, from_location, to_location, custodian_label, comment)
      select l.id, l.organization_id, l.claim_status, l.claim_status, l.location_code, l.location_code, l.custodian_label,
             format('Tarifa corregida de %s a %s (%s). %s', trim_scale(v_old), trim_scale(p_amount),
                    case r.outcome when 'realinear' then 'monto registrado ajustado a la tarifa'
                                   when 'resuelta' then 'el monto registrado ya coincidía; diferencia superada'
                                   else 'se conserva el monto registrado; Facturación decide la diferencia' end, left(v_reason, 300))
        from public.service_lines l where l.id = r.line_id;
    exception when others then
      perform set_config('app.claim_recheck', '', true); perform set_config('app.claim_reprice', '', true); perform set_config('app.discrepancy_reason', '', true);
      v_skip := v_skip + 1;
      if v_skip <= 50 then v_skipped := v_skipped || jsonb_build_object('folio', r.claim_folio, 'motivo', left(sqlerrm, 200)); end if;
    end;
  end loop;

  insert into app.tariff_corrections (id, tariff_id, old_amount, new_amount, reason, lines_total, lines_realigned, lines_resolved, lines_decision, lines_untouched, lines_skipped, detail)
  values (v_id, p_tariff, v_old, p_amount, v_reason, v_total, v_real, v_res, v_dec, v_untouched, v_skip, jsonb_build_object('omitidas', v_skipped));

  return jsonb_build_object('correction_id', v_id, 'old_amount', v_old, 'new_amount', p_amount, 'total', v_total, 'realinear', v_real,
                            'resuelta', v_res, 'decision', v_dec, 'sin_tocar', v_untouched, 'omitidas', v_skip, 'omitidas_detalle', v_skipped);
end $function$;

-- ── API pública (solo authenticated; el permiso real se valida dentro) ────────────────────────────
create or replace function public.tariff_correction_preview(p_tariff uuid, p_amount numeric default null)
returns jsonb language plpgsql security definer set search_path to ''
as $function$ begin return app.tariff_correction_preview_core(p_tariff, p_amount); end $function$;

create or replace function public.tariff_correct(p_tariff uuid, p_amount numeric, p_reason text, p_expected jsonb default null)
returns jsonb language plpgsql security definer set search_path to ''
as $function$ begin return app.tariff_correct_core(p_tariff, p_amount, p_reason, p_expected); end $function$;

revoke all on function app.tariff_correction_check(uuid), app.tariff_correction_lines(uuid, numeric),
  app.tariff_correction_preview_core(uuid, numeric), app.tariff_correct_core(uuid, numeric, text, jsonb) from public, anon, authenticated;
revoke all on function public.tariff_correction_preview(uuid, numeric), public.tariff_correct(uuid, numeric, text, jsonb) from public, anon;
grant execute on function public.tariff_correction_preview(uuid, numeric), public.tariff_correct(uuid, numeric, text, jsonb) to authenticated;

-- ── Registro ──────────────────────────────────────────────────────────────────────────────────────
delete from app.schema_migrations where version = '266';
insert into app.schema_migrations (version, report) values ('266', jsonb_build_object('iteracion', 'I90', 'version', '5.43.0',
  'tema', 'corregir una tarifa (solo Super Admin y Administrador) y recalcular las reclamaciones no radicadas, con vista previa, motivo y bitácora'));
