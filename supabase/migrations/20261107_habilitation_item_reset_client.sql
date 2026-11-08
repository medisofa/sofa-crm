-- 07/11/2026: SOFA puede descartar una entrega del cliente en un requisito de habilitación.
-- Cuando el cliente sube un archivo o marca un requisito como "entregado" pero el contenido
-- es incorrecto o incompleto, el equipo SOFA puede borrar esa entrega para que el cliente
-- vuelva a someter el requisito.
-- La función devuelve el client_storage_path anterior para que el JS pueda borrar el archivo
-- del bucket "habilitation-documents" (si existía).
-- Solo los roles internos con acceso de edición (super_admin, admin, assistant, operations)
-- pueden llamar a esta función.
-- NOTA: ya aplicado en producción (2026-11-07) ✓

create or replace function public.habilitation_item_reset_client(p_item uuid)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  i        public.habilitation_items;
  c        public.habilitation_cases;
  old_path text;
begin
  select * into i from public.habilitation_items where id = p_item;
  if i.id is null then raise exception 'Requisito no encontrado.' using errcode = 'P0002'; end if;
  select * into c from public.habilitation_cases where id = i.case_id;
  if not app.can_operator(c.operator_id,
        array['super_admin','admin','assistant','operations']) then
    raise exception 'Solo el equipo SOFA puede descartar una entrega del cliente.'
      using errcode = '42501';
  end if;
  if i.client_submitted_at is null then
    raise exception 'Este requisito no tiene una entrega del cliente registrada.'
      using errcode = '23514';
  end if;
  old_path := i.client_storage_path;
  update public.habilitation_items
     set client_note         = null,
         client_submitted_at = null,
         client_submitted_by = null,
         client_storage_path = null,
         client_file_name    = null
   where id = p_item;
  return old_path;
end
$function$;

revoke all on function public.habilitation_item_reset_client(uuid) from public, anon;
grant execute on function public.habilitation_item_reset_client(uuid) to authenticated;
