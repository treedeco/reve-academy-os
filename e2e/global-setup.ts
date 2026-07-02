import { execSync } from 'node:child_process';
import path from 'node:path';

export default async function globalSetup() {
  const repoRoot = path.resolve(__dirname, '..');
  const seedPath = path.join(repoRoot, 'scripts', 'seed-owner-alpha.sql');

  let container: string;
  try {
    container = execSync('node scripts/resolve-supabase-db-container.mjs', {
      cwd: repoRoot,
      encoding: 'utf8',
    }).trim();
  } catch (error) {
    throw new Error(
      `Local Supabase DB container not available. Run 'npx supabase start' before Playwright tests. ${error}`,
    );
  }

  const apiUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  if (apiUrl) {
    const lower = apiUrl.toLowerCase();
    if (/supabase\.co|supabase\.in|\.amazonaws\.com/.test(lower)) {
      throw new Error(`Refusing Playwright setup against hosted Supabase URL: ${apiUrl}`);
    }
    if (!/127\.0\.0\.1|localhost/.test(lower)) {
      throw new Error(`Refusing Playwright setup against non-local Supabase URL: ${apiUrl}`);
    }
  }

  execSync(`docker cp "${seedPath}" ${container}:/tmp/seed-owner-alpha.sql`, {
    cwd: repoRoot,
    stdio: 'inherit',
  });
  execSync(
    `docker exec -i ${container} psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/seed-owner-alpha.sql`,
    { cwd: repoRoot, stdio: 'inherit' },
  );
}
