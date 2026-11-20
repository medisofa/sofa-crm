-- 248_clinica_medico_propio.sql
-- Ya aplicado en producción (2026-11-20, mcp__Supabase__apply_migration «clinica_medico_propio_248»).
--
-- Opción 1, etapa 1a (decisión del 20/11/2026): en una organización con MÁS DE UN médico activo (clínica),
-- el usuario con rol «Médico / Cliente» ve y maneja solo lo suyo — agenda, citas, pacientes, cobros privados,
-- horario, bloqueos, tarifas privadas, cuadre de caja y sus secretarias. El director de la clínica conserva
-- la vista completa con la marca organization_users.sees_all_providers.
-- Organizaciones de un solo médico: sin cambios (la regla solo se activa con 2 o más médicos activos).
-- Etapas pendientes: 1b (reclamaciones, radicaciones, glosas, pagos ARS, documentos) y 1c (honorarios y
-- facturas SOFA, mensajes, BI, contador). Hasta cerrarlas, NO dar de alta clínicas con varios médicos.
--
-- Nota sobre la regla «copiar la función completa»: los 7 RPC de la sección 6 solo reciben una guarda al
-- inicio (misma línea en todos). Se aplica con un bloque idempotente sobre su definición vigente para no
-- duplicar aquí 7 cuerpos que no cambian en nada más. Las funciones de acceso (secciones 2-5) sí van completas.
-- Suite: 249_clinica_medico_propio_test.sql.

do $$ begin
  if to_regprocedure('app.appointment_access(uuid,uuid,boolean)') is null then raise exception 'Falta la 244'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'submissions' and column_name = 'provider_id') then
    raise exception 'submissions.provider_id no existe: revisar el filtro de pacientes';
  end if;
end $$;

-- 1. Marca del director de la clínica
alter table public.organization_users add column if not exists sees_all_providers boolean not null default false;
comment on column public.organization_users.sees_all_providers is
  'Solo aplica al rol client en organizaciones con varios médicos: true = director, ve a todos los médicos.';

-- 2. ¿El usuario actual es un médico limitado a lo suyo en esta organización?
create or replace function app.client_limited(p_org uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select coalesce(app.role_for_org(p_org), '') = 'client'
     and (select count(*) from public.providers p where p.organization_id = p_org and p.is_active) > 1
     and not exists (select 1 from public.organization_users ou
                      where ou.organization_id = p_org and ou.user_id = auth.uid() and ou.is_active and ou.sees_all_providers);
$$;

-- Verdadero salvo que el usuario sea médico limitado y el médico pedido no sea él. Médico inexistente: verdadero
-- (cada función conserva su propio mensaje «no existe»).
create or replace function app.client_provider_ok(p_provider uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select not exists (select 1 from public.providers p where p.id = p_provider
                       and app.client_limited(p.organization_id) and p.user_id is distinct from auth.uid());
$$;

-- 3. Acceso al consultorio (copiada de su versión vigente; el rama «client» exige client_provider_ok)
create or replace function app.consultorio_access(p_provider uuid, p_write boolean default false)
returns boolean language sql stable security definer set search_path to '' as $function$
  select exists (select 1 from public.providers p where p.id = p_provider and (
           app.can(p.organization_id, array['super_admin','admin','assistant','operations'])
        or (not p_write and app.can(p.organization_id, array['billing','glosas','auditor']))
        or (app.can(p.organization_id, array['client']) and app.client_provider_ok(p.id))
        or p.id in (select app.capturer_providers())
        or p.id in (select app.assistant_providers())));
$function$;

-- 4. Acceso a citas y permiso de agendar (copiadas de la 244; «client» sale del arreglo general)
create or replace function app.appointment_access(p_provider uuid, p_center uuid, p_write boolean default false)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (
    select 1 from public.providers p where p.id = p_provider and (
         app.can(p.organization_id, array['super_admin','admin','assistant','operations'])
      or (app.can(p.organization_id, array['client']) and app.client_provider_ok(p.id))
      or (not p_write and app.can(p.organization_id, array['billing','glosas','auditor']))
      or p.id in (select app.assistant_providers())
      or (p.id in (select app.capturer_providers())
          and exists (select 1 from public.capturer_scopes cs
                       where cs.user_id = app.view_as_user() and cs.provider_id = p.id
                         and (cs.center_id is null or cs.center_id = p_center)))
      or (p_center is not null and p_center in (select app.reception_centers())
          and exists (select 1 from public.provider_centers pc join public.health_centers hc on hc.id = pc.center_id
                       where pc.provider_id = p.id and pc.center_id = p_center and hc.organization_id = p.organization_id))
    ));
$$;

create or replace function app.appointment_can_book(p_provider uuid, p_center uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.providers p where p.id = p_provider and (
         app.can(p.organization_id, array['super_admin','admin','assistant','operations'])
      or (app.can(p.organization_id, array['client']) and app.client_provider_ok(p.id))
      or p.id in (select app.assistant_providers())
      or (p.id in (select app.capturer_providers())
          and exists (select 1 from public.capturer_scopes cs where cs.user_id = app.view_as_user() and cs.provider_id = p.id
                         and cs.can_book and (cs.center_id is null or cs.center_id = p_center)))
      or (p_center is not null and exists (select 1 from public.reception_scopes rs
                         where rs.user_id = app.view_as_user() and rs.center_id = p_center and rs.can_book and rs.is_active
                           and rs.center_id in (select app.reception_centers()))
          and app.appointment_access(p.id, p_center, true))));
$$;

-- 5. Pacientes: el médico limitado ve los pacientes que él atendió o agendó, o que él registró.
create or replace function app.patient_row_access(p_patient uuid, p_org uuid, p_created_by uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select app.patient_access(p_org) and (
       not app.client_limited(p_org)
    or p_created_by = auth.uid()
    or exists (select 1 from public.appointments a join public.providers p on p.id = a.provider_id
                where a.patient_id = p_patient and p.user_id = auth.uid())
    or exists (select 1 from public.service_lines sl join public.submissions s on s.id = sl.submission_id
                 join public.providers p on p.id = s.provider_id
                where sl.patient_id = p_patient and p.user_id = auth.uid()));
$$;
drop policy if exists patients_select on public.patients;
create policy patients_select on public.patients for select
  using (app.patient_row_access(id, organization_id, created_by));

-- Tablero de flujo de pacientes (copiada de su versión vigente): cada fila pasa por appointment_access,
-- así el médico de clínica ve solo los suyos y la secretaria solo los médicos y centros que tiene asignados.
create or replace function public.flow_board(p_org uuid, p_date date default current_date)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if not ( app.can(p_org, array['super_admin', 'admin', 'client'])
        or exists (select 1 from public.providers pr where pr.organization_id = p_org and pr.id in (select app.capturer_providers()))
        or exists (select 1 from public.providers pr where pr.organization_id = p_org and pr.id in (select app.assistant_providers())) ) then
    raise exception 'Sin acceso a la agenda de este consultorio.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'patient', a.patient_name, 'time', to_char(a.appointment_time, 'HH24:MI'),
      'doctor', pr.full_name, 'provider_id', a.provider_id, 'status', a.status, 'room', a.room, 'type', a.reason,
      'status_changed_at', a.status_changed_at, 'consult_started_at', a.consult_started_at,
      'billed', exists (select 1 from public.private_charges pc where pc.appointment_id = a.id))
      order by a.appointment_time nulls last, a.status_changed_at)
    from public.appointments a join public.providers pr on pr.id = a.provider_id
   where a.organization_id = p_org and a.appointment_date = p_date and a.status <> 'cancelada'
     and app.appointment_access(a.provider_id, a.center_id, false)), '[]'::jsonb);
end $function$;

-- reception_day: los médicos que se listan pasan por appointment_access (el médico de clínica que abre
-- la recepción ve solo su columna).
do $$ declare d text; begin
  d := pg_get_functiondef('public.reception_day(uuid,date)'::regprocedure);
  if position('appointment_access(p.id, p_center, false)' in d) = 0 then
    d := replace(d, 'where p.organization_id = v_org and p.is_active)', 'where p.organization_id = v_org and p.is_active and app.appointment_access(p.id, p_center, false))');
    execute d;
  end if;
end $$;

-- 6. Guarda al inicio de los RPC que reciben p_provider
do $$
declare f regprocedure; d text;
  guard constant text := E'\nbegin\n  if not app.client_provider_ok(p_provider) then\n    raise exception ''En una clínica cada médico maneja solo lo suyo. Pida al director de la clínica que haga este cambio.'' using errcode = ''42501'';\n  end if;\n';
begin
  foreach f in array array[
    'public.set_assistant_permissions(uuid,uuid,boolean,boolean)'::regprocedure,
    'public.set_assistant_permissions(uuid,uuid,boolean,boolean,boolean)'::regprocedure,
    'public.set_capturer_payments(uuid,uuid,boolean)'::regprocedure,
    'public.list_assistants(uuid)'::regprocedure,
    'public.set_assistant_center(uuid,uuid,uuid)'::regprocedure,
    'public.provider_schedule_set(uuid,uuid,jsonb)'::regprocedure,
    'public.provider_block_set(uuid,uuid,date,time,time,text,boolean)'::regprocedure,
    'public.create_private_tariff(uuid,uuid,numeric,date,text)'::regprocedure]
  loop
    d := pg_get_functiondef(f);
    if position('client_provider_ok' in d) = 0 then
      if position(E'\nbegin\n' in d) = 0 then raise exception 'No se encontró el inicio de %', f; end if;
      d := overlay(d placing guard from position(E'\nbegin\n' in d) for length(E'\nbegin\n'));
      execute d;
    end if;
  end loop;
  -- reopen_day: el cierre trae su médico
  d := pg_get_functiondef('public.reopen_day(uuid,text)'::regprocedure);
  if position('client_provider_ok' in d) = 0 then
    d := regexp_replace(d, '(reabren un día cuadrado'' using errcode = ''42501'';\s*end if;)',
                        E'\\1\n  if not app.client_provider_ok(c.provider_id) then raise exception ''En una clínica cada médico reabre solo su propio cuadre.'' using errcode = ''42501''; end if;');
    if position('client_provider_ok' in d) = 0 then raise exception 'No se pudo insertar la guarda en reopen_day'; end if;
    execute d;
  end if;
end $$;

-- 7. Marca del director: solo Super Admin / Administrador SOFA
create or replace function public.set_clinic_director(p_org uuid, p_user uuid, p_on boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not app.can(p_org, array['super_admin','admin']) then
    raise exception 'Solo la Administración de SOFA marca al director de una clínica.' using errcode = '42501';
  end if;
  update public.organization_users set sees_all_providers = coalesce(p_on, false)
   where organization_id = p_org and user_id = p_user and role_code = 'client';
  if not found then raise exception 'Ese usuario no es Médico/Cliente de esta organización.' using errcode = 'P0002'; end if;
end $$;
revoke execute on function public.set_clinic_director(uuid,uuid,boolean) from public, anon;
grant execute on function public.set_clinic_director(uuid,uuid,boolean) to authenticated;
