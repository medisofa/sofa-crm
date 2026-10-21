-- 214 · Integridad adicional para reclamaciones sin lote
begin;

create or replace function app.archive_guard()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare
  v_org uuid; v_per date; v_old_per date; v_new_per date; v_hit date; v_row jsonb;
begin
  if auth.uid() is null then return coalesce(new,old); end if;
  v_row := to_jsonb(coalesce(old,new));
  v_org := coalesce((v_row->>'organization_id')::uuid,null);

  if v_org is null or not exists (
    select 1 from public.period_archives a
    where a.organization_id=v_org and a.restored_at is null
  ) then return coalesce(new,old); end if;

  if tg_table_name='submissions' then
    if tg_op<>'INSERT' then v_old_per:=old.period; end if;
    if tg_op<>'DELETE' then v_new_per:=new.period; end if;
  elsif tg_table_name='service_lines' then
    if tg_op<>'INSERT' then
      v_old_per:=coalesce(
        (select s.period from public.submissions s where s.id=old.submission_id),
        date_trunc('month',old.service_date)::date
      );
    end if;
    if tg_op<>'DELETE' then
      v_new_per:=coalesce(
        (select s.period from public.submissions s where s.id=new.submission_id),
        date_trunc('month',new.service_date)::date
      );
    end if;
  elsif tg_table_name in ('payment_allocations','payment_line_allocations','glosas') then
    if tg_op<>'INSERT' then select s.period into v_old_per from public.submissions s where s.id=old.submission_id; end if;
    if tg_op<>'DELETE' then select s.period into v_new_per from public.submissions s where s.id=new.submission_id; end if;
  elsif tg_table_name='glosa_items' then
    if tg_op<>'INSERT' then
      select coalesce(s.period,date_trunc('month',l.service_date)::date)
        into v_old_per
        from public.service_lines l left join public.submissions s on s.id=l.submission_id
       where l.id=old.service_line_id;
    end if;
    if tg_op<>'DELETE' then
      select coalesce(s.period,date_trunc('month',l.service_date)::date)
        into v_new_per
        from public.service_lines l left join public.submissions s on s.id=l.submission_id
       where l.id=new.service_line_id;
    end if;
  end if;

  for v_per in select x from unnest(array[v_old_per,v_new_per]) x where x is not null loop
    if app.period_archived(v_org,v_per) then v_hit:=date_trunc('month',v_per)::date; exit; end if;
  end loop;

  if v_hit is null then return coalesce(new,old); end if;
  if app.is_staff(array['super_admin']) then
    insert into public.audit_log(user_id,organization_id,table_name,record_id,operation,old_values,new_values)
    values(auth.uid(),v_org,tg_table_name,v_row->>'id',
      case when tg_op='INSERT' then 'INSERT' when tg_op='DELETE' then 'DELETE' else 'UPDATE' end,
      null,jsonb_build_object('excepcion_periodo_archivado',to_char(v_hit,'YYYY-MM'),'operacion',tg_op));
    return coalesce(new,old);
  end if;

  raise exception 'El periodo % de este cliente está archivado (solo lectura): no se puede modificar.',
    to_char(v_hit,'MM/YYYY') using errcode='42501';
end $$;

create or replace function public.set_claim_authorization_date(p_line uuid,p_date date)
returns void
language plpgsql security definer set search_path=''
as $$
declare l public.service_lines; v_prov uuid;
begin
  select * into l from public.service_lines where id=p_line for update;
  if not found then raise exception 'Reclamación no encontrada' using errcode='P0002'; end if;
  v_prov:=coalesce(l.provider_id,(select provider_id from public.submissions where id=l.submission_id));
  if not (
    app.can(l.organization_id,array['super_admin','admin','billing','operations'])
    or v_prov in (select app.capturer_providers())
  ) then raise exception 'Sin permiso para editar esta reclamación' using errcode='42501'; end if;

  if l.claim_status not in ('pendiente_configuracion','capturada','pendiente_retiro','retirada','en_validacion','con_inconsistencia','validada','lista_para_radicar') then
    raise exception 'La reclamación ya fue radicada' using errcode='23514';
  end if;
  if p_date is null or p_date>current_date then
    raise exception 'Fecha de autorización inválida (no futura)' using errcode='22023';
  end if;

  perform set_config('app.claim_authdate','on',true);
  update public.service_lines set authorization_date=p_date where id=p_line;
  perform set_config('app.claim_authdate','',true);
end $$;

commit;
