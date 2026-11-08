-- ya aplicado en producción
-- Amplía el constraint patient_access_log_action_check para incluir
-- 'usar_registro_universal', acción insertada por attach_global_patient()
-- al vincular un paciente del Registro Universal SOFA a un consultorio.
ALTER TABLE public.patient_access_log
  DROP CONSTRAINT patient_access_log_action_check;

ALTER TABLE public.patient_access_log
  ADD CONSTRAINT patient_access_log_action_check
  CHECK (action = ANY (ARRAY['ver'::text, 'crear'::text, 'editar'::text, 'usar_registro_universal'::text]));
