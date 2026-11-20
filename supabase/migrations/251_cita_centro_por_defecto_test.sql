-- 251 · Suite de la 250 (centro por defecto de la cita). Se deshace sola.
-- Ya aplicado en producción (2026-11-20): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_cita_centro();
create or replace function app.qa_run_tests_cita_centro()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_c uuid;
  o  constant uuid := 'b9000000-0000-4000-8000-0000000000c1';
  p1 constant uuid := 'c9000000-0000-4000-8000-0000000000c1';   -- un solo centro, no principal
  p2 constant uuid := 'c9000000-0000-4000-8000-0000000000c2';   -- dos centros, ninguno principal
  c1 constant uuid := 'd9000000-0000-4000-8000-0000000000c1';
  c2 constant uuid := 'd9000000-0000-4000-8000-0000000000c2';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
      values (o,'client','00000000-0000-4000-8000-000000000001','QA CC','00000000181','Consultorio','activo',current_date-30,'8095550051');
    insert into public.providers (id, organization_id, full_name) values (p1,o,'Dr. CC Uno'),(p2,o,'Dr. CC Dos');
    insert into public.health_centers (id, organization_id, name) values (c1,o,'Centro CC 1'),(c2,o,'Centro CC 2');
    insert into public.provider_centers (provider_id, center_id, is_primary) values (p1,c1,false),(p2,c1,false),(p2,c2,false);
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type)
      values (o,p1,current_date+10,'09:00','Paciente CC Uno','privado') returning center_id into v_c;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CC-01 · Médico con un solo centro: la cita sin centro recibe ese centro','ok',v_c = c1,'d',coalesce(v_c::text,'sin centro')));
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type)
      values (o,p2,current_date+10,'09:00','Paciente CC Dos','privado') returning center_id into v_c;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CC-02 · Médico con varios centros y sin principal: no se adivina el centro','ok',v_c is null,'d',coalesce(v_c::text,'sin centro')));
    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
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
revoke execute on function app.qa_run_tests_cita_centro() from public, anon, authenticated;
