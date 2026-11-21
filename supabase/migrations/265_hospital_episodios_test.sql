-- 265 · Suite de la 264 (episodio de hospitalización: aviso, traslados, autorización por tramo, egreso). Se deshace sola.
-- Ya aplicado en producción (2026-11-21): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_hospital_episodios();
create or replace function app.qa_run_tests_hospital_episodios()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_rep uuid; v_proc uuid; v_n int;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  o    constant uuid := '26500000-0000-4000-8000-0000000000a1';
  oX   constant uuid := '26500000-0000-4000-8000-0000000000a2';
  pr   constant uuid := '26500000-0000-4000-8000-0000000000b1';
  pr2  constant uuid := '26500000-0000-4000-8000-0000000000b2';
  hc   constant uuid := '26500000-0000-4000-8000-0000000000c1';
  uMed constant uuid := '26500000-0000-4000-8000-000000000001';
  uMed2 constant uuid := '26500000-0000-4000-8000-000000000002';
  uSec constant uuid := '26500000-0000-4000-8000-000000000003';
  uSecX constant uuid := '26500000-0000-4000-8000-000000000004';
  uBil constant uuid := '26500000-0000-4000-8000-000000000005';
  uOtro constant uuid := '26500000-0000-4000-8000-000000000006';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into public.organizations (id, kind, operator_id, legal_name, org_type, status, started_on) values
      (o,'client',v_sofa,'QA 265 Clínica','Centro médico','activo',current_date-200),
      (oX,'client',v_sofa,'QA 265 Otra','Centro médico','activo',current_date-200);
    insert into auth.users (id,email) values (uMed,'qa.265.med@sofa.do'),(uMed2,'qa.265.med2@sofa.do'),(uSec,'qa.265.sec@sofa.do'),
      (uSecX,'qa.265.secx@sofa.do'),(uBil,'qa.265.bil@sofa.do'),(uOtro,'qa.265.otro@sofa.do');
    insert into public.profiles (id, full_name, is_active) select id, email, true from auth.users where email like 'qa.265.%' on conflict (id) do update set is_active = true;
    insert into public.organization_users (organization_id,user_id,role_code,is_active) values
      (o,uMed,'client',true),(o,uMed2,'client',true),(o,uSec,'capturer',true),(o,uSecX,'capturer',true),(v_sofa,uBil,'billing',true),(oX,uOtro,'client',true);
    insert into public.providers (id, organization_id, full_name, is_active, user_id) values
      (pr,o,'Dr. 265',true,uMed),(pr2,o,'Dra. 265 B',true,uMed2);
    insert into public.health_centers (id, organization_id, name, is_active) values (hc,o,'Centro 265',true);
    insert into public.provider_centers (provider_id, center_id, is_primary) values (pr,hc,true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp) values (uSec,pr,o,true,false),(uSecX,pr2,o,true,false);
    insert into public.staff_client_access (user_id, client_org_id) values (uBil, o);   -- Facturación asignada a este cliente
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;

    -- Día 1: el médico crea el reporte y avisa el ingreso por Emergencia.
    perform set_config('request.jwt.claims', json_build_object('sub',uMed,'role','authenticated','aal','aal2')::text, true);
    v_x := public.hospital_report_save(hc, 'Paciente 265', null, null, current_date-5, null, null);
    v_rep := (v_x->>'id')::uuid;
    if v_rep is null then v_rep := (select id from public.hospital_reports where patient_name = 'Paciente 265'); end if;
    v_x := public.hospital_episode_notify(v_rep, 'emergencia', null);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-01 · Aviso de ingreso: queda «ingresado» con un tramo abierto en Emergencia','ok',
      v_x->>'estado' = 'ingresado' and v_x->>'area_actual' = 'emergencia' and jsonb_array_length(v_x->'tramos') = 1,'d',v_x->>'estado'));
    perform public.hospital_report_line_add(v_rep, v_proc, current_date-5, 1, 1000, null);
    begin perform public.hospital_report_submit(v_rep);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-02 · Sin egreso no se envía para reclamar','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-02 · Sin egreso no se envía para reclamar','ok',sqlerrm like 'El paciente sigue ingresado%','d',left(sqlerrm,110))); end;
    begin perform public.hospital_episode_notify(v_rep, 'uci', null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-03 · No se avisa dos veces el mismo ingreso','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-03 · No se avisa dos veces el mismo ingreso','ok',sqlerrm like '%Trasladar%','d',left(sqlerrm,110))); end;

    -- Traslados: Emergencia → UCI (día 4 atrás) → planta (día 2 atrás).
    v_x := public.hospital_episode_transfer(v_rep, 'uci', current_date-4, null);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-04 · UCI sin autorización queda marcada','ok',(v_x->>'sin_autorizacion')::boolean,'d',null));
    perform set_config('request.jwt.claims', json_build_object('sub',uSec,'role','authenticated')::text, true);
    v_x := public.hospital_episode_set_auth((select id from public.hospital_stays where report_id = v_rep and area = 'uci'), 'AUT-UCI-1');
    v_x := public.hospital_episode_transfer(v_rep, 'hospitalizacion', current_date-2, 'AUT-PL-1');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-05 · La secretaria del médico registra la autorización y el traslado a planta','ok',
      v_x->>'area_actual' = 'hospitalizacion' and not (v_x->>'sin_autorizacion')::boolean and jsonb_array_length(v_x->'tramos') = 3,'d',v_x->>'area_actual'));
    begin perform public.hospital_episode_transfer(v_rep, 'uci', current_date-3, null);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-06 · No hay traslado con fecha anterior al tramo abierto','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-06 · No hay traslado con fecha anterior al tramo abierto','ok',sqlerrm like 'La fecha del traslado%','d',left(sqlerrm,110))); end;

    -- Quién no puede
    perform set_config('request.jwt.claims', json_build_object('sub',uSecX,'role','authenticated')::text, true);
    begin perform public.hospital_episode_discharge(v_rep, current_date);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-07 · La secretaria de otro médico de la clínica no lo toca','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-07 · La secretaria de otro médico de la clínica no lo toca','ok',sqlstate = '42501','d',left(sqlerrm,110))); end;
    perform set_config('request.jwt.claims', json_build_object('sub',uMed2,'role','authenticated','aal','aal2')::text, true);
    begin perform public.hospital_episode_get(v_rep);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-08 · El colega de la clínica no ve el episodio','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-08 · El colega de la clínica no ve el episodio','ok',sqlstate = '42501','d',left(sqlerrm,110))); end;
    v_n := jsonb_array_length(public.hospital_episodes_open());
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-09 · El colega no lo ve en «Pacientes ingresados»','ok',v_n = 0,'d',v_n::text));
    perform set_config('request.jwt.claims', json_build_object('sub',uOtro,'role','authenticated','aal','aal2')::text, true);
    v_n := jsonb_array_length(public.hospital_episodes_open());
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-10 · Otro consultorio no ve ingresados ajenos','ok',v_n = 0,'d',v_n::text));

    -- Personal de SOFA (facturación) lo ve y registra el egreso.
    perform set_config('request.jwt.claims', json_build_object('sub',uBil,'role','authenticated','aal','aal2')::text, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-11 · Facturación de SOFA ve el paciente en «Pacientes ingresados»','ok',
      exists (select 1 from jsonb_array_elements(public.hospital_episodes_open()) e where (e->>'id')::uuid = v_rep),'d',null));
    v_x := public.hospital_episode_discharge(v_rep, current_date);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-12 · Egreso: cierra el último tramo y queda «egresado» con 5 días','ok',
      v_x->>'estado' = 'egresado' and v_x->>'area_actual' is null and (v_x->>'dias')::int = 5
      and (select count(*) from public.hospital_stays where report_id = v_rep and ended_on is null) = 0,'d',v_x->>'dias'));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-13 · Días por área: Emergencia 1, UCI 2, planta 2','ok',
      (select string_agg(e->>'area' || '=' || (e->>'dias'), ',' order by e->>'started_on') from jsonb_array_elements(v_x->'tramos') e) = 'emergencia=1,uci=2,hospitalizacion=2',
      'd',(select string_agg(e->>'area' || '=' || (e->>'dias'), ',' order by e->>'started_on') from jsonb_array_elements(v_x->'tramos') e)));

    -- Con egreso, el médico ya puede enviarlo para reclamar.
    perform set_config('request.jwt.claims', json_build_object('sub',uMed,'role','authenticated','aal','aal2')::text, true);
    perform public.hospital_report_submit(v_rep);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-14 · Con egreso se envía para reclamar','ok',(select status from public.hospital_reports where id = v_rep) = 'enviado','d',null));
    begin perform public.hospital_episode_set_auth((select id from public.hospital_stays where report_id = v_rep limit 1), 'X');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-15 · Enviado: los tramos ya no cambian','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-15 · Enviado: los tramos ya no cambian','ok',sqlerrm like 'Este reporte ya se envió%','d',left(sqlerrm,110))); end;

    perform set_config('request.jwt.claims','',true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','HE-16 · Tramos fuera de la API; funciones no abiertas a anon','ok',
      not has_table_privilege('authenticated','public.hospital_stays','select')
      and not has_function_privilege('anon','public.hospital_episodes_open()','execute')
      and not has_function_privilege('authenticated','app.hospital_episode_can_edit(uuid)','execute'),'d',null));

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;
revoke execute on function app.qa_run_tests_hospital_episodios() from public, anon, authenticated;
