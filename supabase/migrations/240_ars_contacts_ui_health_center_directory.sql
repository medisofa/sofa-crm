-- 240 · Contactos de ARS (teléfono/whatsapp/email en ficha), directorio de centros de salud
-- YA APLICADO EN PRODUCCIÓN (2026-11-19 vía mcp__Supabase__apply_migration).
-- Requiere: ars_contacts (228), ars_save con tarifa de sociedad (20261115), health_centers (226).
-- Idempotente.
-- Incluye limpieza del overload viejo de save_health_center(uuid,uuid,text,text,boolean).

-- A) Nuevas columnas en la tabla ARS: teléfono, WhatsApp, correo
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='ars' and column_name='phone') then
    alter table public.ars add column phone text check (phone is null or length(btrim(phone)) <= 40);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='ars' and column_name='whatsapp') then
    alter table public.ars add column whatsapp text check (whatsapp is null or length(btrim(whatsapp)) <= 40);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='ars' and column_name='contact_email') then
    alter table public.ars add column contact_email text check (contact_email is null or contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
  end if;
end $$;

-- B) Nuevas columnas en health_centers: directorio de centros de salud
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='health_centers' and column_name='address') then
    alter table public.health_centers add column address text check (address is null or length(address) <= 300);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='health_centers' and column_name='city') then
    alter table public.health_centers add column city text check (city is null or length(city) <= 100);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='health_centers' and column_name='phone') then
    alter table public.health_centers add column phone text check (phone is null or length(btrim(phone)) <= 40);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='health_centers' and column_name='contact_name') then
    alter table public.health_centers add column contact_name text check (contact_name is null or length(contact_name) <= 160);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='health_centers' and column_name='contact_email') then
    alter table public.health_centers add column contact_email text check (contact_email is null or contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='health_centers' and column_name='center_type') then
    alter table public.health_centers add column center_type text check (center_type is null or length(center_type) <= 80);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='health_centers' and column_name='notes') then
    alter table public.health_centers add column notes text check (notes is null or length(notes) <= 2000);
  end if;
end $$;

-- C) ars_save — reemplazar con soporte para phone/whatsapp/contact_email
drop function if exists public.ars_save(uuid, text, text, text, text, text, boolean);
drop function if exists public.ars_save(uuid, text, text, text, text, text, boolean, text);
drop function if exists public.ars_save(uuid, text, text, text, text, text, boolean, text, boolean, text);

create or replace function public.ars_save(
  p_id uuid default null, p_name text default null, p_code text default null,
  p_regime text default null, p_channel text default null, p_notes text default null,
  p_active boolean default null, p_portal_url text default null,
  p_uses_society_tariff boolean default null, p_society_tariff_notes text default null,
  p_phone text default null, p_whatsapp text default null, p_contact_email text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_name text := nullif(regexp_replace(trim(coalesce(p_name,'')),'\s+',' ','g'),'');
  v_code text := nullif(lower(regexp_replace(trim(coalesce(p_code,'')), '[^A-Za-z0-9]+','_','g')),'');
  v_url text := nullif(trim(coalesce(p_portal_url,'')),'');
  v_soc_notes text := nullif(trim(coalesce(p_society_tariff_notes,'')),'');
  v_phone text := nullif(trim(coalesce(p_phone,'')),'');
  v_wa text := nullif(trim(coalesce(p_whatsapp,'')),'');
  v_email text := nullif(trim(coalesce(p_contact_email,'')),'');
begin
  perform app.ars_admin_require();
  if v_name is null then raise exception 'El nombre de la ARS no puede estar vacío.' using errcode='22023'; end if;
  if char_length(v_name) < 2 then raise exception 'El nombre debe tener al menos 2 caracteres.' using errcode='22023'; end if;
  if p_regime is not null and p_regime not in ('Contributivo','Subsidiado','Pensionados','Plan voluntario') then
    raise exception 'Régimen inválido: %', p_regime using errcode='22023';
  end if;
  if v_email is not null and v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'El correo «%» no tiene un formato válido.', v_email using errcode='22023';
  end if;
  if p_id is null then
    if v_code is not null and exists (select 1 from public.ars where code = v_code) then
      raise exception 'Ya existe una ARS con el código «%».', v_code using errcode='23505';
    end if;
    insert into public.ars (code, name, regime_default, submission_channel, notes, portal_url,
                            uses_society_tariff, society_tariff_notes,
                            phone, whatsapp, contact_email, is_active, updated_at, updated_by)
    values (v_code, v_name, coalesce(p_regime,'Contributivo'), nullif(trim(coalesce(p_channel,'')),''),
            nullif(trim(coalesce(p_notes,'')),''), v_url, coalesce(p_uses_society_tariff,false), v_soc_notes,
            v_phone, v_wa, v_email, coalesce(p_active,true), now(), auth.uid())
    returning id into v_id;
  else
    update public.ars set name=v_name, regime_default=coalesce(p_regime,regime_default),
      submission_channel=nullif(trim(coalesce(p_channel,'')),''), notes=nullif(trim(coalesce(p_notes,'')),''),
      portal_url=case when p_portal_url is not null then v_url else portal_url end,
      uses_society_tariff=coalesce(p_uses_society_tariff,uses_society_tariff),
      society_tariff_notes=case when p_society_tariff_notes is not null then v_soc_notes else society_tariff_notes end,
      phone=case when p_phone is not null then v_phone else phone end,
      whatsapp=case when p_whatsapp is not null then v_wa else whatsapp end,
      contact_email=case when p_contact_email is not null then v_email else contact_email end,
      is_active=coalesce(p_active,is_active), updated_at=now(), updated_by=auth.uid()
    where id=p_id returning id into v_id;
    if v_id is null then raise exception 'ARS no encontrada.' using errcode='02000'; end if;
  end if;
  return v_id;
end $$;

-- D) ars_catalog — incluir phone, whatsapp, contact_email
create or replace function public.ars_catalog(p_include_inactive boolean default false)
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', a.id, 'code', a.code, 'name', a.name,
      'regime', a.regime_default, 'channel', a.submission_channel,
      'notes', a.notes, 'portal_url', a.portal_url,
      'uses_society_tariff', a.uses_society_tariff, 'society_tariff_notes', a.society_tariff_notes,
      'phone', a.phone, 'whatsapp', a.whatsapp, 'contact_email', a.contact_email,
      'active', a.is_active,
      'tariffs', (select count(*) from public.tariffs t where t.ars_id = a.id and t.valid_during @> current_date),
      'plans', coalesce(
        (select jsonb_agg(
            jsonb_build_object('id', p.id, 'name', p.name, 'regime', p.regime, 'notes', p.notes,
              'active', p.is_active, 'sort', p.sort_order,
              'tariffs', (select count(*) from public.tariffs t where t.plan_id = p.id and t.valid_during @> current_date)
            ) order by p.sort_order, p.name)
         from public.ars_plans p where p.ars_id = a.id and (p_include_inactive or p.is_active)), '[]'::jsonb))
    order by a.is_active desc, a.name
  ), '[]'::jsonb)
  from public.ars a where app.is_active_user() and (p_include_inactive or a.is_active);
$$;

-- E) save_health_center — extender con los campos del directorio
-- Limpieza del overload viejo
drop function if exists public.save_health_center(uuid, uuid, text, text, boolean);

create or replace function public.save_health_center(
  p_id uuid, p_org uuid, p_name text,
  p_tax_id text default null, p_active boolean default true,
  p_address text default null, p_city text default null, p_phone text default null,
  p_contact_name text default null, p_contact_email text default null,
  p_center_type text default null, p_notes text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_tax text := nullif(trim(coalesce(p_tax_id,'')),'');
        v_email text := nullif(trim(coalesce(p_contact_email,'')),'');
begin
  if exists(select 1 from public.support_view_active()) then
    raise exception 'El modo soporte es de solo lectura.' using errcode='42501';
  end if;
  if not app.can(p_org, array['super_admin','admin','client','operations']) then
    raise exception 'Solo el médico, Administración u Operaciones pueden registrar centros.' using errcode='42501';
  end if;
  if p_name is null or length(trim(p_name)) < 3 then
    raise exception 'Escriba el nombre del centro (mínimo 3 letras).' using errcode='22023';
  end if;
  if v_tax is not null then
    v_tax := regexp_replace(translate(v_tax, '-‐‑‒–—―−', ''), '[[:space:]]', '', 'g');
    if v_tax !~ '^([0-9]{9}|[0-9]{11})$' then
      raise exception 'El RNC debe tener 9 dígitos o la cédula 11.' using errcode='22023';
    end if;
  end if;
  if v_email is not null and v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'El correo «%» no tiene un formato válido.', v_email using errcode='22023';
  end if;
  if p_id is null then
    insert into public.health_centers(organization_id, name, tax_id, is_active, created_by,
                                       address, city, phone, contact_name, contact_email, center_type, notes)
    values(p_org, trim(p_name), v_tax, coalesce(p_active,true), auth.uid(),
           nullif(trim(coalesce(p_address,'')),''), nullif(trim(coalesce(p_city,'')),''),
           nullif(trim(coalesce(p_phone,'')),''), nullif(trim(coalesce(p_contact_name,'')),''),
           v_email, nullif(trim(coalesce(p_center_type,'')),''), nullif(trim(coalesce(p_notes,'')),''))
    returning id into v_id;
  else
    update public.health_centers set
      name=trim(p_name), tax_id=v_tax, is_active=coalesce(p_active,true),
      address=case when p_address is not null then nullif(trim(p_address),'') else address end,
      city=case when p_city is not null then nullif(trim(p_city),'') else city end,
      phone=case when p_phone is not null then nullif(trim(p_phone),'') else phone end,
      contact_name=case when p_contact_name is not null then nullif(trim(p_contact_name),'') else contact_name end,
      contact_email=case when p_contact_email is not null then v_email else contact_email end,
      center_type=case when p_center_type is not null then nullif(trim(p_center_type),'') else center_type end,
      notes=case when p_notes is not null then nullif(trim(p_notes),'') else notes end
    where id=p_id and organization_id=p_org returning id into v_id;
    if v_id is null then
      raise exception 'El centro no existe en este cliente. Actualice la lista.' using errcode='P0002';
    end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'Ya existe un centro con ese nombre.' using errcode='23505';
end $$;

-- F) health_center_directory — lectura del directorio para el staff
create or replace function public.health_center_directory(
  p_org uuid default null, p_include_inactive boolean default false
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not app.is_active_user() then
    raise exception 'Inicia sesión para ver el directorio de centros.' using errcode='42501';
  end if;
  return jsonb_build_object(
    'centros', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', hc.id, 'organization_id', hc.organization_id,
               'name', hc.name, 'tax_id', hc.tax_id,
               'address', hc.address, 'city', hc.city,
               'phone', hc.phone, 'contact_name', hc.contact_name,
               'contact_email', hc.contact_email, 'center_type', hc.center_type,
               'notes', hc.notes, 'is_active', hc.is_active
             ) order by hc.name)
        from public.health_centers hc
        join app.visible_org_ids() v(id) on v.id = hc.organization_id
       where (p_org is null or hc.organization_id = p_org)
         and (p_include_inactive or hc.is_active)
    ), '[]'::jsonb));
end $$;

revoke all on function public.health_center_directory(uuid, boolean) from public, anon;
grant execute on function public.health_center_directory(uuid, boolean) to authenticated;

-- G) ars_contact_list — ocultar email a roles que no sean admin/super_admin
create or replace function public.ars_contact_list(p_ars uuid default null, p_only_active boolean default true)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_role text := app.ars_staff_require('leer');
        v_show_email boolean := v_role in ('super_admin','admin');
begin
  return jsonb_build_object(
    'puede_escribir', v_role <> 'auditor',
    'puede_administrar', v_role in ('super_admin','admin'),
    'contactos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'ars_id', c.ars_id, 'ars', a.name, 'area', c.area, 'name', c.name,
               'job_title', c.job_title, 'phone', c.phone,
               'email', case when v_show_email then c.email else null end,
               'notes', c.notes,
               'is_active', c.is_active, 'updated_at', c.updated_at
             ) order by a.name, c.is_active desc, c.area, c.name)
        from public.ars_contacts c join public.ars a on a.id = c.ars_id
       where (p_ars is null or c.ars_id = p_ars)
         and (not coalesce(p_only_active, true) or c.is_active)
    ), '[]'::jsonb));
end $$;

-- H) Permisos
do $$ declare f text; begin
  foreach f in array array[
    'public.ars_save(uuid,text,text,text,text,text,boolean,text,boolean,text,text,text,text)',
    'public.ars_catalog(boolean)',
    'public.save_health_center(uuid,uuid,text,text,boolean,text,text,text,text,text,text,text)',
    'public.health_center_directory(uuid,boolean)',
    'public.ars_contact_list(uuid,boolean)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

insert into app.schema_migrations (version, report)
select '240', jsonb_build_object('nombre','ars_contacts_ui_health_center_directory','nota','phone/whatsapp/email en ARS, directorio centros de salud, email restringido en contactos internos')
 where not exists (select 1 from app.schema_migrations where version = '240');
