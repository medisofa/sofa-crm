-- ============================================================
-- 238 · ARS Portal Bridge
-- Agrega portal_url a la tabla ars y actualiza las funciones
-- ars_save y ars_catalog para exponer y persistir la URL.
-- Ya aplicado en producción (2026-11-11).
-- ============================================================

-- 1. Nueva columna (nullable — ARS sin URL simplemente no muestra botón)
ALTER TABLE public.ars
  ADD COLUMN IF NOT EXISTS portal_url text;

-- 2. Función ars_save: agrega parámetro p_portal_url
CREATE OR REPLACE FUNCTION public.ars_save(
  p_id          uuid    DEFAULT NULL,
  p_name        text    DEFAULT NULL,
  p_code        text    DEFAULT NULL,
  p_regime      text    DEFAULT NULL,
  p_channel     text    DEFAULT NULL,
  p_notes       text    DEFAULT NULL,
  p_active      boolean DEFAULT NULL,
  p_portal_url  text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id      uuid;
  v_name    text := nullif(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), '');
  v_code    text := nullif(lower(regexp_replace(trim(coalesce(p_code, '')), '[^A-Za-z0-9]+', '_', 'g')), '');
  v_url     text := nullif(trim(coalesce(p_portal_url, '')), '');
BEGIN
  PERFORM app.ars_admin_require();

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'El nombre de la ARS no puede estar vacío.' USING errcode = '22023';
  END IF;
  IF char_length(v_name) < 2 THEN
    RAISE EXCEPTION 'El nombre de la ARS debe tener al menos 2 caracteres.' USING errcode = '22023';
  END IF;
  IF p_regime IS NOT NULL AND p_regime NOT IN ('Contributivo', 'Subsidiado', 'Pensionados', 'Plan voluntario') THEN
    RAISE EXCEPTION 'Régimen inválido: %', p_regime USING errcode = '22023';
  END IF;

  IF p_id IS NULL THEN
    -- Verificar código duplicado solo en INSERT
    IF v_code IS NOT NULL AND EXISTS (SELECT 1 FROM public.ars WHERE code = v_code) THEN
      RAISE EXCEPTION 'Ya existe una ARS con el código «%».', v_code USING errcode = '23505';
    END IF;
    INSERT INTO public.ars (code, name, regime_default, submission_channel, notes, portal_url, is_active, updated_at, updated_by)
    VALUES (v_code, v_name, coalesce(p_regime, 'Contributivo'),
            nullif(trim(coalesce(p_channel, '')), ''),
            nullif(trim(coalesce(p_notes, '')), ''),
            v_url,
            coalesce(p_active, true), now(), auth.uid())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.ars SET
      name              = v_name,
      regime_default    = coalesce(p_regime, regime_default),
      submission_channel = nullif(trim(coalesce(p_channel, '')), ''),
      notes             = nullif(trim(coalesce(p_notes, '')), ''),
      portal_url        = CASE WHEN p_portal_url IS NOT NULL THEN v_url ELSE portal_url END,
      is_active         = coalesce(p_active, is_active),
      updated_at        = now(),
      updated_by        = auth.uid()
    WHERE id = p_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'ARS no encontrada.' USING errcode = '02000';
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

-- 3. Función ars_catalog: expone portal_url en el JSON
CREATE OR REPLACE FUNCTION public.ars_catalog(
  p_include_inactive boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'id',         a.id,
      'code',       a.code,
      'name',       a.name,
      'regime',     a.regime_default,
      'channel',    a.submission_channel,
      'notes',      a.notes,
      'portal_url', a.portal_url,
      'active',     a.is_active,
      'tariffs',    (SELECT count(*) FROM public.tariffs t WHERE t.ars_id = a.id AND t.valid_during @> current_date),
      'plans',      coalesce(
        (SELECT jsonb_agg(
            jsonb_build_object(
              'id',      p.id,
              'name',    p.name,
              'regime',  p.regime,
              'notes',   p.notes,
              'active',  p.is_active,
              'sort',    p.sort_order,
              'tariffs', (SELECT count(*) FROM public.tariffs t WHERE t.plan_id = p.id AND t.valid_during @> current_date)
            ) ORDER BY p.sort_order, p.name
         )
         FROM public.ars_plans p
         WHERE p.ars_id = a.id AND (p_include_inactive OR p.is_active)
        ), '[]'::jsonb
      )
    )
    ORDER BY a.is_active DESC, a.name
  ), '[]'::jsonb)
  FROM public.ars a
  WHERE app.is_active_user()
    AND (p_include_inactive OR a.is_active);
$$;
