-- SOFA · 5.35.3 · Módulo #/mercadeo: seguimiento de actividades de marketing y backlog de materiales.
-- Ya aplicado en producción (mcp__Supabase__apply_migration 2026-11-15).
-- Panel ejecutivo (super_admin, admin, operations). No es CRM: el CRM vive en leads/opportunities.
-- Aquí se registran acciones concretas (posts publicados, llamadas, demos, referidos pedidos) y el
-- pipeline de materiales (idea → en proceso → listo → publicado). Las actividades pueden vincularse
-- a un lead (prospecto) o a una organización (cliente ya convertido) para medir conversión.
--
-- Pendiente de aplicar en producción — el pop-up del MCP Supabase ha estado haciendo timeout.
-- Aplicar manualmente este archivo en el proyecto bpwjhgpzhzhiocoxrvzq.

create table if not exists public.marketing_activities (
  id bigserial primary key,
  activity_date date not null default current_date,
  channel text not null check (channel in ('whatsapp','linkedin','instagram','llamada','email','evento','referido','otro')),
  kind text not null check (kind in ('post','mensaje','llamada','demo','reunion','visita','material','otro')),
  lead_id uuid null references public.leads(id) on delete set null,
  organization_id uuid null references public.organizations(id) on delete set null,
  subject text not null check (length(subject) between 1 and 200),
  outcome text not null default 'pendiente' check (outcome in ('pendiente','sin_respuesta','interesado','demo_agendada','no_interesado','convertido')),
  notes text check (notes is null or length(notes) <= 2000),
  actor_id uuid not null,
  actor_name_cached text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_marketing_activities_date on public.marketing_activities(activity_date desc);
create index if not exists idx_marketing_activities_lead on public.marketing_activities(lead_id) where lead_id is not null;
create index if not exists idx_marketing_activities_org on public.marketing_activities(organization_id) where organization_id is not null;

create table if not exists public.marketing_materials (
  id bigserial primary key,
  title text not null check (length(title) between 1 and 160),
  channel text not null check (channel in ('linkedin','instagram','whatsapp','video','pdf','email','otro')),
  status text not null default 'idea' check (status in ('idea','en_proceso','listo','publicado','pausado')),
  due_date date null,
  published_on date null,
  owner_id uuid null,
  owner_name_cached text,
  notes text check (notes is null or length(notes) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_marketing_materials_status on public.marketing_materials(status, due_date nulls last);

-- touched_at trigger (reutiliza patrón del repo)
create or replace function app.marketing_touched()
returns trigger language plpgsql set search_path to '' as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists marketing_activities_touched on public.marketing_activities;
create trigger marketing_activities_touched before update on public.marketing_activities
  for each row execute function app.marketing_touched();

drop trigger if exists marketing_materials_touched on public.marketing_materials;
create trigger marketing_materials_touched before update on public.marketing_materials
  for each row execute function app.marketing_touched();

alter table public.marketing_activities enable row level security;
alter table public.marketing_materials  enable row level security;

-- Policies: solo staff de SOFA (super_admin, admin, operations) ven/escriben.
drop policy if exists marketing_activities_rw on public.marketing_activities;
create policy marketing_activities_rw on public.marketing_activities
  for all using (app.is_staff(array['super_admin','admin','operations']))
          with check (app.is_staff(array['super_admin','admin','operations']));

drop policy if exists marketing_materials_rw on public.marketing_materials;
create policy marketing_materials_rw on public.marketing_materials
  for all using (app.is_staff(array['super_admin','admin','operations']))
          with check (app.is_staff(array['super_admin','admin','operations']));

-- RPC resumen: KPIs + lista actividades recientes + backlog materiales. Un solo round-trip.
create or replace function public.marketing_overview(
  p_from date default (current_date - interval '30 days')::date,
  p_to   date default current_date
) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare
  v_from date := coalesce(p_from, (current_date - interval '30 days')::date);
  v_to   date := coalesce(p_to, current_date);
  v_kpis jsonb;
  v_by_channel jsonb;
  v_funnel jsonb;
  v_activities jsonb;
  v_materials jsonb;
begin
  if not app.is_staff(array['super_admin','admin','operations']) then
    raise exception 'Sin acceso al módulo de mercadeo.' using errcode = '42501';
  end if;

  with ventana as (
    select * from public.marketing_activities where activity_date between v_from and v_to
  ),
  kpis as (
    select
      count(*)::int as total,
      count(*) filter (where kind = 'post')::int as posts,
      count(*) filter (where kind = 'demo')::int as demos,
      count(*) filter (where outcome = 'interesado')::int as interesados,
      count(*) filter (where outcome = 'convertido')::int as convertidos,
      count(distinct lead_id) filter (where lead_id is not null)::int as leads_tocados
      from ventana
  )
  select jsonb_build_object(
    'total', total, 'posts', posts, 'demos', demos,
    'interesados', interesados, 'convertidos', convertidos,
    'leads_tocados', leads_tocados
  ) into v_kpis from kpis;

  select coalesce(jsonb_object_agg(channel, n), '{}'::jsonb) into v_by_channel
    from (select channel, count(*)::int n from public.marketing_activities
           where activity_date between v_from and v_to group by channel) t;

  select coalesce(jsonb_object_agg(outcome, n), '{}'::jsonb) into v_funnel
    from (select outcome, count(*)::int n from public.marketing_activities
           where activity_date between v_from and v_to group by outcome) t;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'activity_date', a.activity_date, 'channel', a.channel, 'kind', a.kind,
    'subject', a.subject, 'outcome', a.outcome, 'notes', a.notes,
    'actor_id', a.actor_id, 'actor_name', a.actor_name_cached,
    'lead_id', a.lead_id, 'lead_company', l.company,
    'organization_id', a.organization_id, 'organization_name', o.legal_name,
    'created_at', a.created_at
  ) order by a.activity_date desc, a.created_at desc), '[]'::jsonb)
    into v_activities
    from public.marketing_activities a
    left join public.leads l on l.id = a.lead_id
    left join public.organizations o on o.id = a.organization_id
   where a.activity_date between v_from and v_to
   limit 200;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id, 'title', m.title, 'channel', m.channel, 'status', m.status,
    'due_date', m.due_date, 'published_on', m.published_on,
    'owner_id', m.owner_id, 'owner_name', m.owner_name_cached,
    'notes', m.notes, 'updated_at', m.updated_at
  ) order by
    case m.status when 'en_proceso' then 1 when 'listo' then 2 when 'idea' then 3
                  when 'publicado' then 4 when 'pausado' then 5 else 6 end,
    m.due_date nulls last, m.updated_at desc), '[]'::jsonb)
    into v_materials
    from public.marketing_materials m;

  return jsonb_build_object(
    'range', jsonb_build_object('from', v_from, 'to', v_to),
    'kpis', v_kpis,
    'by_channel', v_by_channel,
    'funnel', v_funnel,
    'activities', v_activities,
    'materials', v_materials
  );
end $$;

-- RPC registrar actividad.
create or replace function public.marketing_activity_save(
  p_id bigint default null,
  p_activity_date date default current_date,
  p_channel text default 'otro',
  p_kind text default 'otro',
  p_lead uuid default null,
  p_org uuid default null,
  p_subject text default null,
  p_outcome text default 'pendiente',
  p_notes text default null
) returns bigint
language plpgsql security definer set search_path to '' as $$
declare
  v_actor uuid := auth.uid();
  v_name text;
  v_id bigint;
begin
  if not app.is_staff(array['super_admin','admin','operations']) then
    raise exception 'Sin acceso al módulo de mercadeo.' using errcode = '42501';
  end if;
  if coalesce(trim(p_subject), '') = '' then
    raise exception 'Escribe un asunto breve de la actividad.' using errcode = '22023';
  end if;

  select full_name into v_name from public.profiles where id = v_actor;

  if p_id is null then
    insert into public.marketing_activities
      (activity_date, channel, kind, lead_id, organization_id, subject, outcome, notes, actor_id, actor_name_cached)
    values
      (coalesce(p_activity_date, current_date), p_channel, p_kind, p_lead, p_org,
       trim(p_subject), coalesce(p_outcome, 'pendiente'), nullif(trim(coalesce(p_notes, '')), ''),
       v_actor, v_name)
    returning id into v_id;
  else
    update public.marketing_activities set
      activity_date = coalesce(p_activity_date, activity_date),
      channel = coalesce(p_channel, channel),
      kind = coalesce(p_kind, kind),
      lead_id = p_lead,
      organization_id = p_org,
      subject = coalesce(trim(p_subject), subject),
      outcome = coalesce(p_outcome, outcome),
      notes = nullif(trim(coalesce(p_notes, '')), '')
      where id = p_id
      returning id into v_id;
    if v_id is null then raise exception 'Actividad no encontrada.' using errcode = 'P0002'; end if;
  end if;

  return v_id;
end $$;

-- RPC registrar material.
create or replace function public.marketing_material_save(
  p_id bigint default null,
  p_title text default null,
  p_channel text default 'otro',
  p_status text default 'idea',
  p_due_date date default null,
  p_published_on date default null,
  p_notes text default null,
  p_owner uuid default null
) returns bigint
language plpgsql security definer set search_path to '' as $$
declare
  v_actor uuid := auth.uid();
  v_owner uuid := coalesce(p_owner, v_actor);
  v_owner_name text;
  v_id bigint;
begin
  if not app.is_staff(array['super_admin','admin','operations']) then
    raise exception 'Sin acceso al módulo de mercadeo.' using errcode = '42501';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'Escribe un título para el material.' using errcode = '22023';
  end if;

  select full_name into v_owner_name from public.profiles where id = v_owner;

  if p_id is null then
    insert into public.marketing_materials
      (title, channel, status, due_date, published_on, notes, owner_id, owner_name_cached)
    values
      (trim(p_title), p_channel, coalesce(p_status, 'idea'), p_due_date, p_published_on,
       nullif(trim(coalesce(p_notes, '')), ''), v_owner, v_owner_name)
    returning id into v_id;
  else
    update public.marketing_materials set
      title = coalesce(trim(p_title), title),
      channel = coalesce(p_channel, channel),
      status = coalesce(p_status, status),
      due_date = p_due_date,
      published_on = p_published_on,
      notes = nullif(trim(coalesce(p_notes, '')), ''),
      owner_id = coalesce(p_owner, owner_id),
      owner_name_cached = case when p_owner is not null then v_owner_name else owner_name_cached end
      where id = p_id
      returning id into v_id;
    if v_id is null then raise exception 'Material no encontrado.' using errcode = 'P0002'; end if;
  end if;

  return v_id;
end $$;

revoke all on function public.marketing_overview(date, date) from public;
revoke execute on function public.marketing_overview(date, date) from anon;
grant execute on function public.marketing_overview(date, date) to authenticated;

revoke all on function public.marketing_activity_save(bigint, date, text, text, uuid, uuid, text, text, text) from public;
revoke execute on function public.marketing_activity_save(bigint, date, text, text, uuid, uuid, text, text, text) from anon;
grant execute on function public.marketing_activity_save(bigint, date, text, text, uuid, uuid, text, text, text) to authenticated;

revoke all on function public.marketing_material_save(bigint, text, text, text, date, date, text, uuid) from public;
revoke execute on function public.marketing_material_save(bigint, text, text, text, date, date, text, uuid) from anon;
grant execute on function public.marketing_material_save(bigint, text, text, text, date, date, text, uuid) to authenticated;

comment on table public.marketing_activities is 'Actividades de mercadeo (post, llamada, demo, referido…) con outcome para medir conversión.';
comment on table public.marketing_materials  is 'Backlog de materiales de mercadeo (idea → publicado) con canal, fecha y dueño.';
