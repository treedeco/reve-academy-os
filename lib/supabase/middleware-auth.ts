/**
 * Middleware auth failure policy.
 *
 * @supabase/supabase-js getUser() does not accept an AbortSignal.
 * @supabase/ssr createServerClient accepts global.fetch, and auth-js uses that
 * fetch for GET /user. A per-request AbortSignal.timeout is the supported bound.
 *
 * 8s is above observed icn1 → ap-northeast-2 Auth latency (sub-second to a few
 * seconds) and below Vercel's middleware invocation window, so an unavailable
 * Auth host cannot run until the platform 504.
 */
export const MIDDLEWARE_AUTH_TIMEOUT_MS = 8_000;

export type MiddlewareAuthDecision = 'allow' | 'login' | 'unavailable';

export function createBoundedAuthFetch(
  timeoutMs: number,
  baseFetch: typeof fetch = fetch,
): typeof fetch {
  return (input, init) => {
    const timeoutSignal = AbortSignal.timeout(timeoutMs);
    const signal = init?.signal ? AbortSignal.any([init.signal, timeoutSignal]) : timeoutSignal;
    return baseFetch(input, { ...init, signal });
  };
}

/**
 * Fail closed. A present session cookie is not proof of authentication.
 * Only a verified user may continue. A completed "no session" or 4xx Auth
 * response redirects to login. Timeouts, network failures, malformed Auth
 * payloads, and 5xx responses are unavailable — never an authenticated session.
 */
export function decideProtectedAccess(input: {
  userId: string | null;
  errorName: string | null;
  errorStatus: number | null;
}): MiddlewareAuthDecision {
  if (input.userId) {
    return 'allow';
  }

  if (input.errorName === 'AuthSessionMissingError') {
    return 'login';
  }

  if (
    input.errorName === 'AuthApiError' &&
    input.errorStatus !== null &&
    input.errorStatus < 500
  ) {
    return 'login';
  }

  return 'unavailable';
}
