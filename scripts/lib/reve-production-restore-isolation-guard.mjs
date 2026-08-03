/**
 * Fail-closed guards for isolated local restore validation only.
 * Never allow production/hosted restore targets in this phase slice.
 */
import crypto from 'node:crypto';
import { PRODUCTION_PROJECT_REF } from './reve-production-operator-guard.mjs';

const LOCAL_DB_HOSTS = new Set(['', '127.0.0.1', '::1', 'local']);
const HOSTED_HOST_PATTERNS = [
  /supabase\.co$/i,
  /supabase\.in$/i,
  /\.amazonaws\.com$/i,
  /\.azure\./i,
  /\.gcp\./i,
];

export function assertNotProductionDatabaseHost(host) {
  const normalized = String(host ?? '').trim().toLowerCase();
  if (!normalized || LOCAL_DB_HOSTS.has(normalized)) {
    return normalized;
  }

  if (HOSTED_HOST_PATTERNS.some((pattern) => pattern.test(normalized))) {
    throw new Error(`Refusing restore validation against hosted database host '${normalized}'.`);
  }

  if (normalized.includes(PRODUCTION_PROJECT_REF)) {
    throw new Error('Refusing restore validation against production project host.');
  }

  throw new Error(`Refusing restore validation against non-local database host '${normalized}'.`);
}

export function assertLocalSupabaseApiUrlForRestore(apiUrl) {
  const url = String(apiUrl ?? process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? '').trim();
  if (!url) {
    return null;
  }

  const lower = url.toLowerCase();
  if (/supabase\.co|supabase\.in|\.amazonaws\.com|\.azure\.|\.gcp\./.test(lower)) {
    throw new Error(`Refusing restore validation with hosted Supabase URL.`);
  }
  if (!/127\.0\.0\.1|localhost/.test(lower)) {
    throw new Error(`Refusing restore validation with non-local Supabase URL.`);
  }
  return url;
}

export function assertLocalRestoreValidationTarget({ dbHost, apiUrl = null }) {
  assertNotProductionDatabaseHost(dbHost);
  assertLocalSupabaseApiUrlForRestore(apiUrl);
}

export function buildValidationDatabaseName(prefix = 'reve_backup_val') {
  const suffix = crypto.randomBytes(4).toString('hex');
  return `${prefix}_${suffix}`;
}

export function assertValidationDatabaseName(dbName) {
  const normalized = String(dbName ?? '').trim();
  if (!/^reve_backup_val_[a-f0-9]{8}$/.test(normalized)) {
    throw new Error(`Unexpected validation database name: ${normalized.slice(0, 32)}`);
  }
  return normalized;
}

export function assertRestoreValidationConfirmed() {
  const flag = (process.env.REVE_CONFIRM_RESTORE_VALIDATION ?? '').trim().toLowerCase();
  if (flag !== '1' && flag !== 'true' && flag !== 'yes') {
    throw new Error(
      'Isolated restore validation requires REVE_CONFIRM_RESTORE_VALIDATION=1 (PowerShell: -ConfirmRestoreValidation).',
    );
  }
}

export function assertNotDirectProductionRestore() {
  const flag = (process.env.REVE_APPROVE_PRODUCTION_RESTORE ?? '').trim().toLowerCase();
  if (flag === '1' || flag === 'true' || flag === 'yes') {
    throw new Error(
      'Direct production restore is not implemented in Phase 2B-2C1. Use the manual recovery runbook with separate approval.',
    );
  }
}
