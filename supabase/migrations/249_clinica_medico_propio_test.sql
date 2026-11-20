-- 249 · Suite de la 248 (clínica: cada médico ve solo lo suyo; director y secretaria compartida ven todo). Se deshace sola.
-- Ya aplicado en producción (2026-11-20): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_clinica_medico_propio();
create or replace function app.qa_run_tests_clinica_medico_propio()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_ok boolean; v_n int; v_m int; v_x jsonb;
  oC  constant uuid := 'b9000000-0000-4000-8000-0000000000a1';   -- clínica (2 médicos)
  oS  constant uuid := 'b9000000-0000-4000-8000-0000000000a2';   -- consultorio de un médico
  pC1 constant uuid := 'c9000000-0000-4000-8000-0000000000a1';
  pC2 constant uuid := 'c9000000-0000-4000-8000-0000000000a2';
  pS  constant uuid := 'c9000000-0000-4000-8000-0000000000a3';
  cC  constant uuid := 'd9000000-0000-4000-8000-0000000000a1';
  pat1 constant uuid := 'e9000000-0000-4000-8000-0000000000a1';
  pat2 constant uuid := 'e9000000-0000-4000-8000-0000000000a2';
  uC1 constant text := 'a9000000-0000-4000-8000-0000000000a1';
  uC2 constant text := 'a9000000-0000-4000-8000-0000000000a2';
  uDir constant text := 'a9000000-0000-4000-8000-0000000000a3';
  uSec constant text := 'a9000000-0000-4000-8000-0000000000a4';
  uS  constant text := 'a9000000-0000-4000-8000-0000000000a5';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  d constant date := current_date + 9;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email) values (uC1::uuid,'qa.cm.c1@sofa.test'),(uC2::uuid,'qa.cm.c2@sofa.test'),(uDir::uuid,'qa.cm.dir@sofa.test'),(uSec::uuid,'qa.cm.sec@sofa.test'),(uS::uuid,'qa.cm.s@sofa.test');
    insert into public.profiles (id, full_name) select id, email from auth.users where email like 'qa.cm.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (oC,'client',v_op,'QA CM Clinica','00000000161','Clínica','activo',current_date-90,'8095550031'),
      (oS,'client',v_op,'QA CM Solo','00000000162','Consultorio','activo',current_date-90,'8095550032');
    insert into public.providers (id, organization_id, full_name) values (pC1,oC,'Dr. CM Uno'),(pC2,oC,'Dra. CM Dos'),(pS,oS,'Dr. CM Solo');
    insert into public.health_centers (id, organization_id, name) values (cC, oC, 'Clinica CM');
    insert into public.provider_centers (provider_id, center_id, is_primary) values (pC1,cC,true),(pC2,cC,true);
    insert into public.organization_users (organization_id, user_id, role_code) values
      (oC,uC1::uuid,'client'),(oC,uC2::uuid,'client'),(oC,uDir::uuid,'client'),(oC,uSec::uuid,'capturer'),(oS,uS::uuid,'client');
    update public.organization_users set sees_all_providers = true where organization_id = oC and user_id = uDir::uuid;
    update public.providers set user_id = case id when pC1 then uC1::uuid when pC2 then uC2::uuid end where id in (pC1, pC2);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_book, can_whatsapp, can_payments) values
      (uSec::uuid,pC1,oC,true,false,false),(uSec::uuid,pC2,oC,true,false,false);
    insert into public.patients (id, organization_id, full_name) values (pat1, oC, 'Paciente CM Uno'), (pat2, oC, 'Paciente CM Dos');
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type, center_id, patient_id) values
      (oC,pC1,d,'09:00','Paciente CM Uno','privado',cC,pat1),(oC,pC2,d,'09:00','Paciente CM Dos','privado',cC,pat2),
      (oS,pS,d,'09:00','Paciente CM Solo','privado',null,null);

    -- Dr. C1, médico de clínica
    perform set_config('request.jwt.claims', json_build_object('sub',uC1,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    select count(*) into v_n from public.appointments where provider_id in (pC1,pC2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-01 · El médico de clínica ve solo sus citas','ok',v_n = 1,'d',v_n || ' visibles'));
    begin perform public.agenda_week(pC2, cC, d, 1);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-02 · No abre la semana de su colega','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-02 · No abre la semana de su colega','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    begin perform public.list_assistants(pC2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-03 · No ve las secretarias de su colega','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-03 · No ve las secretarias de su colega','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    select count(*) into v_n from public.patients where id in (pat1, pat2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-04 · Ve solo sus pacientes','ok',v_n = 1,'d',v_n || ' visibles'));
    v_x := public.flow_board(oC, d);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-05 · El flujo de pacientes muestra solo los suyos','ok',jsonb_array_length(v_x) = 1,'d',left(v_x::text,120)));
    v_x := public.reception_day(cC, d);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-06 · En la recepción ve solo su columna','ok',jsonb_array_length(v_x->'providers') = 1,'d',left(v_x::text,120)));
    begin perform public.set_clinic_director(oC, uC1::uuid, true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-07 · Un médico no se marca a sí mismo como director','ok',false,'d','Se permitió'));
    exception when others then v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-07 · Un médico no se marca a sí mismo como director','ok',sqlstate = '42501','d',left(sqlerrm,120))); end;
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    -- Director de la clínica
    perform set_config('request.jwt.claims', json_build_object('sub',uDir,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    select count(*) into v_n from public.appointments where provider_id in (pC1,pC2);
    select count(*) into v_m from public.patients where id in (pat1, pat2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-08 · El director ve las citas y pacientes de toda la clínica','ok',v_n = 2 and v_m = 2,'d',v_n || ' citas, ' || v_m || ' pacientes'));
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    -- Secretaria compartida por los dos médicos de la clínica
    perform set_config('request.jwt.claims', json_build_object('sub',uSec,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    select count(*) into v_n from public.appointments where provider_id in (pC1,pC2);
    v_x := public.flow_board(oC, d);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-09 · La secretaria compartida ve las agendas de sus dos médicos','ok',v_n = 2 and jsonb_array_length(v_x) = 2,'d',v_n || ' citas'));
    perform set_config('role','none',true); perform set_config('request.jwt.claims','',true);

    -- Consultorio de un solo médico: sin cambios
    perform set_config('request.jwt.claims', json_build_object('sub',uS,'role','authenticated')::text, true); perform set_config('role','authenticated',true);
    select count(*) into v_n from public.appointments where provider_id = pS;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CM-10 · Consultorio de un solo médico: sigue viendo todo lo suyo','ok',v_n = 1,'d',v_n || ' visibles'));
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
revoke execute on function app.qa_run_tests_clinica_medico_propio() from public, anon, authenticated;
