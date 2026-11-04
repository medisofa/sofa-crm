do $$begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;end$$;
create schema app;create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table public.profiles(id uuid primary key);
create table public.organizations(id uuid primary key);
create table public.providers(id uuid primary key,organization_id uuid,is_active boolean);
create table public.submissions(id uuid primary key,ars_id uuid,status text);
create table public.service_lines(id uuid primary key,organization_id uuid,submission_id uuid,claim_folio text,member_number text,service_date date,procedure_id uuid,authorization_number text,unit_amount numeric,protected boolean default false);
create table public.documents(service_line_id uuid);
create table public.tariffs(id uuid primary key,provider_id uuid,ars_id uuid,procedure_id uuid,organization_id uuid,amount numeric,valid_during daterange,plan_id uuid);
create table public.audit_log(id bigint generated always as identity primary key,user_id uuid,organization_id uuid,table_name text,record_id text,operation text,old_values jsonb,new_values jsonb);
create function app.is_staff(p_roles text[]) returns boolean language sql stable as $$select auth.uid() is not null and coalesce(current_setting('test.role',true),'billing')=any(p_roles)$$;
create function app.visible_org_ids() returns setof uuid language sql stable as $$select case when auth.uid()='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' then '11111111-1111-4111-8111-111111111111'::uuid else '22222222-2222-4222-8222-222222222222'::uuid end$$;
create function app.claim_access_role(p_org uuid,p_provider uuid) returns text language sql stable as $$select case when p_org in(select app.visible_org_ids()) then coalesce(current_setting('test.role',true),'billing') end$$;
create function app.contract_tariff_for(p_provider uuid,p_ars uuid,p_procedure uuid,p_date date,p_plan uuid default null) returns public.tariffs language sql stable as $$select t from public.tariffs t where provider_id=p_provider and ars_id=p_ars and procedure_id=p_procedure and valid_during @> p_date order by lower(valid_during) desc limit 1$$;
create function public.log_google_intake_import(p_record_id text,p_org uuid,p_claim uuid,p_folio text) returns bigint language plpgsql security definer as $$declare v bigint;begin if current_setting('test.audit_fail',true)='on' then raise exception 'audit failed';end if;insert into public.audit_log(user_id,record_id,operation)values(auth.uid(),p_record_id,'IMPORT')returning id into v;return v;end$$;
create function public.log_google_intake_edit(p_record_id text,p_org uuid,p_before jsonb,p_after jsonb,p_fields text[]) returns bigint language plpgsql security definer as $$declare v bigint;begin if current_setting('test.audit_fail',true)='on' then raise exception 'audit failed';end if;insert into public.audit_log(user_id,record_id,operation,old_values,new_values)values(auth.uid(),p_record_id,'EDIT',p_before,p_after)returning id into v;return v;end$$;
create function public.capture_claim_dx(p_provider uuid,p_ars uuid,p_procedure uuid,p_service_date date,p_patient_name text,p_member text,p_authorization text default null,p_patient_doc text default null,p_amount numeric default null,p_quantity numeric default 1,p_care_mode text default null,p_clinic text default null,p_notes text default null,p_discrepancy_reason text default null,p_not_contracted text default 'bloquear',p_exception_reason text default null,p_allow_duplicate boolean default false,p_center uuid default null,p_diagnosis text default null) returns jsonb language plpgsql security definer as $$declare v_id uuid:=gen_random_uuid();v_sub uuid:=gen_random_uuid();v_org uuid;v_amount numeric;begin
 if p_allow_duplicate or p_not_contracted<>'bloquear' then raise exception 'unsafe override';end if;
 select organization_id into v_org from public.providers where id=p_provider;select coalesce(p_amount,amount) into v_amount from public.tariffs where provider_id=p_provider limit 1;
 insert into public.submissions values(v_sub,p_ars,'borrador');insert into public.service_lines(id,organization_id,submission_id,claim_folio,member_number,service_date,procedure_id,authorization_number,unit_amount)values(v_id,v_org,v_sub,'F-'||v_id,p_member,p_service_date,p_procedure,p_authorization,v_amount);
 return jsonb_build_object('id',v_id,'folio','F-'||v_id,'amount',v_amount);end$$;
create function public.remove_service_line(p_line uuid,p_reason text) returns jsonb language plpgsql security definer as $$begin
 if coalesce(current_setting('test.role',true),'billing')='operations' then raise exception using errcode='42501';end if;
 if current_setting('test.remove_protected',true)='on' or exists(select 1 from public.service_lines where id=p_line and protected) then raise exception using errcode='23514',message='claim protected';end if;
 delete from public.service_lines where id=p_line;return jsonb_build_object('removed',true);end$$;
create function public.create_contract_tariff(p_provider uuid,p_ars uuid,p_procedure uuid,p_amount numeric,p_valid_from date,p_valid_to date default null,p_contract_ref text default null,p_ars_code text default null,p_notes text default null,p_currency text default 'DOP') returns uuid language plpgsql security invoker as $$declare v uuid:=gen_random_uuid();begin insert into public.tariffs values(v,p_provider,p_ars,p_procedure,'11111111-1111-4111-8111-111111111111',p_amount,daterange(p_valid_from,p_valid_to),null);return v;end$$;
grant usage on schema app,auth,public to authenticated,anon;grant select on public.providers,public.tariffs to authenticated;grant insert on public.tariffs to authenticated;
insert into public.profiles values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
insert into public.organizations values('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
insert into public.providers values('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111',true);
insert into public.tariffs values('44444444-4444-4444-8444-444444444444','33333333-3333-4333-8333-333333333333','55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666','11111111-1111-4111-8111-111111111111',850,'[2026-01-01,)',null);

create function app.test_audit_guard() returns trigger language plpgsql as $$begin if current_setting('test.audit_fail',true)='on' then raise exception 'audit failed';end if;return new;end$$;
create trigger test_audit_guard before insert on public.audit_log for each row execute function app.test_audit_guard();
