import { describe, expect, it } from 'vitest';
import {
  BACKUP_CONTRACT_VERSION,
  EXPECTED_MIGRATION_COUNT,
  MINIMUM_PRODUCTION_MIGRATION_COUNT,
  RECOVERY_DOMAINS,
  REQUIRED_PUBLIC_TABLES,
  assertBackupContractVersion,
  resolveExpectedMigrationCheckpoint,
} from '../../scripts/lib/reve-production-backup-contract.mjs';
import { BACKUP_ARTIFACTS } from '../../scripts/lib/reve-production-backup-dump-contract.mjs';

describe('reve-production-backup-contract', () => {
  it('defines the hardened 2B-2C1 v2 contract', () => {
    expect(BACKUP_CONTRACT_VERSION).toBe('2b2c1-v2');
    expect(MINIMUM_PRODUCTION_MIGRATION_COUNT).toBe(31);
    expect(EXPECTED_MIGRATION_COUNT).toBe(MINIMUM_PRODUCTION_MIGRATION_COUNT);
    expect(BACKUP_ARTIFACTS).toHaveLength(8);
    expect(REQUIRED_PUBLIC_TABLES).toHaveLength(15);
    expect(RECOVERY_DOMAINS.storageObjects).toContain('not in PostgreSQL');
  });

  it('resolves checkpoint from applied count (local may be ahead; post-deploy may rise)', () => {
    const checkpoint31 = resolveExpectedMigrationCheckpoint(process.cwd(), 31);
    expect(checkpoint31).toContain('20260914180000');
    expect(checkpoint31).not.toContain('20260915120000');

    const checkpoint32 = resolveExpectedMigrationCheckpoint(process.cwd(), 32);
    expect(checkpoint32).toContain('20260915120000');
  });

  it('rejects legacy contract versions', () => {
    expect(() => assertBackupContractVersion('2b2c1-v1')).toThrow(/Unsupported backup contract version/);
  });
});
