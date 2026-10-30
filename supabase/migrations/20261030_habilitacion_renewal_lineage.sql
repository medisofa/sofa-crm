-- Ya aplicado en producción (30/10/2026).
-- Conteo de renovaciones: cada caso de renovación queda enlazado al caso anterior (licencia previa)
-- y lleva su número de secuencia (1 = apertura original, 2 = primera renovación, ...).
-- También expone los casos de habilitación de un prospecto (antes solo visibles desde Clientes),
-- para cerrar la brecha prospecto → habilitación → cliente.
alter table public.habilitation_cases
  add column if not exists renewal_of_case_id uuid references public.habilitation_cases(id),
  add column if not exists renewal_seq int not null default 1;

create index if not exists habilitation_cases_renewal_of_idx on public.habilitation_cases(renewal_of_case_id);

create or replace function public.create_habilitation_case(
  p_name text, p_type text, p_org uuid default null, p_lead uuid default null,
  p_kind text default 'apertura', p_fee numeric default 0, p_target date default null,
  p_notes text default null, p_subkind text default null, p_renewal_of uuid default null
)
returns uuid
language plpgsql
set search_path to ''
as $function$
declare v_op uuid; v_id uuid := gen_random_uuid(); v_kind text := coalesce(p_kind, 'apertura');
  v_subkind text := nullif(trim(coalesce(p_subkind, '')), ''); v_seq int := 1;
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
  if v_kind = 'renovacion' and p_renewal_of is not null then
    select renewal_seq + 1 into v_seq from public.habilitation_cases where id = p_renewal_of;
    v_seq := coalesce(v_seq, 1);
  end if;
  insert into public.habilitation_cases (id, operator_id, organization_id, lead_id, establishment_name, establishment_type, case_kind, case_subkind, fee_amount, target_date, notes, renewal_of_case_id, renewal_seq)
  values (v_id, v_op, p_org, p_lead, trim(p_name), p_type, v_kind, v_subkind, coalesce(p_fee, 0), p_target, nullif(trim(coalesce(p_notes, '')), ''), p_renewal_of, v_seq);
  insert into public.habilitation_items (case_id, area, requirement_id, requirement, is_critical, sort_order, status)
  select v_id, r.area, r.id, r.requirement, r.is_critical, r.sort_order, 'pendiente'
    from public.habilitation_requirements r
   where r.is_active and p_type = any (r.applies_to) and v_kind = any (r.applies_to_kind)
     and (r.applies_to_subkind is null or v_subkind = any (r.applies_to_subkind));
  insert into public.activities (operator_id, organization_id, entity_type, entity_id, activity_type, body)
  values (v_op, p_org, 'habilitation', v_id, 'sistema', format('Caso de habilitación abierto: %s (%s, %s)%s', trim(p_name), p_type, v_kind, case when v_seq > 1 then format(' · renovación #%s', v_seq) else '' end));
  return v_id;
end $function$;

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
    (c.target_date - CURRENT_DATE) AS days_to_target,
    c.dgha_file_number,
    c.submitted_on,
    c.inspection_on,
    c.license_number,
    c.license_valid_until,
    (c.license_valid_until - CURRENT_DATE) AS license_days_left,
    c.pss_code,
    c.owner_id,
    pr.full_name AS owner_name,
    c.notes,
    c.stage_changed_at,
    c.created_at,
    c.updated_at,
    COALESCE(k.total, (0)::bigint) AS items_total,
    COALESCE(k.applicable, (0)::bigint) AS items_applicable,
    COALESCE(k.verde, (0)::bigint) AS verde,
    COALESCE(k.amarillo, (0)::bigint) AS amarillo,
    COALESCE(k.rojo, (0)::bigint) AS rojo,
    COALESCE(k.pendiente, (0)::bigint) AS pendiente,
    COALESCE(k.no_aplica, (0)::bigint) AS no_aplica,
    COALESCE(k.critical_open, (0)::bigint) AS critical_open,
    (
        CASE
            WHEN (COALESCE(k.applicable, (0)::bigint) = 0) THEN (0)::numeric
            ELSE round(((100.0 * (k.verde)::numeric) / (k.applicable)::numeric))
        END)::integer AS ready_pct,
    c.case_subkind,
    c.renewal_of_case_id,
    c.renewal_seq
   FROM ((((habilitation_cases c
     LEFT JOIN organizations o ON ((o.id = c.organization_id)))
     LEFT JOIN leads l ON ((l.id = c.lead_id)))
     LEFT JOIN profiles pr ON ((pr.id = c.owner_id)))
     LEFT JOIN LATERAL ( SELECT count(*) AS total,
            count(*) FILTER (WHERE (i.status <> 'no_aplica'::text)) AS applicable,
            count(*) FILTER (WHERE (i.status = 'verde'::text)) AS verde,
            count(*) FILTER (WHERE (i.status = 'amarillo'::text)) AS amarillo,
            count(*) FILTER (WHERE (i.status = 'rojo'::text)) AS rojo,
            count(*) FILTER (WHERE (i.status = 'pendiente'::text)) AS pendiente,
            count(*) FILTER (WHERE (i.status = 'no_aplica'::text)) AS no_aplica,
            count(*) FILTER (WHERE (i.is_critical AND (i.status = ANY (ARRAY['pendiente'::text, 'amarillo'::text, 'rojo'::text])))) AS critical_open
           FROM habilitation_items i
          WHERE (i.case_id = c.id)) k ON (true));

-- Casos de habilitación visibles desde el prospecto: lo que hoy solo se ve desde Clientes.
create or replace function public.habilitation_cases_for_lead(p_lead uuid)
returns setof public.v_habilitation_cases
language sql stable
security invoker
set search_path to ''
as $function$
  select * from public.v_habilitation_cases where lead_id = p_lead order by created_at desc;
$function$;
