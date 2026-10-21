-- 216 · Visibilidad operativa de reclamaciones antes de radicación
begin;

create or replace function public.history_search(
  p_org uuid default null::uuid, p_q text default null::text, p_ars uuid default null::uuid,
  p_provider uuid default null::uuid, p_from date default null::date, p_to date default null::date,
  p_status text default null::text, p_min numeric default null::numeric, p_max numeric default null::numeric,
  p_archived_only boolean default false, p_limit integer default 50, p_after jsonb default null::jsonb
) returns jsonb
language plpgsql stable security definer
set search_path='' set plan_cache_mode='force_custom_plan' set jit='off'
as $$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
  v_q text:=nullif(trim(coalesce(p_q,'')),'');
  v_rows jsonb; v_n integer; v_more boolean; v_last jsonb;
  v_ad date; v_aid uuid; v_esc text;
begin
  if auth.uid() is null or not exists (
    select 1 from public.organization_users ou
    join public.profiles p on p.id=ou.user_id and p.is_active
    where ou.user_id=auth.uid() and ou.is_active
  ) then raise exception 'Inicie sesión para buscar en el histórico.' using errcode='42501'; end if;

  if v_q is not null and length(v_q)<3 then raise exception 'Escriba al menos 3 caracteres para buscar (nombre, folio, afiliado o autorización).' using errcode='22023'; end if;
  if v_q is not null and length(v_q)>80 then raise exception 'La búsqueda no puede pasar de 80 caracteres.' using errcode='22023'; end if;
  if p_from is not null and p_to is not null and p_to<p_from then raise exception 'La fecha final no puede ser anterior a la inicial.' using errcode='22023'; end if;
  if p_from is not null and p_to is not null and p_to-p_from>3660 then raise exception 'El rango de fechas no puede pasar de 10 años. Divida la búsqueda.' using errcode='22023'; end if;
  if p_min is not null and p_max is not null and p_max<p_min then raise exception 'El monto máximo no puede ser menor que el mínimo.' using errcode='22023'; end if;
  if p_status is not null and not exists(select 1 from public.claim_statuses cs where cs.code=p_status) then
    raise exception 'Estado de reclamación desconocido (%). Elija uno de la lista.',p_status using errcode='22023';
  end if;

  v_esc:=replace(replace(replace(coalesce(v_q,''),'\','\\'),'%','\%'),'_','\_');
  if p_after is not null then
    begin v_ad:=(p_after->>'d')::date; v_aid:=(p_after->>'id')::uuid;
    exception when others then raise exception 'La marca de página no es válida: vuelva a buscar desde la primera página.' using errcode='22023'; end;
  end if;

  if p_org is not null and not exists(
    select 1 from public.organizations o where o.id=p_org and o.id in(select app.visible_org_ids())
  ) then raise exception 'Ese cliente no existe o no está entre los que usted puede ver.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(x.j order by x.service_date desc,x.id desc),'[]'::jsonb),count(*)
    into v_rows,v_n
    from (
      select l.service_date,l.id,
             jsonb_build_object(
               'id',l.id,'folio',l.claim_folio,'organization_id',l.organization_id,
               'client',coalesce(o.trade_name,o.legal_name),'service_date',l.service_date,
               'patient',l.patient_name,'member_number',l.member_number,'authorization_number',l.authorization_number,
               'claim_status',l.claim_status,'amount',l.amount,'submission_id',l.submission_id,
               'submission_folio',s.folio,
               'period',coalesce(s.period,date_trunc('month',l.service_date)::date),
               'ars_id',coalesce(l.ars_id,s.ars_id),
               'provider_id',coalesce(l.provider_id,s.provider_id),
               'archived',app.period_archived(l.organization_id,coalesce(s.period,date_trunc('month',l.service_date)::date))
             ) j
        from public.service_lines l
        left join public.submissions s on s.id=l.submission_id
        join public.organizations o on o.id=l.organization_id
       where l.organization_id in(select app.visible_org_ids())
         and (p_org is null or l.organization_id=p_org)
         and (p_ars is null or coalesce(l.ars_id,s.ars_id)=p_ars)
         and (p_provider is null or coalesce(l.provider_id,s.provider_id)=p_provider)
         and (p_from is null or l.service_date>=p_from)
         and (p_to is null or l.service_date<=p_to)
         and (p_status is null or l.claim_status=p_status)
         and (p_min is null or l.amount>=p_min)
         and (p_max is null or l.amount<=p_max)
         and (
           v_q is null or l.claim_folio ilike v_esc||'%' or l.member_number=v_q
           or l.authorization_number=v_q or l.patient_doc=v_q or l.patient_name ilike '%'||v_esc||'%'
         )
         and (
           not coalesce(p_archived_only,false)
           or app.period_archived(l.organization_id,coalesce(s.period,date_trunc('month',l.service_date)::date))
         )
         and (v_ad is null or (l.service_date,l.id)<(v_ad,v_aid))
       order by l.service_date desc,l.id desc
       limit v_limit+1
    ) x;

  v_more:=v_n>v_limit;
  if v_more then
    select jsonb_agg(e.value order by e.ord) into v_rows
      from jsonb_array_elements(v_rows) with ordinality e(value,ord)
     where e.ord<=v_limit;
  end if;
  v_last:=case when jsonb_array_length(v_rows)>0
    then jsonb_build_object('d',v_rows->(jsonb_array_length(v_rows)-1)->>'service_date','id',v_rows->(jsonb_array_length(v_rows)-1)->>'id')
  end;
  return jsonb_build_object('rows',v_rows,'count',jsonb_array_length(v_rows),'limit',v_limit,'has_more',v_more,'next',case when v_more then v_last end);
end $$;

create or replace function app.weekly_summary_data(p_provider uuid,p_week_start date)
returns jsonb
language sql stable security definer set search_path=''
as $$
  select jsonb_build_object(
    'week_start',p_week_start,'last_week_from',p_week_start-7,'last_week_to',p_week_start-1,
    'provider',(select pr.full_name from public.providers pr where pr.id=p_provider),
    'claims',(select jsonb_build_object('count',count(*),'claimed',coalesce(sum(l.amount),0))
      from public.service_lines l
      left join public.submissions s on s.id=l.submission_id
      where coalesce(l.provider_id,s.provider_id)=p_provider
        and l.service_date>=p_week_start-7 and l.service_date<p_week_start),
    'collected',(select coalesce(sum(pla.amount),0)
      from public.payment_line_allocations pla
      join public.payments py on py.id=pla.payment_id
      join public.submissions s on s.id=pla.submission_id
      where s.provider_id=p_provider and pla.superseded_at is null
        and py.paid_on>=p_week_start-7 and py.paid_on<p_week_start),
    'receivable',(select jsonb_build_object(
      'balance',coalesce(sum(b.balance) filter(where b.balance>0),0),
      'overdue',coalesce(sum(b.balance) filter(where b.balance>0 and b.payment_deadline<current_date),0),
      'lotes',count(*) filter(where b.balance>0))
      from public.v_submission_balance b where b.provider_id=p_provider and b.status in ('radicada','en_auditoria_ars')),
    'glosas_due',(select count(*) from public.glosas g join public.submissions s on s.id=g.submission_id
      where s.provider_id=p_provider and g.status in ('pendiente','analizada','apelada') and g.appeal_deadline<=current_date+7),
    'next_week',(select jsonb_build_object(
      'appointments',count(*) filter(where a.status<>'cancelada'),
      'ars',count(*) filter(where a.status<>'cancelada' and a.payer_type='ars'),
      'privado',count(*) filter(where a.status<>'cancelada' and a.payer_type='privado'))
      from public.appointments a where a.provider_id=p_provider
        and a.appointment_date>=p_week_start and a.appointment_date<p_week_start+7)
  )
$$;

create or replace function public.provider_360(p_provider uuid)
returns jsonb
language plpgsql stable set search_path=''
as $$
declare p public.providers; o public.organizations; r jsonb;
begin
  select * into p from public.providers where id=p_provider;
  if not found then raise exception 'Médico no encontrado o sin acceso' using errcode='P0002'; end if;
  select * into o from public.organizations where id=p.organization_id;

  select jsonb_build_object(
    'provider',to_jsonb(p)-'created_at'-'updated_at',
    'client',jsonb_build_object('id',o.id,'legal_name',o.legal_name,'status',o.status,'tax_id',o.tax_id,'phone',o.phone,'email',o.email,'activated_at',o.activated_at),
    'clinics',coalesce((
      select jsonb_agg(x order by x) from (
        select distinct l.clinic_name x
          from public.service_lines l
          left join public.submissions s on s.id=l.submission_id
         where coalesce(l.provider_id,s.provider_id)=p_provider and l.clinic_name is not null
      ) c
    ),'[]'::jsonb),
    'secretaries',coalesce((
      select jsonb_agg(jsonb_build_object('name',c.full_name,'phone',coalesce(c.whatsapp,c.phone),'clinic',c.clinic_name,'inducted_on',c.inducted_on))
      from public.contacts c where c.provider_id=p_provider and c.contact_role='secretaria'
    ),'[]'::jsonb),
    'capturers',(select count(*) from public.capturer_scopes cs where cs.provider_id=p_provider),
    'ars',coalesce((
      select jsonb_agg(jsonb_build_object('ars',x.ars_name,'services',x.n,'from',x.vf) order by x.ars_name)
      from (
        select t.ars_name,count(*) n,min(t.valid_from) vf
        from public.v_contract_tariffs t where t.provider_id=p_provider and t.is_current group by t.ars_name
      ) x
    ),'[]'::jsonb),
    'claims',(select jsonb_build_object(
      'total',count(*),'open',count(*) filter(where c.claim_status not in ('pagada','cerrada')),
      'captured_30d',count(*) filter(where c.service_date>=current_date-30),
      'by_status',coalesce((select jsonb_object_agg(z.claim_status,z.n) from (
        select claim_status,count(*) n from public.v_claims where provider_id=p_provider group by 1
      ) z),'{}'::jsonb),
      'claimed',sum(c.claimed),'paid',sum(c.paid),'glosado',sum(c.glosado),
      'balance',sum(c.balance) filter(where c.claim_status in ('radicada','en_proceso_ars','pago_parcial','glosada','devuelta'))
    ) from public.v_claims c where c.provider_id=p_provider),
    'submissions',coalesce((
      select jsonb_agg(jsonb_build_object('id',s.id,'folio',s.folio,'ars',s.ars_name,'period',s.period,'status',s.status,'claimed',s.claimed) order by s.period desc)
      from (select * from public.v_submissions where provider_id=p_provider order by period desc limit 8) s
    ),'[]'::jsonb),
    'documents',(select count(*) from public.commercial_documents cd where cd.provider_id=p_provider and cd.status<>'anulado'),
    'onboarding',(select to_jsonb(x) from public.onboarding_summary(o.id) x)
  ) into r;
  return r;
end $$;

commit;
