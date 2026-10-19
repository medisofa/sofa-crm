# SOFA MVP v1 — Pilot Readiness 2026-10-19

## Executive state
Backend/data layer and web build are now validated far enough for a controlled pilot preparation. Production remains untouched.

### Supabase staging
Development branch:
- name: `mvp-v1-sprint-e2e`
- project ref: `bvivlsrixbrczzrmodki`
- parent production: `bpwjhgpzhzhiocoxrvzq`
- project health: ACTIVE_HEALTHY
- branch orchestration status: MIGRATIONS_FAILED because the legacy native migration chain is incomplete on a fresh branch; MVP v1 migrations were applied manually and successfully.

Applied MVP migrations:
- 001_core_mvp_v1
- 002_operations_mvp_v1
- 003_hardening_mvp_v1
- 004_mfa_staff_mvp_v1
- 005_storage_mvp_v1
- 006_pilot_hardening
- 007_policy_helper_grants

## Security and domain tests executed

### Tenant isolation
PASS:
- Doctor A only sees Consultorio A after exception expiry.
- Doctor B sees its own provider and zero claims from Consultorio A.
- Direct INSERT on claims_v1 is revoked from authenticated.

### Capturer scope
PASS:
- Secretary A sees only assigned provider.
- Secretary A sees only the tariff for that provider.
- Claim creation uses the server-validated contractual tariff.

### Multi-organization exception
PASS:
- Valid temporary exception exposed Consultorio B to Doctor A.
- Expiring the exception removed Consultorio B automatically.

### MFA
PASS at PostgreSQL/RLS claim level:
- SOFA Operations with AAL1 sees zero client providers.
- SOFA Operations with AAL2 sees the two assigned client organizations.
- my_context_v1 returns operator + visible client organizations for AAL2 staff.

### RCM lifecycle
PASS:
- captured -> received -> validated
- submission_create_v1 -> submitted
- denial_create_v1 -> denied -> closed
- payment_register_v1 -> paid -> closed
- 2 synthetic claims completed
- 1 synthetic submission
- 1 synthetic denial
- 1 synthetic payment
- audit and claim event rows generated

### Storage
PASS configuration:
- bucket `sofa-claims-v1` exists
- private=true
- 15 MiB limit
- allowed types: PDF/JPEG/PNG/WEBP
- authenticated SELECT/INSERT policies exist and resolve through claim authorization.

Runtime object upload/download A/B is still pending because no connected web runtime is available from this execution environment.

## Fixes discovered by real staging tests
1. RLS policies failed because policy helper functions had EXECUTE revoked from authenticated.
   - fixed by migration 007.
2. Staff context originally did not synthesize visible client organizations.
   - fixed by migration 006.
3. Direct claim INSERT could bypass transactional RPC.
   - fixed by migration 006.
4. Generic transition allowed financial/submission state changes without their transactional records.
   - fixed by migration 006.
5. Active duplicate detection with NULL authorization was weak.
   - fixed by migration 006.
6. TypeScript cookie callbacks had implicit any errors.
   - fixed in middleware and Supabase server client.
7. Dependency audit found vulnerable PostCSS through Next.js.
   - Next.js pinned to 15.5.28.
   - PostCSS overridden to patched 8.5.23.
   - CI security audit now passes.

## CI
Draft PR: #39 — MVP v1 pilot validation — DO NOT MERGE

Latest successful workflow:
- SOFA MVP v1 CI run #21
- npm install: PASS
- npm audit --audit-level=high: PASS
- npm run typecheck: PASS
- npm run build: PASS

## Remaining blockers before a human pilot
1. Deploy the Next.js app to a staging host.
2. Configure staging environment variables with the Supabase development branch URL and publishable key.
3. Create real Auth test users through supported Supabase Auth flows.
4. Validate actual signed JWT login/refresh/logout.
5. Enroll/challenge real MFA AAL2 for staff.
6. Perform real Storage upload/download A/B through the Storage API.
7. Validate browser E2E for Doctor A, Doctor B, Secretary A and SOFA staff.
8. Prove backup/restore before any production migration.

## Decision
Status: **PILOT-BACKEND READY / BROWSER PILOT BLOCKED BY HOSTING + REAL AUTH RUNTIME**.

Do not merge PR #39 and do not deploy to production yet.
