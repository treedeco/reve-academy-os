import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { verifyProductionBackup } from '../../scripts/verify_production_backup.mjs';
import {
  buildManifestArtifactEntry,
  buildManifestSkeleton,
  computeFileSha256,
  writeManifest,
} from '../../scripts/lib/reve-production-backup-io.mjs';
import { BACKUP_ARTIFACTS } from '../../scripts/lib/reve-production-backup-dump-contract.mjs';
import { encryptFileToDestination } from '../../scripts/lib/reve-production-backup-encryption.mjs';

describe('verify-production-backup', () => {
  const tempDirs = [];

  afterEach(() => {
    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  async function createFixture({ tamperChecksum = false, omitArtifact = false } = {}) {
    const repoRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reve-verify-backup-'));
    tempDirs.push(repoRoot);
    const setDir = path.join(repoRoot, 'backups', 'backup-phase-2b2c1-test');
    fs.mkdirSync(setDir, { recursive: true });

    const passphrase = 'operator-passphrase-123';
    const manifestArtifacts = [];

    for (const definition of BACKUP_ARTIFACTS) {
      if (omitArtifact && definition.id === 'data-auth') {
        continue;
      }
      const plain = path.join(setDir, `.build-${definition.fileName}`);
      fs.writeFileSync(plain, `-- ${definition.id}\n`, 'utf8');
      const encryptedPath = path.join(setDir, definition.encryptedFileName);
      const encryptedMeta = encryptFileToDestination(plain, encryptedPath, passphrase);
      fs.rmSync(plain, { force: true });
      manifestArtifacts.push(buildManifestArtifactEntry(definition, encryptedMeta));
    }

    const manifest = buildManifestSkeleton({
      label: 'phase-2b2c1-test',
      runId: '2B2C1-TEST',
      migrationCheckpoint: '20260728120000_phase_2b2b5_owner_permanent_deletion_and_schedule_removal',
      artifacts: manifestArtifacts,
      protection: {
        protectionModel: 'encrypted_artifacts_required',
        platform: 'test',
        bitlockerProtection: 'not_applicable',
        aclRestricted: 'not_applicable',
        cloudSyncRejected: true,
      },
    });

    if (tamperChecksum && manifest.artifacts[0]) {
      manifest.artifacts[0].sha256 = '0'.repeat(64);
    }

    const manifestPath = path.join(setDir, 'manifest.json');
    writeManifest(manifestPath, manifest);

    return { repoRoot, setDir, manifestPath };
  }

  it('verifies every required encrypted artifact checksum and size', async () => {
    const fixture = await createFixture();
    const result = await verifyProductionBackup({
      repoRoot: fixture.repoRoot,
      label: 'phase-2b2c1-test',
    });
    expect(result.ok).toBe(true);
    expect(result.artifactCount).toBe(8);
  });

  it('fails closed on checksum mismatch', async () => {
    const fixture = await createFixture({ tamperChecksum: true });
    await expect(
      verifyProductionBackup({ repoRoot: fixture.repoRoot, label: 'phase-2b2c1-test' }),
    ).rejects.toThrow(/checksum mismatch/);
  });

  it('fails closed when a required artifact is missing', async () => {
    const fixture = await createFixture({ omitArtifact: true });
    await expect(
      verifyProductionBackup({ repoRoot: fixture.repoRoot, label: 'phase-2b2c1-test' }),
    ).rejects.toThrow(/missing required artifact: data-auth/);
  });
});
