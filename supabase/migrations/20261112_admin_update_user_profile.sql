-- SOFA · 5.31.0 · Super Admin edita el perfil (nombre y teléfono) de otros usuarios.
-- La bitácora queda automáticamente registrada por el trigger profiles_audit (app.audit),
-- que anota auth.uid() como actor y solo los campos que efectivamente cambiaron.
-- SECURITY DEFINER para poder saltar la RLS profiles_update_own, con guarda explícita.
--
-- Ya aplicado en producción (mcp__Supabase__apply_migration 12/11/2026).
create or replace function public.admin_update_user_profile(
  p_user uuid,
  p_full_name text default null,
  p_phone text default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor uuid := auth.uid();
  v_is_super boolean;
  v_old record;
  v_new_name text;
  v_new_phone text;
begin
  if v_actor is null then raise exception 'Debe iniciar sesión.'; end if;
  if p_user is null then raise exception 'Indique el usuario.'; end if;

  -- solo super_admin puede editar perfiles ajenos
  select exists(
    select 1 from public.organization_users
    where user_id = v_actor and role_code = 'super_admin' and is_active = true
  ) into v_is_super;
  if not v_is_super then
    raise exception 'Solo el Super Admin puede editar el perfil de otros usuarios.';
  end if;

  -- cargar lo actual para no sobreescribir con NULL lo que el llamador no envió
  select full_name, phone into v_old from public.profiles where id = p_user;
  if v_old is null then raise exception 'No existe el usuario %', p_user; end if;

  v_new_name  := coalesce(nullif(trim(p_full_name), ''), v_old.full_name);
  v_new_phone := coalesce(nullif(trim(p_phone),     ''), v_old.phone);

  -- validaciones mínimas
  if length(v_new_name) < 3 then raise exception 'El nombre completo debe tener al menos 3 caracteres.'; end if;
  if length(v_new_name) > 120 then raise exception 'El nombre completo no puede superar 120 caracteres.'; end if;
  if v_new_phone is not null and length(v_new_phone) > 40 then raise exception 'El teléfono es demasiado largo.'; end if;

  -- la actualización dispara el trigger profiles_audit (bitácora)
  update public.profiles
     set full_name = v_new_name,
         phone     = v_new_phone
   where id = p_user
     and (full_name is distinct from v_new_name or phone is distinct from v_new_phone);

  return jsonb_build_object(
    'ok', true,
    'id', p_user,
    'full_name', v_new_name,
    'phone', v_new_phone
  );
end
$$;

revoke all on function public.admin_update_user_profile(uuid, text, text) from public;
grant execute on function public.admin_update_user_profile(uuid, text, text) to authenticated;

comment on function public.admin_update_user_profile(uuid, text, text) is
  'Super Admin edita nombre y teléfono de otros perfiles. La bitácora queda en audit_log por el trigger profiles_audit.';
