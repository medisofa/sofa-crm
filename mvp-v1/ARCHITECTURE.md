# SOFA MVP v1 — arquitectura de producción

## 1. Evaluación del sistema actual
La aplicación actual ya resuelve mucho más que un MVP: frontend estático modular, Supabase Auth/Postgres/RLS/Storage, captura rápida, reclamaciones por servicio, retiros, radicación, documentos, glosas, pagos, honorarios, habilitación, agenda, pacientes, historia clínica, conciliación y portales. La guía de pendientes añade avisos al paciente y casos de servicio.

Fortalezas: dominio rico, trabajo por reclamación individual, RLS, MFA, roles separados y ausencia de secretos administrativos en el navegador.

Riesgos antes de GO: autorización multicliente todavía requiere remediación y pruebas E2E reales; backup restaurable no demostrado; la superficie funcional es muy grande para certificar como MVP; muchas funciones SECURITY DEFINER amplían la superficie de revisión; el frontend vanilla creció hasta decenas de módulos.

Conclusión: no reescribir producción. Construir un núcleo v1 aislado, validar y migrar por estrangulamiento ("strangler pattern"). El MVP mínimo debe concentrarse en ciclo de ingreso, no en historia clínica o marketing.

## 2. Equipo de agentes especializados
- Arquitecto Principal: límites de dominio, ADR, escalabilidad.
- Ingeniero Backend/Postgres: modelo relacional, RPC transaccionales, índices.
- Ingeniero Seguridad/IAM: RLS, MFA, multitenancy, least privilege, threat model.
- Ingeniero Frontend: UX de médico/secretaria/SOFA y accesibilidad.
- Ingeniero DevOps/SRE: CI/CD, backups, observabilidad, rollback.
- QA/Automation: pruebas unitarias, integración, JWT/RLS, E2E.
- Ingeniero de Datos/BI: KPIs financieros y reconciliación.
- Especialista RCM/ARS: reglas de reclamación, glosas y radicación.
- Privacy/Compliance: minimización, retención y trazabilidad de datos de salud.

Estos son roles de diseño aplicados a esta arquitectura; no representan procesos externos autónomos ejecutándose fuera de esta sesión.

## 3. Arquitectura objetivo
Cliente web -> Next.js/BFF -> Supabase Auth + PostgREST/RPC -> PostgreSQL/RLS
                                      |-> Storage privado
                                      |-> jobs/cron/Edge Functions
                                      |-> audit_events

Principios:
1. Modular monolith primero; microservicios solo al demostrar un cuello de botella.
2. organization_id en toda entidad tenant.
3. RLS es la frontera de autorización, no el menú.
4. La API usa JWT del usuario; service_role queda fuera del request path ordinario.
5. Operaciones críticas son RPC transaccionales e idempotentes.
6. Documentos en Storage; en Postgres solo metadatos.
7. Auditoría append-only sin copiar PHI innecesaria.
8. Paginación por cursor o rango con índices compuestos.
9. Separar lecturas analíticas de escrituras OLTP cuando el volumen lo exija.
10. Capacidad para particionar audit/events por fecha sin cambiar contratos API.

## 4. Dominios del MVP
INCLUIR:
- Identidad, organización y roles.
- Catálogos ARS/procedimientos/tarifas.
- Captura de reclamación.
- Estado y custodia de la reclamación.
- Documentos.
- Radicación.
- Glosa.
- Pago y distribución.
- Dashboard financiero básico.
- Auditoría.

POSTERGAR DEL MVP:
- Historia clínica.
- Portal del paciente.
- Marketing/inteligencia de mercado.
- CRM comercial avanzado.
- Conciliación bancaria automática.
- e-CF.
- Casos de servicio no ligados al ciclo de ingresos.
Estos pueden convivir en la plataforma actual hasta su migración.

## 5. Estructura
```
mvp-v1/
  src/
    app/
      api/
        health/
        v1/claims/
      capture/
      claims/
    lib/
      auth/
      supabase/
      validation/
  supabase/
    migrations/
      001_core.sql
  .env.example
  next.config.mjs
  package.json
  tsconfig.json
```

Evolución propuesta:
```
src/features/
  auth/
  organizations/
  claims/
  submissions/
  denials/
  payments/
  documents/
  dashboard/
src/components/
src/lib/
tests/
  unit/
  integration/
  e2e/
```

## 6. API v1
- GET /api/health
- GET /api/v1/claims?organization_id=&status=&page=&page_size=
- POST /api/v1/claims
- POST /api/v1/claims/:id/transition
Próximos endpoints antes del piloto:
- GET /api/v1/claims/:id
- POST /api/v1/claims/:id/documents
- POST /api/v1/submissions
- POST /api/v1/submissions/:id/submit
- POST /api/v1/denials
- POST /api/v1/payments
- POST /api/v1/payments/:id/allocations
- GET /api/v1/dashboard
- GET /api/v1/me/context

## 7. Roles mínimos
- client: médico/dueño.
- capturer: secretaria limitada a médicos asignados.
- billing: captura/radicación.
- operations: recepción/validación.
- glosas: post-radicación, pagos y glosas.
- auditor: lectura/validación.
- admin/super_admin: gobierno.

Los usuarios externos tienen una organización principal. Cualquier segunda organización requiere excepción explícita con vencimiento y revocación.

## 8. Modelo de datos
organizations_v1 -> organization_users_v1
organizations_v1 -> providers_v1 -> capturer_scopes_v1
organizations_v1 -> tariffs_v1 <- ars_v1/procedures_v1
organizations_v1 -> claims_v1 -> claim_events_v1
                         |-> claim_documents_v1
                         |-> submission_claims_v1 -> submissions_v1
                         |-> payment_allocations_v1 -> payments_v1
                         |-> denials_v1
organization -> audit_events_v1

## 9. Escalabilidad a millones
No se diseña para "millones" agregando microservicios de inmediato. Se preservan caminos de escalado:
- UUID y claves/indexes por tenant.
- consultas siempre acotadas por organización, estado o fecha;
- connection pooling administrado;
- índices compuestos y EXPLAIN en queries calientes;
- Storage para blobs;
- procesos asíncronos fuera del request;
- rate limits en API/Edge;
- CDN para assets;
- read replicas/warehouse para BI cuando la carga lo requiera;
- partición temporal de audit/events si su crecimiento lo justifica;
- API versionada para separar frontend de evolución de DB.

## 10. Seguridad
Amenazas prioritarias:
- fuga entre clientes;
- elevación de rol;
- ejecución de SECURITY DEFINER sin controles;
- enlace/token de documento expuesto;
- exportación masiva;
- cuentas staff sin MFA;
- secretos en frontend/logs.

Controles:
- RLS y pruebas A/B;
- MFA staff;
- home org + excepción temporal;
- signed URLs de corta vida;
- revoke por defecto;
- funciones sensibles con search_path vacío;
- no service_role en browser;
- CSP/headers;
- logs sin PHI;
- rotación de secretos;
- backup + restore drill.

## 11. CI/CD recomendado
PR -> typecheck -> lint -> unit -> DB migration lint -> integration en Supabase aislado -> E2E roles -> preview.
Merge a main -> staging -> smoke tests -> aprobación manual -> producción -> smoke/rollback.

Producción debe desplegar por migraciones versionadas, nunca copiando SQL ad hoc desde una guía.

## 12. SLO inicial
Antes de prometer escala:
- disponibilidad objetivo inicial 99.9%;
- p95 API < 500 ms para lecturas paginadas normales;
- RPO objetivo <= 24 h al inicio, luego <= 1 h si el negocio lo exige;
- RTO documentado y probado;
- 0 accesos cross-tenant tolerados.

## 13. Criterio de MVP GO
1. Backup actual y restauración comprobada.
2. Aislamiento tenant con JWT real.
3. MFA staff.
4. Captura -> recepción -> validación -> radicación -> pago o glosa -> cierre.
5. Storage privado probado A/B.
6. Auditoría y rollback.
7. Piloto de un cliente con datos de prueba antes de datos reales.

## 14. Estrategia de migración
Fase A: correr mvp-v1 sobre entorno aislado.
Fase B: importar catálogos y un cliente ficticio.
Fase C: E2E multirol.
Fase D: piloto paralelo con la app actual.
Fase E: migrar por dominio, no big-bang.
