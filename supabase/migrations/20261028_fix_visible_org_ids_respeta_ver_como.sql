-- 28/10/2026: "Ver como" (modo soporte) nunca cambia la sesión real de auth.uid() por diseño
-- (documentado), pero app.visible_org_ids() —de la que dependen 41 políticas RLS: providers,
-- organizations, glosas, payments, claim_*, documents, etc.— seguía devolviendo TODAS las
-- organizaciones reales del Super Admin mientras estaba "viendo como" un cliente específico.
-- Resultado: el admin veía datos de sus 5 clientes (ej. el selector de "Médico" en Agenda)
-- en vez de quedar acotado al único cliente que está viendo, rompiendo la garantía de
-- "modo soporte, solo lectura DE ESE CLIENTE" que support_view_sessions existe para dar.
-- Encontrado por el usuario probando la app en producción. Aplicado en producción
-- (Supabase, proyecto bpwjhgpzhzhiocoxrvzq) y registrado aquí para el historial.

create or replace function app.visible_org_ids()
 returns setof uuid
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_view_org uuid;
begin
  select s.target_org_id into v_view_org
    from public.support_view_sessions s
   where s.actor_id = auth.uid() and s.ended_at is null
   order by s.started_at desc limit 1;
  if v_view_org is not null then
    return query select v_view_org;
    return;
  end if;

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
