create function public.claim_authorization_review()
returns table (
  line_id uuid, other_line_id uuid, folio text, other_folio text,
  service_date date, other_service_date date, different_patient boolean
)
language sql stable security invoker
set search_path = ''
as $$
  with lines as (
    select l.id, l.organization_id, s.ars_id, l.claim_folio, l.service_date,
           l.patient_id, nullif(upper(regexp_replace(l.authorization_number, '[[:space:]-]+', '', 'g')), '') authorization
    from public.service_lines l
    join public.submissions s on s.id = l.submission_id and s.organization_id = l.organization_id
    join public.organizations o on o.id = l.organization_id
    where o.is_demo is false and l.claim_status is distinct from 'anulada_duplicado'
      and l.patient_id is not null
  )
  select a.id, b.id, a.claim_folio, b.claim_folio, a.service_date, b.service_date,
         a.patient_id <> b.patient_id
  from lines a
  join lines b on a.id < b.id and a.organization_id = b.organization_id
    and a.authorization = b.authorization
    and ((a.patient_id = b.patient_id and a.service_date = b.service_date)
         or (a.patient_id <> b.patient_id and a.ars_id = b.ars_id))
  order by a.claim_folio, b.claim_folio, a.id, b.id;
$$;

revoke execute on function public.claim_authorization_review() from public, anon;
grant execute on function public.claim_authorization_review() to authenticated;
