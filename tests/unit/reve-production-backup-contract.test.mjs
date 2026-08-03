import { describe, expect, it } from 'vitest';
import {
  BACKUP_CONTRACT_VERSION,
  EXPECTED_MIGRATION_COUNT,
  RECOVERY_DOMAINS,
  REQUIRED_PUBLIC_TABLES,
  assertBackupContractVersion,
  resolveExpectedMigrationCheckpoint,
} from '../../scripts/lib/reve-production-backup-contract.mjs';
import { BACKUP_ARTIFACTS } from '../../scripts/lib/reve-production-backup-dump-contract.mjs';

describe('reve-production-backup-contract', () => {
  it('defines the hardened 2B-2C1 v2 contract', () => {
    expect(BACKUP_CONTRACT_VERSION).toBe('2b2c1-v2');
    expect(EXPECTED_MIGRATION_COUNT).toBe(26);
    expect(BACKUP_ARTIFACTS).toHaveLength(8);
    expect(REQUIRED_PUBLIC_TABLES).toHaveLength(15);
    expect(RECOVERY_DOMAINS.storageObjects).toContain('not in PostgreSQL');
  });

  it('resolves the latest migration checkpoint at 26/26', () => {
    const checkpoint = resolveExpectedMigrationCheckpoint(process.cwd());
    expect(checkpoint).toContain('20260728120000');
  });

  it('rejects legacy contract versions', () => {
    expect(() => assertBackupContractVersion('2b2c1-v1')).toThrow(/Unsupported backup contract version/);
  });
});
