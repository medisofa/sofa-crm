-- SOFA MVP v1 — pilot hardening after isolated branch validation.
-- Applies only to MVP v1 schema/tables.

-- Capturers may read only their own provider scopes. This makes provider/tariff
-- policies deterministic while preserving tenant isolation.
drop policy if exists capturer_scopes_v1_self_read on public.capturer_scopes_v1;
create policy capturer_scopes_v1_self_read
on public.capturer_scopes_v1 for select to authenticated
using (user_id = auth.uid());

grant select on public.capturer_scopes_v1 to authenticated;

-- Explicit read grants for the MVP surfaces consumed by the web app.
grant select on
  public.providers_v1,
  public.ars_v1,
  public.procedures_v1,
  public.tariffs_v1,
  public.claims_v1,
  public.claim_events_v1,
  public.claim_documents_v1,
  public.submissions_v1,
  public.submission_claims_v1,
  public.payments_v1,
  public.payment_allocations_v1,
  public.denials_v1
to authenticated;

-- All claim creation must go through claim_create_v1(). Direct DML is blocked.
drop policy if exists claims_v1_insert on public.claims_v1;
revoke insert, update, delete on public.claims_v1 from authenticated;

-- Treat NULL authorization as an empty authorization for active duplicate detection.
drop index if exists public.claims_v1_soft_dup_ux;
create unique index claims_v1_soft_dup_ux
on public.claims_v1(
  organization_id,
  provider_id,
  ars_id,
  service_date,
  member_number,
  procedure_id,
  coalesce(authorization_number,'')
)
where status <> 'closed';

-- Context must expose visible client organizations to staff, not only direct memberships.
create or replace function public.my_context_v1()
returns jsonb language sql stable security definer set search_path=''
as $$
  with direct_operator as (
    select
      o.id organization_id,
      coalesce(o.trade_name,o.legal_name) organization_name,
      o.kind,
      ou.role_code
    from public.organization_users_v1 ou
    join public.organizations_v1 o on o.id=ou.organization_id
    where ou.user_id=auth.uid()
      and ou.is_active
      and o.kind='operator'
  ),
  visible_clients as (
    select
      o.id organization_id,
      coalesce(o.trade_name,o.legal_name) organization_name,
      o.kind,
      app.role_for_org_v1(o.id) role_code
    from public.organizations_v1 o
    where o.kind='client'
      and o.id in (select app.visible_org_ids_v1())
  ),
  all_rows as (
    select * from direct_operator
    union all
    select * from visible_clients
  )
  select jsonb_build_object(
    'user_id', auth.uid(),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organization_id', organization_id,
        'organization_name', organization_name,
        'kind', kind,
        'role_code', role_code
      ) order by kind desc, organization_name)
      from all_rows
      where role_code is not null
    ), '[]'::jsonb)
  )
$$;

revoke all on function public.my_context_v1() from public,anon;
grant execute on function public.my_context_v1() to authenticated;

-- Generic transition may only perform operational state changes.
-- Submission, denial and payment states are owned by their transactional RPCs.
create or replace function public.claim_transition_v1(p_claim uuid,p_to_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  c public.claims_v1;
  v_role text;
  v_allowed boolean := false;
begin
  select * into c from public.claims_v1 where id=p_claim for update;
  if c.id is null or not app.can_claim_v1(c.organization_id,c.provider_id,true) then
    raise exception 'Reclamación no encontrada.' using errcode='P0002';
  end if;

  v_role := app.role_for_org_v1(c.organization_id);

  v_allowed := case c.status
    when 'captured' then
      p_to_status='received' and v_role in ('super_admin','admin','operations','billing')
    when 'received' then
      p_to_status='validated' and v_role in ('super_admin','admin','operations','billing','auditor')
    when 'submitted' then
      p_to_status='observed' and v_role in ('super_admin','admin','glosas')
    when 'observed' then
      p_to_status='validated' and v_role in ('super_admin','admin','operations','billing','glosas')
    when 'denied' then
      p_to_status='closed' and v_role in ('super_admin','admin','glosas')
    when 'paid' then
      p_to_status='closed' and v_role in ('super_admin','admin','glosas')
    else false
  end;

  if not v_allowed then
    raise exception 'Transición no permitida para el estado o rol.' using errcode='42501';
  end if;

  update public.claims_v1
     set status=p_to_status,updated_at=now()
   where id=p_claim;

  insert into public.claim_events_v1(
    claim_id,organization_id,event_type,from_status,to_status,note,actor_id
  )
  values(
    p_claim,c.organization_id,'status_changed',c.status,p_to_status,
    nullif(left(btrim(coalesce(p_note,'')),500),''),
    auth.uid()
  );

  insert into public.audit_events_v1(
    organization_id,actor_id,action,entity_type,entity_id,metadata
  )
  values(
    c.organization_id,auth.uid(),'claim.status_changed','claim',p_claim,
    jsonb_build_object('from',c.status,'to',p_to_status)
  );

  return jsonb_build_object('id',p_claim,'from',c.status,'to',p_to_status);
end
$$;

revoke all on function public.claim_transition_v1(uuid,text,text) from public,anon;
grant execute on function public.claim_transition_v1(uuid,text,text) to authenticated;
