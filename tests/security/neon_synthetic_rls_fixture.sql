-- SOFA synthetic integration fixture. Run ONLY against Neon project SoFa, schema sofa_test.
-- Never run on Supabase production. Does not contain patient data.
BEGIN;
CREATE TABLE IF NOT EXISTS sofa_test.organizations(id text PRIMARY KEY, kind text NOT NULL CHECK(kind IN ('client','operator')));
CREATE TABLE IF NOT EXISTS sofa_test.memberships(user_id text NOT NULL, org_id text NOT NULL REFERENCES sofa_test.organizations(id), role_code text NOT NULL, active boolean NOT NULL DEFAULT true, PRIMARY KEY(user_id,org_id));
CREATE TABLE IF NOT EXISTS sofa_test.home_org(user_id text PRIMARY KEY, org_id text NOT NULL REFERENCES sofa_test.organizations(id));
CREATE TABLE IF NOT EXISTS sofa_test.exceptions(user_id text NOT NULL, org_id text NOT NULL REFERENCES sofa_test.organizations(id), expires_at timestamptz NOT NULL, revoked_at timestamptz, PRIMARY KEY(user_id,org_id));
CREATE TABLE IF NOT EXISTS sofa_test.claims(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, org_id text NOT NULL REFERENCES sofa_test.organizations(id), amount numeric NOT NULL);
INSERT INTO sofa_test.organizations(id,kind) VALUES ('A','client'),('B','client'),('SOFA','operator') ON CONFLICT DO NOTHING;
INSERT INTO sofa_test.memberships(user_id,org_id,role_code) VALUES ('doctor_a','A','client'),('doctor_b','B','client'),('doctor_a','B','client'),('staff','SOFA','billing'),('staff','A','billing') ON CONFLICT DO NOTHING;
INSERT INTO sofa_test.home_org(user_id,org_id) VALUES ('doctor_a','A'),('doctor_b','B') ON CONFLICT DO NOTHING;
INSERT INTO sofa_test.exceptions(user_id,org_id,expires_at) VALUES ('doctor_a','B',now()-interval '1 hour') ON CONFLICT(user_id,org_id) DO UPDATE SET expires_at=excluded.expires_at,revoked_at=NULL;
INSERT INTO sofa_test.claims(org_id,amount) SELECT 'A',100 WHERE NOT EXISTS(SELECT 1 FROM sofa_test.claims WHERE org_id='A');
INSERT INTO sofa_test.claims(org_id,amount) SELECT 'B',200 WHERE NOT EXISTS(SELECT 1 FROM sofa_test.claims WHERE org_id='B');
CREATE OR REPLACE FUNCTION sofa_test.allowed_org(p_org text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM sofa_test.memberships m WHERE m.user_id=current_setting('sofa_test.user_id',true) AND m.org_id=p_org AND m.active
 AND (EXISTS(SELECT 1 FROM sofa_test.home_org h WHERE h.user_id=m.user_id AND h.org_id=p_org)
 OR EXISTS(SELECT 1 FROM sofa_test.exceptions e WHERE e.user_id=m.user_id AND e.org_id=p_org AND e.revoked_at IS NULL AND e.expires_at>now())
 OR (EXISTS(SELECT 1 FROM sofa_test.memberships op JOIN sofa_test.organizations o ON o.id=op.org_id WHERE op.user_id=m.user_id AND op.active AND o.kind='operator') AND current_setting('sofa_test.staff_mfa',true)='true')))
$$;
ALTER TABLE sofa_test.claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS claim_isolation ON sofa_test.claims;
CREATE POLICY claim_isolation ON sofa_test.claims USING (sofa_test.allowed_org(org_id)) WITH CHECK (sofa_test.allowed_org(org_id));
-- Test role is intentionally not the table owner (owners bypass RLS by default).
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='sofa_test_reader') THEN CREATE ROLE sofa_test_reader NOLOGIN; END IF; END $$;
GRANT USAGE ON SCHEMA sofa_test TO sofa_test_reader;
GRANT SELECT,INSERT,UPDATE,DELETE ON sofa_test.claims TO sofa_test_reader;
GRANT EXECUTE ON FUNCTION sofa_test.allowed_org(text) TO sofa_test_reader;
COMMIT;

-- Manual verification in a SEPARATE psql transaction after setup:
-- BEGIN; SET LOCAL ROLE sofa_test_reader;
-- SELECT set_config('sofa_test.user_id','doctor_a',true);
-- SELECT org_id FROM sofa_test.claims; -- only A, not B: exception expired
-- ROLLBACK;
-- A valid positive control must show A. Never run against real patient data.
