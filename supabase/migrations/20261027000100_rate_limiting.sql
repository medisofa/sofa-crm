-- ============================================================================
-- 20261027000100_rate_limiting.sql
-- Limitador de frecuencia (rate limiting) para las edge functions de SOFA.
--
-- Por qué: ni admin-users ni enviar-correos tenían ningún límite de frecuencia.
-- Un atacante (o un error de cliente) podía llamarlas sin freno alguno.
--
-- Qué agrega: una tabla de contadores por ventana fija y una función que
-- incrementa y responde si la clave sigue dentro del límite. Solo invocable
-- por service_role (las edge functions usan la clave de servicio), igual que
-- el resto de funciones administrativas de este proyecto.
--
-- Alcance: cubre las 2 edge functions propias (admin-users, enviar-correos).
-- NO cubre las ~500 RPCs auto-expuestas por PostgREST ni el login nativo de
-- Supabase Auth (ese se configura aparte, en el Dashboard: Authentication →
-- Rate Limits). Limitar cada RPC una por una, o poner un límite uniforme
-- sobre todas, requiere un WAF/proxy delante del dominio — fuera del alcance
-- de una migración de Postgres.
-- ============================================================================

-- En public (no app): las edge functions llaman admin.rpc('rate_limit_check', ...) y el
-- cliente de PostgREST apunta al esquema public por defecto, igual que admin_assign_role
-- y admin_user_id_by_email.
create table if not exists public.rate_limit_hits (
  bucket_key text not null,
  window_start timestamptz not null,
  hits integer not null default 1,
  primary key (bucket_key, window_start)
);

comment on table public.rate_limit_hits is
  'Contadores de rate limiting por ventana fija. Fila por (clave, ventana); se purgan solas tras 1 hora.';

alter table public.rate_limit_hits enable row level security;
-- Sin políticas: nadie entra por PostgREST/RLS. Solo se toca vía la función SECURITY DEFINER
-- de abajo, invocada con service_role. Revocación explícita también a nivel de tabla: no
-- asumir que RLS sola basta (es el mismo hallazgo de las 501 funciones del informe de hoy).
revoke all on public.rate_limit_hits from public, anon, authenticated;

create or replace function public.rate_limit_check(p_key text, p_max integer, p_window_seconds integer)
 returns boolean
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_window timestamptz;
  v_hits integer;
begin
  -- Ventana fija: todas las llamadas dentro del mismo bloque de p_window_seconds comparten fila.
  v_window := to_timestamp(floor(extract(epoch from clock_timestamp()) / p_window_seconds) * p_window_seconds);

  insert into public.rate_limit_hits (bucket_key, window_start, hits)
  values (p_key, v_window, 1)
  on conflict (bucket_key, window_start) do update set hits = public.rate_limit_hits.hits + 1
  returning hits into v_hits;

  -- Purga oportunista (barata, ~1% de las llamadas) para no crecer sin límite.
  if random() < 0.01 then
    delete from public.rate_limit_hits where window_start < clock_timestamp() - interval '1 hour';
  end if;

  return v_hits <= p_max;
end;
$function$;

comment on function public.rate_limit_check(text, integer, integer) is
  'Incrementa el contador de la clave dada y devuelve si sigue dentro del límite. Uso: select rate_limit_check(''ip:1.2.3.4'', 30, 300).';

revoke execute on function public.rate_limit_check(text, integer, integer) from public, anon, authenticated;
grant execute on function public.rate_limit_check(text, integer, integer) to service_role;
