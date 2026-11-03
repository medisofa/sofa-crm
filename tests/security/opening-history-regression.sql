\set ON_ERROR_STOP on
begin;
select set_config('test.uid','50000000-0000-4000-8000-000000000001',false),set_config('test.org','10000000-0000-4000-8000-000000000001',false),set_config('test.role','admin',false);
set role authenticated;
do $$
declare org uuid:='10000000-0000-4000-8000-000000000001';prov uuid:='20000000-0000-4000-8000-000000000001';ars uuid:='30000000-0000-4000-8000-000000000001';
 rows jsonb:='[
 {"tipo":"resumen","radicacion":"RAD-OLD-1","fecha_radicacion":"01/08/2026","facturado":"2000","pagado":"1000","retencion":"0","glosa_aceptada":"100"},
 {"tipo":"reclamacion","radicacion":"RAD-OLD-1","reclamacion":"C-1","facturado":"1000","pagado":"500","glosa_aceptada":"50"},
 {"tipo":"reclamacion","radicacion":"RAD-OLD-1","reclamacion":"C-2","facturado":"1000","pagado":"500","glosa_aceptada":"50"},
 {"tipo":"pago","radicacion":"RAD-OLD-1","reclamacion":"C-1","pagado":"500","fecha_pago":"15/08/2026","referencia_pago":"PAY-1"},
 {"tipo":"pago","radicacion":"RAD-OLD-1","reclamacion":"C-2","pagado":"500","fecha_pago":"15/08/2026","referencia_pago":"PAY-1"},
 {"tipo":"resumen","radicacion":"RAD-OLD-2","fecha_radicacion":"01/07/2026","facturado":"1000","pagado":"900","retencion":"100"},
 {"tipo":"resumen","radicacion":"RAD-UNKNOWN","fecha_radicacion":"01/07/2026","facturado":"500"}]';
 rep jsonb;a jsonb;item uuid;unknown_item uuid;r jsonb;result jsonb;v_id uuid;
begin
 rep:=public.opening_history_preview(org,prov,ars,'2026-10-01','2026-10-02','PRE-123',rows);
 assert jsonb_array_length(rep->'errors')=0,rep::text;
 assert jsonb_array_length(public.opening_history_preview(org,prov,ars,'2026-10-01','2026-09-30','PRE-123',rows)->'errors')=0, 'Cutoff before service start was rejected';
 assert jsonb_array_length(rep->'groups')=3,'Summary and detail were counted as separate radicaciones';
 assert jsonb_array_length(public.opening_history_preview(org,prov,ars,'2026-10-01','2026-10-02','PRE-123','[{"tipo":"reclamacion","radicacion":"SIN-FOLIO","fecha_radicacion":"01/08/2026","fecha_servicio":"01/07/2026","nss":"NSS-X","autorizacion":"AUT-X","simon":"2467","facturado":"1000","pagado":"0"}]')->'errors')=0,'Composite reconciliation key was rejected';
 select x into r from jsonb_array_elements(rep->'groups') x where x->>'external_ref'='RAD-OLD-1';
 assert (r->>'billed')::numeric=2000 and (r->>'paid')::numeric=1000 and (r->>'balance')::numeric=900,'Payment counted twice or glosa accepted omitted';
 assert r->>'detail_level'='completo' and r->>'status'='pago_parcial','Incorrect partial status';
 select x into r from jsonb_array_elements(rep->'groups') x where x->>'external_ref'='RAD-OLD-2';
 assert r->>'status'='pagada_total' and r->>'detail_level'='resumen','Retention was treated as unpaid or detail invented';
 select x into r from jsonb_array_elements(rep->'groups') x where x->>'external_ref'='RAD-UNKNOWN';
 assert r->>'status'='sin_datos_pago' and r->>'balance' is null,'Unknown paid was assumed to be zero';
 begin perform public.opening_history_authorize(org,prov,ars,'2026-10-01','2026-10-02','PRE-123',rows,'outdated','Estado de cuenta y contrato revisados');raise exception 'stale preview accepted';exception when serialization_failure then null;end;
 a:=public.opening_history_authorize(org,prov,ars,'2026-10-01','2026-10-02','PRE-123',rows,rep->>'hash','Estado de cuenta y contrato revisados');
 assert (public.opening_history_board(org)->'summary'->>'radicaciones')::int=0,'Authorization applied financial data early';
 result:=public.opening_history_commit((a->>'id')::uuid);
 assert (result->>'imported')::int=3 and (result->>'fees_generated')::int=0,'Bad commit counts';
 assert (public.opening_history_commit((a->>'id')::uuid)->>'already_committed')::boolean,'Commit retry duplicated data';
 rep:=public.opening_history_board(org);
 assert (rep->'summary'->>'facturado')::numeric=3500,'Aggregate added on top of detail';
 assert (rep->'summary'->>'pagado_inicial')::numeric=1900,'Totals incorrect';
 select (x->>'id')::uuid into item from jsonb_array_elements(rep->'items') x where x->>'external_ref'='RAD-OLD-1';
 select (x->>'id')::uuid into unknown_item from jsonb_array_elements(rep->'items') x where x->>'external_ref'='RAD-UNKNOWN';
 begin perform public.opening_history_recovery_add(item,100,'REC-1','2026-10-10','Recibo bancario verificado');raise exception 'unreviewed recovery accepted';exception when check_violation then null;end;
 perform public.opening_history_review(item,'conforme','Estado de cuenta ARS y pagos cotejados',1);
 assert app.opening_history_has_reviewed(org),'Reviewed prior operations not recognized by onboarding';
 perform public.opening_history_recovery_add(item,900,'REC-1','2026-10-10','Recibo bancario verificado sin duplicidad');
 r:=public.opening_history_item(item);
 assert (r->'item'->>'recovered')::numeric=900,'Recovery missing';
 begin perform public.opening_history_recovery_add(item,900,'REC-1','2026-10-10','Recibo bancario verificado sin duplicidad');raise exception 'duplicate recovery accepted';exception when unique_violation then null;end;
 begin perform public.opening_history_recovery_add(item,100,'REC-OLD','2026-10-01','Pago ya comprendido en corte inicial');raise exception 'pre-cutoff recovery accepted';exception when invalid_parameter_value then null;end;
 begin perform public.opening_history_review(unknown_item,'conforme','Se intenta confirmar un saldo desconocido',1);raise exception 'unknown balance marked reviewed';exception when check_violation then null;end;
 perform public.opening_history_rectify(unknown_item,500,0,0,0,'ARS confirma que no hay pagos registrados al corte',1);
 begin perform public.opening_history_review(unknown_item,'conforme','Pantalla anterior a la rectificación',1);raise exception 'stale audit approved changed balance';exception when serialization_failure then null;end;
 perform public.opening_history_review(unknown_item,'conforme','Saldo cotejado con certificación de la ARS',2);
 rep:=public.opening_history_preview(org,prov,ars,'2026-10-01','2026-10-02','PRE-123',rows);
 assert jsonb_array_length(rep->'errors')>0,'Repeat import was not blocked';
 perform set_config('test.role','billing',true);
 begin perform public.opening_history_authorize(org,prov,ars,'2026-10-01','2026-10-02','PRE-123','[{"tipo":"codigo"}]','x','Estado de cuenta y contrato revisados');raise exception 'billing authorized financial baseline';exception when insufficient_privilege then null;end;
 perform set_config('test.role','operations',true);
 begin perform public.opening_history_board(org);raise exception 'operations saw private money';exception when insufficient_privilege then null;end;
 perform set_config('test.role','admin',true);
 perform set_config('test.org','10000000-0000-4000-8000-000000000002',true);
 begin perform public.opening_history_board(org);raise exception 'foreign client access';exception when insufficient_privilege then null;end;
 perform set_config('test.org',org::text,true);
 begin insert into app.opening_history_items(organization_id) values(org);raise exception 'direct API write allowed';exception when insufficient_privilege then null;end;
 raise notice 'PASS: mixed summary/detail, prior paid/partial/total/unknown, explicit authorization, idempotency, review, recoveries, rectification and role isolation';
end $$;
reset role;
do $$ begin
 assert (select count(*) from public.service_lines)=0,'Historical totals created fictional claims';
 assert (select count(*) from public.payments)=0,'Historical load created new operational payments';
 assert (select count(*) from public.sofa_fees)=0,'Historical load generated fees';
 assert exists(select 1 from public.provider_ars_codes where code='PRE-123' and status='codificado'),'Prior provider code not recognized';
 assert exists(select 1 from public.audit_log where table_name='opening_history_items' and old_values is not null),'Missing audit trail';
 assert app.golive_auto('10000000-0000-4000-8000-000000000001','carga_cuentas'),'Opening load did not satisfy initial accounts load';
end $$;
rollback;

-- Existing operational records are flagged, not copied; a normal payment cannot be re-registered.
begin;
select set_config('test.uid','50000000-0000-4000-8000-000000000001',false),set_config('test.org','10000000-0000-4000-8000-000000000001',false),set_config('test.role','admin',false);
insert into public.submissions values('60000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','RAD-NATIVE',null);
insert into public.payments(organization_id,ars_id,reference,paid_on,amount) values('10000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','NORMAL-EXISTING','2026-10-15',100);
set role authenticated;
do $$
declare org uuid:='10000000-0000-4000-8000-000000000001';prov uuid:='20000000-0000-4000-8000-000000000001';ars uuid:='30000000-0000-4000-8000-000000000001';
 rows jsonb:='[{"tipo":"resumen","radicacion":"RAD-NATIVE","fecha_radicacion":"01/08/2026","facturado":"1000","pagado":"0"},{"tipo":"resumen","radicacion":"RAD-OTHER","fecha_radicacion":"01/08/2026","facturado":"1000","pagado":"0"}]';
 rep jsonb;a jsonb;native uuid;other uuid;
begin
 rep:=public.opening_history_preview(org,prov,ars,'2026-10-01','2026-10-02','PRE-123',rows);
 assert jsonb_array_length(rep->'groups'->0->'native_candidates')=1,'Existing submission was not detected';
 a:=public.opening_history_authorize(org,prov,ars,'2026-10-01','2026-10-02','PRE-123',rows,rep->>'hash','Estado de cuenta previo autorizado para auditoría');
 perform public.opening_history_commit((a->>'id')::uuid);rep:=public.opening_history_board(org);
 select (x->>'id')::uuid into native from jsonb_array_elements(rep->'items') x where x->>'external_ref'='RAD-NATIVE';
 select (x->>'id')::uuid into other from jsonb_array_elements(rep->'items') x where x->>'external_ref'='RAD-OTHER';
 perform public.opening_history_review(native,'ya_en_sofa','Duplicidad confirmada con el expediente existente',1);
 assert (public.opening_history_board(org)->'summary'->>'facturado')::numeric=1000,'Known duplicate remained in baseline totals';
 perform public.opening_history_review(other,'conforme','Saldo revisado sin coincidencias con otros expedientes',1);
 begin perform public.opening_history_recovery_add(other,100,'NORMAL-EXISTING','2026-10-15','Transferencia ya registrada en Pagos de SOFA');raise exception 'normal payment was counted twice';exception when unique_violation then null;end;
 raise notice 'PASS: native duplicates flagged/excluded and existing operational payment not counted twice';
end $$;
reset role;
rollback;
