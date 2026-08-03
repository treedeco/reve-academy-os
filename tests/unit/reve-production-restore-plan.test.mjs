import { describe, expect, it } from 'vitest';
import {
  AUTH_USERS_DEPENDENCY_FIXTURE,
  RESTORE_ARTIFACT_ORDER_PREVIOUS_INVALID,
  assertManagedSchemaRestoreBoundary,
  validateRestorePlan,
} from '../../scripts/lib/reve-production-restore-plan.mjs';
import { RESTORE_ARTIFACT_ORDER } from '../../scripts/lib/reve-production-backup-dump-contract.mjs';

describe('reve-production-restore-plan', () => {
  it('accepts dependency-aware restore order with auth schema before public schema', () => {
    expect(() => validateRestorePlan(RESTORE_ARTIFACT_ORDER)).not.toThrow();
    expect(RESTORE_ARTIFACT_ORDER.indexOf('schema-auth-storage')).toBeLessThan(
      RESTORE_ARTIFACT_ORDER.indexOf('schema-public'),
    );
    expect(RESTORE_ARTIFACT_ORDER.indexOf('data-auth')).toBeLessThan(
      RESTORE_ARTIFACT_ORDER.indexOf('data-public'),
    );
  });

  it('rejects the previous invalid order for auth.users dependency regression', () => {
    expect(RESTORE_ARTIFACT_ORDER_PREVIOUS_INVALID.indexOf('schema-public')).toBeLessThan(
      RESTORE_ARTIFACT_ORDER_PREVIOUS_INVALID.indexOf('schema-auth-storage'),
    );
    expect(() => validateRestorePlan(RESTORE_ARTIFACT_ORDER_PREVIOUS_INVALID)).toThrow(
      /schema-public requires schema-auth-storage/,
    );
  });

  it('enforces managed-schema boundary for schema-auth-storage only on isolated validation DB', () => {
    expect(() =>
      assertManagedSchemaRestoreBoundary({
        artifactId: 'schema-auth-storage',
        validationDatabaseName: 'reve_backup_val_deadbeef',
        dbHost: 'local',
        apiUrl: 'http://127.0.0.1:54321',
      }),
    ).not.toThrow();

    expect(() =>
      assertManagedSchemaRestoreBoundary({
        artifactId: 'schema-auth-storage',
        validationDatabaseName: 'postgres',
        dbHost: 'local',
      }),
    ).toThrow(/isolated validation database/);

    expect(() =>
      assertManagedSchemaRestoreBoundary({
        artifactId: 'schema-auth-storage',
        validationDatabaseName: 'reve_backup_val_deadbeef',
        dbHost: 'db.example.supabase.co',
      }),
    ).toThrow(/hosted database hosts/);

    expect(() =>
      assertManagedSchemaRestoreBoundary({
        artifactId: 'schema-public',
        validationDatabaseName: 'postgres',
      }),
    ).not.toThrow();
  });
});
