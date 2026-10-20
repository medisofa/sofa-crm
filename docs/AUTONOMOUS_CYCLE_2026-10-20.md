# SOFA — Autonomous product/technology/growth cycle

Date: 2026-10-20  
Branch: `autonomous/sofa-scale-cycle-2026-10-20`  
Base: `main@bd6d8ee9e8ba45fb896fe1ba2f7edda415011cef`

## Verified sources

- GitHub repository: `medisofa/sofa-crm`; default branch `main`.
- Supabase production project: `bpwjhgpzhzhiocoxrvzq`.
- Supabase preview branch: `mvp-v1-sprint-e2e` / `bvivlsrixbrczzrmodki`; current status reports `MIGRATIONS_FAILED`.
- Google Drive artifacts: external ARS capture sheet and Radar SOFA Santiago.
- Current main head fixes recovery-flow handling for Supabase 429 responses.
- Supabase contains 1 DEMO client organization and 4 non-DEMO client organizations.
- Current database counts at audit time: 240 DEMO service lines vs 40 non-DEMO service lines; 2 DEMO submissions vs 9 non-DEMO submissions; 2 DEMO payments vs 0 non-DEMO payments.

## Current stage

Stage 4 — business/product with real client organizations and operating workflows, but validation of paid/repeatable economics is not yet evidenced.

## Primary blocker

Reliable production metrics and operational decisions cannot be trusted until DEMO isolation is proven across every production-facing aggregate, report, notification and automated process. A dedicated financial summary already excludes DEMO data, but several general views touching organizations do not explicitly reference `is_demo`.

## Cycle priority

1. Prove DEMO isolation across KPIs/reports/jobs.
2. Restore a healthy development/staging path; current Supabase preview branch reports failed migrations.
3. Complete real-user invitation/recovery/login verification.
4. Validate the core paid workflow end-to-end: capture → validation → radication → payment/glosa.
5. Measure willingness to pay and unit economics with actual clients.

## Executed in this cycle

- Created isolated GitHub branch for reversible work.
- Added `qa/demo_isolation_regression.sql`, a read-only regression audit.
- No production data, Supabase schema, DNS, emails or deployments were modified.

## Acceptance criteria for next technical gate

- Staging branch migrations succeed.
- Demo-regression audit classifies every production-facing aggregate and shows no cross-contamination.
- Auth invitation/recovery/first-login succeeds with an authorized test account and the UI reports accepted/delivered states accurately.
- One real non-DEMO claim completes the main workflow without manual database intervention.
- CI/security harness passes on the candidate commit.

## Commercial hypothesis

Primary ICP: Dominican specialist physician / independent practice with ARS billing handled by a secretary or small admin team. Main value: fewer rejected/delayed claims, less admin time and clearer cash-flow visibility. Evidence of willingness to pay is still incomplete; current commercial documents define fixed-per-claim and percentage-of-collected models but do not establish validated price points.

## Next experiment

Run a 30-day paid pilot offer with a narrowly defined claim-management package. Measure activation time, claims processed, rejection/glosa rate, days-to-radication, collections recovered, admin hours saved, gross margin and renewal intent. Do not contact prospects or launch campaigns until separately authorized.
