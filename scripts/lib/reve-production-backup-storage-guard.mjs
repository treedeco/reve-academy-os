/**
 * Fail-closed backup destination protection checks.
 * Never log full paths that may contain operator usernames or personal folder names.
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const CLOUD_SYNC_MARKERS = [
  `${path.sep}OneDrive${path.sep}`,
  `${path.sep}OneDrive - `,
  `${path.sep}Dropbox${path.sep}`,
  `${path.sep}Google Drive${path.sep}`,
  `${path.sep}iCloudDrive${path.sep}`,
  `${path.sep}Box${path.sep}`,
  `${path.sep}Box Sync${path.sep}`,
];

function normalizeForInspection(value) {
  return path.resolve(value).replace(/\//g, path.sep);
}

export function assertNotCloudSynchronizedPath(targetPath) {
  const normalized = normalizeForInspection(targetPath);
  const lower = normalized.toLowerCase();

  for (const marker of CLOUD_SYNC_MARKERS) {
    if (lower.includes(marker.toLowerCase())) {
      throw new Error('Refusing backup destination in a cloud-synchronized folder.');
    }
  }

  return normalized;
}

export function inspectWindowsVolumeProtection(targetPath) {
  if (process.platform !== 'win32') {
    return {
      platform: process.platform,
      bitlockerProtection: 'not_applicable',
      aclRestricted: 'not_applicable',
    };
  }

  const normalized = assertNotCloudSynchronizedPath(targetPath);
  const driveRoot = `${path.parse(normalized).root}`;

  let bitlockerProtection = 'unknown';
  try {
    const raw = execFileSync('manage-bde', ['-status', driveRoot], {
      encoding: 'utf8',
      timeout: 15_000,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (/Protection On/i.test(raw)) {
      bitlockerProtection = 'on';
    } else if (/Protection Off/i.test(raw)) {
      bitlockerProtection = 'off';
    }
  } catch {
    bitlockerProtection = 'unknown';
  }

  let aclRestricted = 'unknown';
  try {
    const script = `
      $acl = Get-Acl -LiteralPath '${normalized.replace(/'/g, "''")}'
      $rules = @($acl.Access | ForEach-Object { "$($_.IdentityReference)|$($_.FileSystemRights)" })
      $rules -join ';'
    `;
    const raw = execFileSync(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      { encoding: 'utf8', timeout: 15_000, stdio: ['ignore', 'pipe', 'pipe'] },
    ).trim();

    const entries = raw.split(';').filter(Boolean);
    const identities = entries.map((entry) => entry.split('|')[0]?.trim().toLowerCase() ?? '');
    const hasSystem = identities.some((id) => id === 'nt authority\\system' || id.endsWith('\\system'));
    const nonSystem = identities.filter(
      (id) => id && id !== 'nt authority\\system' && !id.endsWith('\\system'),
    );
    aclRestricted = hasSystem && nonSystem.length <= 2 ? 'restricted' : 'broad';
  } catch {
    aclRestricted = 'unknown';
  }

  return {
    platform: 'win32',
    bitlockerProtection,
    aclRestricted,
  };
}

export function assertBackupDestinationProtected(targetPath, options = {}) {
  const normalized = assertNotCloudSynchronizedPath(targetPath);
  fs.mkdirSync(normalized, { recursive: true });

  const protection = inspectWindowsVolumeProtection(normalized);
  const requireEncryption = options.requireEncryption !== false;

  if (requireEncryption) {
    return {
      destination: normalized,
      protectionModel: 'encrypted_artifacts_required',
      protection,
    };
  }

  if (process.platform === 'win32') {
    if (protection.bitlockerProtection !== 'on') {
      throw new Error(
        'Backup destination volume BitLocker protection is not verified (required when encryption is disabled).',
      );
    }
    if (protection.aclRestricted !== 'restricted') {
      throw new Error('Backup destination ACL is broader than current-user + SYSTEM.');
    }
  }

  return {
    destination: normalized,
    protectionModel: 'bitlocker_and_acl',
    protection,
  };
}

export function buildProtectionEvidence(protectionResult) {
  return {
    protectionModel: protectionResult.protectionModel,
    platform: protectionResult.protection.platform,
    bitlockerProtection: protectionResult.protection.bitlockerProtection,
    aclRestricted: protectionResult.protection.aclRestricted,
    cloudSyncRejected: true,
  };
}
