-- ============================================================================
-- 20261026000100_mfa_ok_falla_cerrada.sql
-- Hallazgo H03 de la auditoría del 26 oct 2026.
--
-- Problema: app.mfa_ok() devuelve TRUE (deja pasar sin MFA) cuando app_settings
-- no tiene ninguna fila, porque bool_or() sobre cero filas es NULL y se trata
-- como "no se exige". Hoy hay una fila con require_staff_mfa = true, así que en
-- producción no hay brecha abierta; el riesgo es que la fila se borre o se
-- recree vacía y el sistema quede abierto sin avisar.
--
-- Qué cambia: SOLO el caso "no hay filas". Ahora, sin configuración, se exige
-- AAL2. Con filas se comporta igual que antes:
--   alguna fila con require_staff_mfa = true  -> exige AAL2   (igual que antes)
--   todas las filas con require_staff_mfa = false -> no exige (igual que antes)
--   ninguna fila                               -> exige AAL2   (NUEVO)
--
-- Probado en qa/sql/18_lote_mfa_falla_cerrada.sql (11 escenarios, PASS) y en
-- qa/sql/12_mfa_fail_open.sql (caso rojo que esta migración cierra).
--
-- Es una réplica completa de la función vigente en producción (regla 5 del
-- proyecto): se conservan LANGUAGE sql, STABLE, SECURITY DEFINER y search_path ''.
-- CREATE OR REPLACE conserva los permisos existentes. Idempotente.
-- ============================================================================

-- 1) Dependencias
do $$
begin
  if to_regprocedure('app.mfa_ok()') is null then
    raise exception 'No existe app.mfa_ok(). Aplique primero la migración que la crea.' using errcode = '42883';
  end if;
  if to_regclass('public.app_settings') is null then
    raise exception 'No existe public.app_settings. Aplique primero la migración que la crea.' using errcode = '42P01';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'app_settings' and column_name = 'require_staff_mfa') then
    raise exception 'Falta la columna app_settings.require_staff_mfa. Aplique primero la migración que la agrega.' using errcode = '42703';
  end if;
  if to_regprocedure('auth.jwt()') is null then
    raise exception 'No existe auth.jwt(). Este proyecto debe correr sobre Supabase Auth.' using errcode = '42883';
  end if;
end $$;

-- 2) Función
create or replace function app.mfa_ok()
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case
           when exists (select 1 from public.app_settings)
            and not exists (select 1 from public.app_settings s where s.require_staff_mfa is not false)
             then true
           else coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
         end;
$function$;

-- 3) Verificación: la firma y los atributos no cambiaron.
do $$
declare p pg_proc%rowtype;
begin
  select * into p from pg_proc where oid = to_regprocedure('app.mfa_ok()');
  if not p.prosecdef or p.provolatile <> 's' or p.prorettype <> 'boolean'::regtype
     or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%') then
    raise exception 'app.mfa_ok() quedó con atributos distintos a los esperados. Revierta con rollback.';
  end if;
end $$;

-- ============================================================================
-- REVERSA (definición anterior, vigente en producción antes de esta migración):
-- begin;
-- create or replace function app.mfa_ok()
--  returns boolean language sql stable security definer set search_path to ''
-- as $function$
--   select case when not coalesce((select bool_or(s.require_staff_mfa) from public.app_settings s), false) then true
--               else coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2' end;
-- $function$;
-- commit;
-- ============================================================================
