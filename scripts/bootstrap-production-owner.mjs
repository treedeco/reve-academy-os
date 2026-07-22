/**
 * One-time (idempotent) production Owner bootstrap for hosted Supabase.
 *
 * Requires:
 *   SUPABASE_URL or NEXT_PUBLIC_SUPABASE_URL  (hosted *.supabase.co / *.supabase.in)
 *   SUPABASE_SECRET_KEY (preferred) or SUPABASE_SERVICE_ROLE_KEY (legacy JWT fallback)
 *   OWNER_BOOTSTRAP_PASSWORD                  (one-time; remove from shell after use)
 *
 * Optional:
 *   OWNER_BOOTSTRAP_EMAIL         (default: reve@owner.local — required by current login mapping)
 *   OWNER_BOOTSTRAP_DISPLAY_NAME  (default: REVE Owner)
 *
 * Does NOT run local demo seeds or integration cleanup.
 */

import {
  AUTH_ADMIN_PATH,
  OWNER_AUTH_EMAIL_DEFAULT,
  bootstrapOwnerProfile,
  createSupabaseAdminClient,
  reportBootstrapError,
  resolveOrCreateAuthUser,
} from './lib/bootstrap-production-owner-core.mjs';
import {
  getSupabaseAdminKeyFromEnv,
  resolveHostedSupabaseUrl,
} from './lib/reve-hosted-supabase-guard.mjs';

function requiredBootstrapPassword() {
  const password = process.env.OWNER_BOOTSTRAP_PASSWORD;
  if (!password) {
    throw new Error(
      'OWNER_BOOTSTRAP_PASSWORD is required for bootstrap. Set it in the operator shell only; never commit it.',
    );
  }
  return password;
}

async function main() {
  const apiUrl = resolveHostedSupabaseUrl();
  const secretKey = getSupabaseAdminKeyFromEnv();
  const email = process.env.OWNER_BOOTSTRAP_EMAIL ?? OWNER_AUTH_EMAIL_DEFAULT;
  const displayName = process.env.OWNER_BOOTSTRAP_DISPLAY_NAME ?? 'REVE Owner';
  const password = requiredBootstrapPassword();
  const hostname = new URL(apiUrl).hostname;

  if (email !== OWNER_AUTH_EMAIL_DEFAULT) {
    console.warn(
      `Warning: OWNER_BOOTSTRAP_EMAIL is '${email}'. The app maps username 'reve' to '${OWNER_AUTH_EMAIL_DEFAULT}' only.`,
    );
  }

  console.log(`Target Supabase project URL: ${apiUrl}`);
  console.log(`Bootstrap email: ${email}`);
  console.log('Creating or reusing Auth user (password not logged)...');

  const adminClient = createSupabaseAdminClient(apiUrl, secretKey);

  const authUser = await resolveOrCreateAuthUser(adminClient, email, password);
  if (!authUser?.id) {
    throw new Error('Auth user id missing after create/lookup.');
  }

  console.log(`Auth user id: ${authUser.id}`);
  console.log('Calling reve_bootstrap_first_owner...');

  const profileRows = await bootstrapOwnerProfile(adminClient, authUser.id, displayName);

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
  const hostname = (() => {
    try {
      return new URL(resolveHostedSupabaseUrl()).hostname;
    } catch {
      return null;
    }
  })();

  reportBootstrapError(error, {
    operation: error?.operation ?? 'bootstrap-production-owner',
    hostname,
    path: error?.path ?? null,
  });
  process.exit(1);
});
