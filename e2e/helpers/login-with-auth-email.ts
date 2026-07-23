import { createServerClient, type CookieOptions } from '@supabase/ssr';
import type { BrowserContext, Page } from '@playwright/test';
import { expect } from '@playwright/test';

type StoredCookie = {
  name: string;
  value: string;
  options: CookieOptions;
};

function requireSupabaseEnv(): { url: string; anonKey: string } {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    throw new Error('NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY are required for e2e auth.');
  }
  return { url, anonKey };
}

async function signInAndCollectCookies(email: string, password: string): Promise<StoredCookie[]> {
  const { url, anonKey } = requireSupabaseEnv();
  const cookies: StoredCookie[] = [];

  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return [];
      },
      setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
        cookies.push(...cookiesToSet);
      },
    },
  });

  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    throw new Error(`Failed to sign in test user: ${error.message}`);
  }

  if (cookies.length === 0) {
    throw new Error('Supabase auth cookies were not set after sign-in.');
  }

  return cookies;
}

function normalizeSameSite(value: CookieOptions['sameSite']): 'Lax' | 'Strict' | 'None' {
  if (typeof value !== 'string') {
    return 'Lax';
  }

  const normalized = value.toLowerCase();
  if (normalized === 'strict') {
    return 'Strict';
  }
  if (normalized === 'none') {
    return 'None';
  }
  return 'Lax';
}

function toPlaywrightCookies(stored: StoredCookie[]) {
  const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://127.0.0.1:3000';
  const hostname = new URL(baseURL).hostname;

  return stored.map(({ name, value, options }) => ({
    name,
    value,
    domain: hostname,
    path: options.path ?? '/',
    httpOnly: options.httpOnly ?? false,
    secure: options.secure ?? false,
    sameSite: normalizeSameSite(options.sameSite),
  }));
}

export async function loginWithAuthEmail(
  context: BrowserContext,
  email: string,
  password: string,
): Promise<void> {
  const stored = await signInAndCollectCookies(email, password);
  await context.addCookies(toPlaywrightCookies(stored));
}

export async function loginWithAuthEmailAndOpenDashboard(
  page: Page,
  email: string,
  password: string,
): Promise<void> {
  await loginWithAuthEmail(page.context(), email, password);
  await page.goto('/dashboard');
  await expect(page).toHaveURL(/\/dashboard/, { timeout: 20_000 });
}
