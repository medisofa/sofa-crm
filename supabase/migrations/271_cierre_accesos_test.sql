-- Ya aplicado en producción (26/11/2026). Se guarda aquí como documentación.
-- 271 · Suite de la 270 (cierre de seguridad). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_cierre_accesos();
create or replace function app.qa_run_tests_cierre_accesos()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql set search_path = '' as $function$
declare
  v_res jsonb := '[]'::jsonb; v_msg text; v_a boolean; v_b boolean; v_c boolean; v_n int; v_m int;
  v_sofa constant uuid := '00000000-0000-4000-8000-000000000001';
  v_sec constant uuid := '27000000-0000-4000-8000-000000000001';
  v_med constant uuid := '27000000-0000-4000-8000-000000000002';
  v_pro constant uuid := '27000000-0000-4000-8000-000000000003';
  v_otro constant uuid := '27000000-0000-4000-8000-000000000004';
  v_org constant uuid := '27000000-0000-4000-8000-0000000000a1';
  v_prov constant uuid := '27000000-0000-4000-8000-0000000000b1';
  v_lead uuid; v_case uuid; v_item uuid; v_pn text; v_cn text;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values
      (v_sec,'qa.cs.sec@sofa.test','x'), (v_med,'qa.cs.med@sofa.test','x'), (v_pro,'qa.cs.pro@sofa.test','x'), (v_otro,'qa.cs.otro@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.cs.%@sofa.test' on conflict (id) do nothing;
    update public.profiles set must_change_password = false, is_active = true where id in (v_sec, v_med, v_pro, v_otro);
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', v_sofa, 'QA CS Consultorio', '00000027001', 'Médico independiente', 'activo', current_date - 90, '8095552701');
    insert into public.providers (id, organization_id, full_name, specialty, is_active) values (v_prov, v_org, 'Dr. CS QA', 'Cardiología', true);
    insert into public.organization_users (organization_id, user_id, role_code, is_active) values (v_org, v_sec, 'capturer', true), (v_org, v_med, 'client', true);
    insert into public.capturer_scopes (user_id, provider_id, organization_id, can_payments) values (v_sec, v_prov, v_org, true);
    insert into public.leads (operator_id, company) values (v_sofa, 'QA CS Prospecto') returning id into v_lead;
    insert into public.lead_users (lead_id, user_id, is_active) values (v_lead, v_pro, true);
    insert into public.habilitation_cases (operator_id, lead_id, establishment_name, establishment_type) values (v_sofa, v_lead, 'QA CS Prospecto', 'Consultorio') returning id into v_case;
    insert into public.habilitation_items (case_id, area) values (v_case, 'QA') returning id into v_item;
    v_pn := 'prospects/' || v_item || '/qa.pdf';
    v_cn := 'clients/' || v_org || '/' || v_item || '/qa.pdf';

    perform set_config('role', 'authenticated', true);
    -- Secretaría activa: conserva su acceso
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_a := app.patient_access(v_org); v_b := app.payments_read_ok(v_org); v_c := app.payments_write_ok(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Secretaría activa conserva pacientes y pagos','ok',coalesce(v_a and v_b and v_c, false),'d',format('%s %s %s', v_a, v_b, v_c)));

    -- Prospecto dueño: sube y lee lo suyo
    perform set_config('request.jwt.claims', json_build_object('sub', v_pro, 'role', 'authenticated')::text, true);
    v_msg := null; begin insert into storage.objects (bucket_id, name) values ('habilitation-documents', v_pn); exception when others then v_msg := sqlerrm; end;
    select count(*) into v_n from storage.objects where bucket_id = 'habilitation-documents' and name = v_pn;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · El prospecto sube y lee su documento','ok',coalesce(v_msg is null and v_n = 1, false),'d',v_msg));

    -- Otra sesión cualquiera: ni lee ni sube
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    select count(*) into v_n from storage.objects where bucket_id = 'habilitation-documents' and name = v_pn;
    v_msg := null; begin insert into storage.objects (bucket_id, name) values ('habilitation-documents', 'prospects/' || v_item || '/ajeno.pdf'); exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Un usuario ajeno no lee ni sube en prospects','ok',coalesce(v_n = 0 and v_msg like '%row-level security%', false),'d',v_n || ' · ' || coalesce(v_msg,'subió')));

    -- Médico activo: sube y lee en clients/
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_msg := null; begin insert into storage.objects (bucket_id, name) values ('habilitation-documents', v_cn); exception when others then v_msg := sqlerrm; end;
    select count(*) into v_n from storage.objects where bucket_id = 'habilitation-documents' and name = v_cn;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · El médico activo sube y lee su carpeta','ok',coalesce(v_msg is null and v_n = 1, false),'d',v_msg));

    -- Se desactivan las membresías
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    update public.organization_users set is_active = false where organization_id = v_org;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_a := app.patient_access(v_org); v_b := app.payments_read_ok(v_org); v_c := app.payments_write_ok(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Membresía desactivada: sin pacientes ni pagos','ok',coalesce(not v_a and not v_b and not v_c, false),'d',format('%s %s %s', v_a, v_b, v_c)));
    v_msg := null; begin perform public.storage_usage_org(v_org); exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-06 · Membresía desactivada: sin consulta de espacio','ok',coalesce(v_msg like '%No tiene acceso%', false),'d',v_msg));
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    select count(*) into v_m from storage.objects where bucket_id = 'habilitation-documents' and name = v_cn;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-07 · Médico desactivado ya no lee su carpeta','ok',v_m = 0,'d',v_m::text));

    -- Membresía activa pero perfil desactivado
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
    update public.organization_users set is_active = true where organization_id = v_org;
    update public.profiles set is_active = false where id = v_sec;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    v_a := app.patient_access(v_org); v_b := app.payments_read_ok(v_org); v_c := app.payments_write_ok(v_prov);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-08 · Perfil desactivado: sin pacientes ni pagos','ok',coalesce(not v_a and not v_b and not v_c, false),'d',format('%s %s %s', v_a, v_b, v_c)));
    perform set_config('role', 'none', true); perform set_config('request.jwt.claims', '', true);
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
revoke execute on function app.qa_run_tests_cierre_accesos() from public, anon, authenticated;

delete from app.schema_migrations where version = '271';
insert into app.schema_migrations (version, report) values ('271', jsonb_build_object('tema', 'suite de la 270'));
