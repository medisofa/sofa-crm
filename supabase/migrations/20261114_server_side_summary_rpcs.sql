-- Ya aplicado en producción (mcp__Supabase__apply_migration).
-- Reemplaza funciones de resumen que traían miles de filas para agregar en el cliente
-- por RPCs que devuelven los KPIs pre-agregados desde Postgres.

-- RPC 1: Conteos de reclamaciones por estado (reemplaza claimCounts: 20,000 filas → ~15 filas)
CREATE OR REPLACE FUNCTION claim_status_counts(p_real_only boolean DEFAULT false)
RETURNS TABLE(claim_status text, cnt bigint)
LANGUAGE sql STABLE SECURITY INVOKER
AS $$
  SELECT v.claim_status, count(*) AS cnt
  FROM v_claims v
  WHERE (NOT p_real_only OR v.organization_id IN (SELECT id FROM sofa_real_client_organizations))
  GROUP BY v.claim_status;
$$;

-- RPC 2: KPIs de radicaciones (reemplaza submissionSummary: 5,000 filas → 1 fila)
CREATE OR REPLACE FUNCTION submission_summary_kpis(p_real_only boolean DEFAULT false)
RETURNS TABLE(
  prep_count bigint, prep_claimed numeric,
  ready_count bigint, ready_claimed numeric,
  open_count bigint, open_balance numeric,
  late_count bigint, soon_count bigint
)
LANGUAGE sql STABLE SECURITY INVOKER
AS $$
  SELECT
    count(*) FILTER (WHERE status IN ('borrador','recibida','pendiente_documentos','en_depuracion')) AS prep_count,
    coalesce(sum(claimed) FILTER (WHERE status IN ('borrador','recibida','pendiente_documentos','en_depuracion')), 0) AS prep_claimed,
    count(*) FILTER (WHERE status = 'lista_para_radicar') AS ready_count,
    coalesce(sum(claimed) FILTER (WHERE status = 'lista_para_radicar'), 0) AS ready_claimed,
    count(*) FILTER (WHERE status IN ('radicada','en_auditoria_ars') AND balance > 0) AS open_count,
    coalesce(sum(balance) FILTER (WHERE status IN ('radicada','en_auditoria_ars') AND balance > 0), 0) AS open_balance,
    count(*) FILTER (WHERE status IN ('radicada','en_auditoria_ars') AND balance > 0 AND payment_deadline < current_date) AS late_count,
    count(*) FILTER (WHERE status IN ('radicada','en_auditoria_ars') AND balance > 0 AND payment_deadline >= current_date AND payment_deadline <= current_date + 15) AS soon_count
  FROM v_submissions
  WHERE (NOT p_real_only OR is_demo = false);
$$;

-- RPC 3: KPIs de glosas (reemplaza glosaSummary: 5,000 filas → 1 fila)
CREATE OR REPLACE FUNCTION glosa_summary_kpis(p_real_only boolean DEFAULT false)
RETURNS TABLE(
  total_amount numeric, total_in_dispute numeric, total_recovered numeric, total_accepted numeric,
  total_count bigint, soon_count bigint, sla15_count bigint, sla15_amount numeric
)
LANGUAGE sql STABLE SECURITY INVOKER
AS $$
  SELECT
    coalesce(sum(amount), 0) AS total_amount,
    coalesce(sum(in_dispute), 0) AS total_in_dispute,
    coalesce(sum(recovered), 0) AS total_recovered,
    coalesce(sum(accepted), 0) AS total_accepted,
    count(*) AS total_count,
    count(*) FILTER (WHERE status IN ('pendiente','analizada','apelada','en_revision','en_conciliacion','en_arbitraje') AND days_left <= 7) AS soon_count,
    count(*) FILTER (WHERE status IN ('pendiente','analizada','apelada','en_revision','en_conciliacion','en_arbitraje') AND days_left >= 0 AND days_left <= 15) AS sla15_count,
    coalesce(sum(amount) FILTER (WHERE status IN ('pendiente','analizada','apelada','en_revision','en_conciliacion','en_arbitraje') AND days_left >= 0 AND days_left <= 15), 0) AS sla15_amount
  FROM v_glosas
  WHERE (NOT p_real_only OR organization_id IN (SELECT id FROM sofa_real_client_organizations));
$$;
