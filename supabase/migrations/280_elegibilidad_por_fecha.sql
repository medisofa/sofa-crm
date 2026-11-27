-- PENDIENTE de aplicar en producción. No fusionar así.
-- 280 · La verificación de elegibilidad vale para la fecha y la ARS de la cita (27/11/2026). Si la cita se
-- mueve de día o cambia de ARS, vuelve a «sin verificar». La autorización y su fecha no se tocan. Una cita
-- atendida conserva su registro. El valor anterior queda en la auditoría.
begin;
do $dep$
begin
  if to_regprocedure('public.set_eligibility(uuid,text,text,text,date)') is null then
    raise exception 'Falta set_eligibility: aplique antes las migraciones de la agenda.';
  end if;
end $dep$;

create or replace function app.appointment_eligibility_reset()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.eligibility_status := 'no_verificada';
  new.eligibility_source := null;
  new.eligibility_reference := null;
  new.eligibility_checked_at := null;
  new.eligibility_checked_by := null;
  return new;
end $$;
revoke all on function app.appointment_eligibility_reset() from public, anon, authenticated;

drop trigger if exists appointments_eligibility_reset on public.appointments;
create trigger appointments_eligibility_reset before update of appointment_date, ars_id on public.appointments
  for each row when ((old.appointment_date is distinct from new.appointment_date or old.ars_id is distinct from new.ars_id) and old.status <> 'atendida')
  execute function app.appointment_eligibility_reset();

delete from app.schema_migrations where version = '280';
insert into app.schema_migrations (version, report) values ('280', jsonb_build_object('tema', 'elegibilidad por fecha y ARS de la cita'));
commit;
