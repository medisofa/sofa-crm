-- SOFA · endurecimiento del Registro Universal de Pacientes
-- Evita que un alta local sobrescriba silenciosamente una identidad universal existente.

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
  lp public.patients;
  gp public.global_patients;
  v_patient uuid;
  v_global uuid;
  v_gid_ced uuid;
  v_gid_nss uuid;
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

  if v_ced is not null then
    select id into v_gid_ced from public.global_patients
     where regexp_replace(coalesce(cedula,''),'\D','','g')=v_ced and is_active limit 1;
  end if;
  if v_nss is not null then
    select id into v_gid_nss from public.global_patients
     where lower(trim(coalesce(nss,'')))=v_nss and is_active limit 1;
  end if;
  if v_gid_ced is not null and v_gid_nss is not null and v_gid_ced<>v_gid_nss then
    raise exception 'La cédula y el NSS pertenecen a registros universales distintos. Revise antes de continuar.' using errcode='23505';
  end if;
  v_global:=coalesce(v_gid_ced,v_gid_nss);

  if p_id is null and v_global is not null then
    -- La identidad ya existe: solo vincular a la organización. No sobrescribir datos universales.
    return public.attach_global_patient(v_global,p_org);
  end if;

  if p_id is not null then
    select * into lp from public.patients where id=p_id and organization_id=p_org for update;
    if lp.id is null then raise exception 'Paciente no encontrado en este consultorio.' using errcode='P0002'; end if;
    if lp.global_patient_id is not null then
      if v_global is not null and v_global<>lp.global_patient_id then
        raise exception 'Los identificadores escritos pertenecen a otro paciente universal. No se fusionará automáticamente.' using errcode='23505';
      end if;
      v_global:=lp.global_patient_id;
    end if;

    if coalesce(regexp_replace(lp.doc_number,'\D','','g'),'') is distinct from coalesce(v_ced,'') then
      v_fields:=array_append(v_fields,'cedula'); v_old:=v_old||jsonb_build_object('cedula',lp.doc_number); v_new:=v_new||jsonb_build_object('cedula',p_cedula); v_need_reason:=true;
    end if;
    if coalesce(lower(trim(lp.nss)),'') is distinct from coalesce(v_nss,'') then
      v_fields:=array_append(v_fields,'nss'); v_old:=v_old||jsonb_build_object('nss',lp.nss); v_new:=v_new||jsonb_build_object('nss',p_nss); v_need_reason:=true;
    end if;
    if lp.ars_id is distinct from p_ars then
      v_fields:=array_append(v_fields,'ars'); v_old:=v_old||jsonb_build_object('ars_id',lp.ars_id); v_new:=v_new||jsonb_build_object('ars_id',p_ars); v_need_reason:=true;
    end if;
    if coalesce(trim(lp.member_number),'') is distinct from coalesce(trim(p_member),'') then
      v_fields:=array_append(v_fields,'member_number'); v_old:=v_old||jsonb_build_object('member_number',lp.member_number); v_new:=v_new||jsonb_build_object('member_number',p_member); v_need_reason:=true;
    end if;
    if v_need_reason and length(trim(coalesce(p_reason,'')))<5 then
      raise exception 'Justifique el cambio de cédula, NSS, ARS o número de afiliado (mínimo 5 caracteres).' using errcode='22023';
    end if;
  end if;

  if v_global is null then
    insert into public.global_patients(full_name,cedula,nss,birth_date,sex,phone,email,ars_id,member_number,identity_status)
    values(trim(p_full_name),nullif(trim(p_cedula),''),nullif(trim(p_nss),''),p_birth,p_sex,nullif(trim(p_phone),''),nullif(trim(p_email),''),p_ars,nullif(trim(p_member),''),
           case when v_ced is null and v_nss is null then 'provisional' else 'verified' end)
    returning id into v_global;
  else
    select * into gp from public.global_patients where id=v_global for update;
    update public.global_patients set
      full_name=trim(p_full_name),cedula=nullif(trim(p_cedula),''),nss=nullif(trim(p_nss),''),
      birth_date=p_birth,sex=p_sex,phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),''),
      ars_id=p_ars,member_number=nullif(trim(p_member),''),
      identity_status=case when v_ced is null and v_nss is null then 'provisional' else 'verified' end,
      updated_at=now(),updated_by=auth.uid()
    where id=v_global;
  end if;

  if p_id is null then
    insert into public.patients(organization_id,global_patient_id,full_name,doc_number,nss,birth_date,sex,phone,email,ars_id,member_number,admin_notes,created_by,updated_by)
    values(p_org,v_global,trim(p_full_name),nullif(trim(p_cedula),''),nullif(trim(p_nss),''),p_birth,p_sex,nullif(trim(p_phone),''),nullif(trim(p_email),''),p_ars,nullif(trim(p_member),''),nullif(trim(p_notes),''),auth.uid(),auth.uid())
    returning id into v_patient;
  else
    update public.patients set
      global_patient_id=v_global,full_name=trim(p_full_name),doc_number=nullif(trim(p_cedula),''),nss=nullif(trim(p_nss),''),
      birth_date=p_birth,sex=p_sex,phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),''),
      ars_id=p_ars,member_number=nullif(trim(p_member),''),admin_notes=nullif(trim(p_notes),''),
      updated_at=now(),updated_by=auth.uid()
    where id=p_id returning id into v_patient;
  end if;

  insert into public.patient_global_links(global_patient_id,patient_id,organization_id)
  values(v_global,v_patient,p_org)
  on conflict(global_patient_id,organization_id) do update set patient_id=excluded.patient_id;

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
