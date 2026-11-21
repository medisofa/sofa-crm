-- 257 · Suite de la 256 (clínica: dinero, reportes y mensajes solo del médico propio; director ve todo). Se deshace sola.
-- Ya aplicado en producción (2026-11-20): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_clinica_dinero();
create or replace function app.qa_run_tests_clinica_dinero()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_n int; v_m int; v_x jsonb; v_msg text;
  oC  constant uuid := 'b9000000-0000-4000-8000-0000000000f6';
  oS  constant uuid := 'b9000000-0000-4000-8000-0000000000f7';
  pC1 constant uuid := 'c9000000-0000-4000-8000-0000000000f6';
  pC2 constant uuid := 'c9000000-0000-4000-8000-0000000000f7';
  pS  constant uuid := 'c9000000-0000-4000-8000-0000000000f8';
  uC1 constant text := 'a9000000-0000-4000-8000-0000000000f6';
  uC2 constant text := 'a9000000-0000-4000-8000-0000000000f7';
  uDir constant text := 'a9000000-0000-4000-8000-0000000000f8';
  uS  constant text := 'a9000000-0000-4000-8000-0000000000f9';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  m1 constant date := date_trunc('month', current_date)::date;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email) values (uC1::uuid,'qa.dr.c1@sofa.test'),(uC2::uuid,'qa.dr.c2@sofa.test'),(uDir::uuid,'qa.dr.dir@sofa.test'),(uS::uuid,'qa.dr.s@sofa.test');
    insert into public.profiles (id, full_name) select id, email from auth.users where email like 'qa.dr.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (oC,'client',v_op,'QA DR Clinica','00000000201','Clínica','activo',current_date-90,'8095550081'),
      (oS,'client',v_op,'QA DR Solo','00000000202','Consultorio','activo',current_date-90,'8095550082');
    insert into public.providers (id, organization_id, full_name) values (pC1,oC,'Dr. DR Uno'),(pC2,oC,'Dra. DR Dos'),(pS,oS,'Dr. DR Solo');
    insert into public.organization_users (organization_id, user_id, role_code) values
      (oC,uC1::uuid,'client'),(oC,uC2::uuid,'client'),(oC,uDir::uuid,'client'),(oS,uS::uuid,'client');
    update public.organization_users set sees_all_providers = true where organization_id = oC and user_id = uDir::uuid;
    update public.providers set user_id = case id when pC1 then uC1::uuid when pC2 then uC2::uuid end where id in (pC1, pC2);
    insert into public.sofa_invoices (organization_id, period, issued_on, due_on) values (oC, m1, current_date, current_date + 15);
    insert into public.message_queue (organization_id, provider_id, kind, subject, body, scheduled_for) values
      (oC, pC1, 'resumen_semanal', 'QA', 'QA uno', current_date), (oC, pC2, 'resumen_semanal', 'QA', 'QA dos', current_date);
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type, status) values
      (oC, pC1, current_date, '09:00', 'Paciente DR Uno', 'privado', 'programada'), (oC, pC2, current_date, '09:00', 'Paciente DR Dos', 'privado', 'programada');

    -- Dr. C1 (médico de clínica)
    perform set_config('request.jwt.claims', json_build_object('sub',uC1,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    select count(*) into v_n from public.sofa_invoices where organization_id = oC;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-01 · No ve las facturas de SOFA a la clínica','ok',v_n = 0,'d',v_n || ' visibles'));
    select count(*) into v_n from public.message_queue where organization_id = oC;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-02 · Ve solo sus mensajes','ok',v_n = 1,'d',v_n || ' visibles'));
    begin perform public.account_statement(oC, m1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-03 · El estado de cuenta de toda la clínica queda para el director','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-03 · El estado de cuenta de toda la clínica queda para el director','ok',sqlerrm like 'En una clínica este reporte lo ve el director%','d',left(sqlerrm,120))); end;
    begin perform public.weekly_summary(pC2, m1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-04 · No abre el resumen semanal de su colega','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-04 · No abre el resumen semanal de su colega','ok',sqlerrm like 'En una clínica cada médico maneja solo lo suyo%','d',left(sqlerrm,120))); end;
    v_x := public.my_dashboard();
    select (k->>'value')::int into v_n from jsonb_array_elements(v_x->'sections') s, jsonb_array_elements(s->'kpis') k where s->>'code' = 'medico' and k->>'code' = 'citas_hoy';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-05 · Su inicio cuenta solo sus citas de hoy y no muestra la deuda con SOFA','ok',v_n = 1
      and not exists (select 1 from jsonb_array_elements(v_x->'sections') s where s->>'code' = 'medico' and s->'alert' is not null and s->'alert' <> 'null'::jsonb),'d',coalesce(v_n::text,'sin KPI')));
    v_x := public.fee_scheme(oC);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-06 · No ve el esquema de honorarios SOFA de la clínica','ok',v_x is null,'d',left(coalesce(v_x::text,'vacío'),120)));
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    -- Directora
    perform set_config('request.jwt.claims', json_build_object('sub',uDir,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    select count(*) into v_n from public.sofa_invoices where organization_id = oC;
    select count(*) into v_m from public.message_queue where organization_id = oC;
    v_x := public.my_dashboard();
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-07 · La directora ve las facturas SOFA, todos los mensajes y su inicio cuenta toda la clínica','ok',
      v_n = 1 and v_m = 2 and exists (select 1 from jsonb_array_elements(v_x->'sections') s, jsonb_array_elements(s->'kpis') k where s->>'code' = 'medico' and k->>'code' = 'citas_hoy' and (k->>'value')::int = 2),
      'd',v_n || ' facturas, ' || v_m || ' mensajes'));
    begin perform public.account_statement(oC, m1); v_msg := 'ok';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-08 · La directora no recibe el bloqueo de clínica en el estado de cuenta','ok',v_msg not like 'En una clínica%','d',left(v_msg,120)));
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    -- Consultorio de un solo médico: sin cambios
    perform set_config('request.jwt.claims', json_build_object('sub',uS,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    begin perform public.account_statement(oS, m1); v_msg := 'ok';
    exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','DR-09 · Consultorio de un solo médico: su estado de cuenta no se bloquea','ok',v_msg not like 'En una clínica%','d',left(v_msg,120)));
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('role', 'none', true);
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
revoke execute on function app.qa_run_tests_clinica_dinero() from public, anon, authenticated;
