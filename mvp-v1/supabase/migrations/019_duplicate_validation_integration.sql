-- SOFA · Integración final del motor anti-duplicados con validate_submission.
-- Conserva la validación previa como base y corrige solo la regla de duplicados
-- para respetar revisiones humanas registradas en claim_duplicate_reviews.

do $$
begin
  if to_regprocedure('public.validate_submission_pre_duplicate(uuid,boolean)') is null then
    alter function public.validate_submission(uuid,boolean) rename to validate_submission_pre_duplicate;
  end if;
end
$$;

create or replace function public.validate_submission(p_submission uuid, p_save boolean default true)
returns jsonb
language plpgsql
set search_path=''
as $$
declare
  v_base jsonb;
  v_items jsonb;
  v_item jsonb;
  v_out jsonb := '[]'::jsonb;
  v_n int;
  v_blocked int;
  v_ok_count int;
  v_passed int;
  v_total int;
  v_critical_ok boolean;
  v_org uuid;
begin
  select organization_id into v_org from public.submissions where id=p_submission;
  if v_org is null then
    raise exception 'Radicación no encontrada o sin acceso' using errcode='P0002';
  end if;

  v_base := public.validate_submission_pre_duplicate(p_submission,false);
  v_items := coalesce(v_base->'items','[]'::jsonb);
  select count(*) into v_n from public.service_lines where submission_id=p_submission;

  select count(distinct line_id) into v_blocked
  from public.claim_duplicate_candidates(null,p_submission)
  where blocks_radicacion;

  v_ok_count := greatest(v_n - coalesce(v_blocked,0),0);

  for v_item in select value from jsonb_array_elements(v_items)
  loop
    if v_item->>'code'='dup' then
      v_item := jsonb_build_object(
        'code','dup',
        'label','Sin posibles duplicados de alto riesgo sin resolver',
        'ok',v_n>0 and v_blocked=0,
        'ok_count',v_ok_count,
        'n',v_n,
        'critical',true
      );
    end if;
    v_out := v_out || jsonb_build_array(v_item);
  end loop;

  select
    count(*) filter(where (e->>'ok')::boolean),
    count(*),
    bool_and((e->>'ok')::boolean or not (e->>'critical')::boolean)
  into v_passed,v_total,v_critical_ok
  from jsonb_array_elements(v_out) e;

  v_base := jsonb_set(v_base,'{items}',v_out,true);
  v_base := jsonb_set(v_base,'{passed}',to_jsonb(v_passed),true);
  v_base := jsonb_set(v_base,'{total}',to_jsonb(v_total),true);
  v_base := jsonb_set(v_base,'{critical_ok}',to_jsonb(coalesce(v_critical_ok,false)),true);
  v_base := jsonb_set(v_base,'{duplicate_blocking}',to_jsonb(coalesce(v_blocked,0)),true);

  if p_save then
    insert into public.validation_runs(submission_id,organization_id,passed,total,critical_ok,results)
    values(p_submission,v_org,v_passed,v_total,coalesce(v_critical_ok,false),v_out);
  end if;

  return v_base;
end
$$;

revoke all on function public.validate_submission(uuid,boolean) from public,anon;
grant execute on function public.validate_submission(uuid,boolean) to authenticated;
