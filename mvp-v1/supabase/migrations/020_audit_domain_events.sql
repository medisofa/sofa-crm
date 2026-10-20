-- SOFA · Auditoría de eventos de negocio
-- audit_log sigue aceptando INSERT/UPDATE/DELETE y además eventos de dominio
-- en mayúsculas con guiones bajos, usados por flujos auditables como SeNaSa y anti-duplicados.

alter table public.audit_log
  drop constraint if exists audit_log_operation_check;

alter table public.audit_log
  add constraint audit_log_operation_check
  check (
    operation in ('INSERT','UPDATE','DELETE')
    or operation ~ '^[A-Z][A-Z0-9_]{2,63}$'
  );
