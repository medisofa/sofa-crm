-- SOFA / proposed migration only: NOT applied to production.
-- External users have one active client organization by default.
-- Explicit exceptions are approved, dated and time-bounded.
-- Staff/operator memberships are excluded.
CREATE TABLE IF NOT EXISTS public.external_multi_org_exceptions (
  user_id uuid NOT NULL REFERENCES public.profiles(id),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  approved_by uuid NOT NULL REFERENCES public.profiles(id),
  reason text NOT NULL CHECK (length(trim(reason)) >= 12),
  valid_until timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  PRIMARY KEY (user_id, organization_id)
);
ALTER TABLE public.external_multi_org_exceptions ENABLE ROW LEVEL SECURITY;
-- No client policies: exceptions are managed by a vetted admin server-side workflow.
REVOKE ALL ON public.external_multi_org_exceptions FROM anon, authenticated;
CREATE OR REPLACE FUNCTION public.sofa_enforce_external_single_org()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_kind text;
  v_other_count integer;
  v_authorized boolean;
BEGIN
  IF NEW.is_active IS DISTINCT FROM TRUE THEN RETURN NEW; END IF;
  SELECT kind INTO v_kind FROM public.organizations WHERE id = NEW.organization_id;
  IF v_kind IS DISTINCT FROM 'client' THEN RETURN NEW; END IF;
  -- Staff SOFA exception: membership in the operator organization.
  IF EXISTS (
    SELECT 1 FROM public.organization_users m
    JOIN public.organizations o ON o.id=m.organization_id
    WHERE m.user_id=NEW.user_id AND m.is_active AND o.kind='operator'
      AND m.role_code IN ('super_admin','admin','assistant','billing','glosas','auditor')
  ) THEN RETURN NEW; END IF;
  -- Serialize concurrent membership changes for the same identity.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(NEW.user_id::text, 0));
  SELECT count(*) INTO v_other_count
  FROM public.organization_users m
  JOIN public.organizations o ON o.id=m.organization_id
  WHERE m.user_id=NEW.user_id AND m.organization_id<>NEW.organization_id
    AND m.is_active AND o.kind='client';
  IF v_other_count=0 THEN RETURN NEW; END IF;
  SELECT EXISTS (
    SELECT 1 FROM public.external_multi_org_exceptions e
    WHERE e.user_id=NEW.user_id AND e.organization_id=NEW.organization_id
      AND e.revoked_at IS NULL AND e.valid_until>now()
  ) INTO v_authorized;
  IF NOT v_authorized THEN
    RAISE EXCEPTION 'SOFA: external user already assigned to a different client organization';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.sofa_enforce_external_single_org() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS sofa_external_single_org_guard ON public.organization_users;
CREATE TRIGGER sofa_external_single_org_guard
BEFORE INSERT OR UPDATE OF is_active,organization_id,user_id ON public.organization_users
FOR EACH ROW EXECUTE FUNCTION public.sofa_enforce_external_single_org();
-- Pre-deployment review: resolve existing multi-org identity and verify RLS
-- helper semantics; trigger is forward-looking and does not repair old memberships.
