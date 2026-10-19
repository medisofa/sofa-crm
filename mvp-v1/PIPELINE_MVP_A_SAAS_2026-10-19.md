# SOFA — Pipeline MVP → SaaS · Actualización 2026-10-19

## Estado ejecutivo
Pipeline ejecutado con evidencia real de GitHub, Supabase, Neon y mercado dominicano. No se hicieron cambios en producción ni migraciones destructivas.

## Fase 1 — Auditoría MVP
### GitHub
- Rama activa: `architecture/mvp-production-v1`.
- Núcleo nuevo: `mvp-v1/` con Next.js + TypeScript + Supabase SSR.
- Existe módulo de autoentrenamiento `/mi-usuario` y matriz de entrenamiento por rol.
- Existe `CNAME` con `app.sofamedica.com`.
- CI está definido en `.github/workflows/mvp-v1-ci.yml`, pero los commits recientes no muestran ejecuciones asociadas. El gate CI sigue pendiente.

### Supabase
- Proyecto SOFA activo: `bpwjhgpzhzhiocoxrvzq`.
- Datos observados: 6 organizations, 16 profiles, 19 organization_users, 23 ARS, 172 tariffs, 240 service_lines, 660 claim_status_history, 336 payment_line_allocations, 1242 audit_log.
- Security Advisor: 98 tablas con RLS habilitado sin políticas. Deben clasificarse entre deny-all intencional, interna/no expuesta o pendiente de policy.
- La lista nativa de migraciones solo muestra 062 y 063; el sistema además usa `app.schema_migrations`. Se mantiene la deuda de doble fuente de verdad.

### Neon
- Proyecto: `SoFa`.
- Se usa como sandbox técnico.
- El sprint aislado anterior validó lógica E2E con datos sintéticos; no sustituye JWT/RLS/Auth/Storage reales de Supabase.

## Fase 2 — Nicho / ICP
Posicionamiento recomendado:
**RCM as a Service + SaaS para médicos y consultorios/centros pequeños-medianos de República Dominicana.**

ICP inicial:
1. Médico especialista independiente con secretaria y múltiples ARS.
2. Consultorio o centro de 2–20 médicos sin departamento formal de facturación.
3. Prestadores con cartera vencida, glosas o dependencia de Excel/WhatsApp.

Dolor central:
“Presté el servicio, pero no sé si fue reclamado correctamente, cuándo lo pagarán o qué está bloqueando el cobro.”

Objetivo central del sistema:
Convertir servicios prestados en dinero cobrado con trazabilidad y menor fricción operativa.

## Fase 3 — Valor agregado prioritario
P0:
- bandeja operativa por excepción;
- preventor de glosas;
- estado financiero por reclamación;
- aging/SLA por ARS;
- captura ultrarrápida para secretaria;
- portal simple del médico;
- autoentrenamiento por rol.

P1:
- conciliación de remesas;
- causa raíz de glosas;
- benchmarking por especialidad/ARS;
- alertas de renovación tarifaria;
- onboarding guiado.

P2:
- IA supervisada para sugerencias;
- integraciones externas;
- automatizaciones condicionadas por aprobación humana.

## Fase 4 — Estrategia SaaS
Modelo técnico:
- schema compartido;
- `organization_id` en entidades tenant;
- RLS como frontera de autorización;
- MFA AAL2 para staff;
- excepciones multicliente temporales y auditables.

Planes sugeridos:
- Starter;
- Growth;
- Managed RCM;
- Enterprise.

North Star:
**RD$ efectivamente cobrados mediante reclamaciones gestionadas por SOFA.**

KPIs:
- servicio→radicación;
- first-pass acceptance;
- tasa/monto de glosa;
- radicación→pago;
- aging 30/60/90;
- recovery rate;
- claims por operador/día;
- MRR/churn/expansion.

## Fase 5 — DevOps
Branching:
- `main`: producción;
- `staging`: preproducción;
- `feature/*`: desarrollo;
- `architecture/mvp-production-v1`: núcleo candidato mientras se valida.

Pipeline objetivo:
typecheck → build → migration checks → Supabase branch → JWT/RLS → E2E → preview → staging → aprobación → producción.

## Bloqueadores antes de piloto real
1. CI sin run exitoso confirmado.
2. Supabase development branch aún no creada.
3. Migraciones 001–005 no ejecutadas en staging real.
4. JWT/RLS/MFA/Storage A/B reales pendientes.
5. Backup/restore de producción no demostrado.
6. Doble fuente de verdad de migraciones.
7. Clasificación de 98 tablas RLS sin policy pendiente.

## Decisión
Continuar con `mvp-v1`, congelar expansión funcional no esencial y concentrar el siguiente sprint en staging Supabase + Auth/JWT/RLS/MFA/Storage + E2E del ciclo completo.
