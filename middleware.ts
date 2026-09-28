import { NextResponse, type NextRequest } from 'next/server';
import { updateSession } from '@/lib/supabase/middleware';

const PUBLIC_PATHS = new Set(['/login']);

function redirectToLogin(request: NextRequest, sessionResponse: NextResponse) {
  const loginUrl = request.nextUrl.clone();
  loginUrl.pathname = '/login';
  loginUrl.searchParams.set('next', request.nextUrl.pathname);
  const redirect = NextResponse.redirect(loginUrl);
  for (const cookie of sessionResponse.headers.getSetCookie()) {
    redirect.headers.append('set-cookie', cookie);
  }
  return redirect;
}

function unavailableResponse() {
  return new NextResponse('인증 서비스를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.', {
    status: 503,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/plain; charset=utf-8',
      'Retry-After': '30',
    },
  });
}

export async function middleware(request: NextRequest) {
  const { response, decision } = await updateSession(request);
  const { pathname } = request.nextUrl;

  if (
    pathname.startsWith('/_next') ||
    pathname.startsWith('/favicon') ||
    pathname.includes('.')
  ) {
    return response;
  }

  if (PUBLIC_PATHS.has(pathname)) {
    return response;
  }

  if (decision === 'allow') {
    return response;
  }

  if (decision === 'login') {
    return redirectToLogin(request, response);
  }

  return unavailableResponse();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
