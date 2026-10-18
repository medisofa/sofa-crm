-- SOFA multitenancy authorization guard — draft for restored Supabase staging ONLY.
-- This script is intentionally NOT a production migration.
-- Existing external_access_home and external_multi_org_exceptions are described in
-- docs/sql/PROPOSED_external_exception_expiry_v2.sql; DO NOT auto-create or
-- populate them in production. Assign home explicitly after business review.
--
-- Every authenticated external user MUST have:
--  1) active profile without pending password reset;
--  2) active membership in requested client organization;
--  3) either designated home organization OR unrevoked, unexpired exception.
-- Staff cross-organization authorization must remain on the existing MFA-checked
-- operator path, not via external exceptions.
--
-- Crucial: guard must be enforced in BOTH:
--   app.visible_org_ids() for SELECT policies
--   app.role_for_org(uuid) for app.can()/INSERT/UPDATE/DELETE.
-- Also examine app.can_orgs, capturer helpers, Storage policies, RPC and Edge.
-- Adding the function alone does NOT enforce security.
--
-- Function from prior draft, with no PUBLIC/anon/authenticated execute:
CREATE OR REPLACE FUNCTION app.external_client_org_allowed(p_user uuid,p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
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
                   AND e.revoked_at IS NULL AND e.valid_until > now())
     )
 )
$$;
REVOKE ALL ON FUNCTION app.external_client_org_allowed(uuid,uuid)
FROM PUBLIC,anon,authenticated;

-- Integration pseudocode (must merge into existing functions; not standalone SQL):
-- In app.visible_org_ids() client membership branch:
-- AND app.external_client_org_allowed(auth.uid(), ou.organization_id)
-- In app.role_for_org(p_org) direct client membership branch:
-- AND (r0.is_staff OR app.external_client_org_allowed(auth.uid(),p_org))
-- Do not replace staff MFA checks or staff operator membership path.
-- Make client-role distinction using actual roles.is_staff rather than
-- assuming role_code='client' (capturer and other external roles may exist).
--
-- Required negative controls in Supabase staging:
--  home A: SELECT/INSERT/UPDATE/DELETE A permitted only by role;
--  home A: B denied despite legacy active B membership;
--  valid exception B: permitted within explicit role;
--  expired exception B: denied immediately;
--  revoked exception B: denied immediately;
--  inactive profile or membership: denied;
--  staff: approved B with MFA permitted; no MFA denied;
--  capturer: only delegated submissions, no wider org access.
--
-- Fail-closed on missing home. If a user has multiple memberships, never
-- choose home based on row order or automatically delete memberships.
-- Do not activate until restored staging passes and backup verified.
