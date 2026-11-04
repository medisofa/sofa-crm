do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated;end if;end$$;
create schema app;create schema auth;
create function auth.uid()returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table public.profiles(id uuid primary key);
create table public.audit_log(id bigint generated always as identity primary key,occurred_at timestamptz default now(),user_id uuid,organization_id uuid,table_name text,record_id text,operation text,old_values jsonb,new_values jsonb);
create table public.service_lines(id uuid primary key);
create table app.google_intake_commits(record_id text primary key,created_by uuid,organization_id uuid,claim_id uuid,result jsonb,removed boolean default false);
create function app.is_staff(p_roles text[])returns boolean language sql stable as $$select auth.uid() is not null and coalesce(current_setting('test.role',true),'billing')=any(p_roles)$$;
create function app.visible_org_ids()returns setof uuid language sql stable as $$select case when current_setting('test.revoked',true)='on' then '99999999-9999-4999-8999-999999999999'::uuid else '11111111-1111-4111-8111-111111111111'::uuid end$$;
grant usage on schema public,app,auth to authenticated,anon;
insert into public.profiles values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
insert into public.audit_log(user_id,organization_id,table_name,record_id,operation,old_values,new_values)values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','google_claim_intake','dddddddd-dddd-4ddd-8ddd-dddddddddddd:row:2','CORRECCION_CARGA_EXTERNA','{"fields":["Paciente *"],"values":{"Paciente *":"Original"}}','{"fields":["Paciente *"],"values":{"Paciente *":"Corregido"}}');
