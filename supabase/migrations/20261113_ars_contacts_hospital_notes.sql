-- SOFA · Contactos de ARS y notas de reporte de hospitalización.
-- Ya aplicado en producción (2026-11-13, con SQL directo: NO figura en el historial de migraciones de
-- Supabase; quedó registrado solo en app.schema_migrations como «228», número que en este repositorio
-- corresponde a otro archivo, 228_demo_isolation_automations.sql).
--
-- Estado de lo que crea:
--   · ars_contacts / ars_contact_log y sus funciones: vigentes, sin pantalla todavía, tablas vacías.
--   · hospital_report_notes y hospital_note_*: DUPLICAN la bitácora hospital_report_log (5.35.1), que ya
--     tiene pantalla. Están vacías y se retirarán junto con la pantalla de contactos de ARS.
-- Se conserva tal como se aplicó, para que el repositorio refleje lo que hay en la base.
-- =====================================================================================================

-- =====================================================================
-- 228 · Bitácora de seguimiento de hospitalización + Contactos de ARS
-- Requiere: 226 aplicada (hospital_reports, app.hospital_my_provider,
--           app.role_for_org, app.visible_org_ids, app.is_staff, app.audit).
-- Idempotente: se puede aplicar dos veces seguidas.
--
-- A) Notas de seguimiento por hospitalización (hospital_report_notes)
--    · Dos tipos: 'interna' (solo equipo SOFA) y 'visible_medico'.
--    · Escriben: super_admin, admin, operations, billing, glosas y el
--      Médico dueño del reporte (sus notas son siempre 'visible_medico').
--    · Lee el equipo (incluido auditor). El Médico solo lee las visibles.
--    · Editar y borrar: solo super_admin y admin. Todo queda en audit_log.
--
-- B) Contactos de ARS (ars_contacts) y bitácora de contactos
--    (ars_contact_log). SOLO personal de SOFA; el Médico y la
--    Secretaria no ven nada de esto. Auditor solo lee.
-- =====================================================================

do $$
begin
  if not exists (select 1 from app.schema_migrations where version = '226') then
    raise exception 'Falta la migración 226. Aplícala y vuelve a correr la 228.';
  end if;
  if to_regclass('public.hospital_reports') is null
     or to_regprocedure('app.hospital_my_provider()') is null
     or to_regprocedure('app.role_for_org(uuid)') is null
     or to_regprocedure('app.is_staff(text[])') is null then
    raise exception 'Faltan objetos de Hospitalización o de permisos. Revisa que la 226 esté completa.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- A) NOTAS DE HOSPITALIZACIÓN
-- ---------------------------------------------------------------------
create table if not exists public.hospital_report_notes (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.hospital_reports(id) on delete cascade,
  visibility  text not null default 'interna'
              check (visibility in ('interna','visible_medico')),
  body        text not null check (length(btrim(body)) between 1 and 4000),
  author_id   uuid default auth.uid(),
  author_name text,
  author_role text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  edited_at   timestamptz,
  edited_by   uuid
);
create index if not exists hospital_report_notes_report_idx
  on public.hospital_report_notes (report_id, created_at);

alter table public.hospital_report_notes enable row level security;
revoke all on public.hospital_report_notes from public, anon, authenticated;

drop trigger if exists hospital_report_notes_updated_at on public.hospital_report_notes;
create trigger hospital_report_notes_updated_at before update on public.hospital_report_notes
  for each row execute function app.set_updated_at();
drop trigger if exists hospital_report_notes_audit on public.hospital_report_notes;
create trigger hospital_report_notes_audit after insert or update or delete on public.hospital_report_notes
  for each row execute function app.audit();

-- Qué puede hacer quien llama sobre las notas de un reporte.
-- Devuelve: 'medico' | 'equipo' | 'lectura'. Lanza error si no tiene acceso.
create or replace function app.hospital_note_access(p_report uuid)
returns text
language plpgsql stable security definer set search_path = ''
as $$
declare r public.hospital_reports; v_org uuid; v_role text;
begin
  if auth.uid() is null or not app.is_active_user() then
    raise exception 'Inicia sesión para ver la bitácora.' using errcode = '42501';
  end if;
  select * into r from public.hospital_reports where id = p_report;
  if r.id is null then
    raise exception 'Reporte de hospitalización no encontrado. Actualiza la lista y vuelve a abrirlo.' using errcode = 'P0002';
  end if;
  if r.provider_id is not distinct from app.hospital_my_provider() then
    return 'medico';
  end if;
  select hc.organization_id into v_org from public.health_centers hc where hc.id = r.center_id;
  if v_org is not null
     and exists (select 1 from app.visible_org_ids() v(id) where v.id = v_org)
     and r.status in ('enviado','cerrado') then
    v_role := app.role_for_org(v_org);
    if v_role in ('super_admin','admin','operations','billing','glosas') then return 'equipo'; end if;
    if v_role = 'auditor' then return 'lectura'; end if;
  end if;
  raise exception 'No tienes acceso a la bitácora de este reporte. Si debería ser tuyo, avisa al Administrador.' using errcode = '42501';
end $$;
revoke all on function app.hospital_note_access(uuid) from public, anon, authenticated;

create or replace function public.hospital_note_list(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_acc text := app.hospital_note_access(p_report); v_org uuid; v_manage boolean := false;
begin
  if v_acc = 'equipo' then
    select hc.organization_id into v_org from public.hospital_reports r
      join public.health_centers hc on hc.id = r.center_id where r.id = p_report;
    v_manage := coalesce(app.role_for_org(v_org) in ('super_admin','admin'), false);
  end if;
  return jsonb_build_object(
    'acceso', v_acc,
    'puede_agregar', v_acc in ('medico','equipo'),
    'puede_administrar', v_manage,
    'notas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', n.id, 'visibility', n.visibility, 'body', n.body,
               'author_name', n.author_name, 'author_role', n.author_role,
               'created_at', n.created_at, 'edited_at', n.edited_at,
               'es_mia', n.author_id is not distinct from auth.uid()
             ) order by n.created_at, n.id)
        from public.hospital_report_notes n
       where n.report_id = p_report
         and (v_acc <> 'medico' or n.visibility = 'visible_medico')
    ), '[]'::jsonb));
end $$;

create or replace function public.hospital_note_add(p_report uuid, p_body text, p_visibility text default 'interna')
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_acc text := app.hospital_note_access(p_report); v_vis text; v_org uuid; v_role text; v_id uuid;
begin
  if v_acc = 'lectura' then
    raise exception 'El Auditor solo puede leer la bitácora. Pide a un Administrador que registre la observación.' using errcode = '42501';
  end if;
  if p_body is null or length(btrim(p_body)) = 0 then
    raise exception 'Escribe la observación antes de guardarla.' using errcode = '22023';
  end if;
  if length(btrim(p_body)) > 4000 then
    raise exception 'La observación pasa de 4000 caracteres. Resúmela o divídela en dos notas.' using errcode = '22023';
  end if;
  if coalesce(p_visibility,'interna') not in ('interna','visible_medico') then
    raise exception 'El tipo de nota debe ser «interna» o «visible_medico».' using errcode = '22023';
  end if;
  if v_acc = 'medico' then
    v_vis := 'visible_medico'; v_role := 'client';
  else
    v_vis := coalesce(p_visibility,'interna');
    select hc.organization_id into v_org from public.hospital_reports r
      join public.health_centers hc on hc.id = r.center_id where r.id = p_report;
    v_role := app.role_for_org(v_org);
  end if;
  insert into public.hospital_report_notes (report_id, visibility, body, author_id, author_name, author_role)
  values (p_report, v_vis, btrim(p_body), auth.uid(),
          (select pr.full_name from public.profiles pr where pr.id = auth.uid()), v_role)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'visibility', v_vis);
end $$;

create or replace function public.hospital_note_edit(p_note uuid, p_body text, p_visibility text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare n public.hospital_report_notes; v_org uuid;
begin
  select * into n from public.hospital_report_notes where id = p_note;
  if n.id is null then
    raise exception 'La nota ya no existe. Actualiza la bitácora.' using errcode = 'P0002';
  end if;
  perform app.hospital_note_access(n.report_id);
  select hc.organization_id into v_org from public.hospital_reports r
    join public.health_centers hc on hc.id = r.center_id where r.id = n.report_id;
  if coalesce(app.role_for_org(v_org) not in ('super_admin','admin'), true) then
    raise exception 'Solo el Administrador puede corregir notas. Agrega una nota nueva que aclare el error.' using errcode = '42501';
  end if;
  if p_body is null or length(btrim(p_body)) = 0 or length(btrim(p_body)) > 4000 then
    raise exception 'La observación debe tener entre 1 y 4000 caracteres.' using errcode = '22023';
  end if;
  if p_visibility is not null and p_visibility not in ('interna','visible_medico') then
    raise exception 'El tipo de nota debe ser «interna» o «visible_medico».' using errcode = '22023';
  end if;
  update public.hospital_report_notes
     set body = btrim(p_body), visibility = coalesce(p_visibility, visibility),
         edited_at = now(), edited_by = auth.uid()
   where id = p_note;
  return jsonb_build_object('id', p_note);
end $$;

create or replace function public.hospital_note_delete(p_note uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare n public.hospital_report_notes; v_org uuid;
begin
  select * into n from public.hospital_report_notes where id = p_note;
  if n.id is null then
    raise exception 'La nota ya no existe. Actualiza la bitácora.' using errcode = 'P0002';
  end if;
  perform app.hospital_note_access(n.report_id);
  select hc.organization_id into v_org from public.hospital_reports r
    join public.health_centers hc on hc.id = r.center_id where r.id = n.report_id;
  if coalesce(app.role_for_org(v_org) not in ('super_admin','admin'), true) then
    raise exception 'Solo el Administrador puede borrar notas.' using errcode = '42501';
  end if;
  delete from public.hospital_report_notes where id = p_note;
  return jsonb_build_object('id', p_note, 'borrada', true);
end $$;

-- ---------------------------------------------------------------------
-- B) CONTACTOS DE ARS Y BITÁCORA DE CONTACTOS (solo personal de SOFA)
-- ---------------------------------------------------------------------
create table if not exists public.ars_contacts (
  id         uuid primary key default gen_random_uuid(),
  ars_id     uuid not null references public.ars(id) on delete cascade,
  area       text not null default 'otro'
             check (area in ('radicacion','glosas','autorizaciones','pagos','servicio_cliente','habilitacion','otro')),
  name       text not null check (length(btrim(name)) between 2 and 160),
  job_title  text check (job_title is null or length(job_title) <= 120),
  phone      text check (phone is null or length(btrim(phone)) <= 40),
  email      text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  notes      text check (notes is null or length(notes) <= 1000),
  is_active  boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ars_contacts_medio_chk check (phone is not null or email is not null)
);
create index if not exists ars_contacts_ars_idx on public.ars_contacts (ars_id, is_active);

create table if not exists public.ars_contact_log (
  id               uuid primary key default gen_random_uuid(),
  ars_id           uuid not null references public.ars(id) on delete cascade,
  contact_id       uuid references public.ars_contacts(id) on delete set null,
  hospital_report_id uuid references public.hospital_reports(id) on delete set null,
  case_ref         text check (case_ref is null or length(case_ref) <= 120),
  channel          text not null check (channel in ('llamada','correo','whatsapp','portal','presencial','otro')),
  direction        text not null default 'saliente' check (direction in ('saliente','entrante')),
  subject          text not null check (length(btrim(subject)) between 2 and 160),
  summary          text not null check (length(btrim(summary)) between 2 and 4000),
  outcome          text not null default 'informativo'
                   check (outcome in ('resuelto','en_espera','sin_respuesta','escalado','informativo')),
  next_action      text check (next_action is null or length(next_action) <= 300),
  next_action_date date,
  status           text not null default 'cerrado' check (status in ('abierto','cerrado')),
  occurred_at      timestamptz not null default now(),
  author_id        uuid default auth.uid(),
  author_name      text,
  author_role      text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  closed_at        timestamptz,
  closed_by        uuid,
  constraint ars_contact_log_seguimiento_chk check (next_action_date is null or status = 'abierto' or closed_at is not null)
);
create index if not exists ars_contact_log_ars_idx  on public.ars_contact_log (ars_id, occurred_at desc);
create index if not exists ars_contact_log_open_idx on public.ars_contact_log (next_action_date) where status = 'abierto';
create index if not exists ars_contact_log_rep_idx  on public.ars_contact_log (hospital_report_id) where hospital_report_id is not null;

alter table public.ars_contacts    enable row level security;
alter table public.ars_contact_log enable row level security;
revoke all on public.ars_contacts    from public, anon, authenticated;
revoke all on public.ars_contact_log from public, anon, authenticated;

drop trigger if exists ars_contacts_updated_at on public.ars_contacts;
create trigger ars_contacts_updated_at before update on public.ars_contacts for each row execute function app.set_updated_at();
drop trigger if exists ars_contacts_audit on public.ars_contacts;
create trigger ars_contacts_audit after insert or update or delete on public.ars_contacts for each row execute function app.audit();
drop trigger if exists ars_contact_log_updated_at on public.ars_contact_log;
create trigger ars_contact_log_updated_at before update on public.ars_contact_log for each row execute function app.set_updated_at();
drop trigger if exists ars_contact_log_audit on public.ars_contact_log;
create trigger ars_contact_log_audit after insert or update or delete on public.ars_contact_log for each row execute function app.audit();

-- Quién puede: p_modo 'leer' (todo el personal SOFA), 'escribir' (sin Auditor), 'admin' (super_admin y admin).
create or replace function app.ars_staff_require(p_modo text)
returns text
language plpgsql stable security definer set search_path = ''
as $$
declare v_role text;
begin
  if auth.uid() is null or not app.is_active_user() then
    raise exception 'Inicia sesión para ver los contactos de ARS.' using errcode = '42501';
  end if;
  select ou.role_code into v_role
    from public.organization_users ou
    join public.organizations o on o.id = ou.organization_id and o.kind = 'operator'
    join public.roles r on r.code = ou.role_code and r.is_staff
   where ou.user_id = auth.uid() and ou.is_active and app.is_staff(array[ou.role_code])
   order by (ou.role_code = 'super_admin') desc, (ou.role_code = 'admin') desc
   limit 1;
  if v_role is null then
    raise exception 'Los contactos de ARS son solo para el personal de SOFA.' using errcode = '42501';
  end if;
  if p_modo = 'escribir' and v_role = 'auditor' then
    raise exception 'El Auditor solo puede leer los contactos y la bitácora de ARS.' using errcode = '42501';
  end if;
  if p_modo = 'admin' and v_role not in ('super_admin','admin') then
    raise exception 'Esta acción es solo del Administrador.' using errcode = '42501';
  end if;
  return v_role;
end $$;
revoke all on function app.ars_staff_require(text) from public, anon, authenticated;

create or replace function public.ars_contact_list(p_ars uuid default null, p_only_active boolean default true)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_role text := app.ars_staff_require('leer');
begin
  return jsonb_build_object(
    'puede_escribir', v_role <> 'auditor',
    'puede_administrar', v_role in ('super_admin','admin'),
    'contactos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'ars_id', c.ars_id, 'ars', a.name, 'area', c.area, 'name', c.name,
               'job_title', c.job_title, 'phone', c.phone, 'email', c.email, 'notes', c.notes,
               'is_active', c.is_active, 'updated_at', c.updated_at
             ) order by a.name, c.is_active desc, c.area, c.name)
        from public.ars_contacts c join public.ars a on a.id = c.ars_id
       where (p_ars is null or c.ars_id = p_ars)
         and (not coalesce(p_only_active, true) or c.is_active)
    ), '[]'::jsonb));
end $$;

create or replace function public.ars_contact_save(
  p_ars uuid, p_area text, p_name text, p_job_title text default null,
  p_phone text default null, p_email text default null, p_notes text default null, p_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  perform app.ars_staff_require('escribir');
  if not exists (select 1 from public.ars where id = p_ars) then
    raise exception 'Elige una ARS de la lista.' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_phone,'')),'') is null and nullif(btrim(coalesce(p_email,'')),'') is null then
    raise exception 'Escribe al menos un teléfono o un correo para este contacto.' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_email,'')),'') is not null and btrim(p_email) !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'El correo «%» no tiene un formato válido. Revisa que lleve @ y dominio.', btrim(p_email) using errcode = '22023';
  end if;
  if p_name is null or length(btrim(p_name)) < 2 then
    raise exception 'Escribe el nombre del contacto (mínimo 2 letras).' using errcode = '22023';
  end if;
  if coalesce(p_area,'otro') not in ('radicacion','glosas','autorizaciones','pagos','servicio_cliente','habilitacion','otro') then
    raise exception 'El área del contacto no es válida. Elige una de la lista.' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.ars_contacts (ars_id, area, name, job_title, phone, email, notes)
    values (p_ars, coalesce(p_area,'otro'), btrim(p_name), nullif(btrim(coalesce(p_job_title,'')),''),
            nullif(btrim(coalesce(p_phone,'')),''), nullif(btrim(coalesce(p_email,'')),''), nullif(btrim(coalesce(p_notes,'')),''))
    returning id into v_id;
  else
    update public.ars_contacts
       set ars_id = p_ars, area = coalesce(p_area, area), name = btrim(p_name),
           job_title = nullif(btrim(coalesce(p_job_title,'')),''),
           phone = nullif(btrim(coalesce(p_phone,'')),''), email = nullif(btrim(coalesce(p_email,'')),''),
           notes = nullif(btrim(coalesce(p_notes,'')),'')
     where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'El contacto ya no existe. Actualiza la lista.' using errcode = 'P0002';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.ars_contact_set_active(p_id uuid, p_active boolean)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  perform app.ars_staff_require('escribir');
  update public.ars_contacts set is_active = coalesce(p_active, true) where id = p_id;
  if not found then
    raise exception 'El contacto ya no existe. Actualiza la lista.' using errcode = 'P0002';
  end if;
  return jsonb_build_object('id', p_id, 'is_active', coalesce(p_active, true));
end $$;

create or replace function public.ars_contact_log_add(
  p_ars uuid, p_channel text, p_direction text, p_subject text, p_summary text,
  p_outcome text default 'informativo', p_contact uuid default null, p_report uuid default null,
  p_case_ref text default null, p_next_action text default null, p_next_action_date date default null,
  p_occurred_at timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_role text := app.ars_staff_require('escribir'); v_id uuid; v_org uuid;
begin
  if not exists (select 1 from public.ars where id = p_ars) then
    raise exception 'Elige una ARS de la lista.' using errcode = '22023';
  end if;
  if p_contact is not null and not exists (select 1 from public.ars_contacts where id = p_contact and ars_id = p_ars) then
    raise exception 'El contacto elegido no pertenece a esa ARS.' using errcode = '22023';
  end if;
  if p_report is not null then
    select hc.organization_id into v_org from public.hospital_reports r
      join public.health_centers hc on hc.id = r.center_id where r.id = p_report;
    if v_org is null or not exists (select 1 from app.visible_org_ids() v(id) where v.id = v_org) then
      raise exception 'No tienes acceso a la hospitalización que intentas enlazar.' using errcode = '42501';
    end if;
  end if;
  if p_next_action_date is not null and p_next_action_date < current_date - 1 then
    raise exception 'La fecha de seguimiento ya pasó. Elige hoy o una fecha futura.' using errcode = '22023';
  end if;
  insert into public.ars_contact_log (ars_id, contact_id, hospital_report_id, case_ref, channel, direction,
         subject, summary, outcome, next_action, next_action_date, status, occurred_at, author_name, author_role)
  values (p_ars, p_contact, p_report, nullif(btrim(coalesce(p_case_ref,'')),''), p_channel, coalesce(p_direction,'saliente'),
          btrim(p_subject), btrim(p_summary), coalesce(p_outcome,'informativo'),
          nullif(btrim(coalesce(p_next_action,'')),''), p_next_action_date,
          case when p_next_action_date is not null then 'abierto' else 'cerrado' end,
          coalesce(p_occurred_at, now()),
          (select pr.full_name from public.profiles pr where pr.id = auth.uid()), v_role)
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.ars_contact_log_list(
  p_ars uuid default null, p_report uuid default null, p_status text default null, p_limit integer default 100)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_role text := app.ars_staff_require('leer');
begin
  return jsonb_build_object(
    'puede_escribir', v_role <> 'auditor',
    'puede_administrar', v_role in ('super_admin','admin'),
    'entradas', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.occurred_at desc, x.id) from (
        select l.id, l.ars_id, a.name ars, l.contact_id, c.name contacto, l.hospital_report_id,
               l.case_ref, l.channel, l.direction, l.subject, l.summary, l.outcome,
               l.next_action, l.next_action_date, l.status, l.occurred_at, l.author_name, l.author_role,
               l.closed_at, (l.status = 'abierto' and l.next_action_date < current_date) as vencida
          from public.ars_contact_log l
          join public.ars a on a.id = l.ars_id
          left join public.ars_contacts c on c.id = l.contact_id
         where (p_ars is null or l.ars_id = p_ars)
           and (p_report is null or l.hospital_report_id = p_report)
           and (p_status is null or l.status = p_status)
         order by l.occurred_at desc, l.id
         limit greatest(1, least(coalesce(p_limit,100), 500))
      ) x), '[]'::jsonb));
end $$;

create or replace function public.ars_contact_log_close(p_id uuid, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  perform app.ars_staff_require('escribir');
  update public.ars_contact_log
     set status = 'cerrado', closed_at = now(), closed_by = auth.uid(),
         summary = case when nullif(btrim(coalesce(p_note,'')),'') is null then summary
                        else left(summary || E'\n[Cierre] ' || btrim(p_note), 4000) end
   where id = p_id and status = 'abierto';
  if not found then
    raise exception 'Ese seguimiento no existe o ya estaba cerrado. Actualiza la lista.' using errcode = 'P0002';
  end if;
  return jsonb_build_object('id', p_id, 'status', 'cerrado');
end $$;

create or replace function public.ars_contact_log_delete(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  perform app.ars_staff_require('admin');
  delete from public.ars_contact_log where id = p_id;
  if not found then
    raise exception 'La entrada ya no existe. Actualiza la lista.' using errcode = 'P0002';
  end if;
  return jsonb_build_object('id', p_id, 'borrada', true);
end $$;

create or replace function public.ars_contacts_overview()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_role text := app.ars_staff_require('leer');
begin
  return jsonb_build_object(
    'puede_escribir', v_role <> 'auditor',
    'ars', coalesce((
      select jsonb_agg(jsonb_build_object(
               'ars_id', a.id, 'ars', a.name,
               'contactos', (select count(*) from public.ars_contacts c where c.ars_id = a.id and c.is_active),
               'ultimo_contacto', (select max(l.occurred_at) from public.ars_contact_log l where l.ars_id = a.id),
               'seguimientos_abiertos', (select count(*) from public.ars_contact_log l where l.ars_id = a.id and l.status = 'abierto'),
               'seguimientos_vencidos', (select count(*) from public.ars_contact_log l where l.ars_id = a.id and l.status = 'abierto' and l.next_action_date < current_date)
             ) order by a.name)
        from public.ars a where a.is_active), '[]'::jsonb));
end $$;

-- Permisos de ejecución: solo usuarios con sesión (cada función valida su rol por dentro).
do $$
declare f text;
begin
  foreach f in array array[
    'public.hospital_note_list(uuid)','public.hospital_note_add(uuid,text,text)',
    'public.hospital_note_edit(uuid,text,text)','public.hospital_note_delete(uuid)',
    'public.ars_contact_list(uuid,boolean)',
    'public.ars_contact_save(uuid,text,text,text,text,text,text,uuid)',
    'public.ars_contact_set_active(uuid,boolean)',
    'public.ars_contact_log_add(uuid,text,text,text,text,text,uuid,uuid,text,text,date,timestamptz)',
    'public.ars_contact_log_list(uuid,uuid,text,integer)','public.ars_contact_log_close(uuid,text)',
    'public.ars_contact_log_delete(uuid)','public.ars_contacts_overview()']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

insert into app.schema_migrations (version, report)
select '228', jsonb_build_object('nombre','bitacora_hospitalizacion_contactos_ars','frontend','pendiente')
 where not exists (select 1 from app.schema_migrations where version = '228');
