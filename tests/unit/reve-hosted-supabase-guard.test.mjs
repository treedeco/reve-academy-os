import { afterEach, describe, expect, it } from 'vitest';
import {
  getServiceRoleKeyFromEnv,
  resolveHostedSupabaseUrl,
} from '../../scripts/lib/reve-hosted-supabase-guard.mjs';

describe('reve-hosted-supabase-guard', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it('accepts hosted Supabase URLs', () => {
    expect(resolveHostedSupabaseUrl('https://abc.supabase.co')).toBe('https://abc.supabase.co');
    expect(resolveHostedSupabaseUrl('https://abc.supabase.in/')).toBe('https://abc.supabase.in');
  });

  it('rejects localhost before hosted bootstrap', () => {
    expect(() => resolveHostedSupabaseUrl('http://127.0.0.1:54321')).toThrow(
      /Refusing hosted operator action against local or private URL/,
    );
    expect(() => resolveHostedSupabaseUrl('http://localhost:54321')).toThrow(
      /Refusing hosted operator action against local or private URL/,
    );
  });

  it('rejects private and unknown hosted targets', () => {
    expect(() => resolveHostedSupabaseUrl('http://10.0.0.12:54321')).toThrow(
      /Refusing hosted operator action against local or private URL/,
    );
    expect(() => resolveHostedSupabaseUrl('http://192.168.1.50:54321')).toThrow(
      /Refusing hosted operator action against local or private URL/,
    );
    expect(() => resolveHostedSupabaseUrl('https://db.example.amazonaws.com')).toThrow(
      /Refusing hosted operator action against non-Supabase URL/,
    );
    expect(() => resolveHostedSupabaseUrl('not-a-url')).toThrow(/Invalid Supabase URL/);
  });

  it('rejects non-Supabase hosted URLs', () => {
    expect(() => resolveHostedSupabaseUrl('https://staging.example.com')).toThrow(
      /Refusing hosted operator action against non-Supabase URL/,
    );
  });

  it('reads configured URL from environment when explicit URL is omitted', () => {
    process.env.SUPABASE_URL = 'https://prod.supabase.co';
    expect(resolveHostedSupabaseUrl()).toBe('https://prod.supabase.co');
  });

  it('requires service role key without NEXT_PUBLIC_ prefix', () => {
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-service-role-key';
    expect(getServiceRoleKeyFromEnv()).toBe('test-service-role-key');

    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    expect(() => getServiceRoleKeyFromEnv()).toThrow(/SUPABASE_SERVICE_ROLE_KEY is required/);

    process.env.NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY = 'leaked';
    expect(() => getServiceRoleKeyFromEnv()).toThrow(/must not use the NEXT_PUBLIC_ prefix/);
  });
});
