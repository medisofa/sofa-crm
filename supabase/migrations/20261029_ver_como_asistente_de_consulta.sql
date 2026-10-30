-- 29/10/2026: extiende "Ver como" (support_view_start) al rol Asistente de consulta,
-- igual que ya funcionaba para Secretaria (capturer). El alcance de datos del asistente
-- (assistant_providers/assistant_org_ids, consultorio_access) ya pasaba por
-- app.view_as_user() desde que se creó el rol en la migración del flujo de pacientes, así
-- que esto solo retira la restricción explícita que bloqueaba target_user de rol 'asistente'.
--
-- Historia Clínica sigue sin verse a través de "Ver como" — ni como médico ni como
-- asistente autorizado — porque app.clinical_role() exige el rol real (role_for_org()),
-- no el usuario observado; eso es a propósito (HC es la categoría de dato más sensible y
-- "Ver como" es modo soporte de solo lectura, no un reemplazo de inicio de sesión) y se deja
-- así sin cambios.
create or replace function public.support_view_start(p_org uuid, p_target_user uuid default null)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare v_id uuid; v_kind text; v_role text;
begin
  if not app.is_staff(array['super_admin']) then
    raise exception 'Solo el Super Admin puede usar "Ver como"' using errcode = '42501';
  end if;
  select kind into v_kind from public.organizations where id = p_org;
  if v_kind is distinct from 'client' then raise exception 'Solo se puede "ver como" una organización cliente' using errcode = '22023'; end if;
  if p_target_user is not null then
    select role_code into v_role from public.organization_users
     where user_id = p_target_user and organization_id = p_org and is_active;
    if v_role is null or v_role not in ('client','capturer','asistente') then
      raise exception 'Esa persona no tiene un acceso activo de Médico, Secretaria o Asistente de consulta en este consultorio' using errcode = '22023';
    end if;
  end if;
  insert into public.support_view_sessions (actor_id, target_org_id, target_user_id) values (auth.uid(), p_org, p_target_user) returning id into v_id;
  return v_id;
end $function$;
NOTIFY pgrst,'reload schema';
