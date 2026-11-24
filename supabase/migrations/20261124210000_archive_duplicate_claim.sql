-- Ya aplicado en producción y verificado el 2026-11-24.
create table app.archived_duplicate_claims (
  line_id uuid primary key,
  organization_id uuid not null,
  archived_by uuid not null,
  archived_at timestamptz not null default now(),
  reason text not null,
  claim_snapshot jsonb not null,
  document_snapshots jsonb not null
);

alter table app.archived_duplicate_claims enable row level security;
revoke all on app.archived_duplicate_claims from public, anon, authenticated;

create function public.archive_duplicate_claim(p_line uuid, p_reason text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  l public.service_lines;
  s public.submissions;
begin
  select * into l from public.service_lines where id = p_line;
  if not found or auth.uid() is null
     or not coalesce(app.can(l.organization_id, array['super_admin', 'admin']), false)
     or not coalesce(app.client_line_ok(p_line), false) then
    raise exception 'La reclamación no está disponible para archivar.' using errcode = '42501';
  end if;

  if length(trim(coalesce(p_reason, ''))) not between 10 and 500 then
    raise exception 'Indique un motivo de 10 a 500 caracteres.' using errcode = '22023';
  end if;

  select * into strict s from public.submissions
   where id = l.submission_id and organization_id = l.organization_id for update;

  select * into strict l from public.service_lines
   where id = p_line and submission_id = s.id and organization_id = s.organization_id for update;

  insert into app.archived_duplicate_claims
    (line_id, organization_id, archived_by, reason, claim_snapshot, document_snapshots)
  select l.id, l.organization_id, auth.uid(), trim(p_reason), to_jsonb(l),
         coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
    from public.documents d
   where d.entity_type = 'service_line' and d.service_line_id = l.id;

  -- The existing operation enforces editable status and preserves the audit trail.
  -- Keep the storage objects. Their document metadata is retained in the private archive.
  perform public.remove_service_line(l.id, 'Duplicado · ' || trim(p_reason));
  return jsonb_build_object('folio', l.claim_folio);
end;
$$;

revoke all on function public.archive_duplicate_claim(uuid, text) from public, anon;
grant execute on function public.archive_duplicate_claim(uuid, text) to authenticated;
