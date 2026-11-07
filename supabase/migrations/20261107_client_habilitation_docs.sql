-- 07/11/2026: documentos adjuntos en Mi habilitación (clientes).
-- Extiende la vista client_habilitation para exponer client_storage_path y
-- client_file_name por ítem; el cliente puede adjuntar un archivo al marcar
-- un requisito como entregado (igual que ya funciona para prospectos).
-- Los archivos se guardan en el bucket privado "habilitation-documents" bajo
-- la ruta  clients/{org_id}/{item_id}/{uuid}-{nombre}.
-- Las columnas client_storage_path / client_file_name ya existen en
-- habilitation_items (20261107_prospect_habilitation_docs.sql).
-- NOTA: ya aplicado en producción (2026-11-07) ✓

-- 1. Reconstruir client_habilitation con los nuevos campos de documento
create or replace function public.client_habilitation(p_org uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if not app.can(p_org, array['client','assistant','operations','admin','super_admin','auditor','billing','glosas']) then
    raise exception 'Sin acceso a la habilitación de esta organización.' using errcode = '42501';
  end if;
  return coalesce(
    (select jsonb_agg(
      jsonb_build_object(
        'id',                  c.id,
        'folio',               c.folio,
        'name',                c.establishment_name,
        'type',                c.establishment_type,
        'kind',                c.case_kind,
        'stage',               c.stage,
        'stage_label',         app.hab_stage_label(c.stage),
        'target_date',         c.target_date,
        'license_valid_until', c.license_valid_until,
        'license_days_left',   (c.license_valid_until - current_date),
        'pss_code',            c.pss_code,
        'counts', (
          select jsonb_build_object(
            'verde',         count(*) filter (where status = 'verde'),
            'amarillo',      count(*) filter (where status = 'amarillo'),
            'rojo',          count(*) filter (where status = 'rojo'),
            'pendiente',     count(*) filter (where status = 'pendiente'),
            'applicable',    count(*) filter (where status <> 'no_aplica'),
            'critical_open', count(*) filter (where is_critical and status in ('pendiente','amarillo','rojo'))
          )
          from public.habilitation_items where case_id = c.id
        ),
        'areas', (
          select jsonb_agg(
            jsonb_build_object('area', a.area, 'items', a.items) order by a.area
          )
          from (
            select i.area,
                   jsonb_agg(
                     jsonb_build_object(
                       'id',           i.id,
                       'requirement',  i.requirement,
                       'status',       i.status,
                       'critical',     i.is_critical,
                       'due_on',       i.due_on,
                       'hint',         r.evidence_hint,
                       'notes',        i.notes,
                       'client_note',  i.client_note,
                       'submitted_at', i.client_submitted_at,
                       'storage_path', i.client_storage_path,
                       'file_name',    i.client_file_name,
                       'can_submit',   i.status in ('pendiente','amarillo','rojo')
                     ) order by i.sort_order
                   ) items
              from public.habilitation_items i
              left join public.habilitation_requirements r on r.id = i.requirement_id
             where i.case_id = c.id and i.status <> 'no_aplica'
             group by i.area
          ) a
        )
      )
    ) order by c.created_at desc
    from public.habilitation_cases c
   where c.organization_id = p_org and c.stage <> 'cancelado'),
    '[]'::jsonb
  );
end
$function$;

revoke all on function public.client_habilitation(uuid) from public, anon;
grant execute on function public.client_habilitation(uuid) to authenticated;

-- 2. Políticas de Storage para que clientes puedan subir y leer documentos
--    bajo el prefijo  clients/{org_id}/  del bucket "habilitation-documents".
--    El org_id en el segundo segmento del path debe coincidir con una
--    organización donde el usuario autenticado tenga rol 'client'.
--    (Si las políticas ya existen el CREATE POLICY fallará con un aviso inofensivo.)

-- INSERT
create policy "client_hab_docs_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'habilitation-documents'
    and split_part(name, '/', 1) = 'clients'
    and exists (
      select 1 from public.organization_users
       where organization_id = split_part(name, '/', 2)::uuid
         and user_id         = auth.uid()
         and role_code       = 'client'
    )
  );

-- SELECT
create policy "client_hab_docs_select"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'habilitation-documents'
    and split_part(name, '/', 1) = 'clients'
    and exists (
      select 1 from public.organization_users
       where organization_id = split_part(name, '/', 2)::uuid
         and user_id         = auth.uid()
         and role_code       = 'client'
    )
  );
