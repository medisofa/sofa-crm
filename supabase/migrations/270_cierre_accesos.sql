-- Ya aplicado en producción (26/11/2026). Se guarda aquí como documentación.
-- 270 · Cierre de seguridad: accesos desactivados y carpetas de habilitación.
-- 1) patient_access, payments_read_ok, payments_write_ok y storage_usage_org aceptaban una asignación de secretaría
--    aunque la persona o su membresía estuvieran desactivadas.
-- 2) habilitation-documents/prospects/ se leía y escribía con cualquier sesión.
-- 3) habilitation-documents/clients/ no miraba si el acceso seguía activo.
-- Idempotente. No borra datos ni usuarios.
begin;

do $dep$
begin
  if to_regprocedure('app.hab_access(uuid,boolean)') is null or to_regprocedure('app.role_for_org(uuid)') is null
     or to_regclass('public.lead_users') is null or to_regclass('public.capturer_scopes') is null then
    raise exception 'Falta una dependencia de la 270: aplique antes las migraciones anteriores.';
  end if;
end $dep$;

/* Asignación de secretaría que sigue viva: membresía «capturer» activa y perfil activo. */
create or replace function app.live_capturer_scopes(p_user uuid)
returns setof public.capturer_scopes language sql stable security definer set search_path = '' as $$
  select cs.* from public.capturer_scopes cs
    join public.organization_users ou on ou.user_id = cs.user_id and ou.organization_id = cs.organization_id
         and ou.role_code = 'capturer' and ou.is_active
    join public.profiles p on p.id = cs.user_id and p.is_active
   where cs.user_id = p_user;
$$;
revoke all on function app.live_capturer_scopes(uuid) from public, anon, authenticated;

create or replace function app.patient_access(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $function$
  select app.can(p_org, array['super_admin','admin','client'])
      or exists (select 1 from app.live_capturer_scopes(app.view_as_user()) cs where cs.organization_id = p_org);
$function$;

create or replace function app.payments_read_ok(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $function$
  select app.can(p_org, array['super_admin','admin','operations','billing','auditor','client'])
      or exists (select 1 from app.live_capturer_scopes(auth.uid()) cs where cs.organization_id = p_org);
$function$;

create or replace function app.payments_write_ok(p_provider uuid)
returns boolean language sql stable security definer set search_path = '' as $function$
  select exists (
    select 1 from public.providers p where p.id = p_provider and (
         app.can(p.organization_id, array['super_admin','admin'])
      or app.can(p.organization_id, array['client'])
      or exists (select 1 from app.live_capturer_scopes(auth.uid()) cs where cs.provider_id = p_provider and cs.can_payments)
    )
  );
$function$;

-- storage_usage_org se parcha sobre su definición vigente (si el ancla no aparece, aborta).
do $mig$
declare v text; v_new text;
begin
  select pg_get_functiondef('public.storage_usage_org(uuid)'::regprocedure) into v;
  if position('live_capturer_scopes' in v) = 0 then
    v_new := replace(v, 'from public.capturer_scopes cs where cs.user_id = auth.uid() and cs.organization_id = p_org',
                        'from app.live_capturer_scopes(auth.uid()) cs where cs.organization_id = p_org');
    if v_new = v then raise exception '270: no se encontró el ancla en storage_usage_org'; end if;
    execute v_new;
  end if;
end $mig$;

/* Carpeta prospects/{requisito}/…: personal de SOFA del operador, el prospecto de ese caso o el médico del consultorio ya convertido. */
create or replace function app.hab_prospect_doc_ok(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.habilitation_items i join public.habilitation_cases c on c.id = i.case_id
     where i.id = app.try_uuid(split_part(p_name, '/', 2))
       and (   app.can_operator(c.operator_id, array['super_admin','admin','assistant','operations','auditor','billing','glosas'])
            or (c.organization_id is not null and app.can(c.organization_id, array['client']))
            or exists (select 1 from public.lead_users lu join public.profiles p on p.id = lu.user_id and p.is_active
                        where lu.lead_id = c.lead_id and lu.user_id = auth.uid() and lu.is_active)));
$$;
revoke all on function app.hab_prospect_doc_ok(text) from public, anon;
grant execute on function app.hab_prospect_doc_ok(text) to authenticated;

drop policy if exists prospect_hab_docs_insert on storage.objects;
create policy prospect_hab_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'habilitation-documents' and split_part(name, '/', 1) = 'prospects' and app.hab_prospect_doc_ok(name));
drop policy if exists prospect_hab_docs_select on storage.objects;
create policy prospect_hab_docs_select on storage.objects for select to authenticated
  using (bucket_id = 'habilitation-documents' and split_part(name, '/', 1) = 'prospects' and app.hab_prospect_doc_ok(name));

/* Carpeta clients/{consultorio}/…: el médico con acceso vigente. */
drop policy if exists client_hab_docs_insert on storage.objects;
create policy client_hab_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'habilitation-documents' and split_part(name, '/', 1) = 'clients'
              and app.role_for_org(app.try_uuid(split_part(name, '/', 2))) = 'client');
drop policy if exists client_hab_docs_select on storage.objects;
create policy client_hab_docs_select on storage.objects for select to authenticated
  using (bucket_id = 'habilitation-documents' and split_part(name, '/', 1) = 'clients'
         and app.role_for_org(app.try_uuid(split_part(name, '/', 2))) = 'client');

/* …y el personal de SOFA con membresía y perfil activos (mismos roles que antes). */
create or replace function app.hab_staff_reader()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organization_users ou join public.profiles p on p.id = ou.user_id and p.is_active
                  where ou.user_id = auth.uid() and ou.is_active
                    and ou.role_code in ('assistant','operations','admin','super_admin','auditor','billing','glosas'));
$$;
revoke all on function app.hab_staff_reader() from public, anon;
grant execute on function app.hab_staff_reader() to authenticated;
drop policy if exists sofa_hab_client_docs_select on storage.objects;
create policy sofa_hab_client_docs_select on storage.objects for select to authenticated
  using (bucket_id = 'habilitation-documents' and split_part(name, '/', 1) = 'clients' and app.hab_staff_reader());

delete from app.schema_migrations where version = '270';
insert into app.schema_migrations (version, report) values ('270', jsonb_build_object('tema', 'cierre de seguridad: accesos desactivados y habilitación'));
commit;
