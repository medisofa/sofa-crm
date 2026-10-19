-- Evidencia reproducible del sprint técnico.
-- El harness se ejecutó en Neon, schema aislado sofa_sprint_20261018.
-- No es una migración de producción.
-- Resultado 2026-10-18: 11/11 PASS.
select * from sofa_sprint_20261018.run_sprint_tests('run-20261018-2210');

-- Evidencia de flujo y eventos
select c.id,c.folio,c.patient_ref,c.amount,c.status,count(e.id) event_count
from sofa_sprint_20261018.claims c
left join sofa_sprint_20261018.claim_events e on e.claim_id=c.id
group by c.id,c.folio,c.patient_ref,c.amount,c.status
order by c.id;
