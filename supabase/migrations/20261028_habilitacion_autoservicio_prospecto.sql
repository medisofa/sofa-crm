-- 28/10/2026: autoservicio de habilitación para PROSPECTOS (lead, sin organización todavía).
-- El autoservicio ya existía para Clientes (client_habilitation/habilitation_item_submit vía
-- app.can(org,'client')); esto agrega el mismo camino para un prospecto dueño de su lead
-- (public.lead_users), sin tocar el de Cliente que ya funciona. Aplicado en producción
-- (Supabase, proyecto bpwjhgpzhzhiocoxrvzq) y registrado aquí para el historial.

create or replace function app.hab_access(p_case uuid, p_write boolean)
 returns habilitation_cases
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare c public.habilitation_cases;
begin
  select * into c from public.habilitation_cases where id = p_case;
  if c.id is null then raise exception 'Caso de habilitación no encontrado.' using errcode = 'P0002'; end if;
  if app.can_operator(c.operator_id, array['super_admin','admin','assistant','operations','auditor','billing','glosas']) then return c; end if;
  if c.organization_id is not null and app.can(c.organization_id, array['client']) then return c; end if;
  if c.lead_id is not null and exists (
    select 1 from public.lead_users lu where lu.lead_id = c.lead_id and lu.user_id = auth.uid() and lu.is_active
  ) then return c; end if;
  raise exception 'Sin acceso a este caso de habilitación.' using errcode = '42501';
end
$function$;

create or replace function public.habilitation_item_submit(p_item uuid, p_note text)
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
  update public.habilitation_items set client_note = left(trim(p_note), 500), client_submitted_at = now(), client_submitted_by = auth.uid() where id = p_item;
  if not exists (select 1 from public.tasks t where t.entity_type = 'habilitation' and t.entity_id = c.id and t.status = 'abierta' and t.title like 'Revisar entrega de habilitación%') then
    insert into public.tasks (operator_id, organization_id, title, priority, due_date, entity_type, entity_id, notes)
    values (c.operator_id, c.organization_id, left(format('Revisar entrega de habilitación %s · %s', coalesce(c.folio, ''), c.establishment_name), 200), 'media', current_date + 2,
            'habilitation', c.id, 'El cliente/prospecto marcó requisitos como entregados. Revíselos y cambie su color en Habilitación.');
  end if;
end
$function$;

-- Equivalente de client_habilitation(p_org) pero para el prospecto autenticado: resuelve su
-- propio lead (igual que prospect_portal()) y expone el checklist de sus casos de habilitación.
create or replace function public.prospect_habilitation()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare l public.leads;
begin
  select le.* into l from public.lead_users lu join public.leads le on le.id = lu.lead_id
   where lu.user_id = auth.uid() and lu.is_active and le.converted_org_id is null limit 1;
  if not found then
    raise exception 'Su usuario no está vinculado a un prospecto activo.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'folio', c.folio, 'name', c.establishment_name, 'type', c.establishment_type, 'kind', c.case_kind,
      'stage', c.stage, 'stage_label', app.hab_stage_label(c.stage), 'target_date', c.target_date,
      'counts', (select jsonb_build_object('verde', count(*) filter (where status = 'verde'), 'amarillo', count(*) filter (where status = 'amarillo'),
                   'rojo', count(*) filter (where status = 'rojo'), 'pendiente', count(*) filter (where status = 'pendiente'),
                   'applicable', count(*) filter (where status <> 'no_aplica'), 'critical_open', count(*) filter (where is_critical and status in ('pendiente','amarillo','rojo')))
                 from public.habilitation_items where case_id = c.id),
      'areas', (select jsonb_agg(jsonb_build_object('area', a.area, 'items', a.items) order by a.area) from (
                  select i.area, jsonb_agg(jsonb_build_object('id', i.id, 'requirement', i.requirement, 'status', i.status, 'critical', i.is_critical, 'due_on', i.due_on,
                           'hint', r.evidence_hint, 'client_note', i.client_note, 'submitted_at', i.client_submitted_at,
                           'can_submit', i.status in ('pendiente','amarillo','rojo')) order by i.sort_order) items
                    from public.habilitation_items i left join public.habilitation_requirements r on r.id = i.requirement_id
                   where i.case_id = c.id and i.status <> 'no_aplica' group by i.area) a)) order by c.created_at desc)
     from public.habilitation_cases c where c.lead_id = l.id and c.stage <> 'cancelado'), '[]'::jsonb);
end
$function$;

revoke all on function public.prospect_habilitation() from public, anon;
grant execute on function public.prospect_habilitation() to authenticated;
