-- SOFA MVP v1 — policy helper execution grants.
-- RLS policies invoke these helpers as the authenticated role, so EXECUTE is required.

revoke all on function app.visible_org_ids_v1() from public,anon;
revoke all on function app.role_for_org_v1(uuid) from public,anon;
revoke all on function app.can_claim_v1(uuid,uuid,boolean) from public,anon;

grant execute on function app.visible_org_ids_v1() to authenticated;
grant execute on function app.role_for_org_v1(uuid) to authenticated;
grant execute on function app.can_claim_v1(uuid,uuid,boolean) to authenticated;
