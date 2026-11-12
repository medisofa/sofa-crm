-- SOFA · 5.34.0 · Fortalecer guard de admin_update_user_profile.
-- La v1 (20261112_admin_update_user_profile) verificaba solo role_code='super_admin' en
-- organization_users. app.is_staff(ARRAY['super_admin']) es el patron consistente del resto
-- del esquema y anade: organizacion operador (no cliente), rol marcado is_staff, perfil
-- activo sin must_change_password pendiente, y MFA verificado (app.mfa_ok()).
--
-- Ya aplicado en produccion (mcp__Supabase__apply_migration 12/11/2026).
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
  v_old record;
  v_new_name text;
  v_new_phone text;
begin
  if v_actor is null then raise exception 'Debe iniciar sesion.'; end if;
  if p_user is null then raise exception 'Indique el usuario.'; end if;

  -- Guard consistente con el resto del esquema: MFA + perfil limpio + operador + rol staff.
  if not app.is_staff(array['super_admin']) then
    raise exception 'Solo el Super Admin puede editar el perfil de otros usuarios.'
      using errcode = '42501';
  end if;

  select full_name, phone into v_old from public.profiles where id = p_user;
  if v_old is null then raise exception 'No existe el usuario %', p_user; end if;

  v_new_name  := coalesce(nullif(trim(p_full_name), ''), v_old.full_name);
  v_new_phone := coalesce(nullif(trim(p_phone),     ''), v_old.phone);

  if length(v_new_name) < 3 then raise exception 'El nombre completo debe tener al menos 3 caracteres.'; end if;
  if length(v_new_name) > 120 then raise exception 'El nombre completo no puede superar 120 caracteres.'; end if;
  if v_new_phone is not null and length(v_new_phone) > 40 then raise exception 'El telefono es demasiado largo.'; end if;

  update public.profiles
     set full_name = v_new_name,
         phone     = v_new_phone
   where id = p_user
     and (full_name is distinct from v_new_name or phone is distinct from v_new_phone);

  return jsonb_build_object('ok', true, 'id', p_user, 'full_name', v_new_name, 'phone', v_new_phone);
end
$$;

-- Permisos: preservamos los REVOKEs/GRANTs que ya aplicamos en 20261112_revoke_anon_from_new_rpcs.
revoke all on function public.admin_update_user_profile(uuid, text, text) from public;
revoke execute on function public.admin_update_user_profile(uuid, text, text) from anon;
grant execute on function public.admin_update_user_profile(uuid, text, text) to authenticated;
