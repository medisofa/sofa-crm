-- 243_hospital_projected_50pct_test.sql
-- Suite de prueba para migración 242: regla 100%/50% de proyección hospitalaria.
-- Dependencia: 242_hospital_projected_50pct.sql (ya aplicado en producción).
--
-- Verifica:
--   1. Columnas projected_pct, projected_amount en hospital_report_lines
--   2. Columna projected_total en hospital_reports
--   3. Función app.hospital_recalc_projections existe
--   4. Guard pg_trigger_depth en hospital_report_retotal
--   5. Lógica 100/50: primer servicio del día = 100%, siguientes = 50%
--   6. Recálculo correcto al eliminar la línea que tenía 100%
--   7. hospital_report_get devuelve los campos de proyección

begin;

-- ============================================================
-- 0. Dependencias
-- ============================================================
do $$ begin
  -- Columnas en hospital_report_lines
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'hospital_report_lines'
       and column_name = 'projected_pct'
  ) then raise exception 'FALTA columna projected_pct en hospital_report_lines'; end if;

  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'hospital_report_lines'
       and column_name = 'projected_amount'
  ) then raise exception 'FALTA columna projected_amount en hospital_report_lines'; end if;

  -- Columna en hospital_reports
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'hospital_reports'
       and column_name = 'projected_total'
  ) then raise exception 'FALTA columna projected_total en hospital_reports'; end if;

  -- Función de recálculo
  if not exists (
    select 1 from pg_proc
     where proname = 'hospital_recalc_projections'
       and pronamespace = (select oid from pg_namespace where nspname = 'app')
  ) then raise exception 'FALTA función app.hospital_recalc_projections'; end if;

  -- Guard de recursión en retotal
  if not exists (
    select 1 from pg_proc
     where proname = 'hospital_report_retotal'
       and pronamespace = (select oid from pg_namespace where nspname = 'app')
       and prosrc like '%pg_trigger_depth%'
  ) then raise exception 'hospital_report_retotal NO tiene guard pg_trigger_depth'; end if;

  raise notice '243 · Dependencias OK';
end $$;

-- ============================================================
-- 1. Preparar datos de prueba
-- ============================================================
do $$
declare
  v_org  uuid;
  v_center uuid;
  v_provider uuid;
  v_ars  uuid;
  v_report uuid;
  v_line1 uuid;
  v_line2 uuid;
  v_line3 uuid;
  v_proc1 uuid;
  v_proc2 uuid;
  v_proc3 uuid;
  v_pct  numeric;
  v_pamt numeric;
  v_ptotal numeric;
  v_total numeric;
begin
  -- Buscar una organización, centro, proveedor y ARS reales para las FK
  select id into v_org from public.organizations limit 1;
  if v_org is null then raise exception 'No hay organizaciones para probar'; end if;

  select id into v_center from public.health_centers where organization_id = v_org limit 1;
  if v_center is null then raise exception 'No hay centros para probar'; end if;

  select id into v_provider from public.providers
   where organization_id = v_org limit 1;
  if v_provider is null then raise exception 'No hay proveedores para probar'; end if;

  select id into v_ars from public.ars limit 1;
  if v_ars is null then raise exception 'No hay ARS para probar'; end if;

  -- Buscar 3 procedimientos distintos
  select id into v_proc1 from public.procedures offset 0 limit 1;
  select id into v_proc2 from public.procedures offset 1 limit 1;
  select id into v_proc3 from public.procedures offset 2 limit 1;
  if v_proc3 is null then raise exception 'Se necesitan al menos 3 procedimientos'; end if;

  -- Crear reporte de prueba
  insert into public.hospital_reports
    (provider_id, center_id, patient_name, patient_doc, ars_id, admission_date, status, notes)
  values
    (v_provider, v_center, 'TEST-243-Paciente', '00100000001', v_ars, '2024-01-15', 'borrador', 'Prueba suite 243')
  returning id into v_report;

  raise notice '243 · Reporte de prueba: %', v_report;

  -- ============================================================
  -- 2. Insertar línea 1 — día 15 ene — debe ser 100%
  -- ============================================================
  insert into public.hospital_report_lines
    (report_id, procedure_id, service_date, quantity, unit_amount, notes, center_id)
  values
    (v_report, v_proc1, '2024-01-15', 1, 1040.00, 'Interconsulta', v_center)
  returning id into v_line1;

  select projected_pct, projected_amount into v_pct, v_pamt
    from public.hospital_report_lines where id = v_line1;

  if v_pct <> 100 then
    raise exception '243 FALLO: línea 1 debería ser 100%%, tiene %', v_pct;
  end if;
  if v_pamt <> 1040.00 then
    raise exception '243 FALLO: línea 1 projected_amount debería ser 1040, tiene %', v_pamt;
  end if;

  raise notice '243 · Línea 1 (único servicio día 15) = 100%% ✓';

  -- ============================================================
  -- 3. Insertar línea 2 — mismo día 15 ene — debe ser 50%
  -- ============================================================
  insert into public.hospital_report_lines
    (report_id, procedure_id, service_date, quantity, unit_amount, notes, center_id)
  values
    (v_report, v_proc2, '2024-01-15', 1, 1200.00, 'Nutrición Parenteral', v_center)
  returning id into v_line2;

  select projected_pct, projected_amount into v_pct, v_pamt
    from public.hospital_report_lines where id = v_line2;

  if v_pct <> 50 then
    raise exception '243 FALLO: línea 2 (segundo servicio mismo día) debería ser 50%%, tiene %', v_pct;
  end if;
  if v_pamt <> 600.00 then
    raise exception '243 FALLO: línea 2 projected_amount debería ser 600, tiene %', v_pamt;
  end if;

  raise notice '243 · Línea 2 (segundo servicio día 15) = 50%% ✓';

  -- ============================================================
  -- 4. Insertar línea 3 — día diferente 16 ene — debe ser 100%
  -- ============================================================
  insert into public.hospital_report_lines
    (report_id, procedure_id, service_date, quantity, unit_amount, notes, center_id)
  values
    (v_report, v_proc3, '2024-01-16', 1, 800.00, 'Servicio día siguiente', v_center)
  returning id into v_line3;

  select projected_pct, projected_amount into v_pct, v_pamt
    from public.hospital_report_lines where id = v_line3;

  if v_pct <> 100 then
    raise exception '243 FALLO: línea 3 (primer servicio día 16) debería ser 100%%, tiene %', v_pct;
  end if;
  if v_pamt <> 800.00 then
    raise exception '243 FALLO: línea 3 projected_amount debería ser 800, tiene %', v_pamt;
  end if;

  raise notice '243 · Línea 3 (primer servicio día 16) = 100%% ✓';

  -- ============================================================
  -- 5. Verificar projected_total del reporte
  -- ============================================================
  select projected_total, total into v_ptotal, v_total
    from public.hospital_reports where id = v_report;

  -- total = 1040 + 1200 + 800 = 3040
  if v_total <> 3040 then
    raise exception '243 FALLO: total debería ser 3040, tiene %', v_total;
  end if;

  -- projected_total = 1040 (100%) + 600 (50%) + 800 (100%) = 2440
  if v_ptotal <> 2440 then
    raise exception '243 FALLO: projected_total debería ser 2440, tiene %', v_ptotal;
  end if;

  raise notice '243 · projected_total = 2440 (3040 - 600 de descuento 50%%) ✓';

  -- ============================================================
  -- 6. Eliminar línea 1 (la que tenía 100%) y verificar recálculo
  --    Ahora línea 2 debería subir a 100% (es la primera del día 15)
  -- ============================================================
  delete from public.hospital_report_lines where id = v_line1;

  select projected_pct, projected_amount into v_pct, v_pamt
    from public.hospital_report_lines where id = v_line2;

  if v_pct <> 100 then
    raise exception '243 FALLO: tras eliminar línea 1, línea 2 debería ser 100%%, tiene %', v_pct;
  end if;
  if v_pamt <> 1200.00 then
    raise exception '243 FALLO: tras eliminar línea 1, línea 2 projected_amount debería ser 1200, tiene %', v_pamt;
  end if;

  select projected_total into v_ptotal from public.hospital_reports where id = v_report;
  -- Ahora: 1200 (100%) + 800 (100%) = 2000
  if v_ptotal <> 2000 then
    raise exception '243 FALLO: projected_total tras eliminar debería ser 2000, tiene %', v_ptotal;
  end if;

  raise notice '243 · Recálculo tras eliminar línea 1: línea 2 sube a 100%%, projected_total = 2000 ✓';

  -- ============================================================
  -- 7. Verificar que hospital_report_get incluye campos de proyección
  -- ============================================================
  -- No podemos llamar la RPC directamente (necesita auth), pero verificamos
  -- que la función existe y su definición menciona projected_
  if not exists (
    select 1 from pg_proc
     where proname = 'hospital_report_get'
       and pronamespace = 'public'::regnamespace
       and prosrc like '%projected_pct%'
       and prosrc like '%projected_amount%'
       and prosrc like '%projected_total%'
  ) then
    raise exception '243 FALLO: hospital_report_get no incluye campos projected_*';
  end if;

  raise notice '243 · hospital_report_get incluye projected_pct, projected_amount, projected_total ✓';

  -- ============================================================
  -- Limpieza
  -- ============================================================
  delete from public.hospital_report_lines where report_id = v_report;
  delete from public.hospital_reports where id = v_report;

  raise notice '243 · Datos de prueba eliminados ✓';
  raise notice '══════════════════════════════════════════';
  raise notice '243 · TODAS LAS PRUEBAS PASARON ✓';
  raise notice '══════════════════════════════════════════';
end $$;

rollback;
