-- 242_hospital_projected_50pct.sql
-- YA APLICADO EN PRODUCCIÓN
--
-- Regla 100%/50%: todas las ARS pagan el primer servicio del día al 100%;
-- los siguientes servicios del mismo día, mismo reporte (= mismo paciente,
-- centro y médico) se pagan al 50%.
--
-- Cambios:
--   1. hospital_report_lines: +projected_pct, +projected_amount
--   2. hospital_reports: +projected_total
--   3. app.hospital_recalc_projections(uuid) — recalcula por reporte
--   4. app.hospital_report_retotal() — extendida para llamar recalc
--   5. hospital_report_get — devuelve campos proyectados
--   6. hospital_report_line_add / _remove — sin cambios (retotal trigger ya dispara recalc)

begin;

-- ============================================================
-- 1. Nuevas columnas
-- ============================================================

alter table public.hospital_report_lines
  add column if not exists projected_pct  numeric not null default 100
    check (projected_pct in (100, 50)),
  add column if not exists projected_amount numeric not null default 0;

comment on column public.hospital_report_lines.projected_pct is
  'Porcentaje que pagará la ARS: 100 primer servicio del día, 50 los siguientes.';
comment on column public.hospital_report_lines.projected_amount is
  'Monto proyectado = amount × projected_pct / 100.';

alter table public.hospital_reports
  add column if not exists projected_total numeric not null default 0;

comment on column public.hospital_reports.projected_total is
  'Suma de projected_amount de todas las líneas — lo que realmente pagará la ARS.';

-- ============================================================
-- 2. Función de recálculo de proyecciones
-- ============================================================

create or replace function app.hospital_recalc_projections(p_report uuid)
returns void language plpgsql security definer set search_path to '' as $$
-- Regla 100/50: primera línea de cada service_date → 100 %, resto → 50 %.
-- Dentro de un mismo día, el orden se determina por created_at (la primera
-- línea agregada es la que conserva el 100 %).
declare
  rec record;
  v_prev_date date := null;
begin
  -- Recorrer las líneas ordenadas por fecha del servicio, luego por orden de creación
  for rec in
    select l.id, l.service_date, l.amount
      from public.hospital_report_lines l
     where l.report_id = p_report
     order by l.service_date, l.created_at, l.id
  loop
    if rec.service_date is distinct from v_prev_date then
      -- Primer servicio de este día → 100 %
      update public.hospital_report_lines
         set projected_pct    = 100,
             projected_amount = round(rec.amount, 2)
       where id = rec.id
         and (projected_pct <> 100 or projected_amount <> round(rec.amount, 2));
      v_prev_date := rec.service_date;
    else
      -- Servicio subsiguiente del mismo día → 50 %
      update public.hospital_report_lines
         set projected_pct    = 50,
             projected_amount = round(rec.amount * 0.50, 2)
       where id = rec.id
         and (projected_pct <> 50 or projected_amount <> round(rec.amount * 0.50, 2));
    end if;
  end loop;

  -- Actualizar projected_total en el encabezado
  update public.hospital_reports
     set projected_total = coalesce(
           (select sum(projected_amount)
              from public.hospital_report_lines
             where report_id = p_report), 0)
   where id = p_report;
end $$;

comment on function app.hospital_recalc_projections(uuid) is
  'Recalcula projected_pct y projected_amount de todas las líneas de un reporte según la regla 100/50.';

-- ============================================================
-- 3. Extender hospital_report_retotal para incluir proyecciones
-- ============================================================

-- Copiamos la función original y le agregamos la llamada a recalc.
-- Guard de recursión: recalc_projections actualiza líneas → dispara este
-- trigger de nuevo; pg_trigger_depth() > 1 lo corta.
create or replace function app.hospital_report_retotal()
returns trigger language plpgsql security definer set search_path to '' as $$
declare v_report uuid := coalesce(new.report_id, old.report_id);
begin
  -- Evitar recursión: recalc_projections → update lines → retotal → recalc…
  if pg_trigger_depth() > 1 then return null; end if;

  -- Retotal original
  update public.hospital_reports r
     set total = coalesce(
           (select sum(l.amount)
              from public.hospital_report_lines l
             where l.report_id = v_report), 0)
   where r.id = v_report;

  -- Recalcular proyecciones 100/50
  perform app.hospital_recalc_projections(v_report);

  return null;
end $$;

-- ============================================================
-- 4. Extender hospital_report_get para devolver campos proyectados
-- ============================================================

create or replace function public.hospital_report_get(p_report uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_p uuid := app.hospital_my_provider(); r public.hospital_reports; v_sup boolean;
begin
  if auth.uid() is null or not app.is_active_user() then
    raise exception 'Inicia sesión.' using errcode = '42501';
  end if;

  select * into r from public.hospital_reports where id = p_report;

  if r.id is null then
    raise exception 'Reporte no encontrado.' using errcode = 'P0002';
  end if;

  v_sup := exists(
    select 1 from public.health_centers hc
     where hc.id = r.center_id
       and hc.organization_id in (select app.visible_org_ids())
       and coalesce(app.role_for_org(hc.organization_id), '') in ('super_admin','admin','operations')
  );

  if not (coalesce(r.provider_id = v_p, false) or v_sup) then
    raise exception 'Este reporte no es tuyo.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'id',              r.id,
    'provider_id',     r.provider_id,
    'center_id',       r.center_id,
    'centro',          (select name from public.health_centers where id = r.center_id),
    'medico',          (select full_name from public.providers where id = r.provider_id),
    'patient_name',    r.patient_name,
    'patient_doc',     r.patient_doc,
    'patient_phone',   r.patient_phone,
    'ars_id',          r.ars_id,
    'ars',             (select name from public.ars where id = r.ars_id),
    'admission_date',  r.admission_date,
    'discharge_date',  r.discharge_date,
    'status',          r.status,
    'notes',           r.notes,
    'total',           r.total,
    'projected_total', r.projected_total,
    'avance',          app.hospital_report_progress(r.id),
    'puede_editar',    coalesce(r.status = 'borrador' and r.provider_id = v_p, false),
    'lineas',          coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',               l.id,
          'service_date',     l.service_date,
          'procedure_id',     l.procedure_id,
          'servicio',         pr.description,
          'codigo',           pr.internal_code,
          'quantity',         l.quantity,
          'unit_amount',      l.unit_amount,
          'amount',           l.amount,
          'projected_pct',    l.projected_pct,
          'projected_amount', l.projected_amount,
          'notes',            l.notes
        ) order by l.service_date, l.created_at, l.id
      )
        from public.hospital_report_lines l
        join public.procedures pr on pr.id = l.procedure_id
       where l.report_id = r.id
    ), '[]'::jsonb)
  );
end $$;

-- ============================================================
-- 5. Backfill: recalcular reportes existentes
-- ============================================================

do $$
declare v_id uuid;
begin
  for v_id in select id from public.hospital_reports
  loop
    perform app.hospital_recalc_projections(v_id);
  end loop;
end $$;

commit;
