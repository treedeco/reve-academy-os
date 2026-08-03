/**
 * Explicit Supabase/pg_dump backup artifact contract (Phase 2B-2C1 v2).
 * Derived from `supabase db dump --dry-run` inspection — not from schema config alone.
 */
import { validateRestorePlan } from './reve-production-restore-plan.mjs';

export const BACKUP_MECHANISM = 'supabase_cli_pg_dump_multi_artifact';

export const BACKUP_ARTIFACTS = Object.freeze([
  {
    id: 'roles',
    fileName: 'roles.sql',
    encryptedFileName: 'roles.sql.enc',
    artifactType: 'roles',
    dumpMode: 'role-only',
    classification: 'roles',
    includedSchemas: [],
    excludedSchemas: [],
    captures: ['custom_role_grants_safe_subset'],
    supabaseArgs: ['supabase', 'db', 'dump', '--linked', '--role-only'],
    proofNotes:
      'pg_dumpall --roles-only; reserved Supabase roles stripped by CLI sed filters.',
  },
  {
    id: 'schema-public',
    fileName: 'schema-public.sql',
    encryptedFileName: 'schema-public.sql.enc',
    artifactType: 'schema',
    dumpMode: 'schema-only',
    classification: 'schema',
    includedSchemas: ['public'],
    excludedSchemas: ['auth', 'storage', 'supabase_migrations'],
    captures: [
      'public_tables',
      'public_functions_rpcs',
      'public_constraints_indexes',
      'public_rls_policies',
      'public_triggers',
      'public_sequences',
      'public_views',
    ],
    supabaseArgs: ['supabase', 'db', 'dump', '--linked', '--schema', 'public'],
    proofNotes: 'pg_dump --schema-only --schema=public',
  },
  {
    id: 'schema-auth-storage',
    fileName: 'schema-auth-storage.sql',
    encryptedFileName: 'schema-auth-storage.sql.enc',
    artifactType: 'schema',
    dumpMode: 'schema-only',
    classification: 'schema',
    includedSchemas: ['auth', 'storage'],
    excludedSchemas: ['public', 'supabase_migrations'],
    captures: ['auth_schema_ddl', 'storage_bucket_metadata_schema_ddl'],
    supabaseArgs: ['supabase', 'db', 'dump', '--linked', '--schema', 'auth,storage'],
    proofNotes:
      'Default CLI dump excludes auth/storage; explicit --schema required for DDL. Not included in default single-file dump.',
  },
  {
    id: 'migration-history-schema',
    fileName: 'migration-history-schema.sql',
    encryptedFileName: 'migration-history-schema.sql.enc',
    artifactType: 'schema',
    dumpMode: 'schema-only',
    classification: 'schema',
    includedSchemas: ['supabase_migrations'],
    excludedSchemas: ['public', 'auth', 'storage'],
    captures: ['supabase_migrations_schema_ddl'],
    supabaseArgs: ['supabase', 'db', 'dump', '--linked', '--schema', 'supabase_migrations'],
    proofNotes: 'pg_dump --schema-only --schema=supabase_migrations',
  },
  {
    id: 'data-public',
    fileName: 'data-public.sql',
    encryptedFileName: 'data-public.sql.enc',
    artifactType: 'data',
    dumpMode: 'data-only',
    classification: 'data',
    includedSchemas: ['public'],
    excludedSchemas: ['auth', 'storage', 'supabase_migrations'],
    captures: ['public_table_data'],
    supabaseArgs: ['supabase', 'db', 'dump', '--linked', '--data-only', '--schema', 'public'],
    proofNotes:
      'pg_dump --data-only --schema public with session_replication_role=replica preamble.',
  },
  {
    id: 'data-auth',
    fileName: 'data-auth.sql',
    encryptedFileName: 'data-auth.sql.enc',
    artifactType: 'data',
    dumpMode: 'data-only',
    classification: 'data',
    includedSchemas: ['auth'],
    excludedSchemas: ['public', 'storage', 'supabase_migrations'],
    captures: ['auth_users', 'auth_identities', 'auth_sessions_metadata_tables'],
    excludedTables: ['auth.schema_migrations'],
    supabaseArgs: ['supabase', 'db', 'dump', '--linked', '--data-only', '--schema', 'auth'],
    proofNotes:
      'Includes auth.users rows (password hashes). CLI excludes auth.schema_migrations automatically.',
  },
  {
    id: 'data-storage-metadata',
    fileName: 'data-storage-metadata.sql',
    encryptedFileName: 'data-storage-metadata.sql.enc',
    artifactType: 'data',
    dumpMode: 'data-only',
    classification: 'data',
    includedSchemas: ['storage'],
    excludedSchemas: ['public', 'auth', 'supabase_migrations'],
    captures: ['storage_buckets', 'storage_objects_metadata_rows'],
    excludedTables: ['storage.migrations', 'storage.buckets_vectors', 'storage.vector_indexes'],
    supabaseArgs: [
      'supabase',
      'db',
      'dump',
      '--linked',
      '--data-only',
      '--schema',
      'storage',
      '-x',
      'storage.buckets_vectors',
      '-x',
      'storage.vector_indexes',
    ],
    proofNotes:
      'Bucket/object metadata only; excludes storage.buckets_vectors and storage.vector_indexes per Supabase CLI guidance. Storage object binaries are NOT in PostgreSQL.',
  },
  {
    id: 'migration-history-data',
    fileName: 'migration-history-data.sql',
    encryptedFileName: 'migration-history-data.sql.enc',
    artifactType: 'data',
    dumpMode: 'data-only',
    classification: 'data',
    includedSchemas: ['supabase_migrations'],
    excludedSchemas: ['public', 'auth', 'storage'],
    captures: ['supabase_migrations.schema_migrations_rows'],
    supabaseArgs: [
      'supabase',
      'db',
      'dump',
      '--linked',
      '--data-only',
      '--schema',
      'supabase_migrations',
    ],
    proofNotes:
      'Default data-only dump excludes supabase_migrations; explicit --schema required.',
  },
]);

export const RESTORE_ARTIFACT_ORDER = Object.freeze([
  'roles',
  'schema-auth-storage',
  'migration-history-schema',
  'schema-public',
  'data-auth',
  'data-storage-metadata',
  'data-public',
  'migration-history-data',
]);

export const BACKUP_CONTENT_PROOF = Object.freeze({
  publicSchema: { artifactId: 'schema-public', proven: 'explicit_schema_only_dump' },
  publicData: { artifactId: 'data-public', proven: 'explicit_data_only_dump' },
  authSchema: { artifactId: 'schema-auth-storage', proven: 'explicit_schema_auth_storage_dump' },
  authUsersData: { artifactId: 'data-auth', proven: 'explicit_data_only_auth_dump' },
  storageSchema: { artifactId: 'schema-auth-storage', proven: 'explicit_schema_auth_storage_dump' },
  storageMetadata: { artifactId: 'data-storage-metadata', proven: 'explicit_data_only_storage_dump' },
  migrationHistorySchema: {
    artifactId: 'migration-history-schema',
    proven: 'explicit_schema_supabase_migrations_dump',
  },
  migrationHistoryData: {
    artifactId: 'migration-history-data',
    proven: 'explicit_data_only_supabase_migrations_dump',
  },
  functionsRpcs: { artifactId: 'schema-public', proven: 'pg_dump_schema_only_public' },
  constraintsIndexes: { artifactId: 'schema-public', proven: 'pg_dump_schema_only_public' },
  rlsPolicies: { artifactId: 'schema-public', proven: 'pg_dump_schema_only_public' },
  triggers: { artifactId: 'schema-public', proven: 'pg_dump_schema_only_public' },
  sequences: { artifactId: 'schema-public', proven: 'pg_dump_schema_only_public' },
  roles: { artifactId: 'roles', proven: 'pg_dumpall_roles_only' },
});

export const BACKUP_NOT_CAPTURED = Object.freeze([
  'storage_object_binary_payloads',
  'supabase_auth_provider_configuration',
  'supabase_auth_url_redirect_settings',
  'supabase_storage_cdn_configuration',
  'edge_functions_source_and_secrets',
  'vercel_environment_variables',
  'database_connection_passwords',
  'realtime_publication_internals',
  'pgsodium_root_keys',
]);

export function listRequiredArtifactIds() {
  return BACKUP_ARTIFACTS.map((artifact) => artifact.id);
}

export function getBackupArtifact(id) {
  const artifact = BACKUP_ARTIFACTS.find((entry) => entry.id === id);
  if (!artifact) {
    throw new Error(`Unknown backup artifact id: ${id}`);
  }
  return artifact;
}

export function buildSupabaseDumpCommandArgs(artifact, outputPath) {
  const definition = getBackupArtifact(artifact.id ?? artifact);
  const args = [...definition.supabaseArgs, '-f', outputPath];
  return {
    artifactId: definition.id,
    executable: 'npx',
    args,
    argv: ['npx', ...args],
    commandSummary: `npx ${args.join(' ')}`,
    dumpMode: definition.dumpMode,
  };
}

export function buildDryRunInspectionCommand(artifact, outputPath, useLocal = true) {
  const definition = getBackupArtifact(artifact.id ?? artifact);
  const args = definition.supabaseArgs.filter((arg) => arg !== '--linked');
  if (useLocal) {
    args.push('--local');
  } else {
    args.push('--linked');
  }
  args.push('--dry-run', '-f', outputPath);
  return {
    artifactId: definition.id,
    executable: 'npx',
    args,
    argv: ['npx', ...args],
    commandSummary: `npx ${args.join(' ')}`,
  };
}

export function assertManifestArtifactsComplete(manifest) {
  const artifacts = manifest?.artifacts;
  if (!Array.isArray(artifacts) || artifacts.length === 0) {
    throw new Error('Backup manifest is missing artifacts array.');
  }

  const ids = new Set(artifacts.map((entry) => entry.id));
  for (const requiredId of listRequiredArtifactIds()) {
    if (!ids.has(requiredId)) {
      throw new Error(`Backup manifest missing required artifact: ${requiredId}`);
    }
  }

  for (const entry of artifacts) {
    for (const field of [
      'id',
      'relativePath',
      'artifactType',
      'sha256',
      'sizeBytes',
      'classification',
      'includedSchemas',
      'excludedSchemas',
    ]) {
      if (entry[field] === undefined || entry[field] === null) {
        throw new Error(`Backup manifest artifact ${entry.id ?? 'unknown'} missing ${field}.`);
      }
    }
    if (!entry.encrypted) {
      throw new Error(`Backup manifest artifact ${entry.id} must be encrypted at rest.`);
    }
  }

  return artifacts;
}

export function resolveRestoreArtifacts(manifest) {
  assertManifestArtifactsComplete(manifest);
  validateRestorePlan(RESTORE_ARTIFACT_ORDER);
  const byId = new Map(manifest.artifacts.map((entry) => [entry.id, entry]));
  return RESTORE_ARTIFACT_ORDER.map((id) => {
    const entry = byId.get(id);
    if (!entry) {
      throw new Error(`Restore order references missing manifest artifact: ${id}`);
    }
    return entry;
  });
}
