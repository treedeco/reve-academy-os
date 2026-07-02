import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');

function getProjectId() {
  const configPath = path.join(repoRoot, 'supabase', 'config.toml');
  const config = fs.readFileSync(configPath, 'utf8');
  const match = config.match(/^\s*project_id\s*=\s*"([^"]+)"/m);
  if (!match) {
    throw new Error('Could not resolve project_id from supabase/config.toml');
  }
  return match[1];
}

function listRunningDbContainers() {
  const output = execSync('docker ps --format {{.Names}}', { encoding: 'utf8' });
  return output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith('supabase_db_'));
}

function resolveContainer() {
  if (process.env.SUPABASE_DB_CONTAINER?.trim()) {
    const candidate = process.env.SUPABASE_DB_CONTAINER.trim();
    const running = listRunningDbContainers();
    if (!running.includes(candidate)) {
      throw new Error(
        `SUPABASE_DB_CONTAINER is set to '${candidate}' but that container is not running.`,
      );
    }
    return candidate;
  }

  const expected = `supabase_db_${getProjectId()}`;
  const running = listRunningDbContainers();

  if (running.length === 0) {
    throw new Error('No running supabase_db_* container found. Run: npx supabase start');
  }

  if (running.includes(expected)) {
    return expected;
  }

  if (running.length === 1) {
    console.warn(`Expected '${expected}' not found; using '${running[0]}'.`);
    return running[0];
  }

  throw new Error(
    `Multiple supabase_db_* containers are running (${running.join(', ')}). Set SUPABASE_DB_CONTAINER.`,
  );
}

process.stdout.write(resolveContainer());
