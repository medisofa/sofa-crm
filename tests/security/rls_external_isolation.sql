-- PostgreSQL/RLS integration test (psql). ONLY run on restored isolated DB.
-- Requirements: seeded users A/B, orgs A/B, one claim in each org, active profiles,
-- JWT/MFA context as needed; user A must NOT belong to org B.
-- Usage: psql "$SOFA_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 \
--   -v user_a=... -v org_a=... -v org_b=... -f tests/security/rls_external_isolation.sql
-- NEVER point SOFA_TEST_DATABASE_URL at production.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', :'user_a', true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
-- Assert A is visible (positive control); a test returning 0 because the
-- profile is disabled is NOT a valid isolation certification.
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM app.visible_org_ids()) THEN
   RAISE EXCEPTION 'FAIL: no visible organizations; invalid positive control';
 END IF;
END $$;
SELECT CASE WHEN EXISTS (
 SELECT 1 FROM public.service_lines
 WHERE organization_id=:'org_b'::uuid
) THEN 1/0 ELSE 1 END AS claim_read_isolation;
SELECT CASE WHEN EXISTS (
 SELECT 1 FROM public.payments
 WHERE organization_id=:'org_b'::uuid
) THEN 1/0 ELSE 1 END AS payment_read_isolation;
SELECT CASE WHEN EXISTS (
 SELECT 1 FROM public.documents
 WHERE organization_id=:'org_b'::uuid
) THEN 1/0 ELSE 1 END AS document_read_isolation;
SELECT CASE WHEN EXISTS (
 SELECT 1 FROM public.submissions
 WHERE organization_id=:'org_b'::uuid
) THEN 1/0 ELSE 1 END AS submission_read_isolation;
-- Update attempts must affect zero B rows; rollback protects any accidental A writes.
WITH attempted AS (
 UPDATE public.service_lines SET organization_id=organization_id
 WHERE organization_id=:'org_b'::uuid RETURNING 1
)
SELECT CASE WHEN (SELECT count(*) FROM attempted)=0 THEN 1 ELSE 1/0 END AS update_isolation;
WITH attempted AS (
 DELETE FROM public.service_lines WHERE organization_id=:'org_b'::uuid RETURNING 1
)
SELECT CASE WHEN (SELECT count(*) FROM attempted)=0 THEN 1 ELSE 1/0 END AS delete_isolation;
ROLLBACK;
-- Follow-up: test INSERT and Storage signed URLs via real HTTP JWT; SQL alone
-- does not exercise Edge Functions or signed download authorization.
