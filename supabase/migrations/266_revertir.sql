-- aplicada-primero: no aplica, es el script de reversión de la 266 (no se ha ejecutado).
-- 266 · Revertir «Corrección de tarifa».
-- Devuelve app.guard_tariff a su definición anterior (el monto vuelve a ser inmutable) y quita las funciones nuevas.
-- NO borra app.tariff_corrections (es la bitácora de lo corregido; los montos ya cambiados siguen siendo los nuevos).
-- Si de verdad quiere borrarla: drop table app.tariff_corrections;  (después de exportarla).

drop function if exists public.tariff_correct(uuid, numeric, text, jsonb);
drop function if exists public.tariff_correction_preview(uuid, numeric);
drop function if exists app.tariff_correct_core(uuid, numeric, text, jsonb);
drop function if exists app.tariff_correction_preview_core(uuid, numeric);
drop function if exists app.tariff_correction_lines(uuid, numeric);
drop function if exists app.tariff_correction_check(uuid);
drop function if exists app.qa_run_tests_correccion_tarifa();

create or replace function app.guard_tariff()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if (new.ars_id, new.plan_id, new.organization_id, new.provider_id, new.procedure_id, new.amount, lower(new.valid_during))
     is distinct from (old.ars_id, old.plan_id, old.organization_id, old.provider_id, old.procedure_id, old.amount, lower(old.valid_during)) then
    raise exception 'Una tarifa no se modifica: cree una nueva con public.create_tariff() (la anterior se cierra)' using errcode = '42501';
  end if;
  -- I57: publicar una versión (public.tariff_version_publish, que activa app.tariff_version_publish solo durante la publicación) con fecha anterior a servicios ya
  -- capturados está permitido; esas reclamaciones quedan en la alerta «precio vencido» (public.tariff_stale_claims) para que facturación decida.
  if upper(new.valid_during) is not null
     and coalesce(current_setting('app.tariff_version_publish', true), '') <> 'on'
     and exists (select 1 from public.service_lines l where l.tariff_id = new.id and l.service_date >= upper(new.valid_during)) then
    raise exception 'No se puede cerrar la tarifa antes de servicios que ya la usan' using errcode = '23514';
  end if;
  return new;
end $function$;

delete from app.schema_migrations where version in ('266', '267');
