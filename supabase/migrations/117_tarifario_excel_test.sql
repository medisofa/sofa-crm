-- 117 · Suite de la 116 (tarifario desde Excel, historial y vencimientos). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_tarifario_excel();
create or replace function app.qa_run_tests_tarifario_excel()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000002a1'; v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000002a2';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000002a1';
  v_med constant text := 'a7000000-0000-4000-8000-0000000002a1'; v_otro constant text := 'a7000000-0000-4000-8000-0000000002a2';
  v_adm constant text := 'a7000000-0000-4000-8000-0000000002a3';
  v_ars uuid; v_ars_name text; v_p1 uuid; v_p2 uuid; v_c1 text; v_c2 text; v_rows jsonb;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.te.med@sofa.test','x'),(v_otro::uuid,'qa.te.otro@sofa.test','x'),(v_adm::uuid,'qa.te.adm@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.te.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA TE A', '00000000701', 'Médico independiente', 'activo', current_date - 90, '8095550701');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA TE B', '00000000702', 'Médico independiente', 'activo', current_date - 90, '8095550702');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dr. TE', 'Pediatría');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org2, v_otro::uuid, 'client'), ('00000000-0000-4000-8000-000000000001'::uuid, v_adm::uuid, 'admin');
    select id, name into v_ars, v_ars_name from public.ars where is_active order by name limit 1;
    select id, internal_code into v_p1, v_c1 from public.procedures where is_active and internal_code is not null order by internal_code limit 1;
    select id, internal_code into v_p2, v_c2 from public.procedures where is_active and internal_code is not null and id <> v_p1 order by internal_code limit 1;
    -- Tarifa vigente previa para el primer servicio (para probar «cambia» e «igual»)
    perform public.create_contract_tariff(v_prov, v_ars, v_p1, 1000, current_date - 30, null, 'CT-VIEJO');
    v_rows := jsonb_build_array(
      jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', v_c1, 'tarifa', '1,200.00', 'desde', to_char(current_date, 'DD/MM/YYYY'), 'contrato', 'CT-2026'),
      jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', v_c2, 'tarifa', 'RD$850', 'desde', to_char(current_date, 'DD/MM/YYYY'), 'contrato', 'CT-2026'));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.import_contract_tariffs_v2(v_rows, false, 'tarifario.xlsx');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Vista previa: 1 nueva y 1 que cambia (+20 %)','ok',coalesce(((v_x->>'new')::int = 1 and (v_x->>'changed')::int = 1 and exists (select 1 from jsonb_array_elements(v_x->'rows') r where r->>'change' = 'cambia' and (r->>'diff_pct')::numeric = 20)), false),'d',(v_x->>'new' || ' nuevas, ' || (v_x->>'changed') || ' cambian')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · La vista previa no guarda nada','ok',coalesce(((select count(*) from public.tariffs where provider_id = v_prov) = 1), false),'d',(null)::text));
    v_x := public.import_contract_tariffs_v2(v_rows, true, 'tarifario.xlsx');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Al confirmar importa 2 y cierra la tarifa anterior','ok',coalesce(((v_x->>'imported')::int = 2 and (select amount from public.tariffs where provider_id = v_prov and procedure_id = v_p1 and valid_during @> current_date) = 1200), false),'d',(v_x->>'imported')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Queda en el historial de cargas','ok',coalesce((exists (select 1 from jsonb_array_elements(public.tariff_import_history(v_org)) h where h->>'file' = 'tarifario.xlsx' and (h->>'imported')::int = 2 and h->>'contract' = 'CT-2026')), false),'d',(null)::text));
    v_rows := jsonb_build_array(jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', v_c1, 'tarifa', '1200', 'desde', to_char(current_date + 1, 'DD/MM/YYYY'), 'contrato', 'CT-2026'));
    v_x := public.import_contract_tariffs_v2(v_rows, false, 'otra.csv');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Misma tarifa: se marca «igual» y no se vuelve a cargar','ok',coalesce(((v_x->>'same')::int = 1), false),'d',(v_x::text)::text));
    v_x := public.import_contract_tariffs_v2(jsonb_build_array(jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', 'NO-EXISTE-QA', 'tarifa', '0', 'desde', 'ayer')), false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Filas con error se explican','ok',coalesce((jsonb_array_length(v_x->'errors') = 1), false),'d',(v_x->'errors')::text));
    begin
      perform public.import_contract_tariffs_v2(jsonb_build_array(jsonb_build_object('medico', v_prov, 'ars', v_ars, 'servicio', 'NO-EXISTE-QA', 'tarifa', '0', 'desde', 'ayer')), true);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · No confirma si hay errores','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · No confirma si hay errores','ok',sqlerrm like 'Corrija las 1 filas con errores%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    insert into public.tariffs (ars_id, organization_id, provider_id, procedure_id, amount, valid_during, source, contract_ref)
    select v_ars, v_org, v_prov, p.id, 777, daterange(current_date - 10, current_date + 21), 'Contrato', 'CT-VENCE'
      from public.procedures p where p.is_active and p.id not in (v_p1, v_p2) order by p.internal_code limit 1;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    v_x := public.tariffs_expiring(60, v_org);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Aviso a SOFA de tarifas que vencen en 60 días','ok',coalesce((exists (select 1 from jsonb_array_elements(v_x->'tariffs') t where t->>'contract' = 'CT-VENCE' and (t->>'days_left')::int = 20) or not exists (select 1 from public.procedures p where p.is_active and p.id not in (v_p1, v_p2))), false),'d',(v_x->'tariffs')::text));
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.tariff_import_history(v_org);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Otro médico no ve el historial ajeno','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-09 · Otro médico no ve el historial ajeno','ok',sqlerrm like 'Sin acceso a este cliente%','d',left(sqlerrm,120)));
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
