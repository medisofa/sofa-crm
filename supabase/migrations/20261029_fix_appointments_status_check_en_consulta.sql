-- 29/10/2026: PR #75 agregó el estado 'en_consulta' (call_appointment_in / set_appointment_status)
-- pero nunca actualizó esta restricción, así que CUALQUIER intento de llamar a un paciente a
-- consulta fallaba con una violación de constraint (23514). Detectado probando el tablero de
-- flujo de pacientes con una cuenta Asistente real en producción, y ya aplicado ahí; esta
-- migración solo lo deja registrado en el repositorio.
alter table public.appointments drop constraint appointments_status_check;
alter table public.appointments add constraint appointments_status_check
  check (status = any (array['programada','confirmada','en_espera','en_consulta','atendida','no_asistio','cancelada']));
