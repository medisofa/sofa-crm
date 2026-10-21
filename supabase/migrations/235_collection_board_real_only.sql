-- 235 · Aislamiento DEMO en Cartera escalonada
-- Vista global: solo clientes reales. Contexto explícito: respeta el cliente elegido, incluido DEMO.
begin;

CREATE OR REPLACE FUNCTION public.collection_board(p_org uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform app.collection_access(p_org, false);
  return (with lots as (
      select b.*, app.collection_stage(b.age_days) stage, coalesce(o.trade_name, o.legal_name) client, a.name ars, pr.full_name provider,
             (select max(ca.done_on) from public.collection_actions ca where b.id = any (ca.submission_ids) and ca.kind = app.collection_stage(b.age_days)) stage_done_on,
             (select jsonb_build_object('kind', ca.kind, 'done_on', ca.done_on, 'note', ca.note, 'promise_date', ca.promise_date) from public.collection_actions ca
               where b.id = any (ca.submission_ids) order by ca.done_on desc, ca.created_at desc limit 1) last_action
        from public.v_submission_balance b join public.organizations o on o.id = b.organization_id
        left join public.ars a on a.id = b.ars_id left join public.providers pr on pr.id = b.provider_id
       where b.submitted_on is not null and b.balance > 0.005 and b.status not in ('rechazada','cerrada')
         and (p_org is null or b.organization_id = p_org)
         and (p_org is not null or b.organization_id in (select id from public.sofa_real_client_organizations))
         and b.organization_id in (select app.visible_org_ids())),
    dso as (
      select b.ars_id, round(avg((select max(p.paid_on) from public.payment_allocations pa join public.payments p on p.id = pa.payment_id where pa.submission_id = b.id) - b.submitted_on))::int days, count(*) lots
        from public.v_submission_balance b
       where b.submitted_on is not null and b.claimed > 0 and b.balance <= 0.005 and b.paid > 0
         and (p_org is null or b.organization_id = p_org)
         and (p_org is not null or b.organization_id in (select id from public.sofa_real_client_organizations))
         and b.organization_id in (select app.visible_org_ids())
         and (select max(p.paid_on) from public.payment_allocations pa join public.payments p on p.id = pa.payment_id where pa.submission_id = b.id) >= current_date - 180
       group by b.ars_id)
    select jsonb_build_object(
      'lots', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'folio', folio, 'client', client, 'organization_id', organization_id, 'ars', ars, 'ars_id', ars_id,
                 'provider', provider, 'period', period, 'submitted_on', submitted_on, 'age_days', age_days, 'claimed', claimed, 'paid', paid, 'balance', balance,
                 'stage', stage, 'stage_label', app.collection_stage_label(stage), 'stage_done_on', stage_done_on, 'pending', stage <> 'seguimiento' and stage_done_on is null,
                 'last_action', last_action) order by age_days desc) from lots), '[]'::jsonb),
      'by_ars', coalesce((select jsonb_agg(jsonb_build_object('ars_id', l.ars_id, 'ars', l.ars, 'organization_id', l.organization_id, 'client', l.client, 'lots', l.n, 'balance', l.bal,
                 'max_age', l.max_age, 'pending', l.pend, 'dso', d.days, 'dso_lots', d.lots) order by l.bal desc)
                 from (select ars_id, ars, organization_id, client, count(*) n, sum(balance) bal, max(age_days) max_age, count(*) filter (where stage <> 'seguimiento' and stage_done_on is null) pend
                         from lots group by 1, 2, 3, 4) l left join dso d on d.ars_id = l.ars_id), '[]'::jsonb),
      'totals', (select jsonb_build_object('balance', coalesce(sum(balance), 0), 'lots', count(*), 'over_90', coalesce(sum(balance) filter (where age_days > 90), 0),
                   'pending_actions', count(*) filter (where stage <> 'seguimiento' and stage_done_on is null)) from lots),
      'can_edit', app.is_staff(array['super_admin','admin','glosas'])));
end
$function$;

commit;
