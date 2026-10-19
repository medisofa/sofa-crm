-- SOFA: full multiclient gate for RESTORED STAGING ONLY.
-- Preconditions: execute proposed external_access_home and external_multi_org_exceptions
-- DDL from docs/sql/PROPOSED_external_exception_expiry_v2.sql;
-- manually assign one reviewed home per external user before activating.
-- Never run on production before full restored backup and authenticated acceptance.
BEGIN;
CREATE OR REPLACE FUNCTION app.external_client_org_allowed(p_user uuid,p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT EXISTS (
 SELECT 1 FROM public.organization_users m
 JOIN public.organizations o ON o.id=m.organization_id
 JOIN public.profiles p ON p.id=m.user_id
 WHERE m.user_id=p_user AND m.organization_id=p_org
 AND m.is_active AND o.kind='client' AND p.is_active AND NOT p.must_change_password
 AND (EXISTS(SELECT 1 FROM public.external_access_home h WHERE h.user_id=p_user AND h.organization_id=p_org)
 OR EXISTS(SELECT 1 FROM public.external_multi_org_exceptions e
 WHERE e.user_id=p_user AND e.organization_id=p_org AND e.revoked_at IS NULL AND e.valid_until>now()))
 ) $$;
REVOKE ALL ON FUNCTION app.external_client_org_allowed(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION app.visible_org_ids()
RETURNS SETOF uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 RETURN QUERY
 SELECT ou.organization_id FROM public.organization_users ou
 JOIN public.profiles p ON p.id=ou.user_id AND p.is_active AND NOT p.must_change_password
 JOIN public.roles r ON r.code=ou.role_code
 JOIN public.organizations o ON o.id=ou.organization_id
 WHERE ou.user_id=auth.uid() AND ou.is_active AND ou.role_code<>'capturer'
 AND (NOT r.is_staff OR app.mfa_ok())
 AND (r.is_staff OR o.kind<>'client' OR app.external_client_org_allowed(auth.uid(),ou.organization_id))
 UNION
 SELECT c.id FROM public.organizations c
 JOIN public.organization_users ou ON ou.organization_id=c.operator_id AND ou.user_id=auth.uid() AND ou.is_active
 JOIN public.roles r ON r.code=ou.role_code AND r.is_staff
 JOIN public.profiles p ON p.id=ou.user_id AND p.is_active AND NOT p.must_change_password
 WHERE c.kind='client' AND app.mfa_ok()
 AND (NOT EXISTS(SELECT 1 FROM public.staff_client_access a WHERE a.user_id=auth.uid())
 OR ou.role_code IN ('super_admin','admin')
 OR EXISTS(SELECT 1 FROM public.staff_client_access a WHERE a.user_id=auth.uid() AND a.client_org_id=c.id));
END $$;

CREATE OR REPLACE FUNCTION app.role_for_org(p_org uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_uid uuid:=auth.uid(); v_r text;
BEGIN
 SELECT ou.role_code INTO v_r
 FROM public.organization_users ou
 JOIN public.profiles p ON p.id=ou.user_id AND p.is_active AND NOT p.must_change_password
 JOIN public.roles r ON r.code=ou.role_code
 JOIN public.organizations o ON o.id=ou.organization_id
 WHERE ou.organization_id=p_org AND ou.user_id=v_uid AND ou.is_active
 AND (NOT r.is_staff OR app.mfa_ok())
 AND (r.is_staff OR o.kind<>'client' OR app.external_client_org_allowed(v_uid,p_org));
 IF v_r IS NOT NULL THEN RETURN v_r; END IF;
 SELECT ou.role_code INTO v_r
 FROM public.organizations c
 JOIN public.organization_users ou ON ou.organization_id=c.operator_id AND ou.user_id=v_uid AND ou.is_active
 JOIN public.roles r ON r.code=ou.role_code AND r.is_staff
 JOIN public.profiles p ON p.id=ou.user_id AND p.is_active AND NOT p.must_change_password
 WHERE c.id=p_org AND c.kind='client' AND app.mfa_ok()
 AND (NOT EXISTS(SELECT 1 FROM public.staff_client_access a WHERE a.user_id=v_uid)
 OR ou.role_code IN ('super_admin','admin')
 OR EXISTS(SELECT 1 FROM public.staff_client_access a WHERE a.user_id=v_uid AND a.client_org_id=c.id));
 RETURN v_r;
END $$;

CREATE OR REPLACE FUNCTION app.can_orgs(p_roles text[] DEFAULT NULL::text[])
RETURNS SETOF uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 RETURN QUERY
 WITH directo AS (
 SELECT ou.organization_id AS org,ou.role_code
 FROM public.organization_users ou
 JOIN public.profiles p ON p.id=ou.user_id AND p.is_active AND NOT p.must_change_password
 JOIN public.roles r ON r.code=ou.role_code
 JOIN public.organizations o ON o.id=ou.organization_id
 WHERE ou.user_id=auth.uid() AND ou.is_active AND (NOT r.is_staff OR app.mfa_ok())
 AND (r.is_staff OR o.kind<>'client' OR app.external_client_org_allowed(auth.uid(),ou.organization_id))
 ), delegado AS (
 SELECT c.id AS org,ou.role_code
 FROM public.organizations c
 JOIN public.organization_users ou ON ou.organization_id=c.operator_id AND ou.user_id=auth.uid() AND ou.is_active
 JOIN public.roles r ON r.code=ou.role_code AND r.is_staff
 JOIN public.profiles p ON p.id=ou.user_id AND p.is_active AND NOT p.must_change_password
 WHERE c.kind='client' AND app.mfa_ok()
 AND (NOT EXISTS(SELECT 1 FROM public.staff_client_access a WHERE a.user_id=auth.uid())
 OR ou.role_code IN ('super_admin','admin')
 OR EXISTS(SELECT 1 FROM public.staff_client_access a WHERE a.user_id=auth.uid() AND a.client_org_id=c.id))
 )
 SELECT d.org FROM directo d WHERE p_roles IS NULL OR d.role_code=ANY(p_roles)
 UNION
 SELECT g.org FROM delegado g WHERE NOT EXISTS(SELECT 1 FROM directo d WHERE d.org=g.org)
 AND (p_roles IS NULL OR g.role_code=ANY(p_roles));
END $$;
COMMIT;
-- WARNING: further review required for capturer_*, storage, RPC, Edge, and direct
-- membership policies. Do not treat this SQL as a certified production fix.
