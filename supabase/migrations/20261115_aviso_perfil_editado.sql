-- SOFA · 5.35.10 · El usuario cuyo perfil edita el Super Admin se entera.
-- Cuando el Super Admin usa admin_update_user_profile, el trigger profiles_audit ya escribe
-- en audit_log quién cambió qué. Aquí exponemos dos RPCs para que la UI del propio dueño
-- del perfil pueda:
--   · ver los cambios que otra persona hizo en SU perfil desde la última vez que lo marcó
--     como visto
--   · marcarlos como vistos
-- No se toca la RLS de audit_log: las RPCs son SECURITY DEFINER y filtran al dueño.
--
-- Ya aplicado en producción (mcp__Supabase__apply_migration 15/11/2026).

alter table public.profiles
  add column if not exists last_profile_change_seen_at timestamptz;

create or replace function public.my_recent_profile_changes()
returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare
  v_actor uuid := auth.uid();
  v_seen timestamptz;
  v_rows jsonb;
begin
  if v_actor is null then raise exception 'Debe iniciar sesión.'; end if;
  select coalesce(last_profile_change_seen_at, 'epoch'::timestamptz)
    into v_seen from public.profiles where id = v_actor;

  select coalesce(jsonb_agg(jsonb_build_object(
    'at', a.occurred_at,
    'by_id', a.user_id,
    'by_name', p.full_name,
    'changes', (
      select coalesce(jsonb_object_agg(k, jsonb_build_object('from', a.old_values->k, 'to', a.new_values->k)), '{}'::jsonb)
        from jsonb_object_keys(coalesce(a.new_values, '{}'::jsonb)) k
       where a.new_values->k is distinct from a.old_values->k
         and k in ('full_name','phone')
    )
  ) order by a.occurred_at desc), '[]'::jsonb)
    into v_rows
    from public.audit_log a
    left join public.profiles p on p.id = a.user_id
   where a.table_name = 'profiles'
     and a.record_id = v_actor::text
     and a.operation in ('UPDATE','update')
     and a.user_id is distinct from v_actor
     and a.occurred_at > v_seen;

  -- Solo entradas con al menos un campo relevante cambiado.
  select coalesce(jsonb_agg(x), '[]'::jsonb)
    into v_rows
    from jsonb_array_elements(v_rows) x
   where (x->'changes') <> '{}'::jsonb;

  return jsonb_build_object(
    'seen_at', v_seen,
    'pending', jsonb_array_length(v_rows),
    'entries', v_rows
  );
end $$;

create or replace function public.my_profile_changes_acknowledge()
returns void
language plpgsql security definer set search_path to '' as $$
begin
  if auth.uid() is null then raise exception 'Debe iniciar sesión.'; end if;
  update public.profiles
     set last_profile_change_seen_at = now()
   where id = auth.uid();
end $$;

revoke all on function public.my_recent_profile_changes() from public;
revoke execute on function public.my_recent_profile_changes() from anon;
grant execute on function public.my_recent_profile_changes() to authenticated;

revoke all on function public.my_profile_changes_acknowledge() from public;
revoke execute on function public.my_profile_changes_acknowledge() from anon;
grant execute on function public.my_profile_changes_acknowledge() to authenticated;
