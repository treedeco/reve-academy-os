import { execSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const fixtureFileName = 'cleanup-integration-test-students.sql';
const fixturePath = path.join(repoRoot, 'scripts', fixtureFileName);

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
