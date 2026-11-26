-- Ya aplicado en producción (25/11/2026). Se guarda aquí como documentación.
-- 268 · Unir radicaciones de varios meses (rezagadas) en la del mes más reciente.
-- Mismo médico, ARS y plan; solo lotes sin radicar y sin factura; solo Admin / Super Admin, con motivo.
-- Las dos funciones existentes se parchan sobre su definición vigente (si un ancla no aparece, aborta).
begin;

alter table public.submissions add column if not exists period_from date;
alter table public.submissions drop constraint if exists submissions_period_from_ck;
alter table public.submissions add constraint submissions_period_from_ck
  check (period_from is null or (period_from = date_trunc('month', period_from)::date and period_from < period));

-- period_from afloja la regla de fechas: solo public.merge_submissions() puede escribirlo.
create or replace function app.guard_period_from() returns trigger language plpgsql set search_path = '' as $$
begin
  if new.period_from is distinct from (case when tg_op = 'UPDATE' then old.period_from end)
     and coalesce(current_setting('app.claim_merge', true), '') <> 'on' then
    raise exception 'El mes inicial de una radicación solo cambia al usar «Unir en una radicación»' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists submissions_period_from_guard on public.submissions;
create trigger submissions_period_from_guard before insert or update on public.submissions
  for each row execute function app.guard_period_from();

do $mig$
declare v text; v_new text;
begin
  select pg_get_functiondef('app.guard_service_line'::regproc) into v;
  if position('period_from' in v) = 0 then
    v_new := replace(v, '-- 4.5.1 (SEG-08)', $p$-- 268 · unión de radicaciones: solo cambia el lote
  if tg_op = 'UPDATE' and coalesce(current_setting('app.claim_merge', true), '') = 'on' then
    if (to_jsonb(new) - 'submission_id' - 'updated_at' - 'updated_by' - 'amount') is distinct from (to_jsonb(old) - 'submission_id' - 'updated_at' - 'updated_by' - 'amount') then
      raise exception 'Al unir radicaciones solo cambia el lote de la reclamación' using errcode = '42501';
    end if;
    return new;
  end if;
  -- 4.5.1 (SEG-08)$p$);
    if v_new = v then raise exception '268: no se encontró el ancla de unión en guard_service_line'; end if;
    v := v_new;
    v_new := replace(v, 'if new.service_date < s.period or', 'if new.service_date < coalesce(s.period_from, s.period) or');
    if v_new = v then raise exception '268: no se encontró el ancla de fecha en guard_service_line'; end if;
    execute v_new;
  end if;

  select pg_get_functiondef('public.validate_submission_pre_duplicate(uuid,boolean)'::regprocedure) into v;
  if position('period_from' in v) = 0 then
    v_new := replace(v, 'l.service_date >= s.period and', 'l.service_date >= coalesce(s.period_from, s.period) and');
    if v_new = v then raise exception '268: no se encontró el ancla de fecha en la validación'; end if;
    v := v_new;
    -- el plazo se mide desde el mes más antiguo incluido
    v_new := replace(v, '((s.period + interval ''1 month'')::date - 1 + v_window)', '((coalesce(s.period_from, s.period) + interval ''1 month'')::date - 1 + v_window)');
    if v_new = v then raise exception '268: no se encontró el ancla de plazo en la validación'; end if;
    execute v_new;
  end if;
end $mig$;

create or replace function public.merge_submissions(p_target uuid, p_sources uuid[], p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t public.submissions; s public.submissions; v_from date; v_moved int := 0; v_n int; v_folios text[] := '{}'; v_total numeric;
begin
  select * into t from public.submissions where id = p_target for update;
  if not found then raise exception 'Radicación no encontrada. Recargue la pantalla.' using errcode = 'P0002'; end if;
  if auth.uid() is null or coalesce(app.role_for_org(t.organization_id), '') not in ('super_admin','admin')
     or exists (select 1 from public.support_view_active()) then
    raise exception 'Solo Admin o Super Admin unen radicaciones' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_sources), 0) = 0 or p_target = any (p_sources) then
    raise exception 'Elija al menos dos radicaciones distintas' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 10 then raise exception 'Escriba el motivo (mínimo 10 caracteres)' using errcode = '22023'; end if;
  if not app.is_editable_status(t.status) or t.status = 'lista_para_radicar' or t.sent_on is not null then
    raise exception 'La radicación % debe estar antes de «Lista para radicar». Devuélvala a «En depuración» y repita.', t.folio using errcode = '23514';
  end if;
  if t.ncf is not null or t.fiscal_amount is not null or t.fiscal_invoice_number is not null or t.fiscal_document_id is not null then
    raise exception 'La radicación % ya tiene factura fiscal. Quítela antes de unir y registre después la del total.', t.folio using errcode = '23514';
  end if;
  v_from := coalesce(t.period_from, t.period);

  for s in select * from public.submissions where id = any (p_sources) order by id for update loop
    if (s.organization_id, s.provider_id, s.ars_id) is distinct from (t.organization_id, t.provider_id, t.ars_id)
       or s.plan_id is distinct from t.plan_id then
      raise exception 'Solo se unen radicaciones del mismo médico, ARS y plan (% no coincide)', s.folio using errcode = '23514';
    end if;
    if s.period > t.period then raise exception 'Una la radicación más antigua hacia la del mes más reciente (% es posterior)', s.folio using errcode = '23514'; end if;
    if not app.is_editable_status(s.status) or s.sent_on is not null or s.is_complementary or s.parent_submission_id is not null then
      raise exception 'La radicación % ya fue enviada o es complementaria: no se une', s.folio using errcode = '23514';
    end if;
    if s.ncf is not null or s.fiscal_amount is not null or s.fiscal_invoice_number is not null or s.fiscal_document_id is not null then
      raise exception 'La radicación % ya tiene factura fiscal: quítela antes de unir', s.folio using errcode = '23514';
    end if;
    if not exists (select 1 from public.service_lines where submission_id = s.id) then
      raise exception 'La radicación % no tiene reclamaciones (quizá ya se unió). Recargue la pantalla.', s.folio using errcode = '23514';
    end if;
    if exists (select 1 from public.payment_allocations where submission_id = s.id)
       or exists (select 1 from public.glosas where submission_id = s.id)
       or exists (select 1 from public.submissions c where c.parent_submission_id = s.id)
       or exists (select 1 from public.documents d where d.entity_type = 'submission' and d.entity_id = s.id) then
      raise exception 'La radicación % tiene pagos, glosas, complementarias o documentos propios: no se une', s.folio using errcode = '23514';
    end if;
    v_from := least(v_from, coalesce(s.period_from, s.period));
    v_folios := v_folios || s.folio;
  end loop;
  if cardinality(v_folios) <> cardinality(p_sources) then raise exception 'Falta una de las radicaciones elegidas. Recargue la pantalla.' using errcode = 'P0002'; end if;

  perform set_config('app.claim_merge', 'on', true);
  update public.submissions set period_from = case when v_from < t.period then v_from end where id = t.id;
  update public.service_lines set submission_id = t.id where submission_id = any (p_sources);
  get diagnostics v_moved = row_count;
  update public.submissions
     set notes = concat_ws(E'\n', notes, 'UNIDA a ' || t.folio || ' · ' || trim(p_reason))
   where id = any (p_sources);
  perform set_config('app.claim_merge', 'off', true);

  select count(*), coalesce(sum(amount), 0) into v_n, v_total from public.service_lines where submission_id = t.id;
  insert into public.activities (operator_id, organization_id, entity_type, entity_id, activity_type, body)
  select o.operator_id, t.organization_id, 'organization', t.organization_id, 'sistema',
         'Radicaciones ' || array_to_string(v_folios, ', ') || ' unidas a ' || t.folio || ' (' || v_moved || ' reclamación/es) · ' || trim(p_reason)
    from public.organizations o where o.id = t.organization_id;
  return jsonb_build_object('folio', t.folio, 'moved', v_moved, 'lines', v_n, 'total', v_total);
end $$;
revoke all on function public.merge_submissions(uuid, uuid[], text) from public, anon;
grant execute on function public.merge_submissions(uuid, uuid[], text) to authenticated;

commit;
