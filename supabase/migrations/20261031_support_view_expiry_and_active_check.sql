-- Ya aplicado en producción (31/10/2026).
--
-- Causa real de "el Súper Admin solo ve 1 cliente" (no era un bug de RLS ni de MFA, ya descartados
-- con pruebas directas): la cuenta medicasofa@gmail.com ("Ing. Gustavo Espaillat") entró en modo
-- "Ver como Consultorio Demo SOFA" (soporte, solo lectura) el 30/10/2026 8:40am y esa sesión nunca
-- se cerró (pestaña cerrada sin pulsar «Salir»). Como ese estado vive en support_view_sessions y no
-- solo en el navegador, dejó a la cuenta viendo un solo consultorio en CUALQUIER dispositivo —
-- incluida una ventana de incógnito nueva, sin nada en caché— sin ningún aviso en pantalla, porque
-- el aviso («👁 Viendo como…») solo se dibujaba si la propia pestaña había iniciado ese modo.
-- Se cerró manualmente esa sesión (update support_view_sessions set ended_at=now() where id=
-- 'd1294edc-5dbc-4890-b171-48692c4a0162') y aquí quedan las dos correcciones de fondo:
--
-- 1) app.visible_org_ids() ahora vence el modo "Ver como" a las 4 horas, así una sesión que nadie
--    cerró se autocorrige sola en vez de dejar a alguien "atrapado" indefinidamente.
create or replace function app.visible_org_ids()
returns setof uuid
language sql
stable
security definer
set search_path to ''
as $function$
  with override as (
    select s.target_org_id as id
      from public.support_view_sessions s
     where s.actor_id = auth.uid() and s.ended_at is null and s.started_at > now() - interval '4 hours'
     order by s.started_at desc limit 1
  )
  select id from override
  union all
  select ou.organization_id
    from public.organization_users ou
    join public.profiles p on p.id = ou.user_id and p.is_active and not p.must_change_password
    join public.roles r0 on r0.code = ou.role_code
   where not exists (select 1 from override)
     and ou.user_id = auth.uid() and ou.is_active and ou.role_code not in ('capturer', 'asistente')
     and (not r0.is_staff or app.mfa_ok())
  union
  select c.id
    from public.organizations c
    join public.organization_users ou on ou.organization_id = c.operator_id and ou.user_id = auth.uid() and ou.is_active
    join public.roles r    on r.code = ou.role_code and r.is_staff
    join public.profiles p on p.id = ou.user_id and p.is_active and not p.must_change_password
   where not exists (select 1 from override)
     and c.kind = 'client' and app.mfa_ok()
     and ( ou.role_code in ('super_admin','admin')
           or exists (select 1 from public.staff_client_access a where a.user_id = auth.uid() and a.client_org_id = c.id) );
$function$;

-- 2) public.support_view_active() deja que la pantalla pregunte "¿tengo una sesión de soporte
--    abierta?" al entrar, sin importar en qué dispositivo se abrió — así el aviso «Viendo como…»
--    con su botón «Salir» siempre se ve, en vez de quedar invisible tras recargar o entrar de nuevo.
create or replace function public.support_view_active()
returns table (session_id uuid, org_id uuid, org_name text, target_user_id uuid, target_name text, role_code text, started_at timestamptz)
language sql
stable
security definer
set search_path to ''
as $function$
  select s.id, s.target_org_id, o.legal_name, s.target_user_id, pr.full_name,
    coalesce((select ou.role_code from public.organization_users ou
                where ou.organization_id = s.target_org_id and ou.user_id = coalesce(s.target_user_id, s.actor_id) and ou.is_active
                  and ou.role_code in ('client','capturer','asistente') limit 1), 'client'),
    s.started_at
    from public.support_view_sessions s
    join public.organizations o on o.id = s.target_org_id
    left join public.profiles pr on pr.id = s.target_user_id
   where s.actor_id = auth.uid() and s.ended_at is null and s.started_at > now() - interval '4 hours'
   order by s.started_at desc limit 1;
$function$;

grant execute on function public.support_view_active() to authenticated;
