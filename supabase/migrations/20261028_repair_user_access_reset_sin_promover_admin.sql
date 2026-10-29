-- 28/10/2026: admin_repair_user_access() SIEMPRE promovía la cuenta a Administrador SOFA
-- en el operador, sin opción de solo desactivar la asociación errónea. El botón "Corregir
-- asignación" aparece para CUALQUIER Médico/Secretaria activo de un cliente, así que un
-- Super Admin podía, sin querer, quitarle su acceso real a un médico legítimo (ej. Dr. Juan
-- Carlos Rodríguez Polanco, Médico/Cliente en NutriTeam) y convertirlo en Administrador SOFA
-- del operador. Se agrega p_promote_admin (default false = solo reset) para que promover a
-- Administrador sea una casilla explícita, no el comportamiento por defecto. Reportado por el
-- usuario probando la app en producción. Aplicado en producción (Supabase, proyecto
-- bpwjhgpzhzhiocoxrvzq) y registrado aquí para el historial.

alter function public.admin_repair_user_access(uuid, uuid, text, text, text)
  rename to admin_repair_user_access_deprecated_5arg;
revoke all on function public.admin_repair_user_access_deprecated_5arg(uuid, uuid, text, text, text) from public, anon, authenticated;

create function public.admin_repair_user_access(
  p_user uuid, p_org uuid, p_reason text, p_confirm_email text, p_expected text, p_promote_admin boolean default false
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare context jsonb; actor uuid := auth.uid(); audit_id uuid; old_member jsonb; new_member jsonb;
begin
  context := app.user_access_repair_context(p_user, p_org);
  perform p.id from public.profiles p where p.id in (actor, p_user) order by p.id for update;
  perform u.id from auth.users u where u.id = p_user for update;
  perform o.id from public.organizations o where o.id = p_org for update;
  perform m.user_id from public.organization_users m
    where m.user_id in (actor, p_user) order by m.user_id, m.organization_id for update;
  context := app.user_access_repair_context(p_user, p_org);
  if not (context->>'can_repair')::boolean then
    raise exception 'No se puede corregir automáticamente: %', context->'blockers' using errcode = '23514';
  end if;
  if p_expected is null or p_expected is distinct from context->>'expected' then
    raise exception 'Los accesos cambiaron. Revise una nueva vista previa.' using errcode = '40001';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 12 then raise exception 'Indique un motivo de al menos 12 caracteres' using errcode = '22023'; end if;
  if p_confirm_email is null or lower(btrim(p_confirm_email)) is distinct from lower(context->>'email') then
    raise exception 'El correo de confirmación no coincide' using errcode = '22023';
  end if;
  old_member := context->'before_access';
  update public.organization_users set is_active = false where user_id = p_user and organization_id = p_org;
  if p_promote_admin then
    insert into public.organization_users(organization_id, user_id, role_code, is_active)
      values ((context->>'operator_id')::uuid, p_user, 'admin', (context->>'profile_active')::boolean)
      on conflict (organization_id, user_id) do update set role_code = 'admin', is_active = excluded.is_active;
    select to_jsonb(m) into new_member from public.organization_users m
      where m.user_id = p_user and m.organization_id = (context->>'operator_id')::uuid;
  else
    select to_jsonb(m) into new_member from public.organization_users m
      where m.user_id = p_user and m.organization_id = p_org;
  end if;
  insert into public.user_access_repair_audit(actor_id, user_id, client_org_id, operator_id, reason, before_access, before_staff, after_access)
    values (actor, p_user, p_org, (context->>'operator_id')::uuid, btrim(p_reason), old_member, context->'before_staff', new_member)
    returning id into audit_id;
  return jsonb_build_object('ok', true, 'audit_id', audit_id, 'user_id', p_user, 'promoted_admin', p_promote_admin,
    'profile_active', (context->>'profile_active')::boolean,
    'message', case when p_promote_admin
      then 'Asociación corregida y Administrador SOFA asignado. Se conservan la cuenta, el correo y el historial.'
      else 'Asociación errónea desactivada. No se otorgó ningún rol nuevo. Se conservan la cuenta, el correo y el historial.' end);
end $$;

revoke all on function public.admin_repair_user_access(uuid, uuid, text, text, text, boolean) from public, anon;
grant execute on function public.admin_repair_user_access(uuid, uuid, text, text, text, boolean) to authenticated;
notify pgrst, 'reload schema';
