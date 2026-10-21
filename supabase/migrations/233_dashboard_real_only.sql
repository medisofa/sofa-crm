-- 233 · Corrige dashboard interno y excluye DEMO de KPIs operacionales
begin;

CREATE OR REPLACE FUNCTION public.my_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid(); v_sections jsonb := '[]'::jsonb; v_org uuid; v_debt jsonb;
  v_today date := current_date; v_m1 date := date_trunc('month', current_date)::date; v_n numeric; v_a numeric; v_b numeric; v_c numeric;
begin
  if v_uid is null then
    raise exception 'Inicie sesión para ver su dashboard.' using errcode = '42501';
  end if;

  -- Médico
  select ou.organization_id into v_org from public.organization_users ou
   where ou.user_id = v_uid and ou.role_code = 'client' and coalesce(ou.is_active, true) order by ou.created_at limit 1;
  if v_org is not null then
    select count(*) filter (where a.appointment_date = v_today and a.status in ('programada','confirmada','en_espera')),
           count(*) filter (where a.appointment_date >= v_m1 and a.status = 'atendida')
      into v_n, v_a from public.appointments a where a.organization_id = v_org;
    select coalesce(sum(l.amount), 0) into v_b from public.service_lines l where l.organization_id = v_org and l.service_date >= v_m1;
    select coalesce(sum(b.balance), 0) into v_c from public.v_submission_balance b where b.organization_id = v_org and b.status in ('radicada','en_auditoria_ars');
    v_debt := public.sofa_debt_alert(v_org);
    v_sections := v_sections || jsonb_build_array(jsonb_build_object('code', 'medico', 'title', 'Mi consultorio',
      'alert', case when v_debt->>'level' <> 'al_dia' then v_debt end,
      'kpis', jsonb_build_array(
        app.kpi('citas_hoy', 'Citas de hoy', v_n),
        app.kpi('atendidas_mes', 'Pacientes atendidos este mes', v_a),
        app.kpi('reclamado_mes', 'Reclamado a las ARS este mes', v_b, 'RD$'),
        app.kpi('por_cobrar', 'Radicado pendiente de cobro', v_c, 'RD$'),
        app.kpi('deuda_sofa', 'Pendiente de pago a SOFA', (v_debt->>'pending')::numeric, 'RD$',
                case v_debt->>'level' when 'vencido' then 'critico' when 'pendiente' then 'atencion' else 'normal' end)),
      'shortcuts', jsonb_build_array('agenda', 'captura_rapida', 'reclamaciones')));
  end if;

  -- Secretaria
  if exists (select 1 from public.organization_users ou where ou.user_id = v_uid and ou.role_code = 'capturer' and coalesce(ou.is_active, true)) then
    select count(*) filter (where a.appointment_date = v_today and a.status in ('programada','confirmada','en_espera')),
           count(*) filter (where a.appointment_date = v_today + 1 and a.status in ('programada','confirmada')),
           count(*) filter (where a.appointment_date = v_today + 1 and a.status = 'programada')
      into v_n, v_a, v_b
      from public.appointments a where a.provider_id in (select app.capturer_providers());
    select count(*) into v_c from public.message_queue m
     where m.status = 'pendiente' and m.kind in ('recordatorio_cita','seguimiento_cita') and m.scheduled_for <= v_today + 1
       and m.provider_id in (select app.capturer_providers()) and app.capturer_can(m.provider_id, 'whatsapp');
    v_sections := v_sections || jsonb_build_array(jsonb_build_object('code', 'secretaria', 'title', 'Agenda del día',
      'kpis', jsonb_build_array(
        app.kpi('citas_hoy', 'Citas de hoy', v_n),
        app.kpi('citas_manana', 'Citas de mañana', v_a),
        app.kpi('sin_confirmar', 'Citas de mañana sin confirmar', v_b, 'n', case when v_b > 0 then 'atencion' else 'normal' end),
        app.kpi('whatsapp_pendientes', 'Mensajes de WhatsApp por enviar', v_c, 'n', case when v_c > 0 then 'atencion' else 'normal' end)),
      'shortcuts', jsonb_build_array('trabajo_hoy', 'nueva_cita')));
  end if;

  -- Facturación
  if app.is_staff(array['billing']) then
    select count(*) filter (where s.status = 'borrador'), count(*) filter (where s.status in ('recibida','en_depuracion')),
           count(*) filter (where s.status = 'pendiente_documentos'), count(*) filter (where s.status = 'lista_para_radicar')
      into v_n, v_a, v_b, v_c from public.submissions s
     where s.organization_id in (select id from public.sofa_real_client_organizations);
    v_sections := v_sections || jsonb_build_array(jsonb_build_object('code', 'facturacion', 'title', 'Facturación',
      'kpis', jsonb_build_array(
        app.kpi('borradores', 'Lotes en borrador', v_n),
        app.kpi('en_depuracion', 'Lotes recibidos o en depuración', v_a),
        app.kpi('pendiente_documentos', 'Lotes con documentos pendientes', v_b, 'n', case when v_b > 0 then 'atencion' else 'normal' end),
        app.kpi('listos_radicar', 'Listos para radicar (los radica SOFA oficina)', v_c)),
      'shortcuts', jsonb_build_array('trabajo_hoy', 'captura_rapida', 'reclamaciones', 'retiros_fisicos')));
  end if;

  -- Glosas
  if app.is_staff(array['glosas']) then
    select count(*) filter (where g.status not in ('aceptada','revertida','cerrada')),
           count(*) filter (where g.status not in ('aceptada','revertida','cerrada') and g.appeal_deadline between v_today and v_today + 7),
           count(*) filter (where g.status not in ('aceptada','revertida','cerrada') and g.appeal_deadline < v_today),
           count(*) filter (where g.status = 'en_arbitraje')
      into v_n, v_a, v_b, v_c from public.glosas g
     where g.organization_id in (select id from public.sofa_real_client_organizations);
    v_sections := v_sections || jsonb_build_array(jsonb_build_object('code', 'glosas', 'title', 'Glosas y cobros',
      'kpis', jsonb_build_array(
        app.kpi('abiertas', 'Glosas abiertas', v_n),
        app.kpi('vencen_7d', 'Plazo de apelación en los próximos 7 días', v_a, 'n', case when v_a > 0 then 'atencion' else 'normal' end),
        app.kpi('vencidas', 'Plazo de apelación vencido', v_b, 'n', case when v_b > 0 then 'critico' else 'normal' end),
        app.kpi('arbitraje', 'En arbitraje', v_c)),
      'shortcuts', '[]'::jsonb));
  end if;

  -- Comercial
  if app.is_staff(array['assistant']) then
    select count(*) filter (where o.stage not in ('cliente','perdido')),
           coalesce(sum(o.estimated_value * coalesce(o.probability, 0) / 100.0) filter (where o.stage not in ('cliente','perdido')), 0),
           count(*) filter (where o.stage not in ('cliente','perdido') and o.next_action_date < v_today)
      into v_n, v_a, v_b from public.opportunities o;
    select count(*) into v_c from public.leads l where l.created_at >= now() - interval '30 days';
    v_sections := v_sections || jsonb_build_array(jsonb_build_object('code', 'comercial', 'title', 'Comercial',
      'kpis', jsonb_build_array(
        app.kpi('oportunidades', 'Oportunidades abiertas', v_n),
        app.kpi('pipeline_ponderado', 'Valor ponderado del embudo', v_a, 'RD$'),
        app.kpi('acciones_vencidas', 'Próximas acciones vencidas', v_b, 'n', case when v_b > 0 then 'atencion' else 'normal' end),
        app.kpi('prospectos_30d', 'Prospectos nuevos (30 días)', v_c)),
      'shortcuts', '[]'::jsonb));
  end if;

  -- Dirección (Super Admin, Administrador, Operaciones, Auditoría)
  if app.is_staff(array['super_admin','admin','operations','auditor']) then
    select coalesce(sum(b.balance), 0) into v_n from public.v_submission_balance b
     where b.organization_id in (select id from public.sofa_real_client_organizations)
       and b.status in ('radicada','en_auditoria_ars');
    select coalesce(sum(i.total - coalesce((select sum(p.amount) from public.sofa_invoice_payments p where p.sofa_invoice_id = i.id), 0)), 0)
      into v_a from public.sofa_invoices i
     where i.organization_id in (select id from public.sofa_real_client_organizations)
       and i.status in ('emitida','pagada_parcial') and i.voided_at is null and i.due_on < v_today;
    select count(*) into v_b from public.organizations o
     where o.kind = 'client' and o.status = 'activo' and coalesce(o.is_demo,false)=false;
    select count(*) into v_c from public.alerts al
     where al.status = 'abierta'
       and (al.organization_id is null or al.organization_id in (select id from public.sofa_real_client_organizations));
    v_sections := v_sections || jsonb_build_array(jsonb_build_object('code', 'direccion', 'title', 'Dirección SOFA',
      'kpis', jsonb_build_array(
        app.kpi('cartera_ars', 'Cartera radicada por cobrar (ARS)', v_n, 'RD$'),
        app.kpi('honorarios_vencidos', 'Honorarios de SOFA vencidos', v_a, 'RD$', case when v_a > 0 then 'atencion' else 'normal' end),
        app.kpi('clientes_activos', 'Clientes activos', v_b),
        app.kpi('alertas_abiertas', 'Alertas abiertas', v_c, 'n', case when v_c > 0 then 'atencion' else 'normal' end)),
      'shortcuts', jsonb_build_array('radicacion', 'reclamaciones')));
  end if;

  return jsonb_build_object('generated_at', now(), 'sections', v_sections);
end
$function$;

commit;
