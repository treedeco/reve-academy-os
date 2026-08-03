/**
 * Scan backup artifacts for credential-like material (fail-closed).
 */
import fs from 'node:fs';
import { DUMP_SECRET_SCAN_MAX_BYTES } from './reve-production-backup-contract.mjs';

const SECRET_PATTERNS = [
  { name: 'supabase_secret_key', pattern: /sb_[a-z_]+_[A-Za-z0-9_-]{20,}/gi },
  { name: 'jwt_token', pattern: /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g },
  { name: 'service_role_assignment', pattern: /service_role\s*=\s*'[^']{20,}'/gi },
  { name: 'password_literal', pattern: /OWNER_BOOTSTRAP_PASSWORD\s*=\s*['"][^'"]{4,}['"]/gi },
];

export function scanTextForSecrets(text, options = {}) {
  const sample = String(text ?? '');
  const violations = [];

  for (const { name, pattern } of SECRET_PATTERNS) {
    pattern.lastIndex = 0;
    if (pattern.test(sample)) {
      violations.push(name);
    }
  }

  if (options.failOnViolation !== false && violations.length > 0) {
    throw new Error(`Secret scan failed: ${violations.join(', ')}`);
  }

  return violations;
}

export function scanFileForSecrets(filePath, options = {}) {
  const stat = fs.statSync(filePath);
  if (stat.size > (options.maxBytes ?? DUMP_SECRET_SCAN_MAX_BYTES)) {
    throw new Error(
      `Refusing secret scan on oversized dump (${stat.size} bytes > ${options.maxBytes ?? DUMP_SECRET_SCAN_MAX_BYTES}).`,
    );
  }

  const content = fs.readFileSync(filePath, 'utf8');
  return scanTextForSecrets(content, options);
}
