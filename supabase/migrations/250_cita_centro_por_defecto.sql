-- 250_cita_centro_por_defecto.sql
-- Ya aplicado en producción (2026-11-20, mcp__Supabase__apply_migration «cita_centro_por_defecto_250»).
-- Hallazgo de la prueba en navegador de la 244: en «Recepción del centro», las citas sin centro se mostraban
-- como «No disponible» en vez de como citas. La 244 solo rellenó el centro con el centro PRINCIPAL del
-- médico; un médico con un único centro no marcado como principal quedó con sus citas sin centro.
--   1. Trigger: toda cita nueva o editada sin centro recibe el único centro del médico, o su principal.
--   2. Relleno de las citas existentes con la misma regla.
-- Idempotente. Prueba: CC-01 y CC-02 en 251_cita_centro_por_defecto_test.sql.

do $$ begin
  if to_regclass('public.provider_centers') is null then raise exception 'Falta provider_centers'; end if;
  if not exists (select 1 from information_schema.columns where table_name = 'appointments' and column_name = 'center_id') then
    raise exception 'Falta la 244 (appointments.center_id)';
  end if;
end $$;

create or replace function app.appointment_default_center()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.center_id is null then
    select pc.center_id into new.center_id
      from public.provider_centers pc
      join public.health_centers hc on hc.id = pc.center_id and hc.is_active
      join public.providers p on p.id = pc.provider_id and p.organization_id = hc.organization_id
     where pc.provider_id = new.provider_id
       and (pc.is_primary or (select count(*) from public.provider_centers x where x.provider_id = new.provider_id) = 1)
     order by pc.is_primary desc
     limit 1;
  end if;
  return new;
end $$;
revoke execute on function app.appointment_default_center() from public;
drop trigger if exists appointments_default_center on public.appointments;
-- El nombre empieza por «a» para correr antes que appointments_overlap_guard (los triggers BEFORE van en orden alfabético).
create trigger appointments_aa_default_center before insert or update of center_id, provider_id on public.appointments
  for each row execute function app.appointment_default_center();

update public.appointments a set center_id = pc.center_id
  from public.provider_centers pc
  join public.health_centers hc on hc.id = pc.center_id and hc.is_active
 where a.center_id is null and pc.provider_id = a.provider_id
   and (select count(*) from public.provider_centers x where x.provider_id = a.provider_id) = 1;
