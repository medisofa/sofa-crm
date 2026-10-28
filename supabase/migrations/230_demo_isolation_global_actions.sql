-- 230 · Regla estricta: toda acción global excluye DEMO
-- DEMO solo participa cuando una función admite y recibe un cliente/médico explícito.
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
              and coalesce(o.is_demo,false)=false
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
              and coalesce(o.is_demo,false)=false loop
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
              and (c.organization_id is null or c.organization_id in (select id from public.sofa_real_client_organizations)) loop
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
              and (c.organization_id is null or c.organization_id in (select id from public.sofa_real_client_organizations)) loop
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
         and ap.organization_id in (select id from public.sofa_real_client_organizations)
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
              and coalesce(is_demo,false)=false loop
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
  for s in select x.id, x.organization_id from public.subscriptions x where x.state <> 'cancelada' and x.organization_id in (select id from public.sofa_real_client_organizations) order by x.created_at loop
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
              and x.organization_id in (select id from public.sofa_real_client_organizations) loop
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
       and gl.organization_id in (select id from public.sofa_real_client_organizations)
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
       and py.organization_id in (select id from public.sofa_real_client_organizations)
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
   where s.organization_id in (select app.email_user_orgs(p_user, 'medico')) and s.organization_id in (select id from public.sofa_real_client_organizations) and s.submitted_on between p_from and p_to;
  select count(*), coalesce(sum(py.amount), 0) into v_pag, v_pag_m
    from public.payments py where py.organization_id in (select app.email_user_orgs(p_user, 'medico')) and py.organization_id in (select id from public.sofa_real_client_organizations) and py.paid_on between p_from and p_to;
  select count(*), coalesce(sum((select sum(i.amount) from public.glosa_items i where i.glosa_id = g.id)), 0) into v_gn, v_gn_m
    from public.glosas g where g.organization_id in (select app.email_user_orgs(p_user, 'medico')) and g.organization_id in (select id from public.sofa_real_client_organizations) and g.notified_on between p_from and p_to;
  select count(*), count(*) filter (where g.appeal_deadline between p_today and p_today + 7) into v_ga, v_gv
    from public.glosas g where g.organization_id in (select app.email_user_orgs(p_user, 'medico')) and g.organization_id in (select id from public.sofa_real_client_organizations) and g.status in ('pendiente', 'analizada');
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
                   and y.organization_id in (select id from public.sofa_real_client_organizations)
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
       and coalesce(o.is_demo,false)=false
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
              and coalesce(o.is_demo,false)=false order by pr.full_name loop
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
       and coalesce(o.is_demo,false)=false
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

CREATE OR REPLACE FUNCTION public.portal_requests_list(p_org uuid DEFAULT NULL::uuid, p_status text DEFAULT 'pendiente'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'kind', q.kind, 'note', q.note, 'status', q.status, 'at', q.created_at,
            'patient', p.full_name, 'phone', p.phone, 'organization_id', q.organization_id,
            'appointment', jsonb_build_object('date', a.appointment_date, 'time', to_char(a.appointment_time, 'HH24:MI'), 'doctor', pr.full_name, 'status', a.status),
            'handled_by', hb.full_name, 'handled_at', q.handled_at, 'handled_note', q.handled_note) order by q.created_at desc)
     from public.patient_portal_requests q
     join public.patients p on p.id = q.patient_id
     left join public.appointments a on a.id = q.appointment_id
     left join public.providers pr on pr.id = a.provider_id
     left join public.profiles hb on hb.id = q.handled_by
    where (p_org is null or q.organization_id = p_org)
      and (p_org is not null or q.organization_id in (select id from public.sofa_real_client_organizations))
      and (p_status is null or q.status = p_status)
      and q.created_at > now() - interval '60 days'
      and (case when a.provider_id is not null then app.consultorio_access(a.provider_id, false)
                else app.can(q.organization_id, array['super_admin','admin','client']) end)), '[]'::jsonb);
end
$function$;

commit;
