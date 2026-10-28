-- SOFA SECURITY PATCH v2 - DESIGN / NOT FOR DIRECT PRODUCTION EXECUTION.
-- Existing memberships and legacy app.can/app.visible_org_ids must be reconciled.
-- Applies to external client membership visibility only, not SOFA staff role grants.
-- Fail-closed: additional client org is only visible with unexpired, unrevoked exception.
-- Explicit primary organization must be recorded rather than relying on created_at ordering.

CREATE TABLE IF NOT EXISTS public.external_access_home (
 user_id uuid PRIMARY KEY REFERENCES public.profiles(id),
 organization_id uuid NOT NULL REFERENCES public.organizations(id),
 assigned_by uuid NOT NULL REFERENCES public.profiles(id),
 assigned_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.external_multi_org_exceptions (
 user_id uuid NOT NULL REFERENCES public.profiles(id),
 organization_id uuid NOT NULL REFERENCES public.organizations(id),
 approved_by uuid NOT NULL REFERENCES public.profiles(id),
 reason text NOT NULL CHECK (length(btrim(reason)) >= 12),
 valid_until timestamptz NOT NULL,
 revoked_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,organization_id)
);
ALTER TABLE public.external_access_home ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.external_multi_org_exceptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.external_access_home FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.external_multi_org_exceptions FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION app.external_client_org_allowed(p_user uuid,p_org uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT EXISTS (
   SELECT 1 FROM public.organization_users m
   JOIN public.organizations o ON o.id=m.organization_id
   JOIN public.profiles p ON p.id=m.user_id
   WHERE m.user_id=p_user AND m.organization_id=p_org
     AND m.is_active AND o.kind='client'
     AND p.is_active AND NOT p.must_change_password
     AND (
       EXISTS(SELECT 1 FROM public.external_access_home h
              WHERE h.user_id=p_user AND h.organization_id=p_org)
       OR EXISTS(SELECT 1 FROM public.external_multi_org_exceptions e
                 WHERE e.user_id=p_user AND e.organization_id=p_org
                   AND e.revoked_at IS NULL AND e.valid_until>now())
     )
 )
$$;
REVOKE ALL ON FUNCTION app.external_client_org_allowed(uuid,uuid) FROM PUBLIC,anon,authenticated;

-- MANDATORY integration before activation:
-- 1. Confirm staff identity using server-validated operator membership and MFA.
-- 2. Replace all client membership authorization branches in app.visible_org_ids()
--    AND app.can(), app.can_orgs(), capturer_* helpers, Storage, RPCs and Edge Functions
--    with a common, vetted organization authorization rule.
-- 3. Fail closed if no home assignment is recorded.
-- 4. Ensure a revoked/expired exception invalidates access on the NEXT request,
--    without waiting for a trigger or scheduled job.
-- 5. Restrict writes to home/exception tables to audited admin backend, not clients.
-- 6. Run integration test suite with JWTs in a restored, isolated environment.
-- 7. Do not execute this partial proposal as a complete deployment migration.
