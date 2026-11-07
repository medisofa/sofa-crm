-- Mejoras de rendimiento: índices para las consultas de mayor tráfico
-- NOTA: ya aplicado en producción (2026-11-07)
-- Sin CONCURRENTLY: el SQL Editor de Supabase corre en transacción y no lo admite.
-- El bloqueo breve de escritura es aceptable en mantenimiento programado.

-- service_lines: filtros frecuentes en capture.js / claims.js
CREATE INDEX IF NOT EXISTS idx_service_lines_submission
  ON service_lines (submission_id);

CREATE INDEX IF NOT EXISTS idx_service_lines_org
  ON service_lines (organization_id);

-- submissions: filtros de listSubmissions (status, ars, período, organización)
CREATE INDEX IF NOT EXISTS idx_submissions_org_status
  ON submissions (organization_id, status);

CREATE INDEX IF NOT EXISTS idx_submissions_ars_period
  ON submissions (ars_id, period);

-- tasks: listTasks filtra por assignee y entity (bucket es columna de v_tasks, no de tasks base)
CREATE INDEX IF NOT EXISTS idx_tasks_assignee
  ON tasks (assignee_id);

CREATE INDEX IF NOT EXISTS idx_tasks_entity
  ON tasks (entity_type, entity_id);

-- claim_status_history: consultado en cada apertura de reclamación
CREATE INDEX IF NOT EXISTS idx_claim_status_history_claim
  ON claim_status_history (service_line_id, changed_at DESC);

-- receptions: filtrado por organización y estado en retiros
CREATE INDEX IF NOT EXISTS idx_receptions_org_status
  ON receptions (organization_id, status);

-- glosa_items: accedido por glosa (detalle) y por service_line (reclamación)
CREATE INDEX IF NOT EXISTS idx_glosa_items_glosa
  ON glosa_items (glosa_id);

CREATE INDEX IF NOT EXISTS idx_glosa_items_line
  ON glosa_items (service_line_id);

-- payment_line_allocations: consultado al calcular saldo de radicación
CREATE INDEX IF NOT EXISTS idx_payment_line_alloc_submission
  ON payment_line_allocations (submission_id);

-- capturer_scopes / assistant_scopes: usados en RLS para resolver org visibles
CREATE INDEX IF NOT EXISTS idx_capturer_scopes_profile
  ON capturer_scopes (profile_id);

CREATE INDEX IF NOT EXISTS idx_assistant_scopes_profile
  ON assistant_scopes (profile_id);
