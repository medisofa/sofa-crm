-- SOFA Security P0
-- Restringir RPC destructivas a sesiones autenticadas.
-- La autorización interna super_admin se conserva.
-- No modifica datos, tablas ni funciones existentes.

BEGIN;

REVOKE EXECUTE ON FUNCTION
  public.data_reset(text[],text,text,boolean)
FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION
  public.honorarios_reset(text,text,boolean,boolean)
FROM PUBLIC, anon;

COMMIT;
