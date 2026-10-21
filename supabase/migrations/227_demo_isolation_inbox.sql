-- 227 · Aislamiento DEMO en Mi bandeja y asignaciones
begin;

CREATE OR REPLACE FUNCTION app.inbox_tasks(p_today date DEFAULT NULL::date)
 RETURNS TABLE(task_key text, task_type text, entity_type text, entity_id uuid, organization_id uuid, operator_id uuid, client_name text, ars_name text, folio text, title text, detail text, due_on date, days_late integer, amount numeric, priority text, prio_rank integer, assignment_id uuid, assigned_to uuid, assignee_id uuid, substituted boolean, unassigned_reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with d as (select coalesce(p_today, app.inbox_today()) today),
  cli as (select o.id, o.operator_id, coalesce(o.trade_name, o.legal_name) name
            from public.organizations o where o.kind = 'client' and o.status <> 'inactivo' and coalesce(o.is_demo,false)=false),
  prm as (select o.id operator_id, coalesce(ip.collection_grace_days, 5) grace, coalesce(ip.soon_days, 2) soon, coalesce(ip.high_amount, 50000) high,
                 coalesce(s.submission_window_days, 30) win, coalesce(s.glosa_response_business_days, 7) gdays
            from public.organizations o left join public.inbox_params ip on ip.operator_id = o.id left join public.app_settings s on s.operator_id = o.id
           where o.kind = 'operator'),
  inc as (select sl.submission_id,
                 count(*) n, coalesce(sum(sl.amount), 0) amt,
                 count(*) filter (where nullif(trim(coalesce(sl.member_number, '')), '') is null) no_member,
                 count(*) filter (where nullif(trim(coalesce(sl.authorization_number, '')), '') is null) no_auth,
                 count(*) filter (where sl.claim_status = 'con_inconsistencia') bad,
                 count(*) filter (where sl.claim_status = 'pendiente_configuracion') no_conf
            from public.service_lines sl join public.submissions s on s.id = sl.submission_id
           where s.submitted_on is null and s.status in ('borrador','recibida','pendiente_documentos','en_depuracion')
             and (nullif(trim(coalesce(sl.member_number, '')), '') is null or nullif(trim(coalesce(sl.authorization_number, '')), '') is null
                  or sl.claim_status in ('con_inconsistencia','pendiente_configuracion'))
           group by sl.submission_id),
  src as (
    -- 1 · Capturas incompletas (por lote)
    select 'captura_incompleta'::text tt, 'submission'::text et, s.id eid, s.organization_id oid, s.folio fol, a.name arsn,
           format('Lote %s · %s', coalesce(s.folio, 'sin folio'), coalesce(a.name, 'sin ARS')) ttl,
           format('Faltan datos en %s captura(s): %s', inc.n, array_to_string(array_remove(array[
             case when inc.no_member > 0 then format('%s sin afiliado', inc.no_member) end,
             case when inc.no_auth > 0 then format('%s sin autorización', inc.no_auth) end,
             case when inc.bad > 0 then format('%s con inconsistencia', inc.bad) end,
             case when inc.no_conf > 0 then format('%s sin servicio contratado', inc.no_conf) end], null), ', ')) dtl,
           ((s.period + interval '1 month')::date - 1 + prm.win) due, inc.amt amt
      from inc join public.submissions s on s.id = inc.submission_id join cli on cli.id = s.organization_id join prm on prm.operator_id = cli.operator_id
      left join public.ars a on a.id = s.ars_id
    union all
    -- 2 · Lotes por radicar
    select 'lote_por_radicar', 'submission', s.id, s.organization_id, s.folio, a.name,
           format('Lote %s · %s', coalesce(s.folio, 'sin folio'), coalesce(a.name, 'sin ARS')),
           format('Lista para radicar · %s servicio(s)%s', coalesce(l.n, 0),
                  case when s.sent_on is not null then format(' · enviada el %s, falta el acuse de la ARS', to_char(s.sent_on, 'DD/MM/YYYY')) else '' end),
           ((s.period + interval '1 month')::date - 1 + prm.win), coalesce(l.amt, 0)
      from public.submissions s join cli on cli.id = s.organization_id join prm on prm.operator_id = cli.operator_id left join public.ars a on a.id = s.ars_id
      left join lateral (select count(*) n, sum(sl.amount) amt from public.service_lines sl where sl.submission_id = s.id) l on true
     where s.status = 'lista_para_radicar' and s.submitted_on is null
    union all
    -- 3 · Glosas por responder (plazo de la 144: días hábiles desde la notificación)
    select 'glosa_responder', 'glosa', g.id, g.organization_id, g.folio, a.name,
           format('Glosa %s · %s', coalesce(g.folio, 'sin folio'), coalesce(a.name, 'sin ARS')),
           format('Notificada el %s · responder antes del %s · %s', to_char(g.notified_on, 'DD/MM/YYYY'), to_char(app.add_business_days(g.notified_on, prm.gdays), 'DD/MM/YYYY'),
                  case g.status when 'analizada' then 'ya analizada, falta responder' else 'pendiente de análisis' end),
           app.add_business_days(g.notified_on, prm.gdays), coalesce((select sum(i.amount) from public.glosa_items i where i.glosa_id = g.id), 0)
      from public.glosas g join cli on cli.id = g.organization_id join prm on prm.operator_id = cli.operator_id
      join public.submissions s on s.id = g.submission_id left join public.ars a on a.id = s.ars_id
     where g.status in ('pendiente','analizada') and app.glosa_answered_on(g.id) is null
    union all
    -- 4 · Cobros por escalar (etapa de la cartera escalonada de la 146 sin su gestión registrada)
    select 'cobro_escalar', 'submission', b.id, b.organization_id, b.folio, a.name,
           format('Lote %s · %s', coalesce(b.folio, 'sin folio'), coalesce(a.name, 'sin ARS')),
           format('%s días desde la radicación · pendiente RD$ %s · toca: %s', (d.today - b.submitted_on), to_char(b.balance, 'FM999G999G990D00'),
                  app.collection_stage_label(app.collection_stage(d.today - b.submitted_on))),
           (b.submitted_on + case app.collection_stage(d.today - b.submitted_on) when 'reclamacion_formal' then 31 when 'escalamiento' then 61 else 91 end + prm.grace), b.balance
      from public.v_submission_balance b cross join d join cli on cli.id = b.organization_id join prm on prm.operator_id = cli.operator_id left join public.ars a on a.id = b.ars_id
     where b.submitted_on is not null and b.balance > 0.005 and b.status not in ('rechazada','cerrada')
       and app.collection_stage(d.today - b.submitted_on) <> 'seguimiento'
       and not exists (select 1 from public.collection_actions ca where b.id = any (ca.submission_ids) and ca.kind = app.collection_stage(d.today - b.submitted_on))
  ),
  pairs as (select distinct s2.oid, s2.tt from src s2),
  res as (select p.oid, p.tt, r.* from pairs p cross join lateral app.inbox_effective(p.oid, p.tt, (select today from d)) r)
  select s.tt || ':' || s.eid::text, s.tt, s.et, s.eid, s.oid, cli.operator_id, cli.name, s.arsn, s.fol, s.ttl, s.dtl, s.due::date,
         ((select today from d) - s.due::date)::int, s.amt,
         case when (select today from d) - s.due::date > 0 then 'critica'
              when (select today from d) - s.due::date >= -prm.soon or s.amt >= prm.high then 'alta' else 'normal' end,
         case when (select today from d) - s.due::date > 0 then 1
              when (select today from d) - s.due::date >= -prm.soon or s.amt >= prm.high then 2 else 3 end,
         res.r_assignment, res.r_assigned_to, res.r_effective, res.r_substituted, res.r_reason
    from src s join cli on cli.id = s.oid join prm on prm.operator_id = cli.operator_id join res on res.oid = s.oid and res.tt = s.tt;
$function$;

CREATE OR REPLACE FUNCTION public.inbox_assignments_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if app.inbox_role() is distinct from 'supervisor' then
    raise exception 'Las asignaciones las ven el Super Admin, el Administrador y Operaciones.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'types', (select jsonb_agg(jsonb_build_object('code', t.code, 'label', t.label) order by t.ord) from app.inbox_types() t),
    'assignments', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'organization_id', a.organization_id, 'client', coalesce(o.trade_name, o.legal_name), 'task_type', a.task_type,
                 'type_label', coalesce(app.inbox_type_label(a.task_type), 'Todos los tipos'), 'assignee_id', a.assignee_id, 'assignee', pr.full_name, 'note', a.note, 'since', a.created_at,
                 'available', app.inbox_eligible(a.assignee_id, o.operator_id) and app.inbox_user_sees(a.assignee_id, o.id))
                 order by coalesce(o.trade_name, o.legal_name), a.task_type nulls first)
               from public.inbox_assignments a join public.organizations o on o.id = a.organization_id join public.profiles pr on pr.id = a.assignee_id
              where a.is_active and coalesce(o.is_demo,false)=false and a.organization_id in (select app.visible_org_ids())), '[]'::jsonb),
    'uncovered', coalesce((select jsonb_agg(jsonb_build_object('organization_id', o.id, 'client', coalesce(o.trade_name, o.legal_name),
                 'missing', (select jsonb_agg(t.code order by t.ord) from app.inbox_types() t
                              where not exists (select 1 from public.inbox_assignments a where a.organization_id = o.id and a.is_active and (a.task_type = t.code or a.task_type is null))))
                 order by coalesce(o.trade_name, o.legal_name))
               from public.organizations o
              where o.kind = 'client' and o.status <> 'inactivo' and coalesce(o.is_demo,false)=false and o.id in (select app.visible_org_ids())
                and exists (select 1 from app.inbox_types() t where not exists (select 1 from public.inbox_assignments a where a.organization_id = o.id and a.is_active and (a.task_type = t.code or a.task_type is null)))), '[]'::jsonb),
    'billers', coalesce((select jsonb_agg(jsonb_build_object('user_id', ou.user_id, 'name', p.full_name) order by p.full_name)
                           from public.organization_users ou join public.profiles p on p.id = ou.user_id and p.is_active
                           join public.organizations o on o.id = ou.organization_id and o.kind = 'operator'
                          where ou.role_code = 'billing' and ou.is_active and ou.organization_id in (select app.my_operator_ids())), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.inbox_assignment_save(p_org uuid, p_assignee uuid, p_type text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_note text := nullif(left(regexp_replace(trim(coalesce(p_note, '')), '\s+', ' ', 'g'), 300), ''); v_prev public.inbox_assignments; v_new uuid := gen_random_uuid();
begin
  if app.inbox_role() is distinct from 'supervisor' then
    raise exception 'Solo el Super Admin, el Administrador u Operaciones asignan clientes en la bandeja. Pídaselo a ellos.' using errcode = '42501';
  end if;
  if p_type is not null and not exists (select 1 from app.inbox_types() t where t.code = p_type) then
    raise exception 'Tipo de tarea no válido. Elija uno de la lista o déjelo vacío para asignar todos los tipos del cliente.' using errcode = '22023';
  end if;
  if p_org is null or not exists (select 1 from public.organizations o where o.id = p_org and o.kind = 'client' and coalesce(o.is_demo,false)=false)
     or p_org not in (select app.visible_org_ids()) or coalesce(app.role_for_org(p_org), '') not in ('super_admin','admin','operations') then
    raise exception 'Cliente no encontrado o sin acceso. Elija un cliente de la lista.' using errcode = 'P0002';
  end if;
  if p_assignee is null then
    raise exception 'Elija a la persona de Facturación que atenderá a este cliente.' using errcode = '22023';
  end if;
  perform app.inbox_check_assignee(p_assignee, p_org);
  perform pg_advisory_xact_lock(hashtextextended('inbox:' || p_org::text, 0));
  select * into v_prev from public.inbox_assignments x where x.organization_id = p_org and x.is_active and x.task_type is not distinct from p_type;
  if found and v_prev.assignee_id = p_assignee then
    raise exception 'Ese cliente ya está asignado a esa persona para ese tipo de tarea. No hay nada que cambiar.' using errcode = '22023';
  end if;
  if found then
    update public.inbox_assignments set is_active = false, ended_at = now(), ended_by = auth.uid() where id = v_prev.id;
  end if;
  insert into public.inbox_assignments (id, organization_id, task_type, assignee_id, note) values (v_new, p_org, p_type, p_assignee, v_note);
  return jsonb_build_object('id', v_new, 'organization_id', p_org, 'task_type', p_type, 'assignee_id', p_assignee, 'previous_assignee', v_prev.assignee_id);
end $function$;

CREATE OR REPLACE FUNCTION public.inbox_overdue_report(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_role text := app.inbox_role(); v_today date := app.inbox_today(); v_me uuid := auth.uid(); v_from date; v_to date; v_rows jsonb;
begin
  if v_role is null then
    raise exception 'El indicador de tareas vencidas es del equipo de Facturación (solo ve el suyo) y de la supervisión de SOFA.' using errcode = '42501';
  end if;
  v_to := coalesce(p_to, v_today); v_from := coalesce(p_from, v_to - 13);
  if v_to < v_from then raise exception 'La fecha final no puede ser anterior a la inicial. Corrija las fechas.' using errcode = '22023'; end if;
  if v_to - v_from > 92 then raise exception 'El indicador se consulta hasta por 93 días. Acorte el rango.' using errcode = '22023'; end if;
  with snap as (
    select c.day, c.assignee_id, max(c.assignee_name) assignee_name, sum(c.open_tasks)::int open_tasks, sum(c.overdue_tasks)::int overdue_tasks, sum(c.overdue_amount) overdue_amount,
           coalesce(jsonb_object_agg(c.task_type, c.overdue_tasks) filter (where c.overdue_tasks > 0), '{}'::jsonb) by_type, false live
      from public.inbox_daily_close c
     where c.day between v_from and least(v_to, v_today - 1) and c.organization_id in (select app.visible_org_ids()) and c.organization_id in (select id from public.sofa_real_client_organizations)
       and c.operator_id in (select app.my_operator_ids()) and (v_role = 'supervisor' or c.assignee_id = v_me)
     group by c.day, c.assignee_id),
  lt as (
    select t.* from app.inbox_tasks(v_today) t
     where v_to >= v_today and v_from <= v_today and t.organization_id in (select app.visible_org_ids()) and (v_role = 'supervisor' or t.assignee_id = v_me)),
  live as (
    select v_today as day, l.assignee_id, (select pr.full_name from public.profiles pr where pr.id = l.assignee_id) assignee_name, count(*)::int open_tasks,
           (count(*) filter (where l.days_late > 0))::int overdue_tasks, coalesce(sum(l.amount) filter (where l.days_late > 0), 0) overdue_amount,
           (select coalesce(jsonb_object_agg(q.task_type, q.n), '{}'::jsonb) from (select l2.task_type, count(*) n from lt l2
                                                                                    where l2.assignee_id is not distinct from l.assignee_id and l2.days_late > 0 group by 1) q) by_type,
           true live
      from lt l group by l.assignee_id),
  allr as (select s.day, s.assignee_id, s.assignee_name, s.open_tasks, s.overdue_tasks, s.overdue_amount, s.by_type, s.live from snap s
           union all select l.day, l.assignee_id, l.assignee_name, l.open_tasks, l.overdue_tasks, l.overdue_amount, l.by_type, l.live from live l)
  select jsonb_build_object('from', v_from, 'to', v_to, 'today', v_today,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('day', a.day, 'assignee_id', a.assignee_id, 'assignee', coalesce(a.assignee_name, 'Sin responsable'), 'open', a.open_tasks,
                 'overdue', a.overdue_tasks, 'overdue_amount', a.overdue_amount, 'by_type', a.by_type, 'live', a.live) order by a.day desc, a.overdue_tasks desc, a.assignee_name nulls last) from allr a), '[]'::jsonb),
    'by_person', coalesce((select jsonb_agg(jsonb_build_object('assignee_id', z.assignee_id, 'assignee', coalesce(z.nm, 'Sin responsable'), 'days', z.days, 'days_with_overdue', z.dwo,
                 'max_overdue', z.mx, 'avg_overdue', z.av, 'last_day', z.last_day, 'last_overdue', z.last_overdue) order by z.last_overdue desc, z.nm nulls last)
               from (select a.assignee_id, max(a.assignee_name) nm, count(*) days, count(*) filter (where a.overdue_tasks > 0) dwo, max(a.overdue_tasks) mx,
                            round(avg(a.overdue_tasks), 1) av, max(a.day) last_day, (array_agg(a.overdue_tasks order by a.day desc))[1] last_overdue
                       from allr a group by a.assignee_id) z), '[]'::jsonb))
    into v_rows;
  return v_rows;
end $function$;


commit;
