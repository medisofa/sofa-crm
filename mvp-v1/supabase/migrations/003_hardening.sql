-- SOFA MVP v1 — hardening de privilegios y política de tarifas.
-- Requiere 001_core.sql.

drop policy if exists tariffs_v1_select on public.tariffs_v1;
create policy tariffs_v1_select on public.tariffs_v1 for select to authenticated
using(
  organization_id in(select app.visible_org_ids_v1())
  and (
    app.role_for_org_v1(organization_id)<>'capturer'
    or exists(
      select 1 from public.capturer_scopes_v1 s
      where s.user_id=auth.uid()
        and s.provider_id=tariffs_v1.provider_id
        and s.organization_id=tariffs_v1.organization_id
    )
  )
);

revoke all on function public.my_context_v1(),public.claim_create_v1(jsonb),public.claim_transition_v1(uuid,text,text) from public,anon;
grant execute on function public.my_context_v1(),public.claim_create_v1(jsonb),public.claim_transition_v1(uuid,text,text) to authenticated;

revoke all on public.claim_events_v1,public.audit_events_v1 from anon;
revoke insert,update,delete on public.claim_events_v1,public.audit_events_v1 from authenticated;
