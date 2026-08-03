/**
 * Restore artifact dependency plan and managed-schema boundary enforcement.
 */
import { RESTORE_ARTIFACT_ORDER, getBackupArtifact } from './reve-production-backup-dump-contract.mjs';

export const MANAGED_SCHEMA_ARTIFACT_ID = 'schema-auth-storage';

export const RESTORE_ARTIFACT_DEPENDENCIES = Object.freeze({
  roles: [],
  'schema-auth-storage': ['roles'],
  'migration-history-schema': ['roles'],
  'schema-public': ['schema-auth-storage', 'migration-history-schema'],
  'data-auth': ['schema-auth-storage'],
  'data-storage-metadata': ['schema-auth-storage'],
  'data-public': ['schema-public', 'data-auth', 'data-storage-metadata'],
  'migration-history-data': ['migration-history-schema'],
});

/** Previous invalid order retained for regression tests. */
export const RESTORE_ARTIFACT_ORDER_PREVIOUS_INVALID = Object.freeze([
  'roles',
  'schema-public',
  'schema-auth-storage',
  'migration-history-schema',
  'data-public',
  'data-auth',
  'data-storage-metadata',
  'migration-history-data',
]);

/**
 * Regression fixture: public.profiles.id REFERENCES auth.users(id).
 * schema-public before schema-auth-storage cannot satisfy auth.users dependency.
 */
export const AUTH_USERS_DEPENDENCY_FIXTURE = Object.freeze({
  description: 'public.profiles foreign key to auth.users',
  publicObject: 'public.profiles',
  referencedObject: 'auth.users',
  blockingReason: 'schema-public references auth.users before auth schema exists',
});

export function validateRestorePlan(order, dependencies = RESTORE_ARTIFACT_DEPENDENCIES) {
  const normalized = [...order];
  const seen = new Set();

  for (const artifactId of normalized) {
    const required = dependencies[artifactId];
    if (!required) {
      throw new Error(`Restore plan references unknown artifact: ${artifactId}`);
    }
    for (const dependencyId of required) {
      if (!seen.has(dependencyId)) {
        throw new Error(
          `Restore dependency violation: ${artifactId} requires ${dependencyId} to be restored first.`,
        );
      }
    }
    seen.add(artifactId);
  }

  for (const requiredId of RESTORE_ARTIFACT_ORDER) {
    if (!seen.has(requiredId)) {
      throw new Error(`Restore plan missing required artifact: ${requiredId}`);
    }
  }

  return normalized;
}

export function assertManagedSchemaRestoreBoundary({
  artifactId,
  validationDatabaseName = null,
  dbHost = null,
  apiUrl = null,
}) {
  if (artifactId !== MANAGED_SCHEMA_ARTIFACT_ID) {
    return;
  }

  if (!validationDatabaseName || !/^reve_backup_val_[a-f0-9]{8}$/.test(validationDatabaseName)) {
    throw new Error(
      'Managed schema artifact schema-auth-storage may only be applied to an isolated validation database.',
    );
  }

  const normalizedHost = String(dbHost ?? '').trim().toLowerCase();
  if (normalizedHost && !['', '127.0.0.1', '::1', 'local'].includes(normalizedHost)) {
    throw new Error('Managed schema artifacts must not be applied to hosted database hosts.');
  }

  const url = String(apiUrl ?? '').trim().toLowerCase();
  if (url && /supabase\.co|supabase\.in/.test(url)) {
    throw new Error('Managed schema artifacts must not be applied with hosted Supabase URLs.');
  }

  if (process.env.REVE_APPROVE_PRODUCTION_RESTORE === '1') {
    throw new Error('Direct production managed-schema restore is prohibited in Phase 2B-2C1.');
  }
}

export function describeRestorePlan(order = RESTORE_ARTIFACT_ORDER) {
  return order.map((artifactId) => {
    const artifact = getBackupArtifact(artifactId);
    return {
      id: artifactId,
      artifactType: artifact.artifactType,
      dependsOn: [...(RESTORE_ARTIFACT_DEPENDENCIES[artifactId] ?? [])],
    };
  });
}
