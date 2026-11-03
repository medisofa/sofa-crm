\set ON_ERROR_STOP on
begin;
select set_config('test.uid','50000000-0000-4000-8000-000000000001',false),set_config('test.role','billing',false),set_config('test.org','10000000-0000-4000-8000-000000000001',false);
set role authenticated;
do $$
declare v_org uuid := '10000000-0000-4000-8000-000000000001'; v_row jsonb := '{"medico":"20000000-0000-4000-8000-000000000001","ars":"30000000-0000-4000-8000-000000000001","servicio":"TEST-B","simon":"2467","cups":"","tarifa":"850.00","desde":"01/01/2028","hasta":""}';
v_proposal jsonb; v_auth jsonb; v_report jsonb; v_other jsonb;
begin
  assert app.tariff_resolve_code((v_row->>'ars')::uuid,(v_row->>'medico')::uuid,'CUPS','BETA-ONLY') is null, 'Other ARS code leaked';
  v_report := public.import_contract_tariffs_v2(jsonb_build_array(v_row),false,'test.csv');
  assert jsonb_array_length(v_report->'errors')=1, 'Global conflict was ignored';
  v_proposal := public.tariff_code_exception_prepare(v_org,v_row,array['SIMON'],'Contrato exclusivo de ARS Alpha');
  begin
    perform public.tariff_code_exception_authorize(v_org,v_row,array['SIMON'],'Contrato exclusivo de ARS Alpha','{}');
    raise exception 'stale proposal accepted';
  exception when serialization_failure then null; end;
  v_auth := public.tariff_code_exception_authorize(v_org,v_row,array['SIMON'],'Contrato exclusivo de ARS Alpha',v_proposal);
  assert app.tariff_resolve_code((v_row->>'ars')::uuid,(v_row->>'medico')::uuid,'SIMON','2467')='40000000-0000-4000-8000-000000000001'::uuid, 'Authorization applied too early';
  v_row := v_row || jsonb_build_object('code_authorization',v_auth->>'id');
  v_report := public.import_contract_tariffs_v2(jsonb_build_array(v_row),false,'test.csv');
  assert jsonb_array_length(v_report->'errors')=0, 'Authorized row not valid';
  -- Reject using a colleague's authorization, inactive users and scope changes.
  perform set_config('test.uid','50000000-0000-4000-8000-000000000002',true);
  begin perform public.import_contract_tariffs_v2(jsonb_build_array(v_row),false); raise exception 'foreign token accepted'; exception when insufficient_privilege then null;end;
  perform set_config('test.uid','50000000-0000-4000-8000-000000000001',true);
  begin perform public.import_contract_tariffs_v2(jsonb_build_array(v_row || '{"simon":"CHANGED"}'),false); raise exception 'edited token accepted'; exception when invalid_parameter_value then null;end;
  begin perform public.import_contract_tariffs_v2(jsonb_build_array(v_row || '{"ars":"30000000-0000-4000-8000-000000000002"}'),false); raise exception 'other ARS accepted token'; exception when insufficient_privilege then null;end;
  perform set_config('test.active','false',true);
  begin perform public.tariff_code_exception_prepare(v_org,v_row,array['SIMON'],'Contrato exclusivo de ARS Alpha'); raise exception 'inactive user accepted'; exception when insufficient_privilege then null;end;
  perform set_config('test.active','true',true);
  -- A failure during tariff saving must roll back the code mapping as well.
  perform set_config('test.fail_tariff','true',true);
  begin perform public.import_contract_tariffs_v2(jsonb_build_array(v_row),true,'test.csv'); raise exception 'expected tariff failure'; exception when others then if sqlerrm <> 'test tariff save failure' then raise;end if;end;
  assert app.tariff_resolve_code((v_row->>'ars')::uuid,(v_row->>'medico')::uuid,'SIMON','2467')='40000000-0000-4000-8000-000000000001'::uuid, 'Failed tariff left a code mapping';
  perform set_config('test.fail_tariff','false',true);
  v_report := public.import_contract_tariffs_v2(jsonb_build_array(v_row),true,'test.csv');
  assert (v_report->>'imported')::int=1, 'Tariff not saved';
  assert app.tariff_resolve_code((v_row->>'ars')::uuid,(v_row->>'medico')::uuid,'SIMON','2467')='40000000-0000-4000-8000-000000000002'::uuid, 'Scoped mapping missing';
  assert app.tariff_resolve_code('30000000-0000-4000-8000-000000000002',(v_row->>'medico')::uuid,'SIMON','2467')='40000000-0000-4000-8000-000000000001'::uuid, 'Global code changed for other ARS';
  perform set_config('test.role','client',true);
  begin perform public.tariff_code_exception_prepare(v_org,v_row,array['SIMON'],'Contrato exclusivo de ARS Alpha'); raise exception 'client authorized exception';exception when insufficient_privilege then null;end;
  perform set_config('test.role','billing',true);
  begin perform public.tariff_code_exception_prepare('10000000-0000-4000-8000-000000000002',v_row,array['SIMON'],'Contrato exclusivo de ARS Alpha');raise exception 'other client accepted';exception when insufficient_privilege then null;end;
  begin perform public.tariff_code_exception_prepare(v_org,v_row,array['SIMON'],'');raise exception 'empty reason accepted';exception when invalid_parameter_value then null;end;
  begin insert into app.tariff_code_authorizations(organization_id) values(v_org);raise exception 'direct approval write accepted';exception when insufficient_privilege then null;end;
  raise notice 'PASS: ARS isolation, explicit authorization, no early changes, validation, immutable token scope, permissions, atomic save and rollback';
end $$;
-- Applying only a code association must work even when the tariff amount is unchanged.
do $$
declare v_org uuid := '10000000-0000-4000-8000-000000000001';
 v_row jsonb := '{"medico":"20000000-0000-4000-8000-000000000001","ars":"30000000-0000-4000-8000-000000000002","servicio":"TEST-A","simon":"ONLY-BETA","cups":"CUPS-BETA","tarifa":"900","desde":"01/01/2029"}';
 v_proposal jsonb;v_auth jsonb;v_result jsonb;
begin
 v_proposal:=public.tariff_code_exception_prepare(v_org,v_row,array['SIMON','CUPS'],'Ambos códigos exclusivos de Beta');
 v_auth:=public.tariff_code_exception_authorize(v_org,v_row,array['SIMON','CUPS'],'Ambos códigos exclusivos de Beta',v_proposal);
 v_row:=v_row||jsonb_build_object('code_authorization',v_auth->>'id');
 v_result:=public.import_contract_tariffs_v2(jsonb_build_array(v_row),false);
 assert (v_result->>'same')::int=1 and jsonb_array_length(v_result->'errors')=0, 'Unchanged tariff was not validated';
 v_result:=public.import_contract_tariffs_v2(jsonb_build_array(v_row),true);
 assert (v_result->>'imported')::int=0, 'Unchanged tariff was written';
 assert app.tariff_resolve_code((v_row->>'ars')::uuid,(v_row->>'medico')::uuid,'CUPS','CUPS-BETA')='40000000-0000-4000-8000-000000000001'::uuid, 'CUPS exception not applied';
 assert app.tariff_resolve_code('30000000-0000-4000-8000-000000000001',(v_row->>'medico')::uuid,'CUPS','CUPS-BETA') is null, 'CUPS exception leaked to other ARS';
 raise notice 'PASS: SIMON/CUPS authorization and saving exceptions with unchanged tariffs';
end $$;
-- Two authorized proposals based on the same old mapping cannot overwrite one another.
do $$
declare v_org uuid := '10000000-0000-4000-8000-000000000001';
 a jsonb := '{"medico":"20000000-0000-4000-8000-000000000001","ars":"30000000-0000-4000-8000-000000000001","servicio":"TEST-A","simon":"RACE","tarifa":"800","desde":"01/01/2035"}';
 b jsonb;pa jsonb;pb jsonb;aa jsonb;ab jsonb;
begin
 b:=a||'{"servicio":"TEST-B"}';
 pa:=public.tariff_code_exception_prepare(v_org,a,array['SIMON'],'Primer contrato revisado por usuario');
 pb:=public.tariff_code_exception_prepare(v_org,b,array['SIMON'],'Otro contrato revisado por usuario');
 aa:=public.tariff_code_exception_authorize(v_org,a,array['SIMON'],'Primer contrato revisado por usuario',pa);
 ab:=public.tariff_code_exception_authorize(v_org,b,array['SIMON'],'Otro contrato revisado por usuario',pb);
 a:=a||jsonb_build_object('code_authorization',aa->>'id');b:=b||jsonb_build_object('code_authorization',ab->>'id');
 perform public.import_contract_tariffs_v2(jsonb_build_array(a),true);
 begin perform public.import_contract_tariffs_v2(jsonb_build_array(b),true);raise exception 'stale mapping overwrote newer mapping';exception when serialization_failure then null;end;
 assert app.tariff_resolve_code((a->>'ars')::uuid,(a->>'medico')::uuid,'SIMON','RACE')='40000000-0000-4000-8000-000000000001'::uuid,'Newer mapping lost';
 raise notice 'PASS: stale authorized proposal cannot overwrite a newer exclusive mapping';
end $$;
reset role;
do $$ begin
 assert exists(select 1 from app.tariff_code_authorizations where applied_at is not null), 'Authorization was not marked applied';
 assert exists(select 1 from audit_log where table_name='tariff_code_authorizations' and old_values is not null), 'Missing authorization audit';
end $$;
rollback;
