import { afterEach, describe, expect, it, vi } from 'vitest';
import { ProductionOperatorTimeoutError } from '../../scripts/lib/reve-production-operator-io.mjs';
import {
  permanentlyDeleteStudent,
  permanentlyDeleteTeacher,
  previewDeleteStudent,
  previewDeleteTeacher,
} from '../../scripts/lib/reve-production-owner-session.mjs';
import { runCleanupProductionDisposables } from '../../scripts/cleanup_phase_2b2b5_production_disposables.mjs';

const STUDENT_ID = '2e4716e5-6ad4-4e2e-bc39-7c5a435602e4';
const TEACHER_ID = '3f5827f6-7be5-5f3f-cd4a-8d6b546713f5';

function buildEnv() {
  process.env.PRODUCTION_URL = 'https://reve-academy-os.vercel.app';
  process.env.PRODUCTION_SUPABASE_URL = 'https://bfhptqhgxignyggyxxkx.supabase.co';
  process.env.PRODUCTION_SUPABASE_ANON_KEY = 'anon-key';
  process.env.PRODUCTION_OWNER_PASSWORD = 'owner-password';
  process.env.REVE_CONFIRM_PRODUCTION = '1';
}

function buildMockClient({
  disposableStudents = [],
  disposableTeachers = [],
  nonDisposableCount = 1,
} = {}) {
  const rpc = vi.fn(async (name) => {
    if (name === 'reve_owner_preview_delete_student') {
      return {
        data: [{ preflight_fingerprint: 'fp-student', lesson_count: 0, pass_count: 0, payment_count: 0, sms_notification_count: 0, schedule_slot_count: 0, schedule_change_request_count: 0, lesson_note_count: 0 }],
        error: null,
      };
    }
    if (name === 'reve_owner_preview_delete_teacher') {
      return {
        data: [{ preflight_fingerprint: 'fp-teacher', future_eligible_lesson_count: 0, active_schedule_slot_count: 0 }],
        error: null,
      };
    }
    if (name === 'reve_owner_permanently_delete_student' || name === 'reve_owner_permanently_delete_teacher') {
      throw new Error(`unexpected mutation rpc: ${name}`);
    }
    throw new Error(`unexpected rpc: ${name}`);
  });

  const from = vi.fn((table) => {
    if (table === 'students') {
      return {
        select: vi.fn((_cols, options = {}) => {
          if (options.head) {
            return {
              not: vi.fn(async () => ({ count: nonDisposableCount, error: null })),
            };
          }
          return {
            like: vi.fn(() => ({
              order: vi.fn(async () => ({ data: disposableStudents, error: null })),
            })),
          };
        }),
      };
    }
    if (table === 'teachers') {
      return {
        select: vi.fn(() => ({
          like: vi.fn(() => ({
            order: vi.fn(async () => ({ data: disposableTeachers, error: null })),
          })),
        })),
      };
    }
    throw new Error(`unexpected table: ${table}`);
  });

  return { rpc, from };
}

describe('cleanup-production-disposables', () => {
  afterEach(() => {
    delete process.env.PRODUCTION_URL;
    delete process.env.PRODUCTION_SUPABASE_URL;
    delete process.env.PRODUCTION_SUPABASE_ANON_KEY;
    delete process.env.PRODUCTION_OWNER_PASSWORD;
    delete process.env.REVE_CONFIRM_PRODUCTION;
    delete process.env.REVE_CLEANUP_APPLY_RUN_ID;
    vi.restoreAllMocks();
  });

  it('completes dry-run with zero candidates', async () => {
    buildEnv();
    const client = buildMockClient();
    const outputWriter = vi.fn();

    const exitCode = await runCleanupProductionDisposables({
      createSession: vi.fn(async () => ({ client, userId: STUDENT_ID })),
      buildRunId: () => 'CLEANUP-PHASE2B2B5-TEST-000001',
      outputWriter,
    });

    expect(exitCode).toBe(0);
    expect(outputWriter).toHaveBeenCalledOnce();
    expect(outputWriter.mock.calls[0][0]).toMatchObject({
      ok: true,
      mode: 'dry-run',
      totals: { students: 0, teachers: 0 },
    });
    expect(client.rpc).not.toHaveBeenCalled();
  });

  it('completes dry-run with disposable candidates using preview RPCs only', async () => {
    buildEnv();
    const client = buildMockClient({
      disposableStudents: [
        {
          id: STUDENT_ID,
          name: 'PHASE2B2B5-student',
          student_code: 'S-TEST',
          updated_at: '2026-01-01T00:00:00.000Z',
        },
      ],
      disposableTeachers: [
        {
          id: TEACHER_ID,
          name: 'PHASE2B2B5-teacher',
          teacher_code: 'T-TEST',
          updated_at: '2026-01-01T00:00:00.000Z',
          is_active: true,
        },
      ],
    });
    const outputWriter = vi.fn();

    const exitCode = await runCleanupProductionDisposables({
      createSession: vi.fn(async () => ({ client, userId: STUDENT_ID })),
      buildRunId: () => 'CLEANUP-PHASE2B2B5-TEST-000002',
      outputWriter,
    });

    expect(exitCode).toBe(0);
    expect(outputWriter.mock.calls[0][0].totals).toEqual({ students: 1, teachers: 1 });
    expect(client.rpc.mock.calls.map((call) => call[0])).toEqual([
      'reve_owner_preview_delete_student',
      'reve_owner_preview_delete_teacher',
    ]);
    expect(client.rpc.mock.calls.some((call) => call[0].includes('permanently_delete'))).toBe(false);
  });

  it('surfaces authentication failure', async () => {
    buildEnv();
    await expect(
      runCleanupProductionDisposables({
        createSession: vi.fn(async () => {
          throw new Error('Owner login failed: Invalid login credentials');
        }),
      }),
    ).rejects.toThrow(/Owner login failed/);
  });

  it('surfaces authentication request timeout', async () => {
    buildEnv();
    await expect(
      runCleanupProductionDisposables({
        createSession: vi.fn(async () => {
          throw new ProductionOperatorTimeoutError('fetch', 30_000, 'owner_sign_in');
        }),
      }),
    ).rejects.toBeInstanceOf(ProductionOperatorTimeoutError);
  });

  it('surfaces candidate query timeout', async () => {
    buildEnv();
    const client = {
      from: vi.fn(() => ({
        select: vi.fn(() => ({
          not: vi.fn(async () => {
            throw new ProductionOperatorTimeoutError('fetch', 30_000, 'candidate_query');
          }),
        })),
      })),
      rpc: vi.fn(),
    };

    await expect(
      runCleanupProductionDisposables({
        createSession: vi.fn(async () => ({ client, userId: STUDENT_ID })),
      }),
    ).rejects.toBeInstanceOf(ProductionOperatorTimeoutError);
  });

  it('surfaces preview RPC timeout', async () => {
    buildEnv();
    const client = buildMockClient({
      disposableStudents: [
        {
          id: STUDENT_ID,
          name: 'PHASE2B2B5-student',
          student_code: 'S-TEST',
          updated_at: '2026-01-01T00:00:00.000Z',
        },
      ],
    });
    client.rpc.mockImplementation(async (name) => {
      if (name === 'reve_owner_preview_delete_student') {
        throw new ProductionOperatorTimeoutError('fetch', 30_000, 'preview_delete_student');
      }
      throw new Error(`unexpected rpc: ${name}`);
    });

    await expect(
      runCleanupProductionDisposables({
        createSession: vi.fn(async () => ({ client, userId: STUDENT_ID })),
      }),
    ).rejects.toBeInstanceOf(ProductionOperatorTimeoutError);
  });

  it('exits after writing dry-run output', async () => {
    buildEnv();
    const outputWriter = vi.fn(async () => {});

    const exitCode = await runCleanupProductionDisposables({
      createSession: vi.fn(async () => ({ client: buildMockClient(), userId: STUDENT_ID })),
      outputWriter,
    });

    expect(exitCode).toBe(0);
    expect(outputWriter).toHaveBeenCalledOnce();
  });
});

describe('cleanup owner-session rpc helpers', () => {
  it('maps preview RPC fetch timeouts to staged timeout errors', async () => {
    const client = {
      rpc: vi.fn(async () => {
        throw new ProductionOperatorTimeoutError('fetch', 30_000);
      }),
    };

    await expect(previewDeleteStudent(client, STUDENT_ID)).rejects.toMatchObject({
      name: 'ProductionOperatorTimeoutError',
      stage: 'preview_delete_student',
    });
    await expect(previewDeleteTeacher(client, TEACHER_ID)).rejects.toMatchObject({
      name: 'ProductionOperatorTimeoutError',
      stage: 'preview_delete_teacher',
    });
  });
});
