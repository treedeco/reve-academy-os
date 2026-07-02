import { execSync } from 'node:child_process';
import path from 'node:path';

export default async function globalSetup() {
  const repoRoot = path.resolve(__dirname, '..');
  const seedPath = path.join(repoRoot, 'scripts', 'seed-owner-alpha.sql');
  const container = process.env.SUPABASE_DB_CONTAINER ?? 'supabase_db_reve-academy-os';

  execSync(`docker cp "${seedPath}" ${container}:/tmp/seed-owner-alpha.sql`, {
    cwd: repoRoot,
    stdio: 'inherit',
  });
  execSync(
    `docker exec -i ${container} psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/seed-owner-alpha.sql`,
    { cwd: repoRoot, stdio: 'inherit' },
  );
}
