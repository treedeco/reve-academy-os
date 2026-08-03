# Production backup and restore runbook — REVE ACADEMY OS (Phase 2B-2C1)

**Status:** implemented, **runtime unverified** — production backup not run, restore drill not run, cleanup apply **blocked**.

Operator guide for fail-closed **multi-artifact encrypted** database backup, offline verification, and isolated local restore validation.

**This runbook does not authorize direct production restore.**

Rollback tag: `phase-2b2c1-pre-backup-restore-safety-gate`.

---

## 1. Phase status

| Item | Status |
|------|--------|
| Implementation | Complete in repo (`2b2c1-v2` contract) |
| Production backup executed | **No** |
| Restore drill on production artifact | **No** |
| Runtime verified | **No** |
| Cleanup apply gate | **Blocked** |

---

## 2. Backup mechanism (proven by CLI dry-run inspection)

The backup set uses **`npx supabase db dump`** which wraps **`pg_dump` / `pg_dumpall`** — **not** a single merged SQL file.

### Exact artifact commands (linked production)

| Artifact file (encrypted) | Command |
|---------------------------|---------|
| `roles.sql.enc` | `npx supabase db dump --linked --role-only -f roles.sql` |
| `schema-public.sql.enc` | `npx supabase db dump --linked --schema public -f schema-public.sql` |
| `schema-auth-storage.sql.enc` | `npx supabase db dump --linked --schema auth,storage -f schema-auth-storage.sql` |
| `migration-history-schema.sql.enc` | `npx supabase db dump --linked --schema supabase_migrations -f migration-history-schema.sql` |
| `data-public.sql.enc` | `npx supabase db dump --linked --data-only --schema public -f data-public.sql` |
| `data-auth.sql.enc` | `npx supabase db dump --linked --data-only --schema auth -f data-auth.sql` |
| `data-storage-metadata.sql.enc` | `npx supabase db dump --linked --data-only --schema storage -x storage.buckets_vectors -x storage.vector_indexes -f data-storage-metadata.sql` |
| `migration-history-data.sql.enc` | `npx supabase db dump --linked --data-only --schema supabase_migrations -f migration-history-data.sql` |

Plaintext SQL exists only in a temporary directory during backup, is secret-scanned, encrypted, then **deleted before the runner exits**.

### Proven vs unproven contents

| Contract item | Proven capture path | Notes |
|---------------|---------------------|-------|
| public schema DDL | `schema-public.sql` | pg_dump `--schema-only --schema=public` |
| public table data | `data-public.sql` | pg_dump `--data-only --schema public` |
| auth schema DDL | `schema-auth-storage.sql` | **Not** in default CLI dump; explicit `--schema auth,storage` required |
| auth.users data | `data-auth.sql` | includes password hashes; CLI excludes `auth.schema_migrations` |
| storage metadata schema | `schema-auth-storage.sql` | bucket/table DDL only |
| storage metadata rows | `data-storage-metadata.sql` | excludes `storage.buckets_vectors`, `storage.vector_indexes`; **not** object binaries |
| migration history schema | `migration-history-schema.sql` | explicit schema dump |
| migration history rows | `migration-history-data.sql` | default data dump excludes `supabase_migrations` |
| functions/RPCs, RLS, triggers, sequences | `schema-public.sql` | standard pg_dump schema output |
| roles (safe subset) | `roles.sql` | pg_dumpall `--roles-only` with Supabase CLI filters |

| **Not captured by SQL dump** | Recovery domain |
|------------------------------|-----------------|
| Storage object binaries | Storage object recovery (Dashboard/API) |
| Auth provider / redirect URL settings | Auth configuration recovery (Dashboard) |
| Edge Functions + secrets | Edge Function/configuration recovery |
| Vercel/hosting env vars | Out of band |

---

## 3. Migration checkpoint

- Expected linked migration count: **26 / 26**
- Expected repo checkpoint: `20260728120000_phase_2b2b5_owner_permanent_deletion_and_schedule_removal`

---

## 4. At-rest protection model (required)

1. **Encryption required:** **REVEBKUP1** format — AES-256-GCM + scrypt (N=16384, r=8, p=1); passphrase via PowerShell **SecureString** prompt only.
2. **REVEBKUP1 header (66 bytes before ciphertext):** magic `REVEBKUP1` (9) + version (1) + salt (16) + IV (12) + scrypt N/r/p (4 each) + auth tag (16). Each artifact gets a **new random salt and IV**.
3. Passphrase is **never** stored in manifest, logs, Git, filenames, or command arguments.
4. Authentication failure must **not** write plaintext output.
5. Cloud-synchronized folders (OneDrive, Dropbox, Google Drive, iCloud, Box) are **rejected**.
6. Default destination: `backups/backup-<label>/` (gitignored). Optional override: `REVE_BACKUP_DESTINATION` (must pass storage guard).
7. Decrypted plaintext exists only under `.tmp-restore-*` during validation and is removed in `finally`.

`.gitignore` alone is **not** considered sufficient protection.

---

## 5. Manifest contract (`2b2c1-v2`)

`backups/backup-<label>/manifest.json` lists **each encrypted artifact** with:

- `id`, `relativePath`, `artifactType`, `classification`
- `includedSchemas`, `excludedSchemas`, `dumpMode`
- `encrypted: true`, `sha256`, `sizeBytes`
- aggregate row counts (numbers only — **no names/emails/phones**)

Manifest must **not** contain credentials, JWTs, database URLs, student/teacher personal data, or passphrases.

---

## 6. Restore order (isolated local validation only)

Dependency-aware order for a **new** validation database (`public.profiles` references `auth.users`):

1. `roles.sql`
2. `schema-auth-storage.sql` — **managed schema; validation DB only**
3. `migration-history-schema.sql`
4. `schema-public.sql`
5. `data-auth.sql`
6. `data-storage-metadata.sql`
7. `data-public.sql`
8. `migration-history-data.sql`

### Managed-schema boundary (`schema-auth-storage.sql.enc`)

- **For isolated local restore validation only** (`reve_backup_val_*` temporary database)
- **Never** a direct production or hosted restore artifact
- **Never** applied through `--linked`, to a `supabase.co` host, or to the existing local `postgres` database
- Restore into an existing Supabase project requires a **separately reviewed managed-schema procedure** (not implemented in Phase 2B-2C1)

Temporary database: `reve_backup_val_<suffix>` — **dropped in all exit paths**.

Post-restore validation fails closed on missing artifacts, checksum mismatch, migration checkpoint mismatch, missing tables, FK orphans, RLS disabled, missing policies, active/reserved pass uniqueness violations, pass usage overflow, payment/SMS/slot orphans, and manifest row-count drift.

**Unit tests are not accepted as runtime verification.** Phase becomes runtime-verified only after restoring a **production-created** encrypted backup set locally.

---

## 7. Operator commands

### Backup (guarded — not yet executed in this phase)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_backup_production.ps1 `
  -ConfirmProduction `
  -ConfirmProjectRef bfhptqhgxignyggyxxkx `
  -Label phase-2b2c1-pre-cleanup-apply
```

Prompts (hidden): backup encryption passphrase, Postgres password, Owner password.

### Offline verify

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_verify_production_backup.ps1 `
  -ConfirmProduction `
  -ConfirmProjectRef bfhptqhgxignyggyxxkx `
  -Label phase-2b2c1-pre-cleanup-apply
```

### Restore validation drill (local Supabase required)

```powershell
npx supabase start
powershell -ExecutionPolicy Bypass -File scripts/run_restore_validate_production_backup.ps1 `
  -ConfirmRestoreValidation `
  -Label phase-2b2c1-pre-cleanup-apply
```

---

## 8. Recovery domains (separate procedures)

| Domain | Source |
|--------|--------|
| Database recovery | Encrypted SQL artifact set + manifest |
| Auth configuration recovery | Supabase Dashboard → Authentication settings |
| Storage object recovery | Supabase Storage dashboard/API |
| Edge Function/configuration recovery | Supabase CLI/dashboard redeploy |

---

## 9. Cleanup apply gate

Blocked until:

1. Production encrypted backup PASS
2. Offline verify PASS
3. **Production artifact** restore drill PASS locally
4. Operator sign-off with `runId`, `label`, artifact checksums

When applying cleanup later: run a **fresh** dry-run for a new `RunId` (never reuse prior RunId).

---

## 10. Developer verification

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify_phase_2b2c1.ps1
```
