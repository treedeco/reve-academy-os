import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

function loadEnvLocal(): void {
  const envLocalPath = path.resolve(process.cwd(), '.env.local');
  if (!existsSync(envLocalPath)) {
    return;
  }

  for (const line of readFileSync(envLocalPath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }
    const separator = trimmed.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    const name = trimmed.slice(0, separator).trim();
    const value = trimmed.slice(separator + 1).trim().replace(/^["']|["']$/g, '');
    if (name && process.env[name] === undefined) {
      process.env[name] = value;
    }
  }
}

export function getOwnerPasswordFromEnv(): string {
  loadEnvLocal();
  const password = process.env.OWNER_PASSWORD ?? process.env.E2E_OWNER_PASSWORD;
  if (!password) {
    throw new Error(
      'Owner password is not configured. Set OWNER_PASSWORD in .env.local (gitignored).',
    );
  }
  return password;
}
