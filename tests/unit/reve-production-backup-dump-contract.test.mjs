import { describe, expect, it } from 'vitest';
import {
  BACKUP_ARTIFACTS,
  RESTORE_ARTIFACT_ORDER,
  buildDryRunInspectionCommand,
  buildSupabaseDumpCommandArgs,
  assertManifestArtifactsComplete,
  listRequiredArtifactIds,
} from '../../scripts/lib/reve-production-backup-dump-contract.mjs';

describe('reve-production-backup-dump-contract', () => {
  it('declares eight required artifacts with explicit supabase db dump modes', () => {
    expect(BACKUP_ARTIFACTS).toHaveLength(8);
    expect(listRequiredArtifactIds()).toEqual([
      'roles',
      'schema-public',
      'schema-auth-storage',
      'migration-history-schema',
      'data-public',
      'data-auth',
      'data-storage-metadata',
      'migration-history-data',
    ]);
  });

  it('builds linked production dump commands without merging into one file', () => {
    const roles = buildSupabaseDumpCommandArgs('roles', 'roles.sql');
    expect(roles.argv).toEqual([
      'npx',
      'supabase',
      'db',
      'dump',
      '--linked',
      '--role-only',
      '-f',
      'roles.sql',
    ]);

    const storageData = buildSupabaseDumpCommandArgs('data-storage-metadata', 'data-storage-metadata.sql');
    expect(storageData.argv).toEqual([
      'npx',
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
      '-f',
      'data-storage-metadata.sql',
    ]);
  });

  it('uses schema-only and data-only modes separately (not a single default dump)', () => {
    const schemaPublic = buildSupabaseDumpCommandArgs('schema-public', 'schema-public.sql');
    expect(schemaPublic.dumpMode).toBe('schema-only');
    expect(schemaPublic.argv).not.toContain('--data-only');

    const dataPublic = buildSupabaseDumpCommandArgs('data-public', 'data-public.sql');
    expect(dataPublic.dumpMode).toBe('data-only');
    expect(dataPublic.argv).toContain('--data-only');
  });

  it('documents dependency-aware restore order with auth schema before public schema', () => {
    expect(RESTORE_ARTIFACT_ORDER).toEqual([
      'roles',
      'schema-auth-storage',
      'migration-history-schema',
      'schema-public',
      'data-auth',
      'data-storage-metadata',
      'data-public',
      'migration-history-data',
    ]);
    expect(RESTORE_ARTIFACT_ORDER.indexOf('schema-auth-storage')).toBeLessThan(
      RESTORE_ARTIFACT_ORDER.indexOf('schema-public'),
    );
    expect(RESTORE_ARTIFACT_ORDER.indexOf('data-auth')).toBeLessThan(
      RESTORE_ARTIFACT_ORDER.indexOf('data-public'),
    );
  });

  it('supports dry-run inspection commands for contract audit without production access', () => {
    const cmd = buildDryRunInspectionCommand('data-auth', 'dry.sql', true);
    expect(cmd.argv).toContain('--dry-run');
    expect(cmd.argv).toContain('--local');
    expect(cmd.argv).not.toContain('--linked');
  });

  it('fails closed when manifest artifacts are incomplete or unencrypted', () => {
    expect(() => assertManifestArtifactsComplete({ artifacts: [] })).toThrow(/missing artifacts array/);

    const complete = listRequiredArtifactIds().map((id) => ({
      id,
      relativePath: `${id}.sql.enc`,
      artifactType: 'data',
      sha256: 'a'.repeat(64),
      sizeBytes: 1,
      classification: 'data',
      includedSchemas: [],
      excludedSchemas: [],
      encrypted: id === 'roles' ? false : true,
    }));
    expect(() => assertManifestArtifactsComplete({ artifacts: complete })).toThrow(/must be encrypted/);
  });
});
