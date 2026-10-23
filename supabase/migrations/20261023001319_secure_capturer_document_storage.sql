-- SOFA: seguridad documental para capturistas
-- Requiere las tablas, funciones y políticas de migraciones anteriores.
-- No modifica datos ni concede permisos UPDATE/DELETE.

-- 1. Lectura de documentos organizacionales
DROP POLICY IF EXISTS
  client_contract_documents_select_capturer
ON public.documents;

CREATE POLICY client_contract_documents_select_capturer
ON public.documents
FOR SELECT TO authenticated
USING (
  app.can(organization_id, ARRAY['capturer']::text[])
  AND entity_type = 'organization'
  AND entity_id = organization_id
  AND document_type_code = ANY (
    ARRAY[
      'autorizacion_representacion',
      'carta_clinica',
      'carta_ars',
      'formulario_implementacion'
    ]::text[]
  )
);

-- 2. Inserción de metadatos documentales
DROP POLICY IF EXISTS
  client_contract_documents_insert_capturer
ON public.documents;

CREATE POLICY client_contract_documents_insert_capturer
ON public.documents
FOR INSERT TO authenticated
WITH CHECK (
  app.can(organization_id, ARRAY['capturer']::text[])
  AND uploaded_by = auth.uid()
  AND entity_type = 'organization'
  AND entity_id = organization_id
  AND service_line_id IS NULL
  AND document_type_code = ANY (
    ARRAY[
      'autorizacion_representacion',
      'carta_clinica',
      'carta_ars',
      'formulario_implementacion'
    ]::text[]
  )
);

-- 3. Descarga autenticada desde Storage
DROP POLICY IF EXISTS
  sofa_documents_download
ON storage.objects;

CREATE POLICY sofa_documents_download
ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id IN (
    'claim-documents', 'contracts', 'intake'
  )
  AND storage.allow_any_operation(
    ARRAY[
      'object.get_authenticated',
      'object.get_authenticated_info'
    ]::text[]
  )
  AND EXISTS (
    SELECT 1
    FROM public.documents d
    WHERE d.bucket = storage.objects.bucket_id
      AND d.storage_path = storage.objects.name
  )
);

-- 4. Carga de nuevos documentos operativos
DROP POLICY IF EXISTS
  sofa_capturer_upload
ON storage.objects;

CREATE POLICY sofa_capturer_upload
ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id IN ('contracts', 'intake')
  AND EXISTS (
    SELECT 1
    FROM public.documents d
    WHERE d.bucket = storage.objects.bucket_id
      AND d.storage_path = storage.objects.name
      AND d.uploaded_by = auth.uid()
      AND d.entity_type = 'organization'
      AND d.entity_id = d.organization_id
      AND d.service_line_id IS NULL
      AND d.organization_id IN (
        SELECT app.capturer_org_ids()
      )
      AND d.document_type_code = ANY (
        ARRAY[
          'autorizacion_representacion',
          'carta_clinica',
          'carta_ars',
          'formulario_implementacion'
        ]::text[]
      )
  )
);
