-- PENDING PRODUCTION CHANGE — SOFA role alignment.
-- DO NOT EXECUTE in production until backup + restore gate is closed.
-- Prepared from live production inspection on 2026-10-19.

begin;

update public.roles set
  name = case code
    when 'super_admin' then 'Super Admin SOFA'
    when 'admin' then 'Administrador SOFA'
    when 'operations' then 'Operaciones SOFA'
    when 'billing' then 'Facturación y Radicación'
    when 'glosas' then 'Cobros, Conciliación y Glosas'
    when 'assistant' then 'Comercial / Onboarding'
    when 'auditor' then 'Auditor de Expedientes'
    when 'client' then 'Médico / Cliente'
    when 'capturer' then 'Secretaria / Capturista'
    when 'prospect' then 'Prospecto'
    else name end,
  description = case code
    when 'super_admin' then 'Gobierno completo del sistema, seguridad, usuarios, parámetros y datos críticos.'
    when 'admin' then 'Administración general de SOFA y supervisión de la operación; sin sustituir controles exclusivos del Super Admin.'
    when 'operations' then 'Recepción, retiro físico, validación, pre-radicación, calidad y puesta en marcha; sin pagos ni honorarios.'
    when 'billing' then 'Facturación y radicación de reclamaciones validadas; no registra pagos ARS ni gestiona glosas.'
    when 'glosas' then 'Registro y aplicación de pagos ARS, conciliación, glosas, reconsideraciones y recuperación.'
    when 'assistant' then 'Prospección, CRM, propuestas, onboarding comercial y seguimiento de clientes; no opera pagos ARS.'
    when 'auditor' then 'Auditoría de expedientes, trazabilidad y controles; preferentemente solo lectura.'
    when 'client' then 'Médico o dueño de la práctica: consulta su operación, reclamaciones, resultados y tareas del consultorio.'
    when 'capturer' then 'Secretaria o capturista: agenda, pacientes y captura de reclamaciones de médicos asignados.'
    when 'prospect' then 'Futuro cliente: acceso exclusivo al proceso de incorporación; no es miembro operativo de una organización cliente.'
    else description end;

delete from public.role_modules
where role_code in ('super_admin','admin','operations','billing','glosas','assistant','auditor','client','capturer','prospect');

insert into public.role_modules(role_code,module_code) values
('super_admin','dashboard'),('super_admin','trabajo_hoy'),('super_admin','nueva_cita'),('super_admin','captura_rapida'),('super_admin','reclamaciones'),('super_admin','retiros_fisicos'),('super_admin','radicacion'),('super_admin','agenda'),
('admin','dashboard'),('admin','trabajo_hoy'),('admin','nueva_cita'),('admin','captura_rapida'),('admin','reclamaciones'),('admin','retiros_fisicos'),('admin','radicacion'),('admin','agenda'),
('operations','dashboard'),('operations','trabajo_hoy'),('operations','captura_rapida'),('operations','reclamaciones'),('operations','retiros_fisicos'),('operations','radicacion'),
('billing','dashboard'),('billing','trabajo_hoy'),('billing','captura_rapida'),('billing','reclamaciones'),('billing','retiros_fisicos'),('billing','radicacion'),
('glosas','dashboard'),('glosas','trabajo_hoy'),('glosas','reclamaciones'),
('assistant','dashboard'),('assistant','trabajo_hoy'),
('auditor','dashboard'),('auditor','reclamaciones'),('auditor','retiros_fisicos'),('auditor','radicacion'),
('client','dashboard'),('client','nueva_cita'),('client','captura_rapida'),('client','reclamaciones'),('client','agenda'),
('capturer','dashboard'),('capturer','trabajo_hoy'),('capturer','nueva_cita'),('capturer','captura_rapida'),('capturer','reclamaciones'),('capturer','agenda')
on conflict do nothing;

-- Prospecto is an onboarding identity in lead_users; never an organization membership.
create or replace function public.admin_assign_role(
  p_actor uuid,
  p_user uuid,
  p_role text,
  p_org uuid default null,
  p_dry_run boolean default false
)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare
  v_op uuid;
  v_actor_role text;
  v_staff boolean;
  v_org uuid;
  v_kind text;
  v_target_super boolean;
begin
  select ou.organization_id,ou.role_code into v_op,v_actor_role
  from public.organization_users ou
  join public.organizations o on o.id=ou.organization_id and o.kind='operator'
  join public.profiles p on p.id=ou.user_id and p.is_active
  where ou.user_id=p_actor and ou.is_active and ou.role_code in ('super_admin','admin')
  order by (ou.role_code='super_admin') desc
  limit 1;

  if v_op is null then
    raise exception 'Solo el Super Admin o un Administrador SOFA pueden administrar usuarios'
      using errcode='42501';
  end if;

  select is_staff into v_staff from public.roles where code=p_role;
  if v_staff is null then
    raise exception 'Rol desconocido: %',p_role using errcode='22023';
  end if;

  if p_role='prospect' then
    raise exception 'Prospecto no se asigna desde Usuarios y roles. Use el flujo de incorporación.'
      using errcode='22023';
  end if;

  if not v_staff and p_role not in ('client','capturer') then
    raise exception 'Rol externo no permitido: %',p_role using errcode='22023';
  end if;

  if p_role='super_admin' and v_actor_role<>'super_admin' then
    raise exception 'Solo el Super Admin puede asignar el rol Super Admin'
      using errcode='42501';
  end if;

  if p_role='admin' and v_actor_role<>'super_admin' then
    raise exception 'Solo el Super Admin puede nombrar Administradores'
      using errcode='42501';
  end if;

  if v_staff then
    v_org:=v_op;
  else
    select kind into v_kind from public.organizations where id=p_org and operator_id=v_op;
    if v_kind is distinct from 'client' then
      raise exception 'Para Médico / Cliente o Secretaria / Capturista indique una organización cliente de SOFA'
        using errcode='22023';
    end if;
    v_org:=p_org;
    if app.clinical_mode(v_org)<>'desactivada' and v_actor_role<>'super_admin' then
      raise exception 'Este consultorio tiene la historia clínica activa: solo el Super Admin agrega Médicos o Secretarias.'
        using errcode='42501';
    end if;
  end if;

  if p_user is not null then
    if v_staff and exists(
      select 1 from public.organization_users
      where user_id=p_user and role_code in ('client','capturer') and is_active
    ) then
      raise exception 'Ese usuario ya es Médico o Secretaria de un cliente y no puede ser personal de SOFA. Cree una cuenta separada.'
        using errcode='42501';
    end if;

    if not v_staff and exists(
      select 1
      from public.organization_users ou
      join public.organizations o on o.id=ou.organization_id and o.kind='operator'
      where ou.user_id=p_user and ou.is_active
        and ou.role_code in ('super_admin','admin','operations','billing','glosas','assistant','auditor')
    ) then
      raise exception 'Ese usuario ya es personal de SOFA y no puede reutilizarse como Médico o Secretaria. Use una cuenta separada.'
        using errcode='42501';
    end if;

    if p_user=p_actor then
      raise exception 'No puede cambiar su propio rol' using errcode='22023';
    end if;

    select exists(
      select 1 from public.organization_users
      where user_id=p_user and role_code='super_admin' and is_active
    ) into v_target_super;

    if v_target_super and v_actor_role<>'super_admin' then
      raise exception 'Solo el Super Admin puede modificar a otro Super Admin'
        using errcode='42501';
    end if;
  end if;

  if p_dry_run or p_user is null then return 'ok'; end if;

  perform set_config('request.jwt.claims',json_build_object('sub',p_actor,'role','authenticated')::text,true);
  insert into public.profiles(id,full_name) values(p_user,'Usuario')
  on conflict(id) do update set is_active=true;

  insert into public.organization_users(organization_id,user_id,role_code,is_active)
  values(v_org,p_user,p_role,true)
  on conflict(organization_id,user_id)
  do update set role_code=excluded.role_code,is_active=true;

  perform set_config('request.jwt.claims','',true);
  return format('Rol %s asignado',(select name from public.roles where code=p_role));
end
$$;

-- Cobros/Glosas, no Facturación, registra pagos ARS.
drop policy if exists payments_insert on public.payments;
create policy payments_insert on public.payments
for insert to authenticated
with check(app.can(organization_id,array['super_admin','admin','glosas']));

drop policy if exists payment_allocations_insert on public.payment_allocations;
create policy payment_allocations_insert on public.payment_allocations
for insert to authenticated
with check(app.can(organization_id,array['super_admin','admin','glosas']));

rollback;
-- Replace ROLLBACK with COMMIT only after staging tests + backup/restore GO.
