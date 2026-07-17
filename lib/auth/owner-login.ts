/** Public owner login username (not secret). */
export const OWNER_LOGIN_USERNAME = 'reve';

/** Supabase Auth email mapped from {@link OWNER_LOGIN_USERNAME}. */
export const OWNER_AUTH_EMAIL = 'reve@owner.local';

/** Legacy demo login identifier — must no longer authenticate. */
export const LEGACY_OWNER_AUTH_EMAIL = 'owner-alpha@test.local';

export function resolveOwnerLoginEmail(username: string): string | null {
  const normalized = username.trim().toLowerCase();
  if (normalized === OWNER_LOGIN_USERNAME.toLowerCase()) {
    return OWNER_AUTH_EMAIL;
  }
  return null;
}

export function isLegacyOwnerLoginIdentifier(identifier: string): boolean {
  const normalized = identifier.trim().toLowerCase();
  return (
    normalized === LEGACY_OWNER_AUTH_EMAIL.toLowerCase() ||
    normalized === 'owner-alpha'
  );
}
