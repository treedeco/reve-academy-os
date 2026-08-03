import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { runProductionBackup } from '../../scripts/backup_production_database.mjs';
import { BACKUP_ARTIFACTS } from '../../scripts/lib/reve-production-backup-dump-contract.mjs';
import { decryptFileToDestination } from '../../scripts/lib/reve-production-backup-encryption.mjs';
import { assertManifestArtifactsComplete } from '../../scripts/lib/reve-production-backup-dump-contract.mjs';

describe('backup-production', () => {
  const tempDirs = [];

  afterEach(() => {
    vi.restoreAllMocks();
    delete process.env.REVE_CONFIRM_PRODUCTION;
    delete process.env.REVE_PRODUCTION_PROJECT_REF_CONFIRM;
    delete process.env.REVE_BACKUP_ENCRYPTION_PASSPHRASE;
    delete process.env.PRODUCTION_SUPABASE_URL;
    delete process.env.PRODUCTION_SUPABASE_ANON_KEY;
    delete process.env.PRODUCTION_OWNER_PASSWORD;
    delete process.env.PRODUCTION_URL;

    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  function makeRepoRoot() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'reve-backup-run-'));
    tempDirs.push(dir);
    fs.mkdirSync(path.join(dir, 'supabase', 'migrations'), { recursive: true });
    for (let index = 0; index < 26; index += 1) {
      const version = String(20260626120000 + index);
      fs.writeFileSync(
        path.join(dir, 'supabase', 'migrations', `${version}_migration_${index}.sql`),
        'SELECT 1;',
      );
    }
    fs.mkdirSync(path.join(dir, 'backups'), { recursive: true });
    return dir;
  }

  it('requires explicit production confirmation and encryption passphrase', async () => {
    await expect(runProductionBackup()).rejects.toThrow(/requires explicit confirmation/);
    process.env.REVE_CONFIRM_PRODUCTION = '1';
    process.env.REVE_PRODUCTION_PROJECT_REF_CONFIRM = 'bfhptqhgxignyggyxxkx';
    process.env.PRODUCTION_SUPABASE_URL = 'https://bfhptqhgxignyggyxxkx.supabase.co';
    process.env.PRODUCTION_URL = 'https://reve-academy-os.vercel.app';
    await expect(runProductionBackup()).rejects.toThrow(/encryption passphrase is required/);
  });

  it('creates encrypted multi-artifact backup set and manifest without plaintext residue', async () => {
    const repoRoot = makeRepoRoot();
    process.env.REVE_CONFIRM_PRODUCTION = '1';
    process.env.REVE_PRODUCTION_PROJECT_REF_CONFIRM = 'bfhptqhgxignyggyxxkx';
    process.env.PRODUCTION_SUPABASE_URL = 'https://bfhptqhgxignyggyxxkx.supabase.co';
    process.env.PRODUCTION_URL = 'https://reve-academy-os.vercel.app';
    process.env.PRODUCTION_SUPABASE_ANON_KEY = 'anon-key';
    process.env.PRODUCTION_OWNER_PASSWORD = 'owner-password';
    const passphrase = 'operator-passphrase-123';

    const runNpx = vi.fn(async (args) => {
      if (args[1] === 'migration') {
        return { stdout: '{ "migrations": [' + '1,'.repeat(25) + '1] }', stderr: '' };
      }
      const fileIndex = args.indexOf('-f');
      const dumpPath = args[fileIndex + 1];
      fs.mkdirSync(path.dirname(dumpPath), { recursive: true });
      fs.writeFileSync(dumpPath, `-- artifact ${path.basename(dumpPath)}\n`, 'utf8');
      return { stdout: '', stderr: '' };
    });

    const createOwnerSession = vi.fn(async () => ({
      client: {
        from: vi.fn(() => ({
          select: vi.fn(() => {
            const chain = {
              like: vi.fn(async () => ({ count: 7, error: null })),
              not: vi.fn(async () => ({ count: 4, error: null })),
              eq: vi.fn(() => chain),
              then: (resolve) => Promise.resolve({ count: 1, error: null }).then(resolve),
            };
            return chain;
          }),
        })),
      },
      userId: 'owner-id',
    }));

    const result = await runProductionBackup({
      repoRoot,
      label: 'phase-2b2c1-test',
      runId: '2B2C1-TEST',
      passphrase,
      runNpx,
      createOwnerSession,
      migrationCheckpoint: '20260728120000_phase_2b2b5_owner_permanent_deletion_and_schedule_removal',
    });

    expect(result.ok).toBe(true);
    expect(runNpx).toHaveBeenCalledTimes(BACKUP_ARTIFACTS.length + 1);
    expect(fs.existsSync(path.join(result.setDir, '.tmp-plain'))).toBe(false);

    const manifest = JSON.parse(fs.readFileSync(result.manifestPath, 'utf8'));
    assertManifestArtifactsComplete(manifest);
    expect(manifest.contractVersion).toBe('2b2c1-v2');
    expect(manifest.encryption.required).toBe(true);

    for (const artifact of manifest.artifacts) {
      const encryptedPath = path.join(result.setDir, artifact.relativePath);
      expect(fs.existsSync(encryptedPath)).toBe(true);
      expect(encryptedPath.endsWith('.enc')).toBe(true);
    }

    const decrypted = path.join(result.setDir, '.tmp-verify', 'schema-public.sql');
    decryptFileToDestination(
      path.join(result.setDir, 'schema-public.sql.enc'),
      decrypted,
      passphrase,
    );
    expect(fs.readFileSync(decrypted, 'utf8')).toContain('schema-public.sql');
    fs.rmSync(path.dirname(decrypted), { recursive: true, force: true });
  });
});
