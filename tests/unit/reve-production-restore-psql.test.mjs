import { describe, expect, it } from 'vitest';
import {
  RESTORE_VALIDATION_ARTIFACT_APPLY_USER,
  RESTORE_VALIDATION_BOOTSTRAP_USER,
  listReservedRolesReferenced,
  resolveRestoreValidationPsqlUser,
  rolesSqlTouchesReservedRole,
} from '../../scripts/lib/reve-production-restore-psql.mjs';

describe('reve-production-restore-psql', () => {
  it('uses postgres for bootstrap and supabase_admin for artifact apply', () => {
    expect(resolveRestoreValidationPsqlUser('bootstrap')).toBe(RESTORE_VALIDATION_BOOTSTRAP_USER);
    expect(resolveRestoreValidationPsqlUser('apply_artifact')).toBe(
      RESTORE_VALIDATION_ARTIFACT_APPLY_USER,
    );
    expect(RESTORE_VALIDATION_BOOTSTRAP_USER).toBe('postgres');
    expect(RESTORE_VALIDATION_ARTIFACT_APPLY_USER).toBe('supabase_admin');
  });

  it('detects reserved-role statements without requiring artifact mutation', () => {
    const sql = `
SET client_encoding = 'UTF8';
ALTER ROLE "supabase_admin" SET search_path TO "auth", "public";
ALTER ROLE "anon" SET "statement_timeout" TO '3s';
`;
    expect(rolesSqlTouchesReservedRole(sql)).toBe(true);
    expect(listReservedRolesReferenced(sql)).toEqual(
      expect.arrayContaining(['supabase_admin']),
    );
  });

  it('does not flag safe custom timeout-only role dumps as reserved when absent', () => {
    const sql = `
ALTER ROLE "anon" SET "statement_timeout" TO '3s';
ALTER ROLE "authenticated" SET "statement_timeout" TO '8s';
`;
    expect(rolesSqlTouchesReservedRole(sql)).toBe(false);
  });
});
