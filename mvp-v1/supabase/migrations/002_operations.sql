-- SOFA MVP v1 — operaciones transaccionales mínimas.
-- Requiere 001_core.sql. NO producción sin gate GO.

create or replace function public.submission_create_v1(p_claims uuid[])
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  c0 public.claims_v1;
  c public.claims_v1;
  v_id uuid;
  v_period date;
  v_seq int;
  v_count int := 0;
begin
  if auth.uid() is null then raise exception 'No autenticado.' using errcode='42501'; end if;
  if p_claims is null or cardinality(p_claims)=0 then raise exception 'Seleccione reclamaciones.' using errcode='22023'; end if;
  if cardinality(p_claims)>500 then raise exception 'Máximo 500 reclamaciones por radicación.' using errcode='22023'; end if;

  select * into c0 from public.claims_v1 where id=p_claims[1] for update;
  if c0.id is null or not app.can_claim_v1(c0.organization_id,c0.provider_id,true) then raise exception 'Sin acceso.' using errcode='42501'; end if;
  if app.role_for_org_v1(c0.organization_id) not in ('super_admin','admin','billing') then raise exception 'Rol sin permiso para radicar.' using errcode='42501'; end if;
  v_period := date_trunc('month',c0.service_date)::date;
  select coalesce(max(sequence),0)+1 into v_seq from public.submissions_v1
   where organization_id=c0.organization_id and provider_id=c0.provider_id and ars_id=c0.ars_id and period=v_period;

  foreach c.id in array p_claims loop
    select * into c from public.claims_v1 where id=c.id for update;
    if c.id is null or c.organization_id<>c0.organization_id or c.provider_id<>c0.provider_id or c.ars_id<>c0.ars_id
       or date_trunc('month',c.service_date)::date<>v_period or c.status<>'validated' then
      raise exception 'Todas las reclamaciones deben ser validadas y pertenecer al mismo médico, ARS y período.' using errcode='23514';
    end if;
    v_count := v_count+1;
  end loop;

  insert into public.submissions_v1(organization_id,provider_id,ars_id,period,sequence,status,submitted_on)
  values(c0.organization_id,c0.provider_id,c0.ars_id,v_period,v_seq,'submitted',current_date) returning id into v_id;

  insert into public.submission_claims_v1(submission_id,claim_id)
  select v_id,x from unnest(p_claims) x;

  update public.claims_v1 set status='submitted',updated_at=now() where id=any(p_claims);
  insert into public.claim_events_v1(claim_id,organization_id,event_type,from_status,to_status,note,actor_id)
  select id,organization_id,'submitted','validated','submitted','Incluida en radicación',auth.uid() from public.claims_v1 where id=any(p_claims);
  insert into public.audit_events_v1(organization_id,actor_id,action,entity_type,entity_id,metadata)
  values(c0.organization_id,auth.uid(),'submission.created','submission',v_id,jsonb_build_object('claims',v_count,'sequence',v_seq,'period',v_period));

  return jsonb_build_object('id',v_id,'claims',v_count,'sequence',v_seq,'period',v_period);
end
$$;

create or replace function public.denial_create_v1(p_claim uuid,p_reason text,p_reason_code text default null,p_amount numeric default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare c public.claims_v1; v_id uuid; v_amount numeric;
begin
  select * into c from public.claims_v1 where id=p_claim for update;
  if c.id is null or not app.can_claim_v1(c.organization_id,c.provider_id,true) then raise exception 'Reclamación no encontrada.' using errcode='P0002'; end if;
  if app.role_for_org_v1(c.organization_id) not in ('super_admin','admin','glosas') then raise exception 'Rol sin permiso para registrar glosas.' using errcode='42501'; end if;
  if c.status not in ('submitted','observed') then raise exception 'La reclamación no está en etapa de ARS.' using errcode='23514'; end if;
  if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Indique el motivo de la glosa.' using errcode='22023'; end if;
  v_amount:=coalesce(p_amount,c.amount);
  if v_amount<0 or v_amount>c.amount then raise exception 'Monto glosado inválido.' using errcode='22023'; end if;

  insert into public.denials_v1(claim_id,organization_id,reason_code,reason,denied_amount)
  values(c.id,c.organization_id,nullif(left(btrim(coalesce(p_reason_code,'')),40),''),left(btrim(p_reason),500),v_amount)
  returning id into v_id;

  update public.claims_v1 set status='denied',updated_at=now() where id=c.id;
  insert into public.claim_events_v1(claim_id,organization_id,event_type,from_status,to_status,note,actor_id)
  values(c.id,c.organization_id,'denial_created',c.status,'denied',left(btrim(p_reason),500),auth.uid());
  insert into public.audit_events_v1(organization_id,actor_id,action,entity_type,entity_id,metadata)
  values(c.organization_id,auth.uid(),'denial.created','denial',v_id,jsonb_build_object('claim_id',c.id,'amount',v_amount));
  return jsonb_build_object('id',v_id,'claim_id',c.id,'status','open','amount',v_amount);
end
$$;

create or replace function public.payment_register_v1(p_org uuid,p_ars uuid,p_paid_on date,p_amount numeric,p_reference text,p_allocations jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_payment uuid;
  v_sum numeric := 0;
  a jsonb;
  v_claim uuid;
  v_alloc numeric;
  c public.claims_v1;
  v_total_alloc numeric;
begin
  if p_org not in (select app.visible_org_ids_v1()) then raise exception 'Sin acceso.' using errcode='42501'; end if;
  if app.role_for_org_v1(p_org) not in ('super_admin','admin','glosas') then raise exception 'Rol sin permiso para registrar pagos.' using errcode='42501'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Monto de pago inválido.' using errcode='22023'; end if;
  if jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations)=0 then raise exception 'Debe distribuir el pago.' using errcode='22023'; end if;

  for a in select * from jsonb_array_elements(p_allocations) loop
    v_claim:=(a->>'claim_id')::uuid;
    v_alloc:=(a->>'amount')::numeric;
    if v_alloc<=0 then raise exception 'Distribución inválida.' using errcode='22023'; end if;
    select * into c from public.claims_v1 where id=v_claim for update;
    if c.id is null or c.organization_id<>p_org or c.ars_id<>p_ars or c.status not in ('submitted','observed','denied','paid') then
      raise exception 'Reclamación inválida para este pago.' using errcode='23514';
    end if;
    if not app.can_claim_v1(c.organization_id,c.provider_id,true) then raise exception 'Sin acceso a una reclamación.' using errcode='42501'; end if;
    select coalesce(sum(pa.amount),0) into v_total_alloc from public.payment_allocations_v1 pa where pa.claim_id=c.id;
    if v_total_alloc+v_alloc>c.amount+0.01 then raise exception 'El pago excede el monto de una reclamación.' using errcode='23514'; end if;
    v_sum:=v_sum+v_alloc;
  end loop;
  if abs(v_sum-p_amount)>0.01 then raise exception 'La distribución no coincide con el pago.' using errcode='23514'; end if;

  insert into public.payments_v1(organization_id,ars_id,paid_on,amount,reference)
  values(p_org,p_ars,p_paid_on,p_amount,nullif(left(btrim(coalesce(p_reference,'')),120),''))
  returning id into v_payment;

  for a in select * from jsonb_array_elements(p_allocations) loop
    v_claim:=(a->>'claim_id')::uuid;
    v_alloc:=(a->>'amount')::numeric;
    insert into public.payment_allocations_v1(payment_id,claim_id,amount) values(v_payment,v_claim,v_alloc);
    select coalesce(sum(pa.amount),0) into v_total_alloc from public.payment_allocations_v1 pa where pa.claim_id=v_claim;
    select * into c from public.claims_v1 where id=v_claim;
    if v_total_alloc>=c.amount-0.01 then
      update public.claims_v1 set status='paid',updated_at=now() where id=v_claim and status<>'closed';
      insert into public.claim_events_v1(claim_id,organization_id,event_type,from_status,to_status,note,actor_id)
      values(v_claim,p_org,'payment_applied',c.status,'paid','Pago completado',auth.uid());
    else
      insert into public.claim_events_v1(claim_id,organization_id,event_type,note,actor_id)
      values(v_claim,p_org,'payment_partial','Pago parcial aplicado',auth.uid());
    end if;
  end loop;

  insert into public.audit_events_v1(organization_id,actor_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),'payment.registered','payment',v_payment,jsonb_build_object('amount',p_amount,'allocations',jsonb_array_length(p_allocations)));
  return jsonb_build_object('id',v_payment,'amount',p_amount);
end
$$;

create or replace function public.dashboard_v1(p_org uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
  if p_org not in (select app.visible_org_ids_v1()) then raise exception 'Sin acceso.' using errcode='42501'; end if;
  return jsonb_build_object(
    'claims', coalesce((select jsonb_object_agg(status,n) from (select status,count(*) n from public.claims_v1 where organization_id=p_org group by status) s),'{}'::jsonb),
    'amounts', jsonb_build_object(
      'captured',coalesce((select sum(amount) from public.claims_v1 where organization_id=p_org),0),
      'paid',coalesce((select sum(pa.amount) from public.payment_allocations_v1 pa join public.claims_v1 c on c.id=pa.claim_id where c.organization_id=p_org),0),
      'denied_open',coalesce((select sum(denied_amount) from public.denials_v1 where organization_id=p_org and status in ('open','appealed')),0)
    ),
    'aging', jsonb_build_object(
      'over_30_days',coalesce((select count(*) from public.claims_v1 where organization_id=p_org and status not in ('paid','closed') and service_date<current_date-30),0)
    )
  );
end
$$;

create policy submissions_v1_select on public.submissions_v1 for select to authenticated
using(organization_id in(select app.visible_org_ids_v1()));
create policy submission_claims_v1_select on public.submission_claims_v1 for select to authenticated
using(exists(select 1 from public.submissions_v1 s where s.id=submission_id and s.organization_id in(select app.visible_org_ids_v1())));
create policy payments_v1_select on public.payments_v1 for select to authenticated
using(organization_id in(select app.visible_org_ids_v1()));
create policy allocations_v1_select on public.payment_allocations_v1 for select to authenticated
using(exists(select 1 from public.claims_v1 c where c.id=claim_id and app.can_claim_v1(c.organization_id,c.provider_id,false)));
create policy denials_v1_select on public.denials_v1 for select to authenticated
using(exists(select 1 from public.claims_v1 c where c.id=claim_id and app.can_claim_v1(c.organization_id,c.provider_id,false)));

revoke all on function public.submission_create_v1(uuid[]),public.denial_create_v1(uuid,text,text,numeric),
  public.payment_register_v1(uuid,uuid,date,numeric,text,jsonb),public.dashboard_v1(uuid) from public,anon;
grant execute on function public.submission_create_v1(uuid[]),public.denial_create_v1(uuid,text,text,numeric),
  public.payment_register_v1(uuid,uuid,date,numeric,text,jsonb),public.dashboard_v1(uuid) to authenticated;
