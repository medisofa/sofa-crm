-- 246_reception_staff.sql
-- Ya aplicado en producción (2026-11-20, mcp__Supabase__apply_migration «reception_staff_246»).
-- Lista, para la Administración, las secretarias activas de la organización del centro y si atienden
-- su recepción. Complementa la 244 (pantalla «Recepción del centro»). Idempotente.
-- Prueba: AG-14 en 245_agenda_centros_test.sql.

do $$ begin
  if to_regclass('public.reception_scopes') is null then raise exception 'Falta la 244 (reception_scopes)'; end if;
end $$;

create or replace function public.reception_staff(p_center uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.health_centers where id = p_center;
  if v_org is null then raise exception 'El centro no existe.' using errcode = 'P0002'; end if;
  if not app.can(v_org, array['super_admin','admin']) then
    raise exception 'Solo la Administración asigna la recepción de un centro.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', ou.user_id, 'full_name', pr.full_name, 'role_code', ou.role_code, 'role_name', r.name,
                                                       'assigned', coalesce(rs.is_active, false)) order by pr.full_name)
                     from public.organization_users ou
                     join public.profiles pr on pr.id = ou.user_id and pr.is_active
                     left join public.roles r on r.code = ou.role_code
                     left join public.reception_scopes rs on rs.user_id = ou.user_id and rs.center_id = p_center
                    where ou.organization_id = v_org and ou.is_active and ou.role_code = 'capturer'), '[]'::jsonb);
end $$;
revoke execute on function public.reception_staff(uuid) from public, anon;
grant execute on function public.reception_staff(uuid) to authenticated;
