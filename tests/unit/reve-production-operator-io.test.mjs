import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  DEFAULT_CHILD_PROCESS_TIMEOUT_MS,
  ProductionOperatorTimeoutError,
  createTimedFetch,
  extractJsonPayload,
  runCommandWithTimeout,
} from '../../scripts/lib/reve-production-operator-io.mjs';
import { createProductionOwnerSession } from '../../scripts/lib/reve-production-owner-session.mjs';

describe('reve-production-operator-io', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('extracts JSON arrays from mixed CLI output', () => {
    const payload = extractJsonPayload('noise\n[{"id":"anon"}]\n');
    expect(Array.isArray(payload)).toBe(true);
    expect(payload[0].id).toBe('anon');
  });

  it('times out fetch requests', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => {
          reject(new DOMException('The operation was aborted.', 'AbortError'));
        });
      }),
    );

    const timedFetch = createTimedFetch(50);
    await expect(timedFetch('https://example.test/auth/v1/token')).rejects.toBeInstanceOf(
      ProductionOperatorTimeoutError,
    );
  });

  it('times out child processes and kills the process tree', async () => {
    await expect(
      runCommandWithTimeout(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], 200, {
        stage: 'test_child_timeout',
        useCmdWrapper: false,
      }),
    ).rejects.toMatchObject({
      name: 'ProductionOperatorTimeoutError',
      kind: 'child_process',
      timeoutMs: 200,
      stage: 'test_child_timeout',
    });
  }, 10_000);

  it('completes successful child processes within the timeout', async () => {
    const result = await runCommandWithTimeout(
      process.execPath,
      ['-e', "process.stdout.write('ok')"],
      DEFAULT_CHILD_PROCESS_TIMEOUT_MS,
      { stage: 'test_child_success', useCmdWrapper: false },
    );

    expect(result.stdout.trim()).toBe('ok');
    expect(result.exitCode).toBe(0);
  });
});

describe('reve-production-owner-session', () => {
  afterEach(() => {
    delete process.env.PRODUCTION_URL;
    delete process.env.PRODUCTION_SUPABASE_URL;
    delete process.env.PRODUCTION_SUPABASE_ANON_KEY;
    delete process.env.PRODUCTION_OWNER_PASSWORD;
  });

  function buildEnv() {
    process.env.PRODUCTION_URL = 'https://reve-academy-os.vercel.app';
    process.env.PRODUCTION_SUPABASE_URL = 'https://bfhptqhgxignyggyxxkx.supabase.co';
    process.env.PRODUCTION_SUPABASE_ANON_KEY = 'anon-key';
    process.env.PRODUCTION_OWNER_PASSWORD = 'owner-password';
  }

  it('creates a production owner session on success', async () => {
    buildEnv();

    const signInWithPassword = vi.fn(async () => ({
      data: {
        session: { access_token: 'access-token' },
        user: { id: '2e4716e5-6ad4-4e2e-bc39-7c5a435602e4' },
      },
      error: null,
    }));
    const maybeSingle = vi.fn(async () => ({
      data: { id: '2e4716e5-6ad4-4e2e-bc39-7c5a435602e4', role: 'owner', account_state: 'active' },
      error: null,
    }));
    const createClientImpl = vi.fn(() => ({
      auth: { signInWithPassword },
      from: vi.fn(() => ({
        select: vi.fn(() => ({
          eq: vi.fn(() => ({
            maybeSingle,
          })),
        })),
      })),
    }));

    const session = await createProductionOwnerSession({
      fetchImpl: vi.fn(async () => new Response('{}', { status: 200 })),
      createClientImpl,
    });

    expect(session.userId).toBe('2e4716e5-6ad4-4e2e-bc39-7c5a435602e4');
    expect(signInWithPassword).toHaveBeenCalledOnce();
  });

  it('fails authentication without exposing secrets', async () => {
    buildEnv();
    process.env.PRODUCTION_OWNER_PASSWORD = 'wrong-password';

    const createClientImpl = vi.fn(() => ({
      auth: {
        signInWithPassword: vi.fn(async () => ({
          data: { session: null, user: null },
          error: { message: 'Invalid login credentials' },
        })),
      },
    }));

    await expect(
      createProductionOwnerSession({
        fetchImpl: vi.fn(async () => new Response('{}', { status: 200 })),
        createClientImpl,
      }),
    ).rejects.toThrow(/Owner login failed: Invalid login credentials/);
  });

  it('surfaces fetch timeouts during owner sign-in', async () => {
    buildEnv();
    vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => {
          reject(new DOMException('The operation was aborted.', 'AbortError'));
        });
      }),
    );

    await expect(
      createProductionOwnerSession({
        fetchTimeoutMs: 50,
      }),
    ).rejects.toBeInstanceOf(ProductionOperatorTimeoutError);
  });
});
