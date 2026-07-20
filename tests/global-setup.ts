import { execSync } from 'node:child_process';
import path from 'node:path';

export default async function globalSetup() {
  const repoRoot = path.resolve(__dirname, '..');

  try {
    execSync('node scripts/resolve-supabase-db-container.mjs', {
      cwd: repoRoot,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch {
    console.warn('Skipping Owner Alpha demo seed: local Supabase container not available.');
    return;
  }

  try {
    execSync('node scripts/apply-integration-test-cleanup.mjs', {
      cwd: repoRoot,
      stdio: 'inherit',
    });
    execSync('powershell -ExecutionPolicy Bypass -File scripts/seed-owner-alpha.ps1', {
      cwd: repoRoot,
      stdio: 'inherit',
    });
  } catch (error) {
    console.warn('Owner Alpha demo seed failed; integration tests may skip or fail.');
    console.warn(error);
  }
}
