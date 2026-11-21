-- 264 · Hospitalización como episodio: aviso de ingreso, tramos por área (Emergencia, Hospitalización/planta,
-- Cirugía, UCI) con autorización de la ARS por tramo, traslados y egreso.
-- Ya aplicado en producción (21/11/2026).
--
-- Regla de negocio: mientras el paciente siga ingresado (sin fecha de alta) el reporte es un AVISO de servicio
-- prestado, no una reclamación terminada. Por eso:
--   · El reporte no puede pasar de «borrador» a «enviado» sin fecha de alta (disparador, vale para el médico,
--     el personal de SOFA y cualquier ruta futura).
--   · Al poner la fecha de alta, el tramo abierto se cierra en esa fecha.
-- Quién mueve el episodio (traslado, egreso): el médico del reporte, su secretaria (capturer_scopes sobre ese
-- médico) y el personal de SOFA (super_admin, admin, operations, billing) con acceso a ese consultorio.
-- Nunca en modo soporte. Los tramos no se leen ni escriben desde la API: solo por estas funciones.
-- Ajusta la suite 207 (HS-13 y HS-18): el reporte de prueba ahora lleva fecha de alta.
do $$ begin
  if to_regclass('public.hospital_reports') is null or to_regclass('public.capturer_scopes') is null
     or to_regprocedure('app.hospital_my_provider()') is null or to_regprocedure('app.is_staff(text[])') is null then
    raise exception '264 requiere el reporte de hospitalización (206) y las secretarias por médico.';
  end if;
end $$;

create table if not exists public.hospital_stays (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.hospital_reports(id) on delete cascade,
  area text not null check (area in ('emergencia','hospitalizacion','cirugia','uci')),
  started_on date not null,
  ended_on date,
  auth_number text check (auth_number is null or length(btrim(auth_number)) between 1 and 40),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (ended_on is null or ended_on >= started_on)
);
create unique index if not exists hospital_stays_one_open on public.hospital_stays(report_id) where ended_on is null;
create index if not exists hospital_stays_report on public.hospital_stays(report_id, started_on);
alter table public.hospital_stays enable row level security;
revoke all on public.hospital_stays from anon, authenticated;

alter table public.hospital_reports add column if not exists notified_at timestamptz;
alter table public.hospital_reports add column if not exists discharged_by uuid;

-- Guardas del episodio
create or replace function app.hospital_episode_guard() returns trigger
 language plpgsql set search_path to '' as $f$
begin
  if new.status = 'enviado' and old.status = 'borrador' and new.discharge_date is null then
    raise exception 'El paciente sigue ingresado: registre el egreso (fecha de alta) antes de enviar el reporte para reclamar.' using errcode = '22023';
  end if;
  if new.discharge_date is not null and old.discharge_date is distinct from new.discharge_date then
    if exists (select 1 from public.hospital_stays s where s.report_id = new.id and s.started_on > new.discharge_date) then
      raise exception 'La fecha de alta es anterior a un traslado registrado. Revise las fechas de los tramos.' using errcode = '22023';
    end if;
    update public.hospital_stays set ended_on = new.discharge_date where report_id = new.id and ended_on is null;
  end if;
  return new;
end $f$;
drop trigger if exists hospital_reports_episode_guard on public.hospital_reports;
create trigger hospital_reports_episode_guard before update on public.hospital_reports
  for each row execute function app.hospital_episode_guard();

-- ¿Puede el usuario actual mover este episodio?
create or replace function app.hospital_episode_can_edit(p_report uuid) returns boolean
 language sql stable security definer set search_path to '' as $f$
  select exists (
    select 1 from public.hospital_reports r
      join public.providers p on p.id = r.provider_id
      join public.health_centers hc on hc.id = r.center_id
     where r.id = p_report and auth.uid() is not null
       and not exists (select 1 from public.support_view_active())
       and (
         ((p.user_id = auth.uid() or app.hospital_my_provider() = p.id) and coalesce(app.role_for_org(p.organization_id),'') = 'client')
         or (coalesce(app.role_for_org(p.organization_id),'') = 'capturer'
             and exists (select 1 from public.capturer_scopes cs where cs.user_id = auth.uid() and cs.provider_id = p.id))
         or (app.is_staff(array['super_admin','admin','operations','billing'])
             and app.can(hc.organization_id, array['super_admin','admin','operations','billing']))
       ));
$f$;

create or replace function app.hospital_episode_json(p_report uuid) returns jsonb
 language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object(
    'id', r.id, 'patient_name', r.patient_name, 'medico', pr.full_name, 'centro', hc.name,
    'ars', (select name from public.ars where id = r.ars_id),
    'admission_date', r.admission_date, 'discharge_date', r.discharge_date, 'status', r.status, 'notified_at', r.notified_at,
    'estado', case when r.status <> 'borrador' then r.status when r.discharge_date is not null then 'egresado'
                   when r.notified_at is not null then 'ingresado' else 'sin_notificar' end,
    'dias', case when r.admission_date is null then null else coalesce(r.discharge_date, current_date) - r.admission_date end,
    'area_actual', (select s.area from public.hospital_stays s where s.report_id = r.id and s.ended_on is null),
    'sin_autorizacion', exists (select 1 from public.hospital_stays s where s.report_id = r.id and s.area in ('hospitalizacion','cirugia','uci') and s.auth_number is null),
    'ultimo_movimiento', greatest(r.updated_at, (select max(created_at) from public.hospital_stays s where s.report_id = r.id),
                                  (select max(created_at) from public.hospital_report_lines l where l.report_id = r.id)),
    'total', r.total,
    'tramos', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'area', s.area, 'started_on', s.started_on, 'ended_on', s.ended_on,
                 'auth_number', s.auth_number, 'dias', coalesce(s.ended_on, current_date) - s.started_on) order by s.started_on, s.created_at)
               from public.hospital_stays s where s.report_id = r.id), '[]'::jsonb),
    'puede_mover', app.hospital_episode_can_edit(r.id) and r.status = 'borrador')
  from public.hospital_reports r join public.providers pr on pr.id = r.provider_id join public.health_centers hc on hc.id = r.center_id
  where r.id = p_report;
$f$;

create or replace function app.hospital_episode_lock(p_report uuid) returns public.hospital_reports
 language plpgsql security definer set search_path to '' as $f$
declare r public.hospital_reports;
begin
  if auth.uid() is null then raise exception 'Inicia sesión.' using errcode = '42501'; end if;
  select * into r from public.hospital_reports where id = p_report for update;
  if r.id is null or not app.hospital_episode_can_edit(p_report) then
    raise exception 'Reporte no encontrado o sin permiso: lo mueven el médico, su secretaria o el personal de SOFA.' using errcode = '42501';
  end if;
  if r.status <> 'borrador' then raise exception 'Este reporte ya se envió para reclamar: los tramos ya no cambian. Pida a SOFA que lo reabra si hace falta.' using errcode = '42501'; end if;
  return r;
end $f$;

create or replace function app.hospital_area_ok(p_area text) returns void language plpgsql immutable set search_path to '' as $f$
begin
  if p_area is null or p_area not in ('emergencia','hospitalizacion','cirugia','uci') then
    raise exception 'Elija el área: Emergencia, Hospitalización (planta), Cirugía o UCI.' using errcode = '22023';
  end if;
end $f$;

-- 1) Aviso de ingreso: abre el primer tramo en la fecha de ingreso.
create or replace function public.hospital_episode_notify(p_report uuid, p_area text, p_auth text default null) returns jsonb
 language plpgsql security definer set search_path to '' as $f$
declare r public.hospital_reports;
begin
  r := app.hospital_episode_lock(p_report);
  perform app.hospital_area_ok(p_area);
  if r.admission_date is null then raise exception 'Ponga la fecha de ingreso en el reporte antes de avisar el ingreso.' using errcode = '22023'; end if;
  if r.admission_date > current_date then raise exception 'La fecha de ingreso no puede ser futura.' using errcode = '22023'; end if;
  if exists (select 1 from public.hospital_stays where report_id = p_report) then
    raise exception 'Este ingreso ya fue avisado. Para cambiar de área use «Trasladar».' using errcode = '22023';
  end if;
  insert into public.hospital_stays (report_id, area, started_on, ended_on, auth_number)
    values (p_report, p_area, r.admission_date, r.discharge_date, nullif(btrim(coalesce(p_auth,'')), ''));
  update public.hospital_reports set notified_at = now() where id = p_report;
  return app.hospital_episode_json(p_report);
end $f$;

-- 2) Traslado: cierra el tramo abierto y abre uno nuevo en la misma fecha.
create or replace function public.hospital_episode_transfer(p_report uuid, p_area text, p_on date, p_auth text default null) returns jsonb
 language plpgsql security definer set search_path to '' as $f$
declare r public.hospital_reports; s public.hospital_stays;
begin
  r := app.hospital_episode_lock(p_report);
  perform app.hospital_area_ok(p_area);
  if r.discharge_date is not null then raise exception 'El paciente ya tiene fecha de alta: no se traslada.' using errcode = '22023'; end if;
  select * into s from public.hospital_stays where report_id = p_report and ended_on is null for update;
  if s.id is null then raise exception 'Primero avise el ingreso (área de entrada); luego registre los traslados.' using errcode = '22023'; end if;
  if p_on is null or p_on < s.started_on or p_on > current_date then
    raise exception 'La fecha del traslado debe estar entre el % y hoy.', to_char(s.started_on, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  if s.area = p_area then raise exception 'El paciente ya está en esa área.' using errcode = '22023'; end if;
  update public.hospital_stays set ended_on = p_on where id = s.id;
  insert into public.hospital_stays (report_id, area, started_on, auth_number) values (p_report, p_area, p_on, nullif(btrim(coalesce(p_auth,'')), ''));
  update public.hospital_reports set updated_at = now() where id = p_report;
  return app.hospital_episode_json(p_report);
end $f$;

-- 3) Autorización de un tramo (llega después del traslado).
create or replace function public.hospital_episode_set_auth(p_stay uuid, p_auth text) returns jsonb
 language plpgsql security definer set search_path to '' as $f$
declare v_report uuid;
begin
  select report_id into v_report from public.hospital_stays where id = p_stay;
  if v_report is null then raise exception 'Tramo no encontrado. Recargue la página.' using errcode = 'P0002'; end if;
  perform app.hospital_episode_lock(v_report);
  if length(btrim(coalesce(p_auth,''))) > 40 then raise exception 'El número de autorización tiene más de 40 caracteres. Revíselo.' using errcode = '22023'; end if;
  update public.hospital_stays set auth_number = nullif(btrim(coalesce(p_auth,'')), '') where id = p_stay;
  return app.hospital_episode_json(v_report);
end $f$;

-- 4) Egreso: pone la fecha de alta (el disparador cierra el tramo abierto).
create or replace function public.hospital_episode_discharge(p_report uuid, p_on date) returns jsonb
 language plpgsql security definer set search_path to '' as $f$
declare r public.hospital_reports;
begin
  r := app.hospital_episode_lock(p_report);
  if r.discharge_date is not null then raise exception 'El egreso ya está registrado (%).', to_char(r.discharge_date, 'DD/MM/YYYY') using errcode = '22023'; end if;
  if p_on is null or p_on > current_date then raise exception 'Indique la fecha de egreso (hoy o antes).' using errcode = '22023'; end if;
  if r.admission_date is not null and p_on < r.admission_date then raise exception 'La fecha de egreso no puede ser anterior al ingreso.' using errcode = '22023'; end if;
  update public.hospital_reports set discharge_date = p_on, discharged_by = auth.uid() where id = p_report;
  return app.hospital_episode_json(p_report);
end $f$;

create or replace function public.hospital_episode_get(p_report uuid) returns jsonb
 language plpgsql stable security definer set search_path to '' as $f$
begin
  if auth.uid() is null then raise exception 'Inicia sesión.' using errcode = '42501'; end if;
  if not app.hospital_episode_can_edit(p_report) then
    raise exception 'Reporte no encontrado o sin permiso.' using errcode = '42501';
  end if;
  return app.hospital_episode_json(p_report);
end $f$;

-- 5) Pacientes ingresados y egresados por enviar, según quién pregunta.
create or replace function public.hospital_episodes_open() returns jsonb
 language plpgsql stable security definer set search_path to '' as $f$
begin
  if auth.uid() is null then raise exception 'Inicia sesión.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(app.hospital_episode_json(r.id) order by r.admission_date, r.id)
    from public.hospital_reports r
   where r.status = 'borrador' and r.notified_at is not null and app.hospital_episode_can_edit(r.id)), '[]'::jsonb);
end $f$;

revoke all on function public.hospital_episode_notify(uuid,text,text), public.hospital_episode_transfer(uuid,text,date,text),
  public.hospital_episode_set_auth(uuid,text), public.hospital_episode_discharge(uuid,date), public.hospital_episode_get(uuid),
  public.hospital_episodes_open() from public, anon;
grant execute on function public.hospital_episode_notify(uuid,text,text), public.hospital_episode_transfer(uuid,text,date,text),
  public.hospital_episode_set_auth(uuid,text), public.hospital_episode_discharge(uuid,date), public.hospital_episode_get(uuid),
  public.hospital_episodes_open() to authenticated;
revoke all on function app.hospital_episode_can_edit(uuid), app.hospital_episode_json(uuid), app.hospital_episode_lock(uuid) from public, anon, authenticated;

-- Suite 207: el reporte que se envía ahora lleva fecha de alta (regla de este episodio).
do $$ declare d text;
begin
  if to_regprocedure('app.qa_run_tests_hospital()') is null then return; end if;
  d := pg_get_functiondef('app.qa_run_tests_hospital()'::regprocedure);
  d := replace(d, $a$public.hospital_report_save(v_hc1, 'Paciente QA', '001-0000000-1', null, current_date-3, null, 'ingreso de prueba')$a$,
                  $b$public.hospital_report_save(v_hc1, 'Paciente QA', '001-0000000-1', null, current_date-3, current_date-1, 'ingreso de prueba')$b$);
  d := replace(d, $a$public.hospital_report_save(v_hc2, 'Paciente Vacío')$a$, $b$public.hospital_report_save(v_hc2, 'Paciente Vacío', null, null, current_date-1, current_date)$b$);
  execute d;
end $$;
