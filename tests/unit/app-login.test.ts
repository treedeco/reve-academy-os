import { describe, expect, it } from 'vitest';
import { resolveLoginEmail } from '@/lib/auth/app-login';
import { OWNER_AUTH_EMAIL } from '@/lib/auth/owner-login';

describe('resolveLoginEmail', () => {
  it('maps owner username to auth email', () => {
    expect(resolveLoginEmail('reve')).toBe(OWNER_AUTH_EMAIL);
    expect(resolveLoginEmail(' REVE ')).toBe(OWNER_AUTH_EMAIL);
  });

  it('rejects legacy owner identifier without calling Supabase', () => {
    expect(resolveLoginEmail('owner-alpha@test.local')).toBeNull();
    expect(resolveLoginEmail('owner-alpha')).toBeNull();
  });

  it('accepts teacher email addresses', () => {
    expect(resolveLoginEmail('teacher-alpha@test.local')).toBe('teacher-alpha@test.local');
  });

  it('rejects unsupported usernames', () => {
    expect(resolveLoginEmail('T-A1')).toBeNull();
    expect(resolveLoginEmail('')).toBeNull();
  });
});
