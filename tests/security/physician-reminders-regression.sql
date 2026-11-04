\set ON_ERROR_STOP on
begin;
do $$begin
 if has_function_privilege('anon','public.physician_reminders_v1(uuid,text,jsonb)','execute') then raise exception 'anonymous execute';end if;
 if has_table_privilege('authenticated','app.physician_reminders','select') or has_table_privilege('authenticated','app.physician_reminders','insert') then raise exception 'direct table access';end if;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $$begin
 if (public.physician_reminders_v1('11111111-1111-4111-8111-111111111111')->>'enabled')::boolean then raise exception 'flag default enabled';end if;
end$$;
reset role;
update app.physician_reminder_settings set enabled=true;
set local role authenticated;
do $$declare r jsonb; v jsonb:='{"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","version":0,"kind":"payment","title":"Pago de servicio","body":"Prueba","due_date":"2026-12-01","amount":1200,"completed":false}'; begin
 r:=public.physician_reminders_v1('11111111-1111-4111-8111-111111111111','save',v);
 if (r#>>'{item,version}')::integer<>1 then raise exception 'create';end if;
 r:=public.physician_reminders_v1('11111111-1111-4111-8111-111111111111','save',v);
 if (r#>>'{item,version}')::integer<>1 then raise exception 'retry';end if;
 begin perform public.physician_reminders_v1('11111111-1111-4111-8111-111111111111','save',v||'{"title":"Otra edición"}');raise exception 'stale accepted';exception when serialization_failure then null;end;
 begin perform public.physician_reminders_v1('22222222-2222-4222-8222-222222222222');raise exception 'other org accepted';exception when insufficient_privilege then null;end;
 begin perform public.physician_reminders_v1('11111111-1111-4111-8111-111111111111','save',v||'{"amount":-1}');raise exception 'negative accepted';exception when invalid_parameter_value then null;end;
 r:=public.physician_reminders_v1('11111111-1111-4111-8111-111111111111','save',v||'{"version":1,"completed":true}');
 if (r#>>'{item,version}')::integer<>2 then raise exception 'complete';end if;
 r:=public.physician_reminders_v1('11111111-1111-4111-8111-111111111111','save',v||'{"version":2}');
 if (r#>>'{item,version}')::integer<>3 then raise exception 'reopen';end if;
end$$;
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
do $$begin
 if jsonb_array_length(public.physician_reminders_v1('11111111-1111-4111-8111-111111111111')->'items')<>0 then raise exception 'other doctor read';end if;
 begin perform public.physician_reminders_v1('11111111-1111-4111-8111-111111111111','save','{"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","version":3,"kind":"note","title":"Intruso"}');raise exception 'other doctor write';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);
do $$begin begin perform public.physician_reminders_v1('11111111-1111-4111-8111-111111111111');raise exception 'billing accepted';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','',true);
do $$begin begin perform public.physician_reminders_v1('11111111-1111-4111-8111-111111111111');raise exception 'null uid accepted';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin
 if (select count(*) from app.physician_reminder_events)<>3 then raise exception 'audit retry not idempotent';end if;
 if exists(select 1 from app.physician_reminder_events where to_jsonb(physician_reminder_events)?'body') then raise exception 'body in audit';end if;
end$$;
rollback;
