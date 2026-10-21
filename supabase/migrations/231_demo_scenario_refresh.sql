-- 231 · Refresco idempotente del escenario DEMO
-- Mantiene citas relativas y ROI demostrativo sin crear facturas fiscales ni tocar clientes reales.
begin;

create or replace function app.refresh_demo_scenario(p_on date default current_date)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_org constant uuid := '00000000-0000-4000-8000-0000000000de';
  v_period date := date_trunc('month',coalesce(p_on,current_date)-interval '1 month')::date;
  v_appts integer := 0;
  v_fee uuid;
begin
  if not exists(select 1 from public.organizations o where o.id=v_org and o.kind='client' and o.is_demo) then
    raise exception 'Consultorio Demo SOFA no encontrado o no marcado como DEMO' using errcode='P0002';
  end if;

  with ranked as (
    select a.id,row_number() over(order by a.id) rn
      from public.appointments a
     where a.organization_id=v_org
     order by a.id
     limit 10
  ), plan as (
    select id,rn,
      case rn when 1 then -1 when 2 then -1 when 3 then 0 when 4 then 0 when 5 then 0 when 6 then 0
              when 7 then 1 when 8 then 1 when 9 then 2 else 3 end day_offset,
      case rn when 1 then time '08:00' when 2 then time '09:00' when 3 then time '08:00' when 4 then time '09:00'
              when 5 then time '10:00' when 6 then time '11:00' when 7 then time '08:30' when 8 then time '10:00'
              when 9 then time '09:00' else time '10:30' end at_time,
      case rn when 1 then 'atendida' when 2 then 'no_asistio' when 3 then 'atendida' when 4 then 'en_espera'
              when 5 then 'confirmada' when 6 then 'programada' when 7 then 'confirmada' else 'programada' end new_status
    from ranked
  )
  update public.appointments a
     set appointment_date=coalesce(p_on,current_date)+p.day_offset,
         appointment_time=p.at_time,
         status=p.new_status
    from plan p
   where a.id=p.id;
  get diagnostics v_appts=row_count;

  insert into public.sofa_fees(
    organization_id,source_type,source_id,period,base_amount,rate,amount,service_code,description,calculated_at
  )
  values(
    v_org,'manual',v_org,v_period,15000,null,15000,'facturacion',
    'DEMO · Honorario sintético NO FISCAL · NO CONTABILIZAR',now()
  )
  on conflict on constraint sofa_fees_source_uq do update set
    base_amount=excluded.base_amount,
    amount=excluded.amount,
    service_code=excluded.service_code,
    description=excluded.description,
    calculated_at=now()
  returning id into v_fee;

  return jsonb_build_object(
    'organization_id',v_org,
    'refreshed_on',coalesce(p_on,current_date),
    'appointments_refreshed',v_appts,
    'fee_period',v_period,
    'synthetic_fee',15000,
    'fee_id',v_fee,
    'fiscal_invoice_created',false
  );
end
$$;

revoke all on function app.refresh_demo_scenario(date) from public,anon,authenticated;

do $$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname='sofa_demo_refresco' limit 1;
  if v_job is not null then perform cron.unschedule(v_job); end if;
  perform cron.schedule(
    'sofa_demo_refresco',
    '15 8 * * *',
    'select app.refresh_demo_scenario(current_date)'
  );
end
$$;

CREATE OR REPLACE FUNCTION app.qa_run_tests_demo()
 RETURNS TABLE(n integer, resultado text, prueba text, detalle text)
 LANGUAGE plpgsql
 SET search_path TO 'public, app, extensions, pg_catalog'
AS $function$
declare
  v_res jsonb := '[]'::jsonb;
  v_org uuid := '00000000-0000-4000-8000-0000000000de';
  v_med uuid := '00000000-0000-4000-8000-0000000000d1';
  v_u uuid; v_r jsonb; v_n int; v_t text;
  v_per date := date_trunc('month', current_date - interval '1 month')::date;
begin
  if not exists (select 1 from app.schema_migrations where version = '226') then
    raise exception 'Falta la migración 226. Aplícala y vuelve a correr las pruebas.';
  end if;

  begin
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-01 · La migración 226 queda registrada','ok',
      exists(select 1 from app.schema_migrations where version='226'),'d',null));

    -- ── Que exista y que se vea que es de mentira ───────────────────────────────────────────────
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-02 · El Consultorio Demo existe y está activo','ok',
      exists(select 1 from public.organizations where id = v_org and kind='client' and status='activo'),'d',null));

    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-03 · Dice en su ficha que son datos de demostración','ok',
      exists(select 1 from public.organizations where id = v_org and notes ilike '%DEMOSTRACIÓN%'),'d',null));

    select count(*) into v_n from public.patients where organization_id = v_org and full_name not ilike '%(demo)%';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-04 · Todo paciente lleva «(demo)» en el nombre','ok',
      v_n = 0,'d', v_n||' sin marcar'));

    -- ── LO QUE MÁS IMPORTA: ningún dato real tocado ─────────────────────────────────────────────
    -- Nada sembrado puede haber caído fuera de la organización de demostración.
    select count(*) into v_n from public.patients where full_name ilike '%(demo)%' and organization_id <> v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-05 · Ningún paciente de demostración quedó en otra organización','ok',
      v_n = 0,'d', v_n||' fuera de la demo'));

    select count(*) into v_n from public.payments where reference like 'TRF-DEMO-%' and organization_id <> v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-06 · Ningún pago de demostración quedó en otra organización','ok',
      v_n = 0,'d', v_n||' fuera de la demo'));

    select count(*) into v_n from public.submissions where ars_receipt_number like 'DEMO-%' and organization_id <> v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-07 · Ninguna radicación de demostración quedó en otra organización','ok',
      v_n = 0,'d', v_n||' fuera de la demo'));

    select count(*) into v_n from public.private_charges where reference like 'CAJA-DEMO-%' and organization_id <> v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-08 · Ningún cobro de demostración quedó en otra organización','ok',
      v_n = 0,'d', v_n||' fuera de la demo'));

    -- Los demás clientes siguen siendo clientes y nadie los desactivó.
    select count(*) into v_n from public.organizations
     where kind = 'client' and id <> v_org and status not in ('activo','incorporacion','suspendido','inactivo');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-09 · Ningún cliente real cambió de estado a algo raro','ok',
      v_n = 0,'d', v_n));

    -- ── Los usuarios de demostración, solo en la demo ───────────────────────────────────────────
    select count(*) into v_n from public.organization_users ou
      join auth.users u on u.id = ou.user_id
     where u.email in ('medicasofa+doctor@gmail.com','medicasofa+secretaria@gmail.com')
       and ou.organization_id <> v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-10 · Los usuarios demo no ven ninguna organización real','ok',
      v_n = 0,'d', v_n||' accesos a clientes reales'));

    -- ── El ciclo completo ───────────────────────────────────────────────────────────────────────
    select count(*) into v_n from public.service_lines where organization_id = v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-11 · Hay volumen de un consultorio real, no cuatro líneas','ok',
      v_n >= 100,'d', v_n||' servicios capturados'));

    select count(*) into v_n from public.submissions where organization_id = v_org and status = 'radicada';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-12 · Hay dos lotes radicados, uno cobrado y otro en camino','ok',
      v_n = 2,'d', v_n||' radicados'));

    select count(*) into v_n from public.payments where organization_id = v_org;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-13 · La ARS pagó, y pagó dos veces','ok',
      v_n = 2,'d', v_n||' pagos'));

    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-14 · Hay una glosa peleada y ganada','ok',
      exists(select 1 from public.glosas where organization_id = v_org and status = 'revertida')
      and exists(select 1 from public.glosa_appeals where organization_id = v_org and outcome = 'favorable'),'d',null));

    select count(*) into v_n from public.appointments where organization_id = v_org and appointment_date >= current_date;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-15 · La agenda de la secretaria tiene hoy y los próximos días','ok',
      v_n >= 3,'d', v_n||' citas de hoy en adelante'));

    select count(*) into v_n from public.private_charges where organization_id = v_org and charge_type = 'copago';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-16 · Hay cobros privados y copagos por caja','ok',
      v_n >= 2 and exists(select 1 from public.private_charges where organization_id = v_org and charge_type = 'privado'),'d',
      v_n||' copagos'));

    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-17 · El DEMO tiene honorario sintético no fiscal para mostrar ROI','ok',
      exists(select 1 from public.sofa_fees where organization_id = v_org and period = v_per and source_type='manual'
             and description ilike 'DEMO%NO FISCAL%' and amount > 0),'d',
      (select 'RD

    -- ── Y lo que de verdad se enseña: que las pantallas traigan cifras ──────────────────────────
    select ou.user_id into v_u from public.organization_users ou
      join public.organizations o on o.id = ou.organization_id and o.kind = 'operator'
     where ou.role_code = 'super_admin' and ou.is_active limit 1;
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_u, 'role','authenticated','aal','aal2')::text, true);

    begin
      v_r := public.account_statement(v_org, v_per);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-18 · «Mi dinero» muestra caja cobrada, no RD$ 0.00','ok',
        (v_r->'roi'->>'collected')::numeric > 0,'d', 'RD$'||(v_r->'roi'->>'collected')));

      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-19 · El ROI es creíble: entre 4 y 20 veces','ok',
        (v_r->'roi'->>'return_x')::numeric between 4 and 20,'d', (v_r->'roi'->>'return_x')||'x · honorarios '||(v_r->'roi'->>'fee_pct_of_collected')||'% de lo cobrado'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-18/19 · «Mi dinero»','ok',false,'d',left(sqlerrm,120)));
    end;

    begin
      v_r := public.glosa_analytics(v_org, v_per - 120, current_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-20 · «Mis glosas» muestra una tasa baja y recuperación','ok',
        (v_r->'rates'->>'glosa_pct')::numeric between 0.1 and 10
        and (v_r->'rates'->>'recuperacion_pct')::numeric > 50,'d',
        'glosa '||(v_r->'rates'->>'glosa_pct')||'% · recuperado '||(v_r->'rates'->>'recuperacion_pct')||'%'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-20 · «Mis glosas»','ok',false,'d',left(sqlerrm,120)));
    end;

    begin
      v_r := public.collection_calendar(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-21 · «Calendario de cobros» tiene algo por cobrar','ok',
        (v_r->'totals'->>'balance')::numeric > 0,'d', 'RD$'||(v_r->'totals'->>'balance')));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-21 · «Calendario de cobros»','ok',false,'d',left(sqlerrm,120)));
    end;

    begin
      v_r := public.accountant_report(v_org, v_per);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-22 · «Reporte para mi contador» cuadra con lo cobrado','ok',
        (v_r->'summary'->>'income_ars')::numeric > 0,'d', 'RD$'||(v_r->'summary'->>'income_ars')));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-22 · «Reporte contador»','ok',false,'d',left(sqlerrm,120)));
    end;
    perform set_config('request.jwt.claims','',true);

    -- ── Que se pueda borrar entero ──────────────────────────────────────────────────────────────
    -- Todo cuelga del mismo id, que es lo que hace exacto al revertir.
    select count(*) into v_n from (
      select 1 from public.service_lines   where organization_id = v_org union all
      select 1 from public.payments        where organization_id = v_org union all
      select 1 from public.appointments    where organization_id = v_org union all
      select 1 from public.private_charges where organization_id = v_org union all
      select 1 from public.patients        where organization_id = v_org) q;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-23 · Todo lo sembrado cuelga de la organización demo','ok',
      v_n > 100,'d', v_n||' filas, todas borrables de una'));

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('role','none',true);
  perform set_config('request.jwt.claims','',true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when coalesce((x.e->>'ok')::boolean, false) then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$
||to_char(amount,'FM999,999.00')||' · NO FISCAL'
         from public.sofa_fees where organization_id = v_org and period = v_per and source_type='manual'
         order by calculated_at desc limit 1)));

    -- ── Y lo que de verdad se enseña: que las pantallas traigan cifras ──────────────────────────
    select ou.user_id into v_u from public.organization_users ou
      join public.organizations o on o.id = ou.organization_id and o.kind = 'operator'
     where ou.role_code = 'super_admin' and ou.is_active limit 1;
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_u, 'role','authenticated','aal','aal2')::text, true);

    begin
      v_r := public.account_statement(v_org, v_per);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-18 · «Mi dinero» muestra caja cobrada, no RD$ 0.00','ok',
        (v_r->'roi'->>'collected')::numeric > 0,'d', 'RD$'||(v_r->'roi'->>'collected')));

      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-19 · El ROI es creíble: entre 4 y 20 veces','ok',
        (v_r->'roi'->>'return_x')::numeric between 4 and 20,'d', (v_r->'roi'->>'return_x')||'x · honorarios '||(v_r->'roi'->>'fee_pct_of_collected')||'% de lo cobrado'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-18/19 · «Mi dinero»','ok',false,'d',left(sqlerrm,120)));
    end;

    begin
      v_r := public.glosa_analytics(v_org, v_per - 120, current_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-20 · «Mis glosas» muestra una tasa baja y recuperación','ok',
        (v_r->'rates'->>'glosa_pct')::numeric between 0.1 and 10
        and (v_r->'rates'->>'recuperacion_pct')::numeric > 50,'d',
        'glosa '||(v_r->'rates'->>'glosa_pct')||'% · recuperado '||(v_r->'rates'->>'recuperacion_pct')||'%'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-20 · «Mis glosas»','ok',false,'d',left(sqlerrm,120)));
    end;

    begin
      v_r := public.collection_calendar(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-21 · «Calendario de cobros» tiene algo por cobrar','ok',
        (v_r->'totals'->>'balance')::numeric > 0,'d', 'RD$'||(v_r->'totals'->>'balance')));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-21 · «Calendario de cobros»','ok',false,'d',left(sqlerrm,120)));
    end;

    begin
      v_r := public.accountant_report(v_org, v_per);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-22 · «Reporte para mi contador» cuadra con lo cobrado','ok',
        (v_r->'summary'->>'income_ars')::numeric > 0,'d', 'RD$'||(v_r->'summary'->>'income_ars')));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-22 · «Reporte contador»','ok',false,'d',left(sqlerrm,120)));
    end;
    perform set_config('request.jwt.claims','',true);

    -- ── Que se pueda borrar entero ──────────────────────────────────────────────────────────────
    -- Todo cuelga del mismo id, que es lo que hace exacto al revertir.
    select count(*) into v_n from (
      select 1 from public.service_lines   where organization_id = v_org union all
      select 1 from public.payments        where organization_id = v_org union all
      select 1 from public.appointments    where organization_id = v_org union all
      select 1 from public.private_charges where organization_id = v_org union all
      select 1 from public.patients        where organization_id = v_org) q;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DE-23 · Todo lo sembrado cuelga de la organización demo','ok',
      v_n > 100,'d', v_n||' filas, todas borrables de una'));

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('role','none',true);
  perform set_config('request.jwt.claims','',true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when coalesce((x.e->>'ok')::boolean, false) then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;

commit;
