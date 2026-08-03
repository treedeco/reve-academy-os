import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import {
  assertBackupLabel,
  buildBackupSetPaths,
  buildManifestSkeleton,
  computeFileSha256,
  generateBackupRunId,
  readManifest,
  writeManifest,
} from '../../scripts/lib/reve-production-backup-io.mjs';
import { buildManifestArtifactEntry } from '../../scripts/lib/reve-production-backup-io.mjs';
import { BACKUP_ARTIFACTS } from '../../scripts/lib/reve-production-backup-dump-contract.mjs';

describe('reve-production-backup-io', () => {
  const tempDirs = [];

  afterEach(() => {
    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  function makeRepoRoot() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'reve-backup-io-'));
    tempDirs.push(dir);
    fs.mkdirSync(path.join(dir, 'backups'), { recursive: true });
    return dir;
  }

  it('builds backup set directory paths under backups/', () => {
    const repoRoot = makeRepoRoot();
    const paths = buildBackupSetPaths('phase-2b2c1-test', repoRoot);
    expect(paths.setDir).toContain(`${path.sep}backups${path.sep}backup-phase-2b2c1-test`);
    expect(paths.manifestPath).toContain('manifest.json');
  });

  it('writes manifest without PII or passphrase fields', async () => {
    const repoRoot = makeRepoRoot();
    const paths = buildBackupSetPaths('phase-2b2c1-test', repoRoot);
    fs.mkdirSync(paths.setDir, { recursive: true });
    const artifacts = BACKUP_ARTIFACTS.slice(0, 1).map((definition) =>
      buildManifestArtifactEntry(definition, {
        sha256: 'abc123'.padEnd(64, '0'),
        sizeBytes: 42,
        plaintextSha256: 'def456'.padEnd(64, '0'),
        plaintextSizeBytes: 24,
      }),
    );
    const manifest = buildManifestSkeleton({
      label: 'phase-2b2c1-test',
      runId: generateBackupRunId(),
      migrationCheckpoint: '20260728120000_phase_2b2b5_owner_permanent_deletion_and_schedule_removal',
      artifacts,
      protection: { protectionModel: 'encrypted_artifacts_required' },
    });
    writeManifest(paths.manifestPath, manifest);
    const loaded = readManifest(paths.manifestPath);
    expect(loaded.contractVersion).toBe('2b2c1-v2');
    expect(JSON.stringify(loaded)).not.toMatch(/student|teacher|phone|@[^"]+\.[^"]+/i);
  });

  it('computes deterministic sha256 checksums', async () => {
    const repoRoot = makeRepoRoot();
    const filePath = path.join(repoRoot, 'backups', 'sample.enc');
    fs.writeFileSync(filePath, 'encrypted-bytes', 'utf8');
    const hash = await computeFileSha256(filePath);
    expect(hash).toMatch(/^[a-f0-9]{64}$/);
  });

  it('rejects unsafe backup labels', () => {
    expect(() => assertBackupLabel('../secret')).toThrow(/Backup label must be/);
  });
});
