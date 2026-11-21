-- 254_encf_generico_resto.sql
-- Ya aplicado en producción (2026-11-20, mcp__Supabase__apply_migration «encf_generico_resto_254»).
-- [CRÍTICO] Completa la corrección del PR #195 (e-NCF genérico). Quedaban 4 funciones que exigían SOLO E31:
--   · app.guard_ecf_submission — trigger al radicar: impedía radicar un lote con E45 u otro tipo válido.
--   · app.preaudit_lot          — la preauditoría marcaba el lote como bloqueado por e-CF.
--   · app.ecf_blocked_lots      — el tablero de lotes frenados listaba «Falta el e-NCF E31».
--   · Textos de app.preaudit_rules, app.ecf_followup y app.ecf_steps.
-- Regla: '^E31\d{10}$' → '^E\d{12}$' (E + 12 dígitos: E31, E32, E33, E34, E41, E43, E44, E45, E46, E47).
-- Se reescribe sobre la definición vigente de cada función (solo cambian el patrón y los textos); idempotente.
-- Prueba: EN-01..EN-03 en 255_encf_generico_resto_test.sql.

do $$
declare f text; d text; d0 text;
begin
  foreach f in array array['app.guard_ecf_submission()', 'app.preaudit_lot(uuid)', 'app.ecf_blocked_lots(uuid)', 'app.preaudit_rules()', 'app.ecf_followup()', 'app.ecf_steps()']
  loop
    if to_regprocedure(f) is null then
      -- firma distinta: se busca por nombre (una sola sobrecarga esperada)
      select p.oid::regprocedure::text into f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'app' and p.proname = split_part(split_part(f, '.', 2), '(', 1) limit 1;
      if f is null then raise exception 'No se encontró la función'; end if;
    end if;
    d0 := pg_get_functiondef(f::regprocedure);
    d := d0;
    d := replace(d, 'E31\d{10}', 'E\d{12}');
    d := replace(d, 'e-NCF E31', 'e-NCF');
    d := replace(d, 'e-CF E31 aceptado', 'e-NCF aceptado');
    d := replace(d, 'Primer e-CF E31 emitido', 'Primer e-CF emitido');
    d := replace(d, 'sin E31 aceptado', 'sin e-NCF aceptado');
    if d <> d0 then execute d; end if;
  end loop;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public','app') and p.proname not like 'qa\_%' and p.prosrc like '%E31\\d{10}%') then
    raise exception 'Todavía queda una función con el patrón E31';
  end if;
end $$;

-- 254b · Dos textos que quedaban con «E31» (aplicado en producción como «encf_generico_resto_254b»)
do $$ declare f text; d text; d0 text; begin
  foreach f in array array['ecf_followup', 'preaudit_rules'] loop
    select pg_get_functiondef(p.oid) into d0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = f limit 1;
    d := replace(replace(d0, 'necesitan e-CF (E31) aceptado', 'necesitan e-NCF aceptado'), 'no se podrá radicar sin E31.', 'no se podrá radicar sin e-NCF aceptado.');
    if d <> d0 then execute d; end if;
  end loop;
end $$;
