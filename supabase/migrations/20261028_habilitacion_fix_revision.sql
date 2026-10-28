-- 28/10/2026: correcciones encontradas en la revisión de
-- 20261028_habilitacion_requisitos_renovacion_y_modificacion.sql, aplicadas en producción
-- y registradas aquí.

-- 1) Los 96 requisitos previos (apertura) quedaron con applies_to_kind por defecto incluyendo
--    'renovacion' y 'actualizacion', así que una renovación terminaba sumando el checklist
--    viejo de apertura ENCIMA de los 13 requisitos nuevos de renovación.
update public.habilitation_requirements
   set applies_to_kind = array['apertura']
 where code not like 'HAB-REN-%' and code not like 'HAB-MOD-%';

-- 2) p_subkind no se validaba contra los 6 motivos reales de Modificación; un valor no
--    reconocido creaba el caso igual, pero sin ninguno de los 20 requisitos correspondientes.
create or replace function public.create_habilitation_case(p_name text, p_type text, p_org uuid DEFAULT NULL::uuid, p_lead uuid DEFAULT NULL::uuid, p_kind text DEFAULT 'apertura'::text, p_fee numeric DEFAULT 0, p_target date DEFAULT NULL::date, p_notes text DEFAULT NULL::text, p_subkind text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_op uuid; v_id uuid := gen_random_uuid(); v_kind text := coalesce(p_kind, 'apertura'); v_subkind text := nullif(trim(coalesce(p_subkind, '')), '');
begin
  select id into v_op from app.my_operator_ids() as t(id) limit 1;
  if v_op is null then raise exception 'Solo el personal de SOFA abre casos de habilitación' using errcode = '42501'; end if;
  if length(trim(coalesce(p_name, ''))) < 3 then raise exception 'Indique el nombre del establecimiento' using errcode = '22023'; end if;
  if v_kind = 'actualizacion' then
    if v_subkind is null then raise exception 'Indique el motivo de la modificación' using errcode = '22023'; end if;
    if v_subkind not in ('ampliacion_servicios','cambio_nivel','cambio_nombre','cambio_propietario','cambio_director','cambio_razon_social') then
      raise exception 'Motivo de modificación no reconocido: %', v_subkind using errcode = '22023';
    end if;
  end if;
  insert into public.habilitation_cases (id, operator_id, organization_id, lead_id, establishment_name, establishment_type, case_kind, case_subkind, fee_amount, target_date, notes)
  values (v_id, v_op, p_org, p_lead, trim(p_name), p_type, v_kind, v_subkind, coalesce(p_fee, 0), p_target, nullif(trim(coalesce(p_notes, '')), ''));
  insert into public.habilitation_items (case_id, area, requirement_id, requirement, is_critical, sort_order, status)
  select v_id, r.area, r.id, r.requirement, r.is_critical, r.sort_order, 'pendiente'
    from public.habilitation_requirements r
   where r.is_active and p_type = any (r.applies_to) and v_kind = any (r.applies_to_kind)
     and (r.applies_to_subkind is null or v_subkind = any (r.applies_to_subkind));
  insert into public.activities (operator_id, organization_id, entity_type, entity_id, activity_type, body)
  values (v_op, p_org, 'habilitation', v_id, 'sistema', format('Caso de habilitación abierto: %s (%s, %s)', trim(p_name), p_type, v_kind));
  return v_id;
end $function$;

-- 3) v_habilitation_cases no traía case_subkind — ni la lista ni la ficha del caso podían
--    mostrar el motivo de una modificación (necesario ahora que cada motivo trae su propio
--    checklist y tarifa).
create or replace view public.v_habilitation_cases as
 SELECT c.id,
    c.operator_id,
    c.organization_id,
    o.legal_name AS client_name,
    c.lead_id,
    l.company AS lead_company,
    c.folio,
    c.establishment_name,
    c.establishment_type,
    c.case_kind,
    c.fee_amount,
    c.stage,
    app.hab_stage_label(c.stage) AS stage_name,
    c.opened_on,
    c.closed_on,
    c.target_date,
    c.target_date - CURRENT_DATE AS days_to_target,
    c.dgha_file_number,
    c.submitted_on,
    c.inspection_on,
    c.license_number,
    c.license_valid_until,
    c.license_valid_until - CURRENT_DATE AS license_days_left,
    c.pss_code,
    c.owner_id,
    pr.full_name AS owner_name,
    c.notes,
    c.stage_changed_at,
    c.created_at,
    c.updated_at,
    COALESCE(k.total, 0::bigint) AS items_total,
    COALESCE(k.applicable, 0::bigint) AS items_applicable,
    COALESCE(k.verde, 0::bigint) AS verde,
    COALESCE(k.amarillo, 0::bigint) AS amarillo,
    COALESCE(k.rojo, 0::bigint) AS rojo,
    COALESCE(k.pendiente, 0::bigint) AS pendiente,
    COALESCE(k.no_aplica, 0::bigint) AS no_aplica,
    COALESCE(k.critical_open, 0::bigint) AS critical_open,
        CASE
            WHEN COALESCE(k.applicable, 0::bigint) = 0 THEN 0::numeric
            ELSE round(100.0 * k.verde::numeric / k.applicable::numeric)
        END::integer AS ready_pct,
    c.case_subkind
   FROM habilitation_cases c
     LEFT JOIN organizations o ON o.id = c.organization_id
     LEFT JOIN leads l ON l.id = c.lead_id
     LEFT JOIN profiles pr ON pr.id = c.owner_id
     LEFT JOIN LATERAL ( SELECT count(*) AS total,
            count(*) FILTER (WHERE i.status <> 'no_aplica'::text) AS applicable,
            count(*) FILTER (WHERE i.status = 'verde'::text) AS verde,
            count(*) FILTER (WHERE i.status = 'amarillo'::text) AS amarillo,
            count(*) FILTER (WHERE i.status = 'rojo'::text) AS rojo,
            count(*) FILTER (WHERE i.status = 'pendiente'::text) AS pendiente,
            count(*) FILTER (WHERE i.status = 'no_aplica'::text) AS no_aplica,
            count(*) FILTER (WHERE i.is_critical AND (i.status = ANY (ARRAY['pendiente'::text, 'amarillo'::text, 'rojo'::text]))) AS critical_open
           FROM habilitation_items i
          WHERE i.case_id = c.id) k ON true;
