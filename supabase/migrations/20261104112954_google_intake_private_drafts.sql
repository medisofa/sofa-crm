create table app.google_intake_drafts(
 id uuid primary key,
 owner_id uuid not null references public.profiles(id),
 scope_ids uuid[] not null default '{}',
 source_name text not null check(length(source_name) between 1 and 255),
 payload jsonb not null check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=8388608),
 revision bigint not null default 1 check(revision>0),
 archived boolean not null default false,
 updated_at timestamptz not null default now()
);
create index google_intake_drafts_owner_idx on app.google_intake_drafts(owner_id,archived,updated_at desc);
alter table app.google_intake_drafts enable row level security;
create policy google_intake_drafts_owner on app.google_intake_drafts to authenticated
 using(owner_id=(select auth.uid()) and scope_ids<@array(select app.visible_org_ids()))
 with check(owner_id=(select auth.uid()) and scope_ids<@array(select app.visible_org_ids()));
revoke all on app.google_intake_drafts from public,anon,authenticated;

create table app.google_intake_draft_events(
 id bigint generated always as identity primary key,
 draft_id uuid not null references app.google_intake_drafts(id),
 actor_id uuid not null references public.profiles(id),
 revision bigint not null,
 action text not null check(action in('saved','archived')),
 occurred_at timestamptz not null default now()
);
create index google_intake_draft_events_draft_idx on app.google_intake_draft_events(draft_id,revision);
create index google_intake_draft_events_actor_idx on app.google_intake_draft_events(actor_id);
alter table app.google_intake_draft_events enable row level security;
create policy google_intake_draft_events_owner on app.google_intake_draft_events for select to authenticated
 using(actor_id=(select auth.uid()));
revoke all on app.google_intake_draft_events from public,anon,authenticated;

create function public.google_intake_drafts_v1(p_action text,p_id uuid default null,p_version bigint default null,p_payload jsonb default '{}'::jsonb,p_owner uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_uid uuid:=auth.uid();v_row app.google_intake_drafts;v_scopes uuid[];v_visible uuid[];v_items jsonb;v_name text;v_new boolean;
begin
 if v_uid is null or p_owner is distinct from v_uid or not app.is_staff(array['super_admin','admin','operations','billing']) then
  raise exception using errcode='42501',message='No tiene acceso a los borradores de esta sesión.';
 end if;
 v_visible:=array(select app.visible_org_ids());
 if p_action='list' then
  select coalesce(jsonb_agg(to_jsonb(d) order by d.updated_at desc),'[]'::jsonb) into v_items from(
   select id,source_name,revision,updated_at,jsonb_array_length(payload->'rows') as rows
   from app.google_intake_drafts where owner_id=v_uid and not archived and scope_ids<@v_visible order by updated_at desc limit 20)d;
  return jsonb_build_object('items',v_items);
 end if;
 if p_action in ('legacy_list','legacy_get','events') then
  if p_action='legacy_list' then
   select coalesce(jsonb_agg(to_jsonb(d) order by d.updated_at desc),'[]'::jsonb) into v_items from(
    select split_part(a.record_id,':row:',1)::uuid as id,max(a.occurred_at) as updated_at,count(distinct a.record_id) as rows
    from public.audit_log a where a.user_id=v_uid and a.table_name='google_claim_intake'
     and a.record_id~'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}:row:[0-9]+$'
     and a.operation in('CORRECCION_CARGA_EXTERNA','IMPORTACION_CARGA_EXTERNA','CONFIRMACION_CARGA_EXTERNA','ELIMINACION_CARGA_EXTERNA')
     and not exists(select 1 from app.google_intake_drafts d where d.owner_id=v_uid and coalesce(d.payload->>'origin_id',d.id::text)=split_part(a.record_id,':row:',1))
    group by split_part(a.record_id,':row:',1)
    having bool_and(a.organization_id is null or a.organization_id=any(v_visible))
    order by max(a.occurred_at) desc limit 20)d;
   return jsonb_build_object('items',v_items);
  end if;
  if p_id is null then raise exception using errcode='22023',message='Seleccione la revisión anterior.';end if;
  if p_action='legacy_get' and exists(select 1 from app.google_intake_drafts d where d.owner_id=v_uid and d.id=p_id) then raise exception using errcode='22023',message='Esa revisión ya tiene un borrador. Use Reanudar carga para continuar.';end if;
  if exists(select 1 from public.audit_log a where a.user_id=v_uid and a.table_name='google_claim_intake' and a.record_id like p_id::text||':row:%'
   and a.organization_id is not null and not(a.organization_id=any(v_visible))) then
   raise exception using errcode='42501',message='Cambió su acceso a una organización de esta carga.';
  end if;
  select coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]'::jsonb) into v_items from(
   select a.id,a.record_id,a.operation,a.old_values,a.new_values,a.occurred_at
   from public.audit_log a where a.user_id=v_uid and a.table_name='google_claim_intake' and a.record_id like p_id::text||':row:%'
    and a.operation in('CORRECCION_CARGA_EXTERNA','IMPORTACION_CARGA_EXTERNA','CONFIRMACION_CARGA_EXTERNA','ELIMINACION_CARGA_EXTERNA') order by a.id limit 10000)d;
  return jsonb_build_object('events',v_items,'commits',(select coalesce(jsonb_agg(jsonb_build_object('row',split_part(c.record_id,':row:',2),'result',c.result,'removed',c.removed or not exists(select 1 from public.service_lines l where l.id=c.claim_id))),'[]'::jsonb)
 from app.google_intake_commits c where c.created_by=v_uid and c.record_id like p_id::text||':row:%' and c.organization_id=any(v_visible)));
 end if;
 if p_action='latest' then
  select * into v_row from app.google_intake_drafts where owner_id=v_uid and not archived and scope_ids<@v_visible order by updated_at desc limit 1;
  if not found then return jsonb_build_object('draft',null);end if;
  return jsonb_build_object('draft',jsonb_build_object('id',v_row.id,'version',v_row.revision,'payload',v_row.payload,'updated_at',v_row.updated_at),'commits',(select coalesce(jsonb_agg(jsonb_build_object('row',split_part(c.record_id,':row:',2),'result',c.result,'removed',c.removed or not exists(select 1 from public.service_lines l where l.id=c.claim_id))),'[]'::jsonb)
 from app.google_intake_commits c where c.created_by=v_uid and c.record_id like coalesce(v_row.payload->>'origin_id',v_row.id::text)||':row:%' and c.organization_id=any(v_visible)));
 end if;
 if p_id is null then raise exception using errcode='22023',message='Identificador de carga inválido.';end if;
 if p_action='get' then
  select * into v_row from app.google_intake_drafts where id=p_id and owner_id=v_uid and not archived;
  if not found or not(v_row.scope_ids<@v_visible) then raise exception using errcode='42501',message='La carga no está disponible para su usuario.';end if;
  return jsonb_build_object('draft',jsonb_build_object('id',v_row.id,'version',v_row.revision,'payload',v_row.payload,'updated_at',v_row.updated_at),'commits',(select coalesce(jsonb_agg(jsonb_build_object('row',split_part(c.record_id,':row:',2),'result',c.result,'removed',c.removed or not exists(select 1 from public.service_lines l where l.id=c.claim_id))),'[]'::jsonb)
 from app.google_intake_commits c where c.created_by=v_uid and c.record_id like coalesce(v_row.payload->>'origin_id',v_row.id::text)||':row:%' and c.organization_id=any(v_visible)));
 end if;
 if p_action is null or p_action not in('save','archive') then raise exception using errcode='22023',message='Acción de borrador inválida.';end if;
 perform pg_advisory_xact_lock(hashtextextended('google-draft:'||v_uid::text,0));
 select * into v_row from app.google_intake_drafts where id=p_id for update;
 v_new:=not found;
 if not v_new and (v_row.owner_id<>v_uid or not(v_row.scope_ids<@v_visible)) then raise exception using errcode='42501',message='No puede modificar esta carga.';end if;
 if p_action='archive' then
  if v_new then return jsonb_build_object('archived',true);end if;
  if not v_row.archived and p_version is distinct from v_row.revision then raise exception using errcode='40001',message='La carga cambió en otra pestaña. Recupere la versión guardada antes de descartarla.';end if;
  if not v_row.archived then
   update app.google_intake_drafts set archived=true,revision=revision+1,updated_at=now() where id=p_id returning * into v_row;
   insert into app.google_intake_draft_events(draft_id,actor_id,revision,action)values(p_id,v_uid,v_row.revision,'archived');
  end if;
  return jsonb_build_object('archived',true,'version',v_row.revision);
 end if;
 if p_payload is null or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>8388608
  or p_payload->>'schema' is distinct from '1' or jsonb_typeof(p_payload->'rows') is distinct from 'array' then
  raise exception using errcode='22023',message='El formato del borrador no es válido.';
 end if;
 if jsonb_array_length(p_payload->'rows')>1000 then raise exception using errcode='22023',message='El borrador supera las 1,000 filas.';end if;
 if p_payload ? 'origin_id' then perform (p_payload->>'origin_id')::uuid;end if;
 v_name:=btrim(coalesce(p_payload->>'source_name','Carga sin nombre'));
 if length(v_name) not between 1 and 255 or jsonb_typeof(coalesce(p_payload->'scope_ids','[]'::jsonb))<>'array' then raise exception using errcode='22023',message='Nombre o contexto de carga inválido.';end if;
 v_scopes:=array(select distinct value::uuid from jsonb_array_elements_text(coalesce(p_payload->'scope_ids','[]'::jsonb)));
 if not(v_scopes<@v_visible) then raise exception using errcode='42501',message='No puede guardar datos de esa organización.';end if;
 if not v_new then
  if v_row.archived then raise exception using errcode='40001',message='La carga fue descartada en otra pestaña. No se sobrescribirá.';end if;
  if v_row.payload=p_payload then return jsonb_build_object('version',v_row.revision,'updated_at',v_row.updated_at);end if;
  if p_version is distinct from v_row.revision then raise exception using errcode='40001',message='La carga cambió en otra pestaña. Sus cambios siguen en pantalla; recupere la versión guardada antes de continuar.';end if;
  update app.google_intake_drafts set payload=p_payload,scope_ids=v_scopes,source_name=v_name,revision=revision+1,updated_at=now() where id=p_id returning * into v_row;
 else
  if coalesce(p_version,0)<>0 then raise exception using errcode='40001',message='No se encontró la versión de la carga.';end if;
  if(select count(*) from app.google_intake_drafts where owner_id=v_uid and not archived)>=20 then raise exception using errcode='22023',message='Ya tiene 20 cargas pendientes. Descarte una carga que no necesite.';end if;
  insert into app.google_intake_drafts(id,owner_id,scope_ids,source_name,payload)values(p_id,v_uid,v_scopes,v_name,p_payload)returning * into v_row;
 end if;
 insert into app.google_intake_draft_events(draft_id,actor_id,revision,action)values(p_id,v_uid,v_row.revision,'saved');
 return jsonb_build_object('version',v_row.revision,'updated_at',v_row.updated_at);
end$$;
revoke all on function public.google_intake_drafts_v1(text,uuid,bigint,jsonb,uuid) from public,anon;
grant execute on function public.google_intake_drafts_v1(text,uuid,bigint,jsonb,uuid) to authenticated;

notify pgrst, 'reload schema';
