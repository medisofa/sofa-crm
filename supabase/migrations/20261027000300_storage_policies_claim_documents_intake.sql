-- ============================================================================
-- 20261027000300_storage_policies_claim_documents_intake.sql
-- Cierra el segundo hallazgo CRÍTICO del informe de vigilancia del 27 oct 2026:
-- storage.objects no tenía NINGUNA política para claim-documents ni intake
-- (el borrador que las daba sin alcance por organización se revirtió el 26
-- oct y nunca se reemplazó por una versión correcta).
--
-- Sigue el mismo patrón ya probado y en producción para el bucket "contracts"
-- (ver 218_client_contract_upload.sql y 232_capturer_client_documents.sql):
-- app.can(org_id, roles) comprobando el primer segmento de la ruta.
--
-- Verificación de rutas reales (sesión del 27 oct 2026):
--  - claim-documents: js/services/documents.js sube a
--    `{organization_id}/{entity_id}/{uuid}-{archivo}` → primer segmento = la
--    organización CLIENTE. Acceso: cualquier rol con membresía activa en esa
--    organización (el menú/rol ya decide quién ve el botón de subir; aquí
--    solo se evita la fuga entre organizaciones).
--  - intake: solicitud.html sube con una ruta `{operator_id}/{upload_key}/...`
--    que el propio servidor entrega (rutaBase = data.ruta_base), ANTES de
--    llamar a service_request_doc_register. anon SÍ necesita subir aquí
--    (es el formulario público de solicitud), por eso la política de INSERT
--    valida contra public.service_requests (misma solicitud, vigente, no
--    cerrada) en vez de requerir sesión. La lectura (staff viendo adjuntos,
--    js/modules/solicitudes.js) sí requiere sesión y rol en el operador.
-- ============================================================================

begin;

drop policy if exists sofa_intake_insert_anon on storage.objects;
drop function if exists app.intake_upload_allowed(uuid, text);

-- Helper SECURITY DEFINER: anon no tiene (ni debe tener) SELECT sobre
-- public.service_requests (solo existe la política service_requests_staff,
-- para authenticated). Sin esto, la política de storage.objects de abajo
-- nunca vería la fila aunque exista, porque la subconsulta corre bajo el
-- RLS del rol que llama. Mismo patrón que app.intake_by_token.
--
-- Recibe el operador como TEXT (no uuid) y convierte adentro: la política
-- de abajo corre para anon, y anon no tiene (ni debe tener) EXECUTE directo
-- sobre app.try_uuid tras cerrar el hallazgo #1 (revoke_anon_default_execute).
-- Al convertir aquí dentro, esa conversión corre con los privilegios de esta
-- función SECURITY DEFINER, no con los del llamador.
create or replace function app.intake_upload_allowed(p_operator text, p_upload_key text)
 returns boolean
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_operator uuid;
begin
  begin
    v_operator := p_operator::uuid;
  exception when others then
    return false;
  end;
  return exists (
    select 1 from public.service_requests sr
     where sr.operator_id = v_operator
       and sr.upload_key = p_upload_key
       and sr.expires_at > now()
       and sr.status not in ('convertida', 'descartada')
  );
end;
$function$;

revoke all on function app.intake_upload_allowed(text, text) from public;
grant execute on function app.intake_upload_allowed(text, text) to anon, authenticated;

-- claim-documents: cualquier miembro activo de la organización dueña del documento.
drop policy if exists sofa_claim_documents_insert on storage.objects;
create policy sofa_claim_documents_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'claim-documents'
  and app.can(app.try_uuid((storage.foldername(name))[1]))
);

drop policy if exists sofa_claim_documents_select on storage.objects;
create policy sofa_claim_documents_select
on storage.objects
for select to authenticated
using (
  bucket_id = 'claim-documents'
  and app.can(app.try_uuid((storage.foldername(name))[1]))
);

drop policy if exists sofa_claim_documents_delete on storage.objects;
create policy sofa_claim_documents_delete
on storage.objects
for delete to authenticated
using (
  bucket_id = 'claim-documents'
  and app.can(app.try_uuid((storage.foldername(name))[1]))
);

-- intake: subida pública solo si la ruta corresponde a una solicitud vigente y no cerrada.
drop policy if exists sofa_intake_insert_anon on storage.objects;
create policy sofa_intake_insert_anon
on storage.objects
for insert to anon, authenticated
with check (
  bucket_id = 'intake'
  and app.intake_upload_allowed((storage.foldername(name))[1], (storage.foldername(name))[2])
);

-- intake: lectura solo para personal con membresía en el operador dueño de la solicitud.
drop policy if exists sofa_intake_select_staff on storage.objects;
create policy sofa_intake_select_staff
on storage.objects
for select to authenticated
using (
  bucket_id = 'intake'
  and app.can(app.try_uuid((storage.foldername(name))[1]))
);

commit;
