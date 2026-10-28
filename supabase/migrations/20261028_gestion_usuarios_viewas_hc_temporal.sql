-- SOFA · Tres mejoras de gestión de usuarios y acceso, aplicadas en producción
-- (Supabase, proyecto bpwjhgpzhzhiocoxrvzq) y registradas aquí para el historial.

-- =====================================================================
-- 1) "Revertir asignación" — NOTA (28/10/2026): el primer intento de esta
--    función agregaba un auto-cierre de la membresía del otro lado al
--    reasignar un rol. Eso contradecía la especificación ya aprobada en
--    docs/diseno/GESTION_ACCESOS_SOPORTE_NOVEDADES.md ("La función de
--    asignación habitual conserva la prohibición... No se quitó esa
--    protección para resolver este caso"), así que se revirtió: esta
--    función sigue BLOQUEANDO (como siempre) si el usuario ya tiene el
--    otro tipo de membresía activa, en vez de cerrarla sola. El caso que
--    motivó esto (una cuenta viendo 5 clientes a la vez) se resuelve con
--    la migración 3 de este archivo (admin_user_repair_audit /
--    admin_repair_user_access), que sí fue diseñada para eso con
--    auditoría y confirmación explícitas.
--    Definición actual en producción, tal cual quedó tras el revert:
-- =====================================================================
CREATE OR REPLACE FUNCTION public.admin_assign_role(p_actor uuid, p_user uuid, p_role text, p_org uuid DEFAULT NULL::uuid, p_dry_run boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_op uuid; v_actor_role text; v_staff boolean; v_org uuid; v_kind text; v_target_super boolean;
begin
  select ou.organization_id, ou.role_code into v_op, v_actor_role
    from public.organization_users ou join public.organizations o on o.id = ou.organization_id and o.kind = 'operator'
    join public.profiles p on p.id = ou.user_id and p.is_active
   where ou.user_id = p_actor and ou.is_active and ou.role_code in ('super_admin','admin')
   order by (ou.role_code = 'super_admin') desc limit 1;
  if v_op is null then raise exception 'Solo el Super Admin o un Administrador SOFA pueden invitar usuarios' using errcode = '42501'; end if;
  select is_staff into v_staff from public.roles where code = p_role;
  if v_staff is null then raise exception 'Rol desconocido: %', p_role using errcode = '22023'; end if;
  if p_role = 'super_admin' and v_actor_role <> 'super_admin' then
    raise exception 'Solo el Super Admin puede asignar el rol Super Admin' using errcode = '42501';
  end if;
  if p_role = 'admin' and v_actor_role <> 'super_admin' then
    raise exception 'Solo el Super Admin puede nombrar Administradores. Pídale al Super Admin que haga este cambio.' using errcode = '42501';
  end if;
  if v_staff then
    v_org := v_op;
  else
    select kind into v_kind from public.organizations where id = p_org and operator_id = v_op;
    if v_kind is distinct from 'client' then raise exception 'Para el rol Cliente / PSS indique una organización cliente de SOFA' using errcode = '22023'; end if;
    v_org := p_org;
    if p_role in ('client','capturer') and app.clinical_mode(v_org) <> 'desactivada' and v_actor_role <> 'super_admin' then
      raise exception 'Este consultorio tiene la historia clínica activa: solo el Super Admin agrega Médicos o Secretarias. Pídale al Super Admin que lo haga.' using errcode = '42501';
    end if;
  end if;
  if p_user is not null then
    if v_staff and exists (select 1 from public.organization_users where user_id = p_user and role_code in ('client','capturer') and is_active) then
      raise exception 'Ese usuario ya es Médico o Secretaria de un cliente y no puede ser personal de SOFA. Use «Corregir asignación» desde su ficha si fue un error, o cree una cuenta nueva para el personal.' using errcode = '42501';
    end if;
    if p_user = p_actor then raise exception 'No puede cambiar su propio rol' using errcode = '22023'; end if;
    select exists (select 1 from public.organization_users where user_id = p_user and role_code = 'super_admin' and is_active) into v_target_super;
    if v_target_super and v_actor_role <> 'super_admin' then
      raise exception 'Solo el Super Admin puede modificar a otro Super Admin' using errcode = '42501';
    end if;
  end if;
  if p_dry_run or p_user is null then return 'ok'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', p_actor, 'role', 'authenticated')::text, true);
  insert into public.profiles (id, full_name) values (p_user, 'Usuario') on conflict (id) do update set is_active = true;
  insert into public.organization_users (organization_id, user_id, role_code, is_active)
  values (v_org, p_user, p_role, true)
  on conflict (organization_id, user_id) do update set role_code = excluded.role_code, is_active = true;
  perform set_config('request.jwt.claims', '', true);
  return format('Rol %s asignado', (select name from public.roles where code = p_role));
end $function$;

-- =====================================================================
-- 2) "Ver como" (modo soporte, solo lectura): el Super Admin ve las
--    pantallas de un cliente para darle seguimiento, sin poder guardar.
--    Auditoría SOLO interna de SOFA, nunca visible al cliente.
-- =====================================================================
create table if not exists public.support_view_sessions (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id),
  target_org_id uuid not null references public.organizations(id),
  started_at timestamptz not null default now(),
  ended_at timestamptz
);
comment on table public.support_view_sessions is 'Auditoría interna de SOFA: cuándo un Super Admin vio la pantalla de un cliente en modo soporte. No se expone al cliente.';
alter table public.support_view_sessions enable row level security;
drop policy if exists support_view_sessions_all on public.support_view_sessions;
create policy support_view_sessions_all on public.support_view_sessions for all
  using (app.is_staff(array['super_admin']))
  with check (app.is_staff(array['super_admin']) and actor_id = auth.uid());

create or replace function public.support_view_start(p_org uuid)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare v_id uuid; v_kind text;
begin
  if not app.is_staff(array['super_admin']) then raise exception 'Solo el Super Admin puede usar "Ver como"' using errcode = '42501'; end if;
  select kind into v_kind from public.organizations where id = p_org;
  if v_kind is distinct from 'client' then raise exception 'Solo se puede "ver como" una organización cliente' using errcode = '22023'; end if;
  insert into public.support_view_sessions (actor_id, target_org_id) values (auth.uid(), p_org) returning id into v_id;
  return v_id;
end $function$;

create or replace function public.support_view_end(p_session uuid)
 returns void language sql security definer set search_path to ''
as $function$
  update public.support_view_sessions set ended_at = now() where id = p_session and actor_id = auth.uid() and ended_at is null;
$function$;

-- =====================================================================
-- 3) Historia clínica: acceso previa autorización del médico, con
--    duración fija (5/15/30/60 min, 15 por defecto). Reusa
--    clinical_emergency_access (ya existía, pero nada la llenaba salvo
--    el "acceso de emergencia" sin consentimiento). Todo queda en la
--    misma bitácora con cadena de hashes (clinical_access_log).
-- =====================================================================
create table if not exists public.clinical_access_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  requested_by uuid not null references public.profiles(id),
  duration_minutes int not null check (duration_minutes in (5, 15, 30, 60)),
  reason text not null,
  status text not null default 'pendiente' check (status in ('pendiente', 'aprobado', 'rechazado', 'caducado')),
  requested_at timestamptz not null default now(),
  responded_at timestamptz,
  responded_by uuid references public.profiles(id)
);
comment on table public.clinical_access_requests is 'Solicitudes del Super Admin para ver la historia clínica de un consultorio por tiempo limitado, sujetas a aprobación del médico.';
alter table public.clinical_access_requests enable row level security;

create or replace function public.clinical_access_request(p_org uuid, p_minutes int, p_reason text)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare v_id uuid; v_reason text;
begin
  if not app.is_staff(array['super_admin']) then raise exception 'Solo el Super Admin solicita acceso a la historia clínica.' using errcode = '42501'; end if;
  if app.clinical_mode(p_org) = 'desactivada' then raise exception 'La historia clínica no está activada en este consultorio.' using errcode = '42501'; end if;
  if p_minutes not in (5, 15, 30, 60) then raise exception 'Duración inválida.' using errcode = '22023'; end if;
  v_reason := left(coalesce(nullif(trim(p_reason), ''), 'Sin motivo indicado'), 300);
  update public.clinical_access_requests set status = 'caducado'
   where organization_id = p_org and requested_by = auth.uid() and status = 'pendiente';
  insert into public.clinical_access_requests (organization_id, requested_by, duration_minutes, reason)
  values (p_org, auth.uid(), p_minutes, v_reason) returning id into v_id;
  perform app.clinical_log(p_org, null, null, 'solicitud_acceso', format('%s min · %s', p_minutes, v_reason));
  return v_id;
end $function$;

create or replace function public.clinical_access_pending(p_org uuid)
 returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
begin
  if not coalesce(app.role_for_org(p_org) = 'client' or app.is_staff(array['super_admin']), false) then
    raise exception 'Solo el médico del consultorio o el Super Admin consultan estas solicitudes.' using errcode = '42501';
  end if;
  update public.clinical_access_requests set status = 'caducado'
   where organization_id = p_org and status = 'pendiente' and requested_at < now() - interval '30 minutes';
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id, 'requested_by', pr.full_name, 'duration_minutes', r.duration_minutes, 'reason', r.reason,
      'status', r.status, 'requested_at', r.requested_at,
      'expires_at', (select e.expires_at from public.clinical_emergency_access e
                      where e.user_id = r.requested_by and e.organization_id = r.organization_id
                        and e.granted_at >= r.requested_at order by e.granted_at desc limit 1))
    order by r.requested_at desc)
    from (select * from public.clinical_access_requests where organization_id = p_org order by requested_at desc limit 20) r
    left join public.profiles pr on pr.id = r.requested_by), '[]'::jsonb);
end $function$;

create or replace function public.clinical_access_respond(p_request uuid, p_approve boolean)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare v_org uuid; v_user uuid; v_minutes int; v_status text;
begin
  select organization_id, requested_by, duration_minutes, status into v_org, v_user, v_minutes, v_status
    from public.clinical_access_requests where id = p_request;
  if v_org is null then raise exception 'La solicitud no existe.' using errcode = '22023'; end if;
  if app.role_for_org(v_org) <> 'client' then raise exception 'Solo el médico del consultorio aprueba o rechaza esta solicitud.' using errcode = '42501'; end if;
  if v_status <> 'pendiente' then raise exception 'Esta solicitud ya no está pendiente.' using errcode = '22023'; end if;
  update public.clinical_access_requests
     set status = case when p_approve then 'aprobado' else 'rechazado' end, responded_at = now(), responded_by = auth.uid()
   where id = p_request;
  if p_approve then
    insert into public.clinical_emergency_access (user_id, organization_id, reason, expires_at)
    values (v_user, v_org, 'Autorizado por el médico (solicitud ' || p_request || ')', now() + make_interval(mins => v_minutes));
  end if;
  perform app.clinical_log(v_org, null, null, case when p_approve then 'autorizacion_acceso' else 'rechazo_acceso' end,
    format('%s min, por %s', v_minutes, (select full_name from public.profiles where id = auth.uid())));
end $function$;
