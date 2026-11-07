-- 07/11/2026: SOFA staff puede ver documentos subidos por clientes en Habilitación.
-- La política existente sofa_hab_docs_select usa foldername(name)[1] como org UUID,
-- lo que no aplica a rutas con prefijo literal "clients/" (clients/{org_id}/{item_id}/...).
-- Esta política adicional cubre ese prefijo para roles internos de SOFA.
-- NOTA: ya aplicado en producción (2026-11-07) ✓

create policy "sofa_hab_client_docs_select"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'habilitation-documents'
    and split_part(name, '/', 1) = 'clients'
    and exists (
      select 1 from public.organization_users
       where user_id   = auth.uid()
         and role_code in ('assistant','operations','admin','super_admin','auditor','billing','glosas')
    )
  );
