-- SOFA · Optimización del detector preventivo de reclamaciones duplicadas
-- La infraestructura funcional (claim_duplicate_candidates, review_claim_duplicate y
-- claim_duplicate_reviews) ya existe en producción. Esta migración solo agrega un índice
-- compatible con la regla solicitada: NSS + fecha de servicio + fecha de autorización.

create index if not exists service_lines_duplicate_probe_idx
on public.service_lines (
  organization_id,
  (regexp_replace(lower(trim(coalesce(member_number,''))),'[^0-9a-z]','','g')),
  service_date,
  authorization_date
)
where nullif(trim(coalesce(member_number,'')),'') is not null
  and authorization_date is not null;
