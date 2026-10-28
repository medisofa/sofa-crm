-- 229 · Aislamiento DEMO en colas operativas de correo
begin;

create or replace function app.email_queue_operational(p_org uuid,p_user uuid)
returns boolean
language sql stable security definer set search_path=''
as $$
  select case
    when p_org is not null then exists(
      select 1 from public.sofa_real_client_organizations r where r.id=p_org
    )
    when p_user is null then true
    else not (
      exists(
        select 1 from public.organization_users ou
        join public.organizations o on o.id=ou.organization_id
        where ou.user_id=p_user and ou.is_active and ou.role_code='client' and coalesce(o.is_demo,false)=true
      )
      and not exists(
        select 1 from public.organization_users ou
        join public.organizations o on o.id=ou.organization_id
        where ou.user_id=p_user and ou.is_active and ou.role_code='client' and coalesce(o.is_demo,false)=false
      )
    )
  end
$$;

CREATE OR REPLACE FUNCTION public.email_queue_list(p_status text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_op uuid := app.email_admin_op(); v_rows jsonb; v_total int;
begin
  if p_status is not null and p_status not in ('pendiente', 'enviando', 'enviado', 'fallido', 'cancelado') then
    raise exception 'Estado no válido. Use pendiente, enviando, enviado, fallido o cancelado (o déjelo vacío para ver todos).' using errcode = '22023';
  end if;
  select count(*) into v_total from public.email_queue q where q.operator_id = v_op and app.email_queue_operational(q.organization_id,q.recipient_id) and (p_status is null or q.status = p_status);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.created_at desc, z.id), '[]'::jsonb) into v_rows from (
    select q.id, q.topic, q.recipient_email, q.recipient_name, q.subject, q.status, q.attempts, q.max_attempts, q.last_error, q.scheduled_for, q.sent_at, q.created_at, q.is_critical, q.track_opens, q.opened_at, q.provider
      from public.email_queue q where q.operator_id = v_op and app.email_queue_operational(q.organization_id,q.recipient_id) and (p_status is null or q.status = p_status)
     order by q.created_at desc, q.id limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0)) z;
  return jsonb_build_object('total', v_total, 'rows', v_rows);
end $function$;
CREATE OR REPLACE FUNCTION public.email_queue_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_op uuid := app.email_admin_op();
begin
  return jsonb_build_object(
    'por_estado', coalesce((select jsonb_object_agg(x.status, x.n) from (select q.status, count(*) n from public.email_queue q where q.operator_id = v_op and app.email_queue_operational(q.organization_id,q.recipient_id) group by q.status) x), '{}'::jsonb),
    'pendiente_mas_viejo_min', (select floor(extract(epoch from now() - min(q.scheduled_for)) / 60)::int from public.email_queue q where q.operator_id = v_op and app.email_queue_operational(q.organization_id,q.recipient_id) and q.status = 'pendiente' and q.scheduled_for <= now()),
    'fallidos_24h', (select count(*) from public.email_queue q where q.operator_id = v_op and app.email_queue_operational(q.organization_id,q.recipient_id) and q.status = 'fallido' and q.updated_at > now() - interval '24 hours'),
    'enviados_7d', (select count(*) from public.email_queue q where q.operator_id = v_op and app.email_queue_operational(q.organization_id,q.recipient_id) and q.status = 'enviado' and q.sent_at > now() - interval '7 days'));
end $function$;
CREATE OR REPLACE FUNCTION public.email_open_rate(p_days integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_op uuid := app.email_admin_op(); v_env int; v_open int; v_days int := least(greatest(coalesce(p_days, 90), 7), 365);
begin
  select count(distinct q.recipient_id), count(distinct q.recipient_id) filter (where q.opened_at is not null) into v_env, v_open
    from public.email_queue q
   where q.operator_id = v_op and app.email_queue_operational(q.organization_id,q.recipient_id) and q.template_code = 'resumen_semanal' and q.status = 'enviado' and q.track_opens and q.sent_at > now() - make_interval(days => v_days);
  if v_env = 0 then
    return jsonb_build_object('medido', false, 'porcentaje', null, 'meta', 60, 'medicos_enviados', 0, 'medicos_abrieron', 0,
      'mensaje', 'Sin medición: el seguimiento de aperturas está apagado o todavía no hay resúmenes medibles enviados.');
  end if;
  return jsonb_build_object('medido', true, 'porcentaje', round(100.0 * v_open / v_env, 1), 'meta', 60, 'medicos_enviados', v_env, 'medicos_abrieron', v_open,
    'mensaje', case when 100.0 * v_open / v_env >= 60 then 'Meta cumplida.' else 'Por debajo de la meta del 60 %.' end);
end $function$;

commit;
