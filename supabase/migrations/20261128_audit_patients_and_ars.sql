-- SOFA · 5.48.2 · Bitácora para dos tablas sensibles que no la tenían.
-- Hallazgo del audit del enjambre (agente de seguridad): patients y ars son editables
-- pero sus UPDATEs/DELETEs no quedaban en audit_log. Patrón idéntico a los demás
-- triggers de audit (payments_audit, tariffs_audit, document_rules_audit).
--
-- Ya aplicado en producción (mcp__Supabase__apply_migration 2026-11-28).

create trigger patients_audit
  after insert or update or delete on public.patients
  for each row execute function app.audit();

create trigger ars_audit
  after insert or update or delete on public.ars
  for each row execute function app.audit();
