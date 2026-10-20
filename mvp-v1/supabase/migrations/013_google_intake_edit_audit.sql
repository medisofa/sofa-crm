-- SOFA · Bitácora de correcciones en carga Google Sheets / Form
create or replace function public.log_google_intake_edit(
  p_record_id text,
  p_org uuid,
  p_before jsonb,
  p_after jsonb,
  p_fields text[]
)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id bigint;
begin
  if auth.uid() is null then
    raise exception 'Inicia sesión para registrar la corrección.' using errcode='42501';
  end if;

  if not app.is_staff(array['super_admin','admin','operations','billing']) then
    raise exception 'Su rol no puede corregir cargas externas de Facturación ARS.' using errcode='42501';
  end if;

  if p_org is not null and p_org not in (select app.visible_org_ids()) then
    raise exception 'No tiene acceso al cliente asociado a esta fila.' using errcode='42501';
  end if;

  if length(trim(coalesce(p_record_id,''))) < 3 then
    raise exception 'Identificador de fila inválido.' using errcode='22023';
  end if;

  if coalesce(cardinality(p_fields),0)=0 then
    raise exception 'No hay campos modificados para registrar.' using errcode='22023';
  end if;

  insert into public.audit_log(
    user_id, organization_id, table_name, record_id, operation, old_values, new_values
  )
  values(
    auth.uid(),
    p_org,
    'google_claim_intake',
    left(trim(p_record_id),160),
    'CORRECCION_CARGA_EXTERNA',
    jsonb_build_object('fields',to_jsonb(p_fields),'values',coalesce(p_before,'{}'::jsonb)),
    jsonb_build_object('fields',to_jsonb(p_fields),'values',coalesce(p_after,'{}'::jsonb),'source','Google Sheets/Form','at',now())
  )
  returning id into v_id;

  return v_id;
end
$$;

revoke all on function public.log_google_intake_edit(text,uuid,jsonb,jsonb,text[]) from public,anon;
grant execute on function public.log_google_intake_edit(text,uuid,jsonb,jsonb,text[]) to authenticated;

create or replace function public.log_google_intake_import(
  p_record_id text,
  p_org uuid,
  p_claim uuid,
  p_folio text
)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id bigint;
begin
  if auth.uid() is null then
    raise exception 'Inicia sesión para registrar la importación.' using errcode='42501';
  end if;

  if not app.is_staff(array['super_admin','admin','operations','billing']) then
    raise exception 'Su rol no puede importar cargas externas de Facturación ARS.' using errcode='42501';
  end if;

  if p_org is null or p_org not in (select app.visible_org_ids()) then
    raise exception 'No tiene acceso al cliente asociado a esta fila.' using errcode='42501';
  end if;

  insert into public.audit_log(
    user_id, organization_id, table_name, record_id, operation, old_values, new_values
  )
  values(
    auth.uid(),
    p_org,
    'google_claim_intake',
    left(trim(p_record_id),160),
    'IMPORTACION_CARGA_EXTERNA',
    null,
    jsonb_build_object('claim_id',p_claim,'folio',p_folio,'source','Google Sheets/Form','at',now())
  )
  returning id into v_id;

  return v_id;
end
$$;

revoke all on function public.log_google_intake_import(text,uuid,uuid,text) from public,anon;
grant execute on function public.log_google_intake_import(text,uuid,uuid,text) to authenticated;
