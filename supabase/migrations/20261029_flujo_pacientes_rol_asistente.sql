-- 29/10/2026: Flujo de pacientes (tablero Esperado/Esperando/En consulta/Atendido) + rol "Asistente de
-- consulta". El médico asigna asistentes igual que hoy asigna secretarias (capturer_scopes); el Asistente
-- puede mover el flujo de la agenda Y leer/escribir Historia Clínica (decisión explícita del cliente:
-- rompe el aislamiento médico-only que existía antes, documentado en clinical_require()). Aplicado en
-- producción (Supabase, proyecto bpwjhgpzhzhiocoxrvzq) y registrado aquí para el historial.

insert into public.roles(code, name, is_staff)
values ('asistente', 'Asistente de consulta', false)
on conflict (code) do nothing;

create table public.assistant_scopes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider_id uuid not null references public.providers(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  can_flow boolean not null default true,
  can_hc boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (user_id, provider_id)
);
alter table public.assistant_scopes enable row level security;
revoke all on public.assistant_scopes from public, anon, authenticated;
create policy assistant_scopes_select on public.assistant_scopes for select
  using (user_id = auth.uid() or organization_id in (select app.can_orgs(array['super_admin','admin','auditor','operations'])));
grant select on public.assistant_scopes to authenticated;

create function app.assistant_providers()
 returns setof uuid language plpgsql stable security definer set search_path = ''
as $$
begin
  return query
  select asg.provider_id from public.assistant_scopes asg
    join public.organization_users ou on ou.user_id = asg.user_id and ou.organization_id = asg.organization_id
      and ou.role_code = 'asistente' and ou.is_active
    join public.profiles p on p.id = asg.user_id and p.is_active
   where asg.user_id = app.view_as_user() and asg.can_flow;
end $$;
revoke all on function app.assistant_providers() from public, anon, authenticated;
grant execute on function app.assistant_providers() to authenticated;

create function app.assistant_org_ids()
 returns setof uuid language sql stable security definer set search_path = ''
as $$
  select distinct asg.organization_id from public.assistant_scopes asg where asg.user_id = app.view_as_user() and asg.provider_id in (select app.assistant_providers())
$$;
revoke all on function app.assistant_org_ids() from public, anon, authenticated;
grant execute on function app.assistant_org_ids() to authenticated;

-- consultorio_access: el Asistente mueve el flujo igual que la Secretaria
create or replace function app.consultorio_access(p_provider uuid, p_write boolean default false)
 returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.providers p where p.id = p_provider and (
           app.can(p.organization_id, array['super_admin','admin','assistant','operations'])
        or (not p_write and app.can(p.organization_id, array['billing','glosas','auditor']))
        or app.can(p.organization_id, array['client'])
        or p.id in (select app.capturer_providers())
        or p.id in (select app.assistant_providers())));
$$;

-- clinical_role: el Asistente autorizado (can_hc) entra como 'asistente', no 'emergencia' ni null
create or replace function app.clinical_role(p_org uuid)
 returns text language sql stable security definer set search_path = ''
as $$
  select case
    when p_org is null or auth.uid() is null then null
    when app.clinical_mode(p_org) = 'desactivada' then null
    when app.role_for_org(p_org) = 'client' then 'medico'
    when app.role_for_org(p_org) = 'asistente' and exists (
           select 1 from public.assistant_scopes a
            where a.user_id = auth.uid() and a.organization_id = p_org and a.can_hc) then 'asistente'
    when app.is_staff(array['super_admin']) and exists (
           select 1 from public.clinical_emergency_access e
            where e.user_id = auth.uid() and e.organization_id = p_org and e.expires_at > now()) then 'emergencia'
    else null end;
$$;

-- clinical_require: el Asistente también puede escribir (no solo el médico). Firma correcta
-- (p_org, p_write, p_patient) con defaults — un intento inicial con otro orden de parámetros creó
-- un overload huérfano con permisos abiertos a anon; se corrigió en el mismo despliegue.
create or replace function app.clinical_require(p_org uuid, p_write boolean default false, p_patient uuid default null::uuid)
 returns text language plpgsql stable security definer set search_path = ''
as $$
declare v_role text; v_set public.clinical_settings; v_status text;
begin
  if app.clinical_mode(p_org) = 'desactivada' then
    raise exception 'La historia clínica no está activada en este consultorio. El Super Admin la activa en Configuración › Historia clínica: control.' using errcode = '42501';
  end if;
  v_role := app.clinical_role(p_org);
  if v_role is null then
    raise exception 'Sin acceso a la historia clínica: solo el médico del consultorio o su asistente de consulta autorizado la consultan. La Secretaria y el personal de SOFA no ven datos clínicos.' using errcode = '42501';
  end if;
  if p_patient is not null and not app.clinical_patient_ok(p_org, p_patient) then
    raise exception 'Solo el médico que atiende a este paciente consulta su historia clínica. Si lo atiende usted, pida al Administrador de SOFA que enlace su usuario con su ficha de médico (Médicos › Enlazar usuario).' using errcode = '42501';
  end if;
  select * into v_set from public.clinical_settings where organization_id = p_org;
  if v_set.require_mfa and coalesce(auth.jwt()->>'aal', 'aal1') <> 'aal2' then
    raise exception 'Este consultorio exige verificación en dos pasos para la historia clínica. Actívela en Mi cuenta › Seguridad y vuelva a entrar.' using errcode = '42501';
  end if;
  if p_write then
    if v_role not in ('medico', 'asistente') then
      raise exception 'El acceso de emergencia es solo de lectura. Las notas las escribe el médico del consultorio o su asistente de consulta autorizado.' using errcode = '42501';
    end if;
    select status into v_status from public.organizations where id = p_org;
    if v_status not in ('activo', 'incorporacion') then
      raise exception 'El consultorio está % en SOFA: su historia clínica queda conservada en solo lectura. Para una copia use «Exportar».', v_status using errcode = '42501';
    end if;
  end if;
  return v_role;
end
$$;
revoke all on function app.clinical_require(uuid, boolean, uuid) from public, anon, authenticated;

-- visible_org_ids(): el Asistente, igual que la Secretaria, no tiene visibilidad general de la organización
-- (entra solo por consultorio_access/clinical_role, no por "soy miembro de este org"); preserva el fix de
-- "Ver como" del 28/10/2026 (PR #72).
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
   where ou.user_id = (select auth.uid()) and ou.is_active and ou.role_code not in ('capturer', 'asistente') and (not r0.is_staff or (select app.mfa_ok()))
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

-- providers/organizations: gemelas de providers_select_capturer/organizations_select_capturer
create policy providers_select_asistente on public.providers for select
  using (id in (select app.assistant_providers()));
create policy organizations_select_asistente on public.organizations for select
  using (id in (select app.assistant_org_ids()));

-- Flujo de pacientes: estado intermedio "en_consulta" + sala, columnas del tablero
alter table public.appointments add column if not exists room text;
alter table public.appointments add column if not exists consult_started_at timestamptz;
alter table public.appointments add column if not exists attended_by uuid references public.profiles(id);

create or replace function public.set_appointment_status(p_id uuid, p_status text, p_note text default null)
 returns void language plpgsql security definer set search_path = ''
as $$
declare a public.appointments;
begin
  select * into a from public.appointments where id = p_id for update;
  if not found then raise exception 'Cita no encontrada' using errcode = 'P0002'; end if;
  if not app.consultorio_access(a.provider_id, true) then raise exception 'Sin acceso a la agenda de este médico' using errcode = '42501'; end if;
  if p_status not in ('programada', 'confirmada', 'en_espera', 'en_consulta', 'no_asistio', 'cancelada') then
    raise exception '"Atendida" se registra al capturar la reclamación o el cobro del paciente' using errcode = '22023';
  end if;
  if a.status = 'atendida' then raise exception 'La cita ya fue atendida' using errcode = '23514'; end if;
  update public.appointments set status = p_status, status_changed_at = now(),
         notes = coalesce(nullif(trim(coalesce(p_note, '')), ''), notes)
   where id = p_id;
end $$;

create function public.call_appointment_in(p_id uuid, p_room text)
 returns void language plpgsql security definer set search_path = ''
as $$
declare a public.appointments;
begin
  select * into a from public.appointments where id = p_id for update;
  if not found then raise exception 'Cita no encontrada' using errcode = 'P0002'; end if;
  if not app.consultorio_access(a.provider_id, true) then raise exception 'Sin acceso a la agenda de este médico' using errcode = '42501'; end if;
  if a.status <> 'en_espera' then raise exception 'Solo se llama a consulta a un paciente en espera.' using errcode = '23514'; end if;
  if length(trim(coalesce(p_room, ''))) = 0 then raise exception 'Indique la sala o el consultorio.' using errcode = '22023'; end if;
  update public.appointments set status = 'en_consulta', status_changed_at = now(), consult_started_at = now(),
         attended_by = auth.uid(), room = left(trim(p_room), 40)
   where id = p_id;
end $$;
revoke all on function public.call_appointment_in(uuid, text) from public, anon;
grant execute on function public.call_appointment_in(uuid, text) to authenticated;

create function public.flow_board(p_org uuid, p_date date default current_date)
 returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if not ( app.can(p_org, array['super_admin', 'admin', 'client'])
        or exists (select 1 from public.providers pr where pr.organization_id = p_org and pr.id in (select app.capturer_providers()))
        or exists (select 1 from public.providers pr where pr.organization_id = p_org and pr.id in (select app.assistant_providers())) ) then
    raise exception 'Sin acceso a la agenda de este consultorio.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'patient', a.patient_name, 'time', to_char(a.appointment_time, 'HH24:MI'),
      'doctor', pr.full_name, 'provider_id', a.provider_id, 'status', a.status, 'room', a.room, 'type', a.reason,
      'status_changed_at', a.status_changed_at, 'consult_started_at', a.consult_started_at)
      order by a.appointment_time nulls last, a.status_changed_at)
    from public.appointments a join public.providers pr on pr.id = a.provider_id
   where a.organization_id = p_org and a.appointment_date = p_date and a.status <> 'cancelada'), '[]'::jsonb);
end $$;
revoke all on function public.flow_board(uuid, date) from public, anon;
grant execute on function public.flow_board(uuid, date) to authenticated;

-- Asignación de Asistentes por médico, igual patrón que list_assistants/set_assistant_permissions (secretarias)
create function public.list_consult_assistants(p_provider uuid)
 returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.providers where id = p_provider;
  if v_org is null then raise exception 'El médico no existe. Elija un médico de la lista.' using errcode = 'P0002'; end if;
  if not app.can(v_org, array['super_admin', 'admin', 'client']) then
    raise exception 'Solo el médico o el Administrador pueden ver los asistentes.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', ascp.user_id, 'name', pr.full_name, 'active', pr.is_active,
                                                      'can_flow', ascp.can_flow, 'can_hc', ascp.can_hc) order by pr.full_name)
                     from public.assistant_scopes ascp join public.profiles pr on pr.id = ascp.user_id
                    where ascp.provider_id = p_provider), '[]'::jsonb);
end $$;
revoke all on function public.list_consult_assistants(uuid) from public, anon;
grant execute on function public.list_consult_assistants(uuid) to authenticated;

create function public.set_consult_assistant_permissions(p_user uuid, p_provider uuid, p_can_flow boolean, p_can_hc boolean)
 returns void language plpgsql security definer set search_path = ''
as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.providers where id = p_provider;
  if v_org is null then raise exception 'El médico no existe. Elija un médico de la lista.' using errcode = 'P0002'; end if;
  if not app.can(v_org, array['super_admin', 'admin', 'client']) then
    raise exception 'Solo el médico o el Administrador pueden cambiar los permisos del asistente.' using errcode = '42501';
  end if;
  if p_can_flow is null or p_can_hc is null then raise exception 'Indique cada permiso como sí o no.' using errcode = '22023'; end if;
  update public.assistant_scopes set can_flow = p_can_flow, can_hc = p_can_hc
   where user_id = p_user and provider_id = p_provider;
  if not found then
    raise exception 'Ese asistente no está asignado a este médico. Asígnelo primero desde Usuarios.' using errcode = 'P0002';
  end if;
end $$;
revoke all on function public.set_consult_assistant_permissions(uuid, uuid, boolean, boolean) from public, anon;
grant execute on function public.set_consult_assistant_permissions(uuid, uuid, boolean, boolean) to authenticated;

create function public.set_assistant_scope(p_user uuid, p_providers uuid[])
 returns int language plpgsql security definer set search_path = ''
as $$
declare v_org uuid; v_n int;
begin
  select organization_id into v_org from public.organization_users where user_id = p_user and role_code = 'asistente' and is_active limit 1;
  if v_org is null then raise exception 'El usuario no tiene el rol Asistente de consulta' using errcode = '23514'; end if;
  if coalesce(app.role_for_org(v_org), '') not in ('super_admin', 'admin') then raise exception 'Solo un administrador asigna médicos a un asistente' using errcode = '42501'; end if;
  if exists (select 1 from unnest(coalesce(p_providers, '{}')) x(id) left join public.providers p on p.id = x.id where p.id is null or p.organization_id <> v_org) then
    raise exception 'Todos los médicos deben pertenecer al mismo cliente del asistente' using errcode = '23514';
  end if;
  delete from public.assistant_scopes where user_id = p_user and not (provider_id = any (coalesce(p_providers, '{}')));
  insert into public.assistant_scopes (user_id, provider_id, organization_id, created_by)
  select p_user, x.id, v_org, auth.uid() from unnest(coalesce(p_providers, '{}')) x(id) on conflict do nothing;
  select count(*) into v_n from public.assistant_scopes where user_id = p_user;
  return v_n;
end $$;
revoke all on function public.set_assistant_scope(uuid, uuid[]) from public, anon;
grant execute on function public.set_assistant_scope(uuid, uuid[]) to authenticated;

-- admin_assign_role: el rol Asistente entra en las mismas reglas que Médico/Secretaria
-- (bloqueo mutuo staff↔cliente, y el gate de historia clínica activa exige Super Admin)
create or replace function public.admin_assign_role(p_actor uuid, p_user uuid, p_role text, p_org uuid default null::uuid, p_dry_run boolean default false)
 returns text language plpgsql security definer set search_path = ''
as $$
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
    if p_role in ('client','capturer','asistente') and app.clinical_mode(v_org) <> 'desactivada' and v_actor_role <> 'super_admin' then
      raise exception 'Este consultorio tiene la historia clínica activa: solo el Super Admin agrega Médicos, Secretarias o Asistentes. Pídale al Super Admin que lo haga.' using errcode = '42501';
    end if;
  end if;
  if p_user is not null then
    if v_staff and exists (select 1 from public.organization_users where user_id = p_user and role_code in ('client','capturer','asistente') and is_active) then
      raise exception 'Ese usuario ya es Médico, Secretaria o Asistente de un cliente y no puede ser personal de SOFA. Use «Corregir asignación» desde su ficha si fue un error, o cree una cuenta nueva para el personal.' using errcode = '42501';
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
end
$$;

notify pgrst, 'reload schema';
