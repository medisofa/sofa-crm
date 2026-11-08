-- 07/11/2026: nota de SOFA al descartar una entrega del cliente en habilitación.
-- Cuando el equipo SOFA descarta una entrega incorrecta puede dejar un comentario
-- ("El exequátur debe estar firmado y sellado") que el cliente ve en el formulario
-- de re-envío.  Al volver a someter el requisito, la nota se borra automáticamente.
--
-- Cambios:
--   1. Nueva columna habilitation_items.sofa_reset_note text
--   2. habilitation_item_reset_client(p_item, p_note default null): guarda la nota
--   3. habilitation_item_submit(…): limpia sofa_reset_note al re-someter
--   4. client_habilitation: expone sofa_reset_note por ítem
--   5. prospect_habilitation: expone sofa_reset_note por ítem
-- NOTA: ya aplicado en producción (2026-11-07) ✓

-- 1. Columna
alter table public.habilitation_items
  add column if not exists sofa_reset_note text;

-- 2. habilitation_item_reset_client con nota opcional
create or replace function public.habilitation_item_reset_client(
  p_item uuid,
  p_note text default null
)
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
         client_file_name    = null,
         sofa_reset_note     = nullif(left(trim(coalesce(p_note, '')), 500), '')
   where id = p_item;
  return old_path;
end
$function$;

revoke all on function public.habilitation_item_reset_client(uuid, text) from public, anon;
grant execute on function public.habilitation_item_reset_client(uuid, text) to authenticated;

-- 3. habilitation_item_submit: limpia sofa_reset_note al re-someter
create or replace function public.habilitation_item_submit(
  p_item         uuid,
  p_note         text,
  p_storage_path text   default null,
  p_file_name    text   default null
)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare i public.habilitation_items; c public.habilitation_cases;
begin
  select * into i from public.habilitation_items where id = p_item;
  if i.id is null then raise exception 'Requisito no encontrado.' using errcode = 'P0002'; end if;
  c := app.hab_access(i.case_id, true);
  if i.status not in ('pendiente','amarillo','rojo') then raise exception 'Este requisito ya está listo o no aplica.' using errcode = '23514'; end if;
  if length(trim(coalesce(p_note, ''))) < 5 then raise exception 'Cuente qué entregó y cómo (por ejemplo: «copia del exequátur enviada por WhatsApp»).' using errcode = '22023'; end if;
  update public.habilitation_items
     set client_note           = left(trim(p_note), 500),
         client_submitted_at   = now(),
         client_submitted_by   = auth.uid(),
         client_storage_path   = p_storage_path,
         client_file_name      = p_file_name,
         sofa_reset_note       = null
   where id = p_item;
  if not exists (
    select 1 from public.tasks t
     where t.entity_type = 'habilitation'
       and t.entity_id   = c.id
       and t.status      = 'abierta'
       and t.title like 'Revisar entrega de habilitación%'
  ) then
    insert into public.tasks (operator_id, organization_id, title, priority, due_date, entity_type, entity_id, notes)
    values (c.operator_id, c.organization_id,
            left(format('Revisar entrega de habilitación %s · %s', coalesce(c.folio, ''), c.establishment_name), 200),
            'media', current_date + 2,
            'habilitation', c.id,
            'El cliente/prospecto marcó requisitos como entregados. Revíselos y cambie su color en Habilitación.');
  end if;
end
$function$;

revoke all on function public.habilitation_item_submit(uuid, text, text, text) from public, anon;
grant execute on function public.habilitation_item_submit(uuid, text, text, text) to authenticated;

-- 4. client_habilitation con sofa_reset_note
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
             jsonb_build_object('area', a.area, 'items', a.items)
             order by a.area
           )
           from (
             select i.area,
                    jsonb_agg(
                      jsonb_build_object(
                        'id',              i.id,
                        'requirement',     i.requirement,
                        'status',          i.status,
                        'critical',        i.is_critical,
                        'due_on',          i.due_on,
                        'hint',            r.evidence_hint,
                        'notes',           i.notes,
                        'client_note',     i.client_note,
                        'submitted_at',    i.client_submitted_at,
                        'storage_path',    i.client_storage_path,
                        'file_name',       i.client_file_name,
                        'sofa_reset_note', i.sofa_reset_note,
                        'can_submit',      i.status in ('pendiente','amarillo','rojo')
                      ) order by i.sort_order
                    ) items
               from public.habilitation_items i
               left join public.habilitation_requirements r on r.id = i.requirement_id
              where i.case_id = c.id and i.status <> 'no_aplica'
              group by i.area
           ) a
         )
       ) order by c.created_at desc
     )
     from public.habilitation_cases c
    where c.organization_id = p_org and c.stage <> 'cancelado'),
    '[]'::jsonb
  );
end
$function$;

revoke all on function public.client_habilitation(uuid) from public, anon;
grant execute on function public.client_habilitation(uuid) to authenticated;

-- 5. prospect_habilitation con sofa_reset_note
create or replace function public.prospect_habilitation()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare l public.leads;
begin
  select le.* into l from public.lead_users lu
    join public.leads le on le.id = lu.lead_id
   where lu.user_id = auth.uid() and lu.is_active and le.converted_org_id is null
   limit 1;
  if not found then
    raise exception 'Su usuario no está vinculado a un prospecto activo.' using errcode = '42501';
  end if;
  return coalesce(
    (select jsonb_agg(
       jsonb_build_object(
         'id',          c.id,
         'folio',       c.folio,
         'name',        c.establishment_name,
         'type',        c.establishment_type,
         'kind',        c.case_kind,
         'stage',       c.stage,
         'stage_label', app.hab_stage_label(c.stage),
         'target_date', c.target_date,
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
             jsonb_build_object('area', a.area, 'items', a.items)
             order by a.area
           )
           from (
             select i.area,
                    jsonb_agg(
                      jsonb_build_object(
                        'id',              i.id,
                        'requirement',     i.requirement,
                        'status',          i.status,
                        'critical',        i.is_critical,
                        'due_on',          i.due_on,
                        'hint',            r.evidence_hint,
                        'client_note',     i.client_note,
                        'submitted_at',    i.client_submitted_at,
                        'storage_path',    i.client_storage_path,
                        'file_name',       i.client_file_name,
                        'sofa_reset_note', i.sofa_reset_note,
                        'can_submit',      i.status in ('pendiente','amarillo','rojo')
                      ) order by i.sort_order
                    ) items
               from public.habilitation_items i
               left join public.habilitation_requirements r on r.id = i.requirement_id
              where i.case_id = c.id and i.status <> 'no_aplica'
              group by i.area
           ) a
         )
       ) order by c.created_at desc
     )
     from public.habilitation_cases c
    where c.lead_id = l.id and c.stage <> 'cancelado'),
    '[]'::jsonb
  );
end
$function$;

revoke all on function public.prospect_habilitation() from public, anon;
grant execute on function public.prospect_habilitation() to authenticated;
