-- LOCAL TEST DATABASE ONLY. Minimal contracts for the production import functions.
create role anon nologin; create role authenticated nologin;
create schema app; create schema auth;
grant usage on schema app,auth to authenticated;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function app.is_active_user() returns boolean language sql stable as $$ select auth.uid() is not null and coalesce(current_setting('test.active',true),'true') = 'true' $$;
create function app.is_staff(text[] default null) returns boolean language sql stable as $$ select app.is_active_user() and coalesce(current_setting('test.role',true),'') = any(coalesce($1,array['admin','billing'])) $$;
create function app.role_for_org(uuid) returns text language sql stable as $$ select case when $1::text = current_setting('test.org',true) then current_setting('test.role',true) end $$;
create table public.organizations(id uuid primary key);
create table public.providers(id uuid primary key, organization_id uuid, full_name text, tax_id text, exequatur text, is_active boolean default true);
create table public.ars(id uuid primary key,name text,code text,is_active boolean default true);
create table public.ars_plans(id uuid primary key,ars_id uuid,name text,is_active boolean default true);
create table public.procedures(id uuid primary key,internal_code text,description text,is_active boolean default true);
create table public.procedure_codes(id uuid primary key default gen_random_uuid(),procedure_id uuid,code_system text,ars_id uuid,code text);
create unique index procedure_codes_one_concept_uq on public.procedure_codes(code_system,coalesce(ars_id,'00000000-0000-0000-0000-000000000000'::uuid),upper(code));
create table public.tariffs(provider_id uuid,ars_id uuid,procedure_id uuid,plan_id uuid,amount numeric,valid_during daterange,status text default 'vigente');
create table public.audit_log(id bigint generated always as identity, user_id uuid,table_name text,old_values jsonb,new_values jsonb);
create function app.audit() returns trigger language plpgsql security definer set search_path = '' as $$ begin
 insert into public.audit_log(user_id,table_name,old_values,new_values) values(auth.uid(),tg_table_name,case when tg_op='UPDATE' then to_jsonb(old) end,to_jsonb(new));return null;end $$;
create function app.parse_date_do(text) returns date language plpgsql immutable as $$ begin if $1 is null or trim($1)='' then return null;end if; return to_date($1,'DD/MM/YYYY'); exception when others then return null;end $$;
create function public.create_contract_tariff_plan(uuid,uuid,uuid,uuid,numeric,date,date,text,text,text) returns void language plpgsql security definer as $$ begin
 if current_setting('test.fail_tariff',true)='true' then raise exception 'test tariff save failure';end if;
 if not app.is_staff(array['admin','billing']) then raise insufficient_privilege;end if;
 insert into public.tariffs(provider_id,ars_id,plan_id,procedure_id,amount,valid_during) values($1,$2,$3,$4,$5,daterange($6,case when $7 is null then null else $7+1 end));end $$;
create function app.tariff_import_log_add2(uuid,uuid,uuid,uuid,text,text,date,date,integer,integer,integer,integer,integer) returns void language sql as $$ select $$;
grant select on all tables in schema public to authenticated;
grant execute on all functions in schema app,auth to authenticated;
insert into organizations values('10000000-0000-4000-8000-000000000001'),('10000000-0000-4000-8000-000000000002');
insert into providers(id,organization_id,full_name) values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Test doctor');
insert into ars(id,name,code) values('30000000-0000-4000-8000-000000000001','ARS Alpha','alpha'),('30000000-0000-4000-8000-000000000002','ARS Beta','beta');
insert into procedures(id,internal_code,description) values('40000000-0000-4000-8000-000000000001','TEST-A','Service A'),('40000000-0000-4000-8000-000000000002','TEST-B','Service B');
insert into procedure_codes(procedure_id,code_system,ars_id,code) values
('40000000-0000-4000-8000-000000000001','SIMON',null,'2467'),
('40000000-0000-4000-8000-000000000002','CUPS','30000000-0000-4000-8000-000000000002','BETA-ONLY');

insert into public.tariffs(provider_id,ars_id,procedure_id,amount,valid_during) values('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000001',900,daterange('2025-01-01',null));
