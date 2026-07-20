import { afterEach, describe, expect, it } from 'vitest';
import {
  assertLocalSupabaseApiUrl,
  assertLocalSupabaseContainerHost,
} from '../../scripts/lib/reve-local-supabase-guard.mjs';

describe('reve-local-supabase-guard', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it('accepts localhost Supabase URLs', () => {
    expect(() => assertLocalSupabaseApiUrl('http://127.0.0.1:54321')).not.toThrow();
    expect(() => assertLocalSupabaseApiUrl('http://localhost:54321')).not.toThrow();
  });

  it('rejects hosted and non-local Supabase URLs before cleanup', () => {
    expect(() => assertLocalSupabaseApiUrl('https://abc.supabase.co')).toThrow(
      /Refusing integration cleanup against hosted Supabase URL/,
    );
    expect(() => assertLocalSupabaseApiUrl('https://abc.supabase.in')).toThrow(
      /Refusing integration cleanup against hosted Supabase URL/,
    );
    expect(() => assertLocalSupabaseApiUrl('https://db.example.amazonaws.com/postgres')).toThrow(
      /Refusing integration cleanup against hosted Supabase URL/,
    );
    expect(() => assertLocalSupabaseApiUrl('https://staging.example.com')).toThrow(
      /Refusing integration cleanup against non-local Supabase URL/,
    );
  });

  it('reads configured URL from environment when explicit URL is omitted', () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://prod.supabase.co';
    expect(() => assertLocalSupabaseApiUrl()).toThrow(
      /Refusing integration cleanup against hosted Supabase URL/,
    );
  });

  it('accepts local docker database host targets', () => {
    expect(() =>
      assertLocalSupabaseContainerHost('supabase_db_test', () => '127.0.0.1\n'),
    ).not.toThrow();
    expect(() =>
      assertLocalSupabaseContainerHost('supabase_db_test', () => 'local\n'),
    ).not.toThrow();
  });

  it('rejects non-local docker database host targets', () => {
    expect(() =>
      assertLocalSupabaseContainerHost('supabase_db_test', () => '10.0.0.12\n'),
    ).toThrow(/Refusing integration cleanup: database host '10.0.0.12' does not look local./);
  });
});
