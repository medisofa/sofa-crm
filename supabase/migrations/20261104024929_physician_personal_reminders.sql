-- Additive personal reminders. Activation is a separate, explicit step after validation.
create table app.physician_reminder_settings (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false
);
insert into app.physician_reminder_settings(singleton) values(true);
alter table app.physician_reminder_settings enable row level security;
revoke all on app.physician_reminder_settings from public,anon,authenticated;

create table app.physician_reminders (
 id uuid primary key,
 organization_id uuid not null references public.organizations(id),
 owner_id uuid not null references public.profiles(id),
 kind text not null check(kind in ('note','payment')),
 title text not null check(length(btrim(title)) between 1 and 160),
 body text not null default '' check(length(body)<=2000),
 due_date date,
 amount numeric(14,2),
 completed boolean not null default false,
 version integer not null default 1 check(version>0),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((kind='note' and amount is null) or (kind='payment' and amount is not null and amount>0 and amount<1000000000000 and due_date is not null))
);
create index physician_reminders_owner_org_idx on app.physician_reminders(owner_id,organization_id,completed,due_date);
create index physician_reminders_org_idx on app.physician_reminders(organization_id);
alter table app.physician_reminders enable row level security;
create policy physician_reminders_owner on app.physician_reminders to authenticated
 using(owner_id=(select auth.uid()) and app.can(organization_id,array['client']))
 with check(owner_id=(select auth.uid()) and app.can(organization_id,array['client']));
revoke all on app.physician_reminders from public,anon,authenticated;

create table app.physician_reminder_events (
 id bigint generated always as identity primary key,
 reminder_id uuid not null references app.physician_reminders(id),
 actor_id uuid not null references public.profiles(id),
 organization_id uuid not null references public.organizations(id),
 action text not null check(action in ('created','updated','completed','reopened')),
 version integer not null,
 created_at timestamptz not null default now()
);
create index physician_reminder_events_reminder_idx on app.physician_reminder_events(reminder_id,version);
create index physician_reminder_events_actor_idx on app.physician_reminder_events(actor_id);
create index physician_reminder_events_org_idx on app.physician_reminder_events(organization_id);
alter table app.physician_reminder_events enable row level security;
create policy physician_reminder_events_owner on app.physician_reminder_events for select to authenticated
 using(actor_id=(select auth.uid()) and app.can(organization_id,array['client']));
revoke all on app.physician_reminder_events from public,anon,authenticated;

create function public.physician_reminders_v1(p_org uuid,p_action text default 'list',p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_uid uuid:=auth.uid(); v_row app.physician_reminders; v_old app.physician_reminders;
 v_id uuid; v_kind text; v_title text; v_body text; v_due date; v_amount numeric(14,2);
 v_done boolean; v_version integer; v_exists boolean; v_items jsonb;
begin
 if v_uid is null or not coalesce(app.can(p_org,array['client']),false) then
  raise exception using errcode='42501',message='No tiene acceso a los recordatorios de este consultorio.';
 end if;
 if not coalesce((select enabled from app.physician_reminder_settings where singleton),false) then
  return jsonb_build_object('enabled',false,'items','[]'::jsonb);
 end if;
 if p_action='list' then
  select coalesce(jsonb_agg(to_jsonb(r) order by r.completed,r.due_date nulls last,r.updated_at desc),'[]'::jsonb) into v_items
  from (select id,kind,title,body,due_date,amount,completed,version,updated_at
   from app.physician_reminders where owner_id=v_uid and organization_id=p_org
   order by completed,due_date nulls last,updated_at desc limit 200) r;
  return jsonb_build_object('enabled',true,'items',v_items);
 end if;
 if p_action is distinct from 'save' or p_data is null or jsonb_typeof(p_data) is distinct from 'object' then
  raise exception using errcode='22023',message='Solicitud de recordatorio no válida.';
 end if;
 v_id:=(p_data->>'id')::uuid; v_kind:=p_data->>'kind'; v_title:=btrim(p_data->>'title');
 v_body:=coalesce(p_data->>'body',''); v_due:=nullif(p_data->>'due_date','')::date;
 v_amount:=nullif(p_data->>'amount','')::numeric(14,2); v_done:=coalesce((p_data->>'completed')::boolean,false);
 v_version:=(p_data->>'version')::integer;
 if v_id is null or v_version is null or v_version<0 or v_kind is null or v_kind not in ('note','payment')
  or v_title is null or length(v_title) not between 1 and 160 or length(v_body)>2000
  or (v_kind='note' and v_amount is not null) or (v_kind='payment' and (v_amount is null or v_amount<=0 or v_amount::text='NaN' or v_due is null))
 then raise exception using errcode='22023',message='Revise el título, el tipo, la fecha y el monto del recordatorio.'; end if;
 -- One lock serializes creates for this owner/organization, including retries of the same UUID.
 perform pg_advisory_xact_lock(hashtextextended(v_uid::text||':'||p_org::text,0));
 select * into v_old from app.physician_reminders where id=v_id for update;
 v_exists:=found;
 if v_exists and (v_old.owner_id<>v_uid or v_old.organization_id<>p_org) then
  raise exception using errcode='42501',message='No tiene acceso a este recordatorio.';
 end if;
 if v_exists then
  -- Retrying the exact successful payload returns the saved row without another event.
  if v_old.kind=v_kind and v_old.title=v_title and v_old.body=v_body and v_old.due_date is not distinct from v_due
   and v_old.amount is not distinct from v_amount and v_old.completed=v_done then
   return jsonb_build_object('enabled',true,'item',to_jsonb(v_old)-'owner_id'-'organization_id');
  end if;
  if v_old.version<>v_version then raise exception using errcode='40001',message='Este recordatorio cambió en otra ventana. Actualice la lista antes de editarlo.'; end if;
  update app.physician_reminders set kind=v_kind,title=v_title,body=v_body,due_date=v_due,amount=v_amount,
   completed=v_done,version=version+1,updated_at=now() where id=v_id returning * into v_row;
 else
  if v_version<>0 then raise exception using errcode='40001',message='El recordatorio ya no está disponible. Actualice la lista.'; end if;
  if (select count(*) from app.physician_reminders where owner_id=v_uid and organization_id=p_org)>=500 then
   raise exception using errcode='22023',message='Ha alcanzado el límite de 500 recordatorios en este consultorio.';
  end if;
  insert into app.physician_reminders(id,organization_id,owner_id,kind,title,body,due_date,amount,completed)
   values(v_id,p_org,v_uid,v_kind,v_title,v_body,v_due,v_amount,v_done) returning * into v_row;
 end if;
 insert into app.physician_reminder_events(reminder_id,actor_id,organization_id,action,version)
 values(v_id,v_uid,p_org,case when not v_exists then 'created' when v_done and not v_old.completed then 'completed'
  when not v_done and v_old.completed then 'reopened' else 'updated' end,v_row.version);
 return jsonb_build_object('enabled',true,'item',to_jsonb(v_row)-'owner_id'-'organization_id');
end $$;
revoke all on function public.physician_reminders_v1(uuid,text,jsonb) from public,anon;
grant execute on function public.physician_reminders_v1(uuid,text,jsonb) to authenticated;
