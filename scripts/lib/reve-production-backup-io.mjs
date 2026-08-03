/**
 * Backup artifact paths, manifest IO, and checksum helpers.
 * Never embed secrets, tokens, or personal data in filenames or logs.
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {
  BACKUP_CONTRACT_VERSION,
  EXPECTED_MIGRATION_COUNT,
  PRODUCTION_PROJECT_REF,
} from './reve-production-backup-contract.mjs';
import { BACKUP_ARTIFACTS } from './reve-production-backup-dump-contract.mjs';

const BACKUP_DIR_NAME = 'backups';
const LABEL_PATTERN = /^[a-z0-9][a-z0-9-]{0,63}$/i;

export function resolveBackupRoot(repoRoot = process.cwd()) {
  return path.join(repoRoot, BACKUP_DIR_NAME);
}

export function resolveBackupDestinationRoot(repoRoot = process.cwd()) {
  const fromEnv = (process.env.REVE_BACKUP_DESTINATION ?? '').trim();
  if (fromEnv) {
    return path.resolve(fromEnv);
  }
  return resolveBackupRoot(repoRoot);
}

export function assertBackupLabel(label) {
  const normalized = String(label ?? '').trim();
  if (!LABEL_PATTERN.test(normalized)) {
    throw new Error(
      'Backup label must be 1-64 alphanumeric/hyphen characters and must not contain secrets.',
    );
  }
  return normalized;
}

export function buildBackupSetPaths(label, repoRoot = process.cwd()) {
  const safeLabel = assertBackupLabel(label);
  const setDirName = `backup-${safeLabel}`;
  const destinationRoot = resolveBackupDestinationRoot(repoRoot);
  const setDir = path.join(destinationRoot, setDirName);
  const manifestPath = path.join(setDir, 'manifest.json');

  return {
    destinationRoot,
    setDir,
    setDirName,
    label: safeLabel,
    manifestPath,
    manifestFileName: 'manifest.json',
  };
}

export function buildArtifactPaths(setDir, artifactDefinition) {
  const plaintextPath = path.join(setDir, '.tmp-plain', artifactDefinition.fileName);
  const encryptedPath = path.join(setDir, artifactDefinition.encryptedFileName);
  return { plaintextPath, encryptedPath, relativePath: artifactDefinition.encryptedFileName };
}

export function assertBackupSetPathSafe(setDir, destinationRoot) {
  const resolvedSet = path.resolve(setDir);
  const resolvedRoot = path.resolve(destinationRoot);
  const relative = path.relative(resolvedRoot, resolvedSet);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Backup set directory must live under the configured backup destination root.');
  }
}

export function computeFileSha256(filePath) {
  const hash = crypto.createHash('sha256');
  const stream = fs.createReadStream(filePath);
  return new Promise((resolve, reject) => {
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('error', reject);
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

export function buildManifestSkeleton({
  label,
  runId,
  migrationCheckpoint,
  migrationCount = EXPECTED_MIGRATION_COUNT,
  rowCounts = {},
  artifacts = [],
  protection = {},
  projectRef = PRODUCTION_PROJECT_REF,
  createdAt = new Date().toISOString(),
}) {
  return {
    contractVersion: BACKUP_CONTRACT_VERSION,
    kind: 'production_database_backup_set',
    label,
    runId,
    createdAt,
    projectRef,
    migrationCount,
    migrationCheckpoint,
    mechanism: 'supabase_cli_pg_dump_multi_artifact',
    encryption: {
      required: true,
      algorithm: 'REVEBKUP1/aes-256-gcm-scrypt',
      passphraseStoredInManifest: false,
    },
    protection,
    artifacts,
    rowCounts,
    validation: {
      restoreValidationRequired: true,
      runtimeVerified: false,
      productionBackupExecuted: false,
      directProductionRestoreApproved: false,
    },
  };
}

export function buildManifestArtifactEntry(artifactDefinition, encryptedMeta) {
  return {
    id: artifactDefinition.id,
    relativePath: artifactDefinition.encryptedFileName,
    artifactType: artifactDefinition.artifactType,
    classification: artifactDefinition.classification,
    includedSchemas: artifactDefinition.includedSchemas,
    excludedSchemas: artifactDefinition.excludedSchemas,
    dumpMode: artifactDefinition.dumpMode,
    encrypted: true,
    sha256: encryptedMeta.sha256,
    sizeBytes: encryptedMeta.sizeBytes,
    plaintextSha256: encryptedMeta.plaintextSha256 ?? null,
    plaintextSizeBytes: encryptedMeta.plaintextSizeBytes ?? null,
  };
}

export function writeManifest(manifestPath, manifest) {
  fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
}

export function readManifest(manifestPath) {
  if (!fs.existsSync(manifestPath)) {
    throw new Error(`Backup manifest not found: ${path.basename(manifestPath)}`);
  }
  const payload = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (!payload || typeof payload !== 'object') {
    throw new Error('Backup manifest is not a JSON object.');
  }
  return payload;
}

export function resolveManifestPath(options = {}) {
  if (options.manifestPath) {
    return path.resolve(options.manifestPath);
  }

  const label = (options.label ?? process.env.REVE_BACKUP_LABEL ?? '').trim();
  if (!label) {
    throw new Error('Provide manifestPath or label.');
  }

  const { manifestPath } = buildBackupSetPaths(label, options.repoRoot ?? process.cwd());
  return manifestPath;
}

export function resolveBackupSetDirFromManifest(manifestPath) {
  return path.dirname(path.resolve(manifestPath));
}

export function assertManifestSafe(manifest) {
  const serialized = JSON.stringify(manifest);
  if (/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/.test(serialized)) {
    throw new Error('Manifest contains JWT-like material.');
  }
  if (/sb_[a-z_]+_[A-Za-z0-9_-]+/i.test(serialized)) {
    throw new Error('Manifest contains Supabase secret key material.');
  }
  if (/supabase\.co|postgres:\/\//i.test(serialized)) {
    throw new Error('Manifest contains database URL material.');
  }
  if (/"[^"]*@[^"]+\.[^"]+"/.test(serialized)) {
    throw new Error('Manifest contains email-like personal data.');
  }
  if (/\b0\d{1,2}-?\d{3,4}-?\d{4}\b/.test(serialized)) {
    throw new Error('Manifest contains phone-number-like personal data.');
  }
  if (/encrypted\s*:\s*false/i.test(serialized)) {
    throw new Error('Manifest references unencrypted backup artifacts.');
  }
  if (/"(?:passphrase|password|dbPassword|ownerPassword)"\s*:\s*["'][^"']{8,}["']/i.test(serialized)) {
    throw new Error('Manifest may contain credential material.');
  }
  return manifest;
}

export function generateBackupRunId(prefix = '2B2C1') {
  const stamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);
  const suffix = crypto.randomBytes(3).toString('hex').toUpperCase();
  return `${prefix}-${stamp}-${suffix}`;
}

export function generateBackupLabel(prefix = 'phase-2b2c1') {
  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const suffix = crypto.randomBytes(2).toString('hex');
  return `${prefix}-${stamp}-${suffix}`;
}

export function listContractArtifactDefinitions() {
  return BACKUP_ARTIFACTS;
}
