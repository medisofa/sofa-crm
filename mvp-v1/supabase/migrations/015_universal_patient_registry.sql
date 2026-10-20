-- SOFA · Registro Universal Administrativo de Pacientes
-- Comparte identidad/datos administrativos entre clientes SOFA, nunca datos clínicos ni consultas.

alter table public.patients add column if not exists global_patient_id uuid;
alter table public.patients add column if not exists nss text;

create table if not exists public.global_patients (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  cedula text,
  nss text,
  birth_date date,
  sex text,
  phone text,
  email text,
  ars_id uuid references public.ars(id),
  member_number text,
  identity_status text not null default 'verified' check(identity_status in ('verified','provisional')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create unique index if not exists global_patients_cedula_uq
  on public.global_patients((regexp_replace(cedula,'\D','','g')))
  where nullif(regexp_replace(coalesce(cedula,''),'\D','','g'),'') is not null;

create unique index if not exists global_patients_nss_uq
  on public.global_patients((lower(trim(nss))))
  where nullif(trim(coalesce(nss,'')),'') is not null;

create table if not exists public.patient_global_links (
  global_patient_id uuid not null references public.global_patients(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  linked_at timestamptz not null default now(),
  linked_by uuid default auth.uid(),
  primary key(global_patient_id,organization_id),
  unique(patient_id)
);

create table if not exists public.patient_identity_changes (
  id bigint generated always as identity primary key,
  global_patient_id uuid not null references public.global_patients(id) on delete restrict,
  patient_id uuid references public.patients(id) on delete set null,
  organization_id uuid references public.organizations(id) on delete set null,
  user_id uuid,
  changed_at timestamptz not null default now(),
  reason text not null,
  fields text[] not null,
  old_values jsonb not null,
  new_values jsonb not null
);

alter table public.global_patients enable row level security;
alter table public.patient_global_links enable row level security;
alter table public.patient_identity_changes enable row level security;

-- No lectura directa global desde el cliente. Todo acceso pasa por RPC restringido.
revoke all on public.global_patients from anon,authenticated;
revoke all on public.patient_global_links from anon,authenticated;
revoke all on public.patient_identity_changes from anon,authenticated;

create or replace function public.global_patient_lookup(
  p_cedula text default null,
  p_nss text default null,
  p_name text default null,
  p_birth date default null,
  p_phone text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_ced text := nullif(regexp_replace(coalesce(p_cedula,''),'\D','','g'),'');
  v_nss text := nullif(lower(trim(coalesce(p_nss,''))),'');
  v_name text := nullif(lower(trim(regexp_replace(coalesce(p_name,''),'\s+',' ','g'))),'');
  v_phone text := nullif(regexp_replace(coalesce(p_phone,''),'\D','','g'),'');
  g public.global_patients;
begin
  if auth.uid() is null or not app.is_active_user() then
    raise exception 'Inicia sesión para buscar pacientes.' using errcode='42501';
  end if;

  -- Coincidencia fuerte: cédula o NSS exactos.
  if v_ced is not null or v_nss is not null then
    select * into g
      from public.global_patients x
     where x.is_active
       and ((v_ced is not null and regexp_replace(coalesce(x.cedula,''),'\D','','g')=v_ced)
         or (v_nss is not null and lower(trim(coalesce(x.nss,'')))=v_nss))
     limit 1;

    if g.id is null then
      return jsonb_build_object('match','none','patient',null);
    end if;

    -- Si ambos identificadores fueron suministrados, detectar conflicto en vez de fusionar.
    if v_ced is not null and nullif(regexp_replace(coalesce(g.cedula,''),'\D','','g'),'') is not null
       and regexp_replace(g.cedula,'\D','','g')<>v_ced then
      return jsonb_build_object('match','conflict','reason','cedula_conflict','patient_id',g.id);
    end if;
    if v_nss is not null and nullif(lower(trim(coalesce(g.nss,''))),'') is not null
       and lower(trim(g.nss))<>v_nss then
      return jsonb_build_object('match','conflict','reason','nss_conflict','patient_id',g.id);
    end if;

    return jsonb_build_object('match','exact','patient',jsonb_build_object(
      'id',g.id,'full_name',g.full_name,'cedula',g.cedula,'nss',g.nss,
      'birth_date',g.birth_date,'sex',g.sex,'phone',g.phone,'email',g.email,
      'ars_id',g.ars_id,'member_number',g.member_number,'identity_status',g.identity_status
    ));
  end if;

  -- Sin cédula/NSS: solo sugerir posible coincidencia; nunca fusionar automáticamente.
  if v_name is not null and p_birth is not null and v_phone is not null then
    select * into g
      from public.global_patients x
     where x.is_active
       and lower(trim(regexp_replace(x.full_name,'\s+',' ','g')))=v_name
       and x.birth_date=p_birth
       and regexp_replace(coalesce(x.phone,''),'\D','','g')=v_phone
     limit 1;
    if g.id is not null then
      return jsonb_build_object('match','possible','patient',jsonb_build_object(
        'id',g.id,'full_name',g.full_name,'birth_date',g.birth_date,'sex',g.sex,
        'phone',g.phone,'email',g.email,
        'cedula_masked',case when g.cedula is null then null else '***'||right(regexp_replace(g.cedula,'\D','','g'),4) end,
        'nss_masked',case when g.nss is null then null else '***'||right(regexp_replace(g.nss,'\D','','g'),4) end
      ));
    end if;
  end if;
  return jsonb_build_object('match','none','patient',null);
end
$$;

revoke all on function public.global_patient_lookup(text,text,text,date,text) from public,anon;
grant execute on function public.global_patient_lookup(text,text,text,date,text) to authenticated;

create or replace function public.attach_global_patient(
  p_global uuid,
  p_org uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  g public.global_patients;
  v_patient uuid;
begin
  if not app.can(p_org,array['super_admin','admin','operations','billing','assistant','client','capturer']) then
    raise exception 'Sin acceso para usar pacientes en este consultorio.' using errcode='42501';
  end if;
  select * into g from public.global_patients where id=p_global and is_active;
  if g.id is null then raise exception 'Paciente universal no encontrado.' using errcode='P0002'; end if;

  select patient_id into v_patient
    from public.patient_global_links
   where global_patient_id=g.id and organization_id=p_org;

  if v_patient is null then
    insert into public.patients(
      organization_id,global_patient_id,full_name,doc_number,nss,birth_date,sex,phone,email,ars_id,member_number,admin_notes,created_by,updated_by
    )
    values(
      p_org,g.id,g.full_name,g.cedula,g.nss,g.birth_date,g.sex,g.phone,g.email,g.ars_id,g.member_number,
      'Vinculado al Registro Universal SOFA',auth.uid(),auth.uid()
    )
    returning id into v_patient;

    insert into public.patient_global_links(global_patient_id,patient_id,organization_id)
    values(g.id,v_patient,p_org);
  end if;

  insert into public.patient_access_log(patient_id,organization_id,user_id,action)
  values(v_patient,p_org,auth.uid(),'usar_registro_universal');

  return v_patient;
end
$$;

revoke all on function public.attach_global_patient(uuid,uuid) from public,anon;
grant execute on function public.attach_global_patient(uuid,uuid) to authenticated;

create or replace function public.save_patient_global(
  p_id uuid,
  p_org uuid,
  p_full_name text,
  p_cedula text,
  p_nss text,
  p_birth date,
  p_sex text,
  p_phone text,
  p_email text,
  p_ars uuid,
  p_member text,
  p_notes text,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  p public.patients;
  g public.global_patients;
  v_patient uuid;
  v_global uuid;
  v_ced text := nullif(regexp_replace(coalesce(p_cedula,''),'\D','','g'),'');
  v_nss text := nullif(lower(trim(coalesce(p_nss,''))),'');
  v_fields text[] := '{}';
  v_old jsonb := '{}'::jsonb;
  v_new jsonb := '{}'::jsonb;
  v_need_reason boolean := false;
begin
  if not app.can(p_org,array['super_admin','admin','operations','billing','assistant','client','capturer']) then
    raise exception 'Sin acceso para guardar pacientes en este consultorio.' using errcode='42501';
  end if;
  if length(trim(coalesce(p_full_name,'')))<3 then
    raise exception 'Indique el nombre completo.' using errcode='22023';
  end if;

  if p_id is not null then
    select * into p from public.patients where id=p_id and organization_id=p_org for update;
    if p.id is null then raise exception 'Paciente no encontrado en este consultorio.' using errcode='P0002'; end if;
    v_global:=p.global_patient_id;

    if coalesce(regexp_replace(p.doc_number,'\D','','g'),'') is distinct from coalesce(v_ced,'') then
      v_fields:=array_append(v_fields,'cedula'); v_old:=v_old||jsonb_build_object('cedula',p.doc_number); v_new:=v_new||jsonb_build_object('cedula',p_cedula); v_need_reason:=true;
    end if;
    if coalesce(lower(trim(p.nss)),'') is distinct from coalesce(v_nss,'') then
      v_fields:=array_append(v_fields,'nss'); v_old:=v_old||jsonb_build_object('nss',p.nss); v_new:=v_new||jsonb_build_object('nss',p_nss); v_need_reason:=true;
    end if;
    if p.ars_id is distinct from p_ars then
      v_fields:=array_append(v_fields,'ars'); v_old:=v_old||jsonb_build_object('ars_id',p.ars_id); v_new:=v_new||jsonb_build_object('ars_id',p_ars); v_need_reason:=true;
    end if;
    if coalesce(trim(p.member_number),'') is distinct from coalesce(trim(p_member),'') then
      v_fields:=array_append(v_fields,'member_number'); v_old:=v_old||jsonb_build_object('member_number',p.member_number); v_new:=v_new||jsonb_build_object('member_number',p_member); v_need_reason:=true;
    end if;

    if v_need_reason and length(trim(coalesce(p_reason,'')))<5 then
      raise exception 'Justifique el cambio de cédula, NSS, ARS o número de afiliado (mínimo 5 caracteres).' using errcode='22023';
    end if;
  end if;

  -- Resolver o crear identidad universal.
  if v_global is null then
    if v_ced is not null then
      select id into v_global from public.global_patients where regexp_replace(coalesce(cedula,''),'\D','','g')=v_ced limit 1;
    end if;
    if v_global is null and v_nss is not null then
      select id into v_global from public.global_patients where lower(trim(coalesce(nss,'')))=v_nss limit 1;
    end if;
  end if;

  if v_global is null then
    insert into public.global_patients(full_name,cedula,nss,birth_date,sex,phone,email,ars_id,member_number,identity_status)
    values(trim(p_full_name),nullif(trim(p_cedula),''),nullif(trim(p_nss),''),p_birth,p_sex,nullif(trim(p_phone),''),nullif(trim(p_email),''),p_ars,nullif(trim(p_member),''),
           case when v_ced is null and v_nss is null then 'provisional' else 'verified' end)
    returning id into v_global;
  else
    select * into g from public.global_patients where id=v_global for update;
    update public.global_patients set
      full_name=trim(p_full_name),
      cedula=nullif(trim(p_cedula),''),
      nss=nullif(trim(p_nss),''),
      birth_date=p_birth,
      sex=p_sex,
      phone=nullif(trim(p_phone),''),
      email=nullif(trim(p_email),''),
      ars_id=p_ars,
      member_number=nullif(trim(p_member),''),
      identity_status=case when v_ced is null and v_nss is null then 'provisional' else 'verified' end,
      updated_at=now(),updated_by=auth.uid()
    where id=v_global;
  end if;

  if p_id is null then
    insert into public.patients(organization_id,global_patient_id,full_name,doc_number,nss,birth_date,sex,phone,email,ars_id,member_number,admin_notes,created_by,updated_by)
    values(p_org,v_global,trim(p_full_name),nullif(trim(p_cedula),''),nullif(trim(p_nss),''),p_birth,p_sex,nullif(trim(p_phone),''),nullif(trim(p_email),''),p_ars,nullif(trim(p_member),''),nullif(trim(p_notes),''),auth.uid(),auth.uid())
    returning id into v_patient;
    insert into public.patient_global_links(global_patient_id,patient_id,organization_id)
    values(v_global,v_patient,p_org)
    on conflict(global_patient_id,organization_id) do update set patient_id=excluded.patient_id;
  else
    update public.patients set
      global_patient_id=v_global,full_name=trim(p_full_name),doc_number=nullif(trim(p_cedula),''),nss=nullif(trim(p_nss),''),
      birth_date=p_birth,sex=p_sex,phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),''),
      ars_id=p_ars,member_number=nullif(trim(p_member),''),admin_notes=nullif(trim(p_notes),''),
      updated_at=now(),updated_by=auth.uid()
    where id=p_id
    returning id into v_patient;

    insert into public.patient_global_links(global_patient_id,patient_id,organization_id)
    values(v_global,v_patient,p_org)
    on conflict(global_patient_id,organization_id) do update set patient_id=excluded.patient_id;
  end if;

  if v_need_reason then
    insert into public.patient_identity_changes(global_patient_id,patient_id,organization_id,user_id,reason,fields,old_values,new_values)
    values(v_global,v_patient,p_org,auth.uid(),trim(p_reason),v_fields,v_old,v_new);

    insert into public.audit_log(user_id,organization_id,table_name,record_id,operation,old_values,new_values)
    values(auth.uid(),p_org,'global_patients',v_global::text,'ACTUALIZACION_IDENTIDAD_PACIENTE',v_old,
      v_new||jsonb_build_object('reason',trim(p_reason),'patient_id',v_patient));
  end if;

  return v_patient;
end
$$;

revoke all on function public.save_patient_global(uuid,uuid,text,text,text,date,text,text,text,uuid,text,text,text) from public,anon;
grant execute on function public.save_patient_global(uuid,uuid,text,text,text,date,text,text,text,uuid,text,text,text) to authenticated;

-- Backfill seguro de pacientes existentes. En producción se validó que no hay cédulas duplicadas actualmente.
do $$
declare p record; v_global uuid;
begin
  for p in select * from public.patients where global_patient_id is null loop
    v_global:=null;
    if nullif(regexp_replace(coalesce(p.doc_number,''),'\D','','g'),'') is not null then
      select id into v_global from public.global_patients
       where regexp_replace(coalesce(cedula,''),'\D','','g')=regexp_replace(p.doc_number,'\D','','g') limit 1;
    end if;
    if v_global is null and nullif(trim(coalesce(p.nss,p.member_number,'')),'') is not null then
      select id into v_global from public.global_patients
       where lower(trim(coalesce(nss,'')))=lower(trim(coalesce(p.nss,p.member_number))) limit 1;
    end if;
    if v_global is null then
      insert into public.global_patients(full_name,cedula,nss,birth_date,sex,phone,email,ars_id,member_number,identity_status,created_by,updated_by)
      values(p.full_name,p.doc_number,coalesce(p.nss,p.member_number),p.birth_date,p.sex,p.phone,p.email,p.ars_id,p.member_number,
        case when nullif(trim(coalesce(p.doc_number,p.nss,p.member_number,'')),'') is null then 'provisional' else 'verified' end,p.created_by,p.updated_by)
      returning id into v_global;
    end if;
    update public.patients set global_patient_id=v_global,nss=coalesce(nss,member_number) where id=p.id;
    insert into public.patient_global_links(global_patient_id,patient_id,organization_id,linked_by)
    values(v_global,p.id,p.organization_id,p.updated_by)
    on conflict do nothing;
  end loop;
end
$$;
