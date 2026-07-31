/**
 * Operator-only: reset production Owner Auth password (hosted Supabase).
 *
 * Use when Dashboard only offers "Send password recovery" and the Auth email
 * is reve@owner.local (no real inbox).
 *
 * Requires (operator shell only; never commit or log):
 *   SUPABASE_URL or hosted default via project link
 *   SUPABASE_SECRET_KEY (preferred) or SUPABASE_SERVICE_ROLE_KEY
 *   OWNER_BOOTSTRAP_PASSWORD or NEW_OWNER_PASSWORD  — the new password to set
 *
 * Optional:
 *   OWNER_BOOTSTRAP_EMAIL (default: reve@owner.local)
 */

import { createClient } from '@supabase/supabase-js';
import {
  OWNER_AUTH_EMAIL_DEFAULT,
  createSupabaseAdminClient,
  listAuthUsersByEmail,
  normalizeBootstrapEmail,
  reportBootstrapError,
} from './lib/bootstrap-production-owner-core.mjs';
import {
  getSupabaseAdminKeyFromEnv,
  resolveHostedSupabaseUrl,
} from './lib/reve-hosted-supabase-guard.mjs';
import {
  PRODUCTION_PROJECT_REF,
  assertProductionMutationConfirmed,
  assertProductionSupabaseUrl,
} from './lib/reve-production-operator-guard.mjs';

function requiredNewPassword() {
  const password = process.env.NEW_OWNER_PASSWORD ?? process.env.OWNER_BOOTSTRAP_PASSWORD;
  if (!password) {
    throw new Error(
      'NEW_OWNER_PASSWORD or OWNER_BOOTSTRAP_PASSWORD is required. Set in operator shell only; never commit.',
    );
  }
  return password;
}

async function main() {
  assertProductionMutationConfirmed('production owner password rotation');
  const apiUrl = assertProductionSupabaseUrl(resolveHostedSupabaseUrl());
  if (!apiUrl.includes(PRODUCTION_PROJECT_REF)) {
    throw new Error(`Refusing password rotation for unexpected project ref (expected ${PRODUCTION_PROJECT_REF}).`);
  }
  const secretKey = getSupabaseAdminKeyFromEnv();
  const email = process.env.OWNER_BOOTSTRAP_EMAIL ?? OWNER_AUTH_EMAIL_DEFAULT;
  const newPassword = requiredNewPassword();
  const normalizedEmail = normalizeBootstrapEmail(email);

  const adminClient = createSupabaseAdminClient(apiUrl, secretKey);
  const matches = await listAuthUsersByEmail(adminClient, normalizedEmail);

  if (matches.length === 0) {
    throw new Error(`No Auth user found for ${normalizedEmail}. Run bootstrap first.`);
  }
  if (matches.length > 1) {
    throw new Error(`Multiple Auth users match ${normalizedEmail}. Resolve duplicates first.`);
  }

  const userId = matches[0].id;
  const { data, error } = await adminClient.auth.admin.updateUserById(userId, {
    password: newPassword,
    email_confirm: true,
  });

  if (error) {
    throw error;
  }

  if (!data?.user?.id) {
    throw new Error('Password update returned no user.');
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        email: normalizedEmail,
        auth_user_id: data.user.id,
        message: 'Production Owner password updated. Remove secrets from shell.',
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  reportBootstrapError(error, {
    operation: error?.operation ?? 'reset-production-owner-password',
    hostname: (() => {
      try {
        return new URL(resolveHostedSupabaseUrl()).hostname;
      } catch {
        return null;
      }
    })(),
    path: error?.path ?? null,
  });
  process.exit(1);
});
