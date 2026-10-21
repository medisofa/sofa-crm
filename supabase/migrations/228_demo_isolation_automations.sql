-- 228 · Aislamiento DEMO en automatizaciones programadas
-- Cron/global excluye DEMO; acciones explícitas por médico/cliente siguen disponibles para pruebas.
begin;

CREATE OR REPLACE FUNCTION app.ecf_followup()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_th smallint; v_task uuid; n int := 0;
begin
  for r in select o.id, o.operator_id, coalesce(o.trade_name, o.legal_name) client, o.ecf_required_from, o.ecf_required_from - current_date days_left, o.ecf_status
             from public.organizations o where o.kind = 'client' and o.status in ('activo','incorporacion') and o.ecf_status <> 'listo'
              and (auth.uid() is not null or coalesce(o.is_demo,false)=false)
              and o.ecf_required_from - current_date between 0 and 30 loop
    v_th := case when r.days_left <= 7 then 7 when r.days_left <= 15 then 15 else 30 end;
    continue when exists (select 1 from public.ecf_followup_log where organization_id = r.id and threshold = v_th and required_from = r.ecf_required_from);
    insert into public.tasks (operator_id, organization_id, title, priority, due_date, entity_type, entity_id, notes)
    values (r.operator_id, r.id, left(format('e-CF: %s no está listo (faltan %s días)', r.client, r.days_left), 200), case when v_th <= 15 then 'alta' else 'media' end,
            current_date + 2, 'organization', r.id, 'Revise los pasos en Facturación ARS › Preparación e-CF. Desde la fecha, los lotes sin E31 aceptado no se radican.')
    returning id into v_task;
    insert into public.ecf_followup_log (organization_id, threshold, required_from, task_id) values (r.id, v_th, r.ecf_required_from, v_task);
    insert into public.notifications (user_id, title, body, link)
    select ou.user_id, format('Facturación electrónica: faltan %s días', r.days_left),
           format('Desde el %s sus lotes a las ARS necesitan e-CF (E31) aceptado por la DGII. Revise los pasos que faltan.', to_char(r.ecf_required_from, 'DD/MM/YYYY')),
           '#/mi-cuenta-sofa'
      from public.organization_users ou where ou.organization_id = r.id and ou.role_code = 'client' and ou.is_active;
    n := n + 1;
  end loop;
  return n;
end
$function$;

CREATE OR REPLACE FUNCTION app.glosa_response_followup()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int := coalesce((select glosa_response_business_days from public.app_settings limit 1), 7); r record; k int := 0;
begin
  for r in select g.id, g.organization_id, g.folio, o.operator_id, coalesce(o.trade_name, o.legal_name) client, app.add_business_days(g.notified_on, v_n) due
             from public.glosas g join public.organizations o on o.id = g.organization_id
            where g.status in ('pendiente','analizada') and app.glosa_answered_on(g.id) is null
              and (auth.uid() is not null or coalesce(o.is_demo,false)=false) loop
    continue when app.business_days_between(current_date, r.due) > 1;
    continue when exists (select 1 from public.tasks t where t.entity_type = 'glosa' and t.entity_id = r.id and t.status = 'abierta' and t.title like 'Responder glosa%');
    insert into public.tasks (operator_id, organization_id, title, priority, due_date, entity_type, entity_id, notes)
    values (r.operator_id, r.organization_id, left(format('Responder glosa %s · %s (vence %s)', coalesce(r.folio, ''), r.client, to_char(r.due, 'DD/MM/YYYY')), 200), 'alta',
            r.due, 'glosa', r.id, format('Plazo interno de %s días hábiles. Registre la apelación o la decisión en Cobros › Glosas.', v_n));
    k := k + 1;
  end loop;
  return k;
end
$function$;

CREATE OR REPLACE FUNCTION app.habilitation_followup()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_kind text; v_task uuid; n int := 0;
begin
  for r in select c.*, c.license_valid_until - current_date days_left from public.habilitation_cases c
            where c.stage = 'habilitado' and c.license_valid_until is not null and c.license_valid_until - current_date between 0 and 90
              and (auth.uid() is not null or c.organization_id is null or c.organization_id in (select id from public.sofa_real_client_organizations)) loop
    v_kind := case when r.days_left <= 30 then 'licencia_30' else 'licencia_90' end;
    continue when exists (select 1 from public.habilitation_followup_log where case_id = r.id and kind = v_kind and ref_date = r.license_valid_until);
    insert into public.tasks (operator_id, organization_id, title, priority, due_date, entity_type, entity_id, notes)
    values (r.operator_id, r.organization_id, left(format('Renovar habilitación %s · vence %s', r.establishment_name, to_char(r.license_valid_until, 'DD/MM/YYYY')), 200),
            case when v_kind = 'licencia_30' then 'alta' else 'media' end, current_date + 7, 'habilitation', r.id,
            'Abra el caso de renovación (Habilitación › nuevo caso, tipo «renovación») y avise al cliente.')
    returning id into v_task;
    insert into public.habilitation_followup_log (case_id, kind, ref_date, task_id) values (r.id, v_kind, r.license_valid_until, v_task);
    n := n + 1;
  end loop;
  for r in select c.* from public.habilitation_cases c where c.stage = 'habilitado' and coalesce(trim(c.pss_code), '') = ''
              and (auth.uid() is not null or c.organization_id is null or c.organization_id in (select id from public.sofa_real_client_organizations)) loop
    continue when exists (select 1 from public.habilitation_followup_log where case_id = r.id and kind = 'pss');
    insert into public.tasks (operator_id, organization_id, title, priority, due_date, entity_type, entity_id, notes)
    values (r.operator_id, r.organization_id, left(format('Tramitar código PSS · %s', r.establishment_name), 200), 'alta', current_date + 5, 'habilitation', r.id,
            'Sin código PSS no se puede facturar a las ARS. Tramítelo ante la SISALRIL y regístrelo en el caso.')
    returning id into v_task;
    insert into public.habilitation_followup_log (case_id, kind, ref_date, task_id) values (r.id, 'pss', current_date, v_task);
    n := n + 1;
  end loop;
  return n;
end
$function$;

CREATE OR REPLACE FUNCTION app.next_day_reminders()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_d date := current_date + case when extract(isodow from current_date) = 6 then 2 else 1 end; n int := 0;
begin
  with pend as (
      select ap.organization_id, ap.provider_id, count(*) k from public.appointments ap
       where ap.appointment_date = v_d and ap.payer_type = 'ars' and ap.status in ('programada','confirmada') and ap.eligibility_status = 'no_verificada'
         and (auth.uid() is not null or ap.organization_id in (select id from public.sofa_real_client_organizations))
       group by 1, 2),
    users as (
      select ou.user_id, sum(p.k) k from pend p join public.organization_users ou on ou.organization_id = p.organization_id and ou.is_active and ou.role_code = 'client' group by 1
      union all
      select cs.user_id, sum(p.k) from pend p join public.capturer_scopes cs on cs.provider_id = p.provider_id and cs.organization_id = p.organization_id group by 1),
    agg as (select user_id, sum(k) k from users group by 1),
    ins as (
      insert into public.notifications (user_id, title, body, link)
      select a.user_id, format('Mañana: %s cita(s) ARS sin verificar', a.k),
             format('Verifique la elegibilidad y la autorización antes del %s para evitar glosas por afiliado no vigente o sin autorización.', to_char(v_d, 'DD/MM/YYYY')),
             '#/verificacion'
        from agg a
       where not exists (select 1 from public.notifications x where x.user_id = a.user_id and x.link = '#/verificacion' and x.created_at::date = current_date)
      returning 1)
  select count(*) into n from ins;
  return n;
end
$function$;

CREATE OR REPLACE FUNCTION app.onboarding_followup()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o record; p jsonb; m jsonb; v_task uuid; n int := 0;
begin
  for o in select id, operator_id, coalesce(trade_name, legal_name) client from public.organizations
            where kind = 'client' and status in ('incorporacion','activo') and coalesce(activated_at::date, started_on, created_at::date) between current_date - 45 and current_date
              and (auth.uid() is not null or coalesce(is_demo,false)=false) loop
    p := public.onboarding_plan(o.id);
    for m in select * from jsonb_array_elements(p->'milestones') loop
      continue when (m->>'done')::boolean;
      continue when current_date < (m->>'due')::date - case when (m->>'day')::int = 30 then 3 else 0 end;
      continue when exists (select 1 from public.onboarding_followup_log where organization_id = o.id and milestone = (m->>'day')::int);
      insert into public.tasks (operator_id, organization_id, title, priority, due_date, entity_type, entity_id, notes)
      values (o.operator_id, o.id, left(format('Onboarding día %s · %s: %s', m->>'day', o.client, m->>'label'), 200),
              case when (m->>'day')::int = 30 then 'alta' else 'media' end, greatest((m->>'due')::date, current_date), 'organization', o.id,
              'Falta: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(m->'missing') x) || '. Vea Clientes › Onboarding 30 días.')
      returning id into v_task;
      insert into public.onboarding_followup_log (organization_id, milestone, task_id) values (o.id, (m->>'day')::int, v_task);
      n := n + 1;
    end loop;
  end loop;
  return n;
end
$function$;

CREATE OR REPLACE FUNCTION app.sub_advance_core(p_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s record; v_chg text; v_changes jsonb := '[]'::jsonb; v_drafts int;
begin
  for s in select x.id, x.organization_id from public.subscriptions x where x.state <> 'cancelada' and (auth.uid() is not null or x.organization_id in (select id from public.sofa_real_client_organizations)) order by x.created_at loop
    v_chg := app.sub_advance_one(s.id, p_on);
    if v_chg is not null then v_changes := v_changes || jsonb_build_array(jsonb_build_object('organization_id', s.organization_id, 'estado', v_chg)); end if;
  end loop;
  v_drafts := app.sub_generate_due(p_on);
  return jsonb_build_object('al', p_on, 'cambios', v_changes, 'borradores_generados', v_drafts);
end $function$;

CREATE OR REPLACE FUNCTION app.sub_generate_due(p_on date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s record; v_n int := 0;
begin
  for s in select x.organization_id, x.next_billing_on, x.cycle from public.subscriptions x
            where x.state = 'activa' and x.next_billing_on is not null and x.next_billing_on <= p_on and x.cancel_effective_on is null
              and (auth.uid() is not null or x.organization_id in (select id from public.sofa_real_client_organizations)) loop
    begin
      perform app.sub_generate(s.organization_id, s.next_billing_on, case when s.cycle = 'anual' then 'anual' else 'mensual' end, 'Generada por el calendario de suscripciones');
      v_n := v_n + 1;
    exception when others then
      perform app.sub_log(s.organization_id, null, 'prefactura_no_generada', null, null, jsonb_build_object('motivo', left(sqlerrm, 250), 'periodo', s.next_billing_on));
    end;
  end loop;
  return v_n;
end $function$;

CREATE OR REPLACE FUNCTION app.email_vars_glosas(p_user uuid, p_today date, p_days integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int; v_amt numeric; v_first date; v_li text; v_tx text; v_multi boolean;
begin
  with g as (
    select gl.appeal_deadline dl, coalesce(nullif(gl.folio, ''), 'sin folio') folio, coalesce(o.trade_name, o.legal_name) cname, coalesce(a.name, 'ARS') arsn, gl.organization_id oid,
           coalesce((select sum(i.amount) from public.glosa_items i where i.glosa_id = gl.id), 0) amt
      from public.glosas gl
      join public.organizations o on o.id = gl.organization_id
      join public.submissions s on s.id = gl.submission_id
      left join public.ars a on a.id = s.ars_id
     where gl.organization_id in (select app.email_user_orgs(p_user, 'equipo'))
       and (auth.uid() is not null or gl.organization_id in (select id from public.sofa_real_client_organizations))
       and gl.status in ('pendiente', 'analizada') and gl.appeal_deadline between p_today and p_today + greatest(p_days, 1)
  ), x as (select g.*, row_number() over (order by dl, folio, cname) rn from g)
  select count(*), coalesce(sum(amt), 0), min(dl), count(distinct oid) > 1,
         string_agg('<li>Glosa ' || app.email_esc(folio) || ' · ' || app.email_esc(arsn) || case when (select count(distinct oid) from g) > 1 then ' · ' || app.email_esc(cname) else '' end
                    || ' · vence ' || app.email_date(dl) || ' · ' || app.email_money(amt) || '</li>', '' order by dl, folio, cname) filter (where rn <= 10),
         string_agg('- Glosa ' || folio || ' · ' || arsn || case when (select count(distinct oid) from g) > 1 then ' · ' || cname else '' end
                    || ' · vence ' || app.email_date(dl) || ' · ' || app.email_money(amt), E'\n' order by dl, folio, cname) filter (where rn <= 10)
    into v_n, v_amt, v_first, v_multi, v_li, v_tx
    from x;
  if v_n = 0 then return null; end if;
  return jsonb_build_object('nombre', app.email_user_name(p_user), 'n_glosas', v_n, 'monto_glosado', app.email_money(v_amt), 'proximo_vencimiento', app.email_date(v_first), 'dias_aviso', greatest(p_days, 1),
    'detalle_html', '<ul style="padding-left:18px;margin:8px 0">' || v_li || '</ul>' || case when v_n > 10 then '<p>… y ' || (v_n - 10) || ' más.</p>' else '' end,
    'detalle_text', v_tx || case when v_n > 10 then E'\n… y ' || (v_n - 10) || ' más.' else '' end);
end $function$;

CREATE OR REPLACE FUNCTION app.email_vars_pagos(p_user uuid, p_from date, p_to date, p_payment uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int; v_amt numeric; v_ars text; v_li text; v_tx text;
begin
  with g as (
    select py.paid_on, py.amount amt, coalesce(a.name, 'ARS') arsn, py.id
      from public.payments py left join public.ars a on a.id = py.ars_id
     where py.organization_id in (select app.email_user_orgs(p_user, 'medico'))
       and (auth.uid() is not null or py.organization_id in (select id from public.sofa_real_client_organizations))
       and (p_payment is null or py.id = p_payment)
       and (py.created_at at time zone 'America/Santo_Domingo')::date between p_from and p_to
  ), x as (select g.*, row_number() over (order by paid_on desc, arsn, id) rn from g)
  select count(*), coalesce(sum(amt), 0), string_agg(distinct arsn, ', '),
         string_agg('<li>' || app.email_date(paid_on) || ' · ' || app.email_esc(arsn) || ' · ' || app.email_money(amt) || '</li>', '' order by paid_on desc, arsn, id) filter (where rn <= 10),
         string_agg('- ' || app.email_date(paid_on) || ' · ' || arsn || ' · ' || app.email_money(amt), E'\n' order by paid_on desc, arsn, id) filter (where rn <= 10)
    into v_n, v_amt, v_ars, v_li, v_tx from x;
  if v_n = 0 then return null; end if;
  return jsonb_build_object('nombre', app.email_user_name(p_user), 'n_pagos', v_n, 'monto_total', app.email_money(v_amt), 'arss', v_ars,
    'detalle_html', '<ul style="padding-left:18px;margin:8px 0">' || v_li || '</ul>' || case when v_n > 10 then '<p>… y ' || (v_n - 10) || ' más.</p>' else '' end,
    'detalle_text', v_tx || case when v_n > 10 then E'\n… y ' || (v_n - 10) || ' más.' else '' end);
end $function$;

CREATE OR REPLACE FUNCTION app.email_vars_resumen(p_user uuid, p_from date, p_to date, p_today date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rad int; v_rad_m numeric; v_pag int; v_pag_m numeric; v_gn int; v_gn_m numeric; v_ga int; v_gv int;
begin
  if not exists (select 1 from app.email_user_orgs(p_user, 'medico')) then return null; end if;
  select count(distinct s.id), coalesce(sum(sl.amount), 0) into v_rad, v_rad_m
    from public.submissions s left join public.service_lines sl on sl.submission_id = s.id
   where s.organization_id in (select app.email_user_orgs(p_user, 'medico')) and (auth.uid() is not null or s.organization_id in (select id from public.sofa_real_client_organizations)) and s.submitted_on between p_from and p_to;
  select count(*), coalesce(sum(py.amount), 0) into v_pag, v_pag_m
    from public.payments py where py.organization_id in (select app.email_user_orgs(p_user, 'medico')) and (auth.uid() is not null or py.organization_id in (select id from public.sofa_real_client_organizations)) and py.paid_on between p_from and p_to;
  select count(*), coalesce(sum((select sum(i.amount) from public.glosa_items i where i.glosa_id = g.id)), 0) into v_gn, v_gn_m
    from public.glosas g where g.organization_id in (select app.email_user_orgs(p_user, 'medico')) and (auth.uid() is not null or g.organization_id in (select id from public.sofa_real_client_organizations)) and g.notified_on between p_from and p_to;
  select count(*), count(*) filter (where g.appeal_deadline between p_today and p_today + 7) into v_ga, v_gv
    from public.glosas g where g.organization_id in (select app.email_user_orgs(p_user, 'medico')) and (auth.uid() is not null or g.organization_id in (select id from public.sofa_real_client_organizations)) and g.status in ('pendiente', 'analizada');
  if v_rad = 0 and v_pag = 0 and v_gn = 0 and v_ga = 0 then return null; end if;
  return jsonb_build_object('nombre', app.email_user_name(p_user), 'periodo', app.email_date(p_from) || ' y ' || app.email_date(p_to),
    'n_radicadas', v_rad, 'monto_radicado', app.email_money(v_rad_m), 'n_pagos', v_pag, 'monto_pagado', app.email_money(v_pag_m),
    'n_glosas_nuevas', v_gn, 'monto_glosas_nuevas', app.email_money(v_gn_m), 'n_glosas_abiertas', v_ga, 'n_glosas_por_vencer', v_gv);
end $function$;

CREATE OR REPLACE FUNCTION app.email_gen_pagos(p_today date DEFAULT NULL::date, p_modes text DEFAULT 'ambos'::text, p_operator uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_today date := coalesce(p_today, app.email_today()); u uuid; pr record; v jsonb; n int := 0; s public.email_settings; py record; v_since timestamptz;
begin
  if p_modes not in ('ambos', 'inmediato', 'diario') then raise exception 'Modo no válido: use ambos, inmediato o diario.' using errcode = '22023'; end if;
  for u in select * from app.email_audience_users('pago_recibido', p_operator) loop
    select * into s from public.email_settings x where x.operator_id = app.email_user_operator(u);
    continue when not coalesce(s.enabled, false);
    select * into pr from app.email_pref(u, 'pago_recibido');
    continue when not pr.r_enabled;
    if pr.r_frequency = 'inmediato' and p_modes in ('ambos', 'inmediato') then
      -- solo pagos registrados después de que la persona activó el aviso (y no más viejos de 3 días)
      select greatest(coalesce((select x.updated_at from public.email_preferences x where x.user_id = u and x.topic = 'pago_recibido'), now()), now() - interval '3 days') into v_since;
      for py in select y.id, y.organization_id from public.payments y
                 where y.organization_id in (select app.email_user_orgs(u, 'medico'))
                   and (auth.uid() is not null or y.organization_id in (select id from public.sofa_real_client_organizations))
                   and y.created_at >= v_since order by y.created_at loop
        v := app.email_vars_pagos(u, '2000-01-01'::date, '2100-01-01'::date, py.id);
        continue when v is null;
        if app.email_enqueue(u, 'pago_recibido', v, 'pago:' || py.id || ':' || u, py.organization_id) is not null then n := n + 1; end if;
      end loop;
    elsif pr.r_frequency = 'diario' and p_modes in ('ambos', 'diario') then
      v := app.email_vars_pagos(u, v_today - 1, v_today - 1);
      continue when v is null;
      if app.email_enqueue(u, 'pago_recibido', v, 'pagos:' || u || ':' || v_today, null) is not null then n := n + 1; end if;
    end if;
  end loop;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.ars_codes_followup(p_days integer DEFAULT 30, p_every integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_n int := 0;
begin
  if auth.uid() is not null and not app.is_staff(array['super_admin','admin','assistant','operations']) then
    raise exception 'Solo el equipo SOFA genera los recordatorios de códigos.' using errcode = '42501';
  end if;
  for r in
    select c.id, c.organization_id, o.operator_id, o.legal_name, pr.full_name, a.name as ars, c.request_number,
           current_date - coalesce(c.requested_on, c.status_changed_at::date) as days
      from public.provider_ars_codes c
      join public.providers pr on pr.id = c.provider_id
      join public.organizations o on o.id = c.organization_id
      join public.ars a on a.id = c.ars_id
     where c.status in ('solicitado','pendiente_respuesta')
       and current_date - coalesce(c.requested_on, c.status_changed_at::date) > p_days
       and (c.last_reminder_at is null or c.last_reminder_at < now() - make_interval(days => p_every))
       and o.status in ('activo','incorporacion')
       and (auth.uid() is not null or coalesce(o.is_demo,false)=false)
     for update of c skip locked
  loop
    insert into public.tasks (operator_id, organization_id, title, priority, due_date, entity_type, entity_id, notes)
    values (r.operator_id, r.organization_id, left(format('Seguimiento código %s · %s', r.ars, r.full_name), 200), 'alta', current_date,
            'organization', r.organization_id,
            format('%s días sin respuesta de %s%s. Llamar o escribir a la ARS y actualizar el estado en la ficha del cliente (%s).',
                   r.days, r.ars, coalesce(' · solicitud ' || r.request_number, ''), r.legal_name));
    update public.provider_ars_codes set last_reminder_at = now() where id = r.id;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('tasks_created', v_n);
end
$function$;

CREATE OR REPLACE FUNCTION public.generate_appointment_reminders(p_days integer DEFAULT 1, p_provider uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n integer := 0; v_rows integer;
begin
  if p_days is null or p_days < 0 or p_days > 7 then
    raise exception 'Los días de anticipación deben estar entre 0 y 7. Corrija el valor e intente de nuevo.' using errcode = '22023';
  end if;
  if p_provider is null then
    if auth.uid() is not null and not app.is_staff(array['super_admin','admin']) then
      raise exception 'Indique el médico, o pida al Administrador que genere los recordatorios de todos.' using errcode = '42501';
    end if;
  elsif not app.consultorio_access(p_provider, true) then
    raise exception 'Sin acceso para generar recordatorios de este médico. Pide al Administrador que le asigne el consultorio.' using errcode = '42501';
  end if;

  insert into public.message_queue (organization_id, provider_id, kind, appointment_id, to_phone, subject, body, scheduled_for)
  select a.organization_id, a.provider_id, 'recordatorio_cita', a.id, a.phone, 'Recordatorio de cita',
         format('Hola %s, le recordamos su cita con %s el %s a las %s.%s Si no puede asistir, avísenos con anticipación respondiendo este mensaje.',
                a.patient_name, pr.full_name, to_char(a.appointment_date, 'DD/MM/YYYY'),
                to_char(date '2000-01-01' + a.appointment_time, 'HH12:MI AM'),
                case when a.payer_type = 'ars' then ' Traiga su carnet de la ARS y su cédula.' else '' end),
         a.appointment_date
    from public.appointments a join public.providers pr on pr.id = a.provider_id
   where a.appointment_date = current_date + p_days and a.status in ('programada','confirmada')
     and length(regexp_replace(coalesce(a.phone, ''), '\D', '', 'g')) >= 10
     and (p_provider is null or a.provider_id = p_provider)
     and (p_provider is not null or a.organization_id in (select id from public.sofa_real_client_organizations))
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  v_n := v_rows;
  return v_n;
end
$function$;

CREATE OR REPLACE FUNCTION public.generate_followups(p_provider uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n integer;
begin
  if p_provider is null then
    if auth.uid() is not null and not app.is_staff(array['super_admin','admin']) then
      raise exception 'Indique el médico, o pida al Administrador que genere los seguimientos de todos.' using errcode = '42501';
    end if;
  elsif not app.consultorio_access(p_provider, true) then
    raise exception 'Sin acceso para generar seguimientos de este médico. Pida al Administrador que le asigne el consultorio.' using errcode = '42501';
  end if;

  insert into public.message_queue (organization_id, provider_id, kind, appointment_id, to_phone, subject, body, scheduled_for)
  select a.organization_id, a.provider_id, 'seguimiento_cita', a.id, a.phone, 'Seguimiento de su consulta',
         replace(replace(coalesce(s.followup_text,
           'Hola {paciente}, le saluda el consultorio de {medico}. ¿Cómo se ha sentido después de su consulta? Si tiene alguna duda o molestia, respóndanos este mensaje.'),
           '{paciente}', a.patient_name), '{medico}', pr.full_name),
         current_date
    from public.appointments a
    join public.providers pr on pr.id = a.provider_id
    join public.provider_message_settings s on s.provider_id = a.provider_id and s.followup_enabled
   where a.status = 'atendida' and a.appointment_date = current_date - s.followup_days
     and length(regexp_replace(coalesce(a.phone, ''), '\D', '', 'g')) >= 10
     and (p_provider is null or a.provider_id = p_provider)
     and (p_provider is not null or a.organization_id in (select id from public.sofa_real_client_organizations))
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end
$function$;

CREATE OR REPLACE FUNCTION public.generate_patient_notices(p_provider uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ctrl int; v_rep int;
begin
  if p_provider is null then
    if auth.uid() is not null and not app.is_staff(array['super_admin','admin']) then
      raise exception 'Indique el médico, o pida al Administrador que genere los avisos de todos.' using errcode = '42501';
    end if;
  elsif not app.consultorio_access(p_provider, true) then
    raise exception 'Sin acceso para generar avisos de este médico. Pida al Administrador que le asigne el consultorio.' using errcode = '42501';
  end if;

  -- 1) Control periódico (por paciente del registro, según su última cita atendida con ese médico)
  insert into public.message_queue (organization_id, provider_id, kind, patient_id, to_phone, subject, body, scheduled_for)
  select x.organization_id, x.provider_id, 'control_pendiente', x.patient_id, x.phone, 'Consulta de control',
         replace(replace(coalesce(x.control_text,
           'Hola {paciente}, le saluda el consultorio de {medico}. Ya le toca su consulta de control. Responda este mensaje y le damos una cita.'),
           '{paciente}', x.patient_name), '{medico}', x.provider_name), current_date
    from (select distinct on (a.patient_id, a.provider_id)
                 a.organization_id, a.provider_id, a.patient_id, coalesce(pt.phone, a.phone) phone, pt.full_name patient_name, pr.full_name provider_name,
                 s.control_text, s.control_months, a.appointment_date last_seen
            from public.appointments a
            join public.patients pt on pt.id = a.patient_id and pt.is_active
            join public.providers pr on pr.id = a.provider_id
            join public.provider_message_settings s on s.provider_id = a.provider_id and s.control_enabled
           where a.status = 'atendida' and (p_provider is null or a.provider_id = p_provider)
             and (p_provider is not null or a.organization_id in (select id from public.sofa_real_client_organizations))
           order by a.patient_id, a.provider_id, a.appointment_date desc) x
   where x.last_seen <= (current_date - make_interval(months => x.control_months))::date
     and length(regexp_replace(coalesce(x.phone, ''), '\D', '', 'g')) >= 10
     and not exists (select 1 from public.appointments f where f.patient_id = x.patient_id and f.provider_id = x.provider_id
                      and f.appointment_date >= current_date and f.status in ('programada','confirmada','en_espera'))
     and not exists (select 1 from public.message_queue m where m.patient_id = x.patient_id and m.provider_id = x.provider_id
                      and m.kind = 'control_pendiente' and m.created_at > now() - make_interval(months => x.control_months));
  get diagnostics v_ctrl = row_count;

  -- 2) Reprogramar inasistencias de los últimos 7 días
  insert into public.message_queue (organization_id, provider_id, kind, appointment_id, patient_id, to_phone, subject, body, scheduled_for)
  select a.organization_id, a.provider_id, 'reprogramar_cita', a.id, a.patient_id, a.phone, 'Reprogramar su cita',
         replace(replace(coalesce(s.noshow_text,
           'Hola {paciente}, le esperábamos en su cita con {medico}. ¿Desea que le demos una nueva fecha? Responda este mensaje.'),
           '{paciente}', a.patient_name), '{medico}', pr.full_name), current_date
    from public.appointments a
    join public.providers pr on pr.id = a.provider_id
    join public.provider_message_settings s on s.provider_id = a.provider_id and s.noshow_enabled
   where a.status = 'no_asistio' and a.appointment_date between current_date - 7 and current_date
     and (p_provider is null or a.provider_id = p_provider)
     and (p_provider is not null or a.organization_id in (select id from public.sofa_real_client_organizations))
     and length(regexp_replace(coalesce(a.phone, ''), '\D', '', 'g')) >= 10
     and not exists (select 1 from public.appointments f where f.provider_id = a.provider_id and f.id <> a.id
                      and f.appointment_date >= a.appointment_date and f.status in ('programada','confirmada','en_espera','atendida')
                      and ((a.patient_id is not null and f.patient_id = a.patient_id)
                        or (a.patient_doc is not null and f.patient_doc = a.patient_doc)
                        or (f.phone = a.phone)))
  on conflict do nothing;
  get diagnostics v_rep = row_count;

  return jsonb_build_object('control', v_ctrl, 'reprogramar', v_rep);
end
$function$;

CREATE OR REPLACE FUNCTION public.generate_weekly_summaries(p_week_start date DEFAULT (date_trunc('week'::text, (CURRENT_DATE)::timestamp with time zone))::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record; v_week date := date_trunc('week', coalesce(p_week_start, current_date))::date;
  v_data jsonb; v_text text; v_id uuid; v_n integer := 0;
begin
  if auth.uid() is not null and not app.is_staff(array['super_admin','admin']) then
    raise exception 'Solo Super Admin o Administrador SOFA genera los resúmenes semanales.' using errcode = '42501';
  end if;
  for r in select pr.id provider_id, pr.full_name, pr.organization_id, coalesce(o.whatsapp, o.phone) phone
             from public.providers pr join public.organizations o on o.id = pr.organization_id
            where pr.is_active and o.kind = 'client' and o.status = 'activo'
              and (auth.uid() is not null or coalesce(o.is_demo,false)=false) order by pr.full_name loop
    v_data := app.weekly_summary_data(r.provider_id, v_week);
    v_text := app.weekly_summary_text(v_data);
    v_id := null;
    insert into public.message_queue (organization_id, provider_id, kind, to_phone, subject, body, scheduled_for)
    values (r.organization_id, r.provider_id, 'resumen_semanal', r.phone, 'Resumen semanal · ' || r.full_name, v_text, v_week)
    on conflict do nothing returning id into v_id;
    if v_id is not null then
      insert into public.notifications (user_id, title, body, link)
      select ou.user_id, 'Resumen semanal · ' || r.full_name, v_text, '#/resumen-semanal'
        from public.organization_users ou where ou.organization_id = r.organization_id and ou.role_code = 'client' and ou.is_active;
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end
$function$;

CREATE OR REPLACE FUNCTION public.legal_audit_sample(p_org uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_hi int := 0; v_rnd int := 0; s record;
begin
  if auth.uid() is not null and not app.legal_audit_staff(true) then
    raise exception 'Solo el Auditor, el Administrador o el Super Admin selecciona la muestra.' using errcode = '42501';
  end if;
  for s in select * from public.legal_audit_settings where active and (p_org is null or organization_id = p_org)
             and (p_org is not null or organization_id in (select id from public.sofa_real_client_organizations))
             and (auth.uid() is null or organization_id in (select app.visible_org_ids())) loop
    with c as (
      select l.id, l.organization_id, sub.provider_id, l.amount
        from public.service_lines l join public.submissions sub on sub.id = l.submission_id
       where l.organization_id = s.organization_id and app.is_editable_status(sub.status) and sub.submitted_on is null
         and not exists (select 1 from public.legal_audit_reviews r where r.service_line_id = l.id)),
    ins as (
      insert into public.legal_audit_reviews (service_line_id, organization_id, provider_id, reason)
      select id, organization_id, provider_id, 'alto_valor' from c where amount >= s.high_value_from
      returning 1)
    select count(*) into v_hi from ins;
    v_hi := coalesce(v_hi, 0);
    with c as (
      select l.id, l.organization_id, sub.provider_id
        from public.service_lines l join public.submissions sub on sub.id = l.submission_id
       where l.organization_id = s.organization_id and app.is_editable_status(sub.status) and sub.submitted_on is null and l.amount < s.high_value_from
         and not exists (select 1 from public.legal_audit_reviews r where r.service_line_id = l.id)),
    pick as (select * from c order by random() limit (select ceil(count(*) * s.random_pct / 100.0)::int from c)),
    ins as (insert into public.legal_audit_reviews (service_line_id, organization_id, provider_id, reason) select id, organization_id, provider_id, 'aleatoria' from pick returning 1)
    select v_rnd + count(*) into v_rnd from ins;
  end loop;
  return jsonb_build_object('alto_valor', v_hi, 'aleatoria', v_rnd);
end
$function$;

CREATE OR REPLACE FUNCTION public.link_patients(p_org uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_new int := 0; v_n int; v_apt int := 0; v_cl int := 0;
begin
  if p_org is null then
    if auth.uid() is not null and not app.is_staff(array['super_admin','admin']) then
      raise exception 'Indique el consultorio, o pida al Administrador que vincule los pacientes de todos.' using errcode = '42501';
    end if;
  elsif not app.patient_access(p_org) then
    raise exception 'Sin acceso a los pacientes de este consultorio.' using errcode = '42501';
  end if;

  -- Fuente: citas y reclamaciones con documento o afiliado
  create temporary table if not exists tmp_pat_src (organization_id uuid, full_name text, doc_number text, member_number text, ars_id uuid, phone text, seen date) on commit drop;
  delete from tmp_pat_src where true;
  insert into tmp_pat_src
  select a.organization_id, trim(a.patient_name), nullif(upper(regexp_replace(coalesce(a.patient_doc, ''), '[\s-]', '', 'g')), ''),
         nullif(trim(coalesce(a.member_number, '')), ''), a.ars_id, nullif(trim(coalesce(a.phone, '')), ''), a.appointment_date
    from public.appointments a where (p_org is null or a.organization_id = p_org)
     and (p_org is not null or a.organization_id in (select id from public.sofa_real_client_organizations)) and length(trim(coalesce(a.patient_name, ''))) >= 3
  union all
  select l.organization_id, trim(l.patient_name), nullif(upper(regexp_replace(coalesce(l.patient_doc, ''), '[\s-]', '', 'g')), ''),
         nullif(trim(coalesce(l.member_number, '')), ''), s.ars_id, null, l.service_date
    from public.service_lines l join public.submissions s on s.id = l.submission_id
   where (p_org is null or l.organization_id = p_org)
     and (p_org is not null or l.organization_id in (select id from public.sofa_real_client_organizations)) and length(trim(coalesce(l.patient_name, ''))) >= 3;
  delete from tmp_pat_src where doc_number is not null and length(doc_number) not between 5 and 20;

  -- 1) Con documento
  insert into public.patients (organization_id, full_name, doc_number, member_number, ars_id, phone)
  select distinct on (organization_id, doc_number) organization_id, full_name, doc_number, member_number, ars_id, phone
    from tmp_pat_src t where doc_number is not null
     and not exists (select 1 from public.patients p where p.organization_id = t.organization_id and p.doc_number = t.doc_number)
   order by organization_id, doc_number, seen desc
  on conflict do nothing;
  get diagnostics v_n = row_count; v_new := v_new + v_n;
  -- 2) Solo con afiliado + ARS
  insert into public.patients (organization_id, full_name, member_number, ars_id, phone)
  select distinct on (organization_id, ars_id, member_number) organization_id, full_name, member_number, ars_id, phone
    from tmp_pat_src t where doc_number is null and member_number is not null and ars_id is not null
     and not exists (select 1 from public.patients p where p.organization_id = t.organization_id and p.ars_id = t.ars_id and p.member_number = t.member_number)
   order by organization_id, ars_id, member_number, seen desc
  on conflict do nothing;
  get diagnostics v_n = row_count; v_new := v_new + v_n;

  -- 3) Vincular citas
  update public.appointments a set patient_id = p.id
    from public.patients p
   where a.patient_id is null and p.organization_id = a.organization_id and (p_org is null or a.organization_id = p_org)
     and (p_org is not null or a.organization_id in (select id from public.sofa_real_client_organizations))
     and ((p.doc_number is not null and p.doc_number = nullif(upper(regexp_replace(coalesce(a.patient_doc, ''), '[\s-]', '', 'g')), ''))
       or (p.member_number is not null and p.ars_id is not null and p.ars_id = a.ars_id and p.member_number = trim(a.member_number)));
  get diagnostics v_apt = row_count;

  -- 4) Vincular reclamaciones (solo cambia patient_id; el guardián de reclamaciones lo permite sin tocar estado ni tarifa)
  update public.service_lines l set patient_id = p.id
    from public.submissions s, public.patients p
   where l.patient_id is null and s.id = l.submission_id and p.organization_id = l.organization_id and (p_org is null or l.organization_id = p_org)
     and (p_org is not null or l.organization_id in (select id from public.sofa_real_client_organizations))
     and ((p.doc_number is not null and p.doc_number = nullif(upper(regexp_replace(coalesce(l.patient_doc, ''), '[\s-]', '', 'g')), ''))
       or (p.member_number is not null and p.ars_id is not null and p.ars_id = s.ars_id and p.member_number = trim(l.member_number)));
  get diagnostics v_cl = row_count;

  return jsonb_build_object('created', v_new, 'linked_appointments', v_apt, 'linked_claims', v_cl);
end
$function$;

CREATE OR REPLACE FUNCTION public.tariff_renewal_followup(p_days integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_n int := 0; v_task uuid; v_days int; v_yrs int;
begin
  if auth.uid() is not null and not app.is_staff(array['super_admin','admin','assistant','operations']) then
    raise exception 'Solo el equipo SOFA genera las tareas de renegociación.' using errcode = '42501';
  end if;
  select coalesce(p_days, s.tariff_renewal_notice_days, 90), coalesce(s.tariff_renewal_years, 2) into v_days, v_yrs from public.app_settings s limit 1;
  v_days := coalesce(v_days, p_days, 90); v_yrs := coalesce(v_yrs, 2);
  for r in
    select g.*, o.operator_id from app.tariff_renewal_groups() g join public.organizations o on o.id = g.organization_id
     where g.due <= current_date + v_days and o.status in ('activo','incorporacion')
       and (auth.uid() is not null or coalesce(o.is_demo,false)=false)
       and not exists (select 1 from public.tariff_renewal_reminders x where x.organization_id = g.organization_id and x.provider_id = g.provider_id
                         and x.ars_id = g.ars_id and x.plan_key = coalesce(g.plan_id, '00000000-0000-0000-0000-000000000000'::uuid) and x.since = g.since)
  loop
    insert into public.tasks (operator_id, organization_id, title, priority, due_date, entity_type, entity_id, notes)
    values (r.operator_id, r.organization_id, left(format('Renegociar tarifario · %s%s · %s', r.ars, coalesce(' (' || r.plan || ')', ''), r.provider), 200),
            case when r.due <= current_date + 30 then 'alta' else 'media' end, greatest(current_date, r.due - 30),
            'organization', r.organization_id,
            format('Ofrecer al cliente %s el servicio SOFA de renegociación del tarifario con %s. %s tarifa(s) vigentes desde %s; %s el %s.',
                   r.client, r.ars, r.tariffs, to_char(r.since, 'DD/MM/YYYY'),
                   case r.kind when 'vence' then 'el contrato vence' else format('cumple %s años', v_yrs) end, to_char(r.due, 'DD/MM/YYYY')))
    returning id into v_task;
    insert into public.tariff_renewal_reminders (organization_id, provider_id, ars_id, plan_key, since, task_id)
    values (r.organization_id, r.provider_id, r.ars_id, coalesce(r.plan_id, '00000000-0000-0000-0000-000000000000'::uuid), r.since, v_task)
    on conflict do nothing;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('tasks_created', v_n, 'notice_days', v_days, 'years', v_yrs);
end
$function$;

CREATE OR REPLACE FUNCTION public.generate_balance_reminders(p_org uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int;
begin
  if auth.uid() is not null then
    if p_org is null and not app.is_staff(array['super_admin','admin']) then
      raise exception 'Indique el consultorio.' using errcode = '22023';
    elsif p_org is not null and not app.can(p_org, array['super_admin','admin','client']) then
      raise exception 'Solo el Médico o SOFA generan los recordatorios de pago del consultorio.' using errcode = '42501';
    end if;
  end if;
  with g as (
    select c.organization_id, c.provider_id, app.charge_patient_key(c.patient_doc, c.patient_name) k, count(*) n, sum(c.amount) amt, min(c.charge_date) oldest,
           (array_agg(c.patient_name order by c.charge_date desc))[1] pname
      from public.private_charges c join public.patient_notice_settings s on s.organization_id = c.organization_id and s.balance_auto
     where c.status = 'pendiente' and (p_org is null or c.organization_id = p_org)
       and (p_org is not null or c.organization_id in (select id from public.sofa_real_client_organizations))
     group by 1, 2, 3),
  t as (
    select g.*, s.balance_min, s.balance_every_days, pr.full_name med,
           (select p.id from public.patients p where p.organization_id = g.organization_id and app.charge_patient_key(p.doc_number, p.full_name) = g.k order by p.created_at limit 1) pid,
           -- SEG-20: cuántas fichas comparten la clave (si es por nombre y hay homónimos no se sabe a quién avisar)
           (select count(*) from public.patients p2 where p2.organization_id = g.organization_id and app.charge_patient_key(p2.doc_number, p2.full_name) = g.k) nmatch
      from g join public.patient_notice_settings s on s.organization_id = g.organization_id join public.providers pr on pr.id = g.provider_id
     where g.amt >= s.balance_min)
  insert into public.message_queue (organization_id, provider_id, kind, to_phone, subject, body, scheduled_for, patient_id, has_portal_link)
  select t.organization_id, t.provider_id, 'cobro_pendiente', p.phone, 'Saldo pendiente · ' || t.k,
         format('Hola %s, le saluda el consultorio de %s. Tiene un saldo pendiente de RD$ %s por %s servicio(s) desde el %s. Puede pasar por el consultorio o responder este mensaje para coordinar el pago. Gracias.',
                split_part(t.pname, ' ', 1), t.med, to_char(t.amt, 'FM999G999G990D00'), t.n, to_char(t.oldest, 'DD/MM/YYYY'))
           || case when app.portal_ready(t.organization_id) then ' Vea el detalle de su saldo aquí: {enlace}' else '' end,
         current_date, t.pid, app.portal_ready(t.organization_id)
    from t join public.patients p on p.id = t.pid
   where (t.k not like 'N:%' or t.nmatch = 1)
     and length(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')) >= 10
     and not exists (select 1 from public.message_queue m where m.provider_id = t.provider_id and m.kind = 'cobro_pendiente'
                       and m.subject = 'Saldo pendiente · ' || t.k and m.scheduled_for > current_date - t.balance_every_days);
  get diagnostics v_n = row_count;
  return v_n;
end
$function$;

CREATE OR REPLACE FUNCTION public.portal_enrich_messages(p_org uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int;
begin
  if auth.uid() is not null then
    if p_org is null and not app.is_staff(array['super_admin','admin']) then
      raise exception 'Indique el consultorio.' using errcode = '22023';
    elsif p_org is not null and not app.can(p_org, array['super_admin','admin','client','capturer']) then
      raise exception 'Sin acceso a este consultorio.' using errcode = '42501';
    end if;
  end if;
  update public.message_queue m
     set patient_id = x.pid, has_portal_link = true,
         body = m.body || case m.kind when 'cobro_pendiente' then ' Vea el detalle de su saldo aquí: {enlace}' else ' Vea su cita, sus recetas y su saldo aquí: {enlace}' end
    from (select m2.id,
                 coalesce(m2.patient_id, a.patient_id,
                   (select p.id from public.patients p where p.organization_id = m2.organization_id and m2.kind = 'cobro_pendiente'
                       and app.charge_patient_key(p.doc_number, p.full_name) = split_part(m2.subject, ' · ', 2) order by p.created_at limit 1)) pid
            from public.message_queue m2 left join public.appointments a on a.id = m2.appointment_id
           where m2.status = 'pendiente' and not m2.has_portal_link and m2.scheduled_for >= current_date - 1
             and m2.kind in ('recordatorio_cita','seguimiento_cita','control_pendiente','reprogramar_cita','cobro_pendiente')
             and (p_org is null or m2.organization_id = p_org)
             and (p_org is not null or m2.organization_id in (select id from public.sofa_real_client_organizations))
             and app.portal_ready(m2.organization_id)) x
   where m.id = x.id and x.pid is not null;
  get diagnostics v_n = row_count;
  return v_n;
end
$function$;

commit;
