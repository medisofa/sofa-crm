-- Mejoras de rendimiento: índices para las consultas de mayor tráfico
-- NOTA: ya aplicado en producción manualmente (pendiente de confirmar con el usuario)
-- Ejecutar con precaución en producción: usar CONCURRENTLY para no bloquear escrituras.

-- service_lines: filtros frecuentes en capture.js / claims.js
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_service_lines_submission
  ON service_lines (submission_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_service_lines_org
  ON service_lines (organization_id);

-- submissions: filtros de listSubmissions (status, ars, período, organización)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_submissions_org_status
  ON submissions (organization_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_submissions_ars_period
  ON submissions (ars_id, period);

-- tasks: listTasks filtra por bucket, assignee, entity
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tasks_bucket_due
  ON tasks (bucket, due_date);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tasks_assignee
  ON tasks (assignee_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tasks_entity
  ON tasks (entity_type, entity_id);

-- claim_status_history: consultado en cada apertura de reclamación
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_claim_status_history_claim
  ON claim_status_history (claim_id, changed_at DESC);

-- receptions: filtrado por organización y estado en retiros
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_receptions_org_status
  ON receptions (organization_id, status);

-- glosa_items: por radicación, accedido en el detalle de glosas
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_glosa_items_submission
  ON glosa_items (submission_id);

-- payment_line_allocations: consultado al calcular saldo de radicación
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_payment_line_alloc_submission
  ON payment_line_allocations (submission_id);

-- capturer_scopes / assistant_scopes: usados en RLS para resolver org visibles
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_capturer_scopes_profile
  ON capturer_scopes (profile_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_assistant_scopes_profile
  ON assistant_scopes (profile_id);
