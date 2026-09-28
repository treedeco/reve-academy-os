import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import {
  createBoundedAuthFetch,
  decideProtectedAccess,
  MIDDLEWARE_AUTH_TIMEOUT_MS,
  type MiddlewareAuthDecision,
} from '@/lib/supabase/middleware-auth';

export type MiddlewareSessionResult = {
  response: NextResponse;
  decision: MiddlewareAuthDecision;
};

export async function updateSession(request: NextRequest): Promise<MiddlewareSessionResult> {
  let supabaseResponse = NextResponse.next({ request });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    return { response: supabaseResponse, decision: 'unavailable' };
  }

  const supabase = createServerClient(url, anonKey, {
    global: {
      fetch: createBoundedAuthFetch(MIDDLEWARE_AUTH_TIMEOUT_MS),
    },
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
        cookiesToSet.forEach(({ name, value }) => {
          request.cookies.set(name, value);
        });
        supabaseResponse = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => {
          supabaseResponse.cookies.set(name, value, options);
        });
      },
    },
  });

  const { data, error } = await supabase.auth.getUser();
  const decision = decideProtectedAccess({
    userId: data.user?.id ?? null,
    errorName: error?.name ?? null,
    errorStatus: typeof error?.status === 'number' ? error.status : null,
  });

  return { response: supabaseResponse, decision };
}
