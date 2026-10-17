-- 210 · El molde de las pruebas: una aserción NULL deja de contar como aprobada (SOFA 5.10 · I70)
-- Requiere: 208. Idempotente. Revertir: no aplica (solo endurece el resumen; ver nota abajo).
-- Prueba: 211_molde_pruebas_null_test.sql (app.qa_run_tests_molde())
-- Qué hace:
--   El resumen de cada suite (la fila n = 0) se calculaba con bool_and((e->>'ok')::boolean).
--   bool_and IGNORA los NULL. Si una aserción devolvía NULL en vez de verdadero o falso —cosa que
--   pasa, por ejemplo, al consultar una tabla que el rol activo no puede ver, que devuelve cero filas
--   en vez de error— esa prueba salía «FALLÓ» en su línea, pero el total seguía diciendo «TODO OK».
--   Es decir: una suite podía estar ocultando fallos. Caso real detectado el 16/10/2026 en la 203.
--   Esta migración recorre todas las funciones app.qa_run_tests_* ya instaladas y les aplica la
--   corrección: coalesce((e->>'ok')::boolean, false), tanto en el veredicto como en el conteo.
--   No cambia ninguna prueba: solo deja de ocultar las que no dan un resultado claro.
--   Al correrla de nuevo no encuentra nada que cambiar (idempotente).

do $$
begin
  if not exists (select 1 from app.schema_migrations where version = '208') then
    raise exception 'Falta la migración 208. Aplica las migraciones en orden hasta la 208 y vuelve a correr esta.';
  end if;
end $$;

do $patch$
declare
  r record;
  v_def text;
  v_n int := 0;
  v_rev int := 0;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'app' and p.proname like 'qa\_run\_tests\_%'
     order by p.proname
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('bool_and((e->>''ok'')::boolean)' in v_def) > 0
       or position('filter (where (e->>''ok'')::boolean)' in v_def) > 0 then
      v_def := replace(v_def, 'bool_and((e->>''ok'')::boolean)',
                              'bool_and(coalesce((e->>''ok'')::boolean, false))');
      v_def := replace(v_def, 'filter (where (e->>''ok'')::boolean)',
                              'filter (where coalesce((e->>''ok'')::boolean, false))');
      execute v_def;
      -- CREATE OR REPLACE conserva los permisos, pero lo reafirmamos: las suites no se llaman desde la API.
      execute format('revoke all on function app.%I() from public, anon, authenticated', r.proname);
      v_n := v_n + 1;
    else
      v_rev := v_rev + 1;
    end if;
  end loop;
  raise notice 'Molde de pruebas · corregidas: % · ya estaban al día: %', v_n, v_rev;
end $patch$;

-- ── Registro ─────────────────────────────────────────────────────────────────────────────────────
delete from app.schema_migrations where version = '210';
insert into app.schema_migrations (version, report) values ('210', jsonb_build_object('iteracion', 'I70', 'version', '5.10.0', 'tema', 'el molde de las pruebas deja de ocultar fallos: una aserción NULL ya no cuenta como aprobada'));
