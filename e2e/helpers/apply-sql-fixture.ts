import { execSync } from 'node:child_process';
import path from 'node:path';

function resolveRepoRoot(): string {
  return path.resolve(__dirname, '../..');
}

function resolveDbContainer(repoRoot: string): string {
  return execSync('node scripts/resolve-supabase-db-container.mjs', {
    cwd: repoRoot,
    encoding: 'utf8',
  }).trim();
}

export function applySqlFixture(fixtureFileName: string): void {
  const repoRoot = resolveRepoRoot();
  const fixturePath = path.join(repoRoot, 'scripts', fixtureFileName);

  const apiUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  if (apiUrl) {
    const lower = apiUrl.toLowerCase();
    if (/supabase\.co|supabase\.in|\.amazonaws\.com/.test(lower)) {
      throw new Error(`Refusing SQL fixture against hosted Supabase URL: ${apiUrl}`);
    }
    if (!/127\.0\.0\.1|localhost/.test(lower)) {
      throw new Error(`Refusing SQL fixture against non-local Supabase URL: ${apiUrl}`);
    }
  }

  const container = resolveDbContainer(repoRoot);
  const containerFixturePath = `/tmp/${fixtureFileName}`;

  execSync(`docker cp "${fixturePath}" ${container}:${containerFixturePath}`, {
    cwd: repoRoot,
    stdio: 'inherit',
  });
  execSync(
    `docker exec -i ${container} psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f ${containerFixturePath}`,
    { cwd: repoRoot, stdio: 'inherit' },
  );
}

export function resetLocalDatabase(): void {
  const repoRoot = resolveRepoRoot();
  execSync('npx supabase db reset', { cwd: repoRoot, stdio: 'inherit' });
}

export function seedOwnerTeachersEmptyFixture(): void {
  applySqlFixture('fixture-owner-teachers-empty.sql');
}

export function seedOwnerOnlyAlphaFixture(): void {
  const repoRoot = resolveRepoRoot();
  resetLocalDatabase();
  execSync('powershell -ExecutionPolicy Bypass -File scripts/seed-owner-only-alpha.ps1', {
    cwd: repoRoot,
    stdio: 'inherit',
  });
}

export function seedOwnerAlphaFixture(): void {
  const repoRoot = resolveRepoRoot();
  execSync('powershell -ExecutionPolicy Bypass -File scripts/seed-owner-alpha.ps1', {
    cwd: repoRoot,
    stdio: 'inherit',
  });
}
