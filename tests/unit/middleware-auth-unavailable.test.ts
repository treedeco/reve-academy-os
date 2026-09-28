import { describe, expect, it } from 'vitest';
import {
  createBoundedAuthFetch,
  decideProtectedAccess,
  MIDDLEWARE_AUTH_TIMEOUT_MS,
} from '@/lib/supabase/middleware-auth';

describe('middleware auth fail-closed decisions', () => {
  it('allows a protected route when Auth returns a verified user', () => {
    expect(
      decideProtectedAccess({
        userId: 'user-1',
        errorName: null,
        errorStatus: null,
      }),
    ).toBe('allow');
  });

  it('keeps the login redirect when there is no session', () => {
    expect(
      decideProtectedAccess({
        userId: null,
        errorName: 'AuthSessionMissingError',
        errorStatus: 400,
      }),
    ).toBe('login');
  });

  it('does not allow protected content when Auth rejects the session', () => {
    expect(
      decideProtectedAccess({
        userId: null,
        errorName: 'AuthApiError',
        errorStatus: 401,
      }),
    ).toBe('login');
  });

  it('fails closed when Auth returns 5xx', () => {
    expect(
      decideProtectedAccess({
        userId: null,
        errorName: 'AuthApiError',
        errorStatus: 503,
      }),
    ).toBe('unavailable');
  });

  it('fails closed on a retryable network failure without trusting a cookie', () => {
    expect(
      decideProtectedAccess({
        userId: null,
        errorName: 'AuthRetryableFetchError',
        errorStatus: 0,
      }),
    ).toBe('unavailable');
  });

  it('fails closed on a malformed Auth response', () => {
    expect(
      decideProtectedAccess({
        userId: null,
        errorName: 'AuthInvalidTokenResponseError',
        errorStatus: 500,
      }),
    ).toBe('unavailable');
  });

  it('fails closed when Auth returns neither a user nor a known signed-out error', () => {
    expect(
      decideProtectedAccess({
        userId: null,
        errorName: null,
        errorStatus: null,
      }),
    ).toBe('unavailable');
  });
});

describe('bounded middleware auth fetch', () => {
  it('uses a timeout below the platform middleware window', () => {
    expect(MIDDLEWARE_AUTH_TIMEOUT_MS).toBe(8_000);
    expect(MIDDLEWARE_AUTH_TIMEOUT_MS).toBeLessThan(25_000);
  });

  it('aborts a hanging Auth request within the configured bound', async () => {
    const timeoutMs = 80;
    const hangingFetch: typeof fetch = (_input, init) =>
      new Promise((_resolve, reject) => {
        const signal = init?.signal;
        if (!signal) {
          reject(new Error('missing abort signal'));
          return;
        }
        signal.addEventListener('abort', () => {
          reject(signal.reason instanceof Error ? signal.reason : new Error('aborted'));
        });
      });

    const started = Date.now();
    await expect(createBoundedAuthFetch(timeoutMs, hangingFetch)('https://auth.test/user')).rejects.toThrow();
    const elapsed = Date.now() - started;
    expect(elapsed).toBeLessThan(timeoutMs + 400);
    expect(elapsed).toBeGreaterThanOrEqual(timeoutMs - 20);
  });
});
