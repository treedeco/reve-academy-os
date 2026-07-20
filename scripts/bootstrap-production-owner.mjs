/**
 * One-time (idempotent) production Owner bootstrap for hosted Supabase.
 *
 * Requires:
 *   SUPABASE_URL or NEXT_PUBLIC_SUPABASE_URL  (hosted *.supabase.co / *.supabase.in)
 *   SUPABASE_SERVICE_ROLE_KEY                 (server-only, never NEXT_PUBLIC_)
 *   OWNER_BOOTSTRAP_PASSWORD                  (one-time; remove from shell after use)
 *
 * Optional:
 *   OWNER_BOOTSTRAP_EMAIL         (default: reve@owner.local — required by current login mapping)
 *   OWNER_BOOTSTRAP_DISPLAY_NAME  (default: REVE Owner)
 *
 * Does NOT run local demo seeds or integration cleanup.
 */

import {
  getServiceRoleKeyFromEnv,
  resolveHostedSupabaseUrl,
} from './lib/reve-hosted-supabase-guard.mjs';

const OWNER_AUTH_EMAIL_DEFAULT = 'reve@owner.local';

function requiredBootstrapPassword() {
  const password = process.env.OWNER_BOOTSTRAP_PASSWORD;
  if (!password) {
    throw new Error(
      'OWNER_BOOTSTRAP_PASSWORD is required for bootstrap. Set it in the operator shell only; never commit it.',
    );
  }
  return password;
}

async function findAuthUserByEmail(apiUrl, serviceRoleKey, email) {
  const response = await fetch(
    `${apiUrl}/auth/v1/admin/users?email=${encodeURIComponent(email)}`,
    {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
      },
    },
  );

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Auth user lookup failed (${response.status}): ${body}`);
  }

  const payload = await response.json();
  const users = payload.users ?? payload;
  if (!Array.isArray(users) || users.length === 0) {
    return null;
  }
  return users[0];
}

async function createAuthUser(apiUrl, serviceRoleKey, email, password) {
  const response = await fetch(`${apiUrl}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
    }),
  });

  if (response.ok) {
    return response.json();
  }

  const body = await response.text();
  if (response.status === 422 && /already|exists|registered/i.test(body)) {
    const existing = await findAuthUserByEmail(apiUrl, serviceRoleKey, email);
    if (existing?.id) {
      return existing;
    }
  }

  throw new Error(`Auth user creation failed (${response.status}): ${body}`);
}

async function bootstrapOwnerProfile(apiUrl, serviceRoleKey, authUserId, displayName) {
  const response = await fetch(`${apiUrl}/rest/v1/rpc/reve_bootstrap_first_owner`, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      p_auth_user_id: authUserId,
      p_display_name: displayName,
    }),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`reve_bootstrap_first_owner failed (${response.status}): ${body}`);
  }

  return JSON.parse(body);
}

async function main() {
  const apiUrl = resolveHostedSupabaseUrl();
  const serviceRoleKey = getServiceRoleKeyFromEnv();
  const email = process.env.OWNER_BOOTSTRAP_EMAIL ?? OWNER_AUTH_EMAIL_DEFAULT;
  const displayName = process.env.OWNER_BOOTSTRAP_DISPLAY_NAME ?? 'REVE Owner';
  const password = requiredBootstrapPassword();

  if (email !== OWNER_AUTH_EMAIL_DEFAULT) {
    console.warn(
      `Warning: OWNER_BOOTSTRAP_EMAIL is '${email}'. The app maps username 'reve' to '${OWNER_AUTH_EMAIL_DEFAULT}' only.`,
    );
  }

  console.log(`Target Supabase project URL: ${apiUrl}`);
  console.log(`Bootstrap email: ${email}`);
  console.log('Creating or reusing Auth user (password not logged)...');

  const authUser = await createAuthUser(apiUrl, serviceRoleKey, email, password);
  if (!authUser?.id) {
    throw new Error('Auth user id missing after create/lookup.');
  }

  console.log(`Auth user id: ${authUser.id}`);
  console.log('Calling reve_bootstrap_first_owner...');

  const profileRows = await bootstrapOwnerProfile(
    apiUrl,
    serviceRoleKey,
    authUser.id,
    displayName,
  );

  const profile = Array.isArray(profileRows) ? profileRows[0] : profileRows;
  console.log(
    JSON.stringify(
      {
        profile_id: profile?.profile_id ?? null,
        role: profile?.role ?? null,
        account_state: profile?.account_state ?? null,
        display_name: profile?.display_name ?? null,
        idempotent_replay: profile?.idempotent_replay ?? null,
      },
      null,
      2,
    ),
  );

  console.log('Production Owner bootstrap complete.');
  console.log('Remove OWNER_BOOTSTRAP_PASSWORD from the operator shell and secret store rotation queue.');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
