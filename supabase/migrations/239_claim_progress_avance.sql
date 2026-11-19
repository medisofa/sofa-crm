-- ============================================================
-- 239 · Nivel de avance de la reclamación (0–100, 100 = pagada)
-- Agrega app.claim_progress() y expone la columna `avance` en la
-- vista public.v_claims, para que la lista de reclamaciones y los
-- reportes de hospitalización muestren qué tan cerca está cada
-- reclamación del cobro. El avance combina la etapa del flujo con
-- el cobro proporcional (pagado / reclamado) en las etapas de
-- dinero (pago_parcial, glosada, cerrada).
-- Ya aplicado en producción (2026-11-19). Suite 239: 13/13 APROBADA.
-- ============================================================
begin;

set local search_path = public, app;

-- 0. Verificación de dependencias (falla temprano si falta el piso)
do $$
begin
  if to_regprocedure('app.claim_paid_visible(uuid)') is null then
    raise exception '239: falta app.claim_paid_visible(uuid) — aplica primero la migración que la crea';
  end if;
  if to_regclass('public.service_lines') is null
     or to_regclass('public.claim_statuses') is null then
    raise exception '239: faltan tablas base (service_lines / claim_statuses)';
  end if;
  if to_regclass('public.v_claims') is null then
    raise exception '239: falta la vista public.v_claims';
  end if;
end $$;

-- 1. Función de avance: etapa del flujo + cobro proporcional.
--    IMMUTABLE y sin acceso a tablas: se puede usar dentro de la vista
--    sin costo adicional de consulta. `ratio` = pagado/reclamado acotado a [0,1].
create or replace function app.claim_progress(
  p_status text,
  p_paid   numeric default 0,
  p_billed numeric default 0
) returns integer
language sql
immutable
as $function$
  with r as (
    select case when coalesce(p_billed,0) > 0
                then least(1, greatest(0, coalesce(p_paid,0) / p_billed))
                else 0 end as ratio)
  select case p_status
    when 'pendiente_configuracion' then 5
    when 'capturada'               then 12
    when 'pendiente_retiro'        then 18
    when 'retirada'                then 25
    when 'en_validacion'           then 35
    when 'con_inconsistencia'      then 30
    when 'validada'                then 45
    when 'lista_para_radicar'      then 55
    when 'radicada'                then 68
    when 'en_proceso_ars'          then 78
    when 'devuelta'                then 60
    when 'pago_parcial'            then (80 + round(20 * (select ratio from r)))::int
    when 'glosada'                 then (72 + round(18 * (select ratio from r)))::int
    when 'pagada'                  then 100
    when 'cerrada'                 then case when coalesce(p_billed,0) > 0
                                             then (85 + round(15 * (select ratio from r)))::int
                                             else 100 end
    else 0
  end;
$function$;

grant execute on function app.claim_progress(text,numeric,numeric) to authenticated, service_role;

-- 2. Reexpone v_claims idéntica a producción + columna `avance` al final.
--    SECURITY INVOKER obligatorio (guard scripts/check-view-security-invoker.js):
--    la vista debe respetar las RLS del usuario que la consulta.
create or replace view public.v_claims with (security_invoker=true) as
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
            WHEN 'pendiente_configuracion'::text THEN 'Configurar el tarifario contractual del médico o autorizar la excepción'::text
            WHEN 'capturada'::text THEN 'Completar documentos y programar el retiro'::text
            WHEN 'pendiente_retiro'::text THEN 'Retirar en el consultorio'::text
            WHEN 'retirada'::text THEN 'Entregar a auditoría para validar'::text
            WHEN 'en_validacion'::text THEN 'Auditar el expediente'::text
            WHEN 'con_inconsistencia'::text THEN 'Corregir lo señalado por auditoría'::text
            WHEN 'validada'::text THEN 'Incluir en el lote y pasar a Lista para radicar'::text
            WHEN 'lista_para_radicar'::text THEN 'Registrar la factura fiscal y radicar ante la ARS'::text
            WHEN 'radicada'::text THEN 'Dar seguimiento a la ARS'::text
            WHEN 'en_proceso_ars'::text THEN 'Esperar pago o glosa; registrar la respuesta'::text
            WHEN 'devuelta'::text THEN 'Corregir y volver a validar'::text
            WHEN 'pago_parcial'::text THEN 'Conciliar la diferencia o gestionar la glosa'::text
            WHEN 'glosada'::text THEN 'Responder la glosa dentro del plazo'::text
            WHEN 'pagada'::text THEN 'Conciliar y cerrar'::text
            ELSE '—'::text
        END AS next_step,
    l.created_at,
    l.created_by,
    cb.full_name AS created_by_name,
    l.updated_at,
    l.updated_by,
    app.claim_dossier_ok(l.id) AS dossier_ok,
    cardinality(app.claim_missing_docs(l.id)) AS dossier_missing,
    l.authorization_date,
    app.claim_progress(l.claim_status, app.claim_paid_visible(l.id), l.amount) AS avance
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

-- 3. Suite 239 (solo lectura): valida el mapa de etapas, el cobro
--    proporcional y que la vista nunca entregue un avance fuera de 0..100
--    ni una reclamación pagada con avance <> 100.
create or replace function app.qa_run_tests_claim_progress()
returns table(prueba text, resultado text, detalle text)
language plpgsql
set search_path to ''
as $function$
declare
  r_id text[] := '{}'; r_ok boolean[] := '{}'; r_det text[] := '{}';
  i int; v_fail int := 0; v_n int; v_bad int; v_pag int; v_pagbad int;
begin
  r_id := r_id||'CP-01 captura = 12'::text; r_ok := r_ok||(app.claim_progress('capturada',0,1000)=12); r_det := r_det||''::text;
  r_id := r_id||'CP-02 radicada = 68'::text; r_ok := r_ok||(app.claim_progress('radicada',0,1000)=68); r_det := r_det||''::text;
  r_id := r_id||'CP-03 devuelta retrocede a 60'::text; r_ok := r_ok||(app.claim_progress('devuelta',0,1000)=60); r_det := r_det||''::text;
  r_id := r_id||'CP-04 pago_parcial 0 pagado = 80'::text; r_ok := r_ok||(app.claim_progress('pago_parcial',0,1000)=80); r_det := r_det||''::text;
  r_id := r_id||'CP-05 pago_parcial mitad = 90'::text; r_ok := r_ok||(app.claim_progress('pago_parcial',500,1000)=90); r_det := r_det||('->'||app.claim_progress('pago_parcial',500,1000));
  r_id := r_id||'CP-06 pago_parcial todo = 100'::text; r_ok := r_ok||(app.claim_progress('pago_parcial',1000,1000)=100); r_det := r_det||''::text;
  r_id := r_id||'CP-07 pagada = 100'::text; r_ok := r_ok||(app.claim_progress('pagada',1000,1000)=100); r_det := r_det||''::text;
  r_id := r_id||'CP-08 glosada a medias sube con lo pagado'::text; r_ok := r_ok||(app.claim_progress('glosada',500,1000)=81); r_det := r_det||('->'||app.claim_progress('glosada',500,1000));
  r_id := r_id||'CP-09 cerrada sin pago no llega a 100'::text; r_ok := r_ok||(app.claim_progress('cerrada',0,1000)=85); r_det := r_det||('->'||app.claim_progress('cerrada',0,1000));
  r_id := r_id||'CP-10 cerrada saldada = 100'::text; r_ok := r_ok||(app.claim_progress('cerrada',1000,1000)=100); r_det := r_det||''::text;
  r_id := r_id||'CP-11 monotonía captura<radicada<100'::text;
    r_ok := r_ok||(app.claim_progress('capturada',0,1000) < app.claim_progress('radicada',0,1000) and app.claim_progress('radicada',0,1000) < 100); r_det := r_det||''::text;

  select count(*), count(*) filter (where avance is null or avance < 0 or avance > 100),
         count(*) filter (where claim_status='pagada'), count(*) filter (where claim_status='pagada' and avance<>100)
    into v_n, v_bad, v_pag, v_pagbad
  from public.v_claims;
  r_id := r_id||'CP-12 v_claims.avance siempre 0..100'::text; r_ok := r_ok||(v_bad=0); r_det := r_det||('fuera_rango='||v_bad||' de '||v_n);
  r_id := r_id||'CP-13 toda reclamación pagada muestra 100'::text; r_ok := r_ok||(v_pagbad=0); r_det := r_det||('pagadas='||v_pag||' con_avance<>100='||v_pagbad);

  for i in 1..cardinality(r_id) loop if not r_ok[i] then v_fail := v_fail + 1; end if; end loop;
  prueba := case when v_fail=0 then 'TODO OK · '||cardinality(r_id)||' de '||cardinality(r_id)
                 else 'FALLARON '||v_fail||' de '||cardinality(r_id) end;
  resultado := case when v_fail=0 then 'APROBADA' else 'FALLIDA' end; detalle := ''; return next;
  for i in 1..cardinality(r_id) loop
    prueba := r_id[i]; resultado := case when r_ok[i] then 'APROBADA' else 'FALLIDA' end; detalle := r_det[i]; return next;
  end loop;
end
$function$;

grant execute on function app.qa_run_tests_claim_progress() to authenticated, service_role;

-- 4. Compuerta: la migración falla si la suite no pasa entera.
do $$
declare v_fail int;
begin
  select count(*) into v_fail
    from app.qa_run_tests_claim_progress()
   where prueba like 'CP-%' and resultado <> 'APROBADA';
  if v_fail > 0 then
    raise exception '239: la suite claim_progress falló en % prueba(s)', v_fail;
  end if;
end $$;

commit;
