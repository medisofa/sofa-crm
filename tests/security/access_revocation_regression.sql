\set ON_ERROR_STOP on
-- Solo fixture sintética de user_repair_fixture.sql.
BEGIN;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.sofa_user_repair_fixture_marker WHERE value='synthetic-user-repair-only') THEN RAISE EXCEPTION 'Fixture requerida'; END IF;
END $$;
CREATE FUNCTION public.qa_revoke_assert(v boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',msg; END IF; RAISE NOTICE 'PASS: %',msg; END $$;
CREATE FUNCTION public.qa_revoke_denied(q text, expected_state text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected_state THEN RAISE NOTICE 'PASS denied %',expected_state; RETURN; END IF;
  RAISE;
 END;
 RAISE EXCEPTION 'Expected denial %',expected_state;
END $$;
INSERT INTO public.organization_users VALUES('00000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000003','capturer',true);
SELECT public.qa_revoke_assert(NOT has_function_privilege('anon','public.admin_access_revoke_apply(uuid,uuid[],text,text)','EXECUTE'),'anon cannot apply');
SELECT public.qa_revoke_assert(NOT has_table_privilege('authenticated','public.user_access_revocation_audit','INSERT'),'no direct audit writes');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
SELECT public.qa_revoke_denied($q$SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000003',ARRAY['00000000-0000-4000-8000-000000000101']::uuid[])$q$,'42501');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
SELECT public.qa_revoke_denied($q$SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000001',ARRAY['00000000-0000-4000-8000-000000000100']::uuid[])$q$,'42501');
SELECT public.qa_revoke_denied($q$SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000003',ARRAY[]::uuid[])$q$,'22023');
SELECT public.qa_revoke_denied($q$SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000003',ARRAY['00000000-0000-4000-8000-000000000201']::uuid[])$q$,'42501');
SELECT public.qa_revoke_denied($q$SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000003',ARRAY['00000000-0000-4000-8000-000000000101',NULL]::uuid[])$q$,'22023');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","aal":"aal2"}',true);
SELECT public.qa_revoke_denied($q$SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000003',ARRAY['00000000-0000-4000-8000-000000000101']::uuid[])$q$,'42501');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
RESET ROLE;
UPDATE public.profiles SET must_change_password=true WHERE id='00000000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT public.qa_revoke_denied($q$SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000003',ARRAY['00000000-0000-4000-8000-000000000101']::uuid[])$q$,'42501');
RESET ROLE;
UPDATE public.profiles SET must_change_password=false,is_active=false WHERE id='00000000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT public.qa_revoke_denied($q$SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000003',ARRAY['00000000-0000-4000-8000-000000000101']::uuid[])$q$,'42501');
RESET ROLE;
UPDATE public.profiles SET is_active=true WHERE id='00000000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000003',ARRAY['00000000-0000-4000-8000-000000000101']::uuid[])->>'expected' AS old_token \gset
RESET ROLE;
UPDATE public.organization_users SET role_code='capturer' WHERE user_id='00000000-0000-4000-8000-000000000003' AND organization_id='00000000-0000-4000-8000-000000000101';
SET LOCAL ROLE authenticated;
SELECT public.qa_revoke_denied(format('SELECT public.admin_access_revoke_apply(%L,ARRAY[%L]::uuid[],%L,%L)','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000101','Asociación incorrecta revisada',:'old_token'),'40001');
SELECT public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000003',ARRAY['00000000-0000-4000-8000-000000000101']::uuid[])->>'expected' AS fresh_token \gset
RESET ROLE;
CREATE FUNCTION public.qa_revoke_audit_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'audit unavailable'; END $$;
CREATE TRIGGER qa_fail_audit BEFORE INSERT ON public.user_access_revocation_audit FOR EACH ROW EXECUTE FUNCTION public.qa_revoke_audit_failure();
SET LOCAL ROLE authenticated;
SELECT public.qa_revoke_denied(format('SELECT public.admin_access_revoke_apply(%L,ARRAY[%L]::uuid[],%L,%L)','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000101','Asociación incorrecta revisada',:'fresh_token'),'P0001');
RESET ROLE;
SELECT public.qa_revoke_assert((SELECT is_active FROM public.organization_users WHERE user_id='00000000-0000-4000-8000-000000000003' AND organization_id='00000000-0000-4000-8000-000000000101'),'audit failure rolls back change');
DROP TRIGGER qa_fail_audit ON public.user_access_revocation_audit;
SET LOCAL ROLE authenticated;
SELECT public.qa_revoke_assert((public.admin_access_revoke_apply('00000000-0000-4000-8000-000000000003',ARRAY['00000000-0000-4000-8000-000000000101']::uuid[],'Asociación incorrecta revisada',:'fresh_token')->>'ok')::boolean,'selected revoke succeeds');
RESET ROLE;
SELECT public.qa_revoke_assert((SELECT NOT is_active FROM public.organization_users WHERE user_id='00000000-0000-4000-8000-000000000003' AND organization_id='00000000-0000-4000-8000-000000000101'),'selected access revoked');
SELECT public.qa_revoke_assert((SELECT is_active FROM public.organization_users WHERE user_id='00000000-0000-4000-8000-000000000003' AND organization_id='00000000-0000-4000-8000-000000000102'),'unselected access preserved');
SELECT public.qa_revoke_assert((SELECT is_active FROM public.profiles WHERE id='00000000-0000-4000-8000-000000000003'),'profile unchanged');
SELECT public.qa_revoke_assert((SELECT count(*)=1 FROM public.user_access_revocation_audit),'exactly one audit');
INSERT INTO public.providers VALUES('00000000-0000-4000-8000-000000000777','00000000-0000-4000-8000-000000000004');
SET LOCAL ROLE authenticated;
SELECT public.qa_revoke_assert(NOT (public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000004',ARRAY['00000000-0000-4000-8000-000000000101']::uuid[])->>'can_revoke')::boolean,'provider link blocked');
RESET ROLE;
INSERT INTO public.organization_users VALUES('00000000-0000-4000-8000-000000000100','00000000-0000-4000-8000-000000000005','super_admin',false);
SET LOCAL ROLE authenticated;
SELECT public.qa_revoke_assert(NOT (public.admin_access_revoke_preview('00000000-0000-4000-8000-000000000005',ARRAY['00000000-0000-4000-8000-000000000101']::uuid[])->>'can_revoke')::boolean,'historical Super Admin blocked');
RESET ROLE;
ROLLBACK;
