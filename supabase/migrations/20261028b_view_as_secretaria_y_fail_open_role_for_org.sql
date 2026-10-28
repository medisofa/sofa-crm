-- SOFA · Dos cosas aplicadas ya en producción (Supabase bpwjhgpzhzhiocoxrvzq),
-- registradas aquí para el historial.
--
-- 1) Mismo hueco "abierto por defecto" de can_orgs()/visible_org_ids() (migración
--    20261028_fix_staff_client_access_fail_open.sql) encontrado también en
--    app.role_for_org() -base de app.can(), app.clinical_role(), app.patient_access()
--    y de la mayoría de los permisos sobre datos reales, no solo el menú- y en
--    app.email_user_orgs() / app.inbox_user_sees(). En los tres, un miembro de
--    staff sin ninguna fila en staff_client_access veía TODOS los clientes en vez
--    de ninguno. Se quita esa rama en las tres funciones.
--
-- 2) "Ver como secretaria": a diferencia del médico (alcance por organización,
--    ya visible para el Super Admin), el de la secretaria depende de
--    capturer_scopes.user_id = su propio usuario. Se agrega app.view_as_user():
--    devuelve el usuario observado si hay una sesión de "Ver como" activa y
--    dirigida a una persona concreta (support_view_sessions.target_user_id),
--    si no el usuario real. Se usa en capturer_providers/capturer_org_ids/
--    capturer_can/patient_access -los únicos puntos que dependían de
--    capturer_scopes; se confirmó que ninguna política RLS la referencia
--    directo, todas pasan por estas funciones-.

-- ===== 1) role_for_org, email_user_orgs, inbox_user_sees =====
CREATE OR REPLACE FUNCTION app.role_for_org(p_org uuid)
 RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
declare v_uid uuid := auth.uid(); v_r text;
begin
  select ou.role_code into v_r
    from public.organization_users ou
    join public.profiles p on p.id = ou.user_id and p.is_active and not p.must_change_password
    join public.roles r0 on r0.code = ou.role_code
   where ou.organization_id = p_org and ou.user_id = v_uid and ou.is_active and (not r0.is_staff or app.mfa_ok());
  if v_r is not null then return v_r; end if;
  select ou.role_code into v_r
    from public.organizations c
    join public.organization_users ou on ou.organization_id = c.operator_id and ou.user_id = v_uid and ou.is_active
    join public.roles r    on r.code = ou.role_code and r.is_staff
    join public.profiles p on p.id = ou.user_id and p.is_active and not p.must_change_password
   where c.id = p_org and c.kind = 'client' and app.mfa_ok()
     and ( ou.role_code in ('super_admin','admin')
           or exists (select 1 from public.staff_client_access a where a.user_id = v_uid and a.client_org_id = c.id) );
  return v_r;
end $function$;

CREATE OR REPLACE FUNCTION app.email_user_orgs(p_user uuid, p_scope text)
 RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select ou.organization_id
    from public.organization_users ou
    join public.organizations o on o.id = ou.organization_id and o.kind = 'client' and o.status <> 'inactivo'
    join public.profiles p on p.id = ou.user_id and p.is_active
   where ou.user_id = p_user and ou.is_active and ou.role_code = 'client'
  union
  select c.id
    from public.organizations c
    join public.organization_users ou on ou.organization_id = c.operator_id and ou.user_id = p_user and ou.is_active
         and ou.role_code in ('super_admin', 'admin', 'operations', 'billing', 'glosas')
    join public.profiles p on p.id = ou.user_id and p.is_active
   where p_scope = 'equipo' and c.kind = 'client' and c.status <> 'inactivo'
     and (ou.role_code in ('super_admin', 'admin')
          or exists (select 1 from public.staff_client_access a where a.user_id = p_user and a.client_org_id = c.id));
$function$;

CREATE OR REPLACE FUNCTION app.inbox_user_sees(p_user uuid, p_org uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select exists (select 1 from public.staff_client_access a where a.user_id = p_user and a.client_org_id = p_org)
      or exists (select 1 from public.organization_users ou join public.organizations o on o.id = ou.organization_id and o.kind = 'operator'
                  where ou.user_id = p_user and ou.is_active and ou.role_code in ('super_admin','admin'));
$function$;

-- ===== 2) view_as_user() y sustitución de alcance de secretaria =====
alter table public.support_view_sessions add column if not exists target_user_id uuid references public.profiles(id);

DROP FUNCTION IF EXISTS public.support_view_start(uuid);
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
    if v_role is null or v_role not in ('client','capturer') then
      raise exception 'Esa persona no tiene un acceso activo de Médico o Secretaria en este consultorio' using errcode = '22023';
    end if;
  end if;
  insert into public.support_view_sessions (actor_id, target_org_id, target_user_id) values (auth.uid(), p_org, p_target_user) returning id into v_id;
  return v_id;
end $function$;

create or replace function app.view_as_user()
 returns uuid language sql stable security definer set search_path to ''
as $function$
  select coalesce(
    (select s.target_user_id from public.support_view_sessions s
      where s.actor_id = auth.uid() and s.ended_at is null and s.target_user_id is not null
      order by s.started_at desc limit 1),
    auth.uid());
$function$;

CREATE OR REPLACE FUNCTION app.capturer_providers()
 RETURNS SETOF uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
begin
  return query
  select cs.provider_id from public.capturer_scopes cs
    join public.organization_users ou on ou.user_id = cs.user_id and ou.organization_id = cs.organization_id and ou.role_code = 'capturer' and ou.is_active
    join public.profiles p on p.id = cs.user_id and p.is_active
   where cs.user_id = app.view_as_user();
end $function$;

CREATE OR REPLACE FUNCTION app.capturer_org_ids()
 RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select distinct cs.organization_id from public.capturer_scopes cs where cs.user_id = app.view_as_user() and cs.provider_id in (select app.capturer_providers())
$function$;

CREATE OR REPLACE FUNCTION app.capturer_can(p_provider uuid, p_perm text)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select case when not app.is_capturer_only(p_provider) then true
         else exists (select 1 from public.capturer_scopes cs
                       where cs.user_id = app.view_as_user() and cs.provider_id = p_provider
                         and case p_perm when 'book' then cs.can_book when 'whatsapp' then cs.can_whatsapp else false end) end;
$function$;

CREATE OR REPLACE FUNCTION app.patient_access(p_org uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select app.can(p_org, array['super_admin','admin','client'])
      or exists (select 1 from public.capturer_scopes cs where cs.user_id = app.view_as_user() and cs.organization_id = p_org);
$function$;
