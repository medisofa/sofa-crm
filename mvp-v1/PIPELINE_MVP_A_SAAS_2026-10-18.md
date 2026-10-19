# SOFA — Pipeline multi-agente MVP → SaaS
Fecha: 2026-10-18
Rama evaluada/construida: architecture/mvp-production-v1
Producción Supabase: bpwjhgpzhzhiocoxrvzq
Neon: mute-river-42539854 / branch production
Estado: análisis y construcción aislada. CERO despliegues a producción.

## Agentes aplicados
1. Arquitecto / Auditor Full-Stack
2. Product & Market Strategist
3. Value Proposition / RCM Specialist
4. SaaS Architecture & Monetization
5. DevOps / SRE / Security
6. QA / Test Automation
7. Privacy & Compliance

Nota: estos son roles técnicos aplicados dentro de esta ejecución; no se invocaron modelos externos Claude/Gemini.

## Fase 1 — Auditoría actual

### GitHub
El sistema actual ya supera un MVP: frontend estático modular con Supabase, Auth, RLS, Storage, MFA y decenas de módulos de CRM, RCM, pacientes, agenda, glosas, pagos, honorarios, habilitación, BI y operación.

Nueva base creada en `mvp-v1/`:
- Next.js + TypeScript
- API versionada
- Supabase SSR/Auth
- modelo tenant-first
- migraciones 001–005
- captura, reclamaciones, radicación, glosas, pagos, dashboard
- MFA staff y Storage privado
- CI inicial

### Supabase real
Proyecto activo/healthy, PostgreSQL 17.6.1.
Inventario observado:
- organizations: 6
- profiles: 16
- organization_users: 19
- providers: 5
- ars: 23
- tariffs: 172
- service_lines: 240
- claim_status_history: 660
- payment_line_allocations: 336
- audit_log: 1241
- perf_metrics: 337

El schema actual contiene más de 170 tablas públicas, señal de que la plataforma acumuló demasiada superficie para certificar como MVP inicial.

Security Advisor: 98 tablas con RLS habilitado sin políticas. Esto no prueba una fuga (puede significar deny-all), pero exige clasificación explícita: INTENCIONALMENTE CERRADA / REQUIERE POLICY / NO EXPUESTA.

La lista nativa de migraciones de Supabase solo reporta 062 y 063, mientras el sistema mantiene su propio `app.schema_migrations`. Hay dos fuentes de verdad de migración: deuda técnica crítica para producción.

### Neon
Existe proyecto SoFa con branch default `production`. Contiene únicamente esquema de ensayo `sofa_test`:
claims, exceptions, home_org, memberships, organizations, role_identity, test_environment.
Debe considerarse sandbox de pruebas, NO réplica/copia certificada de producción.

## Fase 2 — Nicho e ICP

### Posicionamiento recomendado
No competir como HIS/ERP clínico generalista.
Categoría: Revenue Cycle Management (RCM) as a Service + SaaS para prestadores independientes de República Dominicana.

### ICP inicial
1. Médico especialista independiente con secretaria, múltiples ARS y facturación recurrente.
2. Consultorio/centro pequeño-mediano con 2–20 médicos y sin departamento formal de RCM.
3. Centros con cartera vencida, glosas recurrentes o alta dependencia de Excel/WhatsApp.
4. Expansión posterior: grupos médicos, centros diagnósticos y clínicas pequeñas.

### Job-to-be-done
“Quiero saber qué reclamé, qué me pagaron, qué rechazaron y qué debo hacer hoy para cobrar, sin convertirme en experto administrativo.”

### Diferenciación
Competir por ciclo de ingresos y servicio administrado, no por cantidad de módulos clínicos.

## Fase 3 — Valor agregado prioritario
P0:
- Bandeja operativa única por excepción
- Preventor de glosas antes de radicar
- Estado de dinero por reclamación
- SLA y aging por ARS
- Portal simple del médico
- captura ultrarrápida de secretaria

P1:
- conciliación de remesas
- recomendación de causa raíz de glosa
- benchmarking anonimizado por especialidad/ARS
- renegociación de tarifas con evidencia
- incorporación guiada y checklist contractual

P2:
- automatizaciones/IA con aprobación humana
- APIs/integraciones con terceros
- e-CF y contabilidad solo donde aporten RCM

## Fase 4 — SaaS

### Multi-tenancy
Un schema compartido con `organization_id` + RLS.
Usuario externo: 1 organización principal.
Acceso adicional: excepción temporal registrada y revocable.
Staff SOFA: alcance explícito + MFA AAL2.

### Planes sugeridos
No fijar precios finales sin entrevistas y unit economics.
- Starter: médico independiente, captura + reclamaciones + dashboard.
- Growth: varios médicos, glosas, pagos, documentos, SLA.
- Managed RCM: software + operación SOFA, precio base + variable por cobro/facturación.
- Enterprise: clínicas/grupos, SSO/integraciones/SLA.

El plan Managed RCM es la ventaja estratégica porque une software con la operación real de SOFA.

### North Star
Monto efectivamente cobrado por clientes a través de reclamaciones gestionadas por SOFA.

KPIs:
- días servicio→radicación
- first-pass acceptance
- tasa y monto de glosa
- días radicación→pago
- % cartera >30/60/90
- recovery rate
- tiempo de captura
- claims por operador/día
- expansión de MRR y churn

## Fase 5 — DevOps / producción

### Modelo de ramas
main = producción
staging = preproducción
feature/* = cambio funcional
architecture/mvp-production-v1 = núcleo nuevo mientras se valida

### CI/CD
PR:
typecheck → build → migration lint → Supabase aislado → tests RLS/JWT → E2E → preview.
Merge:
staging → smoke → aprobación humana → producción → smoke/rollback.

### Backups
Antes de GO:
- PostgreSQL/Auth
- bytes de Storage
- checksums
- restore drill
- RPO/RTO documentados

### Observabilidad
- p50/p95/p99 endpoints
- errores por RPC
- query latency
- lock/deadlock
- tamaño e índices
- auth failures
- cross-tenant denial events
- jobs fallidos
- Storage errors

## Bloqueadores actuales
1. Backup restaurable no demostrado.
2. Aislamiento tenant/JWT real no demostrado de punta a punta.
3. Corrección multicliente nueva no desplegada ni probada en staging fiel.
4. Storage A/B no probado.
5. CI del nuevo MVP definido pero sin run exitoso confirmado.
6. Doble fuente de migraciones.
7. Scope funcional actual demasiado grande para un GO rápido.

## Decisión
Mantener producción intacta.
Usar `mvp-v1` como núcleo candidato.
No añadir módulos no esenciales hasta completar:
1) staging aislado,
2) migraciones,
3) seed sintético,
4) pruebas multirol,
5) flujo claim end-to-end,
6) backup/restore,
7) piloto controlado.
