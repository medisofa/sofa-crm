-- 225 · Aislamiento DEMO en honorarios y facturación automática
begin;

create or replace function public.generate_monthly_fees(p_period date)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  v_period date := date_trunc('month', p_period)::date;
  v_n integer;
begin
  if auth.uid() is not null and not app.is_staff(array['super_admin','admin']) then
    raise exception 'Solo Super Admin o Administrador SOFA' using errcode='42501';
  end if;

  insert into public.sofa_fees (
    organization_id, fee_rule_id, source_type, source_id, period, base_amount, rate, amount
  )
  select fr.organization_id, fr.id, 'cuota', null, v_period, d.days, null,
         case when d.days >= d.month_days
              then fr.fixed_amount
              else round(fr.fixed_amount * d.days / d.month_days, 2)
         end
    from public.fee_rules fr
    join public.organizations o on o.id=fr.organization_id
    cross join lateral (
      select (upper(x)-lower(x)) as days,
             ((v_period + interval '1 month')::date - v_period) as month_days
      from (
        select fr.valid_during * daterange(v_period,(v_period + interval '1 month')::date) as x
      ) q
    ) d
   where fr.basis='cuota_mensual'
     and fr.valid_during && daterange(v_period,(v_period + interval '1 month')::date)
     and d.days>0
     and o.status in ('activo','incorporacion')
     and coalesce(o.is_demo,false)=false
     and (auth.uid() is null or o.operator_id in (select app.my_operator_ids()))
  on conflict on constraint sofa_fees_source_uq do nothing;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.generate_sofa_invoices(p_period date,p_due_days integer default 15)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  v_period date := date_trunc('month', p_period)::date;
  r record;
  v_inv uuid;
  v_n integer := 0;
begin
  if auth.uid() is not null and not app.is_staff(array['super_admin','admin']) then
    raise exception 'Solo Super Admin o Administrador SOFA' using errcode='42501';
  end if;

  perform public.generate_monthly_fees(v_period);

  for r in
    select f.organization_id,sum(f.amount) as total
      from public.sofa_fees f
      join public.organizations o on o.id=f.organization_id
     where f.period<=v_period
       and f.sofa_invoice_id is null
       and coalesce(o.is_demo,false)=false
       and (auth.uid() is null or o.operator_id in (select app.my_operator_ids()))
     group by f.organization_id
    having sum(f.amount)>0
  loop
    insert into public.sofa_invoices(organization_id,period,issued_on,due_on,total)
    values(r.organization_id,v_period,current_date,current_date+p_due_days,r.total)
    returning id into v_inv;

    update public.sofa_fees
       set sofa_invoice_id=v_inv
     where organization_id=r.organization_id
       and period<=v_period
       and sofa_invoice_id is null;

    v_n:=v_n+1;
  end loop;

  return v_n;
end $$;

commit;
