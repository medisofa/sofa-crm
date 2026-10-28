-- Restringe admin_user_id_by_email(text): solo service_role puede ejecutarla.
-- Motivo: la función corre con privilegios elevados y consulta auth.users sin
-- verificar a quien llama. Con EXECUTE abierto a anon/authenticated, cualquiera
-- podía convertir un correo en un ID de usuario.
-- Único llamador conocido: supabase/functions/admin-users (cliente con service_role).
-- Idempotente: se puede correr más de una vez sin efecto adicional.

DO $mig$
DECLARE
  r record;
  n integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    RAISE EXCEPTION 'Falta el rol service_role. Qué hacer: este esquema no es un proyecto Supabase estándar; revisa los roles antes de aplicar esta migración.';
  END IF;

  FOR r IN
    SELECT p.oid::regprocedure AS firma
    FROM pg_proc p
    WHERE p.proname = 'admin_user_id_by_email'
  LOOP
    n := n + 1;
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.firma);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.firma);
    RAISE NOTICE 'Restringida: %', r.firma;
  END LOOP;

  IF n = 0 THEN
    RAISE NOTICE 'admin_user_id_by_email no existe en esta base; no hay nada que restringir.';
  END IF;
END
$mig$;
