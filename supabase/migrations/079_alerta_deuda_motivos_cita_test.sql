-- 079 · Suite de la 078 (alerta de deuda con SOFA y motivos de cita). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_deuda_motivos();
create or replace function app.qa_run_tests_deuda_motivos()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_inv uuid := 'e7000000-0000-4000-8000-0000000000f1';
  v_ars uuid; v_proc uuid; v_proc2 uuid;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000000d1';
  v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000000d2';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000000d1';
  v_op constant uuid := '00000000-0000-4000-8000-000000000001';
  v_admin constant text := 'a7000000-0000-4000-8000-0000000000d1';
  v_cli constant text := 'a7000000-0000-4000-8000-0000000000d2';
  v_otro constant text := 'a7000000-0000-4000-8000-0000000000d3';
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_admin::uuid, 'qa.dm.admin@sofa.test', 'x'), (v_cli::uuid, 'qa.dm.cli@sofa.test', 'x'), (v_otro::uuid, 'qa.dm.otro@sofa.test', 'x');
    insert into public.profiles (id, full_name) select id, replace(email, '@sofa.test', '') from auth.users where email like 'qa.dm.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp) values
      (v_org, 'client', v_op, 'QA DM A', '00000000161', 'Médico independiente', 'activo', current_date - 90, '8095550004'),
      (v_org2, 'client', v_op, 'QA DM B', '00000000162', 'Médico independiente', 'activo', current_date - 90, '8095550005');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. DM A', 'Cardiología');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_op, v_admin::uuid, 'admin'), (v_org, v_cli::uuid, 'client'), (v_org2, v_otro::uuid, 'client');
    select id into v_ars from public.ars where code = 'humano';
    select id into v_proc from public.procedures where internal_code = 'SOFA-P07';
    select id into v_proc2 from public.procedures where is_active and id <> v_proc order by internal_code limit 1;
    insert into public.sofa_invoices (id, organization_id, folio, period, issued_on, due_on, total, status)
      values (v_inv, v_org, 'QA-DM-1', date_trunc('month', current_date - 60)::date, current_date - 50, current_date - 20, 1000, 'emitida');
    insert into public.sofa_invoice_payments (sofa_invoice_id, organization_id, paid_on, amount, method) values (v_inv, v_org, current_date - 5, 400, 'transferencia');

    -- CT-01 · El médico ve su deuda vencida con el saldo correcto (1000 - 400)
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.sofa_debt_alert(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Deuda vencida con saldo correcto','ok',
      v_x->>'level' = 'vencido' and (v_x->>'overdue')::numeric = 600 and (v_x->>'max_days_overdue')::int = 20,'d',v_x::text));

    -- CT-02 · Otro médico no puede ver la cuenta
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.sofa_debt_alert(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Otro cliente no ve la deuda ajena','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Otro cliente no ve la deuda ajena','ok',sqlerrm like 'Sin acceso a la cuenta%','d',left(sqlerrm,100)));
    end;
    -- y sin deuda queda al día
    v_x := public.sofa_debt_alert(v_org2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Sin facturas queda al día','ok',v_x->>'level' = 'al_dia','d',v_x::text));

    -- CT-04 · Factura pagada completa deja de contar
    perform set_config('role', 'none', true);
    insert into public.sofa_invoice_payments (sofa_invoice_id, organization_id, paid_on, amount, method) values (v_inv, v_org, current_date, 600, 'transferencia');
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_x := public.sofa_debt_alert(v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Pagada completa: al día','ok',v_x->>'level' = 'al_dia' and (v_x->>'pending')::numeric = 0,'d',v_x::text));

    -- Motivos de cita
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    perform public.create_contract_tariff(v_prov, v_ars, v_proc, 1500, current_date - 30, null, 'CT-DM');
    perform public.create_contract_tariff(v_prov, v_ars, v_proc2, 900, current_date - 30, null, 'CT-DM2');
    v_x := public.appointment_reasons(v_prov, v_ars);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Motivos: 2 consultas fijas + 2 servicios contratados','ok',jsonb_array_length(v_x) = 4
      and v_x->0->>'label' = 'Consulta primera vez' and v_x->1->>'label' = 'Consulta de seguimiento','d',jsonb_array_length(v_x)::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · El servicio trae el monto de la tarifa','ok',
      exists (select 1 from jsonb_array_elements(v_x) e where (e->>'amount')::numeric = 1500),'d',null));
    v_x := public.appointment_reasons(v_prov, null);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Sin ARS solo las 2 consultas','ok',jsonb_array_length(v_x) = 2,'d',null));

    -- CT-08 · Tarifa suspendida no aparece
    perform set_config('role', 'none', true);
    update public.tariffs set status = 'suspendida' where provider_id = v_prov and procedure_id = v_proc2;
    perform set_config('role', 'authenticated', true);
    v_x := public.appointment_reasons(v_prov, v_ars);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Tarifa suspendida no se ofrece','ok',jsonb_array_length(v_x) = 3,'d',jsonb_array_length(v_x)::text));

    -- CT-09 · Otro cliente no ve los motivos de este médico
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.appointment_reasons(v_prov, v_ars);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Acceso a motivos protegido','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Acceso a motivos protegido','ok',sqlerrm like 'Sin acceso a este médico%','d',left(sqlerrm,100)));
    end;

    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,   -- 5.10.0: una prueba sin resultado (NULL) cuenta como fallo; antes bool_and la ignoraba
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;
