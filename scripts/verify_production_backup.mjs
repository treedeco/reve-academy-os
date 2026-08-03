/**
 * Verify a production backup manifest and encrypted artifact integrity (offline-safe).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertBackupContractVersion } from './lib/reve-production-backup-contract.mjs';
import {
  assertManifestArtifactsComplete,
  resolveRestoreArtifacts,
} from './lib/reve-production-backup-dump-contract.mjs';
import {
  assertManifestSafe,
  computeFileSha256,
  readManifest,
  resolveBackupSetDirFromManifest,
  resolveManifestPath,
} from './lib/reve-production-backup-io.mjs';
import { scanFileForSecrets } from './lib/reve-production-backup-secrets-scan.mjs';
import { logStage } from './lib/reve-production-operator-io.mjs';

function loadManifestContext(options = {}) {
  const manifestPath = resolveManifestPath(options);
  const manifest = readManifest(manifestPath);
  const setDir = resolveBackupSetDirFromManifest(manifestPath);
  return { manifestPath, manifest, setDir };
}

export async function verifyProductionBackup(options = {}) {
  logStage('verify_backup_start');
  const { manifestPath, manifest, setDir } = loadManifestContext(options);

  assertBackupContractVersion(manifest.contractVersion);
  assertManifestSafe(manifest);
  assertManifestArtifactsComplete(manifest);
  const orderedArtifacts = resolveRestoreArtifacts(manifest);

  const verified = [];
  for (const entry of orderedArtifacts) {
    const artifactPath = path.join(setDir, entry.relativePath);
    if (!fs.existsSync(artifactPath)) {
      throw new Error(`Missing backup artifact: ${entry.relativePath}`);
    }

    const sizeBytes = fs.statSync(artifactPath).size;
    if (entry.sizeBytes != null && sizeBytes !== entry.sizeBytes) {
      throw new Error(`Artifact size mismatch: ${entry.id}`);
    }

    const sha256 = await computeFileSha256(artifactPath);
    if (entry.sha256 && sha256 !== entry.sha256) {
      throw new Error(`Artifact checksum mismatch: ${entry.id}`);
    }

    verified.push({
      id: entry.id,
      relativePath: entry.relativePath,
      sha256,
      sizeBytes,
    });
  }

  if (manifest.encryption?.required !== true) {
    throw new Error('Backup set is not marked encrypted-at-rest.');
  }

  logStage('verify_backup_complete');

  return {
    ok: true,
    label: manifest.label,
    runId: manifest.runId,
    migrationCount: manifest.migrationCount,
    migrationCheckpoint: manifest.migrationCheckpoint,
    artifactCount: verified.length,
    artifacts: verified,
    manifestPath,
    setDir,
  };
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
    }
  }
  return options;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isMain) {
  verifyProductionBackup(parseArgs(process.argv))
    .then((result) => {
      console.log(JSON.stringify(result, null, 2));
    })
    .catch((error) => {
      logStage('verify_backup_failed');
      console.error(JSON.stringify({ ok: false, error: error.message ?? String(error) }, null, 2));
      process.exitCode = 1;
    });
}
