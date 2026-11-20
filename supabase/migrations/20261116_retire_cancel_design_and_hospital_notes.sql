-- SOFA · Base de datos: retiro del diseño anterior de duplicados y de la bitácora de hospitalización duplicada.
-- Ya aplicado en producción con mcp__Supabase__apply_migration (2026-11-16), en dos partes:
--   1) ars_contacts_suite_without_notes: la suite de contactos de ARS de este archivo.
--   2) retire_cancel_design_and_hospital_notes: los retiros y la compuerta final.
-- Comprobado después: duplicados 15 de 15, contactos de ARS 27 de 27, sin datos de prueba.
--
-- 1) Duplicados: retira cancel_duplicate_line, v_canceled_duplicates, la suite vieja y el estado
--    'anulada_duplicado'. Los reemplaza public.execute_claim_duplicate_exclusion (5.41.0).
-- 2) Hospitalización: retira hospital_report_notes y hospital_note_*. Duplicaban hospital_report_log
--    (5.35.1), que es la bitácora con pantalla. La tabla estaba vacía; la migración se detiene si no lo está.
-- 3) La suite de contactos de ARS pasa a llamarse app.qa_run_tests_contactos_ars() y ya no prueba notas.
-- La transacción solo se confirma si las dos suites pasan completas; ninguna deja datos.

drop view if exists public.v_canceled_duplicates;
drop function if exists public.cancel_duplicate_line(uuid, uuid);
drop function if exists app.qa_run_tests_anulacion_blindaje();
do $$
begin
  if exists (select 1 from public.service_lines where claim_status = 'anulada_duplicado') then
    raise exception 'Hay reclamaciones en estado anulada_duplicado. Revíselas antes de retirar el estado.';
  end if;
  delete from public.claim_statuses where code = 'anulada_duplicado';
end $$;

do $$
declare f regprocedure;
begin
  if to_regclass('public.hospital_report_notes') is not null then
    if exists (select 1 from public.hospital_report_notes) then
      raise exception 'hospital_report_notes tiene notas. Páselas a hospital_report_log antes de retirar la tabla.';
    end if;
  end if;
  for f in select p.oid::regprocedure from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
            where (n.nspname = 'public' and p.proname in ('hospital_note_list','hospital_note_add','hospital_note_edit','hospital_note_delete'))
               or (n.nspname = 'app' and p.proname = 'hospital_note_access') loop
    execute 'drop function ' || f;
  end loop;
end $$;
drop table if exists public.hospital_report_notes;
drop function if exists app.qa_run_tests_notas_ars();

create or replace function app.qa_run_tests_contactos_ars()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path to 'public, app, extensions, pg_catalog'
as $suite$
declare
  v_res jsonb := '[]'::jsonb;
  v_op  uuid := '00000000-0000-4000-8000-000000000001';
  c1 uuid; hc uuid; p1 uuid; p2 uuid; ars_a uuid; ars_b uuid; r_env uuid; r_bor uuid;
  u_adm uuid := gen_random_uuid(); u_bil uuid := gen_random_uuid(); u_glo uuid := gen_random_uuid();
  u_aud uuid := gen_random_uuid(); u_med uuid := gen_random_uuid(); u_med2 uuid := gen_random_uuid();
  v_msg text; v_j jsonb; v_n int; v_id uuid; v_id2 uuid; v_cont uuid; v_log uuid;
  v_ok_prev boolean;
begin
  if to_regclass('public.ars_contacts') is null or to_regclass('public.ars_contact_log') is null then
    raise exception 'Faltan las tablas de contactos de ARS. Aplica la migración de contactos de ARS y vuelve a correr las pruebas.';
  end if;

  begin
    -- ===== Datos de la prueba (todos se deshacen al final) =====
    insert into auth.users(id, email) select u, u::text||'@qa228.test' from unnest(array[u_adm,u_bil,u_glo,u_aud,u_med,u_med2]) u;
    insert into public.profiles(id, full_name) values
      (u_adm,'QA Admin'),(u_bil,'QA Facturación'),(u_glo,'QA Cobros'),
      (u_aud,'QA Auditor'),(u_med,'QA Médico'),(u_med2,'QA Médico Dos')
    on conflict (id) do update set full_name = excluded.full_name;
    insert into public.organizations(kind, operator_id, legal_name, tax_id, org_type)
      values ('client', v_op, 'Clínica QA 228', '910000228', 'Clínica') returning id into c1;
    insert into public.organization_users(organization_id,user_id,role_code) values
      (v_op,u_adm,'admin'),(v_op,u_bil,'billing'),(v_op,u_glo,'glosas'),(v_op,u_aud,'auditor'),
      (c1,u_med,'client'),(c1,u_med2,'client');
    insert into public.staff_client_access(user_id, client_org_id) values (u_bil,c1),(u_aud,c1);   -- u_glo NO tiene acceso al cliente
    insert into public.health_centers(organization_id,name) values (c1,'Centro QA 228') returning id into hc;
    insert into public.providers(organization_id,full_name,tax_id,user_id) values (c1,'Dr. QA Uno','800000228',u_med) returning id into p1;
    insert into public.providers(organization_id,full_name,tax_id,user_id) values (c1,'Dra. QA Dos','800000229',u_med2) returning id into p2;
    insert into public.provider_centers(provider_id,center_id) values (p1,hc),(p2,hc);
    insert into public.ars(code,name) values ('qa_ars_228a','QA ARS 228 A') returning id into ars_a;
    insert into public.ars(code,name) values ('qa_ars_228b','QA ARS 228 B') returning id into ars_b;
    insert into public.hospital_reports(provider_id,center_id,patient_name,ars_id,status) values (p1,hc,'Paciente QA Enviado',ars_a,'enviado') returning id into r_env;
    insert into public.hospital_reports(provider_id,center_id,patient_name,ars_id,status) values (p1,hc,'Paciente QA Borrador',ars_a,'borrador') returning id into r_bor;

    -- ===== CONTACTOS DE ARS (solo personal de SOFA) =====
    perform set_config('request.jwt.claims', json_build_object('sub',u_adm,'role','authenticated','aal','aal2')::text, true);
    -- AC-01 el Administrador guarda un contacto
    v_j := public.ars_contact_save(ars_a, 'glosas', 'María Pérez', 'Analista de glosas', '809-555-0101', 'maria.perez@arsqa.test', 'Responde en la mañana.');
    v_cont := (v_j->>'id')::uuid;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-01 · El Administrador registra un contacto de ARS','ok', v_cont is not null,'d', null));
    -- AC-02 sin teléfono ni correo
    begin perform public.ars_contact_save(ars_a, 'pagos', 'Sin medio', null, null, null, null); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-02 · Un contacto sin teléfono ni correo se rechaza','ok', position('al menos un teléfono o un correo' in coalesce(v_msg,'')) > 0,'d', v_msg));
    -- AC-03 correo inválido
    begin perform public.ars_contact_save(ars_a, 'pagos', 'Correo malo', null, null, 'esto-no-es-correo', null); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-03 · Un correo mal escrito se rechaza diciendo qué revisar','ok', position('formato válido' in coalesce(v_msg,'')) > 0,'d', v_msg));
    -- AC-04 edición del mismo contacto
    perform public.ars_contact_save(ars_a, 'glosas', 'María Pérez', 'Supervisora de glosas', '809-555-0101', 'maria.perez@arsqa.test', null, v_cont);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-04 · Editar un contacto no crea otro','ok',
      (select count(*) from public.ars_contacts where ars_id=ars_a)=1 and exists(select 1 from public.ars_contacts where id=v_cont and job_title='Supervisora de glosas'),'d', null));

    -- AC-05 el Médico no ve nada de ARS
    perform set_config('request.jwt.claims', json_build_object('sub',u_med,'role','authenticated','aal','aal2')::text, true);
    begin perform public.ars_contact_list(null,true); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-05 · ATAQUE: el Médico no ve los contactos de ARS','ok', position('solo para el personal de SOFA' in coalesce(v_msg,'')) > 0,'d', v_msg));
    begin perform public.ars_contact_log_list(null,null,null,10); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-06 · ATAQUE: el Médico no ve la bitácora de contactos','ok', position('solo para el personal de SOFA' in coalesce(v_msg,'')) > 0,'d', v_msg));
    begin perform public.ars_contact_log_add(ars_a,'llamada','saliente','intento','intento del médico'); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-07 · ATAQUE: el Médico no escribe en la bitácora de contactos','ok', position('solo para el personal de SOFA' in coalesce(v_msg,'')) > 0,'d', v_msg));

    -- AC-08 el Auditor lee pero no escribe
    perform set_config('request.jwt.claims', json_build_object('sub',u_aud,'role','authenticated','aal','aal2')::text, true);
    v_j := public.ars_contact_list(ars_a,true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-08 · El Auditor lee los contactos y no puede escribir','ok', jsonb_array_length(v_j->'contactos')=1 and not (v_j->>'puede_escribir')::boolean,'d', null));
    begin perform public.ars_contact_save(ars_a,'otro','Auditor','x','809-555-0000',null,null); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-09 · ATAQUE: el Auditor no crea contactos','ok', position('solo puede leer' in coalesce(v_msg,'')) > 0,'d', v_msg));

    -- AC-10 Facturación registra un contacto con seguimiento → queda abierto, enlazado a la hospitalización
    perform set_config('request.jwt.claims', json_build_object('sub',u_bil,'role','authenticated','aal','aal2')::text, true);
    v_j := public.ars_contact_log_add(ars_a,'llamada','saliente','Autorización de internamiento','Se habló con María; pidió reenviar el informe.','en_espera',v_cont,r_env,'AUT-QA-1','Reenviar informe y confirmar recepción',current_date+2);
    v_log := (v_j->>'id')::uuid;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-10 · Con fecha de seguimiento la entrada queda abierta y enlazada al caso','ok',
      exists(select 1 from public.ars_contact_log where id=v_log and status='abierto' and hospital_report_id=r_env and author_role='billing' and author_name='QA Facturación'),'d', null));
    -- AC-11 sin fecha de seguimiento queda cerrada
    v_j := public.ars_contact_log_add(ars_a,'correo','entrante','Constancia de pago','La ARS confirmó el pago.','resuelto');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-11 · Sin fecha de seguimiento la entrada nace cerrada','ok',
      exists(select 1 from public.ars_contact_log where id=(v_j->>'id')::uuid and status='cerrado'),'d', null));
    -- AC-12 contacto de otra ARS
    begin perform public.ars_contact_log_add(ars_b,'llamada','saliente','Cruce','contacto equivocado','informativo',v_cont); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-12 · No se puede usar un contacto de otra ARS','ok', position('no pertenece a esa ARS' in coalesce(v_msg,'')) > 0,'d', v_msg));
    -- AC-13 fecha de seguimiento ya pasada
    begin perform public.ars_contact_log_add(ars_a,'llamada','saliente','Fecha vieja','seguimiento en el pasado','informativo',null,null,null,'x',current_date-10); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-13 · Un seguimiento con fecha pasada se rechaza','ok', position('ya pasó' in coalesce(v_msg,'')) > 0,'d', v_msg));
    -- AC-14 enlazar una hospitalización sin acceso (Cobros sin acceso al cliente)
    perform set_config('request.jwt.claims', json_build_object('sub',u_glo,'role','authenticated','aal','aal2')::text, true);
    begin perform public.ars_contact_log_add(ars_a,'llamada','saliente','Sin acceso','intenta enlazar un caso ajeno','informativo',null,r_env); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-14 · ATAQUE: no se enlaza una hospitalización de un cliente al que no tienes acceso','ok', position('No tienes acceso a la hospitalización' in coalesce(v_msg,'')) > 0,'d', v_msg));
    -- AC-15 pero Cobros sí puede registrar contactos que no enlazan casos
    v_j := public.ars_contact_log_add(ars_a,'whatsapp','saliente','Consulta general','Pregunta sobre plazos.','informativo');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-15 · Cobros registra contactos sin enlazar casos','ok', v_j->>'id' is not null,'d', null));

    -- AC-16 resumen por ARS: abiertos y vencidos
    update public.ars_contact_log set next_action_date = current_date - 3 where id = v_log;   -- el tiempo pasó
    perform set_config('request.jwt.claims', json_build_object('sub',u_adm,'role','authenticated','aal','aal2')::text, true);
    v_j := public.ars_contacts_overview();
    select e into v_j from jsonb_array_elements(v_j->'ars') e where e->>'ars_id' = ars_a::text;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-16 · El resumen cuenta contactos, abiertos y vencidos','ok',
      (v_j->>'contactos')::int=1 and (v_j->>'seguimientos_abiertos')::int=1 and (v_j->>'seguimientos_vencidos')::int=1,'d', v_j::text));
    v_j := public.ars_contact_log_list(ars_a, null, 'abierto', 50);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-17 · La lista marca como vencida la entrada atrasada','ok',
      jsonb_array_length(v_j->'entradas')=1 and (v_j->'entradas'->0->>'vencida')::boolean,'d', null));
    v_j := public.ars_contact_log_list(null, r_env, null, 50);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-18 · Se puede ver la bitácora de ARS de una hospitalización','ok', jsonb_array_length(v_j->'entradas')=1,'d', null));

    -- AC-19 cerrar un seguimiento y no poder cerrarlo dos veces
    perform public.ars_contact_log_close(v_log, 'Confirmaron recepción.');
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-19 · Cerrar un seguimiento anota el cierre y quién lo cerró','ok',
      exists(select 1 from public.ars_contact_log where id=v_log and status='cerrado' and closed_by=u_adm and summary like '%[Cierre] Confirmaron recepción.%'),'d', null));
    begin perform public.ars_contact_log_close(v_log, null); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-20 · Cerrar dos veces el mismo seguimiento se rechaza','ok', position('ya estaba cerrado' in coalesce(v_msg,'')) > 0,'d', v_msg));

    -- AC-21 solo Administrador borra entradas
    perform set_config('request.jwt.claims', json_build_object('sub',u_bil,'role','authenticated','aal','aal2')::text, true);
    begin perform public.ars_contact_log_delete(v_log); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-21 · Facturación no puede borrar entradas de la bitácora','ok', position('solo del Administrador' in coalesce(v_msg,'')) > 0,'d', v_msg));
    perform set_config('request.jwt.claims', json_build_object('sub',u_adm,'role','authenticated','aal','aal2')::text, true);
    perform public.ars_contact_log_delete(v_log);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-22 · El Administrador borra y queda el rastro en la auditoría','ok',
      not exists(select 1 from public.ars_contact_log where id=v_log)
      and exists(select 1 from public.audit_log where table_name='ars_contact_log' and record_id=v_log::text and operation='DELETE'),'d', null));

    -- AC-23 desactivar un contacto lo saca de la lista activa pero no se pierde
    perform public.ars_contact_set_active(v_cont, false);
    v_j := public.ars_contact_list(ars_a, true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-23 · Un contacto desactivado sale de la lista activa','ok', jsonb_array_length(v_j->'contactos')=0,'d', null));
    v_j := public.ars_contact_list(ars_a, false);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-24 · Pero sigue disponible si se piden los inactivos','ok', jsonb_array_length(v_j->'contactos')=1,'d', null));

    -- AC-25/26 cierre de puertas
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-25 · ATAQUE: las tablas de contactos no se leen ni escriben directo desde la API','ok',
      not has_table_privilege('authenticated','public.ars_contacts','select') and not has_table_privilege('authenticated','public.ars_contact_log','select')
      and not has_table_privilege('authenticated','public.ars_contacts','insert') and not has_table_privilege('authenticated','public.ars_contact_log','update')
      and not has_table_privilege('anon','public.ars_contacts','select') and not has_table_privilege('anon','public.ars_contact_log','select'),'d', null));
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-26 · ATAQUE: un usuario anónimo no puede llamar las funciones de contactos','ok',
      not has_function_privilege('anon','public.ars_contact_list(uuid,boolean)','execute') and not has_function_privilege('anon','public.ars_contacts_overview()','execute')
      and not has_function_privilege('authenticated','app.ars_staff_require(text)','execute'),'d', null));

    -- AC-27 sin doble factor, el personal no entra (la producción lo exige)
    perform set_config('request.jwt.claims', json_build_object('sub',u_adm,'role','authenticated','aal','aal1')::text, true);
    begin perform public.ars_contact_list(null,true); v_msg := null; exception when others then v_msg := sqlerrm; end;
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','AC-27 · ATAQUE: el personal sin doble factor no abre los contactos','ok', position('solo para el personal de SOFA' in coalesce(v_msg,'')) > 0,'d', v_msg));

    -- Se deshace todo lo de la prueba
    raise exception using errcode = 'P0777', message = 'qa_rollback';
  exception when sqlstate 'P0777' then
    null;
  end;
  perform set_config('request.jwt.claims', '', true);

  return query
    with t as (select e, ord from jsonb_array_elements(v_res) with ordinality x(e, ord))
    select ord::int, case when coalesce((e->>'ok')::boolean, false) then 'OK' else 'FALLÓ' end, e->>'p', e->>'d' from t
    union all
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from t
    order by 1;
end $suite$;

revoke all on function app.qa_run_tests_contactos_ars() from public, anon, authenticated;

-- Compuerta: si alguna prueba falla, la migración entera se deshace.
do $$
declare v_mal text;
begin
  select string_agg(x, E'\n') into v_mal from (
    select 'duplicados · '||prueba||coalesce(' ['||nullif(detalle,'')||']','') x from app.qa_run_tests_exclusion_duplicados() where resultado <> 'APROBADA'
    union all
    select 'contactos · '||prueba||coalesce(' ['||detalle||']','') from app.qa_run_tests_contactos_ars() where resultado not in ('OK','TODO OK')
  ) q;
  if v_mal is not null then
    raise exception E'Las suites no pasaron; no se aplicó nada:\n%', v_mal;
  end if;
end $$;
