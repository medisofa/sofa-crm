-- SOFA · Corrige acceso delegado "abierto por defecto" para personal de staff.
--
-- Hallazgo: una cuenta de staff (organization_users en una organización
-- kind='operator', con rol marcado is_staff) que NUNCA tuvo una fila de
-- alcance en staff_client_access recibía acceso delegado a TODOS los
-- clientes (fail-open), en vez de a ninguno. Esto se reportó al ver que
-- una cuenta de Facturación y Radicación (rol "billing", no admin) veía
-- el selector de organización con clientes a los que no debía tener
-- acceso.
--
-- Corrección: se quita la rama "not exists (select 1 from
-- staff_client_access where user_id = ...)" de app.can_orgs() y
-- app.visible_org_ids(). Ahora, sin una fila explícita de alcance, un
-- usuario de staff no-admin no ve ningún cliente por la vía delegada
-- (fail-closed). super_admin/admin siguen viendo todos los clientes,
-- como antes. El acceso DIRECTO (fila propia del usuario en
-- organization_users para ese cliente) no se toca.
--
-- Nota operativa: al aplicar esto, cuentas de staff que dependían del
-- comportamiento anterior pierden el acceso delegado hasta que se les
-- cree su fila correspondiente en staff_client_access (o se les dé
-- acceso directo). Revisar qué cuentas quedaron afectadas:
--
--   select distinct ou.user_id
--     from public.organization_users ou
--     join public.organizations o on o.id = ou.organization_id and o.kind = 'operator'
--     join public.roles r on r.code = ou.role_code and r.is_staff
--    where ou.is_active and r.code not in ('super_admin','admin')
--      and not exists (select 1 from public.staff_client_access a where a.user_id = ou.user_id);

CREATE OR REPLACE FUNCTION app.can_orgs(p_roles text[] DEFAULT NULL::text[])
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return query
  with directo as (
    select ou.organization_id as org, ou.role_code as role_code
      from public.organization_users ou
      join public.profiles p on p.id = ou.user_id and p.is_active and not p.must_change_password
      join public.roles r0 on r0.code = ou.role_code
     where ou.user_id = auth.uid() and ou.is_active and (not r0.is_staff or app.mfa_ok())
  ), delegado as (
    select c.id as org, ou.role_code as role_code
      from public.organizations c
      join public.organization_users ou on ou.organization_id = c.operator_id and ou.user_id = auth.uid() and ou.is_active
      join public.roles r    on r.code = ou.role_code and r.is_staff
      join public.profiles p on p.id = ou.user_id and p.is_active and not p.must_change_password
     where c.kind = 'client' and app.mfa_ok()
       and ( ou.role_code in ('super_admin','admin')
             or exists (select 1 from public.staff_client_access a where a.user_id = auth.uid() and a.client_org_id = c.id) )
  )
  select d.org from directo d where p_roles is null or d.role_code = any (p_roles)
  union
  select g.org from delegado g
   where not exists (select 1 from directo d where d.org = g.org)
     and (p_roles is null or g.role_code = any (p_roles))
  ;
end $function$;

CREATE OR REPLACE FUNCTION app.visible_org_ids()
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return query
  select ou.organization_id
    from public.organization_users ou
    join public.profiles p on p.id = ou.user_id and p.is_active and not p.must_change_password
    join public.roles r0 on r0.code = ou.role_code
   where ou.user_id = (select auth.uid()) and ou.is_active and ou.role_code <> 'capturer' and (not r0.is_staff or (select app.mfa_ok()))
  union
  select c.id
    from public.organizations c
    join public.organization_users ou on ou.organization_id = c.operator_id and ou.user_id = (select auth.uid()) and ou.is_active
    join public.roles r    on r.code = ou.role_code and r.is_staff
    join public.profiles p on p.id = ou.user_id and p.is_active and not p.must_change_password
   where c.kind = 'client' and (select app.mfa_ok())
     and ( ou.role_code in ('super_admin','admin')
           or exists (select 1 from public.staff_client_access a where a.user_id = (select auth.uid()) and a.client_org_id = c.id) );
end $function$;
