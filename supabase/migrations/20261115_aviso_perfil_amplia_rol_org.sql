-- SOFA · 5.35.11 · Amplía el aviso: también cubre cambios de rol y de organización.
-- Reemplaza my_recent_profile_changes para unir dos fuentes del audit_log:
--   · profiles (full_name / phone)
--   · organization_users (INSERT/UPDATE/DELETE del acceso rol+organización)
-- El mismo acknowledge (my_profile_changes_acknowledge) cubre ambos: una sola marca.
--
-- Ya aplicado en producción (mcp__Supabase__apply_migration 15/11/2026).

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

  with prof as (
    select
      'profile' as kind,
      a.occurred_at as at,
      a.user_id as by_id,
      (select full_name from public.profiles where id = a.user_id) as by_name,
      (
        select coalesce(jsonb_object_agg(k, jsonb_build_object('from', a.old_values->k, 'to', a.new_values->k)), '{}'::jsonb)
          from jsonb_object_keys(coalesce(a.new_values, '{}'::jsonb)) k
         where a.new_values->k is distinct from a.old_values->k
           and k in ('full_name','phone')
      ) as changes,
      null::text as op
      from public.audit_log a
     where a.table_name = 'profiles'
       and a.record_id = v_actor::text
       and a.operation in ('UPDATE','update')
       and a.user_id is distinct from v_actor
       and a.occurred_at > v_seen
  ),
  acc as (
    -- INSERT = «te dieron acceso»; DELETE = «te quitaron»; UPDATE = cambio (rol o is_active).
    select
      'access' as kind,
      a.occurred_at as at,
      a.user_id as by_id,
      (select full_name from public.profiles where id = a.user_id) as by_name,
      jsonb_strip_nulls(jsonb_build_object(
        'operation', a.operation,
        'organization_id', coalesce(a.new_values->>'organization_id', a.old_values->>'organization_id'),
        'organization_name', (
          select legal_name from public.organizations o
           where o.id::text = coalesce(a.new_values->>'organization_id', a.old_values->>'organization_id')
        ),
        'role_from', case when a.operation in ('UPDATE','update') then r_old.name else null end,
        'role_to',   case when a.operation in ('INSERT','insert','UPDATE','update') then r_new.name else null end,
        'role_removed', case when a.operation in ('DELETE','delete') then r_old.name else null end,
        'is_active_from', case when a.operation in ('UPDATE','update') and (a.old_values->>'is_active') is distinct from (a.new_values->>'is_active')
                               then (a.old_values->>'is_active')::boolean else null end,
        'is_active_to',   case when a.operation in ('UPDATE','update') and (a.old_values->>'is_active') is distinct from (a.new_values->>'is_active')
                               then (a.new_values->>'is_active')::boolean else null end
      )) as changes,
      a.operation as op
      from public.audit_log a
      left join public.roles r_new on r_new.code = a.new_values->>'role_code'
      left join public.roles r_old on r_old.code = a.old_values->>'role_code'
     where a.table_name = 'organization_users'
       and a.record_id = v_actor::text
       and a.user_id is distinct from v_actor
       and a.occurred_at > v_seen
  ),
  todo as (
    select * from prof
    union all
    select * from acc
    order by at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', kind, 'at', at, 'by_id', by_id, 'by_name', by_name, 'changes', changes, 'op', op
  )), '[]'::jsonb) into v_rows from todo;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_rows
    from jsonb_array_elements(v_rows) x
   where not (x->>'kind' = 'profile' and (x->'changes') = '{}'::jsonb);

  return jsonb_build_object(
    'seen_at', v_seen,
    'pending', jsonb_array_length(v_rows),
    'entries', v_rows
  );
end $$;
