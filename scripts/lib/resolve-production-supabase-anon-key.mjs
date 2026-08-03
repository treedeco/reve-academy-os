/**
 * Resolve production anon key via Supabase CLI with timeout and write to a temp file.
 * stdout is sanitized; the anon key is written only to REVE_ANON_KEY_OUTPUT_PATH.
 */
import fs from 'node:fs';
import {
  PRODUCTION_PROJECT_REF,
  assertProductionMutationConfirmed,
} from './reve-production-operator-guard.mjs';
import {
  DEFAULT_CHILD_PROCESS_TIMEOUT_MS,
  extractJsonPayload,
  logStage,
  runNpxWithTimeout,
} from './reve-production-operator-io.mjs';

async function main() {
  assertProductionMutationConfirmed('production anon key resolution');

  const outputPath = process.env.REVE_ANON_KEY_OUTPUT_PATH ?? '';
  const projectRef = (process.env.REVE_SUPABASE_PROJECT_REF ?? PRODUCTION_PROJECT_REF).trim();

  if (!outputPath) {
    throw new Error('REVE_ANON_KEY_OUTPUT_PATH is required.');
  }
  if (projectRef !== PRODUCTION_PROJECT_REF) {
    throw new Error(`Refusing anon key resolution for unexpected project ref: ${projectRef}`);
  }

  const { stdout } = await runNpxWithTimeout(
    ['supabase', 'projects', 'api-keys', '--project-ref', projectRef, '-o', 'json'],
    DEFAULT_CHILD_PROCESS_TIMEOUT_MS,
    { stage: 'resolve_anon_key' },
  );

  logStage('resolve_anon_key_parse');
  const payload = extractJsonPayload(stdout);
  const rows = Array.isArray(payload) ? payload : payload?.keys ?? [];
  const anonKey = rows.find((row) => row?.id === 'anon')?.api_key ?? null;
  if (!anonKey) {
    throw new Error('Failed to resolve production anon key.');
  }

  fs.writeFileSync(
    outputPath,
    `${JSON.stringify({ projectRef, anonKey })}\n`,
    'utf8',
  );

  logStage('resolve_anon_key_complete');
  console.log(JSON.stringify({ ok: true, projectRef }, null, 2));
}

main().catch((error) => {
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
  process.exit(1);
});
