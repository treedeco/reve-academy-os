import { execSync } from 'node:child_process';
import path from 'node:path';

export function applyLocalSqlFixture(fixtureFileName: string): void {
  const repoRoot = path.resolve(process.cwd());
  const fixturePath = path.join(repoRoot, 'scripts', fixtureFileName);
  const apiUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  if (apiUrl && !/127\.0\.0\.1|localhost/.test(apiUrl)) {
    throw new Error(`Refusing SQL fixture against non-local Supabase URL: ${apiUrl}`);
  }

  const container = execSync('node scripts/resolve-supabase-db-container.mjs', {
    cwd: repoRoot,
    encoding: 'utf8',
  }).trim();

  execSync(`docker cp "${fixturePath}" ${container}:/tmp/${fixtureFileName}`, {
    cwd: repoRoot,
    stdio: 'inherit',
  });
  execSync(
    `docker exec -i ${container} psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/${fixtureFileName}`,
    { cwd: repoRoot, stdio: 'inherit' },
  );
}
