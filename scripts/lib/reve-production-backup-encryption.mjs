/**
 * Encrypt/decrypt backup SQL artifacts at rest (REVEBKUP1 / AES-256-GCM + scrypt).
 * Passphrase must never appear in logs, manifest, filenames, or Git.
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const REVEBKUP1_MAGIC = Buffer.from('REVEBKUP1');
export const REVEBKUP1_VERSION = 0x01;
export const REVEBKUP1_SALT_LENGTH = 16;
export const REVEBKUP1_IV_LENGTH = 12;
export const REVEBKUP1_TAG_LENGTH = 16;
export const REVEBKUP1_KEY_LENGTH = 32;
export const REVEBKUP1_SCRYPT_N = 16384;
export const REVEBKUP1_SCRYPT_R = 8;
export const REVEBKUP1_SCRYPT_P = 1;
export const REVEBKUP1_HEADER_LENGTH =
  REVEBKUP1_MAGIC.length + 1 + REVEBKUP1_SALT_LENGTH + REVEBKUP1_IV_LENGTH + 4 + 4 + 4 + REVEBKUP1_TAG_LENGTH;

export const REVEBKUP1_HEADER_CONTRACT = Object.freeze({
  magic: 'REVEBKUP1',
  magicBytes: REVEBKUP1_MAGIC.length,
  versionByte: REVEBKUP1_VERSION,
  saltBytes: REVEBKUP1_SALT_LENGTH,
  ivBytes: REVEBKUP1_IV_LENGTH,
  tagBytes: REVEBKUP1_TAG_LENGTH,
  scrypt: {
    N: REVEBKUP1_SCRYPT_N,
    r: REVEBKUP1_SCRYPT_R,
    p: REVEBKUP1_SCRYPT_P,
  },
  cipher: 'aes-256-gcm',
  totalHeaderBytes: REVEBKUP1_HEADER_LENGTH,
});

function writeUInt32BE(value) {
  const buf = Buffer.alloc(4);
  buf.writeUInt32BE(value, 0);
  return buf;
}

function readUInt32BE(buffer, offset) {
  return buffer.readUInt32BE(offset);
}

function deriveKey(passphrase, salt, scryptParams) {
  return crypto.scryptSync(passphrase, salt, REVEBKUP1_KEY_LENGTH, scryptParams);
}

function buildAuthenticatedHeaderAad(version, scryptN, scryptR, scryptP) {
  return Buffer.concat([
    REVEBKUP1_MAGIC,
    Buffer.from([version]),
    writeUInt32BE(scryptN),
    writeUInt32BE(scryptR),
    writeUInt32BE(scryptP),
  ]);
}

export function parseReveBkup1Header(payload) {
  if (!Buffer.isBuffer(payload)) {
    throw new Error('Encrypted backup artifact must be a buffer.');
  }
  if (payload.length < REVEBKUP1_HEADER_LENGTH) {
    throw new Error('Encrypted backup artifact is truncated or invalid.');
  }
  if (!payload.subarray(0, REVEBKUP1_MAGIC.length).equals(REVEBKUP1_MAGIC)) {
    throw new Error('Encrypted backup artifact has invalid header magic.');
  }

  let offset = REVEBKUP1_MAGIC.length;
  const version = payload[offset];
  offset += 1;
  if (version !== REVEBKUP1_VERSION) {
    throw new Error(`Unsupported REVEBKUP1 version: ${version}.`);
  }

  const salt = payload.subarray(offset, offset + REVEBKUP1_SALT_LENGTH);
  offset += REVEBKUP1_SALT_LENGTH;
  const iv = payload.subarray(offset, offset + REVEBKUP1_IV_LENGTH);
  offset += REVEBKUP1_IV_LENGTH;
  const scryptN = readUInt32BE(payload, offset);
  offset += 4;
  const scryptR = readUInt32BE(payload, offset);
  offset += 4;
  const scryptP = readUInt32BE(payload, offset);
  offset += 4;

  if (scryptN !== REVEBKUP1_SCRYPT_N || scryptR !== REVEBKUP1_SCRYPT_R || scryptP !== REVEBKUP1_SCRYPT_P) {
    throw new Error('Encrypted backup artifact has unsupported scrypt parameters.');
  }

  const tag = payload.subarray(offset, offset + REVEBKUP1_TAG_LENGTH);
  offset += REVEBKUP1_TAG_LENGTH;
  const ciphertext = payload.subarray(offset);
  if (ciphertext.length === 0) {
    throw new Error('Encrypted backup artifact has empty ciphertext.');
  }

  return {
    version,
    salt,
    iv,
    scryptN,
    scryptR,
    scryptP,
    tag,
    ciphertext,
    aad: buildAuthenticatedHeaderAad(version, scryptN, scryptR, scryptP),
  };
}

export function assertBackupEncryptionPassphraseConfigured() {
  const passphrase = process.env.REVE_BACKUP_ENCRYPTION_PASSPHRASE?.trim();
  if (!passphrase) {
    throw new Error(
      'Backup encryption passphrase is required (PowerShell secure prompt). Plaintext backup artifacts are not permitted.',
    );
  }
  if (passphrase.length < 12) {
    throw new Error('Backup encryption passphrase must be at least 12 characters.');
  }
  return passphrase;
}

export function encryptFileToDestination(sourcePath, destinationPath, passphrase) {
  const salt = crypto.randomBytes(REVEBKUP1_SALT_LENGTH);
  const iv = crypto.randomBytes(REVEBKUP1_IV_LENGTH);
  const scryptParams = { N: REVEBKUP1_SCRYPT_N, r: REVEBKUP1_SCRYPT_R, p: REVEBKUP1_SCRYPT_P };
  const key = deriveKey(passphrase, salt, scryptParams);
  const aad = buildAuthenticatedHeaderAad(REVEBKUP1_VERSION, scryptParams.N, scryptParams.r, scryptParams.p);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(aad);

  const plaintext = fs.readFileSync(sourcePath);
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();

  const header = Buffer.concat([
    REVEBKUP1_MAGIC,
    Buffer.from([REVEBKUP1_VERSION]),
    salt,
    iv,
    writeUInt32BE(scryptParams.N),
    writeUInt32BE(scryptParams.r),
    writeUInt32BE(scryptParams.p),
    tag,
  ]);

  fs.mkdirSync(path.dirname(destinationPath), { recursive: true });
  fs.writeFileSync(destinationPath, Buffer.concat([header, encrypted]));

  key.fill(0);
  return {
    sizeBytes: fs.statSync(destinationPath).size,
    sha256: crypto.createHash('sha256').update(fs.readFileSync(destinationPath)).digest('hex'),
    saltHex: salt.toString('hex'),
    ivHex: iv.toString('hex'),
  };
}

export function decryptFileToDestination(sourcePath, destinationPath, passphrase) {
  const payload = fs.readFileSync(sourcePath);
  const parsed = parseReveBkup1Header(payload);
  const key = deriveKey(passphrase, parsed.salt, {
    N: parsed.scryptN,
    r: parsed.scryptR,
    p: parsed.scryptP,
  });

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, parsed.iv);
  decipher.setAAD(parsed.aad);
  decipher.setAuthTag(parsed.tag);

  let decrypted;
  try {
    decrypted = Buffer.concat([decipher.update(parsed.ciphertext), decipher.final()]);
  } catch (error) {
    key.fill(0);
    removeFileIfExists(destinationPath);
    throw error;
  }

  fs.mkdirSync(path.dirname(destinationPath), { recursive: true });
  const tempPath = `${destinationPath}.partial-${crypto.randomBytes(4).toString('hex')}`;
  try {
    fs.writeFileSync(tempPath, decrypted);
    fs.renameSync(tempPath, destinationPath);
  } catch (error) {
    removeFileIfExists(tempPath);
    removeFileIfExists(destinationPath);
    throw error;
  } finally {
    key.fill(0);
  }

  return {
    sizeBytes: decrypted.length,
    sha256: crypto.createHash('sha256').update(decrypted).digest('hex'),
  };
}

export function removeFileIfExists(filePath) {
  if (filePath && fs.existsSync(filePath)) {
    fs.rmSync(filePath, { force: true });
  }
}

export function removeDirectoryIfExists(dirPath) {
  if (dirPath && fs.existsSync(dirPath)) {
    fs.rmSync(dirPath, { recursive: true, force: true });
  }
}

export function buildEncryptedPayloadForTests(plaintext, passphrase, overrides = {}) {
  const salt = overrides.salt ?? crypto.randomBytes(REVEBKUP1_SALT_LENGTH);
  const iv = overrides.iv ?? crypto.randomBytes(REVEBKUP1_IV_LENGTH);
  const scryptParams = {
    N: overrides.scryptN ?? REVEBKUP1_SCRYPT_N,
    r: overrides.scryptR ?? REVEBKUP1_SCRYPT_R,
    p: overrides.scryptP ?? REVEBKUP1_SCRYPT_P,
  };
  const key = deriveKey(passphrase, salt, scryptParams);
  const aad = buildAuthenticatedHeaderAad(REVEBKUP1_VERSION, scryptParams.N, scryptParams.r, scryptParams.p);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(aad);
  const encrypted = Buffer.concat([cipher.update(Buffer.from(plaintext, 'utf8')), cipher.final()]);
  const tag = overrides.tag ?? cipher.getAuthTag();
  key.fill(0);
  return Buffer.concat([
    REVEBKUP1_MAGIC,
    Buffer.from([REVEBKUP1_VERSION]),
    salt,
    iv,
    writeUInt32BE(scryptParams.N),
    writeUInt32BE(scryptParams.r),
    writeUInt32BE(scryptParams.p),
    tag,
    encrypted,
  ]);
}
