-- 240 · Canal de cobro "vía clínica"
-- Ya aplicado en producción (en partes: DDL, vista, funciones).
--
-- Agrega billing_channel a service_lines para distinguir:
--   'directo'     → flujo normal SoFa→ARS (default)
--   'via_clinica'  → la clínica cobra a la ARS por el médico; SoFa solo registra
--
-- Las líneas via_clinica no entran al flujo de radicación de SoFa.
-- Se les asigna el status 'pendiente_cobro_clinica' en lugar de seguir capturada→validada→radicada.

begin;

-- ─── Idempotencia ───────────────────────────────────────────────────────────
do $guard$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_lines' and column_name = 'billing_channel'
  ) then
    raise notice '240: billing_channel ya existe, saltando migración';
    return;
  end if;

  -- 1. Nuevo campo
  alter table public.service_lines
    add column billing_channel text not null default 'directo'
    constraint service_lines_billing_channel_check
    check (billing_channel in ('directo', 'via_clinica'));

  comment on column public.service_lines.billing_channel is
    'Canal de cobro: directo = SoFa radica ante la ARS; via_clinica = la clínica cobra y paga al médico';

  -- 2. Nuevo status
  insert into public.claim_statuses (code, name, stage, sort_order)
  values ('pendiente_cobro_clinica', 'Pendiente cobro clínica', 'cobro', 75)
  on conflict (code) do nothing;

  -- 3. Índice parcial para consultas de líneas vía clínica pendientes
  create index if not exists idx_service_lines_via_clinica
    on public.service_lines (organization_id, billing_channel)
    where billing_channel = 'via_clinica';

end $guard$;

-- 4. Recrear v_claims con billing_channel expuesto y next_step para el nuevo status
create or replace view public.v_claims with (security_invoker = true) as
SELECT l.id,
    l.claim_folio AS folio,
    l.organization_id,
    o.legal_name AS client_name,
    s.provider_id,
    pr.full_name AS provider_name,
    s.ars_id,
    a.name AS ars_name,
    l.submission_id,
    s.folio AS submission_folio,
    s.status AS submission_status,
    s.period,
    l.service_date,
    l.patient_name,
    l.patient_doc,
    l.member_number,
    l.authorization_number,
    l.care_mode,
    l.clinic_name,
    l.procedure_id,
    COALESCE(l.service_name_snapshot, p.description) AS service_name,
    p.internal_code,
    l.simon_code_snapshot AS simon,
    l.cups_code_snapshot AS cups,
    l.quantity,
    l.unit_amount,
    l.tariff_amount,
    l.amount AS claimed,
    l.contracted,
    l.amount_ok,
    l.contract_ref_snapshot AS contract_ref,
    l.tariff_valid_from,
    l.tariff_valid_to,
    l.contract_override_reason,
    l.claim_status,
    cs.name AS status_name,
    cs.stage,
    l.status_changed_at,
    l.location_code,
    loc.name AS location_name,
    l.custodian_id,
    COALESCE(l.custodian_label, cp.full_name) AS custodian_name,
    ( SELECT d.status
           FROM tariff_discrepancies d
          WHERE d.service_line_id = l.id
          ORDER BY d.created_at DESC
         LIMIT 1) AS discrepancy_status,
    app.claim_paid_visible(l.id) AS paid,
    COALESCE(( SELECT sum(gi.amount) AS sum
           FROM glosa_items gi
          WHERE gi.service_line_id = l.id), 0::numeric) AS glosado,
    COALESCE(( SELECT sum(gi.accepted_amount) AS sum
           FROM glosa_items gi
          WHERE gi.service_line_id = l.id), 0::numeric) AS glosa_accepted,
    COALESCE(( SELECT sum(gi.recovered_amount) AS sum
           FROM glosa_items gi
          WHERE gi.service_line_id = l.id), 0::numeric) AS recovered,
    l.amount - COALESCE(( SELECT sum(gi.accepted_amount) AS sum
           FROM glosa_items gi
          WHERE gi.service_line_id = l.id), 0::numeric) AS recognized,
    l.amount - app.claim_paid_visible(l.id) - COALESCE(( SELECT sum(gi.accepted_amount) AS sum
           FROM glosa_items gi
          WHERE gi.service_line_id = l.id), 0::numeric) AS balance,
    ( SELECT gr.name
           FROM glosa_items gi
             JOIN glosa_reasons gr ON gr.code = gi.reason_code
          WHERE gi.service_line_id = l.id
          ORDER BY gi.created_at DESC
         LIMIT 1) AS glosa_reason,
    ( SELECT max(py.paid_on) AS max
           FROM payment_line_allocations pla
             JOIN payments py ON py.id = pla.payment_id
          WHERE pla.service_line_id = l.id AND pla.superseded_at IS NULL AND pla.amount > 0::numeric) AS last_paid_on,
    ( SELECT string_agg(DISTINCT py.reference, ', '::text) AS string_agg
           FROM payment_line_allocations pla
             JOIN payments py ON py.id = pla.payment_id
          WHERE pla.service_line_id = l.id AND pla.superseded_at IS NULL AND pla.amount > 0::numeric) AS payment_refs,
    ( SELECT h.comment
           FROM claim_status_history h
          WHERE h.service_line_id = l.id
          ORDER BY h.changed_at DESC, h.id DESC
         LIMIT 1) AS last_action,
    ( SELECT h.changed_at
           FROM claim_status_history h
          WHERE h.service_line_id = l.id
          ORDER BY h.changed_at DESC, h.id DESC
         LIMIT 1) AS last_action_at,
        CASE l.claim_status
            WHEN 'pendiente_configuracion' THEN 'Configurar el tarifario contractual del médico o autorizar la excepción'
            WHEN 'capturada' THEN 'Completar documentos y programar el retiro'
            WHEN 'pendiente_retiro' THEN 'Retirar en el consultorio'
            WHEN 'retirada' THEN 'Entregar a auditoría para validar'
            WHEN 'en_validacion' THEN 'Auditar el expediente'
            WHEN 'con_inconsistencia' THEN 'Corregir lo señalado por auditoría'
            WHEN 'validada' THEN 'Incluir en el lote y pasar a Lista para radicar'
            WHEN 'lista_para_radicar' THEN 'Registrar la factura fiscal y radicar ante la ARS'
            WHEN 'radicada' THEN 'Dar seguimiento a la ARS'
            WHEN 'en_proceso_ars' THEN 'Esperar pago o glosa; registrar la respuesta'
            WHEN 'devuelta' THEN 'Corregir y volver a validar'
            WHEN 'pago_parcial' THEN 'Conciliar la diferencia o gestionar la glosa'
            WHEN 'glosada' THEN 'Responder la glosa dentro del plazo'
            WHEN 'pagada' THEN 'Conciliar y cerrar'
            WHEN 'pendiente_cobro_clinica' THEN 'Dar seguimiento al cobro de la clínica y registrar el pago cuando se reciba'
            ELSE '—'
        END AS next_step,
    l.created_at,
    l.created_by,
    cb.full_name AS created_by_name,
    l.updated_at,
    l.updated_by,
    app.claim_dossier_ok(l.id) AS dossier_ok,
    cardinality(app.claim_missing_docs(l.id)) AS dossier_missing,
    l.authorization_date,
    app.claim_progress(l.claim_status, app.claim_paid_visible(l.id), l.amount) AS avance,
    l.billing_channel
   FROM service_lines l
     JOIN submissions s ON s.id = l.submission_id
     LEFT JOIN organizations o ON o.id = l.organization_id
     LEFT JOIN providers pr ON pr.id = s.provider_id
     LEFT JOIN ars a ON a.id = s.ars_id
     LEFT JOIN procedures p ON p.id = l.procedure_id
     LEFT JOIN claim_statuses cs ON cs.code = l.claim_status
     LEFT JOIN claim_locations loc ON loc.code = l.location_code
     LEFT JOIN profiles cp ON cp.id = l.custodian_id
     LEFT JOIN profiles cb ON cb.id = l.created_by;

-- 5. Función para marcar una línea como cobro vía clínica
create or replace function public.set_billing_channel_via_clinica(p_line_id uuid)
returns void
language plpgsql
security invoker
as $$
begin
  update public.service_lines
  set billing_channel = 'via_clinica',
      claim_status = 'pendiente_cobro_clinica',
      status_changed_at = now(),
      updated_at = now(),
      updated_by = auth.uid()
  where id = p_line_id
    and billing_channel = 'directo';

  if not found then
    raise exception 'La reclamación no existe o ya está marcada como cobro vía clínica.';
  end if;

  insert into public.claim_status_history (service_line_id, new_status, changed_by, comment)
  values (p_line_id, 'pendiente_cobro_clinica', auth.uid(), 'Marcada como cobro vía clínica — no se radicará por SoFa');
end;
$$;

-- 6. Función para revertir a cobro directo (solo admin)
create or replace function public.revert_billing_channel_to_directo(p_line_id uuid)
returns void
language plpgsql
security invoker
as $$
begin
  update public.service_lines
  set billing_channel = 'directo',
      claim_status = 'capturada',
      status_changed_at = now(),
      updated_at = now(),
      updated_by = auth.uid()
  where id = p_line_id
    and billing_channel = 'via_clinica';

  if not found then
    raise exception 'La reclamación no existe o ya es cobro directo.';
  end if;

  insert into public.claim_status_history (service_line_id, new_status, changed_by, comment)
  values (p_line_id, 'capturada', auth.uid(), 'Revertida a cobro directo — entra al flujo normal de radicación');
end;
$$;

-- 7. Grants
grant execute on function public.set_billing_channel_via_clinica(uuid) to authenticated;
grant execute on function public.revert_billing_channel_to_directo(uuid) to authenticated;

commit;
