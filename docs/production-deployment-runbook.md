# Production deployment runbook — REVE ACADEMY OS

Operator guide for deploying the approved application to **hosted Supabase** and **Vercel** without changing application behavior.

**Prerequisites**: GitHub repository access, Supabase organization access, Vercel account, Supabase CLI (`npx supabase`), Node.js 22+.

**Do not deploy** local alpha demo accounts, integration test students (`student_code ~ '^S-'`), test passwords, or `npm run db:seed:alpha` to production.

---

## 1. Production requirements audit

### 1.1 Runtime environment variables (Next.js application)

| Variable | Required at runtime | Exposure |
|----------|---------------------|----------|
| `NEXT_PUBLIC_SUPABASE_URL` | Yes | Browser-safe (public) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Yes | Browser-safe (public) |

The application does **not** read a service-role key at runtime. Supabase SSR uses the anon key with RLS and authenticated sessions.

Reference: `lib/supabase/client.ts`, `lib/supabase/server.ts`, `lib/supabase/middleware.ts`.

### 1.2 Environment variable classification

| Class | Variables | Notes |
|-------|-----------|-------|
| **Browser-safe public** | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Set in Vercel **Production** (and Preview if desired). |
| **Server-only secrets** | `SUPABASE_SECRET_KEY` (preferred) or `SUPABASE_SERVICE_ROLE_KEY` (legacy JWT fallback) | Operator workstation only for bootstrap. **Never** use `NEXT_PUBLIC_` prefix. **Do not** add to Vercel. |
| **One-time bootstrap** | `OWNER_BOOTSTRAP_PASSWORD` | Operator shell only when running `npm run bootstrap:production-owner`. Remove after bootstrap. |
| **Local / CI only** | `OWNER_PASSWORD`, `E2E_OWNER_PASSWORD`, `SUPABASE_DB_CONTAINER`, `PLAYWRIGHT_BASE_URL`, `CI` | Never set in production hosting. |

Optional bootstrap overrides (operator shell): `OWNER_BOOTSTRAP_EMAIL` (default `reve@owner.local`), `OWNER_BOOTSTRAP_DISPLAY_NAME` (default `REVE Owner`).

Template (names only): [`.env.production.example`](../.env.production.example).

### 1.3 Supabase migrations (apply all, in order)

Apply every file under `supabase/migrations/` in lexicographic order:

1. `20260626120000_phase_0b3a_foundation.sql`
2. `20260626120100_phase_0b3a_core_tables.sql`
3. `20260626120200_phase_0b3a_constraints_indexes_rls.sql`
4. `20260626121018_phase_0b3b1_identity_rls.sql`
5. `20260626123408_phase_0b3b2a_safe_read_projections.sql`
6. `20260626124258_phase_0b3b2b1_lesson_transitions.sql`
7. `20260629040048_phase_0b3b2b2_payment_renewal.sql`
8. `20260629120000_phase_0b3b2b2a_reserved_lesson_shells.sql`
9. `20260630120000_phase_0b3b2b3a_profile_people_master_data.sql` — includes `reve_bootstrap_first_owner`
10. `20260701120000_phase_0b3b2b3b_course_product_management.sql`
11. `20260702120000_phase_0b3b2b3c_initial_enrollment.sql`
12. `20260703120000_phase_0b3b2b3d1_pass_schedule_management.sql`
13. `20260704120000_phase_0b3b2b3d2a_schedule_change_workflow.sql`
14. `20260705120000_phase_0b3b2b3d2b_lesson_cascade_rescheduling.sql`
15. `20260706120000_phase_0b3b2b3d2b_owner_sms_sent_confirmation.sql`
16. `20260707120000_phase_0b3b2b3d3b_h1_remove_test_harness.sql`
17. `20260708120000_phase_0b3b2b3e_owner_payment_refund.sql`
18. `20260708130100_phase_1a_owner_read_projections.sql`
19. `20260708130200_phase_1a_deferred_trigger_security.sql`
20. `20260716180000_phase_2b2b1r1_owner_lesson_operations.sql`

`supabase/seed.sql` is intentionally empty. **Do not** run local alpha seeds in production.

### 1.4 Local-only scripts (never production)

| Script | Purpose |
|--------|---------|
| `npm run db:seed:alpha` | Local Owner + demo data |
| `scripts/seed-owner-alpha.ps1` / `.sql` | Local alpha seed |
| `scripts/apply-integration-test-cleanup.mjs` | Deletes `student_code ~ '^S-'` — **local guard only** |
| `scripts/fixture-*.sql` | E2E / integration fixtures |

### 1.5 Localhost and cookie assumptions

- **Application code** (`app/`, `lib/`): no hard-coded localhost URLs.
- **Middleware**: Supabase SSR default cookies; no custom domain or `Secure`/`SameSite` overrides in repo. Vercel serves HTTPS; Supabase Auth redirect URLs must include the production origin in the Supabase dashboard.
- **Owner login**: username `reve` maps to Supabase Auth email `reve@owner.local` (`lib/auth/owner-login.ts`). Production Auth user must use that email unless the application is changed in a future release.

### 1.6 Service-role usage

- **Application runtime**: none.
- **Database**: `service_role` grants on RPCs such as `reve_bootstrap_first_owner` (migration `20260630120000_phase_0b3b2b3a_profile_people_master_data.sql`).
- **Operator bootstrap**: `scripts/bootstrap-production-owner.mjs` uses `SUPABASE_SECRET_KEY` (preferred) or legacy `SUPABASE_SERVICE_ROLE_KEY` from the operator environment only, via `@supabase/supabase-js` Auth Admin APIs. Opaque `sb_secret_...` keys must not be sent as `Authorization: Bearer` tokens.

---

## 2. Supabase project preparation

1. Create a new Supabase project in the target region (recommend same region as Vercel deployment).
2. Record (do not commit):
   - Project URL → `NEXT_PUBLIC_SUPABASE_URL`
   - Anon (public) key → `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - Secret API key (`sb_secret_...`) → `SUPABASE_SECRET_KEY` (bootstrap workstation only)
   - Legacy JWT service_role key → `SUPABASE_SERVICE_ROLE_KEY` (fallback only if secret key unavailable)
3. In **Authentication → URL configuration**, add:
   - **Site URL**: your Vercel production URL (set after first deploy, then update)
   - **Redirect URLs**: production origin and `https://<project>.vercel.app/**` if using Vercel default domain
4. Link local CLI to the hosted project (one-time):

```powershell
npx supabase login
npx supabase link --project-ref <PROJECT_REF>
```

5. Confirm linked project in Supabase dashboard matches the intended production project.

---

## 3. Apply migrations to hosted Supabase

From repository root, with CLI linked to the **production** project:

```powershell
npx supabase db push
```

Verify in Supabase SQL editor:

```sql
select version, name from supabase_migrations.schema_migrations order by version;
```

Expect 20 migration versions matching the list in §1.3.

**Rollback (schema)**: Supabase does not auto-reverse migrations. For a failed push, fix forward with a new migration or restore from backup (§8). Do not run `db:seed:alpha` or integration cleanup on hosted projects.

---

## 4. One-time Owner bootstrap (fail-closed)

Script: `scripts/bootstrap-production-owner.mjs`  
npm: `npm run bootstrap:production-owner`

### 4.1 Guards

- Targets **hosted** Supabase only (`*.supabase.co` / `*.supabase.in`); rejects localhost.
- Requires `SUPABASE_SECRET_KEY` (preferred) or legacy `SUPABASE_SERVICE_ROLE_KEY` (rejects `NEXT_PUBLIC_` admin keys).
- Uses `@supabase/supabase-js` Auth Admin APIs (`listUsers`, `createUser`) — not raw `fetch()` with `Authorization: Bearer` for opaque secret keys.
- Does **not** run integration cleanup or local seeds.
- Does **not** print passwords or API keys.
- Idempotent: lists Auth users by exact normalized email before create; reuses a single existing user; fails if duplicates exist; `reve_bootstrap_first_owner` returns `idempotent_replay` when appropriate.

### 4.2 Operator steps

1. Set variables in the operator shell only (PowerShell example):

```powershell
$env:SUPABASE_URL = "https://<PROJECT_REF>.supabase.co"
$env:SUPABASE_SECRET_KEY = "<from Supabase dashboard — secret key, server only>"
# Legacy fallback only:
# $env:SUPABASE_SERVICE_ROLE_KEY = "<legacy JWT service_role key>"
$env:OWNER_BOOTSTRAP_PASSWORD = "<strong one-time password>"
# Optional: $env:OWNER_BOOTSTRAP_EMAIL = "reve@owner.local"
```

Prefer a secure local prompt instead of placing secrets directly in shell history. See §4.4.

2. Run bootstrap:

```powershell
npm run bootstrap:production-owner
```

3. Confirm output includes `profile_id`, `role: owner`, `account_state: active`.
4. **Remove** `OWNER_BOOTSTRAP_PASSWORD` and `SUPABASE_SECRET_KEY` / `SUPABASE_SERVICE_ROLE_KEY` from the shell and from any temporary secret notes.
5. Store the Owner password in your team password manager; operators sign in at `/login` with username **`reve`**.

### 4.4 Secure local PowerShell bootstrap (recommended)

```powershell
Set-Location C:\Dev\reve-academy-os
$ErrorActionPreference = 'Stop'

function Read-SecurePlainText {
  param([string]$Prompt)
  $secure = Read-Host $Prompt -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $secure.Dispose()
  }
}

$secretKey = Read-SecurePlainText 'SUPABASE_SECRET_KEY (input hidden)'
$bootstrapPassword = Read-SecurePlainText 'OWNER_BOOTSTRAP_PASSWORD (input hidden)'

$env:SUPABASE_URL = 'https://<PROJECT_REF>.supabase.co'
$env:SUPABASE_SECRET_KEY = $secretKey
$env:OWNER_BOOTSTRAP_PASSWORD = $bootstrapPassword

$secretKey = $null
$bootstrapPassword = $null
[GC]::Collect()

try {
  npm run bootstrap:production-owner
} finally {
  Remove-Item Env:SUPABASE_SECRET_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:OWNER_BOOTSTRAP_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:SUPABASE_URL -ErrorAction SilentlyContinue
}
```

Never commit, log, or paste `SUPABASE_SECRET_KEY`, legacy `SUPABASE_SERVICE_ROLE_KEY`, or `OWNER_BOOTSTRAP_PASSWORD` into chat or git.

### 4.3 Failure modes

| Error | Action |
|-------|--------|
| Local URL rejected | Confirm `SUPABASE_URL` is the hosted project URL |
| `REVE_BOOTSTRAP_ALREADY_COMPLETED` | Owner already exists; verify login |
| Auth user exists but wrong email | Use `reve@owner.local` or update app in a controlled release |
| Missing admin key | Set `SUPABASE_SECRET_KEY` (preferred) or legacy `SUPABASE_SERVICE_ROLE_KEY` on workstation, not Vercel |

---

## 5. Vercel configuration

### 5.1 Connect the existing project to GitHub

**Target (do not create a duplicate project):**

| Setting | Value |
|---------|-------|
| Team | `revevocal-9909s-projects` |
| Project | `reve-academy-os` |
| GitHub repository | `treedeco/reve-academy-os` |
| Production branch | `main` |
| Primary domain | `https://reve-academy-os.vercel.app` |

Current deployments may have been created with `vercel deploy --prod` (CLI). Git integration is **separate** and must be connected before pushes to `main` trigger automatic production deploys.

#### Step A — GitHub Login Connection (browser; operator only)

Required before `vercel git connect` or dashboard import will succeed.

1. Open [Vercel Account Settings → Login Methods and Connections](https://vercel.com/account/settings/authentication).
2. Under **Git**, click **Connect** next to **GitHub**.
3. Approve the Vercel GitHub App when GitHub prompts you.
4. On **Repository access**, choose **Only select repositories** (recommended).
5. Select **`treedeco/reve-academy-os`** only. Do not grant access to unrelated repositories.
6. Complete authorization and return to Vercel.

If CLI reports `You need to add a Login Connection to your GitHub account first`, Step A is incomplete.

#### Step B — Link the existing Vercel project (after Step A)

**Dashboard (recommended):**

1. Vercel → team **`revevocal-9909s-projects`** → project **`reve-academy-os`**.
2. **Settings** → **Git** → **Connect Git Repository**.
3. Choose **GitHub** → **`treedeco/reve-academy-os`**.
4. Set **Production Branch** to **`main`**.
5. Save. Do **not** create a new project.

**CLI (alternative, from repo root after Step A):**

```powershell
npx vercel link --yes --project reve-academy-os
npx vercel git connect https://github.com/treedeco/reve-academy-os.git
```

#### Step C — Branch and deployment behavior

| Event | Expected result |
|-------|-----------------|
| Push to `main` | **Production** deployment; updates `https://reve-academy-os.vercel.app` |
| Pull request | **Preview** deployment only (unique preview URL) |
| Push to other branches | **Preview** only; never production |
| Fork PRs | Do not enable untrusted fork production deploys; use Vercel **Deployment Protection** defaults |

Framework preset: **Next.js**. Build command: `npm run build`. Install command: `npm ci` (recommended).

No hard-coded URLs or secrets belong in the repository.

#### Step D — Verify Git-triggered production deploy

After Step B succeeds:

1. Push a safe, non-functional commit to `main` (empty commit or documentation-only).
2. Vercel → **Deployments** → confirm a new deployment shows source **Git** / commit SHA matching the push.
3. Confirm production alias still points to `https://reve-academy-os.vercel.app`.
4. Smoke: `/login` loads; unauthenticated `/students` redirects to `/login`.

Do **not** use the production Owner password for automation smoke checks.

### 5.2 Environment variables (Production)

| Name | Value source |
|------|----------------|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase → Settings → API → Project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase → Settings → API → anon public |

Do **not** set `OWNER_PASSWORD`, `E2E_OWNER_PASSWORD`, `OWNER_BOOTSTRAP_PASSWORD`, `SUPABASE_SECRET_KEY`, or `SUPABASE_SERVICE_ROLE_KEY` in Vercel for normal operation.

Apply to **Production** only unless a **separate isolated Supabase preview project** exists.

#### Preview deployments and Supabase

**Default policy (no isolated preview Supabase):**

- Do **not** copy Production Supabase `NEXT_PUBLIC_*` variables into **Preview**.
- Preview builds may compile but must **not** be used for authenticated operational testing against production data.
- Pull-request previews are for UI/build verification only until a dedicated preview Supabase project is approved and configured.

Do not create a new Supabase project without explicit operator approval.

### 5.3 Deploy

- **Automatic (after Git connected)**: push to `main` triggers production deploy when Production env vars are set.
- **Manual fallback**: `npx vercel deploy --prod --yes` or Vercel dashboard → **Redeploy**.

After first deploy, update Supabase Auth **Site URL** and **Redirect URLs** to the live Vercel URL.

---

## 6. Rollback

### Application (Vercel)

1. Vercel → Project → **Deployments**.
2. Select the last known-good deployment → **Promote to Production** (or **Rollback**).

### Database

- Prefer **point-in-time recovery** or scheduled backup restore via Supabase dashboard (Pro plan) or manual `pg_dump` restore.
- Do not run local integration cleanup scripts against production.

### Configuration

- Revert environment variable changes in Vercel and redeploy.
- Document incident and whether schema rollback or forward-fix migration is required.

---

## 7. Backup

1. Enable Supabase **daily backups** (plan-dependent) for the production project.
2. Before major migrations, take a manual backup:

```powershell
npx supabase db dump --linked -f backup-pre-<date>.sql
```

Store dumps in encrypted operator storage, not in git.

3. Record RPO/RTO expectations in your operations policy; test restore on a staging project periodically.

---

## 8. Production smoke verification

After deploy and Owner bootstrap:

| Step | Check |
|------|-------|
| 1 | Open production `/login` over HTTPS |
| 2 | Sign in with username `reve` and bootstrap password |
| 3 | Confirm redirect to dashboard; session persists on refresh |
| 4 | Open **Today’s lessons** and **Students** — empty or real data only (no `S-*` test codes) |
| 5 | Sign out; confirm protected routes redirect to login |
| 6 | Supabase Auth dashboard shows `reve@owner.local` user |

Optional local regression before release (developer machine):

```powershell
npm run typecheck
npm run lint
npm run test
npm run build
.\scripts\verify_phase_1a.ps1   # requires local Docker Supabase
```

---

## 9. Security checklist

- [ ] No secrets committed to git (verify with `git grep -i password` on tracked files)
- [ ] Service role / secret keys never prefixed with `NEXT_PUBLIC_`
- [ ] Vercel production env has only public Supabase vars for app runtime
- [ ] Bootstrap secrets (`SUPABASE_SECRET_KEY`, legacy service role key, bootstrap password) removed from operator shell after use
- [ ] Local alpha seeds and integration cleanup never run against hosted URL
- [ ] Supabase RLS enabled (migrations apply policies)

---

## 10. Related documentation

- [`.env.production.example`](../.env.production.example)
- [Trusted operation contracts — bootstrap](./trusted-operation-contracts.md)
- [Manual verification (local reference)](./manual-verification-owner-alpha.md)
- [Owner minimum go-live readiness audit](./owner-minimum-go-live-readiness-audit.md)
