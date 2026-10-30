-- Ya aplicado en producción (30/10/2026). Hallazgo de la auditoría de las funciones
-- SECURITY DEFINER del portal público (petición explícita del usuario: "Audita el resto de las
-- funciones SECURITY DEFINER del portal público").
--
-- [VERIFICACIÓN, resuelto] En portal_view(), el saldo pendiente (private_charges) se emparejaba
-- solo por número de documento normalizado, sin usar el vínculo real cuando existe
-- (appointment_id -> appointments.patient_id). Acotado a la misma organización, así que nunca
-- cruzaba entre clientes, pero si dos pacientes del mismo consultorio compartieran por error el
-- mismo número de documento escrito en private_charges.patient_doc, uno vería el saldo del otro.
--
-- Ahora se prioriza el vínculo por patient_id vía la cita (fuerte, sin ambigüedad posible) y el
-- documento queda solo como respaldo para cargos sueltos sin cita asociada
-- (appointment_id is null). Verificado con datos sintéticos en memoria: un cargo con cita de OTRO
-- paciente, aunque comparta el mismo documento, ya no se muestra; uno sin cita con el documento
-- correcto sigue mostrándose igual que antes.
create or replace function public.portal_view(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l public.patient_portal_links; p public.patients; o public.organizations; v_mode text; v_doc text;
begin
  if p_token is null or length(p_token) < 24 or length(p_token) > 64 or p_token !~ '^[A-Za-z0-9_-]+$' then
    raise exception 'Enlace no válido. Ábralo tal como le llegó por WhatsApp o pida uno nuevo a su consultorio.' using errcode = '22023';
  end if;
  select * into l from public.patient_portal_links where token_hash = app.sha256(p_token);
  if l.id is null or l.revoked_at is not null or l.expires_at <= now() then
    raise exception 'Este enlace venció o fue anulado. Pida uno nuevo a su consultorio.' using errcode = '42501';
  end if;
  -- 4.7.0 (SEG-35) · con el paciente desactivado o el consultorio inactivo no se muestra nada
  if not app.portal_subject_ok(l.patient_id, l.organization_id) then
    raise exception 'Este enlace ya no está disponible. Comuníquese con su consultorio.' using errcode = '42501';
  end if;
  v_mode := app.clinical_mode(l.organization_id);
  if v_mode = 'desactivada' then
    raise exception 'El portal de este consultorio no está disponible. Comuníquese con su consultorio.' using errcode = '42501';
  end if;
  select * into p from public.patients where id = l.patient_id;
  select * into o from public.organizations where id = l.organization_id;
  update public.patient_portal_links set views = views + 1, last_view_at = now() where id = l.id;
  insert into public.patient_portal_access (link_id, organization_id, patient_id) values (l.id, l.organization_id, l.patient_id);
  if l.show_orders then
    perform app.clinical_log(l.organization_id, l.patient_id, null, 'ver', 'portal del paciente');
  end if;
  v_doc := regexp_replace(coalesce(p.doc_number, ''), '[^0-9A-Za-z]', '', 'g');
  return jsonb_build_object(
    'test_mode', v_mode = 'prueba',
    'expires_at', l.expires_at,
    'clinic', jsonb_build_object('name', coalesce(o.trade_name, o.legal_name), 'phone', o.phone, 'whatsapp', o.whatsapp, 'address', o.address),
    'patient', jsonb_build_object('first_name', split_part(trim(p.full_name), ' ', 1),
                 'doc', case when length(v_doc) > 4 then repeat('•', length(v_doc) - 4) || right(v_doc, 4) else null end),
    'appointments', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'date', a.appointment_date, 'time', to_char(a.appointment_time, 'HH24:MI'),
                       'doctor', pr.full_name, 'status', a.status,
                       'change_requested', exists (select 1 from public.patient_portal_requests q where q.appointment_id = a.id and q.kind = 'cambio_cita' and q.status = 'pendiente'))
                       order by a.appointment_date, a.appointment_time)
                  from (select * from public.appointments a where a.patient_id = p.id and a.appointment_date >= current_date
                          and a.status in ('programada','confirmada','en_espera') order by a.appointment_date, a.appointment_time limit 10) a
                  left join public.providers pr on pr.id = a.provider_id), '[]'::jsonb),
    'orders', case when l.show_orders then coalesce((select jsonb_agg(jsonb_build_object('kind', c.kind, 'at', c.signed_at,
                       'doctor', (select full_name from public.profiles where id = c.signed_by), 'content', app.clinical_dec(c.content_enc)) order by c.signed_at desc)
                  from (select * from public.clinical_orders c where c.patient_id = p.id and c.signed_at > now() - interval '180 days' order by c.signed_at desc limit 20) c), '[]'::jsonb)
               else null end,
    'balance', jsonb_build_object(
      'items', coalesce((select jsonb_agg(jsonb_build_object('date', c.charge_date, 'service', c.service_name, 'amount', c.amount) order by c.charge_date)
                  from public.private_charges c
                  left join public.appointments ap on ap.id = c.appointment_id
                  where c.organization_id = l.organization_id and c.status = 'pendiente'
                    and (
                      (ap.patient_id is not null and ap.patient_id = p.id)
                      or (ap.patient_id is null and v_doc <> '' and regexp_replace(coalesce(c.patient_doc, ''), '[^0-9A-Za-z]', '', 'g') = v_doc)
                    )), '[]'::jsonb),
      'total', coalesce((select sum(c.amount) from public.private_charges c
                  left join public.appointments ap on ap.id = c.appointment_id
                  where c.organization_id = l.organization_id and c.status = 'pendiente'
                    and (
                      (ap.patient_id is not null and ap.patient_id = p.id)
                      or (ap.patient_id is null and v_doc <> '' and regexp_replace(coalesce(c.patient_doc, ''), '[^0-9A-Za-z]', '', 'g') = v_doc)
                    )), 0)));
end
$function$;
