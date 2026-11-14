-- Ya aplicado en producción via mcp__Supabase__apply_migration
-- Fecha: 2024-11-14
-- Descripción: 5 RPCs para eliminar agregación client-side de las funciones restantes
--   - task_bucket_counts: conteo de tareas por bucket (reemplaza ~2000 filas)
--   - glosa_pareto_by_reason: monto glosado agrupado por motivo (reemplaza ~5000 filas)
--   - glosa_pareto_by_ars: monto glosado agrupado por ARS (reemplaza ~5000 filas)
--   - ars_reconciliation_agg: conciliación ARS pre-agrupada (reemplaza ~5000 filas)
--   - clients_open_balance: clientes con saldo abierto agrupado por org+ARS (reemplaza ~5000 filas)
-- Todas usan SECURITY INVOKER para respetar RLS.

CREATE OR REPLACE FUNCTION task_bucket_counts(
  p_assignee uuid DEFAULT NULL,
  p_real_only boolean DEFAULT false
) RETURNS TABLE(bucket text, cnt bigint)
  LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT v.bucket, count(*) AS cnt
  FROM v_tasks v
  WHERE (p_assignee IS NULL OR v.assignee_id = p_assignee)
    AND (
      NOT p_real_only
      OR v.organization_id IS NULL
      OR v.organization_id IN (SELECT id FROM sofa_real_client_organizations)
    )
  GROUP BY v.bucket;
$$;

CREATE OR REPLACE FUNCTION glosa_pareto_by_reason(
  p_real_only boolean DEFAULT false
) RETURNS TABLE(reason_name text, total_amount numeric)
  LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT v.reason_name, sum(v.amount) AS total_amount
  FROM v_glosa_pareto v
  WHERE NOT p_real_only
     OR v.organization_id IN (SELECT id FROM sofa_real_client_organizations)
  GROUP BY v.reason_name
  ORDER BY total_amount DESC
  LIMIT 20;
$$;

CREATE OR REPLACE FUNCTION glosa_pareto_by_ars(
  p_real_only boolean DEFAULT false
) RETURNS TABLE(ars_id uuid, ars_name text, total_amount numeric)
  LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT v.ars_id, v.ars_name, sum(v.amount) AS total_amount
  FROM v_glosa_pareto v
  WHERE NOT p_real_only
     OR v.organization_id IN (SELECT id FROM sofa_real_client_organizations)
  GROUP BY v.ars_id, v.ars_name
  ORDER BY total_amount DESC;
$$;

CREATE OR REPLACE FUNCTION ars_reconciliation_agg(
  p_real_only boolean DEFAULT false
) RETURNS TABLE(ars_id uuid, ars text, radicado numeric, pagado numeric, glosa_aceptada numeric, saldo numeric)
  LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT v.ars_id, v.ars,
         sum(v.radicado)        AS radicado,
         sum(v.pagado)          AS pagado,
         sum(v.glosa_aceptada)  AS glosa_aceptada,
         sum(v.saldo)           AS saldo
  FROM v_ars_reconciliation v
  WHERE NOT p_real_only
     OR v.organization_id IN (SELECT id FROM sofa_real_client_organizations)
  GROUP BY v.ars_id, v.ars;
$$;

CREATE OR REPLACE FUNCTION clients_open_balance(
  p_real_only boolean DEFAULT false
) RETURNS TABLE(organization_id uuid, client_name text, ars_id uuid, ars_name text, total_balance numeric)
  LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT v.organization_id, v.client_name, v.ars_id, v.ars_name,
         sum(v.balance) AS total_balance
  FROM v_submissions v
  WHERE v.status IN ('radicada', 'en_auditoria_ars')
    AND v.balance > 0
    AND (NOT p_real_only
         OR v.organization_id IN (SELECT id FROM sofa_real_client_organizations))
  GROUP BY v.organization_id, v.client_name, v.ars_id, v.ars_name;
$$;
