\set ON_ERROR_STOP on
begin;
do $$begin if has_function_privilege('anon','public.google_intake_drafts_v1(text,uuid,bigint,jsonb,uuid)','execute')then raise exception 'anonymous execute';end if;if has_table_privilege('authenticated','app.google_intake_drafts','select')or has_table_privilege('authenticated','app.google_intake_drafts','insert')then raise exception 'direct access';end if;end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $$declare u uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';b uuid:='cccccccc-cccc-4ccc-8ccc-cccccccccccc';p jsonb:='{"schema":1,"source_name":"prueba.csv","scope_ids":["11111111-1111-4111-8111-111111111111"],"rows":[{"raw":{"__row":2,"Paciente *":"Prueba"},"status":"excluded"}],"editor":{"row":2,"values":{"patient":"Texto sin confirmar"}}}';r jsonb;begin
 r:=public.google_intake_drafts_v1('save',b,0,p,u);if(r->>'version')::int<>1 then raise exception 'initial save';end if;
 r:=public.google_intake_drafts_v1('save',b,0,p,u);if(r->>'version')::int<>1 then raise exception 'retry duplicated';end if;
 r:=public.google_intake_drafts_v1('get',b,null,'{}',u);if r#>>'{draft,payload,editor,values,patient}'<>'Texto sin confirmar' then raise exception 'editor lost';end if;
 begin perform public.google_intake_drafts_v1('save',b,0,p||'{"source_name":"otro.csv"}',u);raise exception 'stale overwrite';exception when serialization_failure then null;end;
 begin perform public.google_intake_drafts_v1('save',gen_random_uuid(),0,p||'{"scope_ids":["22222222-2222-4222-8222-222222222222"]}',u);raise exception 'other org';exception when insufficient_privilege then null;end;
 begin perform public.google_intake_drafts_v1('get',b,null,'{}','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');raise exception 'wrong session accepted';exception when insufficient_privilege then null;end;
 perform set_config('test.revoked','on',true);begin perform public.google_intake_drafts_v1('get',b,null,'{}',u);raise exception 'revoked scope read';exception when insufficient_privilege then null;end;perform set_config('test.revoked','off',true);
 r:=public.google_intake_drafts_v1('legacy_get','dddddddd-dddd-4ddd-8ddd-dddddddddddd',null,'{}',u);if jsonb_array_length(r->'events')<>1 then raise exception 'legacy missing';end if;
 r:=public.google_intake_drafts_v1('archive',b,1,'{}',u);if not(r->>'archived')::boolean then raise exception 'archive';end if;
 begin perform public.google_intake_drafts_v1('save',b,1,p,u);raise exception 'archived restored';exception when serialization_failure then null;end;
end$$;
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
do $$declare u uuid:='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';begin
 if jsonb_array_length(public.google_intake_drafts_v1('list',null,null,'{}',u)->'items')<>0 then raise exception 'other owner list';end if;
 if jsonb_array_length(public.google_intake_drafts_v1('legacy_get','dddddddd-dddd-4ddd-8ddd-dddddddddddd',null,'{}',u)->'events')<>0 then raise exception 'other owner history';end if;
 begin perform public.google_intake_drafts_v1('get','cccccccc-cccc-4ccc-8ccc-cccccccccccc',null,'{}',u);raise exception 'other owner read';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin if(select count(*)from app.google_intake_draft_events)<>2 then raise exception 'audit not idempotent';end if;end$$;
rollback;
