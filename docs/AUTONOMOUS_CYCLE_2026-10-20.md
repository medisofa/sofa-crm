# SOFA — Autonomous product/technology/growth cycle

Date: 2026-10-20  
Branch: `autonomous/sofa-scale-cycle-2026-10-20`  
Base: `main@bd6d8ee9e8ba45fb896fe1ba2f7edda415011cef`

## Verified sources

- GitHub repository: `medisofa/sofa-crm`; default branch `main`.
- Supabase production project: `bpwjhgpzhzhiocoxrvzq`.
- Supabase preview branch: `mvp-v1-sprint-e2e` / `bvivlsrixbrczzrmodki`.
- Google Drive artifacts: external ARS capture sheet and Radar SOFA Santiago.
- Production contains 1 DEMO client organization and 4 non-DEMO client organizations.

## Current stage

Stage 4 — product with real client organizations and operating workflows, but paid/repeatable economics are not yet validated.

## Validation executed: isolation + E2E + paid client + margin

### 1. DEMO isolation — PARTIAL PASS

Production read-only counts:

- Real clients: 4
- DEMO clients: 1
- Real service lines: 40, claimed RD$34,000.00
- DEMO service lines: 240, claimed RD$352,800.00
- Real submissions: 9
- DEMO submissions: 2
- Real ARS payments: 0
- DEMO ARS payments: 2, amount RD$238,904.40

`public.sofa_real_financial_summary` correctly excludes DEMO data and reports only 4 real clients, RD$34,000 claimed, RD$0 paid and 40 service lines.

However, multiple general views that consume service_lines/payments/submissions do not explicitly reference `organizations.is_demo`. These require classification because some may be organization-scoped and safe, while production-wide KPI/report views must explicitly exclude DEMO.

Conclusion: the dedicated production financial summary passes; global isolation is not yet proven.

### 2. End-to-end technical flow — STAGING PASS / REAL CLIENT NOT YET PASS

The Supabase preview environment is accessible for read-only validation. Its synthetic RCM dataset contains two closed claims with full downstream outcomes:

- Claim A: created → status changes → submitted → payment_applied → closed.
- Claim B: created → status changes → submitted → denial_created → closed.

Both claims are linked to a submission. One has a payment allocation and the other has a denial.

This proves the technical lifecycle can represent both payment and denial outcomes in staging.

Production real-client data does not yet prove the same lifecycle:
- 40 real claims total.
- 10 have reached validation / list-to-radicate.
- 0 have reached radication.
- 0 have payment allocation.
- 0 have glosa.

Conclusion: synthetic E2E is demonstrated; real-client E2E remains pending.

### 3. Paid client — FAIL / NOT YET EVIDENCED

Across all 4 non-DEMO client organizations:

- SOFA invoices: 0
- SOFA invoice payments: RD$0
- Subscription invoices: 0
- Subscription amount paid: RD$0
- Service contracts: 0

Therefore there is no database evidence yet of a paying SOFA client.

### 4. Margin — FAIL / NOT MEASURABLE YET

The cost model exists technically:
- `app_settings.staff_hour_cost`
- `staff_time_entries.hours`

But current production values are:
- staff_hour_cost = RD$0.00
- tracked hours for real clients = 0
- collected SOFA revenue = RD$0.00

This produces a mathematical contribution of RD$0.00 but not an economically meaningful margin.

To validate margin, SOFA must record:
1. actual collected client revenue,
2. staff hourly cost,
3. time spent by client,
4. any other direct variable costs.

### Security note from staging

The staging advisor reports 5 legacy/public tables with RLS disabled:
- roles
- organizations
- profiles
- organization_users
- clinical_settings

This does not affect the evidence that the synthetic RCM lifecycle exists, but it blocks treating the preview environment as production-equivalent until the intended policies are defined and tested. No automatic remediation was applied.

## Current readiness verdict

| Criterion | Verdict |
|---|---|
| DEMO isolation in dedicated real financial summary | PASS |
| DEMO isolation across all production aggregates | PARTIAL / PENDING |
| Synthetic technical E2E | PASS |
| Real-client E2E through radication/payment/glosa | FAIL / PENDING |
| Paying real client evidenced in system | FAIL |
| Gross/contribution margin evidenced | FAIL |

## Primary blocker

The next stage is not additional feature development. The missing evidence is commercial-operational:

**one real client must complete the workflow, be invoiced, pay SOFA, and have actual delivery time/cost recorded.**

## Acceptance criteria for the next gate

The project advances when all of these are true:

1. Every production-wide KPI/report excludes `is_demo=true`.
2. At least one real non-DEMO claim reaches radication and payment or glosa without manual DB intervention.
3. At least one non-DEMO client has a SOFA invoice and a recorded payment.
4. `staff_hour_cost > 0` and delivery hours are recorded for that client.
5. Contribution margin is positive:
   `collected SOFA revenue - direct labor cost - variable direct costs > 0`.
6. The client confirms continuation/renewal after the pilot.

## Changes performed

- Read-only validation queries were executed in production and staging.
- No production rows, schema, emails, DNS or deployments were modified.
- Results recorded in this existing cycle document instead of creating a duplicate report.
