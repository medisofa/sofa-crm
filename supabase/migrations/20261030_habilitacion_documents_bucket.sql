-- Ya aplicado en producción (30/10/2026).
-- Bucket dedicado para evidencia de habilitación, separado de claim-documents (que comparte
-- regla de acceso con documentos de cobro). Mismo patrón de clinical-records: rol explícito,
-- enlace firmado corto (60 s en vez de 300 s).
--
-- Nota de alcance: esta migración NO mueve los archivos ya subidos. Cada documento ya existente
-- queda registrado con bucket='claim-documents' en su propia fila de "documents" y sigue
-- abriéndose desde ahí sin problema (documents.js respeta el bucket que cada fila declara).
-- Solo las evidencias que se suban de ahora en adelante van al bucket nuevo. Mover los objetos
-- históricos requiere copiarlos con la API de Storage (no solo SQL), y queda como una tarea
-- aparte si se decide hacerlo.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('habilitation-documents', 'habilitation-documents', false, 10485760, array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy sofa_hab_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'habilitation-documents' and app.can(app.try_uuid((storage.foldername(name))[1]), array['super_admin','admin','assistant']));

create policy sofa_hab_docs_select on storage.objects for select to authenticated
  using (bucket_id = 'habilitation-documents' and app.can(app.try_uuid((storage.foldername(name))[1]), array['super_admin','admin','assistant','billing','auditor','client']));

create policy sofa_hab_docs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'habilitation-documents' and app.can(app.try_uuid((storage.foldername(name))[1]), array['super_admin','admin']));
