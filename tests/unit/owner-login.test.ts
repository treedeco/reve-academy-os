import { describe, expect, it } from 'vitest';
import {
  isLegacyOwnerLoginIdentifier,
  LEGACY_OWNER_AUTH_EMAIL,
  OWNER_AUTH_EMAIL,
  OWNER_LOGIN_USERNAME,
  resolveOwnerLoginEmail,
} from '@/lib/auth/owner-login';

describe('owner login mapping', () => {
  it('maps reve username to Supabase auth email', () => {
    expect(resolveOwnerLoginEmail('reve')).toBe(OWNER_AUTH_EMAIL);
    expect(resolveOwnerLoginEmail(' REVE ')).toBe(OWNER_AUTH_EMAIL);
  });

  it('rejects unknown usernames', () => {
    expect(resolveOwnerLoginEmail('owner-alpha')).toBeNull();
    expect(resolveOwnerLoginEmail('admin')).toBeNull();
  });

  it('identifies legacy login identifiers', () => {
    expect(isLegacyOwnerLoginIdentifier(LEGACY_OWNER_AUTH_EMAIL)).toBe(true);
    expect(isLegacyOwnerLoginIdentifier('owner-alpha')).toBe(true);
    expect(isLegacyOwnerLoginIdentifier(OWNER_LOGIN_USERNAME)).toBe(false);
  });
});
