-- SOFA · 5.35.1 · Bitácora de hospitalización: procesos / hallazgos / observaciones.
-- Append-only (protegida por trigger). Cada entrada tiene visibilidad explícita:
--   shared_with_admin=false → solo el autor y el staff SOFA.
--   shared_with_admin=true  → además, el super_admin y el admin del cliente (organization_id del center).
-- Las acciones de escritura y lectura pasan por RPCs SECURITY DEFINER para enforzar reglas uniformes.
--
-- Pendiente de aplicar en producción — el pop-up de confirmación del MCP no se respondió a tiempo.
-- Aplicar manualmente: copiar este archivo y correrlo contra el proyecto bpwjhgpzhzhiocoxrvzq.

create table if not exists public.hospital_report_log (
  id bigserial primary key,
  report_id uuid not null references public.hospital_reports(id) on delete cascade,
  organization_id uuid not null,                       -- desnormalizada para RLS rápida
  kind text not null check (kind in ('proceso','hallazgo','observacion')),
  content text not null check (length(content) between 1 and 4000),
  shared_with_admin boolean not null default false,
  author_id uuid not null,
  author_name_cached text,
  created_at timestamptz not null default now()
);

create index if not exists idx_hospital_report_log_report on public.hospital_report_log(report_id, created_at desc);
create index if not exists idx_hospital_report_log_org on public.hospital_report_log(organization_id, created_at desc);

alter table public.hospital_report_log enable row level security;

-- Trigger append-only: ni UPDATE ni DELETE.
create or replace function app.hospital_report_log_protect()
returns trigger language plpgsql set search_path to '' as $$
begin
  if tg_op in ('UPDATE','DELETE') then
    raise exception 'La bitácora de hospitalización no se modifica (append-only).' using errcode = '42501';
  end if;
  return null;
end $$;

drop trigger if exists hospital_report_log_protect on public.hospital_report_log;
create trigger hospital_report_log_protect
  before update or delete on public.hospital_report_log
  for each row execute function app.hospital_report_log_protect();

-- Policies: SELECT (autor, staff, admin del cliente si shared). INSERT solo con auth.uid()=author_id.
drop policy if exists hospital_report_log_select on public.hospital_report_log;
create policy hospital_report_log_select on public.hospital_report_log
  for select using (
    auth.uid() = author_id
    or app.is_staff()
    or (
      shared_with_admin = true
      and exists (
        select 1 from public.organization_users ou
        where ou.user_id = auth.uid()
          and ou.organization_id = hospital_report_log.organization_id
          and ou.is_active
          and ou.role_code in ('super_admin','admin','client')
      )
    )
  );

drop policy if exists hospital_report_log_insert on public.hospital_report_log;
create policy hospital_report_log_insert on public.hospital_report_log
  for insert with check (auth.uid() = author_id);

-- RPC crear: valida acceso al reporte y resuelve organization_id del center.
create or replace function public.hospital_log_add(
  p_report uuid,
  p_kind text,
  p_content text,
  p_shared_with_admin boolean default false
) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v_actor uuid := auth.uid();
  v_org uuid;
  v_provider uuid;
  v_name text;
begin
  if v_actor is null then raise exception 'Debe iniciar sesión.'; end if;
  if p_kind not in ('proceso','hallazgo','observacion') then
    raise exception 'Tipo inválido. Use proceso, hallazgo u observacion.' using errcode = '22023';
  end if;
  if coalesce(trim(p_content), '') = '' then
    raise exception 'El contenido no puede ir vacío.' using errcode = '22023';
  end if;

  select hr.provider_id, hc.organization_id
    into v_provider, v_org
    from public.hospital_reports hr
    join public.health_centers hc on hc.id = hr.center_id
   where hr.id = p_report;
  if v_org is null then
    raise exception 'Reporte no encontrado.' using errcode = 'P0002';
  end if;

  if not (
    exists (select 1 from public.providers p where p.id = v_provider and p.user_id = v_actor)
    or app.is_staff()
    or exists (
      select 1 from public.organization_users ou
      where ou.user_id = v_actor and ou.organization_id = v_org and ou.is_active
        and ou.role_code in ('super_admin','admin','client','capturer','asistente')
    )
  ) then
    raise exception 'No tiene permiso para agregar notas a este reporte.' using errcode = '42501';
  end if;

  select full_name into v_name from public.profiles where id = v_actor;

  insert into public.hospital_report_log (
    report_id, organization_id, kind, content, shared_with_admin, author_id, author_name_cached
  ) values (
    p_report, v_org, p_kind, trim(p_content), coalesce(p_shared_with_admin, false), v_actor, v_name
  );

  return jsonb_build_object('ok', true);
end $$;

-- RPC listar: aplica las mismas reglas de visibilidad que el policy.
create or replace function public.hospital_log_list(p_report uuid)
returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare
  v_actor uuid := auth.uid();
  v_org uuid;
  v_rows jsonb;
begin
  if v_actor is null then raise exception 'Debe iniciar sesión.'; end if;

  select hc.organization_id into v_org
    from public.hospital_reports hr join public.health_centers hc on hc.id = hr.center_id
   where hr.id = p_report;
  if v_org is null then raise exception 'Reporte no encontrado.' using errcode = 'P0002'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id, 'kind', l.kind, 'content', l.content,
    'shared_with_admin', l.shared_with_admin,
    'author_id', l.author_id, 'author_name', l.author_name_cached,
    'created_at', l.created_at,
    'mine', l.author_id = v_actor
  ) order by l.created_at desc), '[]'::jsonb)
    into v_rows
    from public.hospital_report_log l
   where l.report_id = p_report
     and (
       l.author_id = v_actor
       or app.is_staff()
       or (
         l.shared_with_admin = true
         and exists (
           select 1 from public.organization_users ou
           where ou.user_id = v_actor and ou.organization_id = v_org
             and ou.is_active and ou.role_code in ('super_admin','admin','client')
         )
       )
     );

  return jsonb_build_object(
    'report_id', p_report,
    'can_write', (
      exists (select 1 from public.hospital_reports hr join public.providers p on p.id = hr.provider_id
               where hr.id = p_report and p.user_id = v_actor)
      or app.is_staff()
      or exists (select 1 from public.organization_users ou
                 where ou.user_id = v_actor and ou.organization_id = v_org and ou.is_active
                   and ou.role_code in ('super_admin','admin','client','capturer','asistente'))
    ),
    'entries', v_rows
  );
end $$;

revoke all on function public.hospital_log_add(uuid, text, text, boolean) from public;
revoke execute on function public.hospital_log_add(uuid, text, text, boolean) from anon;
grant execute on function public.hospital_log_add(uuid, text, text, boolean) to authenticated;

revoke all on function public.hospital_log_list(uuid) from public;
revoke execute on function public.hospital_log_list(uuid) from anon;
grant execute on function public.hospital_log_list(uuid) to authenticated;

comment on table public.hospital_report_log is
  'Bitácora append-only de hospitalización: procesos, hallazgos y observaciones por reporte, con visibilidad explícita al admin del cliente.';
