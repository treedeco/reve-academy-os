import { isLegacyOwnerLoginIdentifier, resolveOwnerLoginEmail } from '@/lib/auth/owner-login';

/** Resolve a login username to a Supabase Auth email. */
export function resolveLoginEmail(username: string): string | null {
  const trimmed = username.trim();
  if (!trimmed) {
    return null;
  }

  if (isLegacyOwnerLoginIdentifier(trimmed)) {
    return null;
  }

  const ownerEmail = resolveOwnerLoginEmail(trimmed);
  if (ownerEmail) {
    return ownerEmail;
  }

  if (trimmed.includes('@')) {
    return trimmed.toLowerCase();
  }

  return null;
}
