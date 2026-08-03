/**
 * Restore encrypted backup artifacts into an isolated local validation database.
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { assertBackupContractVersion } from './lib/reve-production-backup-contract.mjs';
import { resolveRestoreArtifacts } from './lib/reve-production-backup-dump-contract.mjs';
import {
  assertManagedSchemaRestoreBoundary,
} from './lib/reve-production-restore-plan.mjs';
import {
  assertBackupEncryptionPassphraseConfigured,
  decryptFileToDestination,
  removeDirectoryIfExists,
} from './lib/reve-production-backup-encryption.mjs';
import { resolveBackupSetDirFromManifest, readManifest } from './lib/reve-production-backup-io.mjs';
import { scanFileForSecrets } from './lib/reve-production-backup-secrets-scan.mjs';
import {
  assertLocalRestoreValidationTarget,
  assertNotDirectProductionRestore,
  assertRestoreValidationConfirmed,
  assertValidationDatabaseName,
  buildValidationDatabaseName,
} from './lib/reve-production-restore-isolation-guard.mjs';
import {
  RESTORE_VALIDATION_QUERIES,
  buildRestoreValidationReport,
  compareManifestRowCounts,
  validateRestoreReport,
} from './lib/reve-production-restore-validation.mjs';
import { REQUIRED_PUBLIC_TABLES } from './lib/reve-production-backup-contract.mjs';
import { logStage } from './lib/reve-production-operator-io.mjs';
import { verifyProductionBackup } from './verify_production_backup.mjs';

function psqlExec(container, sql, dbName = 'postgres') {
  return execFileSync(
    'docker',
    ['exec', '-i', container, 'psql', '-U', 'postgres', '-d', dbName, '-v', 'ON_ERROR_STOP=1', '-t', '-A', '-c', sql],
    { encoding: 'utf8', timeout: 120_000 },
  ).trim();
}

function psqlExecJson(container, sql, dbName = 'postgres') {
  const wrapped = `SELECT row_to_json(t) FROM (${sql.replace(/;\s*$/, '')}) t;`;
  const raw = psqlExec(container, wrapped, dbName);
  const line = raw.split('\n').find((entry) => entry.trim().startsWith('{'));
  return line ? JSON.parse(line) : null;
}

function psqlExecJsonArray(container, sql, dbName = 'postgres') {
  const wrapped = `SELECT coalesce(json_agg(row_to_json(t)), '[]'::json) FROM (${sql.replace(/;\s*$/, '')}) t;`;
  const raw = psqlExec(container, wrapped, dbName);
  const line = raw.split('\n').find((entry) => entry.trim().startsWith('['));
  return line ? JSON.parse(line) : [];
}

function psqlApplyFile(container, sqlFilePath, dbName) {
  execFileSync(
    'docker',
    ['exec', '-i', container, 'psql', '-U', 'postgres', '-d', dbName, '-v', 'ON_ERROR_STOP=1'],
    {
      input: fs.readFileSync(sqlFilePath),
      timeout: 300_000,
      stdio: ['pipe', 'pipe', 'pipe'],
    },
  );
}

function assertLocalContainerHost(container) {
  const dbHost = psqlExec(container, "SELECT COALESCE(inet_server_addr()::text, 'local');");
  assertLocalRestoreValidationTarget({ dbHost, apiUrl: process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL });
  return dbHost;
}

function createValidationDatabase(container, validationDbName) {
  logStage('restore_validation_create_db_start');
  psqlExec(container, `CREATE DATABASE ${validationDbName};`);
  logStage('restore_validation_create_db_complete');
}

function dropValidationDatabase(container, validationDbName) {
  logStage('restore_validation_drop_db_start');
  psqlExec(container, `
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '${validationDbName}'
      AND pid <> pg_backend_pid();
  `);
  psqlExec(container, `DROP DATABASE IF EXISTS ${validationDbName};`);
  logStage('restore_validation_drop_db_complete');
}

function collectRestoreValidationRawResults(container, validationDbName) {
  const requiredTablesSql = RESTORE_VALIDATION_QUERIES.requiredTablesPresent.replace(
    '$1::text[]',
    `ARRAY[${REQUIRED_PUBLIC_TABLES.map((table) => `'${table}'`).join(',')}]`,
  );
  const rlsSql = RESTORE_VALIDATION_QUERIES.rlsEnabled.replace(
    '$1::text[]',
    `ARRAY[${REQUIRED_PUBLIC_TABLES.map((table) => `'${table}'`).join(',')}]`,
  );

  return {
    publicTableCount: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.publicTableCount, validationDbName),
    requiredTablesPresent: psqlExecJsonArray(container, requiredTablesSql, validationDbName),
    migrationCount: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.migrationCount, validationDbName),
    latestMigrationVersion: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.latestMigrationVersion, validationDbName),
    rowCounts: psqlExecJsonArray(container, RESTORE_VALIDATION_QUERIES.rowCounts, validationDbName),
    fkIntegrityProbe: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.fkIntegrityProbe, validationDbName),
    activePassUniqueness: psqlExecJsonArray(container, RESTORE_VALIDATION_QUERIES.activePassUniqueness, validationDbName),
    reservedPassUniqueness: psqlExecJsonArray(container, RESTORE_VALIDATION_QUERIES.reservedPassUniqueness, validationDbName),
    passUsageConsistency: psqlExecJsonArray(container, RESTORE_VALIDATION_QUERIES.passUsageConsistency, validationDbName),
    paymentsPassLinkage: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.paymentsPassLinkage, validationDbName),
    scheduleSlotsActiveLessons: psqlExecJson(
      container,
      RESTORE_VALIDATION_QUERIES.scheduleSlotsActiveLessons,
      validationDbName,
    ),
    smsNotificationLinkage: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.smsNotificationLinkage, validationDbName),
    auditLogPresence: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.auditLogPresence, validationDbName),
    rlsEnabled: psqlExecJsonArray(container, rlsSql, validationDbName),
    rlsPolicyCount: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.rlsPolicyCount, validationDbName),
    ownerAuthPresence: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.ownerAuthPresence, validationDbName),
    ownerProfilePresence: psqlExecJson(container, RESTORE_VALIDATION_QUERIES.ownerProfilePresence, validationDbName),
  };
}

export async function decryptArtifactsForRestore(setDir, manifest, passphrase, tempDir) {
  const ordered = resolveRestoreArtifacts(manifest);
  const decrypted = [];

  fs.mkdirSync(tempDir, { recursive: true });
  for (const entry of ordered) {
    const encryptedPath = path.join(setDir, entry.relativePath);
    const plainName = entry.relativePath.replace(/\.enc$/, '');
    const plaintextPath = path.join(tempDir, plainName);
    decryptFileToDestination(encryptedPath, plaintextPath, passphrase);
    scanFileForSecrets(plaintextPath);
    decrypted.push({ ...entry, plaintextPath, plainName });
  }

  return decrypted;
}

export async function applyRestoreArtifacts(container, validationDbName, decryptedArtifacts, context = {}) {
  for (const artifact of decryptedArtifacts) {
    assertManagedSchemaRestoreBoundary({
      artifactId: artifact.id,
      validationDatabaseName: validationDbName,
      dbHost: context.dbHost ?? null,
      apiUrl: context.apiUrl ?? null,
    });
    logStage('restore_validation_apply_artifact_start', artifact.id);
    psqlApplyFile(container, artifact.plaintextPath, validationDbName);
    logStage('restore_validation_apply_artifact_complete', artifact.id);
  }
}

export async function runRestoreValidation(options = {}) {
  assertNotDirectProductionRestore();
  assertRestoreValidationConfirmed();

  const container = (options.container ?? process.env.SUPABASE_DB_CONTAINER ?? '').trim();
  if (!container) {
    throw new Error('SUPABASE_DB_CONTAINER is required for isolated restore validation.');
  }

  const passphrase = options.passphrase ?? assertBackupEncryptionPassphraseConfigured();
  const verifyResult = await verifyProductionBackup(options);
  const manifest = readManifest(verifyResult.manifestPath);
  assertBackupContractVersion(manifest.contractVersion);

  const setDir = verifyResult.setDir ?? resolveBackupSetDirFromManifest(verifyResult.manifestPath);
  const validationDbName = assertValidationDatabaseName(
    options.validationDbName ?? buildValidationDatabaseName(),
  );
  const tempDir = path.join(setDir, `.tmp-restore-${validationDbName}`);

  logStage('restore_validation_isolation_check_start');
  const dbHost = assertLocalContainerHost(container);
  logStage('restore_validation_isolation_check_complete', `host=${dbHost}`);

  let databaseCreated = false;
  try {
    createValidationDatabase(container, validationDbName);
    databaseCreated = true;

    const decryptedArtifacts = await decryptArtifactsForRestore(setDir, manifest, passphrase, tempDir);
    await applyRestoreArtifacts(container, validationDbName, decryptedArtifacts, {
      dbHost,
      apiUrl: process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? null,
    });

    const rawResults = collectRestoreValidationRawResults(container, validationDbName);
    const report = buildRestoreValidationReport(rawResults);
    validateRestoreReport(report, manifest);
    compareManifestRowCounts(manifest, report);

    return {
      ok: true,
      label: manifest.label,
      runId: manifest.runId,
      validationDatabase: validationDbName,
      artifactCount: decryptedArtifacts.length,
      isolationProof: {
        container,
        dbHost,
        directProductionRestoreApproved: false,
      },
      report,
    };
  } catch (error) {
    logStage('restore_validation_partial_failure', error.message?.slice(0, 120) ?? 'unknown');
    throw error;
  } finally {
    removeDirectoryIfExists(tempDir);
    if (databaseCreated) {
      dropValidationDatabase(container, validationDbName);
    }
  }
}

function parseArgs(argv) {
  const options = {};
  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--manifest') {
      options.manifestPath = argv[index + 1];
      index += 1;
    } else if (arg === '--label') {
      options.label = argv[index + 1];
      index += 1;
    } else if (arg === '--container') {
      options.container = argv[index + 1];
      index += 1;
    }
  }
  return options;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isMain) {
  runRestoreValidation(parseArgs(process.argv))
    .then((result) => {
      console.log(JSON.stringify(result, null, 2));
    })
    .catch((error) => {
      logStage('restore_validation_failed');
      console.error(JSON.stringify({ ok: false, error: error.message ?? String(error) }, null, 2));
      process.exitCode = 1;
    });
}
