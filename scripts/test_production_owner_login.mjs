/**
 * Quick production owner login check (Stage 1 auth only).
 */
import {
  assertProductionMutationConfirmed,
  resolveProductionAppUrlFromEnv,
  resolveProductionSupabaseUrlFromEnv,
} from './lib/reve-production-operator-guard.mjs';
import { logStage } from './lib/reve-production-operator-io.mjs';
import { redactUuid } from './lib/reve-production-evidence-redaction.mjs';
import { createProductionOwnerSession } from './lib/reve-production-owner-session.mjs';

async function main() {
  logStage('login_test_start');
  resolveProductionSupabaseUrlFromEnv();
  resolveProductionAppUrlFromEnv();
  assertProductionMutationConfirmed('production owner login test');

  const { userId } = await createProductionOwnerSession();
  logStage('login_test_complete');

  console.log(
    JSON.stringify(
      {
        ok: true,
        authUserId: redactUuid(userId),
      },
      null,
      2,
    ),
  );
  await new Promise((resolve) => setTimeout(resolve, 150));
}

main().catch(async (error) => {
  logStage('login_test_failed');
  console.log(
    JSON.stringify(
      {
        ok: false,
        message: error instanceof Error ? error.message : String(error),
      },
      null,
      2,
    ),
  );
  await new Promise((resolve) => setTimeout(resolve, 150));
  process.exit(1);
});
