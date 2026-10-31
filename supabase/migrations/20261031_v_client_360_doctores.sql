-- Ya aplicado en producción (31/10/2026). Hallazgo real: el usuario reportó 4 "clientes" como no
-- disponibles. Ningún dato se borró — dos de los cuatro (Dr. Juan Carlos Rodríguez, Dra. Ariela
-- Grullón) comparten un mismo consultorio real ("NutriTeam"), creado con org_type='Médico
-- independiente' (incorrecto, confirmado por el usuario que sí comparten práctica) y sin ninguna
-- forma de encontrarlos por su propio nombre en "Clientes" — la búsqueda solo comparaba contra el
-- nombre del consultorio.
--
-- 1) Agrega "doctors" a v_client_360: los nombres de los médicos (rol 'client' activo) de cada
-- consultorio, para mostrarlos como subtítulo en el listado.
create or replace view public.v_client_360 as
WITH b AS (
  SELECT v_submission_balance.id, v_submission_balance.organization_id, v_submission_balance.provider_id,
    v_submission_balance.ars_id, v_submission_balance.period, v_submission_balance.folio,
    v_submission_balance.status, v_submission_balance.submitted_on, v_submission_balance.ncf,
    v_submission_balance.lines, v_submission_balance.claimed, v_submission_balance.paid,
    v_submission_balance.glosado, v_submission_balance.glosa_accepted, v_submission_balance.glosa_recovered,
    v_submission_balance.glosa_in_dispute, v_submission_balance.balance, v_submission_balance.display_status,
    v_submission_balance.payment_deadline, v_submission_balance.age_days, v_submission_balance.aging_bucket
  FROM v_submission_balance
), lastpay AS (
  SELECT pa.submission_id, max(p.paid_on) AS last_paid
  FROM (payment_allocations pa JOIN payments p ON ((p.id = pa.payment_id)))
  GROUP BY pa.submission_id
), docs AS (
  SELECT ou.organization_id, string_agg(DISTINCT pr.full_name, ', ' ORDER BY pr.full_name) AS doctors
  FROM organization_users ou
  JOIN profiles pr ON pr.id = ou.user_id
  WHERE ou.role_code = 'client' AND ou.is_active
  GROUP BY ou.organization_id
)
SELECT o.id AS organization_id, o.legal_name, o.status, o.started_on,
  count(b.id) AS submissions,
  count(b.id) FILTER (WHERE (b.submitted_on IS NOT NULL)) AS submitted,
  COALESCE(sum(b.claimed) FILTER (WHERE (b.submitted_on IS NOT NULL)), (0)::numeric) AS radicado,
  COALESCE(sum(b.paid), (0)::numeric) AS pagado,
  COALESCE(sum(b.glosado), (0)::numeric) AS glosado,
  COALESCE(sum(b.balance), (0)::numeric) AS saldo,
  round((((100)::numeric * COALESCE(sum(b.paid), (0)::numeric)) / NULLIF(sum(b.claimed) FILTER (WHERE (b.submitted_on IS NOT NULL)), (0)::numeric)), 1) AS tasa_pago,
  round((((100)::numeric * COALESCE(sum(b.glosado), (0)::numeric)) / NULLIF(sum(b.claimed) FILTER (WHERE (b.submitted_on IS NOT NULL)), (0)::numeric)), 1) AS tasa_glosa,
  round(avg((lp.last_paid - b.submitted_on)) FILTER (WHERE (b.display_status = 'pagada'::text))) AS dias_promedio_cobro,
  count(b.id) FILTER (WHERE ((b.age_days > COALESCE((st.payment_term_days)::integer, 90)) AND (b.balance > (0)::numeric))) AS vencidas,
  ( SELECT count(*) AS count FROM provider_ars_codes c WHERE ((c.organization_id = o.id) AND (c.status <> 'codificado'::text))) AS codigos_pendientes,
  d.doctors
FROM (((( organizations o
  LEFT JOIN b ON ((b.organization_id = o.id)))
  LEFT JOIN lastpay lp ON ((lp.submission_id = b.id)))
  LEFT JOIN app_settings st ON ((st.operator_id = o.operator_id)))
  LEFT JOIN docs d ON (d.organization_id = o.id))
WHERE (o.kind = 'client'::text)
GROUP BY o.id, o.legal_name, o.status, o.started_on, st.payment_term_days, d.doctors;

alter view public.v_client_360 set (security_invoker = true);

-- 2) Corrige el tipo de NutriTeam: era "Médico independiente" (una sola práctica), pero el
-- usuario confirmó que sí es un consultorio con más de un médico.
update public.organizations set org_type = 'Consultorio'
where id = '458bcb18-4339-4df4-a0c5-5d0ba5cdcaab' and org_type = 'Médico independiente';
