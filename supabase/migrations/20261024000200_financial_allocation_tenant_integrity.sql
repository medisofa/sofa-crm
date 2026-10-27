-- SOFA Security P0: integridad financiera multiempresa
-- Ejecutar solo después de regresión funcional satisfactoria.
BEGIN;

ALTER TABLE public.payment_allocations
  ADD CONSTRAINT payment_allocations_full_identity_uq
  UNIQUE (id, organization_id, payment_id, submission_id);

ALTER TABLE public.service_lines
  ADD CONSTRAINT service_lines_full_identity_uq
  UNIQUE (id, organization_id, submission_id);

ALTER TABLE public.payment_line_allocations
  ADD CONSTRAINT pla_full_allocation_identity_fk
  FOREIGN KEY (allocation_id, organization_id, payment_id, submission_id)
  REFERENCES public.payment_allocations
  (id, organization_id, payment_id, submission_id);

ALTER TABLE public.payment_line_allocations
  ADD CONSTRAINT pla_full_line_submission_fk
  FOREIGN KEY (service_line_id, organization_id, submission_id)
  REFERENCES public.service_lines
  (id, organization_id, submission_id);

COMMIT;
