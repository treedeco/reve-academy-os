/**
 * Phase 2B-2C1 production backup / restore contract (fail-closed).
 * No secrets or personal data in exported constants.
 */
import fs from 'node:fs';
import path from 'node:path';
import { PRODUCTION_PROJECT_REF } from './reve-production-operator-guard.mjs';
import {
  BACKUP_ARTIFACTS,
  BACKUP_CONTENT_PROOF,
  BACKUP_MECHANISM,
  BACKUP_NOT_CAPTURED,
  RESTORE_ARTIFACT_ORDER,
} from './reve-production-backup-dump-contract.mjs';

export const BACKUP_CONTRACT_VERSION = '2b2c1-v2';
/**
 * Minimum applied production migrations required for a valid backup.
 * Actual backup/restore counts follow the linked applied head (may rise after db push).
 * Keep as a floor only — do not treat this as a permanently fixed production head.
 */
export const MINIMUM_PRODUCTION_MIGRATION_COUNT = 31;
/** @deprecated Use MINIMUM_PRODUCTION_MIGRATION_COUNT; retained for restore fallback defaults. */
export const EXPECTED_MIGRATION_COUNT = MINIMUM_PRODUCTION_MIGRATION_COUNT;
export { PRODUCTION_PROJECT_REF, BACKUP_MECHANISM, BACKUP_ARTIFACTS, RESTORE_ARTIFACT_ORDER };

export const REQUIRED_PUBLIC_TABLES = Object.freeze([
  'profiles',
  'students',
  'teachers',
  'courses',
  'course_products',
  'passes',
  'schedule_slots',
  'lessons',
  'payments',
  'payment_refunds',
  'sms_notifications',
  'schedule_change_requests',
  'lesson_schedule_changes',
  'lesson_notes',
  'audit_logs',
]);

export const CRITICAL_ROW_COUNT_TABLES = Object.freeze([...REQUIRED_PUBLIC_TABLES]);
export const RLS_REQUIRED_TABLES = Object.freeze([...REQUIRED_PUBLIC_TABLES]);

export const BACKUP_INCLUDES = Object.freeze({
  mechanism: BACKUP_MECHANISM,
  multiArtifactSet: true,
  encryptionAtRestRequired: true,
  contentProof: BACKUP_CONTENT_PROOF,
});

export const BACKUP_EXCLUDES = Object.freeze({
  notCaptured: BACKUP_NOT_CAPTURED,
  environmentVariables: true,
  serviceRoleKeys: true,
  jwtTokens: true,
  databasePasswords: true,
  ownerPlaintextPasswords: true,
  storageObjectBinaryPayloads: true,
  manifestPersonalData: true,
});

export const AUTH_RESTORE_LIMITATIONS = Object.freeze({
  ownerLoginEmail: 'reve@owner.local',
  ownerUsername: 'reve',
  authUsersIncludedViaArtifact: 'data-auth',
  authProviderSettingsNotInSqlDump: true,
  passwordMaterialExcludedFromManifest: true,
  passwordHashesExistInEncryptedDataAuthArtifact: true,
  postRestoreLoginRequiresKnownOwnerPassword: true,
  bootstrapScriptNotRequiredWhenAuthRestored: true,
});

export const RECOVERY_DOMAINS = Object.freeze({
  database: 'roles + schema/data SQL artifacts (encrypted at rest)',
  authConfiguration: 'Supabase Dashboard Auth URL/provider settings (manual)',
  storageObjects: 'Supabase Storage dashboard/API (binaries not in PostgreSQL dump)',
  edgeFunctions: 'Supabase Edge Functions deploy/config (manual)',
});

export const DUMP_SECRET_SCAN_MAX_BYTES = 64 * 1024 * 1024;

export function listRepoMigrationVersions(repoRoot = process.cwd()) {
  const migrationsDir = path.join(repoRoot, 'supabase', 'migrations');
  if (!fs.existsSync(migrationsDir)) {
    throw new Error(`Migration directory not found: ${migrationsDir}`);
  }

  return fs
    .readdirSync(migrationsDir)
    .filter((name) => name.endsWith('.sql'))
    .map((name) => name.replace(/\.sql$/, ''))
    .sort();
}

export function resolveExpectedMigrationCheckpoint(
  repoRoot = process.cwd(),
  appliedMigrationCount = MINIMUM_PRODUCTION_MIGRATION_COUNT,
) {
  const versions = listRepoMigrationVersions(repoRoot);
  const appliedCount = Number(appliedMigrationCount);
  if (!Number.isInteger(appliedCount) || appliedCount < MINIMUM_PRODUCTION_MIGRATION_COUNT) {
    throw new Error(
      `Applied migration count must be an integer >= ${MINIMUM_PRODUCTION_MIGRATION_COUNT} (got ${appliedMigrationCount}).`,
    );
  }
  if (versions.length < appliedCount) {
    throw new Error(
      `Repo migrations (${versions.length}) are behind production applied count (${appliedCount}).`,
    );
  }
  // Pin to the production-applied head for the given applied count (not a local-only pending file).
  return versions[appliedCount - 1];
}

export function assertBackupContractVersion(version) {
  if (version !== BACKUP_CONTRACT_VERSION) {
    throw new Error(
      `Unsupported backup contract version: ${version ?? 'missing'} (expected ${BACKUP_CONTRACT_VERSION}).`,
    );
  }
}

export function assertProductionProjectRefConfirmed(providedRef, expectedRef = PRODUCTION_PROJECT_REF) {
  const normalized = String(providedRef ?? '').trim();
  if (!normalized) {
    throw new Error('Production project ref confirmation is required.');
  }
  if (normalized !== expectedRef) {
    throw new Error(
      `Production project ref mismatch: expected ${expectedRef}, got ${normalized.slice(0, 16)}.`,
    );
  }
  return normalized;
}
