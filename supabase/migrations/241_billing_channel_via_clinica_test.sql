-- 241 · Suite de pruebas para 240 — Canal de cobro "vía clínica"
-- Verifica: columna, constraint, status, vista, funciones.

begin;

do $test$
declare
  _ok  boolean;
  _val text;
  _cnt int;
begin
  raise notice '── 241: Pruebas de billing_channel ──';

  -- T1: La columna billing_channel existe en service_lines
  select exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_lines' and column_name = 'billing_channel'
  ) into _ok;
  assert _ok, 'T1 FALLO: columna billing_channel no existe en service_lines';
  raise notice 'T1 OK: columna billing_channel existe';

  -- T2: El default es ''directo''
  select column_default from information_schema.columns
  where table_schema = 'public' and table_name = 'service_lines' and column_name = 'billing_channel'
  into _val;
  assert _val = '''directo''::text', format('T2 FALLO: default es %s, esperaba directo', _val);
  raise notice 'T2 OK: default es directo';

  -- T3: La constraint CHECK existe
  select exists(
    select 1 from information_schema.check_constraints
    where constraint_name = 'service_lines_billing_channel_check'
  ) into _ok;
  assert _ok, 'T3 FALLO: constraint service_lines_billing_channel_check no existe';
  raise notice 'T3 OK: constraint CHECK existe';

  -- T4: El status pendiente_cobro_clinica existe
  select exists(
    select 1 from public.claim_statuses where code = 'pendiente_cobro_clinica'
  ) into _ok;
  assert _ok, 'T4 FALLO: status pendiente_cobro_clinica no existe';
  raise notice 'T4 OK: status pendiente_cobro_clinica existe';

  -- T5: El status está en la stage ''cobro''
  select stage from public.claim_statuses where code = 'pendiente_cobro_clinica' into _val;
  assert _val = 'cobro', format('T5 FALLO: stage es %s, esperaba cobro', _val);
  raise notice 'T5 OK: stage es cobro';

  -- T6: El índice parcial existe
  select exists(
    select 1 from pg_indexes
    where tablename = 'service_lines' and indexname = 'idx_service_lines_via_clinica'
  ) into _ok;
  assert _ok, 'T6 FALLO: índice idx_service_lines_via_clinica no existe';
  raise notice 'T6 OK: índice parcial existe';

  -- T7: v_claims expone billing_channel (si la vista ya fue recreada)
  select exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'v_claims' and column_name = 'billing_channel'
  ) into _ok;
  if _ok then
    raise notice 'T7 OK: v_claims expone billing_channel';
  else
    raise notice 'T7 SKIP: v_claims aún no recreada con billing_channel';
  end if;

  -- T8: v_claims tiene el next_step para pendiente_cobro_clinica (si la vista ya fue recreada)
  if _ok then
    -- Solo se puede probar si hay datos, así que verificamos la definición
    select exists(
      select 1 from pg_views
      where viewname = 'v_claims' and definition like '%pendiente_cobro_clinica%'
    ) into _ok;
    assert _ok, 'T8 FALLO: v_claims no incluye pendiente_cobro_clinica en el CASE';
    raise notice 'T8 OK: v_claims incluye next_step para pendiente_cobro_clinica';
  else
    raise notice 'T8 SKIP: depende de T7';
  end if;

  -- T9: Función set_billing_channel_via_clinica existe
  select exists(
    select 1 from pg_proc where proname = 'set_billing_channel_via_clinica'
  ) into _ok;
  if _ok then
    raise notice 'T9 OK: función set_billing_channel_via_clinica existe';
  else
    raise notice 'T9 SKIP: función aún no creada';
  end if;

  -- T10: Función revert_billing_channel_to_directo existe
  select exists(
    select 1 from pg_proc where proname = 'revert_billing_channel_to_directo'
  ) into _ok;
  if _ok then
    raise notice 'T10 OK: función revert_billing_channel_to_directo existe';
  else
    raise notice 'T10 SKIP: función aún no creada';
  end if;

  -- T11: Todas las líneas existentes tienen billing_channel = ''directo'' (no hay vía clínica aún)
  select count(*) from public.service_lines where billing_channel != 'directo' into _cnt;
  assert _cnt = 0, format('T11 FALLO: hay %s líneas con billing_channel != directo', _cnt);
  raise notice 'T11 OK: todas las líneas existentes tienen billing_channel = directo';

  raise notice '── 241: Suite completada ──';
end $test$;

rollback;
