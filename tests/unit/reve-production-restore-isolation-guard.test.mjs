import { describe, expect, it } from 'vitest';
import {
  assertLocalRestoreValidationTarget,
  assertNotDirectProductionRestore,
  assertNotProductionDatabaseHost,
  assertRestoreValidationConfirmed,
  buildValidationDatabaseName,
} from '../../scripts/lib/reve-production-restore-isolation-guard.mjs';

describe('reve-production-restore-isolation-guard', () => {
  it('accepts local database hosts only', () => {
    expect(assertNotProductionDatabaseHost('local')).toBe('local');
    expect(assertNotProductionDatabaseHost('127.0.0.1')).toBe('127.0.0.1');
    expect(() => assertNotProductionDatabaseHost('db.bfhptqhgxignyggyxxkx.supabase.co')).toThrow(
      /hosted database host/,
    );
  });

  it('requires explicit restore validation confirmation', () => {
    delete process.env.REVE_CONFIRM_RESTORE_VALIDATION;
    expect(() => assertRestoreValidationConfirmed()).toThrow(/REVE_CONFIRM_RESTORE_VALIDATION/);
    process.env.REVE_CONFIRM_RESTORE_VALIDATION = '1';
    expect(assertRestoreValidationConfirmed()).toBeUndefined();
    delete process.env.REVE_CONFIRM_RESTORE_VALIDATION;
  });

  it('blocks direct production restore flags', () => {
    process.env.REVE_APPROVE_PRODUCTION_RESTORE = '1';
    expect(() => assertNotDirectProductionRestore()).toThrow(/not implemented/);
    delete process.env.REVE_APPROVE_PRODUCTION_RESTORE;
  });

  it('builds isolated validation database names', () => {
    const dbName = buildValidationDatabaseName();
    expect(dbName).toMatch(/^reve_backup_val_[a-f0-9]{8}$/);
  });

  it('validates local restore targets', () => {
    expect(() =>
      assertLocalRestoreValidationTarget({
        dbHost: 'local',
        apiUrl: 'http://127.0.0.1:54321',
      }),
    ).not.toThrow();
  });
});
