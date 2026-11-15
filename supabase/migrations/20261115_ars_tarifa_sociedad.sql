-- SOFA · 5.35.5 · ARS × tarifario de la sociedad.
-- Ya aplicado en producción (mcp__Supabase__apply_migration 2026-11-15).
-- Algunas ARS reconocen directamente la tarifa publicada por la sociedad médica de cada
-- especialidad (Sociedad Dominicana de ...). Cuando aplica, el médico no necesita negociar
-- tarifa propia con la ARS: se factura al valor de la sociedad. Esta bandera lo deja explícito
-- por ARS, con una nota libre para detallar (p. ej. «solo para radiología y laboratorio»).
--
-- Pendiente de aplicar en producción — el MCP Supabase ha estado haciendo timeout en los
-- pop-ups de confirmación. Aplicar manualmente en el proyecto bpwjhgpzhzhiocoxrvzq.

alter table public.ars
  add column if not exists uses_society_tariff boolean not null default false,
  add column if not exists society_tariff_notes text;

comment on column public.ars.uses_society_tariff is
  'true cuando la ARS reconoce el tarifario de la sociedad médica de cada especialidad. Si es true, la negociación por ARS no es necesaria.';
comment on column public.ars.society_tariff_notes is
  'Detalle opcional (qué especialidades, limitaciones, etc.) cuando uses_society_tariff = true.';

-- ars_save: agrega p_uses_society_tariff y p_society_tariff_notes.
create or replace function public.ars_save(
  p_id                   uuid    default null,
  p_name                 text    default null,
  p_code                 text    default null,
  p_regime               text    default null,
  p_channel              text    default null,
  p_notes                text    default null,
  p_active               boolean default null,
  p_portal_url           text    default null,
  p_uses_society_tariff  boolean default null,
  p_society_tariff_notes text    default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid;
  v_name text := nullif(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), '');
  v_code text := nullif(lower(regexp_replace(trim(coalesce(p_code, '')), '[^A-Za-z0-9]+', '_', 'g')), '');
  v_url  text := nullif(trim(coalesce(p_portal_url, '')), '');
  v_soc_notes text := nullif(trim(coalesce(p_society_tariff_notes, '')), '');
begin
  perform app.ars_admin_require();

  if v_name is null then
    raise exception 'El nombre de la ARS no puede estar vacío.' using errcode = '22023';
  end if;
  if char_length(v_name) < 2 then
    raise exception 'El nombre de la ARS debe tener al menos 2 caracteres.' using errcode = '22023';
  end if;
  if p_regime is not null and p_regime not in ('Contributivo', 'Subsidiado', 'Pensionados', 'Plan voluntario') then
    raise exception 'Régimen inválido: %', p_regime using errcode = '22023';
  end if;

  if p_id is null then
    if v_code is not null and exists (select 1 from public.ars where code = v_code) then
      raise exception 'Ya existe una ARS con el código «%».', v_code using errcode = '23505';
    end if;
    insert into public.ars (code, name, regime_default, submission_channel, notes, portal_url,
                            uses_society_tariff, society_tariff_notes, is_active, updated_at, updated_by)
    values (v_code, v_name, coalesce(p_regime, 'Contributivo'),
            nullif(trim(coalesce(p_channel, '')), ''),
            nullif(trim(coalesce(p_notes, '')), ''),
            v_url,
            coalesce(p_uses_society_tariff, false),
            v_soc_notes,
            coalesce(p_active, true), now(), auth.uid())
    returning id into v_id;
  else
    update public.ars set
      name                = v_name,
      regime_default      = coalesce(p_regime, regime_default),
      submission_channel  = nullif(trim(coalesce(p_channel, '')), ''),
      notes               = nullif(trim(coalesce(p_notes, '')), ''),
      portal_url          = case when p_portal_url is not null then v_url else portal_url end,
      uses_society_tariff = coalesce(p_uses_society_tariff, uses_society_tariff),
      society_tariff_notes = case when p_society_tariff_notes is not null then v_soc_notes else society_tariff_notes end,
      is_active           = coalesce(p_active, is_active),
      updated_at          = now(),
      updated_by          = auth.uid()
      where id = p_id
      returning id into v_id;
    if v_id is null then
      raise exception 'ARS no encontrada.' using errcode = '02000';
    end if;
  end if;

  return v_id;
end $$;

-- ars_catalog: expone los dos campos nuevos.
create or replace function public.ars_catalog(
  p_include_inactive boolean default false
) returns jsonb
language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',                   a.id,
      'code',                 a.code,
      'name',                 a.name,
      'regime',               a.regime_default,
      'channel',              a.submission_channel,
      'notes',                a.notes,
      'portal_url',           a.portal_url,
      'uses_society_tariff',  a.uses_society_tariff,
      'society_tariff_notes', a.society_tariff_notes,
      'active',               a.is_active,
      'tariffs',              (select count(*) from public.tariffs t where t.ars_id = a.id and t.valid_during @> current_date),
      'plans',                coalesce(
        (select jsonb_agg(
            jsonb_build_object(
              'id',      p.id,
              'name',    p.name,
              'regime',  p.regime,
              'notes',   p.notes,
              'active',  p.is_active,
              'sort',    p.sort_order,
              'tariffs', (select count(*) from public.tariffs t where t.plan_id = p.id and t.valid_during @> current_date)
            ) order by p.sort_order, p.name
         )
         from public.ars_plans p
         where p.ars_id = a.id and (p_include_inactive or p.is_active)
        ), '[]'::jsonb
      )
    )
    order by a.is_active desc, a.name
  ), '[]'::jsonb)
  from public.ars a
  where app.is_active_user()
    and (p_include_inactive or a.is_active);
$$;
