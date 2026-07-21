/**
 * Fail-closed guards for hosted Supabase operator scripts (bootstrap only).
 * Not used by local integration cleanup or demo seeds.
 */

function parseHostname(apiUrl) {
  let parsed;
  try {
    parsed = new URL(apiUrl);
  } catch {
    throw new Error(`Invalid Supabase URL: ${apiUrl}`);
  }
  return parsed.hostname.toLowerCase();
}

function isPrivateOrLocalHostname(hostname) {
  if (hostname === 'localhost' || hostname === '::1') {
    return true;
  }

  const ipv4Match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(hostname);
  if (!ipv4Match) {
    return false;
  }

  const octets = ipv4Match.slice(1).map((part) => Number(part));
  if (octets.some((part) => part > 255)) {
    return true;
  }

  const [a, b] = octets;
  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 0) return true;

  return false;
}

function isHostedSupabaseHostname(hostname) {
  return (
    hostname.endsWith('.supabase.co') ||
    hostname.endsWith('.supabase.in') ||
    hostname === 'supabase.co' ||
    hostname === 'supabase.in'
  );
}

export function resolveHostedSupabaseUrl(apiUrl) {
  const url = (apiUrl ?? process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? '').trim();
  if (!url) {
    throw new Error(
      'Hosted Supabase URL is required. Set SUPABASE_URL or NEXT_PUBLIC_SUPABASE_URL.',
    );
  }

  const hostname = parseHostname(url);

  if (isPrivateOrLocalHostname(hostname)) {
    throw new Error(`Refusing hosted operator action against local or private URL: ${url}`);
  }
  if (!isHostedSupabaseHostname(hostname)) {
    throw new Error(`Refusing hosted operator action against non-Supabase URL: ${url}`);
  }

  return url.replace(/\/$/, '');
}

function assertAdminKeyNotPublic() {
  if (
    process.env.NEXT_PUBLIC_SUPABASE_SECRET_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY
  ) {
    throw new Error('Supabase admin API keys must not use the NEXT_PUBLIC_ prefix.');
  }
}

export function getSupabaseAdminKeyFromEnv() {
  assertAdminKeyNotPublic();

  const secretKey = process.env.SUPABASE_SECRET_KEY?.trim();
  const legacyServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  const key = secretKey || legacyServiceRoleKey;

  if (!key) {
    throw new Error(
      'SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY is required for hosted operator scripts.',
    );
  }

  return key;
}

/** @deprecated Prefer getSupabaseAdminKeyFromEnv(). Legacy alias for tests and callers. */
export function getServiceRoleKeyFromEnv() {
  return getSupabaseAdminKeyFromEnv();
}
