-- SOFA · 5.35.6 · Agente de análisis de glosas (zero-cost, basado en reglas).
--
-- Dado el id de una glosa, para cada uno de sus ítems (motivo), devuelve:
--   · la causa probable (de un catálogo editable por el equipo de glosas),
--   · acciones concretas de mejora (lista corta, accionable),
--   · tip de prevención (para que la causa no se repita),
--   · patrón detectado: cuántas glosas con el mismo motivo tienen el mismo médico y la misma
--     ARS en los últimos 90 días (si ≥ 3, el agente sugiere revisar el proceso de captura),
--   · plantillas del banco de respuestas que mejor aplican (banco de respuestas v_glosa_template_stats
--     ya expone tasa de éxito).
--
-- El «agente» no llama a ningún LLM: es determinístico y está basado en un catálogo que el equipo de
-- glosas (super_admin, admin, glosas) puede editar en producción. Mantener el contrato del RPC
-- permite enchufar un modelo real después sin tocar la UI.
--
-- Pendiente de aplicar en producción — el MCP Supabase sigue haciendo timeout en los pop-ups.

-- 1) Catálogo editable de causas y acciones por motivo.
create table if not exists public.glosa_cause_catalog (
  reason_code text primary key references public.glosa_reasons(code) on delete cascade,
  probable_cause text not null check (length(probable_cause) between 1 and 400),
  recommended_actions text[] not null default '{}'::text[] check (array_length(recommended_actions, 1) is null or array_length(recommended_actions, 1) between 1 and 10),
  prevention_tip text check (prevention_tip is null or length(prevention_tip) <= 400),
  confidence smallint not null default 3 check (confidence between 1 and 5),
  updated_at timestamptz not null default now(),
  updated_by uuid
);

alter table public.glosa_cause_catalog enable row level security;

drop policy if exists glosa_cause_catalog_read on public.glosa_cause_catalog;
create policy glosa_cause_catalog_read on public.glosa_cause_catalog
  for select using (app.is_staff() or exists (
    select 1 from public.organization_users ou
    where ou.user_id = auth.uid() and ou.is_active
      and ou.role_code in ('super_admin','admin','client')
  ));

drop policy if exists glosa_cause_catalog_write on public.glosa_cause_catalog;
create policy glosa_cause_catalog_write on public.glosa_cause_catalog
  for all using (app.is_staff(array['super_admin','admin','glosas']))
          with check (app.is_staff(array['super_admin','admin','glosas']));

-- Semilla: causas y acciones típicas por los motivos más comunes en el mercado RD.
-- Si el código aquí no existe en glosa_reasons, simplemente se ignora (sin FK rota porque el
-- INSERT lo filtra). No sobreescribimos si ya hay datos.
insert into public.glosa_cause_catalog (reason_code, probable_cause, recommended_actions, prevention_tip, confidence)
select v.reason_code, v.probable_cause, v.recommended_actions, v.prevention_tip, v.confidence
from (values
  ('autorizacion_vencida',
    'La autorización de la ARS expiró antes de la fecha del servicio.',
    array[
      'Verificar la fecha de vigencia en el portal de la ARS.',
      'Si el servicio fue antes del vencimiento, adjuntar captura con fecha y número de autorización.',
      'Si ya expiró, solicitar retroactivo con el acta médica.'
    ],
    'Al capturar, exigir pantalla del portal con la vigencia de la autorización.', 4),
  ('codigo_no_cubierto',
    'El código facturado no está cubierto por el plan del afiliado.',
    array[
      'Confirmar cobertura del código en el plan específico del afiliado.',
      'Si la cobertura aplica, adjuntar la cláusula del contrato con la ARS.',
      'Si no aplica, revisar si existe un código equivalente cubierto.'
    ],
    'Cruzar el código contra la tabla de cobertura del plan antes de enviar.', 4),
  ('afiliado_no_activo',
    'El afiliado no estaba activo con la ARS en la fecha del servicio.',
    array[
      'Verificar afiliación en el portal SISALRIL con la fecha del servicio.',
      'Si estaba activo, adjuntar la consulta de afiliación con fecha.',
      'Si no, trasladar el cobro al paciente como privado.'
    ],
    'Confirmar elegibilidad el mismo día del servicio desde la agenda.', 5),
  ('monto_sobre_tarifa',
    'El monto facturado supera la tarifa contratada o la tarifa de la sociedad reconocida.',
    array[
      'Verificar la tarifa vigente del contrato por fecha del servicio.',
      'Si la ARS reconoce el tarifario de sociedad, usarlo como referencia.',
      'Si el monto es correcto, adjuntar el tarifario firmado.'
    ],
    'Mantener el tarifario del contrato actualizado y vigente en SOFA.', 4),
  ('autorizacion_faltante',
    'No se adjuntó la autorización de la ARS al radicar.',
    array[
      'Buscar la autorización en el portal de la ARS o pedirla al consultorio.',
      'Adjuntar en la apelación con número y fecha.',
      'Si nunca se autorizó, tratar como caso privado.'
    ],
    'Bloquear la radicación cuando la autorización es obligatoria y está vacía.', 5),
  ('documentacion_incompleta',
    'Faltan soportes obligatorios para el servicio (reporte operatorio, lectura, acta, etc.).',
    array[
      'Pedir al médico/consultorio el soporte específico que la ARS reclama.',
      'Adjuntar al expediente digital y referenciar en la apelación.',
      'Si el documento no existe, documentar la justificación clínica.'
    ],
    'Definir por servicio qué soportes son obligatorios y validarlo al capturar.', 5),
  ('duplicado',
    'La ARS detectó que el servicio ya fue cobrado en otra reclamación.',
    array[
      'Verificar en SOFA si se radicó dos veces el mismo servicio.',
      'Si fue error de captura, aceptar la glosa.',
      'Si no es duplicado, enviar comprobante del otro cobro referido.'
    ],
    'Alerta automática en captura cuando se repite paciente+servicio+fecha.', 5),
  ('fuera_plazo_radicacion',
    'La reclamación se radicó fuera del plazo contractual con la ARS.',
    array[
      'Confirmar el plazo exacto del contrato (30/45/60 días).',
      'Si hay caso de fuerza mayor, documentarlo y apelar.',
      'Si no, aceptar la glosa.'
    ],
    'Alerta semanal de servicios cerca del plazo y bloqueo al vencer.', 4),
  ('error_codificacion',
    'El código CUPS/SIMON facturado no corresponde al servicio efectivamente prestado.',
    array[
      'Revisar el reporte clínico y el código correcto.',
      'Si hay un código mejor, pedir cambio en la ARS (reconsideración con nota).',
      'Si el servicio sí fue el que se facturó, adjuntar justificación clínica.'
    ],
    'Codificar siempre con el reporte clínico a la vista.', 3)
) as v(reason_code, probable_cause, recommended_actions, prevention_tip, confidence)
where exists (select 1 from public.glosa_reasons r where r.code = v.reason_code)
on conflict (reason_code) do nothing;

-- 2) RPC principal: analiza una glosa y devuelve el resumen completo.
create or replace function public.glosa_ai_analyze(p_glosa uuid)
returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare
  v_actor uuid := auth.uid();
  v_glosa record;
  v_result jsonb;
  v_items jsonb;
  v_actions jsonb;
  v_templates jsonb;
  v_pattern jsonb;
begin
  if v_actor is null then raise exception 'Debe iniciar sesión.'; end if;

  -- RLS de glosas valida el acceso al hacer este SELECT (SECURITY DEFINER + RLS sobre glosas).
  -- Si el usuario no la ve, el record viene nulo y lanzamos 42501.
  select g.id, g.ars_id, g.provider_name, g.ars_name, g.main_reason, g.status, g.amount,
         sl.provider_id
    into v_glosa
    from public.glosas g
    left join public.service_lines sl on sl.id = (
      select glosa_items.service_line_id from public.glosa_items where glosa_items.glosa_id = g.id limit 1
    )
   where g.id = p_glosa;

  if v_glosa.id is null then
    raise exception 'Glosa no encontrada o sin acceso.' using errcode = '42501';
  end if;

  -- Por ítem (motivo): monto, causa probable, acciones, tip, confianza.
  select coalesce(jsonb_agg(jsonb_build_object(
    'reason_code', gi.reason_code,
    'reason_name', gr.name,
    'reason_category', gr.category,
    'amount', gi.amount,
    'probable_cause', coalesce(c.probable_cause,
      'Sin causa registrada todavía para este motivo. El equipo de glosas puede agregarla al catálogo.'),
    'recommended_actions', coalesce(to_jsonb(c.recommended_actions),
      '["Revisar manualmente y documentar la causa para registrarla al catálogo."]'::jsonb),
    'prevention_tip', c.prevention_tip,
    'confidence', coalesce(c.confidence, 1)
  )), '[]'::jsonb)
    into v_items
    from public.glosa_items gi
    join public.glosa_reasons gr on gr.code = gi.reason_code
    left join public.glosa_cause_catalog c on c.reason_code = gi.reason_code
   where gi.glosa_id = p_glosa;

  -- Acciones agregadas y únicas, priorizadas por confidence * número de ítems que las necesitan.
  select coalesce(jsonb_agg(action order by weight desc, action), '[]'::jsonb)
    into v_actions
    from (
      select unnest(coalesce(c.recommended_actions, '{}'::text[])) as action,
             sum(coalesce(c.confidence, 1))::int as weight
        from public.glosa_items gi
        left join public.glosa_cause_catalog c on c.reason_code = gi.reason_code
       where gi.glosa_id = p_glosa
       group by action
    ) t
   where action is not null;

  -- Templates del banco de respuestas que matchean los motivos de esta glosa, priorizados por ARS.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'title', t.title, 'reason_name', t.reason_name,
    'ars_id', t.ars_id, 'ars_match', t.ars_id = v_glosa.ars_id,
    'body_preview', left(t.body, 180)
  ) order by (t.ars_id = v_glosa.ars_id) desc, t.title), '[]'::jsonb)
    into v_templates
    from public.v_glosa_template_stats t
   where t.is_active = true
     and t.reason_code in (select distinct reason_code from public.glosa_items where glosa_id = p_glosa)
     and (t.ars_id is null or t.ars_id = v_glosa.ars_id);

  -- Patrón: cuántas glosas con el mismo motivo + médico + ARS en los últimos 90 días.
  select jsonb_build_object(
    'window_days', 90,
    'provider_id', v_glosa.provider_id,
    'repeated', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reason_code', reason_code, 'reason_name', reason_name, 'n', n, 'total', total
      ) order by n desc)
      from (
        select gi.reason_code, gr.name as reason_name,
               count(distinct g.id)::int as n,
               sum(gi.amount) as total
          from public.glosas g
          join public.glosa_items gi on gi.glosa_id = g.id
          join public.glosa_reasons gr on gr.code = gi.reason_code
          join public.service_lines sl on sl.id = gi.service_line_id
         where g.ars_id = v_glosa.ars_id
           and (v_glosa.provider_id is null or sl.provider_id = v_glosa.provider_id)
           and g.notified_on >= current_date - 90
           and gi.reason_code in (select distinct reason_code from public.glosa_items where glosa_id = p_glosa)
         group by gi.reason_code, gr.name
         having count(distinct g.id) >= 3
      ) rep
    ), '[]'::jsonb)
  ) into v_pattern;

  v_result := jsonb_build_object(
    'glosa_id', p_glosa,
    'engine', 'rule-based-v1',
    'generated_at', now(),
    'items', v_items,
    'top_actions', v_actions,
    'suggested_templates', v_templates,
    'pattern', v_pattern,
    'summary', case
      when jsonb_array_length(v_items) = 0 then 'Esta glosa no tiene ítems para analizar.'
      when jsonb_array_length(v_items) = 1 then 'Un solo motivo: ' || (v_items->0->>'reason_name') || '.'
      else jsonb_array_length(v_items) || ' motivos en la glosa. Causa dominante: '
           || (v_items->0->>'reason_name') || '.'
    end
  );

  return v_result;
end $$;

-- RPC para que el equipo de glosas edite el catálogo.
create or replace function public.glosa_cause_save(
  p_reason_code text,
  p_probable_cause text,
  p_recommended_actions text[],
  p_prevention_tip text default null,
  p_confidence smallint default 3
) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if not app.is_staff(array['super_admin','admin','glosas']) then
    raise exception 'Sin acceso para editar el catálogo de causas.' using errcode = '42501';
  end if;
  if coalesce(trim(p_probable_cause), '') = '' then
    raise exception 'La causa probable es obligatoria.' using errcode = '22023';
  end if;
  if p_confidence not between 1 and 5 then
    raise exception 'La confianza va de 1 a 5.' using errcode = '22023';
  end if;

  insert into public.glosa_cause_catalog
    (reason_code, probable_cause, recommended_actions, prevention_tip, confidence, updated_at, updated_by)
  values
    (p_reason_code, trim(p_probable_cause), coalesce(p_recommended_actions, '{}'::text[]),
     nullif(trim(coalesce(p_prevention_tip, '')), ''), p_confidence, now(), auth.uid())
  on conflict (reason_code) do update set
    probable_cause = excluded.probable_cause,
    recommended_actions = excluded.recommended_actions,
    prevention_tip = excluded.prevention_tip,
    confidence = excluded.confidence,
    updated_at = now(),
    updated_by = auth.uid();
end $$;

revoke all on function public.glosa_ai_analyze(uuid) from public;
revoke execute on function public.glosa_ai_analyze(uuid) from anon;
grant execute on function public.glosa_ai_analyze(uuid) to authenticated;

revoke all on function public.glosa_cause_save(text, text, text[], text, smallint) from public;
revoke execute on function public.glosa_cause_save(text, text, text[], text, smallint) from anon;
grant execute on function public.glosa_cause_save(text, text, text[], text, smallint) to authenticated;

comment on table public.glosa_cause_catalog is
  'Catálogo editable de causas probables, acciones recomendadas y tips de prevención por motivo de glosa. Lo consume glosa_ai_analyze.';
comment on function public.glosa_ai_analyze(uuid) is
  'Agente de análisis de glosas (rule-based v1). Dado un glosa_id, devuelve por ítem: causa probable, acciones, tip; plus top_actions deduplicadas, templates sugeridos y patrón de repetición en 90 días.';
