import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import {
  REVEBKUP1_HEADER_CONTRACT,
  REVEBKUP1_HEADER_LENGTH,
  REVEBKUP1_MAGIC,
  assertBackupEncryptionPassphraseConfigured,
  buildEncryptedPayloadForTests,
  decryptFileToDestination,
  encryptFileToDestination,
  parseReveBkup1Header,
  removeDirectoryIfExists,
  removeFileIfExists,
} from '../../scripts/lib/reve-production-backup-encryption.mjs';

describe('reve-production-backup-encryption', () => {
  const tempDirs = [];

  afterEach(() => {
    delete process.env.REVE_BACKUP_ENCRYPTION_PASSPHRASE;
    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  function makeTempDir() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'reve-backup-enc-'));
    tempDirs.push(dir);
    return dir;
  }

  it('documents REVEBKUP1 header contract fields and byte lengths', () => {
    expect(REVEBKUP1_HEADER_CONTRACT.magic).toBe('REVEBKUP1');
    expect(REVEBKUP1_HEADER_CONTRACT.magicBytes).toBe(9);
    expect(REVEBKUP1_HEADER_CONTRACT.versionByte).toBe(0x01);
    expect(REVEBKUP1_HEADER_CONTRACT.saltBytes).toBe(16);
    expect(REVEBKUP1_HEADER_CONTRACT.ivBytes).toBe(12);
    expect(REVEBKUP1_HEADER_CONTRACT.tagBytes).toBe(16);
    expect(REVEBKUP1_HEADER_CONTRACT.scrypt).toEqual({ N: 16384, r: 8, p: 1 });
    expect(REVEBKUP1_HEADER_CONTRACT.totalHeaderBytes).toBe(REVEBKUP1_HEADER_LENGTH);
    expect(REVEBKUP1_HEADER_LENGTH).toBe(9 + 1 + 16 + 12 + 4 + 4 + 4 + 16);
  });

  it('requires a configured encryption passphrase', () => {
    expect(() => assertBackupEncryptionPassphraseConfigured()).toThrow(/passphrase is required/);
    process.env.REVE_BACKUP_ENCRYPTION_PASSPHRASE = 'short';
    expect(() => assertBackupEncryptionPassphraseConfigured()).toThrow(/at least 12 characters/);
  });

  it('uses unique salt and IV for every encrypted artifact', () => {
    const dir = makeTempDir();
    const sourceA = path.join(dir, 'a.sql');
    const sourceB = path.join(dir, 'b.sql');
    fs.writeFileSync(sourceA, 'SELECT 1;\n', 'utf8');
    fs.writeFileSync(sourceB, 'SELECT 2;\n', 'utf8');
    const passphrase = 'operator-passphrase-123';

    const metaA = encryptFileToDestination(sourceA, path.join(dir, 'a.sql.enc'), passphrase);
    const metaB = encryptFileToDestination(sourceB, path.join(dir, 'b.sql.enc'), passphrase);

    expect(metaA.saltHex).not.toBe(metaB.saltHex);
    expect(metaA.ivHex).not.toBe(metaB.ivHex);
  });

  it('encrypts and decrypts artifacts without leaving plaintext behind', () => {
    const dir = makeTempDir();
    const source = path.join(dir, 'sample.sql');
    const encrypted = path.join(dir, 'sample.sql.enc');
    const decrypted = path.join(dir, '.tmp-restore', 'sample.sql');
    fs.writeFileSync(source, 'CREATE TABLE public.students (id uuid);\n', 'utf8');

    const passphrase = 'operator-passphrase-123';
    encryptFileToDestination(source, encrypted, passphrase);
    removeFileIfExists(source);

    const payload = fs.readFileSync(encrypted);
    expect(payload.subarray(0, REVEBKUP1_MAGIC.length).toString()).toBe('REVEBKUP1');
    expect(parseReveBkup1Header(payload).scryptN).toBe(16384);

    decryptFileToDestination(encrypted, decrypted, passphrase);
    expect(fs.readFileSync(decrypted, 'utf8')).toContain('CREATE TABLE public.students');
    removeDirectoryIfExists(path.dirname(decrypted));
  });

  it('fails closed on wrong passphrase without writing plaintext output', () => {
    const dir = makeTempDir();
    const encrypted = path.join(dir, 'sample.sql.enc');
    const out = path.join(dir, 'out.sql');
    fs.writeFileSync(path.join(dir, 'sample.sql'), 'SELECT 1;\n', 'utf8');
    encryptFileToDestination(path.join(dir, 'sample.sql'), encrypted, 'correct-passphrase-1');
    expect(() => decryptFileToDestination(encrypted, out, 'wrong-passphrase')).toThrow();
    expect(fs.existsSync(out)).toBe(false);
  });

  it('rejects header, tag, and truncation tampering', () => {
    const dir = makeTempDir();
    const encrypted = path.join(dir, 'sample.sql.enc');
    const out = path.join(dir, 'out.sql');
    const payload = buildEncryptedPayloadForTests('SELECT 1;', 'correct-passphrase-1');
    fs.writeFileSync(encrypted, payload);

    const headerTampered = Buffer.from(payload);
    headerTampered[0] = headerTampered[0] === 82 ? 83 : 82;
    fs.writeFileSync(path.join(dir, 'header-tampered.enc'), headerTampered);
    expect(() =>
      decryptFileToDestination(path.join(dir, 'header-tampered.enc'), out, 'correct-passphrase-1'),
    ).toThrow();
    expect(fs.existsSync(out)).toBe(false);

    const tagTampered = Buffer.from(payload);
    tagTampered[REVEBKUP1_HEADER_LENGTH - 1] ^= 0xff;
    fs.writeFileSync(path.join(dir, 'tag-tampered.enc'), tagTampered);
    expect(() =>
      decryptFileToDestination(path.join(dir, 'tag-tampered.enc'), out, 'correct-passphrase-1'),
    ).toThrow(/authenticate|invalid/i);
    expect(fs.existsSync(out)).toBe(false);

    const ciphertextTampered = Buffer.from(payload);
    ciphertextTampered[ciphertextTampered.length - 1] ^= 0xff;
    fs.writeFileSync(path.join(dir, 'ciphertext-tampered.enc'), ciphertextTampered);
    expect(() =>
      decryptFileToDestination(path.join(dir, 'ciphertext-tampered.enc'), out, 'correct-passphrase-1'),
    ).toThrow(/authenticate|invalid/i);
    expect(fs.existsSync(out)).toBe(false);

    fs.writeFileSync(path.join(dir, 'header-truncated.enc'), payload.subarray(0, REVEBKUP1_HEADER_LENGTH - 1));
    expect(() =>
      decryptFileToDestination(path.join(dir, 'header-truncated.enc'), out, 'correct-passphrase-1'),
    ).toThrow(/truncated|invalid/i);
    expect(fs.existsSync(out)).toBe(false);

    fs.writeFileSync(path.join(dir, 'truncated.enc'), payload.subarray(0, payload.length - 4));
    expect(() =>
      decryptFileToDestination(path.join(dir, 'truncated.enc'), out, 'correct-passphrase-1'),
    ).toThrow(/truncated|invalid|authenticate/i);
    expect(fs.existsSync(out)).toBe(false);
  });
});
