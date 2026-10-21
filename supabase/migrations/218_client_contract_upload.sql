-- 218 · El médico puede subir sus documentos A–E al expediente contractual de su propio cliente
begin;

drop policy if exists sofa_contracts_insert_client on storage.objects;
create policy sofa_contracts_insert_client
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'contracts'
  and app.can(
    app.try_uuid((storage.foldername(name))[1]),
    array['client']
  )
);

commit;
