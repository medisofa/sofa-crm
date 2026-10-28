-- Clasificación DEMO con autorización por oportunidad.
CREATE FUNCTION app.pipeline_opportunity_is_demo(
    p_opportunity_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_operator uuid;
    v_demo boolean;
BEGIN
    SELECT op.operator_id,
           EXISTS (
               SELECT 1 FROM public.organizations o
               WHERE o.id = op.organization_id AND o.is_demo
           )
           OR EXISTS (
               SELECT 1
               FROM public.leads l
               JOIN public.organizations o
                 ON o.id = l.converted_org_id
               WHERE l.id = op.lead_id AND o.is_demo
           )
    INTO v_operator, v_demo
    FROM public.opportunities op
    WHERE op.id = p_opportunity_id;

    IF v_operator IS NULL
       OR NOT app.can_operator(
           v_operator,
           ARRAY[
             'super_admin', 'admin', 'billing',
             'glosas', 'assistant', 'auditor'
           ]
       )
       OR NOT app.mfa_ok()
    THEN
        RAISE EXCEPTION 'Acceso denegado'
          USING ERRCODE = '42501';
    END IF;

    RETURN coalesce(v_demo, false);
END;
$function$;

REVOKE ALL ON FUNCTION app.pipeline_opportunity_is_demo(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION app.pipeline_opportunity_is_demo(uuid)
TO authenticated;

-- SOFA · Aislamiento del pipeline comercial
-- Nueva vista: no modifica v_pipeline ni datos existentes.

CREATE VIEW public.v_pipeline_real
WITH (security_invoker = true)
AS
SELECT
    op.operator_id,
    op.stage,
    count(*) AS opportunities,
    sum(op.estimated_value) AS monthly_value,
    round(
        sum(
            op.estimated_value *
            op.probability::numeric / 100.0
        ),
        2
    ) AS weighted_value
FROM public.opportunities op
WHERE NOT app.pipeline_opportunity_is_demo(op.id)
GROUP BY op.operator_id, op.stage;

GRANT SELECT ON public.v_pipeline_real
TO authenticated;

COMMENT ON VIEW public.v_pipeline_real IS
'Pipeline comercial real: excluye organizaciones DEMO '
'y prospectos convertidos en DEMO. '
'Conserva prospectos no convertidos.';

-- anon no debe consultar el pipeline: los permisos por defecto de Supabase se lo daban.
REVOKE ALL ON public.v_pipeline_real FROM PUBLIC, anon;
