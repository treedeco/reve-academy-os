import { describe, expect, it } from 'vitest';
import {
  DISPOSABLE_NAME_PREFIX,
  PRODUCTION_APP_URL,
  PRODUCTION_PROJECT_REF,
  PRODUCTION_SUPABASE_URL,
  assertDisposableName,
  assertProductionAppUrl,
  assertProductionMutationConfirmed,
  assertProductionSupabaseUrl,
  isProductionMutationConfirmed,
} from '../../scripts/lib/reve-production-operator-guard.mjs';
import {
  redactProductionEvidence,
  redactUuid,
} from '../../scripts/lib/reve-production-evidence-redaction.mjs';

describe('reve-production-operator-guard', () => {
  it('accepts the configured production Supabase URL', () => {
    expect(assertProductionSupabaseUrl(PRODUCTION_SUPABASE_URL)).toBe(PRODUCTION_SUPABASE_URL);
  });

  it('rejects localhost Supabase URLs for production scripts', () => {
    expect(() => assertProductionSupabaseUrl('http://127.0.0.1:54321')).toThrow(
      /Refusing hosted operator action against local or private URL/,
    );
  });

  it('rejects the wrong hosted Supabase project ref', () => {
    expect(() => assertProductionSupabaseUrl('https://wrongref.supabase.co')).toThrow(
      /expected Supabase host/,
    );
  });

  it('accepts the configured production app URL', () => {
    expect(assertProductionAppUrl(PRODUCTION_APP_URL)).toBe(PRODUCTION_APP_URL);
  });

  it('rejects localhost app URLs for production scripts', () => {
    expect(() => assertProductionAppUrl('http://localhost:3000')).toThrow(/local app URL/);
  });

  it('requires explicit production mutation confirmation', () => {
    const previous = process.env.REVE_CONFIRM_PRODUCTION;
    delete process.env.REVE_CONFIRM_PRODUCTION;
    expect(isProductionMutationConfirmed()).toBe(false);
    expect(() => assertProductionMutationConfirmed('cleanup apply')).toThrow(/REVE_CONFIRM_PRODUCTION/);
    process.env.REVE_CONFIRM_PRODUCTION = '1';
    expect(isProductionMutationConfirmed()).toBe(true);
    process.env.REVE_CONFIRM_PRODUCTION = previous;
  });

  it('allows only disposable prefixed names', () => {
    expect(assertDisposableName(`${DISPOSABLE_NAME_PREFIX}20260729-ABC`, 'student')).toContain(
      DISPOSABLE_NAME_PREFIX,
    );
    expect(() => assertDisposableName('Real Student Name', 'student')).toThrow(/must start with/);
  });

  it('exports the expected production project ref', () => {
    expect(PRODUCTION_PROJECT_REF).toBe('bfhptqhgxignyggyxxkx');
  });
});

describe('reve-production-evidence-redaction', () => {
  it('redacts UUIDs and password metadata from evidence', () => {
    const redacted = redactProductionEvidence({
      stage1: {
        passwordConfigured: true,
        passwordLength: 15,
        authUserId: '2e4716e5-6ad4-4e2e-bc39-7c5a435602e4',
      },
      records: {
        students: {
          schedule: {
            id: '79a7228a-037a-407d-9cb6-57060c50da9e',
            name: 'PHASE2B2B5-20260729-ON8T7N Schedule Student',
          },
        },
      },
      cleanup: {
        deletedDisposableStudents: ['2473d534-59e2-4f83-ba61-1cbf58845a4d'],
        retainedRecords: [{ type: 'student', id: '79a7228a-037a-407d-9cb6-57060c50da9e' }],
      },
    });

    expect(redacted.stage1.passwordLength).toBeUndefined();
    expect(redacted.stage1.authUserId).toBe('2e4716e5…');
    expect(redacted.records.students.schedule.id).toBe('79a7228a…');
    expect(redacted.cleanup.deletedDisposableStudents[0]).toBe('2473d534…');
    expect(redacted.cleanup.retainedRecords[0].id).toBe('79a7228a…');
  });

  it('redacts short UUID-like strings safely', () => {
    expect(redactUuid('abc')).toBe('…');
  });
});
