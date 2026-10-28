-- ============================================================================
-- 20261027000200_revoke_anon_default_execute.sql
-- Cierra el hallazgo CRÍTICO del informe de vigilancia del 27 oct 2026:
-- 501 funciones en public/app eran ejecutables por anon (471 SECURITY
-- DEFINER) porque Postgres concede EXECUTE a PUBLIC por defecto y este
-- proyecto nunca estableció una línea base de revocación.
--
-- Verificación previa (sesión del 27 oct 2026): se revisaron los 3 puntos de
-- entrada públicos reales del frontend (portal.html, solicitud.html,
-- login.html) y confirman que NINGUNO llama a nada fuera de las 6 funciones
-- ya permitidas abajo. Por eso este cambio es seguro para usuarios anónimos
-- legítimos y transparente para usuarios con sesión (ver siguiente párrafo).
--
-- Qué hace: para cada función en public/app que hoy ejecuta anon y NO está en
-- la lista blanca de entrada pública, revoca EXECUTE de PUBLIC y de anon, y
-- lo restaura explícitamente para authenticated. Es decir: los usuarios
-- logueados (el 100% del uso real hoy) siguen teniendo acceso exactamente
-- igual que antes; solo se cierra la puerta a quien no tiene sesión.
--
-- No toca funciones que ya estaban correctamente restringidas (ej.
-- admin_assign_role, register_new_user) ni añade restricciones nuevas sobre
-- authenticated — ese nivel de permisos lo sigue resolviendo cada función
-- internamente (RLS, app.role_for_org(), etc.), igual que hoy.
-- ============================================================================

do $$
declare
  r record;
  v_tocadas int := 0;
begin
  for r in
    select p.oid, s.nspname as esquema, p.proname as funcion,
           pg_get_function_identity_arguments(p.oid) as firma
    from pg_proc p
    join pg_namespace s on s.oid = p.pronamespace
    where s.nspname in ('public','app')
      and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
      and has_function_privilege('anon', p.oid, 'execute')
      and (s.nspname || '.' || p.proname) not in (
        'public.service_request_create', 'public.service_request_view',
        'public.service_request_doc_register', 'public.portal_view',
        'public.portal_appointment_action', 'app.intake_puede_subir'
      )
  loop
    execute format('revoke execute on function %I.%I(%s) from public, anon', r.esquema, r.funcion, r.firma);
    execute format('grant execute on function %I.%I(%s) to authenticated', r.esquema, r.funcion, r.firma);
    v_tocadas := v_tocadas + 1;
  end loop;
  raise notice 'revoke_anon_default_execute: % funciones ajustadas (anon revocado, authenticated conservado)', v_tocadas;
end $$;

-- Verificación: debe quedar en 0, igual que exige el chequeo #2 de la capa 1 de vigilancia.
do $$
declare v_restantes int;
begin
  select count(*) into v_restantes
  from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname in ('public','app') and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
    and has_function_privilege('anon', p.oid, 'execute')
    and (s.nspname || '.' || p.proname) not in (
      'public.service_request_create', 'public.service_request_view',
      'public.service_request_doc_register', 'public.portal_view',
      'public.portal_appointment_action', 'app.intake_puede_subir'
    );
  if v_restantes <> 0 then
    raise exception 'La migración no dejó el conteo en 0: quedan % funciones ejecutables por anon fuera de la lista blanca', v_restantes;
  end if;
end $$;
