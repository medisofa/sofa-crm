-- PENDIENTE de aplicar en producción. No fusionar así.
-- 274 · Regla de negocio (26/11/2026): el médico solo ve su información. Completa la 252 en lo que faltaba:
-- tarifas por médico, códigos de prestador, retiros, diferencias de tarifa y los archivos de claim-documents.
-- Solo restringe a médicos de clínicas (app.i_am_limited_client()); los demás no cambian.
begin;
do $dep$
begin
  if to_regprocedure('app.i_am_limited_client()') is null or to_regprocedure('app.client_line_ok(uuid)') is null then
    raise exception 'Falta la migración 252: aplíquela antes de la 274.';
  end if;
end $dep$;

drop policy if exists tariffs_clinica_propio on public.tariffs;
create policy tariffs_clinica_propio on public.tariffs as restrictive for all to authenticated
  using ((select app.i_am_limited_client()) is not true or app.client_provider_ok(provider_id))
  with check ((select app.i_am_limited_client()) is not true or app.client_provider_ok(provider_id));

drop policy if exists provider_ars_codes_clinica_propio on public.provider_ars_codes;
create policy provider_ars_codes_clinica_propio on public.provider_ars_codes as restrictive for all to authenticated
  using ((select app.i_am_limited_client()) is not true or app.client_provider_ok(provider_id))
  with check ((select app.i_am_limited_client()) is not true or app.client_provider_ok(provider_id));

drop policy if exists receptions_clinica_propio on public.receptions;
create policy receptions_clinica_propio on public.receptions as restrictive for all to authenticated
  using ((select app.i_am_limited_client()) is not true or app.client_provider_ok(provider_id))
  with check ((select app.i_am_limited_client()) is not true or app.client_provider_ok(provider_id));

drop policy if exists reception_items_clinica_propio on public.reception_items;
create policy reception_items_clinica_propio on public.reception_items as restrictive for all to authenticated
  using ((select app.i_am_limited_client()) is not true or app.client_line_ok(service_line_id))
  with check ((select app.i_am_limited_client()) is not true or app.client_line_ok(service_line_id));

drop policy if exists tariff_discrepancies_clinica_propio on public.tariff_discrepancies;
create policy tariff_discrepancies_clinica_propio on public.tariff_discrepancies as restrictive for all to authenticated
  using ((select app.i_am_limited_client()) is not true or app.client_line_ok(service_line_id))
  with check ((select app.i_am_limited_client()) is not true or app.client_line_ok(service_line_id));

-- Archivos: rutas org/lote/archivo u org/entidad/archivo. La función mira el lote sin RLS (si no, el lote
-- ajeno "no existiría" para el médico); null = la carpeta no es un lote.
create or replace function app.claim_file_lot_ok(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.client_provider_ok(s.provider_id) from public.submissions s
   where s.id = app.try_uuid((storage.foldername(p_name))[2]);
$$;
revoke all on function app.claim_file_lot_ok(text) from public, anon;
grant execute on function app.claim_file_lot_ok(text) to authenticated, service_role;

drop policy if exists sofa_claim_docs_clinica_ver on storage.objects;
create policy sofa_claim_docs_clinica_ver on storage.objects as restrictive for select to authenticated
  using (bucket_id <> 'claim-documents'
    or (select app.i_am_limited_client()) is not true
    or objects.owner = auth.uid()
    or coalesce(app.claim_file_lot_ok(objects.name), exists (select 1 from public.documents d where d.storage_path = objects.name)));

drop policy if exists sofa_claim_docs_clinica_subir on storage.objects;
create policy sofa_claim_docs_clinica_subir on storage.objects as restrictive for insert to authenticated
  with check (bucket_id <> 'claim-documents'
    or (select app.i_am_limited_client()) is not true
    or coalesce(app.claim_file_lot_ok(objects.name), true));

delete from app.schema_migrations where version = '274';
insert into app.schema_migrations (version, report) values ('274', jsonb_build_object('tema', 'el médico solo ve su información'));
commit;
