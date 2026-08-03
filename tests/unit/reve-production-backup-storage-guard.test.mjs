import { describe, expect, it } from 'vitest';
import {
  assertBackupDestinationProtected,
  assertNotCloudSynchronizedPath,
} from '../../scripts/lib/reve-production-backup-storage-guard.mjs';

describe('reve-production-backup-storage-guard', () => {
  it('rejects cloud-synchronized destination paths', () => {
    expect(() =>
      assertNotCloudSynchronizedPath('C:\\Users\\operator\\OneDrive\\reve-backups'),
    ).toThrow(/cloud-synchronized folder/);
    expect(() =>
      assertNotCloudSynchronizedPath('C:\\Users\\operator\\Dropbox\\reve-backups'),
    ).toThrow(/cloud-synchronized folder/);
  });

  it('requires encrypted artifacts by default', () => {
    const result = assertBackupDestinationProtected('C:\\Dev\\reve-backup-dest', {
      requireEncryption: true,
    });
    expect(result.protectionModel).toBe('encrypted_artifacts_required');
  });

  it('fails closed when encryption disabled but BitLocker is not verified on Windows', () => {
    if (process.platform !== 'win32') {
      return;
    }

    expect(() =>
      assertBackupDestinationProtected('C:\\Dev\\reve-backup-dest', { requireEncryption: false }),
    ).toThrow(/BitLocker protection is not verified|ACL is broader/);
  });
});
