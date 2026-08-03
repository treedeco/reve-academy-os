/**
 * Phase 2B-2C1 guarded production database backup runner (multi-artifact + encrypted).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  BACKUP_EXCLUDES,
  BACKUP_INCLUDES,
  assertProductionProjectRefConfirmed,
  resolveExpectedMigrationCheckpoint,
} from './lib/reve-production-backup-contract.mjs';
import {
  assertExpectedMigrationCount,
  collectProductionBaselineExtras,
  collectProductionRowCounts,
  countLinkedMigrations,
} from './lib/reve-production-backup-baseline.mjs';
import {
  BACKUP_ARTIFACTS,
  RESTORE_ARTIFACT_ORDER,
  buildSupabaseDumpCommandArgs,
} from './lib/reve-production-backup-dump-contract.mjs';
import {
  assertBackupEncryptionPassphraseConfigured,
  encryptFileToDestination,
  removeDirectoryIfExists,
  removeFileIfExists,
} from './lib/reve-production-backup-encryption.mjs';
import {
  assertBackupSetPathSafe,
  buildArtifactPaths,
  buildBackupSetPaths,
  buildManifestArtifactEntry,
  buildManifestSkeleton,
  computeFileSha256,
  generateBackupLabel,
  generateBackupRunId,
  writeManifest,
  assertManifestSafe,
} from './lib/reve-production-backup-io.mjs';
import { scanFileForSecrets } from './lib/reve-production-backup-secrets-scan.mjs';
import {
  assertBackupDestinationProtected,
  buildProtectionEvidence,
} from './lib/reve-production-backup-storage-guard.mjs';
import {
  PRODUCTION_PROJECT_REF,
  assertProductionMutationConfirmed,
  resolveProductionSupabaseUrlFromEnv,
} from './lib/reve-production-operator-guard.mjs';
import {
  DEFAULT_CHILD_PROCESS_TIMEOUT_MS,
  logStage,
  runNpxWithTimeout,
} from './lib/reve-production-operator-io.mjs';
import { createProductionOwnerSession } from './lib/reve-production-owner-session.mjs';

const DEFAULT_DUMP_TIMEOUT_MS = 300_000;

function resolveBackupLabelFromEnv() {
  const fromEnv = (process.env.REVE_BACKUP_LABEL ?? '').trim();
  return fromEnv || generateBackupLabel();
}

function resolveConfirmedProjectRef() {
  return assertProductionProjectRefConfirmed(
    process.env.REVE_PRODUCTION_PROJECT_REF_CONFIRM ?? process.env.REVE_SUPABASE_PROJECT_REF,
    PRODUCTION_PROJECT_REF,
  );
}

async function verifyLinkedMigrationCheckpoint(runNpx = runNpxWithTimeout) {
  logStage('backup_migration_list_start');
  const { stdout } = await runNpx(['supabase', 'migration', 'list', '--linked'], DEFAULT_CHILD_PROCESS_TIMEOUT_MS, {
    stage: 'backup_migration_list',
  });
  const migrationCount = assertExpectedMigrationCount(countLinkedMigrations(stdout));
  logStage('backup_migration_list_complete', `count=${migrationCount}`);
  return migrationCount;
}

async function runArtifactDump(definition, plaintextPath, runNpx = runNpxWithTimeout) {
  fs.mkdirSync(path.dirname(plaintextPath), { recursive: true });
  const command = buildSupabaseDumpCommandArgs(definition, plaintextPath);
  logStage('backup_artifact_dump_start', definition.id);
  await runNpx(command.args, DEFAULT_DUMP_TIMEOUT_MS, {
    stage: `backup_artifact_${definition.id}`,
    detail: definition.id,
  });

  if (!fs.existsSync(plaintextPath)) {
    throw new Error(`Backup artifact dump was not created: ${definition.id}`);
  }
  const sizeBytes = fs.statSync(plaintextPath).size;
  if (sizeBytes <= 0) {
    throw new Error(`Backup artifact dump is empty: ${definition.id}`);
  }

  scanFileForSecrets(plaintextPath);
  const plaintextSha256 = await computeFileSha256(plaintextPath);
  logStage('backup_artifact_dump_complete', `${definition.id} sizeBytes=${sizeBytes}`);
  return { sizeBytes, sha256: plaintextSha256 };
}

export async function runProductionBackup(options = {}) {
  const repoRoot = options.repoRoot ?? process.cwd();
  const runNpx = options.runNpx ?? runNpxWithTimeout;
  const createOwnerSession = options.createOwnerSession ?? createProductionOwnerSession;
  assertProductionMutationConfirmed('production backup');
  resolveConfirmedProjectRef();
  resolveProductionSupabaseUrlFromEnv();
  const passphrase = options.passphrase ?? assertBackupEncryptionPassphraseConfigured();

  const label = options.label ?? resolveBackupLabelFromEnv();
  const runId = options.runId ?? generateBackupRunId();
  const { setDir, manifestPath, destinationRoot } = buildBackupSetPaths(label, repoRoot);
  const protectionResult = assertBackupDestinationProtected(setDir, { requireEncryption: true });
  assertBackupSetPathSafe(setDir, destinationRoot);
  const migrationCheckpoint = options.migrationCheckpoint ?? resolveExpectedMigrationCheckpoint(repoRoot);

  const migrationCount = await verifyLinkedMigrationCheckpoint(runNpx);

  logStage('backup_owner_session_start');
  const { client } = await createOwnerSession();
  const rowCounts = await collectProductionRowCounts(client);
  const extras = await collectProductionBaselineExtras(client);
  logStage('backup_owner_session_complete');

  const plaintextTempDir = path.join(setDir, '.tmp-plain');
  const manifestArtifacts = [];

  try {
    for (const definition of options.artifacts ?? BACKUP_ARTIFACTS) {
      const { plaintextPath, encryptedPath } = buildArtifactPaths(setDir, definition);
      const plaintextMeta = await runArtifactDump(definition, plaintextPath, runNpx);
      const encryptedMeta = encryptFileToDestination(plaintextPath, encryptedPath, passphrase);
      encryptedMeta.plaintextSha256 = plaintextMeta.sha256;
      encryptedMeta.plaintextSizeBytes = plaintextMeta.sizeBytes;
      removeFileIfExists(plaintextPath);
      manifestArtifacts.push(buildManifestArtifactEntry(definition, encryptedMeta));
    }
  } finally {
    removeDirectoryIfExists(plaintextTempDir);
  }

  const manifest = assertManifestSafe(
    buildManifestSkeleton({
      label,
      runId,
      migrationCheckpoint,
      migrationCount,
      rowCounts,
      artifacts: manifestArtifacts,
      protection: buildProtectionEvidence(protectionResult),
    }),
  );

  manifest.includes = BACKUP_INCLUDES;
  manifest.excludes = BACKUP_EXCLUDES;
  manifest.baseline = extras;
  manifest.restoreOrder = [...RESTORE_ARTIFACT_ORDER];
  manifest.validation.productionBackupExecuted = options.markProductionExecuted === true;

  writeManifest(manifestPath, manifest);
  logStage('backup_manifest_written');

  return {
    ok: true,
    runId,
    label,
    setDir,
    manifestPath,
    migrationCount,
    migrationCheckpoint,
    artifactCount: manifestArtifacts.length,
    baseline: extras,
    rowCountTables: Object.keys(rowCounts).length,
    protection: manifest.protection,
  };
}

function printBackupSummary(result) {
  console.log(
    JSON.stringify(
      {
        ok: result.ok,
        runId: result.runId,
        label: result.label,
        migrationCount: result.migrationCount,
        migrationCheckpoint: result.migrationCheckpoint,
        artifactCount: result.artifactCount,
        rowCountTables: result.rowCountTables,
        baseline: result.baseline,
        protection: result.protection,
        manifestFile: path.basename(result.manifestPath),
        setDirName: path.basename(result.setDir),
      },
      null,
      2,
    ),
  );
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isMain) {
  runProductionBackup()
    .then((result) => {
      printBackupSummary(result);
      logStage('backup_complete');
    })
    .catch((error) => {
      logStage('backup_failed');
      console.error(JSON.stringify({ ok: false, error: error.message ?? String(error) }, null, 2));
      process.exitCode = 1;
    });
}
