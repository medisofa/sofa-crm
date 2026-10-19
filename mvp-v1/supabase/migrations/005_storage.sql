-- SOFA MVP v1 — Storage privado por reclamación.
-- Ruta obligatoria: <organization_id>/<claim_id>/<nombre-seguro>

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('sofa-claims-v1','sofa-claims-v1',false,15728640,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create policy "sofa_claims_v1_read"
on storage.objects for select to authenticated
using (
  bucket_id='sofa-claims-v1'
  and array_length(storage.foldername(name),1)>=2
  and exists(
    select 1 from public.claims_v1 c
    where c.organization_id=((storage.foldername(name))[1])::uuid
      and c.id=((storage.foldername(name))[2])::uuid
      and app.can_claim_v1(c.organization_id,c.provider_id,false)
  )
);

create policy "sofa_claims_v1_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id='sofa-claims-v1'
  and array_length(storage.foldername(name),1)>=2
  and exists(
    select 1 from public.claims_v1 c
    where c.organization_id=((storage.foldername(name))[1])::uuid
      and c.id=((storage.foldername(name))[2])::uuid
      and app.can_claim_v1(c.organization_id,c.provider_id,true)
  )
);
