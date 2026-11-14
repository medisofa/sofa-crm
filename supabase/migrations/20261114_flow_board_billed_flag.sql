-- 14/11/2026: Agrega el campo 'billed' al tablero de flujo de pacientes.
-- Un cobro privado (private_charges) con appointment_id indica facturación directa.
-- Las reclamaciones ARS (submissions) no enlazan con cita individual, así que
-- 'billed' hoy solo cubre cobros privados; la señal ARS se agregará cuando
-- submissions tenga appointment_id.
-- Ya aplicado en producción (Supabase, proyecto bpwjhgpzhzhiocoxrvzq).

create or replace function public.flow_board(p_org uuid, p_date date default current_date)
 returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if not ( app.can(p_org, array['super_admin', 'admin', 'client'])
        or exists (select 1 from public.providers pr where pr.organization_id = p_org and pr.id in (select app.capturer_providers()))
        or exists (select 1 from public.providers pr where pr.organization_id = p_org and pr.id in (select app.assistant_providers())) ) then
    raise exception 'Sin acceso a la agenda de este consultorio.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'patient', a.patient_name, 'time', to_char(a.appointment_time, 'HH24:MI'),
      'doctor', pr.full_name, 'provider_id', a.provider_id, 'status', a.status, 'room', a.room, 'type', a.reason,
      'status_changed_at', a.status_changed_at, 'consult_started_at', a.consult_started_at,
      'billed', exists (select 1 from public.private_charges pc where pc.appointment_id = a.id))
      order by a.appointment_time nulls last, a.status_changed_at)
    from public.appointments a join public.providers pr on pr.id = a.provider_id
   where a.organization_id = p_org and a.appointment_date = p_date and a.status <> 'cancelada'), '[]'::jsonb);
end $$;

notify pgrst, 'reload schema';
