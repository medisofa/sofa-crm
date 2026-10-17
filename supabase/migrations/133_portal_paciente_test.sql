-- 133 · Suite de la 132 (portal del paciente). Se deshace sola.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_portal_paciente();
create or replace function app.qa_run_tests_portal_paciente()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb; v_x jsonb; v_n int; v_ok boolean;
  v_org constant uuid := 'b7000000-0000-4000-8000-0000000003d1'; v_org2 constant uuid := 'b7000000-0000-4000-8000-0000000003d2';
  v_prov constant uuid := 'c7000000-0000-4000-8000-0000000003d1'; v_prov2 constant uuid := 'c7000000-0000-4000-8000-0000000003d2';
  v_med constant text := 'a7000000-0000-4000-8000-0000000003d1'; v_sec constant text := 'a7000000-0000-4000-8000-0000000003d2';
  v_otro constant text := 'a7000000-0000-4000-8000-0000000003d3';
  v_pat uuid; v_pat2 uuid; v_proc uuid; v_tok text; v_tok2 text;
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into auth.users (id, email, encrypted_password) values (v_med::uuid,'qa.pp.med@sofa.test','x'),(v_sec::uuid,'qa.pp.sec@sofa.test','x'),(v_otro::uuid,'qa.pp.otro@sofa.test','x');
    insert into public.profiles (id, full_name) select id, replace(email,'@sofa.test','') from auth.users where email like 'qa.pp.%@sofa.test' on conflict (id) do nothing;
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA PP Consultorio', '00000000761', 'Médico independiente', 'activo', current_date - 90, '8095550761');
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp)
    values (v_org2, 'client', '00000000-0000-4000-8000-000000000001'::uuid, 'QA PP Otro', '00000000762', 'Médico independiente', 'activo', current_date - 90, '8095550762');
    insert into public.providers (id, organization_id, full_name, specialty) values (v_prov, v_org, 'Dra. Portal', 'Medicina Interna'), (v_prov2, v_org2, 'Dr. Otro', 'Pediatría');
    insert into public.organization_users (organization_id, user_id, role_code) values (v_org, v_med::uuid, 'client'), (v_org, v_sec::uuid, 'capturer'), (v_org2, v_otro::uuid, 'client');
    insert into public.clinical_settings (organization_id, mode) values (v_org, 'prueba');
    insert into public.patients (organization_id, full_name, doc_number, phone) values (v_org, 'Rosa Ficticia Portal', '402-0000076-1', '8095550761') returning id into v_pat;
    insert into public.patients (organization_id, full_name, doc_number) values (v_org2, 'Paciente Otro Portal', '40200000762') returning id into v_pat2;
    select id into v_proc from public.procedures where is_active order by internal_code limit 1;
    insert into public.appointments (organization_id, provider_id, appointment_date, appointment_time, patient_name, payer_type, status, patient_id)
    values (v_org, v_prov, current_date + 3, '10:30', 'Rosa Ficticia Portal', 'privado', 'programada', v_pat),
           (v_org, v_prov, current_date + 5, '11:00', 'Rosa Ficticia Portal', 'privado', 'cancelada', v_pat),
           (v_org, v_prov, current_date - 5, '09:00', 'Rosa Ficticia Portal', 'privado', 'atendida', v_pat);
    insert into public.private_charges (organization_id, provider_id, charge_date, patient_name, patient_doc, procedure_id, service_name, quantity, unit_amount, payment_method, status)
    values (v_org, v_prov, current_date - 5, 'Rosa Ficticia Portal', '40200000761', v_proc, 'Consulta', 1, 1800, 'pendiente', 'pendiente');
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    perform public.create_clinical_order(v_pat, 'receta', jsonb_build_object('items', jsonb_build_array(jsonb_build_object('medicamento', 'Amoxicilina 500 mg', 'dosis', '1 cápsula', 'frecuencia', 'cada 8 horas', 'duracion', '7 días')), 'indicaciones', 'Con comida'), null);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
    begin
      perform public.portal_link_create(v_pat);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-01 · Otro consultorio no crea enlaces de mis pacientes','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-01 · Otro consultorio no crea enlaces de mis pacientes','ok',sqlerrm like 'Sin acceso a este paciente%','d',left(sqlerrm,120)));
    end;
    begin
      perform public.portal_link_create(v_pat2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-02 · Sin historia clínica activada el portal no se habilita','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-02 · Sin historia clínica activada el portal no se habilita','ok',sqlerrm like 'El portal del paciente se habilita junto con la historia clínica%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sec, 'role', 'authenticated')::text, true);
    begin
      perform public.portal_link_create(v_pat, 120);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-03 · El enlace dura de 1 a 90 días','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-03 · El enlace dura de 1 a 90 días','ok',sqlerrm like 'El enlace puede durar de 1 a 90 días%','d',left(sqlerrm,120)));
    end;
    -- 170 (SEG-03): solo el médico deja las órdenes visibles en el portal; por eso este enlace lo crea el médico
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.portal_link_create(v_pat, 30, true);
    v_tok := v_x->>'token';
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-04 · El médico crea el enlace (clave al azar, modo prueba avisado)','ok',coalesce((length(v_tok) >= 30 and (v_x->>'test_mode')::boolean and v_x->>'phone' = '8095550761'), false),'d',(length(v_tok))::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-05 · En la base solo queda la huella, nunca la clave','ok',coalesce((not exists (select 1 from public.patient_portal_links where token_hash = v_tok) and exists (select 1 from public.patient_portal_links where token_hash = app.sha256(v_tok))), false),'d',(null)::text));
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    v_x := public.portal_view(v_tok);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-06 · El paciente ve su nombre y el documento enmascarado','ok',coalesce((v_x->'patient'->>'first_name' = 'Rosa' and v_x->'patient'->>'doc' = '•••••••0761' and (v_x->>'test_mode')::boolean), false),'d',(v_x->>'patient')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-07 · Ve solo sus próximas citas vigentes','ok',coalesce((jsonb_array_length(v_x->'appointments') = 1 and v_x->'appointments'->0->>'time' = '10:30'), false),'d',(v_x->>'appointments')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-08 · Ve su receta','ok',coalesce((jsonb_array_length(v_x->'orders') = 1 and v_x->'orders'->0->'content'->'items'->0->>'medicamento' = 'Amoxicilina 500 mg'), false),'d',(v_x->>'orders')::text));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-09 · Ve su saldo pendiente en el consultorio','ok',coalesce(((v_x->'balance'->>'total')::numeric = 1800), false),'d',(v_x->>'balance')::text));
    begin
      perform public.portal_view('abc');
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-10 · Enlace mal copiado: dice qué hacer','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-10 · Enlace mal copiado: dice qué hacer','ok',sqlerrm like 'Enlace no válido%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_x := public.portal_link_status(v_pat);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-11 · El consultorio ve cuántas veces se abrió','ok',coalesce(((v_x->>'views')::int = 1 and (v_x->>'active')::boolean), false),'d',(v_x::text)::text));
    v_tok2 := public.portal_link_create(v_pat, 7, false)->>'token';
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    begin
      perform public.portal_view(v_tok);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-12 · Un enlace nuevo anula el anterior','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-12 · Un enlace nuevo anula el anterior','ok',sqlerrm like 'Este enlace venció o fue anulado%','d',left(sqlerrm,120)));
    end;
    v_x := public.portal_view(v_tok2);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-13 · Sin permiso de recetas no las muestra','ok',coalesce((v_x->'orders' = 'null'::jsonb), false),'d',(v_x->>'orders')::text));
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    update public.patient_portal_links set expires_at = now() - interval '1 minute' where patient_id = v_pat and revoked_at is null;
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    begin
      perform public.portal_view(v_tok2);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-14 · Enlace vencido: pide uno nuevo','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-14 · Enlace vencido: pide uno nuevo','ok',sqlerrm like 'Este enlace venció o fue anulado%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_med, 'role', 'authenticated')::text, true);
    v_tok := public.portal_link_create(v_pat)->>'token';
    perform public.portal_link_revoke(v_pat);
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    begin
      perform public.portal_view(v_tok);
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-15 · El consultorio anula el enlace cuando quiera','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-15 · El consultorio anula el enlace cuando quiera','ok',sqlerrm like 'Este enlace venció o fue anulado%','d',left(sqlerrm,120)));
    end;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','PO-16 · Sin sesión solo se puede VER con el enlace (no crear ni leer la tabla)','ok',coalesce((has_function_privilege('anon', 'public.portal_view(text)', 'execute') and not has_function_privilege('anon', 'public.portal_link_create(uuid,integer,boolean)', 'execute') and not has_table_privilege('authenticated', 'public.patient_portal_links', 'select')), false),'d',(null)::text));

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
